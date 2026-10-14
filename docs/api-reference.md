# API Reference

Last checked against commit `106ae55` on 10/13/26.

---

**Base URL:** `https://commute-backend-a6lj.onrender.com`

This page lists every route in `config/routes.rb`. The publish contract for the ops dashboard is in
[Ops Publish API](ops-publish-api.md).

## Conventions

### Envelopes

A successful response wraps the payload. `meta` is present only when the controller sets it.

```json
{ "data": { }, "meta": { "count": 42 } }
```

An error response has an `error` string. It can also have an `errors` array of strings.

```json
{ "error": "Validation failed", "errors": ["Name can't be blank"] }
```

### Case

| Surface | Key case |
|:--|:--|
| `GET /api/v1/graph`, `GET /api/v1/admin/graph` | camelCase |
| `PATCH /api/v1/admin/lines/:id` response | camelCase |
| Publish, version history, and line delete | snake_case |
| Every other endpoint | snake_case |

### Authentication

| Value | Meaning |
|:--|:--|
| none | No token needed. The controller calls `skip_before_action :authenticate_user!`. |
| user | Send `Authorization: Bearer <token>`. `BaseController` runs `authenticate_user!`. |
| admin | As `user`, and the user role is `admin`. The controller runs `before_action :require_admin!`. |

### Errors that apply to many routes

| Status | Body | Cause |
|:--|:--|:--|
| 400 | `{ "error": "Bad request", "message": "…" }` | A required param key is missing (`ActionController::ParameterMissing`). |
| 401 | Devise failure body, `{ "error": "<message>" }` | No token, an invalid token, or a revoked token. |
| 403 | `{ "error": "Forbidden", "message": "Admin access required" }` | The user is not an admin. |
| 404 | `{ "error": "Not found", "message": "…" }` | `ActiveRecord::RecordNotFound`. |
| 422 | `{ "error": "Unprocessable", "errors": ["…"] }` | `ActiveRecord::RecordInvalid`. |
| 429 | `{ "error": "Too many requests. Please try again later." }` | A Rack::Attack throttle. |
| 500 | `{ "error": "Internal server error" }` | `ActiveRecord::StatementInvalid`. Other errors give the Rails default 500. |

### Rate limits

