# Craftling 基于 OpenClaw 源码的初步探查

日期：2026-04-20

## 1. 当前结论

当前 `E:\Craftling` 是一个从 OpenClaw fork 而来的大型 TypeScript monorepo。它不是单一前端项目，也不是单一 CLI 项目，而是一个“本地优先个人 AI 助手”平台，核心由 Gateway、CLI、Agent 执行层、多渠道接入、插件系统、Skills、Control UI，以及 macOS/iOS/Android companion apps 组成。

对 Craftling 重构来说，第一阶段的重点不应该先改品牌或 UI，而是先把源码运行基线建立起来：安装依赖、跑通 `pnpm openclaw --help`、跑通 `pnpm openclaw setup` 或最小 Gateway dev loop，再决定保留哪些能力、裁掉哪些能力、重命名哪些边界。

## 2. 本机工作空间状态

- 工作目录：`E:\Craftling`
- 仓库当前分支：`main`
- 远端跟踪：`origin/main`
- 最近确认提交：`c700bfc35d perf(test): slim matrix media fixtures`
- Git 工作区：探查前后均未发现已有未提交改动；本文档是本轮新增文件。
- 本机 Node：`v24.14.1`
- 项目声明的 Node 要求：`>=22.14.0`
- 项目声明的包管理器：`pnpm@10.33.0`
- 当前 shell 中 `pnpm` 不可用。
- 当前未发现 `node_modules`、`dist`、`ui/node_modules`、`ui/dist`。

这意味着：当前源码已经 clone 下来并可阅读，但还没有进入“本机可运行/可构建”的状态。

## 3. 项目定位

OpenClaw README 对产品的核心描述是：用户自己设备上运行的 personal AI assistant。

它的产品形态不是单纯聊天网页，而是：

- 一个长期运行的本地 Gateway，负责控制面。
- 多个控制端，包括 CLI、Control UI、macOS app、移动端 node。
- 多个消息渠道，包括 WhatsApp、Telegram、Slack、Discord、Signal、iMessage、Matrix、Feishu、LINE、QQ、WeChat 等。
- 多个 AI provider 和工具 provider，通过插件/扩展提供能力。
- Agent 运行时负责执行对话、工具调用、会话管理、上下文、skills 和 sandbox。

README 里有一句对架构判断很关键：Gateway 只是 control plane，真正的产品是 assistant。这对 Craftling 重构很重要，因为如果 Craftling 的目标不是“多渠道个人助理平台”，就需要尽早裁剪 Gateway 周边能力，而不是被 OpenClaw 的全量功能牵着走。

## 4. Monorepo 结构

根目录主要结构如下：

- `src/`：核心 TypeScript 源码，包含 CLI、Gateway、Agent、配置、会话、渠道、插件、工具、媒体、Web、TUI 等。
- `extensions/`：内置插件/扩展，每个扩展通常有 `openclaw.plugin.json`，用于声明 provider、渠道、能力、认证方式、配置 schema 等。
- `packages/`：可复用包，目前包括 `plugin-sdk`、`plugin-package-contract`、`memory-host-sdk`。
- `ui/`：Control UI，独立 Vite/Lit 前端项目。
- `apps/`：companion apps，包括 `macos`、`ios`、`android` 和共享代码。
- `skills/`：内置 skills，属于 agent 可加载的任务/工具说明与执行素材。
- `docs/`：产品和开发文档。
- `scripts/`：构建、测试、运行、生成、发布相关脚本。
- `test/`、`test-fixtures/`、`qa/`：测试配置、fixture 和 QA 实验工具。
- `vendor/`：外部或嵌入式依赖素材。

`pnpm-workspace.yaml` 声明的 workspace 包括：

- 根包 `.`
- `ui`
- `packages/*`
- `extensions/*`

注意：`apps/` 没有作为 pnpm workspace 包加入，macOS/iOS 主要是 Swift/Xcode 体系，Android 主要是 Gradle/Kotlin 体系。

