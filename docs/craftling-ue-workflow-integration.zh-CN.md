# Craftling UE 工作流整合说明

本文说明如何把旧 UE workflow repo 中的 Lobster、UE skills、AgentBridge OpenClaw 插件和 agent 工作空间内容，整合进新的 Craftling fork，使 `<Craftling repo>` 成为唯一产品 repo。

适用前提：

- 新电脑上已经 clone 并跑通 `<Craftling repo>` baseline
- 新电脑上已经 clone `<legacy UE workflow repo>`
- Unreal 项目 repo 存在，例如 `<Unreal project repo>`
- Unreal 项目内的 UE 插件 `Plugins/AgentBridge` 已经更新

## 目标状态

整合后，Craftling repo 内应该包含：

```text
<Craftling repo>\
  product\
    craftling\
      workspace\
        AGENTS.md
        BOOTSTRAP.md
        HEARTBEAT.md
        IDENTITY.md
        ORCHESTRATION.md
        SOUL.md
        TOOLS.md
        USER.md
        skills\
          ue-build\
          ue-code-gen\
          ue-editor\
          ue-full-loop\
          ue-play-test\
      plugins\
        openclaw-unreal-agentbridge\
      examples\
        openclaw.example.json
```

Craftling dev runtime 仍然使用：

```text
<Craftling repo>\.craftling\
  state\
  workspace\
  logs\
  tmp\
```

`.craftling/` 是本机运行态，不提交。

## 迁移原则

不要直接替换 OpenClaw 原生目录：

```text
<Craftling repo>\skills\
<Craftling repo>\src\
<Craftling repo>\docs\
```

旧 UE 工作流先作为 Craftling 的产品工作空间放入：

```text
<Craftling repo>\product\craftling\workspace
```

原因：

- `<Craftling repo>` 根目录仍然是 runtime 源码
- `product/craftling/workspace` 是 Craftling 产品人格、skills、workflow
- `product/craftling/plugins` 是 Craftling 产品插件
- 这样既能让 agent 使用 UE 工作流，又不会污染 OpenClaw upstream 结构

## 第一步：复制旧 UE 工作空间内容

从：

```text
<legacy UE workflow repo>
```

复制这些文件到：

```text
<Craftling repo>\product\craftling\workspace
```

需要复制：

```text
AGENTS.md
BOOTSTRAP.md
HEARTBEAT.md
IDENTITY.md
ORCHESTRATION.md
SOUL.md
TOOLS.md
USER.md
skills\
```

不要复制：

```text
.craftling-progress\
.craftling-evidence\
.openclaw\
.lobster\
state\
memory\.dreams\
```

这些是运行态或历史产物。

## 第二步：复制 OpenClaw 侧 UE 插件

从：

```text
<legacy UE workflow repo>\plugins\openclaw-unreal-agentbridge
```

复制到：

```text
<Craftling repo>\product\craftling\plugins\openclaw-unreal-agentbridge
```

这个插件负责向 Craftling/OpenClaw 注册 UE 工具，例如：

- `ue_health`
- `ue_build`
- `ue_editor_open`
- `ue_spawn_actor`
- `ue_pie_start`
- `ue_pie_stop`
- `ue_logs_tail`
- `ue_test_status`
- `ue_test_results`

## 第三步：复制示例配置

从：

```text
<legacy UE workflow repo>\examples\openclaw.example.json
```

复制到：

```text
<Craftling repo>\product\craftling\examples\openclaw.example.json
```

这个文件只作为模板提交，不存放真实 token 或本机授权状态。

## 第四步：更新 Craftling setup

目标是让：

```powershell
pnpm craftling:setup
```

生成的配置默认指向 repo 内产品工作空间和插件。

目标配置应包含：

```json
{
  "agents": {
    "defaults": {
      "workspace": "<Craftling repo>\\product\\craftling\\workspace"
    }
  },
  "plugins": {
    "load": {
      "paths": [
        "<Craftling repo>\\product\\craftling\\plugins\\openclaw-unreal-agentbridge"
      ]
    },
    "entries": {
      "lobster": {
        "enabled": true
      },
      "unreal-agentbridge": {
        "enabled": true,
        "config": {
          "baseUrl": "http://127.0.0.1:8080",
          "buildBat": "<Unreal Engine Build.bat absolute path>",
          "projectFile": "<Craftling repo>Demo\\UnrealClaw\\ClawTestProject.uproject",
          "defaultBuildTarget": "ClawTestProjectEditor",
          "defaultBuildPlatform": "Win64",
          "defaultBuildConfiguration": "Development",
          "editorExe": "<UnrealEditor.exe absolute path>"
        }
      }
    }
  }
}
```