| Name | Limit | Key | Applies to |
|:--|:--|:--|:--|
| `auth/ip` | 10 per 20 s | IP address | Paths that start with `/auth/` |
| `auth/email` | 5 per 5 min | Lower-case `user.email` | `POST /auth/sign_in` (see [Security](security.md#rackattack)) |
| `api/ip` | 60 per 1 min | IP address | Paths that start with `/api/` |
| `analytics/user` | 30 per 1 min | Last word of the `Authorization` header | `POST /api/v1/analytics/route_plan` |

A route under `/api/` counts against `api/ip` in addition to any other limit. `GET /health` has no limit.

### Caches

| Key | TTL | Used by |
|:--|:--|:--|
| `graph_version` | 30 s | `GET /api/v1/graph/version` |
| `full_graph` | 5 min | `GET /api/v1/graph` |
| `routes_index` | 30 min | `GET /api/v1/routes` |
| `stations/<line>/<type>/<interchange>/<search>` | 1 h | `GET /api/v1/stations` |

`bust_graph_cache!` deletes `full_graph` and `graph_version`. Some actions also delete `stations*`. Nothing deletes `routes_index`.

## Route index

Every route in `config/routes.rb`. `Service` is the service class that the action calls. A dash means the action uses models only.

| Group | Method | Path | Auth | Controller#action | Service |
|:--|:--|:--|:--|:--|:--|
| Health | GET | `/health` | none | `health#show` | – |
| Auth | POST | `/auth/register` | none | `api/v1/auth/registrations#create` | – |
| Auth | POST | `/auth/sign_in` | none | `api/v1/auth/sessions#create` | – |
| Auth | DELETE | `/auth/sign_out` | user | `api/v1/auth/sessions#destroy` | – |
| Auth | POST | `/api/v1/auth/refresh` | user | `api/v1/auth/sessions#refresh` | – |
| Auth | DELETE | `/api/v1/auth/account` | user | `api/v1/auth/registrations#destroy` | – |
| User | GET | `/api/v1/me` | user | `api/v1/users#me` | – |
| User | PATCH | `/api/v1/me` | user | `api/v1/users#update` | – |
| Graph | GET | `/api/v1/graph/version` | none | `api/v1/graph#version` | `GraphService.graph_version` |
| Graph | GET | `/api/v1/graph` | none | `api/v1/graph#show` | `GraphService.assemble_graph` |
| Stations | GET | `/api/v1/stations` | none | `api/v1/stations#index` | – |
| Stations | GET | `/api/v1/stations/:id` | none | `api/v1/stations#show` | – |
| Routes | GET | `/api/v1/routes` | none | `api/v1/routes#index` | – |
| Routes | GET | `/api/v1/routes/:line_id` | none | `api/v1/routes#show` | – |
| Saved routes | GET | `/api/v1/saved_routes` | user | `api/v1/saved_routes#index` | – |
| Saved routes | POST | `/api/v1/saved_routes` | user | `api/v1/saved_routes#create` | – |
| Saved routes | DELETE | `/api/v1/saved_routes/:id` | user | `api/v1/saved_routes#destroy` | – |
| AR maps | GET | `/api/v1/ar_world_maps` | user | `api/v1/ar_world_maps#index` | – |
| AR maps | GET | `/api/v1/ar_world_maps/:id` | user | `api/v1/ar_world_maps#show` | – |
| AR maps | POST | `/api/v1/ar_world_maps` | user | `api/v1/ar_world_maps#create` | – |
| AR maps | POST | `/api/v1/ar_world_maps/:id/relocalize` | user | `api/v1/ar_world_maps#relocalize` | – |
| Analytics | POST | `/api/v1/analytics/route_plan` | user | `api/v1/analytics#route_plan` | – |
| Incidents | GET | `/api/v1/incidents` | user | `api/v1/incidents#index` | – |
| Incidents | POST | `/api/v1/incidents` | user | `api/v1/incidents#create` | – |
| Places | GET | `/api/v1/places`, `/api/v1/places/:id` | – | `api/v1/places#index`, `#show` (no controller) | – |
| Events | GET | `/api/v1/events`, `/api/v1/events/:id` | – | `api/v1/events#index`, `#show` (no controller) | – |
| Admin users | GET, GET, DELETE | `/api/v1/admin/users`, `/:id` | admin | `api/v1/admin/users#index`, `#show`, `#destroy` (no controller) | – |
| Admin AR maps | GET, GET, PATCH/PUT, DELETE | `/api/v1/admin/ar_world_maps`, `/:id` | admin | `api/v1/admin/ar_world_maps#*` (no controller) | – |
| Admin incidents | GET, PATCH/PUT, DELETE | `/api/v1/admin/incidents`, `/:id` | admin | `api/v1/admin/incidents#*` (no controller) | – |
| Admin analytics | GET | `/api/v1/admin/analytics/summary` | admin | `api/v1/admin/analytics#summary` | – |
| Admin analytics | GET | `/api/v1/admin/analytics/hotspots` | admin | `api/v1/admin/analytics#hotspots` | – |
| Admin graph | GET | `/api/v1/admin/graph` | admin | `api/v1/admin/graph#show` | `GraphService.assemble_admin_graph` |
| Admin graph | POST | `/api/v1/admin/graph/publish` | admin | `api/v1/admin/graph#publish` | `GraphPublisher.publish` |
| Admin graph | GET | `/api/v1/admin/graph/versions` | admin | `api/v1/admin/graph_versions#index` | – |
| Admin graph | GET | `/api/v1/admin/graph/versions/:version` | admin | `api/v1/admin/graph_versions#show` | – |
| Admin graph | POST | `/api/v1/admin/graph/routes` | admin | `api/v1/admin/graph#create_route` | `GraphService.add_route` |
| Admin graph | DELETE | `/api/v1/admin/graph/routes/:line_id` | admin | `api/v1/admin/graph#delete_route` | `GraphService.delete_route` |
| Admin stations | POST | `/api/v1/admin/stations` | admin | `api/v1/admin/stations#create` | `GraphService.insert_stop` |
| Admin stations | PATCH, PUT | `/api/v1/admin/stations/:id` | admin | `api/v1/admin/stations#update` | `GraphService.bump_version!` |
| Admin stations | DELETE | `/api/v1/admin/stations/:id` | admin | `api/v1/admin/stations#destroy` | `GraphService.remove_stop` |
| Admin edges | PATCH, PUT | `/api/v1/admin/edges/:id` | admin | `api/v1/admin/edges#update` | `GraphService.polyline_distance_km`, `.bump_version!` |
| Admin lines | PATCH, PUT | `/api/v1/admin/lines/:id` | admin | `api/v1/admin/lines#update` | `GraphService.bump_version!` |
| Admin lines | DELETE | `/api/v1/admin/lines/:id` | admin | `api/v1/admin/lines#destroy` | `LineDeletion.call` |
| Admin settings | GET | `/api/v1/admin/settings` | admin | `api/v1/admin/settings#show` | – |
| Admin settings | PATCH | `/api/v1/admin/settings` | admin | `api/v1/admin/settings#update` | – |

Routes that carry a graph ID (`stations/:id`, `routes/:line_id`, and the admin station, edge, line, and route routes) use the `GRAPH_ID` constraint and `format: false`. The ID can contain a dot. Admin graph version routes use `version: /\d+/`.

### Routes that Devise adds

`devise_for :users` also adds these routes. The mobile apps do not use them.

| Method | Path | Note |
|:--|:--|:--|
| GET | `/auth/sign_in` | `sessions#new` |
| DELETE | `/auth/register` | Same action as `DELETE /api/v1/auth/account`. |
| PATCH, PUT | `/auth/register` | Devise `registrations#update`. |
| GET | `/auth/register/sign_up`, `/auth/register/edit`, `/auth/register/cancel` | Devise defaults. |
| GET, POST, PATCH, PUT | `/password/new`, `/password`, `/password/edit` | Devise `passwords` controller. No mailer is configured. |

Rails also mounts Active Storage, Action Mailbox, and Conductor routes under `/rails/`. See [Security](security.md#known-gaps).

---

## Health

### `GET /health`

Auth: none. Rate limit: none.

200: `{ "status": "ok", "db": "connected", "env": "production", "timestamp": "<ISO 8601>" }`.
503: the same keys with `"status": "degraded"` and `"db": "error"`. Render uses this route as the health check.

## Auth

### `POST /auth/register`

Auth: none. Rate limit: `auth/ip`.

Body:

```json
{ "user": { "email": "…", "password": "…", "password_confirmation": "…", "display_name": "…" } }
```

201: `{ "data": { "token": "<jwt>", "user": { "id", "email", "display_name", "role" } } }`. The role is always `commuter`.
422: `{ "error": "Registration failed", "errors": ["…"] }`. 400: the `user` key is missing.

### `POST /auth/sign_in`

Auth: none. Rate limits: `auth/ip`, `auth/email`.

Body: `{ "user": { "email": "…", "password": "…" } }`.
200: `{ "data": { "token": "<jwt>", "user": { "id", "email", "display_name", "role" } } }`. The token is also in the `Authorization` response header.
401: Devise failure body.

### `DELETE /auth/sign_out`

Auth: user. Rate limit: `auth/ip`. 200: `{ "message": "Signed out successfully" }`. The server rotates the user `jti`, so every token of that user stops working.

### `POST /api/v1/auth/refresh`

Auth: user. No body. Rate limit: `api/ip`.

200: the same shape as sign in. The server rotates the `jti`. The token that made the call stops working.
401: `{ "error": "Unauthorized" }`. An expired token also gives 401.

### `DELETE /api/v1/auth/account`

Auth: user. Rate limit: `api/ip`. 200: `{ "message": "Account deleted successfully" }`.
500: `{ "error": "Could not delete account", "message": "<exception text>" }`. See [Known issues](backend.md#known-issues).

## User

### `GET /api/v1/me`

200: `{ "data": { "id", "email", "display_name", "role", "home_station_id", "created_at" } }`.

### `PATCH /api/v1/me`

Body: `{ "user": { "display_name": "…", "home_station_id": "…" } }`. Both keys are optional.
200: `{ "data": { "id", "email", "display_name", "home_station_id" } }`. 422: `{ "error": "Update failed", "errors": [] }`. The server does not check that `home_station_id` exists.

## Graph

### `GET /api/v1/graph/version`

200: `{ "data": { "version": 42, "lastModified": "<ISO 8601>", "stationCount": 60, "edgeCount": 76 } }`.
The counts include hidden rows. 503: `{ "error": "Graph unavailable", "message": "<exception text>" }`.

### `GET /api/v1/graph`

200: `{ "data": <graph document> }`. See [Data Model](data-model.md#the-json-document).
The server leaves out hidden lines, stops, and edges. 503: as above.

## Stations

### `GET /api/v1/stations`

Query keys: `line`, `type`, `interchange` (only the value `true` filters), `search` (`ILIKE` on `name`, `short_name`, `line`).
200: `{ "data": [<station>], "meta": { "count": n } }`, ordered by `line`, then `name`. The result includes hidden stops.

### `GET /api/v1/stations/:id`

200: `{ "data": <station> }`. 404: `{ "error": "Not found", "message": "…" }`.

A station has these keys: `id`, `name`, `short_name`, `line`, `type`, `coordinates { lat, lng }`, `is_terminal`, `is_interchange`, `boarding`, `amenities`, `operating_hours { open, close }`, `access_points`, and `sequence` (only when set).
An access point has `id`, `station_id`, `name`, `kind`, `direction`, `coordinates`, `position`.

## Routes (lines)

### `GET /api/v1/routes`

Query keys: `mode`, `search` (substring of the line ID, upper-cased). The server filters in Ruby after the cache read.
200: `{ "data": [{ "line_id", "mode", "base_fare", "accepted_payments", "is_air_conditioned", "crowd_factor", "reliability", "stop_count" }], "meta": { "count": n } }`.

### `GET /api/v1/routes/:line_id`

200: `{ "data": { "line_id", "mode", "base_fare", "accepted_payments", "is_air_conditioned", "crowd_factor", "reliability", "stations": [], "edges": [] } }`. Edge keys: `id`, `from`, `to`, `mode`, `line`, `travel_time_minutes`, `distance_km`, `base_fare`, `fare_per_km`, `accepted_payments`, `is_air_conditioned`, `crowd_factor`, `reliability`, `bidirectional`, `direction`, `polyline_coordinates`, `mk_directions_transport_type`, `is_road_snapped`.
404: `{ "error": "Route not found" }` when the line has no stations.

## Saved routes

### `GET /api/v1/saved_routes`

200: `{ "data": [{ "id", "name", "origin_station_id", "destination_station_id", "legs", "created_at" }] }`, newest first.

### `POST /api/v1/saved_routes`

Body:

```json
{ "saved_route": { "name": "…", "origin_station_id": "…", "destination_station_id": "…",
  "legs": [{ "line_id": "…", "mode": "…", "from_station": "…", "to_station": "…", "travel_time_minutes": 4 }] } }
```

201: `{ "data": <saved route> }`. 422: `{ "error": "Could not save route", "errors": [] }`.

### `DELETE /api/v1/saved_routes/:id`

200: `{ "message": "Saved route deleted" }`. 404 when the route belongs to another user.

## AR world maps

A map has `status` `pending`, `approved`, or `rejected`. A user who is not an admin sees approved maps only.

### `GET /api/v1/ar_world_maps`

Query keys: `station_id`, `status`, `page`, `items` (Pagy). 200: `{ "data": [<map>], "meta": { "current_page", "total_pages", "total_count", "per_page" } }`.
Map keys: `id`, `station_id`, `version`, `status`, `uploaded_by`, `file_size_mb`, `created_at`.
Warning: this action raises `NoMethodError` today. See [Known issues](backend.md#known-issues).

### `GET /api/v1/ar_world_maps/:id`

200: `{ "data": <map> }` with `download_url` when a file is attached. 404: `{ "error": "Not found" }`, also for a map that is not approved when the user is not an admin.

### `POST /api/v1/ar_world_maps`

Multipart form keys: `station_id`, `map_file`. 201: `{ "data": <map> }` with `status` `pending`. The server sets `version` to the highest version of the station plus one.
400: `{ "error": "map_file is required" }`. 413: `{ "error": "File too large (max 150 MB)" }`. 422: `{ "error": "Upload failed", "errors": [] }`.

### `POST /api/v1/ar_world_maps/:id/relocalize`

Top-level body keys: `accuracy`, `device`. 200: `{ "message": "Logged", "event_count": n }`. The server keeps the last 100 events in `metadata.relocalization_events`. 404 for an unknown map.

## Analytics

### `POST /api/v1/analytics/route_plan`

Rate limits: `analytics/user`, `api/ip`.

```json
{ "event": { "origin_station_id": "…", "destination_station_id": "…", "line_ids": ["MRT3"], "duration_seconds": 1860 } }
```

Always 201 `{ "message": "Logged" }`. The action rescues every error. A write failure looks like success. `duration_seconds` becomes `total_time_minutes` (rounded up). `line_ids` goes to `modes_used`.

## Incidents

### `GET /api/v1/incidents`

200: `{ "data": [{ "id", "station_id", "line_id", "category", "description", "reported_by", "created_at" }] }`. Active incidents only (`expires_at` is null or in the future). Newest first, 50 at most.

### `POST /api/v1/incidents`

Body: `{ "incident": { "station_id", "line_id", "category", "description" } }`. `category` is `delay`, `crowding`, `breakdown`, `closure`, or `other`.
201: `{ "data": <incident> }`. 422: `{ "error": "Could not report incident", "errors": [] }`. A `category` outside the list raises `ArgumentError` (500).

## Places and events

`GET /api/v1/places`, `/api/v1/places/:id`, `/api/v1/events`, and `/api/v1/events/:id` have no controller. The router raises a routing error. Do not call them.

## Admin: users, AR maps, incidents

`/api/v1/admin/users`, `/api/v1/admin/ar_world_maps`, and `/api/v1/admin/incidents` have no controller. The router raises a routing error. Do not call them.

## Admin: analytics

All routes in this section need the `admin` role.

### `GET /api/v1/admin/analytics/summary`

200: `{ "data": { "dau", "wau", "total_users", "route_plans_today", "top_origins": [{ "station_id", "count" }], "top_destinations": [], "mode_share": { "<line id>": n } } }`. Top lists cover 7 days, 5 rows.

### `GET /api/v1/admin/analytics/hotspots`

200: `{ "data": [{ "station_id", "count" }] }`. The 20 top origins of the last 30 days.

## Admin: graph read, publish, history

These routes are in [Ops Publish API](ops-publish-api.md): `GET /api/v1/admin/graph`, `POST /api/v1/admin/graph/publish`, `GET /api/v1/admin/graph/versions`, `GET /api/v1/admin/graph/versions/:version`.
Errors: 400 (not a JSON object), 409 (version conflict or lock busy), 422 (validation), 404 (unknown version).

## Admin: route create and delete

### `POST /api/v1/admin/graph/routes`

Adds a whole line. The server calls `GraphService.add_route(params.to_unsafe_h)`. The body uses camelCase keys.

| Key | Type | Rule |
|:--|:--|:--|
| `lineID` | String | Required. A new line matches `^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$`. An existing line also accepts a dot. No spaces. |
| `displayName` | String | Required. |
| `mode` | String | Required. Must be an ID in `transport_modes`. |
| `baseFare`, `farePerKm` | Number | 0 or more. |
| `crowdFactor`, `reliability` | Number | 0 to 1. |
| `acceptedPayments` | Array of String | At least one. Each must be an ID in `payment_methods`. |
| `isAirConditioned` | Bool | Optional. |
| `openTime`, `closeTime` | String | Required. `HH:mm`. |
| `colorHex` | String | Optional. `#RRGGBB`. |
| `stops` | Array | Flat shape. One pass. Each stop: `name` (required), `lat`, `lng` (required), `shortName`, `polyline` (array of `{ lat, lng }`). |
| `passes` | Array | Multi-pass shape. Each pass: `direction` (`northbound`, `southbound`, or omit), `stops`, `closesLoop`, `closingPolyline`, `bidirectional`, `isRoadSnapped`. |
| `direction`, `bidirectional`, `closesLoop`, `closingPolyline` | | Flat-shape twins of the pass keys. |

Rules: each pass needs 2 or more stops. A direction can appear once. A pass with a `direction` cannot set `bidirectional: true`. A train line cannot take more passes. An existing line accepts a new direction only.
When `bidirectional` is absent, the pass is bidirectional only when it has no `direction`.
The server makes stop IDs `<LINE>_S<n>` or `<LINE>_NB_S<n>`, and edge IDs `<FROM>__<TO>`.

201: `{ "data": { "line_id", "stations_added", "edges_added" } }`.
422: `{ "error": "Validation failed", "errors": ["<message>"] }`. A database failure also gives 422 with the text `Database write failed: …`.

### `DELETE /api/v1/admin/graph/routes/:line_id`

Removes the stops and edges of the line, and every edge that touches a removed stop. It removes the line ID from `transport_modes.lines`. It keeps the `lines` row, the fare rows, and the rail fare table. Use `DELETE /api/v1/admin/lines/:id` to remove those.
200: `{ "data": { "line_id", "stations_removed", "edges_removed" } }`. 422: `{ "error": "Delete failed", "errors": ["No route found with line ID '…'."] }`.

## Admin: stations

### `POST /api/v1/admin/stations`

Inserts one stop. The server calls `GraphService.insert_stop(params.to_unsafe_h)`.

| Key | Rule |
|:--|:--|
| `referenceStationId` | Required. A stop of the line, with an ID that ends in `_S<n>` or `_STOP<n>`. |
| `position` | Required. `before` or `after`. |
| `name` | Required. |
| `lat`, `lng` | Required. |
| `shortName`, `openTime`, `closeTime` | Optional. The defaults come from the name and the reference stop. |
| `newEdgePolylines` | Optional. Array of paths of 3 or more points, in creation order. |

Rules: the server refuses a train stop. A stop with the same name within 5 m on the same chain is the same stop, and the response is 201 with that stop. The server changes `sequence` values only. It never renames a stop or an edge.
201: `{ "data": { "line_id", "station_id" } }`. 422: `{ "error": "Validation failed", "errors": ["…"] }`.

### `PATCH /api/v1/admin/stations/:id`

Body: `{ "station": { … } }`. Every key is optional.

| Key | Rule |
|:--|:--|
| `lat` / `latitude`, `lng` / `longitude` | Applied only when a latitude is present. The server sets both. |
| `name`, `short_name`, `open_time`, `close_time` | Applied when present. The server trims them. |
| `boarding` | `both` or `alight_only`. |
| `access_points` | An array. It replaces the whole set. A door that is absent is deleted. Omit the key to keep the doors. |

An access point has `access_point_id` (or `id`), `name`, `kind` (`entrance`, `exit`, `both`), `direction` (`northbound`, `southbound`, or `null`), `lat`/`lng` (or `coordinates { lat, lng }`), `position`.
200: `{ "data": <station> }`. 404: `{ "error": "Station not found" }`. 422: `{ "error": "Update failed", "errors": [] }`. The action bumps the graph version and busts `stations*`.

### `DELETE /api/v1/admin/stations/:id`

Removes a stop and merges the two adjacent edges. A terminal drops its one edge. The server refuses a train stop, a stop with a non-standard ID, and a chain of 2 stops.
200: `{ "data": { "line_id" } }`. 404: `{ "error": "Station not found" }`. 422: `{ "error": "Delete failed", "errors": ["…"] }`.

## Admin: edges

### `PATCH /api/v1/admin/edges/:id`

Body: `{ "edge": { "polyline_coordinates": [{ "lat", "lng" }], "bidirectional": true, "direction": "northbound" } }`.
Send at least one key. Each key applies on its own. `direction: null` clears the label. The server refuses `bidirectional: true` together with a `direction`.
When the body has `polyline_coordinates`, the server recomputes `distance_km` and sets `is_road_snapped` to `true`. It never changes `travel_time_minutes`.
200: `{ "data": <edge> }`. 404: `{ "error": "Edge not found" }`. 422: `{ "error": "Nothing to update" | "Update failed", "errors": [] }`.

## Admin: lines

### `PATCH /api/v1/admin/lines/:id`

Body: `{ "line": { "color_hex": "#RRGGBB" } }`. `null` clears the color.
200: `{ "data": { "id", "displayName", "mode", "colorHex" } }`. 404: `{ "error": "Line not found" }`. 422: `{ "error": "Nothing to update" | "Update failed", "errors": [] }`.

### `DELETE /api/v1/admin/lines/:id`

See [Ops Publish API](ops-publish-api.md#delete-apiv1adminlinesid). 200: `{ "data": { "line_id", "version" } }`.

## Admin: settings

### `GET /api/v1/admin/settings`

200: `{ "data": { "enforce_operating_hours": true } }`.

### `PATCH /api/v1/admin/settings`

Body: `{ "enforce_operating_hours": false }`. 200: the same shape as GET. The action busts the graph cache. It does not raise the graph version.
