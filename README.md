# Context Bootstrapper

Rapid context recovery for AI agent sessions. Generates a concise summary of recent activity, pending work, and current state to help agents get up to speed quickly.

## Installation

```bash
clawhub install context-bootstrapper
```

## Usage

```bash
# Quick bootstrap (default - 20 line summary)
context-bootstrapper

# Extended bootstrap (more detail)
context-bootstrapper --extended

# JSON output for scripting
context-bootstrapper --json
```

## Why This Matters

- **Time savings**: 2-5 min → 30 sec context recovery
- **Consistency**: Same format every session
- **Completeness**: Won't miss important pending work
- **Velocity**: Start working faster, less ramp-up

## Tests

Run the regression suite with Bash, Git, and Python 3:

```bash
python3 -m unittest discover -s tests -v
bash -n bootstrap.sh
```

The tests create temporary synthetic workspaces and do not read your real workspace.

## License

MIT
