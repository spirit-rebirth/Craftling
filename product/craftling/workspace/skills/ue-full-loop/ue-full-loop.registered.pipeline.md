# UE Full Loop Registered Lobster Pipeline

Preferred registered-tool pipeline for Windows. This path avoids the YAML file workflow executor and its `/bin/sh` dependency.

Replace the placeholders before calling the `lobster` tool:
- `__CLASS__`
- `__ACTOR_NAME__`
- `__LOC_X__`
- `__LOC_Y__`
- `__LOC_Z__`
- `__PROGRESS_FILE__`

```text
exec node ./skills/ue-full-loop/ue-full-loop-state.mjs init "__CLASS__" "__ACTOR_NAME__" "__LOC_X__" "__LOC_Y__" "__LOC_Z__" "__PROGRESS_FILE__" --json |
exec node ./skills/ue-full-loop/ue-full-loop-state.mjs build "__PROGRESS_FILE__" --stdin=json --json |
exec node ./skills/ue-full-loop/ue-full-loop-state.mjs open-editor "__PROGRESS_FILE__" --stdin=json --json |
exec node ./skills/ue-full-loop/ue-full-loop-state.mjs wait-bridge "__PROGRESS_FILE__" --stdin=json --json |
exec node ./skills/ue-full-loop/ue-full-loop-state.mjs validate-class "__PROGRESS_FILE__" --stdin=json --json |
exec node ./skills/ue-full-loop/ue-full-loop-state.mjs place-actor "__PROGRESS_FILE__" --stdin=json --json |
approve --emit --preview-from-stdin --limit 1 --prompt "Build OK, editor open, actor placed. Proceed to PIE verification?" |
exec node ./skills/ue-full-loop/ue-full-loop-state.mjs start-pie "__PROGRESS_FILE__" --stdin=json --json |
exec node ./skills/ue-full-loop/ue-full-loop-state.mjs wait-pie "__PROGRESS_FILE__" --stdin=json --json |
exec node ./skills/ue-full-loop/ue-full-loop-state.mjs capture-screenshot "__PROGRESS_FILE__" --stdin=json --json |
exec node ./skills/ue-full-loop/ue-full-loop-state.mjs collect-evidence "__PROGRESS_FILE__" --stdin=json --json |
exec node ./skills/ue-full-loop/ue-full-loop-state.mjs stop-pie "__PROGRESS_FILE__" --stdin=json --json |
approve --emit --preview-from-stdin --limit 1 --prompt "Review runtime evidence. Did the implementation pass?"
```

Example tool call:

```json
{
  "action": "run",
  "pipeline": "<the pipeline text above with placeholders replaced>",
  "cwd": "product/craftling/workspace",
  "timeoutMs": 1200000
}
```
