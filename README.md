[**中文文档**](README_CN.md)

# LetMeKnow-cc2feishu

Smart Feishu (Lark) notifications for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Get notified on your phone — only when you're not looking.

## How it works

```
┌─────────────┐    hooks     ┌──────────────────┐    lark-cli    ┌────────┐
│  Claude Code │ ──────────> │ notify-feishu.sh │ ────────────> │  Feishu │
│  (terminal)  │             │                  │               │  (app)  │
└─────────────┘             │  ActivityWatch   │               └────────┘
                             │  ┌────────────┐  │
                             │  │ watching?   │  │
                             │  │ afk?        │  │
                             │  └────────────┘  │
                             └──────────────────┘
                              Only notifies when
                              you're NOT watching
```

Claude Code fires [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) on key events. This script catches them, checks whether you're currently focused on that terminal via [ActivityWatch](https://activitywatch.net/), and only sends a Feishu message when you're **not looking**.

### Notification types

| Event | Trigger | Example |
|-------|---------|---------|
| 📢 Response ready | Claude finishes responding | `📢 [project \| topic] CC 已回复` |
| 🔐 Approval needed | Claude needs tool permission | `🔐 [project \| topic] 需要审批` |
| 📢 Attention needed | Other notifications | `📢 [project \| topic] 需要你查看` |

Each message includes your original question (❓) and Claude's reply or the notification content (🦀):

```
📢 [E:\my-project | discussing auth flow] CC 已回复
❓ help me implement JWT authentication
🦀 I've added the JWT middleware in src/auth.ts with token validation...
```

Permission requests use a different layout — ❓ shows what needs approval, 🦀 shows your options:

```
🔐 [E:\my-project | discussing auth flow] 需要审批
❓ Bash: npm install express
🦀 允许 / 拒绝 / 始终允许
```

### Smart suppression

Notifications are suppressed when **both** conditions are met:

1. Your focused window is the terminal running that CC session (matched by window title topic via `aw-watcher-window`)
2. You are **not** AFK (via `aw-watcher-afk`)

Otherwise — different window, different CC session, or AFK — the notification fires.

### Multi-session isolation

Each CC session gets independent state files (`/tmp/lmk_topic_<session>`, `/tmp/lmk_task_<session>`, `/tmp/lmk_prompt_<session>`), keyed by the session's transcript path. Multiple concurrent CC sessions won't interfere with each other.

---

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (v1.0+)
- [lark-cli](https://github.com/nichenqin/lark-cli) — `npm install -g @nichenqin/lark-cli`
- [jq](https://jqlang.github.io/jq/) — JSON processor
- [ActivityWatch](https://activitywatch.net/) with window and AFK watchers running

### ActivityWatch data source

This project uses ActivityWatch for focus window and AFK detection. The standard ActivityWatch works, but for enhanced tracking you can use these customized versions:

| Component | Repo | Description |
|-----------|------|-------------|
| Window watcher | [aw-watcher-window-plus](https://github.com/liv10let/aw-watcher-window-plus) | Enhanced window title tracking |
| AFK watcher | [aw-watcher-afk-plus](https://github.com/liv10let/aw-watcher-afk-plus) | Enhanced AFK detection |
| VS Code watcher | [aw-watcher-vscode-plus](https://github.com/liv10let/aw-watcher-vscode-plus) | VS Code activity tracking |
| Web watcher | [aw-watcher-web-plus](https://github.com/liv10let/aw-watcher-web-plus) | Browser activity tracking |
| Android client | [aw-android-plus](https://github.com/liv10let/aw-android-plus) | Enhanced Android client |

---

## Install

```bash
git clone https://github.com/liv10let/LetMeKnow-cc2feishu.git
cd LetMeKnow-cc2feishu
bash install.sh
```

The installer will:
1. Copy the hook script to `~/.claude/notify-feishu.sh`
2. Create a config template at `~/.config/letmeknow/config.json`
3. Register hooks in Claude Code's `~/.claude/settings.json`

## Configure

Edit `~/.config/letmeknow/config.json`:

```json
{
  "feishu": {
    "open_id": "ou_your_feishu_open_id"
  },
  "activitywatch": {
    "host": "localhost",
    "port": 5600,
    "user": "",
    "pass": "",
    "window_bucket": "aw-watcher-window_YOUR-HOSTNAME",
    "afk_bucket": "aw-watcher-afk_YOUR-HOSTNAME"
  },
  "terminal_app": "WindowsTerminal.exe"
}
```

| Field | Description |
|-------|-------------|
| `feishu.open_id` | Your Feishu user open_id |
| `activitywatch.host` | AW server host (default `localhost`) |
| `activitywatch.port` | AW server port (default `5600`) |
| `activitywatch.user/pass` | AW basic auth credentials (leave empty if none) |
| `activitywatch.window_bucket` | Window watcher bucket name |
| `activitywatch.afk_bucket` | AFK watcher bucket name (optional) |
| `terminal_app` | Terminal process name for window matching |

Common `terminal_app` values:

| Terminal | Process name |
|----------|-------------|
| Windows Terminal | `WindowsTerminal.exe` |
| VS Code | `Code.exe` |
| iTerm2 | `iTerm2` |
| macOS Terminal | `Terminal` |
| Alacritty | `Alacritty` |

### Feishu bot setup

```bash
npm install -g @nichenqin/lark-cli
lark-cli auth login
```

You need a Feishu custom app with `im:message:send_as_bot` permission. See [Feishu Bot Guide](https://open.feishu.cn/document/home/develop-a-bot-in-5-minutes/create-an-app).

---

## Architecture

### Hook flow

```
User sends prompt ──> UserPromptSubmit
                      ├── Save window topic (per-session)
                      ├── Save user prompt
                      └── Mark task as "pending"

Claude responds ────> Stop (primary notification)
                      ├── Dedup check (skip if already notified)
                      ├── Check if user is watching (window + AFK)
                      └── Send 📢 with question + reply

CC waits for input ─> Notification (fallback)
                      ├── Skip if Stop already notified
                      ├── Check if user is watching
                      ├── Detect "permission" keyword → send 🔐
                      └── Otherwise send 📢 with notification content

Tool needs approval ─> PermissionRequest (if fired)
                       ├── Check if user is watching
                       └── Send 🔐 with tool details
```

> **Note**: Claude Code typically sends permission requests via the Notification hook (message: "Claude needs your permission"), not PermissionRequest. The script auto-detects this and uses the 🔐 format.

### Window matching

Claude Code updates the terminal title with a spinner + conversation topic (e.g., `⠋ discussing AW integration`). The script strips the spinner prefix to extract the stable topic, then compares it against the saved topic from when the user sent their prompt.

### Dedup

- `UserPromptSubmit` marks the session as `"pending"`
- `Stop` marks it `"notified"` and sends immediately
- `Notification` (fires ~60s later) checks for `"notified"` and skips if Stop already handled it
- Result: one notification per CC turn, never duplicates

---

## Limitations

- **Permission requests arrive via Notification hook**, not PermissionRequest — Claude Code sends `"Claude needs your permission"` through the Notification channel. The script detects this keyword and renders it as a 🔐 message.
- **Notification/Permission hooks** don't receive session identifiers from Claude Code, so they use a global topic file for window matching. In multi-CC scenarios, this may occasionally misjudge.
- **AFK detection** requires `aw-watcher-afk` running. Without it, only window matching is used.
- Requires `lark-cli` in PATH.
- Bash script — Windows users need Git Bash, WSL, or MSYS2. Claude Code on Windows uses Git Bash by default.

---

## License

[MIT](LICENSE)