## 5. 运行入口和开发命令

根 `package.json` 信息：

- 包名：`openclaw`
- 版本：`2026.4.19-beta.2`
- ESM 项目：`"type": "module"`
- bin：`openclaw -> openclaw.mjs`

发布后的 CLI 入口是根目录 `openclaw.mjs`。这个文件做的事情包括：

- 检查 Node 版本。
- 尝试读取构建产物 `dist/entry.js` 或 `dist/entry.mjs`。
- 如果缺少 `dist/entry`，提示这是未构建源码树，需要执行 `pnpm install && pnpm build`。
- 对 `openclaw --help` 做快速路径优化。

源码开发时更重要的入口是：

- `pnpm openclaw ...`，对应脚本 `node scripts/run-node.mjs`
- `pnpm gateway:watch`，对应脚本 `node scripts/watch-node.mjs gateway --force`
- `pnpm gateway:dev`，对应脚本 `OPENCLAW_SKIP_CHANNELS=1 node scripts/run-node.mjs --dev gateway`
- `pnpm ui:build`，构建 Control UI
- `pnpm ui:dev`，启动 Control UI 开发服务器
- `pnpm build`，执行全量构建
- `pnpm test`，执行项目测试入口
- `pnpm test:fast` / `pnpm test:unit:fast`，更适合早期验证的快速测试入口

README 推荐的源码开发流程是：

```bash
pnpm install
pnpm openclaw setup
pnpm ui:build
pnpm gateway:watch
```

但当前本机还没有 `pnpm`，所以实际下一步需要先启用/安装 pnpm。

## 6. CLI 层

CLI 的启动链路大致是：

```text
openclaw.mjs
  -> dist/entry.js，发布构建后
  -> src/entry.ts，源码构建来源
  -> src/cli/run-main.ts
  -> src/cli/program/build-program.ts
  -> registerProgramCommands(...)
  -> 各命令组懒加载
```

CLI 使用 `commander`。命令注册采用懒加载设计，避免每次启动都导入所有子系统。

核心命令描述位于：

- `src/cli/program/core-command-descriptors.ts`
- `src/cli/program/register.subclis-core.ts`

重要命令包括：

- `setup`：初始化本地配置和 agent workspace。
- `onboard`：交互式 onboarding，配置 Gateway、workspace、channels、skills。
- `configure` / `config`：交互式或非交互式配置。
- `gateway`：启动/管理 Gateway。
- `daemon` / `logs` / `system`：服务化运行与系统集成。
- `doctor` / `health` / `status`：检查和诊断。
- `agent` / `agents`：执行单轮 agent 或管理多 agent。
- `sessions` / `tasks`：会话和后台任务状态。
- `message`：发送、读取和管理消息。
- `channels` / `pairing`：渠道和配对。
- `plugins` / `skills` / `mcp`：扩展能力。
- `nodes` / `devices` / `node`：移动端、桌面端或 headless node 接入。
- `cron` / `hooks` / `webhooks`：自动化。
- `tui` / `dashboard`：用户界面入口。

对 Craftling 来说，CLI 层是重构的第一批入口之一，因为产品命名、命令命名、配置路径、默认行为和 onboarding 都会从这里暴露给用户。

## 7. Gateway 层

Gateway 是 OpenClaw 的核心控制面。源码主要位于：

- `src/gateway/server.ts`
- `src/gateway/server.impl.ts`
- `src/gateway/server-*`
- `src/gateway/protocol`

官方架构文档在：

- `docs/concepts/architecture.md`

Gateway 的核心职责：

- 维护消息渠道/provider 连接。
- 暴露 WebSocket API。
- 暴露 HTTP 辅助接口，包括 Control UI、Canvas、OpenAI-compatible endpoints 等。
- 维护 health、presence、agent event、chat event、cron event 等事件流。
- 管理设备/node 连接和配对。
- 启动插件运行时和渠道运行时。
- 负责配置热重载、认证、限流、TLS/Tailscale/loopback 等访问策略。

