# Craftling 本地开发指南

这份文档面向新机器上的开发者。目标是：从零拉下 Craftling repo，安装开发依赖，配置 LLM，然后跑通当前 baseline，包括 Gateway、原 OpenClaw Dashboard，以及 Craftling Flutter 前端。

当前 repo 是开发仓库，不是最终用户 release 包。开发者需要安装 Node.js、pnpm、Flutter 等工具；未来 release 版本应尽量把构建产物和启动流程封装好，让普通用户不需要安装这些开发环境。

## 1. 环境要求

必需：

- Git
- PowerShell
- Node.js，建议使用官方安装包。项目要求 Node `>=22.14.0`
- pnpm `10.33.0`
- Flutter SDK
- Windows 桌面 Flutter 依赖，例如 Visual Studio 的 Desktop development with C++
- Chrome，只有运行 `craftling:flutter:web` 时需要

推荐安装官方 Node.js，而不是只带 `node.exe` 的临时运行时。官方 Node.js 会包含 npm 和 corepack，后续安装 pnpm 更顺。

确认 Node：

```powershell
node -v
npm -v
corepack -v
```

如果 PowerShell 提示 `npm.ps1` 或 `pnpm.ps1` 因执行策略被禁止，可以使用 `.cmd` 形式：

```powershell
npm.cmd -v
pnpm.cmd -v
corepack.cmd -v
```

启用 pnpm：

```powershell
corepack.cmd enable
corepack.cmd prepare pnpm@10.33.0 --activate
pnpm.cmd -v
```

如果 `corepack enable` 因为没有管理员权限而无法写入 `C:\Program Files\nodejs\pnpm`，可以用管理员 PowerShell 执行，或者先通过 corepack 临时调用 pnpm。当前文档里的命令统一使用 `pnpm.cmd`，在 Windows PowerShell 下更稳。

确认 Flutter：

```powershell
flutter --version
flutter doctor
```

如果 Flutter 不在 PATH 中，可以把 Flutter SDK 的 `bin` 目录加入用户 PATH。例如 SDK 位于 `D:\FlutterContent\flutter` 时，需要加入：

```text
D:\FlutterContent\flutter\bin
```

也可以临时设置：

```powershell
$env:FLUTTER_ROOT='D:\FlutterContent\flutter'
```

## 2. 拉取和安装

克隆仓库：

```powershell
cd D:\GitHubContent
git clone https://github.com/spirit-rebirth/Craftling.git
cd D:\GitHubContent\Craftling
```

安装 Node 依赖：

```powershell
pnpm.cmd install
```

构建 OpenClaw/Craftling 后端和原 Web UI：

```powershell
pnpm.cmd build
pnpm.cmd --dir ui run build
```

初始化 Craftling 本地 dev profile：

```powershell
pnpm.cmd craftling:setup
```

这个命令会把本地运行状态放在 repo 内的 `.craftling` 目录下，而不是写入旧的全局 profile。

## 3. 配置 LLM

当前 baseline 可以使用 OpenAI Codex OAuth，也可以使用 API key。推荐先用 OpenClaw 的 onboard/configure 流程完成登录或配置。

如果你在需要代理的网络环境中，先在启动 Gateway 或执行 OAuth 配置前设置代理：

```powershell
$env:HTTP_PROXY='http://127.0.0.1:7890'
$env:HTTPS_PROXY='http://127.0.0.1:7890'
$env:ALL_PROXY='http://127.0.0.1:7890'
```

配置 LLM 前，先确认使用 repo 内的 Craftling dev profile 状态目录：

```powershell
$env:OPENCLAW_PROFILE='craftling-dev'
$env:OPENCLAW_STATE_DIR=(Resolve-Path .\.craftling\state).Path
$env:OPENCLAW_CONFIG_PATH=(Join-Path $env:OPENCLAW_STATE_DIR 'openclaw.json')
$env:OPENCLAW_GATEWAY_PORT='19001'
```

然后配置 LLM：

```powershell
node .\openclaw.mjs --profile craftling-dev onboard
```

如果选择 OpenAI Codex OAuth，配置成功后默认模型应类似：

```text
openai-codex/gpt-5.4
```

注意：如果已经通过 OpenAI Codex OAuth 登录，就应该使用 `openai-codex/...` 模型；如果使用 `openai/...` 模型，则需要设置 `OPENAI_API_KEY`。配置完成后应更新：

```text
<repo>\.craftling\state\openclaw.json
```

## 4. 启动顺序

推荐 baseline 验证顺序：

1. 启动 Gateway
2. 用原 OpenClaw Dashboard 验证 Gateway 和 LLM
3. 启动 Craftling Flutter 前端
4. 发一条消息，确认流式回复和 task 状态
5. 停止 Gateway

启动 Gateway：

```powershell
pnpm.cmd craftling:dev
```

这个命令会占用当前终端。它默认监听：

```text
127.0.0.1:19001
```

另开一个 PowerShell，查看状态：

```powershell
pnpm.cmd craftling:health
pnpm.cmd craftling:status
```

