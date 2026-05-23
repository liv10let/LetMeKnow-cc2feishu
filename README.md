# LetMeKnow-cc2feishu

Smart Feishu (Lark) notifications for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Get notified on your phone only when you're not looking.

Claude Code 的飞书智能提醒。只在你没盯着屏幕时才发通知。

---

## How it works / 工作原理

```
┌─────────────┐    hooks     ┌──────────────────┐    lark-cli    ┌────────┐
│  Claude Code │ ──────────> │ notify-feishu.sh │ ────────────> │  Feishu │
│  (terminal)  │             │                  │               │  (手机)  │
└─────────────┘             │  ActivityWatch   │               └────────┘
                             │  ┌────────────┐  │
                             │  │ window? afk?│  │
                             │  └────────────┘  │
                             └──────────────────┘
                              Only sends if you're
                              NOT watching / 不在看时才发
```

Claude Code fires [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) on key events. This script catches them, checks whether you're currently focused on that terminal (via [ActivityWatch](https://activitywatch.net/)), and only sends a Feishu message when you're **not looking**.

Claude Code 在关键事件时触发 hook。脚本捕获这些事件，通过 ActivityWatch 检查你是否正在看那个终端窗口——**只有你不在看时**才发飞书消息。

### Notification types / 通知类型

| Event | When / 触发时机 | Message |
|-------|----------|---------|
| 📢 CC responded | Claude finishes a response / 回复完成 | `📢 [project] CC 已回复 └ your question` |
| 🔐 Approval needed | Claude needs permission for a tool / 需要审批 | `🔐 [project] 需要审批 工具：Bash 内容：npm install` |
| 📢 Attention | Other notifications / 其他通知 | `📢 [project] 需要你查看` |

### Smart suppression / 智能静默

Notifications are suppressed when **all** of these are true:

1. Your focused window is the terminal running that CC session (via `aw-watcher-window`)
2. You are **not** AFK (via `aw-watcher-afk`)

If you're looking at a **different** CC session, or a different app entirely, or AFK — the notification fires.

只有当你**同时满足**以下条件时，通知才会静默：
1. 当前焦点窗口正是运行该 CC 会话的终端（通过 `aw-watcher-window` 检测）
2. 你**没有** AFK（通过 `aw-watcher-afk` 检测）

如果你在看别的 CC 会话、别的应用、或者人已离开——通知照常发送。

### Multi-session isolation / 多会话隔离

Each Claude Code session gets its own state files (`/tmp/lmk_topic_<session>`, `/tmp/lmk_task_<session>`), so multiple concurrent CC sessions won't interfere with each other's dedup or window matching.

每个 CC 会话有独立的状态文件，多个 CC 会话并行运行时互不干扰。

---

