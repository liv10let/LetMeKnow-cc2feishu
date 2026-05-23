#!/bin/bash
# LetMeKnow-cc2feishu — Smart Feishu notifications for Claude Code
# https://github.com/liv10let/LetMeKnow-cc2feishu

set -euo pipefail

EVENT="${1:-unknown}"
INPUT=$(cat 2>/dev/null || true)
PROJECT=$(basename "$(pwd)")

# ── Load config ──────────────────────────────────────────────
CONFIG_FILE="${LETMEKNOW_CONFIG:-$HOME/.config/letmeknow/config.json}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[LetMeKnow] Config not found: $CONFIG_FILE" >&2
    exit 1
fi

OPEN_ID=$(jq -r '.feishu.open_id' "$CONFIG_FILE")
AW_HOST=$(jq -r '.activitywatch.host // "localhost"' "$CONFIG_FILE")
AW_PORT=$(jq -r '.activitywatch.port // 5600' "$CONFIG_FILE")
AW_USER=$(jq -r '.activitywatch.user // ""' "$CONFIG_FILE")
AW_PASS=$(jq -r '.activitywatch.pass // ""' "$CONFIG_FILE")
AW_WINDOW_BUCKET=$(jq -r '.activitywatch.window_bucket' "$CONFIG_FILE")
AW_AFK_BUCKET=$(jq -r '.activitywatch.afk_bucket // ""' "$CONFIG_FILE")
TERMINAL_APP=$(jq -r '.terminal_app // "WindowsTerminal.exe"' "$CONFIG_FILE")

AW_BASE="http://${AW_HOST}:${AW_PORT}/api/0/buckets"
AW_URL="${AW_BASE}/${AW_WINDOW_BUCKET}/events?limit=1"
AW_AFK_URL="${AW_BASE}/${AW_AFK_BUCKET}/events?limit=1"

AW_AUTH_ARG=""
if [ -n "$AW_USER" ] && [ "$AW_USER" != "null" ]; then
    AW_AUTH_ARG="--user ${AW_USER}:${AW_PASS}"
fi

GLOBAL_TOPIC_FILE="/tmp/lmk_window_topic"
PENDING_MSG_FILE="/tmp/lmk_pending_msg"

# ── Session isolation ────────────────────────────────────────
get_session_key() {
    local tp sid
    tp=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null | sed 's|\\|/|g')
    if [ -n "$tp" ] && [ "$tp" != "null" ]; then
        basename "$tp" .jsonl
        return
    fi
    sid=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
    if [ -n "$sid" ] && [ "$sid" != "null" ]; then
        echo "$sid"
        return
    fi
    echo "global"
}

SESSION_KEY=$(get_session_key)
TOPIC_FILE="/tmp/lmk_topic_${SESSION_KEY}"
TASK_FILE="/tmp/lmk_task_${SESSION_KEY}"

# ── Helpers ──────────────────────────────────────────────────

# Strip spinner prefix from CC window title to get stable topic
extract_topic() {
    echo "$1" | sed 's/^[^ ]* //'
}

aw_get() {
    curl -s $AW_AUTH_ARG "$1" --connect-timeout 2 2>/dev/null
}

# Returns 0 if user is actively watching this CC window (suppress notification)
# Returns 1 if user is away (send notification)
user_is_watching() {
    local topic_file="${1:-$TOPIC_FILE}"
    local expected_topic app title current_topic response

    expected_topic=$(cat "$topic_file" 2>/dev/null)
    [ -z "$expected_topic" ] && return 1

    response=$(aw_get "$AW_URL")
    [ -z "$response" ] && return 1

    app=$(echo "$response" | jq -r '.[0].data.app // ""' 2>/dev/null)
    title=$(echo "$response" | jq -r '.[0].data.title // ""' 2>/dev/null)

    [ "$app" != "$TERMINAL_APP" ] && return 1

    current_topic=$(extract_topic "$title")
    [ "$current_topic" != "$expected_topic" ] && return 1

    # Window matches, but check AFK status
    if [ -n "$AW_AFK_BUCKET" ] && [ "$AW_AFK_BUCKET" != "null" ]; then
        local afk_response afk_status
        afk_response=$(aw_get "$AW_AFK_URL")
        afk_status=$(echo "$afk_response" | jq -r '.[0].data.status // ""' 2>/dev/null)
        [ "$afk_status" = "afk" ] && return 1
    fi

    return 0
}

