---
name: ue-full-loop
description: "Execute the full Unreal implement-build-open-editor-place-PIE-verify-retry loop for tasks that must be implemented and then proven to work in-engine."
---
# Skill: UE Full Development Loop

You are running a complete Unreal implementation-and-verification loop.

Use this skill when the user is asking for a UE feature to be implemented and then verified in-engine, especially requests like:
- write an actor/component/system and make sure it works
- add code, build it, open the editor, place it in the level, run PIE, and verify the result
- keep iterating until the Unreal-side behavior passes or the retry budget is exhausted

Do not use this skill for simple one-step requests like:
- check bridge health
- list actors
- spawn a basic actor once
- open the editor only
- start or stop PIE only

## Response Contract

During this skill, every substantive progress reply must start with exactly these three lines:
- `Stage: <stage name>`
- `Skill: ue-full-loop`
- `Tool: <tool name or comma-separated tool names>`

If no tool has been called yet for that stage, use:
- `Tool: none yet`

Keep the rest of the update concise and factual.

## Current Environment

The OpenClaw workspace, Unreal project path, Unreal Engine path, and build target are machine-specific. They must be supplied by each machine's local `~/.openclaw/openclaw.json` using the `unreal-agentbridge` plugin config. See `examples/openclaw.example.json` in the CraftlingClaw repo.

Preferred compile policy: CLI build with the editor closed, then reopen the editor for testing

## Mandatory Execution Rule

For implementation-and-verification requests, you are responsible for:
- Stage 1: analyze
- Stage 2: write or edit source files
- then handing off all remaining stages to the registered `lobster` tool

Do not call `ue_build`, `ue_editor_open`, `ue_health`, `ue_spawn_actor`, `ue_pie_start`, `ue_pie_stop`, or other direct UE tools yourself after Stage 2.

Those direct UE tools are the tool surface used inside the deterministic Lobster workflow. If you call them directly for this full-loop skill, you have bypassed Lobster and the workflow is invalid.

If the registered `lobster` tool is not available, use the wrapper-script fallback described in the Lobster section. Do not silently continue with direct UE tools.

## Tool Surface Reference

Primary deterministic workflow tool:
- `lobster`

Direct UE tools used by the Lobster workflow and by simple `ue-direct` one-step requests only:
- `ue_build`
- `ue_editor_open`
- `ue_health`
- `ue_world_query`
- `ue_list_actors`
- `ue_spawn_actor`
- `ue_modify_actor`
- `ue_delete_actor`
- `ue_pie_start`
- `ue_pie_status`
- `ue_pie_stop`
- `ue_logs_tail`
- `ue_test_status`
- `ue_test_results`

Do not use `ue_live_compile` in this workflow.

## Loop Contract

Run the stages in order. Do not skip verification.

### Stage 1: Analyze

Before changing code, produce a short internal plan:
- what class or files need to be created or modified
- what Unreal-side behavior should prove success
- what evidence will count as verification

Preferred verification evidence, in order:
1. `ue_test_status` + `ue_test_results`
2. structured logs via `ue_logs_tail`
3. if neither is available, a narrowly scoped observable Unreal-side signal

### Stage 2: Implement

Write or edit the C++ files needed for the task.

Implementation requirements:
- follow Unreal naming and include conventions
- keep logs structured when runtime observability is needed
- for runtime verification by logs, prefer lines prefixed with `[AgentTest]`
- if the task needs per-frame confirmation, emit a narrow, machine-checkable log format instead of vague prose

### Stage 3: Build

Default path:
- call the registered `lobster` tool with the expanded `ue-full-loop.registered.pipeline.md` text
- Lobster will perform build, editor launch, bridge wait, placement, PIE, verification, cleanup, and approval gates

Rules:
- do not call `ue_build` directly in this full-loop skill
- do not claim success until Lobster reaches runtime verification and PIE cleanup
- if Lobster reports a build failure, use the actual compiler output to guide the next source fix, then re-run Lobster from scratch
- do not use `ue_live_compile`

### Stage 4: Open Editor

After a successful build:
- call `ue_editor_open`
- launch the configured project

Rules:
- do not assume the editor is ready immediately after process launch
- if launch fails, report the actual launcher error and stop

### Stage 5: Wait For Bridge

After editor launch:
- poll `ue_health` until AgentBridge is reachable
- if needed, inspect `ue_logs_tail` once the bridge comes up

Rules:
- do not continue to placement or PIE until the bridge is reachable
- use a bounded wait window
- if the bridge never comes up, report the blocker clearly

### Stage 6: Verify Class Availability

After the bridge is up, verify the class is usable before continuing.

Preferred approach:
- try a narrow spawn operation with `ue_spawn_actor`
- if the class is not found or spawn fails because the class is unavailable, inspect logs, wait briefly, and retry with bounded attempts
- if class availability still fails, treat that as a build-to-editor integration failure, not as a final success

Rules:
- use a deterministic actor name for test placement
- if retrying placement, clean up old test actors first with `ue_delete_actor` when needed
- prefer checking the returned `resolved_class_path` when diagnosing what class AgentBridge actually spawned

### Stage 7: Place In Level

