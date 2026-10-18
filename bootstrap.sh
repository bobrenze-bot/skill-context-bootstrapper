#!/bin/bash
# Context Bootstrapper - Rapid context recovery for AI agent sessions
# Usage: ./bootstrap.sh [--extended] [--hours N] [--json] [--sections "list"]

set -e

# Configuration
WORKSPACE="${WORKSPACE:-$HOME/bob-bootstrap}"
QUEUE_FILE="$WORKSPACE/autonomous-queue.yaml"
MEMORY_DIR="$WORKSPACE/memory"
IDENTITY_FILE="$WORKSPACE/IDENTITY.md"
USER_FILE="$WORKSPACE/USER.md"
BLOCKERS_FILE="$WORKSPACE/BLOCKERS.md"
LEARNING_LOG="$WORKSPACE/learning-log.md"

# Defaults
HOURS=12
EXTENDED=false
JSON_OUTPUT=false
SECTIONS="identity,time,commits,queue,blockers,memory,urgent,stats"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --extended|-e)
            EXTENDED=true
            HOURS=24
            shift
            ;;
        --hours|-h)
            HOURS="$2"
            shift 2
            ;;
        --json|-j)
            JSON_OUTPUT=true
            shift
            ;;
        --sections|-s)
            SECTIONS="$2"
            shift 2
            ;;
        --help)
            echo "Context Bootstrapper - Rapid context recovery"
            echo ""
            echo "Usage: ./bootstrap.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --extended, -e    Extended output (24h, more detail)"
            echo "  --hours N, -h N   Timeframe in hours (default: 12)"
            echo "  --json, -j        Output as JSON"
            echo "  --sections, -s    Comma-separated sections to include"
            echo "                    (identity,time,commits,queue,blockers,memory,urgent,stats)"
            echo "  --help            Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Helper functions
get_identity() {
    local name="Bob"
    local human="Serene"
    
    if [[ -f "$IDENTITY_FILE" ]]; then
        local name_line=$(grep -i "^- \*\*Name:\*\*" "$IDENTITY_FILE" 2>/dev/null | head -1)
        if [[ -n "$name_line" ]]; then
            name=$(echo "$name_line" | sed 's/.*\*\*Name:\*\* *//' | sed 's/ *(.*//')
        fi
    fi
    
    if [[ -f "$USER_FILE" ]]; then
        local human_line=$(grep -i "^- \*\*Name:\*\*" "$USER_FILE" 2>/dev/null | head -1)
        if [[ -n "$human_line" ]]; then
            human=$(echo "$human_line" | sed 's/.*\*\*Name:\*\* *//' | sed 's/ *(.*//')
        fi
    fi
    
    echo "$name|$human|$WORKSPACE"
}

get_recent_commits() {
    local since_hours=$1
    cd "$WORKSPACE"
    
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        echo "0|No git repo"
        return
    fi
    
    local since_date=$(date -v-${since_hours}H "+%Y-%m-%d %H:%M" 2>/dev/null || date -d "$since_hours hours ago" "+%Y-%m-%d %H:%M")
    local count=$(git log --since="$since_date" --oneline 2>/dev/null | wc -l | tr -d ' ')
    local last_msg=$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "No commits")
    local rate=$(echo "scale=2; $count / $since_hours" | bc 2>/dev/null || echo "0")
    
    echo "$count|$rate|$last_msg"
}

# grep -c already prints 0 for no matches, even though it exits with status 1.
# Do not append another zero: callers require a single numeric field.
count_queue_status() {
    local count
    count=$(grep -c "status: $1" "$QUEUE_FILE" 2>/dev/null || true)
    printf '%s\n' "${count:-0}"
}

