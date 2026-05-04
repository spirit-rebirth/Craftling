---
name: ue-play-test
description: "Run Play-In-Editor verification loops, observe Unreal test harness results or logs, and determine runtime pass or fail for UE tasks."
---
# Skill: UE Play-Test (ue-play-test)

You are an agent that runs gameplay tests in Unreal Engine via the AgentBridge HTTP API. You start PIE (Play-In-Editor), observe test results, and determine pass/fail.

---

## Project Context

- **Project:** active Unreal project configured in local OpenClaw plugin config
- **AgentBridge URL:** `http://localhost:8080` (may be 8081閳?089 if 8080 was taken 閳?check the UE Output Log for the actual port)
- **Test infrastructure:** `UTestHarnessSubsystem` collects results from `ATestHarnessActor` instances

---

## Core Workflow

### 1. Pre-Flight Check

Before starting a test, verify the AgentBridge is alive:

```
GET /api/health
```

Expected: `{"status":"ok","port":8080}`

If this fails, the UE Editor is not running or the AgentBridge plugin isn't loaded.

### 2. Spawn a Test Harness Actor

For each test condition, spawn a `TestHarnessActor` configured for the test:

```
POST /api/actors/spawn
Content-Type: application/json

{
  "class": "TestHarnessActor",
  "x": 0, "y": 0, "z": 200,
  "properties": {
    "TestName": "HealthPickupRestoresHP",
    "TargetActorTag": "HealthPickup",
    "TimeoutSeconds": 15,
    "PollIntervalSeconds": 1.0,
    "SuccessCondition": "exists"
  }
}
```

#### Success Conditions

| Condition | Meaning |
|-----------|---------|
| `"exists"` | Target actor with the given tag exists in the world |
| `"destroyed"` | Target actor existed at start and was removed (e.g., consumed pickup) |
| `"overlapped"` | Player pawn overlapped the target actor's collision |

Choose the condition that matches what the test should verify.

### 3. Start PIE

```
POST /api/pie/start
```

Expected response: `{"status":"started"}` or `{"status":"already_running"}`

### 4. Poll for Test Completion

Poll every 2閳? seconds until status is `"complete"` or you hit a timeout:

```
GET /api/test/status
```

Response example:
```json
{
  "status": "running",
  "result_count": 0,
  "pending_count": 1,
  "passed": 0,
  "failed": 0
}
```

**Status values:**
- `"idle"` 閳?No test session active (PIE may not be running)
- `"running"` 閳?Tests are in progress
- `"complete"` 閳?All pending tests have reported results

**Agent-side timeout:** If you've been polling for 60 seconds and status is still `"running"`, stop PIE and treat it as a timeout failure.

### 5. Get Test Results

Once status is `"complete"` (or after your timeout):

```
GET /api/test/results
```

Response example:
```json
{
  "status_summary": {
    "status": "complete",
    "result_count": 1,
    "pending_count": 0,
    "passed": 1,
    "failed": 0
  },
  "results": [
    {
      "test_name": "HealthPickupRestoresHP",
      "passed": true,
      "message": "Actor with tag 'HealthPickup' exists in world",
      "timestamp": 3.250
    }
  ]
}
```

### 6. Stop PIE

```
POST /api/pie/stop
```

Always stop PIE after collecting results, even on failure.

### 7. Tail Logs (supplemental)

For additional context, check the structured agent test logs:

```
GET /api/logs/tail?filter=AgentTest
```

This returns the recent log lines with `[AgentTest]` prefix 閳?useful for debugging failures.

---

## Decision Logic

After collecting results, decide the next action:

### ALL TESTS PASS
閳?Report success. The task is complete.
閳?Output a clear summary: which tests ran, what they verified, results.

### ANY TEST FAILS
閳?Analyze the failure message from the results.
閳?Check `/api/logs/tail?filter=AgentTest` for additional context.
閳?Identify what went wrong:
  - **"No actor found with tag X"** 閳?The actor wasn't spawned or tagged correctly. Go back to editor operations (spawn/tag the actor).
  - **"Timeout 閳?condition not met"** 閳?The gameplay logic didn't trigger. Go back to code gen to fix the logic.
  - **Unexpected message** 閳?Read the full log tail and diagnose.
閳?Loop back to the appropriate phase (code gen, build, or editor) with specific fix context.

### PIE CRASH
閳?The PIE session ended unexpectedly.
閳?Check `/api/logs/tail` (no filter) for crash callstacks or error lines.
閳?Parse the crash to identify the offending code.
閳?Loop back to code gen with the crash context.

### AGENT TIMEOUT (60s polling with no completion)
閳?Something may be hung. Stop PIE.
閳?Check logs for clues.
閳?Consider: was the test harness spawned? Did PIE actually start?
閳?Report the issue with full diagnostic info.

---

## Common Test Patterns

### Test: "Does actor X exist after code gen + build?"
```json
{
  "SuccessCondition": "exists",
  "TargetActorTag": "HealthPickup"
}
```
Precondition: The actor must be spawned (via /api/actors/spawn) and tagged before starting PIE.

### Test: "Does the pickup get consumed when player touches it?"
```json
{
  "SuccessCondition": "destroyed",
  "TargetActorTag": "HealthPickup"
}
```
Precondition: Pickup actor exists, has collision with overlap events, and is near the player start.

### Test: "Does the player reach the trigger zone?"
```json
{
  "SuccessCondition": "overlapped",
  "TargetActorTag": "TriggerZone"
}
```
Precondition: A trigger volume exists with the tag, player can walk to it.

---

## Important Notes

- **One test harness per condition.** If you need to verify multiple things, spawn multiple TestHarnessActors with different test names.
- **Tags are key.** The test harness finds targets by UE actor tags, not by name. Make sure target actors have the correct tag applied.
- **PIE resets the subsystem.** Each PIE session starts fresh 閳?previous results are not carried over.
- **Game thread safety.** The AgentBridge endpoints handle thread marshaling internally. Just call the HTTP endpoints normally.
- **Port may vary.** The AgentBridge tries ports 8080閳?089. If 8080 doesn't respond, try the next port or check the UE Output Log.
