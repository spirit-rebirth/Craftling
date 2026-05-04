---
name: ue-editor
description: "Operate the Unreal Editor through AgentBridge for world inspection, actor placement, actor modification, and PIE lifecycle control in the active project."
---
# Skill: UE Editor Control (AgentBridge)

## Overview

You can control the Unreal Engine Editor via the **AgentBridge** HTTP plugin running inside the editor. The plugin exposes REST endpoints on `http://localhost:8080` (may be 8081閳?089 if 8080 is occupied).

**Important:** The UE Editor must be running with the locally configured Unreal project open for these endpoints to work.

---

## Pre-flight Check

Before calling any endpoint, verify the plugin is running:

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/api/health" -Method GET
```

If this fails, the editor isn't running or the plugin didn't load. Check a different port (8081, 8082, etc.) or look at the UE Output Log for the actual port.

---

## Endpoints Reference

### Health Check

```
GET /api/health
```

Returns: `{ "status": "ok", "plugin": "AgentBridge", "port": 8080 }`

---

### List Actors

```
GET /api/actors/list
```

Returns all actors in the current editor level with their name, class, location, label, and visibility.

**Response:**
```json
{
  "actors": [
    {
      "name": "ThirdPersonCharacter",
      "class": "BP_ThirdPersonCharacter_C",
      "location": { "x": 0, "y": 0, "z": 100 },
      "label": "ThirdPersonCharacter",
      "hidden": false
    }
  ],
  "count": 42
}
```

---

### Spawn Actor

```
POST /api/actors/spawn
Content-Type: application/json

{
  "class": "<ClassName>",
  "name": "<OptionalLabel>",
  "location": { "x": 0, "y": 0, "z": 200 },
  "rotation": { "pitch": 0, "yaw": 0, "roll": 0 }
}
```

**Supported class names** (case-insensitive):
- `StaticMeshActor` 閳?a basic static mesh actor
- `PointLight` 閳?a point light
- `DirectionalLight` 閳?a directional light
- Any custom class from the project (e.g., `HealthPickup` or `AHealthPickup`)

The system automatically tries both the name as-given and with the `A` prefix (UE actor convention).

**PowerShell example:**
```powershell
$body = @{
    class = "PointLight"
    name = "AgentLight_1"
    location = @{ x = 0; y = 0; z = 300 }
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8080/api/actors/spawn" `
  -Method POST -Body $body -ContentType "application/json"
```

---

### Delete Actor

```
DELETE /api/actors/delete
Content-Type: application/json

{
  "name": "<ActorNameOrLabel>"
}
```

Matches against both the actor's internal name and its editor label.

---

### Modify Actor

```
PUT /api/actors/modify
Content-Type: application/json

{
  "name": "<ActorNameOrLabel>",
  "location": { "x": 100, "y": 200, "z": 300 },
  "rotation": { "pitch": 0, "yaw": 45, "roll": 0 },
  "scale": { "x": 2, "y": 2, "z": 2 }
}
```

All fields except `name` are optional. Only the fields you include will be modified.

---

### Start PIE (Play In Editor)

```
POST /api/pie/start
```

Starts a Play-In-Editor session. This is **asynchronous** 閳?PIE takes a moment to initialize. Poll `/api/pie/status` to confirm it's running.

**Workflow:**
1. Call `POST /api/pie/start`
2. Wait 2-3 seconds
3. Call `GET /api/pie/status` to confirm `is_running: true`
4. Perform observations (poll logs, etc.)
5. Call `POST /api/pie/stop` when done

---

### Stop PIE

```
POST /api/pie/stop
```

Stops the current PIE session.

---

### PIE Status

```
GET /api/pie/status
```

**Response when running:**
```json
{
  "status": "running",
  "is_running": true,
  "map": "ThirdPersonMap",
  "elapsed_seconds": 12.5
}
```

**Response when stopped:**
```json
{
  "status": "stopped",
  "is_running": false
}
```

---

### World Query

```
GET /api/world/query
```

Returns general information about the current editor world: map name, total actor count, breakdown by class, and PIE status.

**Response:**
```json
{
  "map_name": "ThirdPersonMap",
  "world_type": "Editor",
  "total_actors": 42,
  "actor_class_counts": {
    "StaticMeshActor": 15,
    "PointLight": 3,
    "BP_ThirdPersonCharacter_C": 1
  },
  "pie_running": false
}
```

---

### Tail Logs

```
GET /api/logs/tail?count=50&filter=AgentTest
```

**Parameters:**
- `count` (optional, default 50): Number of recent log lines to return (max 500)
- `filter` (optional): Only return lines where the message or category contains this string

**Response:**
```json
{
  "logs": [
    {
      "message": "[AgentTest] PICKUP_COLLECTED: HealthPickup_1",
      "category": "LogTemp",
      "verbosity": "Log",
      "timestamp": "2026-03-22T10:15:30"
    }
  ],
  "count": 1,
  "buffer_size": 245
}
```

The plugin keeps a rolling buffer of the last 500 log lines. The `filter` parameter is useful for Phase 3's test harness 閳?use `filter=AgentTest` to get only structured test output.

---

## Common Workflows

### Workflow 1: Place an actor and verify

```
1. POST /api/actors/spawn  (spawn the actor)
2. GET  /api/actors/list    (verify it appears)
3. PUT  /api/actors/modify  (adjust position if needed)
```

### Workflow 2: Test during PIE

```
1. POST /api/pie/start      (start the game)
2. Wait 2-3 seconds
3. GET  /api/pie/status      (confirm running)
4. GET  /api/logs/tail?filter=AgentTest  (poll for test results)
5. ... repeat polling every 2-3 seconds ...
6. POST /api/pie/stop        (stop when done)
```

### Workflow 3: Full level setup for testing

```
1. GET  /api/world/query     (understand current level)
2. POST /api/actors/spawn    (add test actors)
3. GET  /api/actors/list     (verify placement)
4. POST /api/pie/start       (run the game)
5. GET  /api/logs/tail       (observe results)
6. POST /api/pie/stop        (stop)
7. DELETE /api/actors/delete  (clean up test actors)
```

---

## Error Handling

All error responses have this format:
```json
{
  "error": "Description of what went wrong",
  "status": 400
}
```

Common errors:
- `"No editor world available"` 閳?No level is loaded in the editor
- `"Class 'X' not found"` 閳?Invalid class name for spawning
- `"Actor 'X' not found"` 閳?No actor with that name/label exists
- `"PIE is already running"` 閳?Tried to start PIE when it's already active
- `"PIE is not running"` 閳?Tried to stop PIE when it's not active

---

## Key Paths (Project-Specific)

- **Plugin source:** configured per project; see your Unreal project plugin directory and `examples/openclaw.example.json`.
- **Project:** active Unreal project configured in local OpenClaw plugin config
- **UE version:** 5.6+
- **Default port:** 8080 (check Output Log for actual port)

---

## Notes

- The HTTP server runs on the **game thread** within the UE Editor process. Requests are processed during the editor tick.
- Only one PIE session is supported at a time.
- Actor names might not be unique 閳?use descriptive labels when spawning to make deletion/modification reliable.
- The log buffer holds 500 entries max. For long PIE sessions, poll logs frequently to avoid missing entries.
- All location coordinates use Unreal's coordinate system (X=forward, Y=right, Z=up), units in centimeters.
