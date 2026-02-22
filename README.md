# Claude Code Process Cleanup

Hooks and skill for cleaning up orphaned Claude Code processes that persist after sessions end or crash.

## Problem

After Claude Code sessions end (or crash/Ctrl+C), child processes get orphaned:
- `bun worker-service.cjs --daemon` gets adopted by launchd (PPID=1)
- Under it: claude subagent processes (~200MB each) + node MCP servers
- These accumulate across sessions and can consume 15-24GB+ of RAM

Ref: https://github.com/anthropics/claude-code/issues/18859

## How it works

The cleanup script identifies orphaned process trees by checking for **PPID=1** (adopted by launchd = truly orphaned). This is safe for parallel sessions — active sessions' workers have a real parent PID and are never touched.

### Automatic cleanup
- **SessionEnd hook**: runs when sessions exit normally (`/exit`, Ctrl+C)
- **SessionStart hook**: catches stragglers from crashes/hard kills

### Manual cleanup
- `/cleanup` skill: surveys processes, shows memory usage, asks confirmation, then cleans up

## Install

```bash
./install.sh
```

Or manually copy files:

```bash
cp hooks/cleanup-processes.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/cleanup-processes.sh
cp -r skills/cleanup ~/.claude/skills/
```

Then add hooks to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/cleanup-processes.sh --startup",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/cleanup-processes.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```
