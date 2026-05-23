#!/bin/bash
# LetMeKnow-cc2feishu installer
# Copies the hook script and registers it in Claude Code settings

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/letmeknow"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
HOOK_SCRIPT="$CLAUDE_DIR/notify-feishu.sh"

echo "=== LetMeKnow-cc2feishu Installer ==="
echo ""

# ── Check dependencies ───────────────────────────────────────
check_dep() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: '$1' not found. $2"
        exit 1
    fi
}

check_dep jq "Install: https://jqlang.github.io/jq/download/"
check_dep curl "Install via your package manager."
check_dep lark-cli "Install: npm install -g @aspect-build/lark-cli"

# ── Config ───────────────────────────────────────────────────
mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_DIR/config.json" ]; then
    cp "$SCRIPT_DIR/config.example.json" "$CONFIG_DIR/config.json"
    echo "Created config at: $CONFIG_DIR/config.json"
    echo ">>> Please edit it with your Feishu open_id and ActivityWatch settings <<<"
    echo ""
else
    echo "Config already exists: $CONFIG_DIR/config.json"
fi

# ── Install hook script ─────────────────────────────────────
mkdir -p "$CLAUDE_DIR"
cp "$SCRIPT_DIR/notify-feishu.sh" "$HOOK_SCRIPT"
chmod +x "$HOOK_SCRIPT"
echo "Installed hook script: $HOOK_SCRIPT"

# ── Register hooks in CC settings ────────────────────────────
HOOK_CMD="bash ~/.claude/notify-feishu.sh"
HOOK_ENTRY='{"type":"command","command":"CMD EVENT","async":true}'

if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

EVENTS=("UserPromptSubmit:user_prompt" "Stop:stop" "Notification:notification" "PermissionRequest:permission")

TMP_SETTINGS=$(mktemp)
cp "$SETTINGS_FILE" "$TMP_SETTINGS"

for pair in "${EVENTS[@]}"; do
    CC_EVENT="${pair%%:*}"
    SCRIPT_EVENT="${pair##*:}"
    FULL_CMD="${HOOK_CMD} ${SCRIPT_EVENT}"

    ALREADY=$(jq -r ".hooks.${CC_EVENT} // [] | .[].hooks // [] | .[].command // \"\"" "$TMP_SETTINGS" 2>/dev/null | grep -c "$HOOK_CMD" || true)

    if [ "$ALREADY" -gt 0 ]; then
        echo "Hook already registered: $CC_EVENT"
        continue
    fi

    ENTRY=$(echo "$HOOK_ENTRY" | sed "s|CMD EVENT|${FULL_CMD}|")
    jq ".hooks.${CC_EVENT} = (.hooks.${CC_EVENT} // []) + [{\"hooks\": [${ENTRY}]}]" "$TMP_SETTINGS" > "${TMP_SETTINGS}.new"
    mv "${TMP_SETTINGS}.new" "$TMP_SETTINGS"
    echo "Registered hook: $CC_EVENT -> $SCRIPT_EVENT"
done

cp "$TMP_SETTINGS" "$SETTINGS_FILE"
rm -f "$TMP_SETTINGS"

echo ""
echo "=== Done! ==="
echo ""
echo "Next steps:"
echo "  1. Edit $CONFIG_DIR/config.json with your settings"
echo "  2. Make sure lark-cli is configured (lark-cli auth login)"
echo "  3. Restart Claude Code for hooks to take effect"