默认端口是 `18789`。控制端、Web UI、macOS/iOS/Android nodes 都通过 Gateway 通信。

架构不变量包括：

- 一台 host 上通常只有一个 Gateway。
- WebSocket 第一帧必须是 `connect`。
- Gateway 是单机本地优先控制面，但可以通过 Tailscale、SSH tunnel 或可信代理远程访问。
- 远程访问和非 loopback 连接需要认真处理认证、配对和授权。

对 Craftling 来说，Gateway 是最应该谨慎改的核心。短期建议先保留 Gateway 机制，只收敛配置、默认插件和入口；除非 Craftling 的产品目标明确不需要多端/多渠道/本地常驻能力。

## 8. Agent 层

Agent 相关源码主要在：

- `src/agents/`
- `src/sessions/`
- `src/context-engine/`
- `src/tasks/`
- `src/terminal/`
- `src/process/`
- `src/mcp/`

`src/agents/` 下可以看到这些子模块：

- `auth-profiles`：provider 认证 profile 和轮换。
- `cli-runner`：外部 CLI backend 运行。
- `command`：agent command 编排。
- `harness`：测试/运行 harness。
- `pi-embedded-runner`：嵌入式运行器相关能力。
- `sandbox`：sandbox 策略。
- `schema`：agent 输入输出 schema。
- `skills`：skills 加载和注入。
- `tools`：agent 可调用工具。

Agent 层与 Gateway 的关系是：Gateway 接受控制面请求或渠道消息，然后触发 agent run；agent run 会使用模型 provider、tools、skills、会话历史、上下文和安全策略，最终把事件流和结果回传给 Gateway。

对 Craftling 来说，Agent 层大概率是产品差异化的核心。需要尽早判断：

- Craftling 是继续做通用 assistant，还是聚焦特定任务域？
- 是否保留多模型/provider 切换？
- 是否保留 skills 机制？
- 是否保留 sandbox 和命令执行能力？
- 默认 workspace 和会话模型是否需要改名/改路径？

## 9. Channels 层

渠道相关源码主要在：

- `src/channels/`
- `src/channels/plugins/`
- `extensions/*` 中的具体渠道插件，例如 `discord`、`telegram`、`whatsapp`、`slack`、`wechat` 等。

`src/channels/` 包含通用渠道抽象：

- allowlist、DM policy、mention gating。
- conversation/thread/session 绑定。
- sender identity 和 target 解析。
- typing、status reactions、ack reactions。
- channel config 和 config presence。
- native command session target。

具体渠道实现更多在 `extensions/` 中，核心系统通过插件运行时把它们装配进 Gateway。

对 Craftling 来说，多渠道是 OpenClaw 的重量级能力。如果 Craftling 初期不需要全量渠道，应优先考虑通过默认配置和插件启用策略收敛，而不是立即删除大量扩展代码。

## 10. 插件和扩展系统

插件/扩展是这个仓库的关键边界。相关位置：

- `extensions/`
- `src/plugins/`
- `packages/plugin-sdk`
- `packages/plugin-package-contract`

每个扩展通常有 `openclaw.plugin.json`。例如 `extensions/openai/openclaw.plugin.json` 声明了：

- 插件 id：`openai`
- 是否默认启用。
- provider：`openai`、`openai-codex`
- model prefix 支持。
- CLI backend：`codex-cli`
- 认证方式：OAuth 或 API key。
- 可提供的能力 contract：speech、realtime transcription、realtime voice、memory embedding、media understanding、image/video generation 等。
- 插件自己的 config schema。

`src/plugins/` 则提供插件发现、manifest 校验、运行时、CLI 注册、capability provider、channel registry、config policy、contracts、bundled plugin metadata 等基础设施。