send_feishu() {
    local msg="$1"
    lark-cli im +messages-send --as bot \
        --user-id "$OPEN_ID" \
        --text "$msg" > /dev/null 2>&1
}

# ── Event handlers ───────────────────────────────────────────
case "$EVENT" in
  user_prompt)
    echo "pending" > "$TASK_FILE"
    RESPONSE=$(aw_get "$AW_URL")
    APP=$(echo "$RESPONSE" | jq -r '.[0].data.app // ""' 2>/dev/null)
    TITLE=$(echo "$RESPONSE" | jq -r '.[0].data.title // ""' 2>/dev/null)
    if [ "$APP" = "$TERMINAL_APP" ]; then
        TOPIC=$(extract_topic "$TITLE")
        echo "$TOPIC" > "$TOPIC_FILE"
        echo "$TOPIC" > "$GLOBAL_TOPIC_FILE"
    fi
    # Cleanup stale session files (>24h)
    find /tmp -maxdepth 1 -name 'lmk_topic_*' -mmin +1440 -delete 2>/dev/null
    find /tmp -maxdepth 1 -name 'lmk_task_*' -mmin +1440 -delete 2>/dev/null
    exit 0
    ;;

  stop)
    [ ! -f "$TASK_FILE" ] && exit 0
    CONTENT=$(cat "$TASK_FILE" 2>/dev/null)
    [ "$CONTENT" = "notified" ] && exit 0
    echo "notified" > "$TASK_FILE"

    user_is_watching "$TOPIC_FILE" && exit 0

    TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null | sed 's|\\|/|g')
    LAST_Q=""
    if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
        LAST_Q=$(grep -a '"type":"user"' "$TRANSCRIPT" | while IFS= read -r line; do
            echo "$line" | jq -r 'select(.message.content | type == "string") | .message.content' 2>/dev/null
        done | grep -v "^$\|^null$" | tail -1 | sed 's/^[└ │]*//' | cut -c1-60)
    fi

    # Write rich context for notification hook to pick up
    echo "$(date +%s)|${LAST_Q}" > "$PENDING_MSG_FILE"
    exit 0
    ;;

  notification)
    user_is_watching "$GLOBAL_TOPIC_FILE" && exit 0

    if [ -f "$PENDING_MSG_FILE" ]; then
        PENDING=$(cat "$PENDING_MSG_FILE")
        PENDING_TS=$(echo "$PENDING" | cut -d'|' -f1)
        PENDING_CONTENT=$(echo "$PENDING" | cut -d'|' -f2-)
        NOW=$(date +%s)
        if [ $((NOW - PENDING_TS)) -lt 10 ]; then
            rm -f "$PENDING_MSG_FILE"
            if [ -n "$PENDING_CONTENT" ]; then
                MSG="📢 [${PROJECT}] CC 已回复
└ ${PENDING_CONTENT}"
            else
                MSG="📢 [${PROJECT}] CC 已回复"
            fi
        fi
    fi

    if [ -z "${MSG:-}" ]; then
        NOTIF=$(echo "$INPUT" | jq -r '.message // .title // ""' 2>/dev/null)
        if [ -n "$NOTIF" ] && [ "$NOTIF" != "null" ]; then
            SHORT=$(echo "$NOTIF" | cut -c1-80)
            MSG="📢 [${PROJECT}] 需要你查看
└ ${SHORT}"
        else
            MSG="📢 [${PROJECT}] 有消息需要你查看"
        fi
    fi
    ;;

  permission)
    user_is_watching "$GLOBAL_TOPIC_FILE" && exit 0

    TOOL=$(echo "$INPUT" | jq -r '.tool_name // "未知工具"' 2>/dev/null)
    CMD=$(echo "$INPUT" | jq -r '
      .tool_input |
      .command // .file_path // .description // .path // ""
    ' 2>/dev/null)
    if [ -n "$CMD" ] && [ "$CMD" != "null" ]; then
        SHORT_CMD=$(echo "$CMD" | head -1 | cut -c1-80)
        MSG="🔐 [${PROJECT}] 需要审批
工具：${TOOL}
内容：${SHORT_CMD}"
    else
        MSG="🔐 [${PROJECT}] 需要审批：${TOOL}"
    fi
    ;;

  *)
    MSG="⚡ [${PROJECT}] CC 事件：${EVENT}"
    ;;
esac

send_feishu "$MSG"
