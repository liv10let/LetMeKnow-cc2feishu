# LetMeKnow — Claude Code 飞书智能提醒

> 只在你没盯着屏幕的时候，才打扰你。

---

## 这是什么

LetMeKnow 是一个 Claude Code 的 Hook 插件，通过飞书机器人在以下场景给你发消息提醒：

- **CC 回复完成** — 你去泡咖啡了，CC 干完活了，飞书告诉你
- **需要审批** — CC 要执行某个工具，等你确认，飞书告诉你
- **需要关注** — CC 有其他事项需要你查看，飞书告诉你

**核心特性：它不会在你盯着屏幕的时候骚扰你。**

它通过 ActivityWatch 实时检测你当前的焦点窗口：
- 你正在看这个 CC 的终端 → 静默，不发通知
- 你切到了浏览器、另一个 CC、或者任何其他窗口 → 发通知
- 你的焦点虽然在 CC 终端上，但人已经离开电脑（AFK）→ 发通知

---

## 架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                        你的电脑                                  │
│                                                                 │
│  ┌─────────────┐   CC Hooks    ┌──────────────────────────┐    │
│  │ Claude Code  │ ───────────> │    notify-feishu.sh       │    │
│  │  (终端)      │              │                          │    │
│  └─────────────┘              │  1. 检查去重状态           │    │
│                                │  2. 查询 ActivityWatch    │    │
│  ┌─────────────┐              │     - 当前焦点窗口是？     │    │
│  │ActivityWatch │ <─────────  │     - 用户是否 AFK？      │    │
│  │  (数据源)    │   HTTP API   │  3. 决定是否发送          │    │
│  └─────────────┘              └───────────┬──────────────┘    │
│                                            │                    │
└────────────────────────────────────────────┼────────────────────┘
                                             │ lark-cli
                                             ▼
                                      ┌────────────┐
                                      │  飞书机器人  │
                                      │  (消息推送)  │
                                      └──────┬─────┘
                                             │
                                             ▼
                                      ┌────────────┐
                                      │  你的手机    │
                                      │  📢 CC 已回复│
                                      └────────────┘
```

---

## 通知类型

### 📢 CC 已回复

**触发时机**：Claude Code 完成一轮回复（Stop hook 直接发送，不等待 Notification hook）

**消息格式**：
```
📢 [E:\my-project | discussing auth flow] CC 已回复
❓ 帮我实现 JWT 认证
🦀 我已经在 src/auth.ts 中添加了 JWT 中间件，包含 token 校验...
```

- 第一行：`📢 [工作路径 | 对话主题] CC 已回复`
- ❓ 行：你最后一条提问（截取前 200 字）
- 🦀 行：CC 的回复摘要（截取前 500 字）

### 🔐 需要审批

**触发时机**：Claude Code 需要执行某个工具（如运行命令、修改文件），等待你批准

> **注意**：CC 实际上通过 Notification hook（而非 PermissionRequest hook）发送权限请求，消息内容为 "Claude needs your permission"。脚本会自动检测该关键词并转为 🔐 审批格式。

**消息格式**：
```
🔐 [E:\my-project | discussing auth flow] 需要审批
❓ Bash: npm install express
🦀 允许 / 拒绝 / 始终允许
```

- ❓ 行：待审批的工具和命令
- 🦀 行：你的可选操作

### 📢 需要你查看

**触发时机**：Claude Code 发出其他类型的通知（作为 Stop 的兜底）

**消息格式**：
```
📢 [E:\my-project | discussing auth flow] 需要你查看
❓ 帮我优化这段代码
🦀 Claude is waiting for your input
```

---

## 智能静默机制

这是本项目的核心能力。通知不是无脑发送的，而是经过两层判断：

### 第一层：焦点窗口检测

通过 ActivityWatch 的 `aw-watcher-window` 获取你当前电脑的焦点窗口信息（应用名 + 窗口标题）。

Claude Code 会自动在终端标题中显示一个 spinner 字符加上当前对话主题，例如：
```
⠋ discussing AW integration
```

脚本在你发送 prompt 时记录下这个主题，CC 回复完成后再次查询当前窗口，对比主题是否一致：

| 场景 | 焦点窗口 | 结果 |
|------|---------|------|
| 你在看这个 CC | WindowsTerminal + 匹配的主题 | ✅ 静默 |
| 你在看别的 CC | WindowsTerminal + 不同的主题 | 📢 发通知 |
| 你在用浏览器 | Chrome / Edge / ... | 📢 发通知 |
| 你在用 VS Code | Code.exe | 📢 发通知 |

### 第二层：AFK 检测

即使焦点窗口匹配（你"看起来"在 CC 终端上），脚本还会查询 `aw-watcher-afk`：

| 焦点窗口匹配 | AFK 状态 | 结果 |
|-------------|---------|------|
| ✅ 匹配 | not-afk（人在） | ✅ 静默 |
| ✅ 匹配 | afk（人走了） | 📢 发通知 |
| ❌ 不匹配 | （不检查） | 📢 发通知 |

**典型场景**：你把终端开着，去上厕所了。CC 干完活了。虽然你的屏幕还停留在 CC 终端上，但 AFK 检测发现你已经离开，照常给你发飞书消息。

---

## 多会话隔离

如果你同时开了多个终端，每个终端里都跑着一个 Claude Code 会话，它们不会互相干扰。

每个 CC 会话有独立的状态文件：

```
/tmp/lmk_topic_<session-uuid>   ← 该会话的窗口主题
/tmp/lmk_task_<session-uuid>    ← 该会话的去重状态
/tmp/lmk_prompt_<session-uuid>  ← 该会话的用户提问
```

session 标识符来源于 CC 的 transcript 文件路径（每个对话唯一且稳定）。

### 去重机制

同一轮对话只会发送一条通知，不会重复：

```
你发 prompt ──→ UserPromptSubmit hook
                ├── 标记 "pending"
                └── 保存用户提问