对 Craftling 来说，插件系统是一个值得保留的扩展点。重构时建议先设计 Craftling 的“默认插件集合”和“必须支持的 capability contract”，而不是直接把插件系统改散。

## 11. Control UI

Control UI 位于：

- `ui/`

`ui/package.json` 显示它是一个私有 Vite 项目，技术栈主要包括：

- Vite
- Lit
- Vitest
- Playwright browser testing
- Markdown rendering/sanitization 相关依赖

根脚本提供：

- `pnpm ui:build`
- `pnpm ui:dev`
- `pnpm ui:install`
- `pnpm test:ui`

Gateway 会根据配置提供 Control UI，并处理 Control UI 的 CSP、路由、token、origin 等。

对 Craftling 来说，UI 是品牌和产品体验最明显的地方，但它依赖 Gateway API、认证、配置和 agent/session 模型。建议在跑通 Gateway 后再重构 UI，否则容易只改了外壳，后端语义仍然是 OpenClaw。

## 12. Companion Apps

`apps/` 包含：

- `apps/macos`：Swift Package，包含 macOS menu bar、Gateway 控制、Canvas、Voice Wake、调试工具等。
- `apps/ios`：iOS node。
- `apps/android`：Android node，Gradle/Kotlin 项目。
- `apps/shared`：共享 Swift/OpenClawKit 等。

README 说明这些 apps 是可选增强能力，Gateway 单独运行也可用。

对 Craftling 初期重构来说，apps 建议先当作外围能力保留，不作为第一阶段改造重点。除非 Craftling 的核心产品就是桌面/移动 companion app。

## 13. Skills

`skills/` 下有大量内置 skills，例如：

- `coding-agent`
- `github`
- `obsidian`
- `notion`
- `weather`
- `slack`
- `canvas`
- `taskflow`
- `summarize`

这些 skills 是 agent 能力和具体用户任务之间的桥梁。它们更像“产品技能包”，不一定是核心运行时代码。

对 Craftling 来说，skills 是低风险的产品定制入口：可以新增 Craftling 专属 skills，也可以逐步禁用不需要的内置 skills。

## 14. 配置系统

配置相关源码主要在：

- `src/config/`

这个目录非常关键，包含：

- config schema、defaults、io、env substitution。
- agent dirs、agent limits、channel config、plugin validation。
- group policy、gateway control UI origins、secrets schema。
- 生成的 bundled channel config metadata。

很多产品默认行为都藏在配置层：默认端口、默认启用插件、渠道策略、sandbox 策略、agent workspace、secrets、control UI 访问策略等。

对 Craftling 重构来说，配置系统应该是第一批重点阅读对象。产品换名、默认路径、默认启用能力、onboarding 表单、环境变量前缀，都可能从这里开始。

## 15. 当前还没有做的事

初次探查时只是源码探查和文档整理，没有执行依赖安装、构建或启动。随后已按 dev baseline 路线补齐本地运行条件。

已完成：

- 通过 Corepack 激活 `pnpm@10.33.0`，当前可用入口是 `corepack pnpm ...`。
- 执行 `corepack pnpm install`，安装 106 个 workspace project 的依赖。
- 执行 `corepack pnpm openclaw --help`，源码版 CLI 可启动。
- 执行 `corepack pnpm openclaw --dev onboard --non-interactive --accept-risk --mode local --auth-choice skip --skip-channels --skip-daemon --skip-search --skip-health --no-install-daemon --json`，已初始化隔离 dev profile。
- 执行 `corepack pnpm --dir ui run build`，Control UI 已构建到 `dist/control-ui`。
- 执行 `$env:OPENCLAW_SKIP_CHANNELS='1'; corepack pnpm openclaw --dev gateway --verbose`，dev Gateway 已以前台方式启动。
- `corepack pnpm openclaw --dev health --json` 返回 `ok: true`。
- `corepack pnpm openclaw --dev gateway status --json` 确认 Gateway 监听 `ws://127.0.0.1:19001`。