注意：

- `buildBat` 和 `editorExe` 是每台机器自己的路径
- 不要把真实机器路径写死到通用模板里
- 可以在 `craftling:setup` 中为当前机器生成实际路径
- 也可以先手工编辑 `.craftling/state/openclaw.json` 做验证

## 第五步：确认 product 目录进入 Git

应该提交：

```text
product/craftling/workspace/AGENTS.md
product/craftling/workspace/*.md
product/craftling/workspace/skills/**
product/craftling/plugins/openclaw-unreal-agentbridge/**
product/craftling/examples/openclaw.example.json
docs/craftling-ue-workflow-integration.zh-CN.md
```

不应该提交：

```text
.craftling/**
product/craftling/workspace/.craftling-progress/**
product/craftling/workspace/.craftling-evidence/**
product/craftling/workspace/.openclaw/**
product/craftling/workspace/.lobster/**
product/craftling/workspace/state/**
```

如果需要，更新 `.gitignore`：

```gitignore
product/craftling/workspace/.craftling-progress/
product/craftling/workspace/.craftling-evidence/
product/craftling/workspace/.openclaw/
product/craftling/workspace/.lobster/
product/craftling/workspace/state/
product/craftling/workspace/memory/.dreams/
```

## 第六步：重建并重启 Craftling

在 `<Craftling repo>` 执行：

```powershell
pnpm build
pnpm --dir ui run build
pnpm craftling:setup
pnpm craftling:stop
pnpm craftling:dev
```

另开一个终端：

```powershell
cd <Craftling repo>
pnpm craftling:health
pnpm craftling:status
```

## 第七步：确认插件加载

在 `<Craftling repo>` 执行：

```powershell
node openclaw.mjs --profile craftling-dev plugins list
```

确认至少能看到：

```text
lobster
unreal-agentbridge
```

检查插件详情：

```powershell
node openclaw.mjs --profile craftling-dev plugins inspect unreal-agentbridge
```

## 第八步：确认 UE AgentBridge 可用

打开 Unreal 项目：

```text
<Unreal project repo>\ClawTestProject.uproject
```

确认 UE 内部 `AgentBridge` 插件启用。

检查 HTTP 服务：

```powershell
curl http://127.0.0.1:8080/api/health
```

预期返回类似：

```json
{
  "status": "ok",
  "plugin": "AgentBridge"
}
```

## 第九步：测试 Craftling 调用 UE 工具

在 `<Craftling repo>` 执行：

```powershell
node openclaw.mjs --profile craftling-dev agent --agent main --message "检查 Unreal AgentBridge 是否可用。只调用 ue_health，不要做其他事。"
```

预期：

- agent 能识别 UE 工具
- 能调用 `ue_health`
- 返回 AgentBridge ok

## 第十步：测试 Lobster UE full-loop

使用一个小任务：

```powershell
node openclaw.mjs --profile craftling-dev agent --agent main --message "创建一个简单 Unreal Actor 类 TestCraftlingLobster001，并严格按 ue-full-loop 完成 build、打开编辑器、放置、PIE、收集证据。"
```

预期行为：

- agent 先分析和实现
- 然后必须进入 `lobster`
- 不应直接用 UE tools 代替 Lobster deterministic stages
- 到 approval gate 时应停下来等待人工批准
- 批准后继续 PIE、evidence、stop、evaluate

如果 agent 直接调用 UE tools 而没有进入 Lobster，优先检查：

- `product/craftling/workspace/AGENTS.md`
- `product/craftling/workspace/skills/ue-full-loop/SKILL.md`
- `agents.defaults.workspace`

## 第十一步：更新文档和记忆

整合完成后，更新：

```text
<Craftling repo>\docs\craftling-local-dev.zh-CN.md
C:\Users\李臻\.codex\memories\craftling-openclaw-rebuild-memory.md
```

记录：

- UE workflow 已迁入 `product/craftling`
- dev config 默认指向 repo 内 product workspace
- 插件路径默认指向 repo 内 product plugin
- 验证过的命令和结果

## 最终判断

完成以上步骤后，`<Craftling repo>` 就不再只是 OpenClaw fork runtime，而是包含 Craftling 产品工作空间、UE skills、Lobster workflow 和 UE OpenClaw 插件的唯一产品 repo。

仍然外置的是：

- Unreal 项目 repo：`<Unreal project repo>`
- Unreal Engine 安装目录
- 本机运行态 `.craftling/`
- 本机 approval/session/token/evidence/progress

这些内容不应合并进 Craftling 产品 repo。
