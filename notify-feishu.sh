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
PROMPT_FILE="/tmp/lmk_prompt_${SESSION_KEY}"

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)

# ── Helpers ──────────────────────────────────────────────────

extract_topic() {
    echo "$1" | sed 's/^[^ ]* //'
}

aw_get() {
    curl -s $AW_AUTH_ARG "$1" --connect-timeout 2 2>/dev/null
}

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

    if [ -n "$AW_AFK_BUCKET" ] && [ "$AW_AFK_BUCKET" != "null" ]; then
        local afk_response afk_status
        afk_response=$(aw_get "$AW_AFK_URL")
        afk_status=$(echo "$afk_response" | jq -r '.[0].data.status // ""' 2>/dev/null)
        [ "$afk_status" = "afk" ] && return 1
    fi

    return 0
}

build_header() {
    local label="$1"
    local topic=$(cat "$GLOBAL_TOPIC_FILE" 2>/dev/null)
    local display_path="$CWD"
    [ -z "$display_path" ] || [ "$display_path" = "null" ] && display_path="$PROJECT"
    if [ -n "$topic" ]; then
        echo "[${display_path} | ${topic}] ${label}"
    else
        echo "[${display_path}] ${label}"
    fi
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
    PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)
    echo "$PROMPT" > "$PROMPT_FILE"

    RESPONSE=$(aw_get "$AW_URL")
    APP=$(echo "$RESPONSE" | jq -r '.[0].data.app // ""' 2>/dev/null)
    TITLE=$(echo "$RESPONSE" | jq -r '.[0].data.title // ""' 2>/dev/null)
    if [ "$APP" = "$TERMINAL_APP" ]; then
        TOPIC=$(extract_topic "$TITLE")
        echo "$TOPIC" > "$TOPIC_FILE"
        echo "$TOPIC" > "$GLOBAL_TOPIC_FILE"
    fi
    find /tmp -maxdepth 1 -name 'lmk_topic_*' -mmin +1440 -delete 2>/dev/null
    find /tmp -maxdepth 1 -name 'lmk_task_*' -mmin +1440 -delete 2>/dev/null
    find /tmp -maxdepth 1 -name 'lmk_prompt_*' -mmin +1440 -delete 2>/dev/null
    exit 0
    ;;

  stop)
    [ ! -f "$TASK_FILE" ] && exit 0
    CONTENT=$(cat "$TASK_FILE" 2>/dev/null)
    [ "$CONTENT" = "notified" ] && exit 0
    echo "notified" > "$TASK_FILE"

    user_is_watching "$TOPIC_FILE" && exit 0

    SAVED_PROMPT=$(cat "$PROMPT_FILE" 2>/dev/null | cut -c1-200)
    LAST_REPLY=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null | tr '\n' ' ' | cut -c1-500)

    MSG="📢 $(build_header "CC 已回复")"
    [ -n "$SAVED_PROMPT" ] && MSG="${MSG}
❓ ${SAVED_PROMPT}"
    [ -n "$LAST_REPLY" ] && MSG="${MSG}
🦀 ${LAST_REPLY}"
    ;;

  notification)
    TASK_CONTENT=$(cat "$TASK_FILE" 2>/dev/null)
    [ "$TASK_CONTENT" = "notified" ] && exit 0

    user_is_watching "$GLOBAL_TOPIC_FILE" && exit 0

    SAVED_PROMPT=$(cat "$PROMPT_FILE" 2>/dev/null | cut -c1-200)
    NOTIF=$(echo "$INPUT" | jq -r '.message // .title // ""' 2>/dev/null | cut -c1-200)

    MSG="📢 $(build_header "需要你查看")"
    [ -n "$SAVED_PROMPT" ] && MSG="${MSG}
❓ ${SAVED_PROMPT}"
    [ -n "$NOTIF" ] && [ "$NOTIF" != "null" ] && MSG="${MSG}
🦀 ${NOTIF}"
    ;;

  permission)
    user_is_watching "$GLOBAL_TOPIC_FILE" && exit 0

    SAVED_PROMPT=$(cat "$PROMPT_FILE" 2>/dev/null | cut -c1-200)
    TOOL=$(echo "$INPUT" | jq -r '.tool_name // "未知工具"' 2>/dev/null)
    CMD=$(echo "$INPUT" | jq -r '
      .tool_input |
      .command // .file_path // .description // .path // ""
    ' 2>/dev/null)
    SHORT_CMD=""
    if [ -n "$CMD" ] && [ "$CMD" != "null" ]; then
        SHORT_CMD=$(echo "$CMD" | head -1 | cut -c1-200)
    fi

    MSG="🔐 $(build_header "需要审批")"
    if [ -n "$SHORT_CMD" ]; then
        MSG="${MSG}
❓ ${TOOL}: ${SHORT_CMD}"
    else
        MSG="${MSG}
❓ ${TOOL}"
    fi
    MSG="${MSG}
🦀 允许 / 拒绝 / 始终允许"
    ;;

  *)
    MSG="⚡ [${PROJECT}] CC 事件：${EVENT}"
    ;;
esac

send_feishu "$MSG"
