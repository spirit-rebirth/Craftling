name: ue-full-loop
description: "Deterministic Unreal implement-build-open-place-PIE-verify loop. Enforces all stages 鈥?cannot stop early."

args:
  class:
    description: >
      Actor class to spawn. For C++ actors use the class name without the A prefix
      (e.g. "TestLobster8" for ATestLobster8). For Blueprints use the full path
      (e.g. "/Game/Blueprints/BP_MyActor.BP_MyActor_C"). This MUST NOT be empty.
    default: ""
  actor_name:
    description: "Label for the spawned actor in the level"
    default: "AgentTestActor"
  loc_x:
    default: "0"
  loc_y:
    default: "0"
  loc_z:
    default: "100"

env:
  CLAWD_URL: "http://127.0.0.1:18789"
  CLAWD_TOKEN: "${CLAWD_TOKEN}"
  UE_INVOKE: "node __UECLAW_ROOT__/skills/ue-full-loop/ue-invoke.mjs"
  UE_APPROVAL_PAYLOAD: "node __UECLAW_ROOT__/skills/ue-full-loop/ue-approval-payload.mjs"
  MSYS_NO_PATHCONV: "1"
  MSYS2_ARG_CONV_EXCL: "*"

steps:
  # 鈹€鈹€ Stage 1: Build 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  # Runs Build.bat. Exits 1 if build fails 鈫?workflow stops here.
  - id: build
    command: $UE_INVOKE ue_build

  # 鈹€鈹€ Stage 2: Open Editor 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  # Launches UnrealEditor.exe. Non-blocking (returns immediately after spawn).
  - id: open_editor
    command: $UE_INVOKE ue_editor_open

  # 鈹€鈹€ Stage 3: Wait for AgentBridge 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  # Polls ue_health every 10s for up to 5 minutes.
  - id: wait_bridge
    command: |
      for i in $(seq 1 30); do
        result=$($UE_INVOKE ue_health 2>/dev/null)
        if echo "$result" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"'; then
          echo "$result"
          exit 0
        fi
        sleep 10
      done
      echo '{"ok":false,"error":"bridge_timeout_after_300s"}'
      exit 1

  # 鈹€鈹€ Stage 3.5: Validate class arg 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  # Fail fast if the LLM forgot to pass the class name.
  - id: validate_class
    command: |
      if [ -z "${class}" ]; then
        echo '{"ok":false,"error":"class argument is empty. You must pass the actor class name (e.g. TestLobster8 for ATestLobster8) in argsJson when invoking lobster."}'
        exit 1
      fi
      echo '{"ok":true,"class":"${class}"}'

  # 鈹€鈹€ Stage 4: Place Actor (class availability check + placement) 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  # Spawns the actor. Exit 1 if class not found 鈫?workflow stops.
  - id: place_actor
    command: >
      $UE_INVOKE ue_spawn_actor
      --class "${class}" --name "${actor_name}" --loc-x "${loc_x}" --loc-y "${loc_y}" --loc-z "${loc_z}"

  # 鈹€鈹€ Stage 5: Confirm before PIE 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  # Approval gate: shows placement result, waits for human/LLM to confirm.
  # JSON data passed via stdin to avoid shell escaping issues.
  - id: confirm_pie
    command: $UE_APPROVAL_PAYLOAD confirm_pie --stdin
    stdin: '{"class":"${class}","actor_name":"${actor_name}","build":$build.json,"placement":$place_actor.json}'
    approval: required

  # 鈹€鈹€ Stage 6: Start PIE 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  - id: start_pie
    command: $UE_INVOKE ue_pie_start
    condition: $confirm_pie.approved

  # 鈹€鈹€ Stage 7: Wait for PIE to settle, then collect evidence 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  - id: wait_pie
    command: sleep 8
    condition: $confirm_pie.approved

  - id: logs
    command: $UE_INVOKE ue_logs_tail '{"count":60}'
    condition: $confirm_pie.approved

  - id: test_status
    command: $UE_INVOKE ue_test_status
    condition: $confirm_pie.approved

  - id: test_results
    command: $UE_INVOKE ue_test_results
    condition: $confirm_pie.approved

  # 鈹€鈹€ Stage 8: Stop PIE 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  # Always runs (whether tests passed or failed).
  - id: stop_pie
    command: $UE_INVOKE ue_pie_stop
    condition: $confirm_pie.approved

  # 鈹€鈹€ Stage 9: Evaluate 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  # Final approval gate: shows all evidence for pass/fail decision.
  # JSON data passed via stdin to avoid shell escaping issues.
  - id: evaluate
    command: $UE_APPROVAL_PAYLOAD evaluate --stdin
    stdin: '{"test_status":$test_status.json,"test_results":$test_results.json,"logs":$logs.json}'
    approval: required
    condition: $confirm_pie.approved