当前 dev baseline 已迁移为 Craftling repo 内路径：

- dev 配置文件：`E:\Craftling\.craftling\state\openclaw.json`
- dev workspace：`E:\Craftling\.craftling\workspace`
- dev sessions：`E:\Craftling\.craftling\state\agents\main\sessions`
- Gateway bind：`127.0.0.1`
- Gateway port：`19001`
- Gateway URL：`ws://127.0.0.1:19001`
- channels：`{}`
- daemon：未安装/未运行，这是当前阶段的预期状态。

注意：

- 新增了 `scripts/craftling-setup.ps1` 和 `scripts/craftling-dev.ps1`，用于复现 repo 内本地运行路径。
- 新增了 `docs/craftling-local-dev.zh-CN.md`，说明哪些配置/脚本应提交、哪些本机运行数据应忽略。
- `.craftling/state/`、`.craftling/workspace/`、`.craftling/logs/`、`.craftling/tmp/` 已加入 `.gitignore`，运行数据留在 repo 空间内但不提交。
- 由于当前 PowerShell PATH 中没有裸 `pnpm` 命令，根脚本 `pnpm ui:build` 会因为找不到 UI runner 失败；可用替代命令是 `corepack pnpm --dir ui run build`。
- `corepack pnpm install` 期间 `@discordjs/opus` 没有 Node 24 预编译包，已自动 fallback 到本机 VS/Python 编译并成功完成。
- 当前 Git 状态只显示新增未跟踪文档 `CRAFTLING_OPENCLAW_SOURCE_SURVEY.zh-CN.md`；依赖和构建产物未作为 Git 改动出现。

## 16. 建议下一步

建议下一步按下面顺序建立运行基线：

1. 启用 pnpm。优先尝试 `corepack enable` 和 `corepack prepare pnpm@10.33.0 --activate`，因为项目已经声明了 pnpm 版本。
2. 执行 `pnpm install`。
3. 执行 `pnpm openclaw --help`，确认源码 CLI 能启动。
4. 执行 `pnpm openclaw setup`，建立本地配置和 workspace。
5. 执行 `pnpm ui:build`，预构建 Control UI。
6. 执行 `pnpm gateway:dev` 或 `pnpm gateway:watch`，启动最小 Gateway。
7. 执行 `pnpm openclaw health` 或 Gateway 相关 probe，确认本地控制面可用。
8. 再执行一组快速测试，例如 `pnpm test:unit:fast` 或更小范围的 Gateway/CLI 测试。

如果这些步骤能跑通，就可以形成 Craftling 重构前的 baseline。之后再进入第二阶段：

- 明确 Craftling 产品目标。
- 制定保留/裁剪模块清单。
- 决定命名、配置路径、默认插件、默认 UI 的重构策略。
- 从 CLI/onboarding/config/defaults 这些用户入口开始小步改造。

## 17. 初步重构优先级建议

第一优先级：运行基线

- pnpm、依赖、CLI、Gateway、Control UI 构建。
- 明确 Windows 原生运行与 WSL2 推荐路径之间的差异。

第二优先级：产品入口

- CLI 命名和帮助文案。
- onboarding/setup/config 默认项。
- 默认启用插件和 provider。
- 默认 workspace/config/secrets 路径。

第三优先级：核心能力收敛

- Gateway 保留到什么程度。
- Agent runner、skills、tools、sessions 是否继续沿用。
- 多渠道是否先通过配置禁用，只保留少数目标渠道。

第四优先级：体验层

- Control UI 品牌和信息架构。
- macOS/iOS/Android apps 是否进入 Craftling 第一阶段。
- docs/README/VISION 统一改写。

第五优先级：深层重构

- 删除不需要的 provider/channel 扩展。
- 重塑插件 contract。
- 重写架构边界或拆包。

当前最稳妥的路线是：先跑通，再收敛默认行为，再做品牌和产品语义替换，最后才考虑删除大模块。