Place the actor or supporting actors needed for the scenario.

Rules:
- use `ue_world_query` and `ue_list_actors` first if location context matters
- pick a reachable, testable location
- record the spawned actor name(s)
- if the task needs adjustments, use `ue_modify_actor`
- this stage is not a valid stopping point for an implement-and-verify request
- after successful placement, continue directly to Stage 8 unless there is a concrete blocker

### Stage 8: Start PIE

Use `ue_pie_start`, then confirm with `ue_pie_status`.

Rules:
- do not assume PIE is running until `ue_pie_status` says it is
- if PIE is already running, stop it first, then restart cleanly if the scenario requires a fresh run
- this stage is also not a valid stopping point; after PIE is confirmed, continue to runtime verification

### Stage 9: Verify Runtime Behavior

Use evidence, not intuition.

Preferred verification modes:
- test harness path: poll `ue_test_status` and `ue_test_results`
- log path: poll `ue_logs_tail`, preferably filtered to `[AgentTest]` or a specific class/test marker

Timeout guidance:
- use a bounded polling window
- if no success signal appears within the window, treat it as a failure that needs diagnosis
- do not skip this stage just because placement or PIE launch succeeded

### Stage 10: Stop PIE

Always call `ue_pie_stop` after verification, whether the result is success or failure.

This is a hard rule.

### Stage 11: Evaluate And Retry

If verification succeeded:
- report success
- include concise evidence
- stop

If verification failed:
- include the actual failure evidence
- decide whether the problem is code, build, editor launch, class loading, placement, timing, or test setup
- loop back with a targeted fix

Maximum outer-loop retries:
- 3 full iterations

If the retry budget is exhausted:
- stop
- report the remaining blocker and the evidence collected

## Lobster Workflow (Deterministic Execution)

After code is implemented (Stage 1-2), you MUST use the Lobster workflow to run all remaining stages deterministically.
This prevents early stopping and enforces the full stage sequence.

Directly calling `ue_build`, `ue_editor_open`, `ue_health`, or other UE tools after Stage 2 is a workflow error. It is not an acceptable fallback for this skill.

### CRITICAL: You MUST pass the class name

When you write a C++ actor (e.g. `ATestLobster10`), the class name to pass is the name **without the `A` prefix**: `TestLobster10`.

If you do not pass `class`, the workflow will fail immediately at the validation step. This is by design.

### How to invoke (RECOMMENDED 鈥?registered `lobster` tool)

If the `lobster` tool is available in your tool list, load the pipeline text from:

- `skills/ue-full-loop/ue-full-loop.registered.pipeline.md`

Read that file before calling `lobster`. The `pipeline` argument MUST be the command pipeline text from the fenced `text` block in that file, after placeholder replacement.

Do NOT invent a Lobster pipeline from memory. Do NOT pass YAML or JSON workflow syntax such as `name:`, `args:`, or `steps:` as the `pipeline` value. The registered Lobster tool expects command pipeline text; YAML-style input fails with `Unknown command: name`.

Replace these placeholders in the template before calling the tool:

- `__CLASS__`
- `__ACTOR_NAME__`
- `__LOC_X__`
- `__LOC_Y__`
- `__LOC_Z__`
- `__PROGRESS_FILE__`

The registered pipeline uses relative script paths like `./skills/ue-full-loop/ue-full-loop-state.mjs`. When calling `lobster`, pass `cwd: "product/craftling/workspace"`. Do NOT pass an absolute `cwd`; Lobster requires a relative cwd inside the gateway repo.

If the current request includes a runtime progress file path, replace `__PROGRESS_FILE__` with that exact path. Otherwise replace it with an empty temp file path under `%TEMP%`.

Then call the tool with:

```json
{
  "action": "run",
  "pipeline": "<expanded pipeline text from ue-full-loop.registered.pipeline.md>",
  "cwd": "product/craftling/workspace",
  "timeoutMs": 1200000
}
```

To resume after an approval gate:

```json
{
  "action": "resume",
  "token": "<resumeToken from the paused response>",
  "approve": true
}
```

### How to invoke (Fallback 鈥?wrapper script via exec/process)

Use the wrapper script only if the registered pipeline path is unavailable on the current runtime. This fallback keeps using the legacy file workflow in `ue-full-loop.lobster`.
It takes simple positional arguments 鈥?no JSON escaping needed:

```bash
node <CRAFTLING_SKILL_WORKSPACE_ROOT>/skills/ue-full-loop/ue-run-fullloop.mjs <class> [actor_name] [loc_x] [loc_y] [loc_z]
```

Example for a C++ actor `ATestLobster11`:
```bash
node <CRAFTLING_SKILL_WORKSPACE_ROOT>/skills/ue-full-loop/ue-run-fullloop.mjs TestLobster11
```

With custom location:
```bash
node <CRAFTLING_SKILL_WORKSPACE_ROOT>/skills/ue-full-loop/ue-run-fullloop.mjs TestLobster11 AgentTestActor 100 200 300
```

