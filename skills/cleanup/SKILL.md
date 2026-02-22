---
name: cleanup
description: Kill orphaned Claude Code processes and report memory usage. Use when the system feels slow or after crashes.
user_invocable: true
---

# Process Cleanup

Kill orphaned Claude Code processes (bun workers, subagents, MCP servers) that persist after sessions end or crash.

## Steps

1. **Survey** orphaned processes before cleanup:
   ```bash
   echo "=== Orphaned bun workers (PPID=1) ===" && \
   ps -eo pid,ppid,tty,rss,command | grep 'worker-service\.cjs.*--daemon' | grep -v grep | awk '$2 == 1' && \
   echo "=== Detached claude subagents ===" && \
   ps -eo pid,ppid,tty,rss,command | grep 'claude.*--output-format.*stream-json' | grep -v grep | awk '$3 == "??"' && \
   echo "=== Detached MCP servers ===" && \
   ps -eo pid,ppid,tty,rss,command | grep 'node.*mcp-server' | grep -v grep | awk '$3 == "??"' && \
   echo "=== Memory summary ===" && \
   ps -eo rss,command | grep -E '(worker-service|claude.*stream-json|node.*mcp-server)' | grep -v grep | awk '{sum += $1} END {printf "Total RSS: %.0f MB\n", sum/1024}'
   ```

2. **Show the user** what was found and how much memory it's using.

3. **Ask the user** for confirmation before killing anything.

4. **Run cleanup**:
   ```bash
   ~/.claude/hooks/cleanup-processes.sh
   ```

5. **Report results**:
   ```bash
   echo "=== Cleanup log ===" && tail -5 ~/.claude/logs/cleanup.log
   ```

6. **Show current memory** after cleanup:
   ```bash
   ps -eo rss,command | grep -E '(worker-service|claude.*stream-json|node.*mcp-server)' | grep -v grep | awk '{sum += $1} END {printf "Remaining RSS: %.0f MB\n", sum/1024}'
   ```