CC 回复完成 ──→ Stop hook（主通知）
                ├── 检查去重（已 notified 则跳过）
                ├── 标记 "notified"
                ├── 检查用户是否在看
                └── 立即发送 📢

CC 等待输入 ──→ Notification hook（兜底，约 60 秒后）
                ├── 检查 "notified"，已处理则跳过
                ├── 检测消息是否含 "permission"
                │   ├── 是 → 发送 🔐 审批通知
                │   └── 否 → 发送 📢 普通通知
                └── 只在 Stop 未触发时才发送
```

Stop hook 在 CC 回复完成时**立即发送**，无延迟。Notification hook 作为兜底，只在 Stop 因某种原因未触发时才会补发。

---

## 安装指南

### 前置要求

| 依赖 | 用途 | 安装 |
|------|------|------|
| Claude Code | 本体 | [官方文档](https://docs.anthropic.com/en/docs/claude-code) |
| lark-cli | 发送飞书消息 | `npm install -g @nichenqin/lark-cli` |
| jq | 解析 JSON | [下载](https://jqlang.github.io/jq/download/) |
| curl | HTTP 请求 | 系统自带 |
| ActivityWatch | 焦点检测 | [官网](https://activitywatch.net/) |

### ActivityWatch 数据源

本项目依赖 ActivityWatch 采集的窗口焦点和 AFK 数据。标准版 ActivityWatch 即可使用，但推荐使用以下增强版本获得更好的数据采集效果：

| 组件 | 仓库 | 说明 |
|------|------|------|
| 窗口监控 | [aw-watcher-window-plus](https://github.com/liv10let/aw-watcher-window-plus) | 增强的窗口标题追踪 |
| AFK 检测 | [aw-watcher-afk-plus](https://github.com/liv10let/aw-watcher-afk-plus) | 增强的 AFK 检测 |
| VS Code 监控 | [aw-watcher-vscode-plus](https://github.com/liv10let/aw-watcher-vscode-plus) | VS Code 活动追踪 |
| 浏览器监控 | [aw-watcher-web-plus](https://github.com/liv10let/aw-watcher-web-plus) | 浏览器活动追踪 |
| 安卓客户端 | [aw-android-plus](https://github.com/liv10let/aw-android-plus) | 增强的安卓端 |

### 安装步骤

**1. 克隆仓库**

```bash
git clone https://github.com/liv10let/LetMeKnow-cc2feishu.git
cd LetMeKnow-cc2feishu
```

**2. 运行安装脚本**

```bash
bash install.sh
```

安装脚本会自动完成：
- 复制 `notify-feishu.sh` 到 `~/.claude/`
- 创建配置模板到 `~/.config/letmeknow/config.json`
- 在 Claude Code 的 `~/.claude/settings.json` 中注册四个 hook

**3. 配置飞书机器人**

如果还没有飞书机器人，需要先创建一个：

1. 前往 [飞书开放平台](https://open.feishu.cn/) 创建自建应用
2. 添加「机器人」能力
3. 在权限管理中开通 `im:message:send_as_bot`（以机器人身份发送消息）
4. 发布应用并获取 App ID 和 App Secret

然后配置 lark-cli：
```bash
lark-cli auth login
# 输入 App ID 和 App Secret
```

**4. 编辑配置文件**

```bash
nano ~/.config/letmeknow/config.json
```

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

配置项说明：

| 字段 | 说明 | 示例 |
|------|------|------|
| `feishu.open_id` | 飞书用户 open_id | `ou_2bcfa58c...` |
| `activitywatch.host` | AW 服务地址 | `localhost` 或远程 IP |
| `activitywatch.port` | AW 服务端口 | `5600`（默认） |
| `activitywatch.user/pass` | AW 认证（如有） | 留空则不认证 |
| `activitywatch.window_bucket` | 窗口监控 bucket | `aw-watcher-window_MY-PC` |
| `activitywatch.afk_bucket` | AFK 监控 bucket | `aw-watcher-afk_MY-PC`（可选） |
| `terminal_app` | 终端进程名 | 见下表 |

常见终端进程名：

| 终端 | 进程名 |
|------|--------|
| Windows Terminal | `WindowsTerminal.exe` |
| VS Code 终端 | `Code.exe` |
| iTerm2 | `iTerm2` |
| macOS Terminal | `Terminal` |
| Alacritty | `Alacritty` |

**5. 重启 Claude Code**

Hooks 在 CC 启动时加载，修改后需要重启：

```bash
/exit
claude
```

**6. 验证**

获取你的 AW bucket 名称：
```bash
curl http://localhost:5600/api/0/buckets | jq 'keys'
```

测试飞书消息发送：
```bash
lark-cli im +messages-send --as bot \
  --user-id "ou_你的open_id" \
  --text "LetMeKnow 测试消息 🎉"
