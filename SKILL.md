# Context Bootstrapper

Rapid context recovery for AI agent sessions. Generates a concise summary of recent activity, pending work, and current state to help agents get up to speed quickly.

## The Problem

Every new session requires reading 5-10 files to understand:
- What happened recently (commits, completed tasks)
- What's pending (queue, blockers)
- Current state (memory, identity)

This takes 2-5 minutes and wastes context window. A bootstrapper can summarize everything in 30 seconds.

## Commands

```bash
# Quick bootstrap (default - 20 line summary)
./bootstrap.sh

# Extended bootstrap (more detail)
./bootstrap.sh --extended

# Specific timeframe
./bootstrap.sh --hours 24

# JSON output for scripting
./bootstrap.sh --json

# Include specific sections only
./bootstrap.sh --sections "commits,queue,blockers"

# Override workspace (default: ~/bob-bootstrap)
WORKSPACE=/path/to/workspace ./bootstrap.sh
```

## Output Sections

1. **Identity** - Who am I? (name, human, workspace)
2. **Time Context** - Current time, timezone, session age
3. **Recent Activity** - Last N commits with messages
4. **Queue Status** - Pending/blocked/completed counts
5. **Active Blockers** - What's waiting on external input
6. **Memory Highlights** - Recent entries from daily logs
7. **Urgent Items** - High priority pending tasks
8. **Quick Stats** - Commits/day, completion rate, velocity

## Example Output

```
╔══════════════════════════════════════════════════════════════╗
║                    CONTEXT BOOTSTRAP                          ║
╠══════════════════════════════════════════════════════════════╣
║ Identity: Bob | Human: Serene | Workspace: ~/clawd           ║
║ Time: 2026-01-31 08:15 PST | Session: fresh                  ║
╠══════════════════════════════════════════════════════════════╣
║ RECENT ACTIVITY (last 6h)                                    ║
║ • 12 commits (2.0/hr) - mostly Queue: and Learning:          ║
║ • Last: "Queue: completed task #62 - deep research pipeline" ║
╠══════════════════════════════════════════════════════════════╣
║ QUEUE STATUS                                                 ║
║ • Pending: 2 | Blocked: 1 | Completed: 48                    ║
║ • Next: #64 "Build novel tool" (high priority)               ║
╠══════════════════════════════════════════════════════════════╣
║ BLOCKERS                                                     ║
║ • #61: ClawdHub publish (needs browser login)                ║
╠══════════════════════════════════════════════════════════════╣
║ VELOCITY: 0.59 tasks/hr | 75% completion rate                ║
╚══════════════════════════════════════════════════════════════╝
```

## Integration

### Heartbeat Integration
Add to HEARTBEAT.md:
```
## Session Start Check
If this is a new session (no prior context), run:
./skills/context-bootstrapper/bootstrap.sh
```

### Cron Integration
Schedule daily bootstrap summary:
```yaml
schedule:
  kind: every
  everyMs: 86400000  # 24h
payload:
  kind: systemEvent
  text: "Run context bootstrap for daily summary"
```

## Why This Matters

- **Time savings**: 2-5 min → 30 sec context recovery
- **Consistency**: Same format every session
- **Completeness**: Won't miss important pending work
- **Velocity**: Start working faster, less ramp-up

## Files

- `SKILL.md` - This documentation
- `bootstrap.sh` - Main script (executable)
