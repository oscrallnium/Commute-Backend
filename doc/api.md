# CommuteBeh API — iOS Reference

Base URL (local): `http://localhost:3000`  
Base URL (production): _set from Koyeb dashboard_

All authenticated requests must include:
```
Authorization: Bearer <token>
Content-Type: application/json
```

---

## Authentication

### Register
```
POST /auth/register
```
**Body:**
```json
{
  "user": {
    "email": "user@example.com",
    "password": "Password123!",
    "password_confirmation": "Password123!",
    "display_name": "Juan dela Cruz"
  }
}
```
**Response `201`:**
```json
{
  "data": {
    "token": "<jwt>",
    "user": {
      "id": "uuid",
      "email": "user@example.com",
      "display_name": "Juan dela Cruz",
      "role": "user"
    }
  }
}
```
**Response `422`:**
```json
{ "error": "Registration failed", "errors": ["Email has already been taken"] }
```

---

### Login
```
POST /auth/sign_in
```
**Body:**
```json
{
  "user": {
    "email": "user@example.com",
    "password": "Password123!"
  }
}
```
**Response `200`:**
```json
{
  "data": {
    "token": "<jwt>",
    "user": {
      "id": "uuid",
      "email": "user@example.com",
      "display_name": "Juan dela Cruz",
      "role": "user"
    }
  }
}
```
**Response `401`:**
```json
{ "error": "Invalid email or password" }
```

---

### Logout
```
DELETE /auth/sign_out
Authorization: Bearer <token>
```
**Response `200`:**
```json
{ "message": "Signed out successfully" }
```
The token's JTI is immediately revoked — the token cannot be used again.

---

### Refresh Token
```
POST /api/v1/auth/refresh
Authorization: Bearer <token>
```
**Response `200`:**
```json
{
  "data": {
    "token": "<new_jwt>",
    "user": {
      "id": "uuid",
      "email": "user@example.com",
      "display_name": "Juan dela Cruz",
      "role": "user"
    }
  }
}
```
The old token is revoked. Store the new token and discard the old one.

---

### Delete Account
```
DELETE /api/v1/auth/account
Authorization: Bearer <token>
```
**Response `200`:**
```json
{ "message": "Account deleted successfully" }
```
Required for App Store compliance. Permanently deletes the user and all associated data.

---

## User Profile

### Get Current User
```
GET /api/v1/me
Authorization: Bearer <token>
```
**Response `200`:**
```json
{
  "data": {
    "id": "uuid",
    "email": "user@example.com",
    "display_name": "Juan dela Cruz",
    "role": "user",
    "home_station_id": "MRT3_NORTH_AVE",
    "created_at": "2025-01-01T00:00:00.000Z"
  }
}
```

---

### Update Profile
```
PATCH /api/v1/me
Authorization: Bearer <token>
```
**Body** (all fields optional):
```json
{
  "user": {
    "display_name": "Juan",
    "home_station_id": "LRT1_BACLARAN"
  }
}
```
**Response `200`:**
```json
{
  "data": {
    "id": "uuid",
    "email": "user@example.com",
    "display_name": "Juan",
    "home_station_id": "LRT1_BACLARAN"
  }
}
```

---

## Transit Graph

### Check Graph Version
```
GET /api/v1/graph/version
```
No auth required. Call this first before fetching the full graph — only re-download when the version changes.

**Response `200`:**
```json
{
  "data": {
    "version": 1,
    "last_modified": "2025-06-01T00:00:00.000Z",
    "schema_version": "3.0.0",
    "region": "Metro Manila, Philippines"
  }
}
```

---

### Get Full Transit Graph
```
GET /api/v1/graph
```
No auth required. Returns the complete graph in `transit_graph_v3.json` shape. Cache locally and only refetch when `/graph/version` changes.

**Response `200`:** Full graph JSON (stations, edges, fare matrix, transport modes, payment methods, graph metadata).

---

## Stations

### List Stations
```
GET /api/v1/stations
```
No auth required.

**Query parameters:**

| Param | Type | Description |
|---|---|---|
| `line` | string | Filter by line ID e.g. `MRT-3` |
| `type` | string | Filter by type e.g. `train`, `bus` |
| `interchange` | boolean | `true` to return interchange stations only |
| `search` | string | Search by name, short name, or line |

**Response `200`:**
```json
{
  "data": [
    {
      "id": "MRT3_NORTH_AVE",
      "name": "North Avenue",
      "short_name": "North Ave",
      "line": "MRT-3",
      "type": "train",
      "coordinates": { "lat": 14.6516, "lng": 121.0327 },
      "is_terminal": true,
      "is_interchange": false,
      "amenities": [],
      "operating_hours": { "open": "05:30", "close": "22:30" }
    }
  ],
  "meta": { "count": 1 }
}
```

---

### Get Station
```
GET /api/v1/stations/:id
```
No auth required. `:id` is the station ID string e.g. `MRT3_NORTH_AVE`.

**Response `200`:** Single station object (same shape as above).

---

## Routes

### List Routes
```
GET /api/v1/routes
```
No auth required. Returns one entry per transit line.

**Query parameters:**

