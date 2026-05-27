[**English**](README.md)

# LetMeKnow-cc2feishu

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) 的飞书智能提醒。只在你没盯着屏幕时才发通知。

## 工作原理

```
┌─────────────┐    hooks     ┌──────────────────┐    lark-cli    ┌────────┐
│  Claude Code │ ──────────> │ notify-feishu.sh │ ────────────> │   飞书  │
│   (终端)     │             │                  │               │  (手机) │
└─────────────┘             │  ActivityWatch   │               └────────┘
                             │  ┌────────────┐  │
                             │  │ 在看吗？     │  │
                             │  │ 离开了吗？   │  │
                             │  └────────────┘  │
                             └──────────────────┘
                              只在你不看的时候才发
```

Claude Code 在关键事件时触发 [hook](https://docs.anthropic.com/en/docs/claude-code/hooks)。脚本捕获这些事件，通过 [ActivityWatch](https://activitywatch.net/) 检查你是否正在看那个终端窗口——**只有你不在看时**才发飞书消息。

### 通知类型

| 事件 | 触发时机 | 示例 |
|------|---------|------|
| 📢 回复完成 | Claude 完成一轮回复 | `📢 [项目 \| 主题] CC 已回复` |
| 🔐 需要审批 | Claude 需要工具权限 | `🔐 [项目 \| 主题] 需要审批` |
| 📢 需要关注 | 其他通知 | `📢 [项目 \| 主题] 需要你查看` |

每条消息包含你的原始问题（❓）和 Claude 的回复或通知内容（🦀）：

```
📢 [E:\my-project | discussing auth flow] CC 已回复
❓ 帮我实现 JWT 认证
🦀 我已经在 src/auth.ts 中添加了 JWT 中间件，包含 token 校验...
```

审批通知的格式略有不同——❓ 显示待审批内容，🦀 显示你的可选操作：

```
🔐 [E:\my-project | discussing auth flow] 需要审批
❓ Bash: npm install express
🦀 允许 / 拒绝 / 始终允许
```

### 智能静默

只有**同时满足**以下条件时，通知才会被静默：

1. 当前焦点窗口正是运行该 CC 会话的终端（通过 `aw-watcher-window` 匹配窗口标题主题）
2. 你**没有** AFK（通过 `aw-watcher-afk` 检测）

如果你在看别的窗口、别的 CC 会话、或者人已离开——通知照常发送。

### 多会话隔离

每个 CC 会话有独立的状态文件（`/tmp/lmk_topic_<session>`、`/tmp/lmk_task_<session>`、`/tmp/lmk_prompt_<session>`），通过会话的 transcript 路径区分。多个 CC 会话并行运行时互不干扰。

---

## 前置依赖

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)（v1.0+）
- [Node.js](https://nodejs.org/)（lark-cli 依赖）
- [lark-cli](https://github.com/nichenqin/lark-cli) — `npm install -g @nichenqin/lark-cli`
- [jq](https://jqlang.github.io/jq/) — JSON 处理工具
- curl
- （可选）[ActivityWatch](https://activitywatch.net/)，需运行 window 和 AFK watcher — 用于智能静默。不安装的话所有通知都会发送。

### ActivityWatch 数据源

本项目依赖 ActivityWatch 检测当前焦点窗口和 AFK 状态。标准 ActivityWatch 即可使用，如需增强数据采集可使用以下魔改版本：

| 组件 | 仓库 | 说明 |
|------|------|------|
| 窗口监控 | [aw-watcher-window-plus](https://github.com/liv10let/aw-watcher-window-plus) | 增强的窗口标题追踪 |
| AFK 检测 | [aw-watcher-afk-plus](https://github.com/liv10let/aw-watcher-afk-plus) | 增强的 AFK 检测 |
| VS Code 监控 | [aw-watcher-vscode-plus](https://github.com/liv10let/aw-watcher-vscode-plus) | VS Code 活动追踪 |
| 浏览器监控 | [aw-watcher-web-plus](https://github.com/liv10let/aw-watcher-web-plus) | 浏览器活动追踪 |
| 安卓客户端 | [aw-android-plus](https://github.com/liv10let/aw-android-plus) | 增强的安卓端 |

---

## 安装

```bash
git clone https://github.com/liv10let/LetMeKnow-cc2feishu.git
cd LetMeKnow-cc2feishu
bash install.sh
```

安装脚本会自动：
1. 复制 hook 脚本到 `~/.claude/notify-feishu.sh`
2. 创建配置模板到 `~/.config/letmeknow/config.json`
3. 在 Claude Code 的 `~/.claude/settings.json` 中注册四个 hook

## 配置

编辑 `~/.config/letmeknow/config.json`：

```json
{
  "feishu": {
    "open_id": "ou_你的飞书open_id"
  },
  "activitywatch": {
    "host": "localhost",
    "port": 5600,
    "user": "",
    "pass": "",
    "window_bucket": "aw-watcher-window_你的主机名",
    "afk_bucket": "aw-watcher-afk_你的主机名"
  },
  "terminal_app": "WindowsTerminal.exe"
}
```

| 字段 | 说明 |
|------|------|
| `feishu.open_id` | 飞书用户 open_id |
| `activitywatch.host` | AW 服务地址（默认 `localhost`） |
| `activitywatch.port` | AW 服务端口（默认 `5600`） |
| `activitywatch.user/pass` | AW 认证信息（无则留空） |
| `activitywatch.window_bucket` | 窗口监控 bucket 名 |
| `activitywatch.afk_bucket` | AFK 监控 bucket 名（可选） |
| `terminal_app` | 终端进程名，用于窗口匹配 |

常见终端进程名：

| 终端 | 进程名 |
|------|--------|
| Windows Terminal | `WindowsTerminal.exe` |
| VS Code 终端 | `Code.exe` |
| iTerm2 | `iTerm2` |
| macOS Terminal | `Terminal` |
| Alacritty | `Alacritty` |

### 飞书机器人配置

```bash
npm install -g @nichenqin/lark-cli
lark-cli auth login
```

需要一个飞书自建应用，开通 `im:message:send_as_bot` 权限。参见[飞书机器人开发指南](https://open.feishu.cn/document/home/develop-a-bot-in-5-minutes/create-an-app)。

登录后获取你的 `open_id`：

```bash
lark-cli auth status
# 找 "userOpenId": "ou_xxxxxxxx"
```

### ActivityWatch bucket 名称

如果安装了 ActivityWatch，查看你的 bucket 名称：

```bash
curl -s http://localhost:5600/api/0/buckets | jq 'keys'
```

找到类似 `aw-watcher-window_你的主机名` 和 `aw-watcher-afk_你的主机名` 的条目。

### 验证安装

测试飞书通道是否通畅：

```bash
lark-cli im +messages-send --as bot --user-id "ou_你的open_id" --text "LetMeKnow 测试消息"
```

你应该在飞书收到一条消息。如果没有，检查应用是否开通了 `im:message:send_as_bot` 权限。

---

## 架构设计

### Hook 触发流程

```
用户发送 prompt ──> UserPromptSubmit
                    ├── 保存窗口主题（按会话隔离）
                    ├── 保存用户提问
                    └── 标记任务为 "pending"

Claude 回复完成 ──> Stop（主通知）
                    ├── 去重检查（已通知则跳过）
                    ├── 检查用户是否在看（窗口 + AFK）
                    └── 发送 📢，包含问题 + 回复

CC 等待输入 ─────> Notification（兜底）
                    ├── Stop 已通知则跳过
                    ├── 检查用户是否在看
                    ├── 检测消息含 "permission" → 发送 🔐
                    └── 否则发送 📢，包含通知内容

工具需要审批 ────> PermissionRequest（如触发）
                    ├── 检查用户是否在看
                    └── 发送 🔐，包含工具详情
```

> **注意**：CC 实际上通过 Notification hook 发送权限请求（消息为 "Claude needs your permission"），而非 PermissionRequest hook。脚本会自动检测该关键词并转为 🔐 审批格式。

### 窗口匹配

Claude Code 会不断用 spinner 字符 + 对话主题更新终端标题（如 `⠋ discussing AW integration`）。脚本去除 spinner 前缀后提取稳定的主题部分，与用户发送 prompt 时保存的主题进行比对。

### 去重机制

- `UserPromptSubmit` 标记会话为 `"pending"`
- `Stop` 标记为 `"notified"` 并立即发送通知
- `Notification`（约 60 秒后触发）检查到 `"notified"` 则跳过
- 结果：每轮 CC 回复只发一条通知，不会重复

---

## 已知限制

- **权限请求通过 Notification hook 发送**，而非 PermissionRequest — Claude Code 通过 Notification 通道发送 `"Claude needs your permission"` 消息。脚本检测该关键词后自动渲染为 🔐 格式。
- **Notification/Permission hook** 不会从 Claude Code 接收会话标识符，因此使用全局 topic 文件做窗口匹配。在多 CC 并行场景下偶尔可能误判。
- **AFK 检测**需要运行 `aw-watcher-afk`。未配置时只使用窗口匹配。
- 需要 `lark-cli` 在 PATH 中。
- 脚本使用 bash 编写，Windows 用户需要 Git Bash、WSL 或 MSYS2。Claude Code 在 Windows 上默认使用 Git Bash，通常无需额外配置。

---

## 卸载

1. 从 `~/.claude/settings.json` 的 `hooks` 中删除 `UserPromptSubmit`、`Stop`、`Notification`、`PermissionRequest` 条目
2. 删除 hook 脚本：`rm ~/.claude/notify-feishu.sh`
3. 删除配置：`rm -rf ~/.config/letmeknow`

---

## License

[MIT](LICENSE)