## Prerequisites / 前置依赖

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (v1.0+)
- [lark-cli](https://github.com/nichenqin/lark-cli) — Feishu/Lark CLI tool (`npm install -g @nichenqin/lark-cli`)
- [jq](https://jqlang.github.io/jq/) — JSON processor
- [ActivityWatch](https://activitywatch.net/) with window and AFK watchers running

### ActivityWatch data source / ActivityWatch 数据源

This project relies on ActivityWatch to detect your current focus window and AFK status. The standard ActivityWatch distribution works, but for enhanced data collection (especially on Android and in browsers), you may want to use these customized versions:

本项目依赖 ActivityWatch 检测当前焦点窗口和 AFK 状态。标准 ActivityWatch 即可使用，但如需增强数据采集（特别是安卓端和浏览器端），推荐使用以下魔改版本：

| Component | Repo | Description |
|-----------|------|-------------|
| Window watcher | [aw-watcher-window-plus](https://github.com/liv10let/aw-watcher-window-plus) | Enhanced window title tracking |
| AFK watcher | [aw-watcher-afk-plus](https://github.com/liv10let/aw-watcher-afk-plus) | Enhanced AFK detection |
| VS Code watcher | [aw-watcher-vscode-plus](https://github.com/liv10let/aw-watcher-vscode-plus) | VS Code activity tracking |
| Web watcher | [aw-watcher-web-plus](https://github.com/liv10let/aw-watcher-web-plus) | Browser activity tracking |
| Android client | [aw-android-plus](https://github.com/liv10let/aw-android-plus) | Enhanced Android client |

---

## Install / 安装

```bash
git clone https://github.com/liv10let/LetMeKnow-cc2feishu.git
cd LetMeKnow-cc2feishu
bash install.sh
```

The installer will:
1. Copy the hook script to `~/.claude/notify-feishu.sh`
2. Create a config template at `~/.config/letmeknow/config.json`
3. Register hooks in Claude Code's `~/.claude/settings.json`

安装脚本会自动复制 hook 脚本、创建配置模板、注册到 Claude Code 的 hooks 中。

## Configure / 配置

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
| `feishu.open_id` | Your Feishu user open_id (get from Feishu bot admin) / 飞书用户 open_id |
| `activitywatch.host` | AW server host (default `localhost`) |
| `activitywatch.port` | AW server port (default `5600`) |
| `activitywatch.user/pass` | AW basic auth credentials, leave empty if none / AW 认证信息，无则留空 |
| `activitywatch.window_bucket` | AW window watcher bucket name / 窗口监控 bucket 名 |
| `activitywatch.afk_bucket` | AW AFK watcher bucket name (optional) / AFK 监控 bucket 名（可选） |
| `terminal_app` | Terminal process name for window matching / 终端进程名，用于窗口匹配 |

Common `terminal_app` values / 常见终端进程名:
- Windows Terminal: `WindowsTerminal.exe`
- VS Code: `Code.exe`
- iTerm2: `iTerm2`
- macOS Terminal: `Terminal`
- Alacritty: `Alacritty`

### lark-cli setup / 飞书 CLI 配置

```bash
# Install
npm install -g @nichenqin/lark-cli

# Login with your Feishu bot credentials
lark-cli auth login
```

You need a Feishu custom bot with messaging permissions. See [Feishu Bot Guide](https://open.feishu.cn/document/home/develop-a-bot-in-5-minutes/create-an-app).

需要一个有消息发送权限的飞书自建应用。

---

## How it works (detailed) / 详细原理

### Hook → notification flow / Hook 触发流程

```
User sends prompt ──> UserPromptSubmit hook
                      ├── Save current window topic (per-session)
                      └── Mark task as "pending"

Claude responds ────> Stop hook
                      ├── Dedup check (skip if already notified)
                      ├── Check if user is watching (AW window + AFK)
                      ├── Extract last user question from transcript
                      └── Write rich context to pending file (don't send yet)

CC waits for input ─> Notification hook
                      ├── Check if user is watching
                      ├── Read pending rich context from Stop
                      └── Send single 📢 message with context

Tool needs approval ─> PermissionRequest hook
                       ├── Check if user is watching
                       └── Send 🔐 message with tool details
```

### Window matching / 窗口匹配

Claude Code constantly updates the terminal title with a spinner character + conversation topic (e.g., `⠋ discussing AW integration`). The script strips the spinner prefix to extract the stable topic, then compares it against the saved topic from when the user sent their prompt.

Claude Code 会不断用 spinner 字符 + 对话主题更新终端标题。脚本去除 spinner 前缀后提取稳定的主题部分，与用户发送 prompt 时保存的主题进行比对。

### Dedup / 去重机制

- Each CC session maintains its own task state file
- `UserPromptSubmit` marks it "pending"
- `Stop` marks it "notified" on first fire, subsequent fires within the same turn are skipped
- `Stop` writes rich context to a pending file; `Notification` picks it up within 10 seconds
- Result: one message per CC turn, never duplicates

每个 CC 会话维护独立的任务状态文件，确保每个回合只发一条通知。

---

## Limitations / 已知限制

- **Notification/Permission hooks** don't receive session identifiers from Claude Code, so they use a global topic file for window matching. In multi-CC scenarios, this may occasionally suppress a notification incorrectly (if you're focused on a different CC session in the same project).
- **AFK detection** depends on `aw-watcher-afk` running. If not configured, only window matching is used.
- Requires `lark-cli` in PATH. The script does not manage Feishu bot tokens directly.

---

## License

[MIT](LICENSE)
