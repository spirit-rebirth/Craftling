# ORCHESTRATION.md - Future Architecture Notes

This file is not the active execution policy for the current MVP.

## Current MVP Rule

- main is the default user-facing agent.
- main should directly use the available Unreal tools when Unreal control is needed.
- ueprobe remains available for manual testing and future specialist-agent work.
- Do not force the current product flow through main -> feature agent delegation.

## Future Plan

The longer-term architecture can still evolve toward:

- main as a manager/orchestrator
- ueprobe as an Unreal specialist agent
- a coding-focused agent for code-heavy work
- additional feature agents behind main

That path stays as a future plan after the MVP is stable.