To resume after an approval gate:
```bash
node <CRAFTLING_SKILL_WORKSPACE_ROOT>/skills/ue-full-loop/ue-run-fullloop.mjs resume <resumeToken> approve
node <CRAFTLING_SKILL_WORKSPACE_ROOT>/skills/ue-full-loop/ue-run-fullloop.mjs resume <resumeToken> reject
```

### How to invoke (Alternative 鈥?lobster CLI)

**WARNING: On Windows, `--args-json` with JSON through PowerShell/cmd.exe will mangle the double quotes.
Use the registered pipeline (recommended) or the wrapper script (fallback) instead.**

```bash
lobster run --mode tool --file "<CRAFTLING_SKILL_WORKSPACE_ROOT>/skills/ue-full-loop/ue-full-loop.lobster" --args-json '{"class":"TestLobster11","actor_name":"AgentTestActor","loc_x":"0","loc_y":"0","loc_z":"100"}'
```

### Class name rules

| Source code class | What to pass as `class` |
|---|---|
| `ATestLobster10` (C++) | `TestLobster10` |
| `AMyRotatingActor` (C++) | `MyRotatingActor` |
| Blueprint `/Game/Blueprints/BP_Foo.BP_Foo_C` | `/Game/Blueprints/BP_Foo.BP_Foo_C` |

The `class` field **MUST NOT be empty**. If you just wrote an actor, you already know the class name 鈥?pass it.

Set `timeoutMs` to at least 1200000 (20 minutes) because the build step can take 10-15 minutes.

### On place_actor failure

If the `place_actor` step fails (class not found, spawn error), the workflow stops immediately.
Check the error output 鈥?common causes:
- Empty `class` field (you forgot `--args-json` or forgot to include `class` in argsJson)
- Wrong class name format (for C++ actors, do NOT include the `A` prefix)
- Class not compiled into the module yet (build may have failed silently)

### Approval gates

The workflow pauses twice for human review:

1. **confirm_pie** - after build + editor open + actor placed. Resume with `approve: true` to start PIE, or `approve: false` to abort.
2. **evaluate** - after PIE + logs + test results. Resume with `approve: true` if pass, `approve: false` if fail.

Human approval is mandatory. You MUST NOT approve, reject, or call `lobster resume` yourself when Lobster returns a `needs_approval` result.

When Lobster returns a paused approval result, stop immediately. First send a concise normal status message using the response contract, then send the approval request to the user/system in this exact machine-readable form on its own line:

```text
Stage: Approval
Skill: ue-full-loop
Tool: lobster

<one sentence explaining what is waiting for human approval>
```

```text
APPROVAL_REQUIRED_JSON: {"gate":"<gate name>","prompt":"<approval prompt>","resumeToken":"<resumeToken>"}
```

Rules for this marker:
- Include the exact `resumeToken` returned by Lobster.
- Use the Lobster prompt if it is available; otherwise summarize the approval question.
- Do not render the full Lobster `progress` list before the marker. Craftling reads the runtime progress file and streams those entries as UI evidence/progress automatically.
- Do not include secrets or unrelated tool output.
- Do not call the registered `lobster` tool with `action: "resume"` until the human has approved through the frontend or explicitly replied with approval.
- After the human approves, call `lobster resume` exactly once with that token, `approve: true`, and `cwd: "product/craftling/workspace"`.

To resume (registered tool, preferred):
```json
{
  "action": "resume",
  "token": "<resumeToken from the paused response>",
  "approve": true,
  "cwd": "product/craftling/workspace"
}
```

To resume (CLI):
```bash
lobster resume --token "<resumeToken>" --approve yes
```

### On build failure

If the `build` step fails, the deterministic Lobster pipeline stops immediately and returns the build error output.
That is not a completed task.

Repair loop:
- Read the compiler/linker errors from the Lobster failure progress or tool error.
- Decide whether the failure is in source code, module dependencies, generated class naming, encoding/string literals, or environment/config.
- If it is source/module code, edit the relevant Unreal files and re-run the registered Lobster pipeline from scratch with the same class, actor name, location, and runtime progress file.
- Keep build-repair attempts bounded to 2 retries for one user request unless the user explicitly asks to keep going.
- If the retry budget is exhausted, report failure with the exact build errors and the files changed.
- Do not report success or mark the task complete after a failed build.

## Completion Rule

For implement-and-verify tasks, the loop is incomplete unless one of these is true:
- runtime verification produced pass/fail evidence and PIE cleanup was attempted
- or a concrete blocker is reported at the exact stage that prevented continuation

These are not acceptable stopping points by themselves:
- successful build
- successful editor open
- successful class recognition
- successful actor placement
- successful PIE launch

## Behavioral Rules

- Use the registered `lobster` tool as the default path after source edits.
- Do not call direct UE tools after Stage 2 unless the user requested a simple one-step `ue-direct` action instead of this full loop.
- Prefer Lobster's CLI build plus editor-open sequence over any Live Coding path.
- Do not stop after a successful build; build is only the midpoint.
- Do not stop after opening the editor; bridge and class verification still need to happen.
- Do not stop after a successful PIE start; verification still needs to happen.
- Do not leave PIE running at the end of a loop.
- Do not declare success without evidence.
- Keep retries bounded and evidence-based.