| Param | Type | Description |
|---|---|---|
| `mode` | string | Filter by mode e.g. `train`, `bus` |
| `search` | string | Search by line ID |

**Response `200`:**
```json
{
  "data": [
    {
      "line_id": "MRT-3",
      "mode": "train",
      "base_fare": 13.0,
      "accepted_payments": ["beep", "cash"],
      "is_air_conditioned": true,
      "open_time": "05:30",
      "close_time": "22:30",
      "crowd_factor": 0.8,
      "reliability": 0.9,
      "stop_count": 13
    }
  ],
  "meta": { "count": 1 }
}
```

---

### Get Route
```
GET /api/v1/routes/:line_id
```
No auth required. Returns full route detail including all stations and edges.

**Response `200`:**
```json
{
  "data": {
    "line_id": "MRT-3",
    "mode": "train",
    "base_fare": 13.0,
    "accepted_payments": ["beep", "cash"],
    "is_air_conditioned": true,
    "open_time": "05:30",
    "close_time": "22:30",
    "crowd_factor": 0.8,
    "reliability": 0.9,
    "stations": [ /* station objects */ ],
    "edges": [ /* edge objects */ ]
  }
}
```

---

## Saved Routes

### List Saved Routes
```
GET /api/v1/saved_routes
Authorization: Bearer <token>
```
**Response `200`:**
```json
{
  "data": [
    {
      "id": "uuid",
      "name": "Home to Work",
      "origin_station_id": "LRT1_BACLARAN",
      "destination_station_id": "MRT3_NORTH_AVE",
      "legs": [
        {
          "line_id": "LRT-1",
          "mode": "train",
          "from_station": "LRT1_BACLARAN",
          "to_station": "LRT1_EDSA",
          "travel_time_minutes": 25
        }
      ],
      "created_at": "2025-06-01T00:00:00.000Z"
    }
  ]
}
```

---

### Save a Route
```
POST /api/v1/saved_routes
Authorization: Bearer <token>
```
**Body:**
```json
{
  "saved_route": {
    "name": "Home to Work",
    "origin_station_id": "LRT1_BACLARAN",
    "destination_station_id": "MRT3_NORTH_AVE",
    "legs": [
      {
        "line_id": "LRT-1",
        "mode": "train",
        "from_station": "LRT1_BACLARAN",
        "to_station": "LRT1_EDSA",
        "travel_time_minutes": 25
      }
    ]
  }
}
```
**Response `201`:** Saved route object.

---

### Delete Saved Route
```
DELETE /api/v1/saved_routes/:id
Authorization: Bearer <token>
```
**Response `200`:**
```json
{ "message": "Saved route deleted" }
```

---

## Incidents

### List Active Incidents
```
GET /api/v1/incidents
Authorization: Bearer <token>
```
Returns up to 50 active incidents ordered by most recent.

**Response `200`:**
```json
{
  "data": [
    {
      "id": "uuid",
      "station_id": "MRT3_CUBAO",
      "line_id": "MRT-3",
      "category": "delay",
      "description": "Signaling issue causing 15-minute delays",
      "reported_by": "user-uuid",
      "created_at": "2025-06-29T08:00:00.000Z"
    }
  ]
}
```

**Incident categories:** `delay` · `crowding` · `breakdown` · `closure` · `other`

---

### Report an Incident
```
POST /api/v1/incidents
Authorization: Bearer <token>
```
**Body:**
```json
{
  "incident": {
    "station_id": "MRT3_CUBAO",
    "line_id": "MRT-3",
    "category": "delay",
    "description": "Signaling issue causing 15-minute delays"
  }
}
```
**Response `201`:** Incident object.

---

## Analytics

### Log Route Plan
```
POST /api/v1/analytics/route_plan
Authorization: Bearer <token>
```
Call this after every successful A* route computation on-device. This call **never fails the user's commute** — even if the server is down, the app receives `201`.

**Body:**
```json
{
  "origin_id": "LRT1_BACLARAN",
  "destination_id": "MRT3_NORTH_AVE",
  "total_time_minutes": 45,
  "modes_used": ["train", "train"],
  "legs": [
    {
      "line_id": "LRT-1",
      "mode": "train",
      "from_station": "LRT1_BACLARAN",
      "to_station": "LRT1_EDSA",
      "travel_time_minutes": 25
    }
  ]
}
```
**Response `201`:**
```json
{ "message": "Logged" }
```

---

## Health Check

```
GET /health
```
No auth required. Used by uptime monitors.

**Response `200`:**
```json
{ "status": "ok", "database": "connected" }
```

---

## Error format

All errors follow this shape:
```json
{ "error": "Short message", "errors": ["Detail 1", "Detail 2"] }
```

| Status | Meaning |
|---|---|
| `400` | Bad request / missing params |
| `401` | Missing or invalid token |
| `403` | Insufficient role (admin required) |
| `404` | Record not found |
| `422` | Validation failed |
| `429` | Rate limit exceeded |
| `503` | Graph service unavailable |

---

## Rate limits

| Scope | Limit |
|---|---|
| Auth endpoints (per IP) | 10 req / 20 s |
| Sign-in by email | 5 req / 5 min |
| API endpoints (per IP) | 60 req / min |
| Analytics writes (per user) | 30 req / min |
