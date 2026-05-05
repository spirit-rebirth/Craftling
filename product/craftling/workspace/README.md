# CraftlingClaw

OpenClaw workspace and Unreal AgentBridge tooling for the Craftling UE workflow.

This repo is meant to be cloned as an OpenClaw workspace. It contains reusable OpenClaw skills, Lobster pipeline templates, and the local Unreal AgentBridge plugin. Machine-specific OpenClaw state stays outside git.

## Repository Layout

- `skills/`: OpenClaw skills used by the Unreal workflow.
- `skills/ue-full-loop/`: Lobster-driven build, editor, placement, PIE, evidence, and approval workflow.
- `plugins/openclaw-unreal-agentbridge/`: OpenClaw plugin that registers UE tools such as `ue_build`, `ue_editor_open`, `ue_spawn_actor`, `ue_pie_start`, and `ue_logs_tail`.
- `examples/openclaw.example.json`: Local OpenClaw config template. Copy the relevant fields into your own `~/.openclaw/openclaw.json`.

## Local OpenClaw Configuration

Each machine must point OpenClaw at its local clone path and local Unreal installation. Do not commit real `~/.openclaw/openclaw.json` files because they can contain auth state and machine-specific paths.

Minimal values to configure:

```json
{
  "agents": {
    "defaults": {
      "workspace": "<absolute path to this CraftlingClaw repo>"
    }
  },
  "plugins": {
    "load": {
      "paths": [
        "<absolute path to this CraftlingClaw repo>\\plugins\\openclaw-unreal-agentbridge"
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
          "buildBat": "<absolute path to Unreal Engine Build.bat>",
          "projectFile": "<absolute path to your .uproject>",
          "defaultBuildTarget": "<UnrealEditorTargetName>",
          "defaultBuildPlatform": "Win64",
          "defaultBuildConfiguration": "Development",
          "editorExe": "<absolute path to UnrealEditor.exe>"
        }
      }
    }
  }
}
```

The paths above are examples. Replace them with paths from the current machine.

## Lobster

Lobster is enabled in local OpenClaw config, not by committing `~/.lobster` state. The reusable workflow lives in `skills/ue-full-loop/ue-full-loop.registered.pipeline.md`.

When expanding the registered pipeline, replace:

- `__PROGRESS_FILE__` with the runtime JSONL progress path supplied by the backend.

The registered pipeline uses relative script paths. Call the Lobster tool with `cwd: "product/craftling/workspace"` from the Craftling repo. Do not pass an absolute `cwd`; Lobster intentionally rejects absolute cwd values.

Do not commit `~/.lobster/state`. It contains approval tokens and resume data from previous runs.

## Runtime Artifacts

These are intentionally ignored:

- `.craftling-progress/`
- `.craftling-evidence/`
- `.openclaw/`
- `.lobster/`
- `state/`
- `memory/.dreams/`

They are generated during local runs and are not needed to reproduce the workflow on a new machine.

## Backend Link

The backend can discover this repo automatically when the backend repo and this repo are cloned as sibling directories. For example, both of these layouts work without setting `OPENCLAW_WORKDIR`:

```text
<workspace-root>/PythonContent
<workspace-root>/UEClaw
```

```text
<workspace-root>/PythonContent
<workspace-root>/CraftlingClaw
```

If this repo is not a sibling of the backend repo, set one of these environment variables to this repo's absolute path:

```env
OPENCLAW_WORKDIR=<absolute path to this CraftlingClaw repo>
```

The backend defaults to its repo-local ACP bridge at `tools/openclaw_acp_bridge.mjs`. Override `OPENCLAW_ACP_BRIDGE` only if you intentionally keep the bridge somewhere else.

Keep `OPENCLAW_SESSION_KEY=agent:main:main` unless the OpenClaw agent id changes.

## Rollback

This repo can be introduced without changing the currently running OpenClaw setup. To test it locally, update `~/.openclaw/openclaw.json` to point `workspace` and the `plugins.load.paths` entry at this clone. To roll back, restore those two values to the previous workspace and plugin path.