get_queue_status() {
    if [[ ! -f "$QUEUE_FILE" ]]; then
        echo "0|0|0|No queue"
        return
    fi
    
    local pending=$(count_queue_status pending)
    local blocked=$(count_queue_status blocked)
    local completed=$(count_queue_status completed)
    
    # Get next pending task
    local next_task=""
    if [[ $pending -gt 0 ]]; then
        # Find first pending high priority, then medium, then low
        for priority in high medium low; do
            next_task=$(awk -v prio="$priority" '
                /^  - id:/ { id = $3 }
                /status: pending/ { pending = 1 }
                /priority:/ && pending && $2 == prio { 
                    getline; 
                    if (/task:/) {
                        gsub(/.*task: *"?/, ""); 
                        gsub(/".*/, ""); 
                        print "#" id ": " $0
                        exit
                    }
                }
                /^  - id:/ { pending = 0 }
            ' "$QUEUE_FILE" 2>/dev/null)
            
            if [[ -n "$next_task" ]]; then
                break
            fi
        done
        
        # Fallback: just get first pending
        if [[ -z "$next_task" ]]; then
            next_task=$(grep -B5 "status: pending" "$QUEUE_FILE" | grep "task:" | head -1 | sed 's/.*task: *"*//' | sed 's/"*$//' | head -c 50)
        fi
    fi
    
    echo "$pending|$blocked|$completed|$next_task"
}

get_blockers() {
    local blockers=""
    
    # From queue file
    if [[ -f "$QUEUE_FILE" ]]; then
        blockers=$(awk '
            /^  - id:/ { id = $3 }
            /status: blocked/ { blocked = 1 }
            /blocker:/ && blocked { 
                gsub(/.*blocker: *"?/, ""); 
                gsub(/".*/, ""); 
                print "#" id ": " $0
            }
            /^  - id:/ { blocked = 0 }
        ' "$QUEUE_FILE" 2>/dev/null | head -5)
    fi
    
    # From BLOCKERS.md if exists
    if [[ -f "$BLOCKERS_FILE" ]] && [[ -z "$blockers" ]]; then
        blockers=$(grep -E "^- " "$BLOCKERS_FILE" 2>/dev/null | head -5)
    fi
    
    echo "${blockers:-None}"
}

get_memory_highlights() {
    local today=$(date "+%Y-%m-%d")
    local yesterday=$(date -v-1d "+%Y-%m-%d" 2>/dev/null || date -d "yesterday" "+%Y-%m-%d")
    
    local highlights=""
    
    # Check today's memory file
    if [[ -f "$MEMORY_DIR/$today.md" ]]; then
        highlights=$(tail -10 "$MEMORY_DIR/$today.md" 2>/dev/null | grep -E "^[-•*]" | tail -3)
    fi
    
    # Fallback to yesterday
    if [[ -z "$highlights" ]] && [[ -f "$MEMORY_DIR/$yesterday.md" ]]; then
        highlights=$(tail -10 "$MEMORY_DIR/$yesterday.md" 2>/dev/null | grep -E "^[-•*]" | tail -3)
    fi
    
    # Fallback to learning log
    if [[ -z "$highlights" ]] && [[ -f "$LEARNING_LOG" ]]; then
        highlights=$(tail -20 "$LEARNING_LOG" 2>/dev/null | grep -E "^[-•*]" | tail -3)
    fi
    
    echo "${highlights:-No recent memory entries}"
}

get_stats() {
    cd "$WORKSPACE"
    
    # Calculate velocity from queue
    local total_tasks=$(count_queue_status completed)
    local pending=$(count_queue_status pending)
    
    # Commits per day (last 7 days)
    local week_commits=$(git log --since="7 days ago" --oneline 2>/dev/null | wc -l | tr -d ' ')
    local commits_per_day=$(echo "scale=1; $week_commits / 7" | bc 2>/dev/null || echo "0")
    
    # Completion rate
    local total=$((total_tasks + pending))
    local rate=0
    if [[ $total -gt 0 ]]; then
        rate=$(echo "scale=0; $total_tasks * 100 / $total" | bc 2>/dev/null || echo "0")
    fi
    
    echo "$commits_per_day|$rate|$total_tasks"
}

# JSON output
output_json() {
    local identity=$(get_identity)
    local commits=$(get_recent_commits $HOURS)
    local queue=$(get_queue_status)
    local blockers=$(get_blockers | tr '\n' '|' | sed 's/|$//')
    local stats=$(get_stats)
    
    IFS='|' read -r name human workspace <<< "$identity"
    IFS='|' read -r commit_count commit_rate last_commit <<< "$commits"
    IFS='|' read -r pending blocked completed next_task <<< "$queue"
    IFS='|' read -r commits_day completion_rate total_completed <<< "$stats"
    
    cat << EOF
{
  "timestamp": "$(date -Iseconds)",
  "identity": {
    "name": "$name",
    "human": "$human",
    "workspace": "$workspace"
  },
  "activity": {
    "hours": $HOURS,
    "commits": $commit_count,
    "commits_per_hour": $commit_rate,
    "last_commit": "$last_commit"
  },
  "queue": {
    "pending": $pending,
    "blocked": $blocked,
    "completed": $completed,
    "next_task": "$next_task"
  },
  "stats": {
    "commits_per_day": $commits_day,
    "completion_rate": $completion_rate,
    "total_completed": $total_completed
  }
}
EOF
}

# Terminal output
output_terminal() {
    local identity=$(get_identity)
    local commits=$(get_recent_commits $HOURS)
    local queue=$(get_queue_status)
    local blockers=$(get_blockers)
    local memory=$(get_memory_highlights)
    local stats=$(get_stats)
    
    IFS='|' read -r name human workspace <<< "$identity"
    IFS='|' read -r commit_count commit_rate last_commit <<< "$commits"
    IFS='|' read -r pending blocked completed next_task <<< "$queue"
    IFS='|' read -r commits_day completion_rate total_completed <<< "$stats"
    
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║${NC}                        ${CYAN}CONTEXT BOOTSTRAP${NC}                             ${BOLD}║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    
    # Identity section
    if [[ "$SECTIONS" == *"identity"* ]]; then
        printf "${BOLD}║${NC} ${BLUE}Identity:${NC} %-10s ${BLUE}Human:${NC} %-12s ${BLUE}Workspace:${NC} %-15s ${BOLD}║${NC}\n" "$name" "$human" "$(basename $workspace)"
    fi
    
    # Time section
    if [[ "$SECTIONS" == *"time"* ]]; then
        printf "${BOLD}║${NC} ${BLUE}Time:${NC} %-20s ${BLUE}Timeframe:${NC} %dh                         ${BOLD}║${NC}\n" "$(date '+%Y-%m-%d %H:%M %Z')" "$HOURS"
    fi
    
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    
    # Commits section
    if [[ "$SECTIONS" == *"commits"* ]]; then
        echo -e "${BOLD}║${NC} ${YELLOW}RECENT ACTIVITY${NC} (last ${HOURS}h)                                          ${BOLD}║${NC}"
        printf "${BOLD}║${NC}   • %d commits (%.1f/hr)                                            ${BOLD}║${NC}\n" "$commit_count" "$commit_rate"
        printf "${BOLD}║${NC}   • Last: %-55s ${BOLD}║${NC}\n" "${last_commit:0:55}"
    fi
    
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    
    # Queue section
    if [[ "$SECTIONS" == *"queue"* ]]; then
        echo -e "${BOLD}║${NC} ${YELLOW}QUEUE STATUS${NC}                                                        ${BOLD}║${NC}"
        printf "${BOLD}║${NC}   • ${GREEN}Pending:${NC} %-3s  ${RED}Blocked:${NC} %-3s  ${BLUE}Completed:${NC} %-4s                   ${BOLD}║${NC}\n" "$pending" "$blocked" "$completed"
        if [[ -n "$next_task" ]]; then
            printf "${BOLD}║${NC}   • ${CYAN}Next:${NC} %-57s ${BOLD}║${NC}\n" "${next_task:0:57}"
        fi
    fi
    
    # Blockers section
    if [[ "$SECTIONS" == *"blockers"* ]] && [[ "$blocked" -gt 0 ]]; then
        echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${BOLD}║${NC} ${RED}BLOCKERS${NC}                                                            ${BOLD}║${NC}"
        echo "$blockers" | while read -r line; do
            if [[ -n "$line" ]]; then
                printf "${BOLD}║${NC}   • %-61s ${BOLD}║${NC}\n" "${line:0:61}"
            fi
        done
    fi
    
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    
    # Stats section
    if [[ "$SECTIONS" == *"stats"* ]]; then
        printf "${BOLD}║${NC} ${CYAN}VELOCITY:${NC} %.1f commits/day  ${CYAN}Completion:${NC} %d%%  ${CYAN}Total:${NC} %d tasks       ${BOLD}║${NC}\n" "$commits_day" "$completion_rate" "$total_completed"
    fi
    
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    
    # Extended output
    if [[ "$EXTENDED" == true ]]; then
        echo ""
        echo -e "${BOLD}=== MEMORY HIGHLIGHTS ===${NC}"
        echo "$memory"
        echo ""
        echo -e "${BOLD}=== RECENT COMMITS ===${NC}"
        cd "$WORKSPACE"
        git log --since="${HOURS} hours ago" --oneline 2>/dev/null | head -10
    fi
}

# Main
if [[ "$JSON_OUTPUT" == true ]]; then
    output_json
else
    output_terminal
fi
