#!/usr/bin/env bash
# Claude Code orphaned process cleanup
# 1. Kills orphaned bun worker daemons and their entire process trees
#    (subagents, MCP servers) that persist after sessions end or crash.
# 2. Removes old Claude Code binary versions, keeping only the current one.
#
# Safe for parallel sessions: only targets process trees whose root
# daemon has PPID=1 (adopted by launchd = orphaned). Active sessions'
# workers have a real parent and are never touched.
#
# Usage:
#   cleanup-processes.sh            # Normal cleanup (SessionEnd)
#   cleanup-processes.sh --startup  # Startup cleanup (SessionStart)
#   cleanup-processes.sh --stop     # Per-reply cleanup (Stop hook)

set -euo pipefail

LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/cleanup.log"
mkdir -p "$LOG_DIR"

MODE=""
case "${1:-}" in
  --startup) MODE="startup" ;;
  --stop)    MODE="stop" ;;
  *)         MODE="session-end" ;;
esac

MY_PID=$$

log() {
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] $*" >> "$LOG_FILE"
}

# Get all ancestor PIDs of current process
get_ancestors() {
  local pid=$1
  local ancestors=""
  while [[ $pid -gt 1 ]]; do
    ancestors="$ancestors $pid"
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ') || break
    [[ -z "$pid" ]] && break
  done
  echo "$ancestors"
}

MY_ANCESTORS=$(get_ancestors $MY_PID)

is_my_ancestor() {
  local check_pid=$1
  for a in $MY_ANCESTORS; do
    [[ "$check_pid" == "$a" ]] && return 0
  done
  return 1
}

# Recursively collect all descendant PIDs of a given process
get_descendants() {
  local parent=$1
  local children
  children=$(ps -eo pid,ppid 2>/dev/null | awk -v p="$parent" '$2 == p {print $1}')
  for child in $children; do
    echo "$child"
    get_descendants "$child"
  done
}

kill_tree() {
  local root_pid=$1
  local desc=$2

  # Safety: never kill our own ancestor tree
  if is_my_ancestor "$root_pid"; then
    log "SKIP $desc (pid $root_pid) - ancestor of current process"
    return 1
  fi

  # Collect entire tree: root + all descendants
  local all_pids="$root_pid"
  local descendants
  descendants=$(get_descendants "$root_pid")
  [[ -n "$descendants" ]] && all_pids="$all_pids $descendants"

  local count=0
  for pid in $all_pids; do
    count=$((count + 1))
  done

  log "KILLING $desc (root pid $root_pid, $count process(es) in tree)"

  # SIGTERM the root process group first (catches all children)
  kill -TERM "-$root_pid" 2>/dev/null || true
  # Also SIGTERM individual descendants in case they escaped the group
  for pid in $descendants; do
    kill -TERM "$pid" 2>/dev/null || true
  done

  # Brief wait then SIGKILL any survivors
  sleep 1
  for pid in $all_pids; do
    if kill -0 "$pid" 2>/dev/null; then
      log "SIGKILL pid $pid - did not respond to SIGTERM"
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done

  return 0
}

KILLED_COUNT=0

# Strategy: find orphaned bun worker-service daemons (PPID=1) and kill
# their entire process tree. This is safe for parallel sessions because
# active sessions' workers have a real PPID (not 1).
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pid=$(echo "$line" | awk '{print $1}')
  ppid=$(echo "$line" | awk '{print $2}')
  if [[ "$ppid" == "1" ]]; then
    if kill_tree "$pid" "orphaned bun worker-service daemon"; then
      ((KILLED_COUNT++)) || true
    fi
  fi
done < <(ps -eo pid,ppid,command 2>/dev/null | grep 'worker-service\.cjs.*--daemon' | grep -v grep || true)

# Also catch any standalone orphaned claude subagents (PPID=1, no parent worker)
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pid=$(echo "$line" | awk '{print $1}')
  ppid=$(echo "$line" | awk '{print $2}')
  if [[ "$ppid" == "1" ]]; then
    if kill_tree "$pid" "orphaned standalone claude subagent"; then
      ((KILLED_COUNT++)) || true
    fi
  fi
done < <(ps -eo pid,ppid,command 2>/dev/null | grep 'claude.*--output-format.*stream-json' | grep -v grep || true)

# Also catch any standalone orphaned MCP servers (PPID=1, no parent worker)
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pid=$(echo "$line" | awk '{print $1}')
  ppid=$(echo "$line" | awk '{print $2}')
  if [[ "$ppid" == "1" ]]; then
    if kill_tree "$pid" "orphaned standalone MCP server"; then
      ((KILLED_COUNT++)) || true
    fi
  fi
done < <(ps -eo pid,ppid,command 2>/dev/null | grep 'node.*mcp-server' | grep -v grep || true)

MODE_LABEL="$MODE"
if [[ $KILLED_COUNT -gt 0 ]]; then
  log "Cleanup complete: killed $KILLED_COUNT orphaned process tree(s) [mode: $MODE_LABEL]"
else
  log "Cleanup: no orphaned processes found [mode: $MODE_LABEL]"
fi

# --- Old version cleanup ---
# Remove old Claude Code binaries, keeping only the currently running version.
VERSIONS_DIR="$HOME/.local/share/claude/versions"
if [[ -d "$VERSIONS_DIR" ]]; then
  CURRENT_VERSION=$(claude --version 2>/dev/null | awk '{print $1}')
  if [[ -n "$CURRENT_VERSION" ]]; then
    REMOVED_COUNT=0
    FREED_BYTES=0
    for version_file in "$VERSIONS_DIR"/*; do
      [[ -e "$version_file" ]] || continue
      version_name=$(basename "$version_file")
      if [[ "$version_name" != "$CURRENT_VERSION" ]]; then
        file_size=$(stat -f%z "$version_file" 2>/dev/null || echo 0)
        FREED_BYTES=$((FREED_BYTES + file_size))
        rm -f "$version_file"
        log "REMOVED old version $version_name ($(( file_size / 1048576 ))MB)"
        ((REMOVED_COUNT++)) || true
      fi
    done
    if [[ $REMOVED_COUNT -gt 0 ]]; then
      log "Version cleanup: removed $REMOVED_COUNT old version(s), freed $(( FREED_BYTES / 1048576 ))MB [mode: $MODE_LABEL]"
    fi
  fi
fi

exit 0