打开原 OpenClaw Dashboard：

```powershell
pnpm.cmd craftling:dashboard
```

启动 Craftling Flutter Windows 桌面端：

```powershell
pnpm.cmd craftling:flutter
```

或者显式指定 Windows：

```powershell
pnpm.cmd craftling:flutter:windows
```

启动 Craftling Flutter Web：

```powershell
pnpm.cmd craftling:flutter:web
```

停止 Gateway：

```powershell
pnpm.cmd craftling:stop
```

如果 Gateway 是用管理员权限启动的，普通权限的终端可能无法停止对应进程。这种情况下，用同样的管理员权限运行 `pnpm.cmd craftling:stop`。

## 5. 命令合集

Craftling 本地开发命令：

```powershell
pnpm.cmd craftling:setup
pnpm.cmd craftling:dev
pnpm.cmd craftling:health
pnpm.cmd craftling:status
pnpm.cmd craftling:dashboard
pnpm.cmd craftling:flutter
pnpm.cmd craftling:flutter:windows
pnpm.cmd craftling:flutter:web
pnpm.cmd craftling:stop
```

构建和测试命令：

```powershell
pnpm.cmd build
pnpm.cmd --dir ui run build
pnpm.cmd test:unit:fast
pnpm.cmd test:windows:ci
```

Flutter 子项目命令：

```powershell
cd D:\GitHubContent\Craftling\apps\craftling_flutter
flutter pub get
flutter test
flutter run -d windows
flutter run -d chrome
```

## 6. 路径和状态约定

Craftling dev profile 的本地状态在：

```text
<repo>\.craftling\
  state\       # config、tokens、sessions 等
  workspace\   # agent workspace
  logs\        # 本地日志
  tmp\         # 临时文件
```

这些目录是每台机器自己的运行状态，不应提交到 Git。里面可能包含：

- gateway token
- OAuth token
- API key 或 SecretRef
- session 历史
- 本机绝对路径
- 日志和缓存

Flutter 前端源码在：

```text
<repo>\apps\craftling_flutter\
```

不要提交 Flutter 生成的本地缓存或构建产物，例如：

```text
apps\craftling_flutter\.dart_tool\
apps\craftling_flutter\build\
```

这些已经由 Flutter 子项目的 `.gitignore` 忽略。

## 7. Gateway 和前端入口

原 OpenClaw Dashboard 使用原生 WebSocket 入口：

```text
ws://127.0.0.1:19001/ws
```

Craftling Flutter 前端使用新增的 adapter 入口：

```text
ws://127.0.0.1:19001/__craftling__/ws
```

这两个入口同时存在，不需要切换。原 Dashboard 保留为验证工具；Flutter 前端走 Craftling adapter，用于产品界面开发。

Flutter app 默认可以填写或使用：

```text
http://127.0.0.1:19001
```

前端会把这个 Gateway base URL 转成 Craftling adapter WebSocket URL。

## 8. 常见问题

### PowerShell 为什么要用 `.cmd`

Windows 上 `npm`、`pnpm`、`corepack` 可能同时存在 `.ps1` 和 `.cmd` shim。PowerShell 执行策略可能禁止 `.ps1` 脚本运行，从而报：

```text
无法加载文件 ... npm.ps1，因为在此系统上禁止运行脚本
```

使用 `npm.cmd`、`pnpm.cmd`、`corepack.cmd` 可以绕开 PowerShell 脚本执行策略。

### Flutter 命令每次都会重新 build 吗

`pnpm.cmd craftling:flutter` 底层会执行：

```powershell
flutter pub get
flutter run -d windows
```

它是开发运行命令。Flutter 每次会检查依赖和构建状态；第一次通常较慢，后续通常是增量构建，不是每次都从零开始。

退出 Flutter app 时，可以关闭 app 窗口。如果终端仍被占用，可以按：

```text
Ctrl+C
```

### Dashboard 提示没有 API key

如果使用 OpenAI Codex OAuth，需要确认模型是 `openai-codex/...`，而不是 `openai/...`。`openai/...` provider 需要 `OPENAI_API_KEY`。

### Gateway token missing

如果 Dashboard 提示：

```text
unauthorized: gateway token missing
```

优先使用：

```powershell
pnpm.cmd craftling:dashboard
```

不要直接运行不带环境约定的 dashboard 命令。`craftling:dashboard` 会使用 repo 内 `.craftling\state\openclaw.json` 和固定的 `craftling-dev` profile。

### stop 命令停不掉 Gateway

如果 Gateway 是管理员权限启动的，普通权限 `craftling:stop` 可能无法结束进程。请在管理员 PowerShell 中运行：

```powershell
pnpm.cmd craftling:stop
```

### 什么时候需要重新 build

修改 TypeScript 源码或 Gateway adapter 后，需要重新构建：

```powershell
pnpm.cmd build
```

修改原 OpenClaw Web UI 后，需要重新构建 UI：

```powershell
pnpm.cmd --dir ui run build
```

修改 Flutter 前端后，直接重新运行：

```powershell
pnpm.cmd craftling:flutter
```
