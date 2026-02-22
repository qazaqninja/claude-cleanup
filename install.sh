#!/usr/bin/env bash
# Install Claude Code process cleanup hooks and skill
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing Claude Code process cleanup..."

# Copy hook
mkdir -p ~/.claude/hooks ~/.claude/logs
cp "$SCRIPT_DIR/hooks/cleanup-processes.sh" ~/.claude/hooks/
chmod +x ~/.claude/hooks/cleanup-processes.sh
echo "  Installed cleanup-processes.sh hook"

# Copy skill
mkdir -p ~/.claude/skills/cleanup
cp "$SCRIPT_DIR/skills/cleanup/SKILL.md" ~/.claude/skills/cleanup/
echo "  Installed /cleanup skill"

echo ""
echo "Done! Add the following hooks to ~/.claude/settings.json manually:"
echo ""
echo '  "hooks": {'
echo '    "SessionStart": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/cleanup-processes.sh --startup", "timeout": 10}]}],'
echo '    "SessionEnd": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/cleanup-processes.sh", "timeout": 10}]}]'
echo '  }'
