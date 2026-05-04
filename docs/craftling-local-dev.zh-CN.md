# Craftling 本地开发命令

本文记录 Craftling fork 的本地运行约定。目标是把 OpenClaw/Craftling 的运行状态放在仓库工作空间内，同时避免把个人运行数据提交到 Git。

## 环境要求

- Git。
- PowerShell。当前 `craftling:*` 命令调用的是 `scripts/craftling-*.ps1`。
- Node.js 24 推荐；项目声明最低要求为 Node `>=22.14.0`。
- pnpm `10.33.0`。项目在 `package.json` 里通过 `packageManager` 声明了该版本。

推荐安装官方 Node.js 发行版，而不是只带 `node.exe` 的精简运行时。精简运行时可能没有 `npm`、`corepack` 或 `pnpm`，会导致首次安装卡住。

启用 pnpm：

```powershell
corepack enable
corepack prepare pnpm@10.33.0 --activate
pnpm -v
```

如果当前 shell 找不到裸 `pnpm`，可以先用：

```powershell
corepack pnpm -v
```

下文命令里的 `pnpm` 也可以替换成 `corepack pnpm`。

## 首次安装顺序

克隆并进入仓库根目录：

```powershell
git clone https://github.com/spirit-rebirth/Craftling.git
cd Craftling
```

安装依赖：

```powershell
pnpm install
```

构建源码和 Control UI：

```powershell
pnpm build
pnpm --dir ui run build
```

初始化 Craftling 本地配置：

```powershell
pnpm craftling:setup
```

启动 dev Gateway：

```powershell
pnpm craftling:dev
```

另开一个 PowerShell，查看健康状态和 Gateway 状态：

```powershell
pnpm craftling:health
pnpm craftling:status
```

打开 Dashboard/Control UI：

```powershell
pnpm craftling:dashboard
```

停止 Gateway：

```powershell
pnpm craftling:stop
```

Control UI 修改后可单独重建：

```powershell
pnpm --dir ui run build
```

## 路径约定

本地运行数据放在：

```text
<repo>\.craftling\
  state\       # state、config、sessions、tokens 等
  workspace\   # agent workspace
  logs\        # 本地日志
  tmp\         # 临时文件
```

这些目录由脚本生成，并已在 `.gitignore` 中忽略。它们属于每台机器自己的运行状态，不应提交。

## 为什么忽略 .craftling

`.craftling/state` 里可能包含：

- gateway token/password
- API keys 或 SecretRef
- sessions 历史
- device/pairing token
- 本机绝对路径
- 缓存、日志、临时状态

这些内容不适合提交。应提交的是脚本、示例配置和文档，而不是某台机器生成的实际运行状态。

## 脚本说明

底层 PowerShell 脚本位于 `scripts/`：

```text
scripts/craftling-setup.ps1
scripts/craftling-dev.ps1
scripts/craftling-health.ps1
scripts/craftling-status.ps1
scripts/craftling-dashboard.ps1
scripts/craftling-stop.ps1
```

这些脚本内部会统一设置：

```text
OPENCLAW_PROFILE=craftling-dev
OPENCLAW_STATE_DIR=<repo>\.craftling\state
OPENCLAW_CONFIG_PATH=<repo>\.craftling\state\openclaw.json
OPENCLAW_GATEWAY_PORT=19001
OPENCLAW_SKIP_CHANNELS=1
```

这些路径由脚本根据自身所在位置自动推导，不依赖固定盘符或固定目录。因此日常使用时不需要手动输入环境变量。

## Gateway

默认监听：

```text
ws://127.0.0.1:19001
```

该模式不会连接真实消息渠道，也不会安装 daemon。

日志文件：

```text
<repo>\.craftling\logs\openclaw.log
```

`pnpm craftling:dev` 是前台运行命令，终端会被占用。可以按 `Ctrl+C` 停止，也可以在另一个终端运行：

```powershell
pnpm craftling:stop
```

该命令会释放 Craftling dev profile 使用的本地端口 `19001` 和 `19003`。

Dashboard/Control UI 优先通过脚本打开：

```powershell
pnpm craftling:dashboard
```

这个命令会使用仓库内的 `.craftling/state/openclaw.json`，并固定连接
`127.0.0.1:19001`。不要直接运行
`node .\openclaw.mjs --profile craftling-dev dashboard`，因为它不会自动带上
Craftling 本地 dev profile 的状态目录、配置路径和端口约定，可能打开到其他端口或
旧 profile。

## 收敛范围

当前 Craftling dev profile 的项目运行数据收敛在仓库内：

```text
<repo>\.craftling\state\openclaw.json
<repo>\.craftling\state\agents\main\sessions\
<repo>\.craftling\workspace\
<repo>\.craftling\logs\openclaw.log
<repo>\.craftling\tmp\
```

仍然不属于 repo 的内容包括 Node、pnpm/Corepack、pnpm store、Windows 临时目录中历史残留日志，以及过去旧 profile 生成过的 C 盘目录。当前 `craftling:*` 命令不会使用旧 C 盘 profile。

## 验证命令

Windows 原生环境可先跑 Windows CI 子集：

```powershell
pnpm test:windows:ci
```

完整快速单测入口是：

```powershell
pnpm test:unit:fast
```

注意：在 Windows 原生环境或中文系统区域设置下，部分 OpenClaw 原始测试可能对路径分隔符或 `Intl` 默认语言敏感。例如 `/tmp`、`/Users/...` 期望 POSIX 路径，或日期格式期望英文星期缩写。这类失败不一定代表 Craftling Gateway/UI baseline 失败。需要判断时，优先结合 `pnpm build`、`pnpm --dir ui run build`、`pnpm craftling:health`、`pnpm craftling:status` 和 `pnpm test:windows:ci` 的结果。

## Windows 原生注意事项

- `@discordjs/opus` 在 Node 24 上可能没有对应预编译包，会尝试 fallback 到本机编译。
- 如果机器没有 Python 或 Visual Studio Build Tools，`@discordjs/opus` 的源码编译可能失败；在当前 dev baseline 中它可能表现为安装 warning，而不是阻断整体安装。
- 如果 `pnpm install` 明确失败在 node-gyp 编译步骤，安装 Python 3 和 Visual Studio Build Tools 后重试。
- OpenClaw 官方仍更推荐 Windows 通过 WSL2 运行；Craftling 当前脚本用于 Windows 原生 dev profile 的最小验证。
