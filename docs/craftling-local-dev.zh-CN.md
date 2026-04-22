# Craftling 本地开发命令

本文记录 Craftling fork 的本地运行约定。目标是把 OpenClaw/Craftling 的运行状态放在仓库工作空间内，同时避免把个人运行数据提交到 Git。

## 快速命令

在仓库根目录执行：

```powershell
cd E:\Craftling
```

初始化本地配置：

```powershell
pnpm craftling:setup
```

如果是刚 clone 的源码树，先执行一次：

```powershell
pnpm install
pnpm build
pnpm --dir ui run build
```

启动 dev Gateway：

```powershell
pnpm craftling:dev
```

查看健康状态：

```powershell
pnpm craftling:health
```

查看 Gateway 状态：

```powershell
pnpm craftling:status
```

停止 Gateway：

```powershell
pnpm craftling:stop
```

构建 Control UI：

```powershell
pnpm --dir ui run build
```

## 路径约定

本地运行数据放在：

```text
E:\Craftling\.craftling\
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
scripts/craftling-stop.ps1
```

这些脚本内部会统一设置：

```text
OPENCLAW_PROFILE=craftling-dev
OPENCLAW_STATE_DIR=E:\Craftling\.craftling\state
OPENCLAW_CONFIG_PATH=E:\Craftling\.craftling\state\openclaw.json
OPENCLAW_GATEWAY_PORT=19001
OPENCLAW_SKIP_CHANNELS=1
```

因此日常使用时不需要手动输入环境变量。

## Gateway

默认监听：

```text
ws://127.0.0.1:19001
```

该模式不会连接真实消息渠道，也不会安装 daemon。

日志文件：

```text
E:\Craftling\.craftling\logs\openclaw.log
```

`pnpm craftling:dev` 是前台运行命令，终端会被占用。可以按 `Ctrl+C` 停止，也可以在另一个终端运行：

```powershell
pnpm craftling:stop
```

## 收敛范围

当前 Craftling dev profile 的项目运行数据收敛在仓库内：

```text
E:\Craftling\.craftling\state\openclaw.json
E:\Craftling\.craftling\state\agents\main\sessions\
E:\Craftling\.craftling\workspace\
E:\Craftling\.craftling\logs\openclaw.log
E:\Craftling\.craftling\tmp\
```

仍然不属于 repo 的内容包括 Node、pnpm/Corepack、pnpm store、Windows 临时目录中历史残留日志，以及过去旧 profile 生成过的 C 盘目录。当前 `craftling:*` 命令不会使用旧 C 盘 profile。