```

然后在 CC 里正常对话，切换到其他窗口，等 CC 回复完成——你应该会在飞书收到一条 📢 通知。

---

## 已知限制

1. **权限请求通过 Notification hook 发送** — Claude Code 实际上通过 Notification hook（而非 PermissionRequest hook）发送权限请求，消息内容为 "Claude needs your permission"。脚本会自动检测该关键词并转为 🔐 审批格式。PermissionRequest hook 作为后备保留。

2. **Notification/Permission hook 没有会话标识** — Claude Code 不会把 session_id 传给这两种 hook，因此它们使用全局 topic 文件做窗口匹配。在多 CC 并行场景下，偶尔可能误判（把你在另一个 CC 窗口误认为在看当前 CC）。Stop hook 的去重和窗口匹配是完全按会话隔离的。

3. **AFK 检测依赖 aw-watcher-afk** — 如果没有运行 AFK watcher，只使用窗口匹配，不会判断你是否离开电脑。

4. **需要 lark-cli 在 PATH 中** — 脚本通过 lark-cli 发送消息，不直接管理飞书 token。

5. **仅支持类 Unix shell** — 脚本使用 bash 编写，Windows 用户需要 Git Bash、WSL 或 MSYS2 环境。Claude Code 在 Windows 上默认使用 Git Bash，所以通常不需要额外配置。

---

## 项目地址

**GitHub**: [github.com/liv10let/LetMeKnow-cc2feishu](https://github.com/liv10let/LetMeKnow-cc2feishu)

**License**: MIT

---

## 相关项目

- [ActivityWatch](https://activitywatch.net/) — 开源的个人活动追踪工具
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — Anthropic 的终端 AI 编程助手
- [lark-cli](https://github.com/nichenqin/lark-cli) — 飞书/Lark 命令行工具
