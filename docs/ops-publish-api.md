# Ops Publish API

Last checked against commit `106ae55` on 10/13/26.

The contract between the Gora Operations Dashboard and the backend for the admin graph read,
publish, version history, and line delete. The dashboard builds against this file.

---

## Conventions

| Item | Rule |
|---|---|
| Base URL | `https://commute-backend-a6lj.onrender.com` |
| Auth | Every endpoint in this file needs `Authorization: Bearer <token>` from a user with the `admin` role. |
| Request body | JSON. Send `Content-Type: application/json`. |
| Graph JSON keys | camelCase, the same as `GET /api/v1/graph`. |
| Publish, history, and delete keys | snake_case. |
| Times | ISO 8601 with a UTC offset, for example `2026-10-12T23:04:47+08:00`. |
| Numbers | JSON numbers. A string such as `"5"` is refused. The server stores and returns decimals, for example `15` comes back as `15.0`. |

### Shared errors

| Status | When | Body |
|---|---|---|
| 401 | No token, or the token is not valid. | Devise error body. |
| 429 | More than 60 requests in one minute from one IP address (`api/ip`). | `{ "error": "Too many requests. Please try again later." }` |
| 403 | The user is not an admin. | `{ "error": "Forbidden", "message": "Admin access required" }` |

---

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/v1/admin/graph` | The whole graph, including hidden items, with the ops fields. |
| POST | `/api/v1/admin/graph/publish` | Apply a list of changes as one graph version. |
| GET | `/api/v1/admin/graph/versions` | Published versions, newest first, paged. |
| GET | `/api/v1/admin/graph/versions/:version` | One published version with its change list. |
| DELETE | `/api/v1/admin/lines/:id` | Delete a line that has no stops and no edges. |

---

## GET /api/v1/admin/graph

Returns every line, stop, and edge. The server never caches this response, so `version` is the
current graph version. Send that number as `base_version` when you publish.

**200**

```json
{
  "data": {
    "version": 203,
    "lastModified": "2026-10-12T00:06:50+08:00",
    "enforceOperatingHours": true,
    "metadata": { "region": "Metro Manila, Philippines", "currency": "PHP", "schemaVersion": "3.0.0", "polylineNote": "…" },
    "transportModes": { "bus": { "id": "bus", "lines": ["AYALA_ALABANG", "…"], "…": "…" } },
    "paymentMethods": { "cash": { "…": "…" } },
    "lines": {
      "AYALA_ALABANG": {
        "id": "AYALA_ALABANG",
        "displayName": "Ayala–Alabang",
        "mode": "bus",
        "lastStopNumber": 15,
        "baseKm": 4.0,
        "colorHex": "#A64D0D",
        "enabled": false,
        "disabledReason": "Road works",
        "hiddenFromRiders": true,
        "direction": "one_way"
      }
    },
    "peakHourMultipliers": { "…": "…" },
    "fareMatrix": {
      "MRT3": { "type": "flat_with_distance", "brackets": [{ "fare": 13, "maxStations": 4 }], "maximumFare": 28, "minimumFare": 13 }
    },
    "railFareTables": {
      "MRT3": {
        "stationIds": ["MRT_NORTH_AVE", "MRT_QUEZON_AVE", "MRT_GMA_KAMUNING"],
        "fares": [[null, 13.0, 13.0], [13.0, null, 13.0], [13.0, 13.0, null]]
      }
    },
    "stations": [
      {
        "id": "MRT_TAFT_AVE",
        "name": "Taft Avenue",
        "shortName": "TAFT",
        "line": "MRT3",
        "type": "train",
        "coordinates": { "lat": 14.5376, "lng": 121.0014 },
        "isTerminal": true,
        "isInterchange": true,
        "amenities": [],
        "operatingHours": { "open": "04:30", "close": "22:30" },
        "sequence": 13,
        "accessPoints": [
          { "id": "MRT_TAFT_AVE_AP_1", "name": "Gate 1", "kind": "entrance", "direction": null, "coordinates": { "lat": 14.5372, "lng": 121.0013 } }
        ],
        "enabled": true,
        "disabledReason": null,
        "hiddenFromRiders": false
      }
    ],
    "edges": [
      {
        "id": "AYALA_ALABANG_NB_S1__AYALA_ALABANG_NB_S2",
        "from": "AYALA_ALABANG_NB_S1",
        "to": "AYALA_ALABANG_NB_S2",
        "mode": "bus",
        "line": "AYALA_ALABANG",
        "travelTimeMinutes": 3.0,
        "distanceKm": 1.1,
        "baseFare": 15.0,
        "farePerKm": 2.2,
        "acceptedPayments": ["cash"],
        "isAirConditioned": true,
        "crowdFactor": 0.5,
        "reliability": 0.9,
        "bidirectional": false,
        "direction": "northbound",
        "polylineCoordinates": [{ "lat": 14.5, "lng": 121.0 }, { "lat": 14.51, "lng": 121.0 }],
        "mkDirectionsTransportType": "bus",
        "isRoadSnapped": true,
        "enabled": true,
        "disabledReason": null,
        "hiddenFromRiders": true
      }
    ]
  }
}
```

### Fields that only the admin graph has

| Object | Field | Type | Meaning |
|---|---|---|---|
| line, station, edge | `enabled` | Bool | The stored switch. `false` hides the item from riders. |
| line, station, edge | `disabledReason` | String or null | Staff note. Always `null` when `enabled` is `true`. |
| line, station, edge | `hiddenFromRiders` | Bool | The result of the visibility rule below. Show "Hidden from riders" when it is `true`. |
| line | `direction` | `"both"` or `"one_way"` | The line direction. |

Rules for the admin graph:

- It lists every row, also hidden ones and edges that point at a stop that does not exist.
- `transportModes[*].lines` and `fareMatrix` list every line.
- `railFareTables` holds each table as stored, with no rows removed.
- A line has `colorHex` only when it is set. An edge has `direction` only when it is set. `sequence` is present only when the stop has one.
- `boarding` and `accessPoints` follow the public rules: `boarding` is present only when it is not `"both"`. `accessPoints` is present only when the stop has one or more.

### The visibility rule

The server applies this rule to `GET /api/v1/graph`. The admin graph reports it in `hiddenFromRiders`.

| Item | Hidden from riders when |
|---|---|
| Line | `enabled` is `false`. |
| Station | Its `enabled` is `false`, or its line is hidden. |
| Edge | Its `enabled` is `false`, or its line is hidden, or either end is not a visible station (this includes an end that does not exist). |
| `fareMatrix` entry, `railFareTables` entry, `transportModes[*].lines` entry | Its line is hidden. |
| A row and a column of a public `railFareTables` entry | Its station is hidden. |

A line ID that has no `lines` row counts as visible.

---

## Public graph changes (`GET /api/v1/graph`)

The public JSON keeps every key and every type that the current iOS app decodes. The server
filters hidden items, so the filter works for old app versions with no release.

| Change | Effect on the current iOS app |
|---|---|
| Hidden lines, stations, and edges are left out. | None. Works with old versions. |
| Edges that point at a missing stop are left out (six INTERCHANGE edges on 10/12/26). | None. The app could not use them. |
| `lines[*].baseKm` (number, default `0.0`) is added. | Ignored until the app reads it. The free-distance fare needs an app release. |
| `railFareTables` (top-level object, keyed by line ID) is added. | Ignored until the app reads it. The station-pair fare needs an app release. |
| `fareMatrix` stays the bracket table, unchanged. | None. |
| The ops fields (`enabled`, `disabledReason`, `hiddenFromRiders`, `direction`) are not in the public JSON. | None. |

`GET /api/v1/graph/version` still counts every station and edge row in `stationCount` and `edgeCount`.

### Rail fare table shape

```json
"railFareTables": {
  "LRT2": {
    "stationIds": ["LRT2_RECTO", "LRT2_LEGARDA", "LRT2_PUREZA"],
    "fares": [[null, 15.0, 15.0], [15.0, null, 15.0], [15.0, 15.0, null]]
  }
}
```

`fares[i][j]` is the fare from `stationIds[i]` to `stationIds[j]`. The diagonal is `null`. The
table can be asymmetric. A line with no published table has no entry. Use `fareMatrix` for it.

---

## POST /api/v1/admin/graph/publish

Applies every change in one database transaction. The graph version goes up by exactly one, and
the server writes one row to the version history.

### Request

```json
{
  "base_version": 203,
  "changes": [
    { "type": "line_road_fare", "line_id": "KAYAMANAN_C_PRC", "base_fare": 14, "base_km": 4, "fare_per_km": 1.8 },
    { "type": "stop_enabled", "station_id": "AYALA_ALABANG_NB_S4", "enabled": false, "reason": "Closed for road works" },
    { "type": "access_point_add", "station_id": "MRT_TAFT_AVE", "kind": "exit", "lat": 14.5372, "lng": 121.0013 }
  ]
}
```

| Field | Type | Rule |
|---|---|---|
| `base_version` | Integer | The `version` of the graph that the draft started from. |
| `changes` | Array | 1 to 2000 change objects. Each has a `type` and the fields of that type. |

### Order and validation

1. The server checks the shape of every change. It reports **every** shape error, each with its index. Status 422.
2. The server locks the graph version and compares it with `base_version`. A different version gives 409.
3. The server applies the changes in array order. A later change sees the result of an earlier change. When two changes set the same field, the last one wins.
4. A missing row or a refused rule stops the publish at the **first** such change. Status 422.
5. On any error, the server changes nothing and the version does not move.

An unknown field in a change is an error. A field that is `null` where null is not allowed is an error.

### 201 response

```json
{
  "data": {
    "version": 204,
    "published_at": "2026-10-12T23:04:47+08:00",
    "published_by": { "id": "bee409c5-57fb-483d-9093-92123a59a19b", "display_name": "Ops Admin" },
    "change_count": 3,
    "created": [
      { "index": 2, "type": "access_point_add", "id": "MRT_TAFT_AVE_AP_826846F6" }
    ]
  }
}
```

`created` lists the ID of each row that an add change made. It is `[]` when no change adds a row.

After a 201, the server deletes the `full_graph`, `graph_version`, and `stations*` cache entries. It does not delete `routes_index`, so `GET /api/v1/routes` can show old fares for up to 30 minutes.

### Error responses

**400** — the body is not valid JSON, or it is not a JSON object.

```json
{ "error": "Bad request", "message": "The body is not valid JSON." }
{ "error": "Bad request", "message": "Send a JSON object." }
```

**409** — the graph changed after the draft started. Reload `GET /api/v1/admin/graph`, rebase the draft, and publish again.

```json
{
  "error": "Version conflict",
  "base_version": 202,
  "current_version": 203,
  "message": "The graph changed after this draft started. Reload the graph and publish again."
}
```

**409** — another write holds the graph lock. Send the same request again.

```json
{ "error": "Graph busy", "message": "Another write holds the graph. Try again." }
```

**422** — one or more changes are not valid.

```json
{
  "error": "Validation failed",
  "errors": [
    { "index": 1, "type": "edge_enabled", "field": "edge_id", "message": "Edge 'OPST_NONE' was not found." }
  ]
}
```

| Error field | Type | Meaning |
|---|---|---|
| `index` | Integer | The position of the change in `changes`. Absent for an error in `base_version` or `changes` itself. |
| `type` | String | The `type` of the change. Absent when the change is not an object. |
| `field` | String | The field with the problem, for example `fares[1][2]`. Absent when the problem is not one field. |
| `message` | String | Text for staff. |

---

## Change types

### Field types

| Name | Rule |
|---|---|
| ID | A non-empty string with no white space, 120 characters or fewer. The row must exist. Legacy IDs (with a dot) are accepted. |
| New ID | Matches `^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$`. Uppercase letters, digits, and single underscores. |
| Name | A string, trimmed, 1 to 120 characters. |
| Short name | A string, trimmed, 1 to 20 characters. |
| Label | A string, trimmed, 0 to 120 characters. |
| Reason | A string of 200 characters or fewer, or `null`. An empty string becomes `null`. |
| Bool | `true` or `false`. |
| Color | `"#RRGGBB"`, any case, or `null`. The server stores it in uppercase. `null` clears the color. |
| Time | `"HH:mm"`, 24-hour, `00:00` to `23:59`. |
| Number ≥ 0 | A JSON number, 0 or more. |
| Number > 0 | A JSON number, more than 0. |
| Lat, Lng | A JSON number from -90 to 90, and from -180 to 180. |
| Path | An array of two or more `{ "lat": Lat, "lng": Lng }` objects. |
| Boundary | An array of 3 to 200 `{ "lat": Lat, "lng": Lng }` objects. The ring must not cross itself. A last point equal to the first is dropped. |

For each `*_enabled` change: when `enabled` is `true`, the server stores `reason` as `null`.

### Summary

| `type` | Target | Writes |
|---|---|---|
| `line_name` | Line | `display_name` |
| `line_color` | Line | `color_hex` |
| `line_direction` | Line | `direction`, and `bidirectional` on every edge of the line. `"both"` also clears `direction` on every edge of the line. |
| `line_enabled` | Line | `enabled`, `disabled_reason` |
| `line_road_fare` | Line | `base_fare` and `fare_per_km` on every edge of the line, `base_km` on the line |
| `line_rail_fares` | Line | The station-pair fare table of the line |
| `line_delete` | Line | Deletes the line |
| `stop_name` | Station | `name` |
| `stop_short_name` | Station | `short_name` |
| `stop_boarding` | Station | `boarding` |
| `stop_fare_km` | Station | `fare_km` |
| `stop_hours` | Station | `open_time`, `close_time` |
| `stop_enabled` | Station | `enabled`, `disabled_reason` |
| `edge_travel_time` | Edge | `travel_time_minutes` |
| `edge_distance` | Edge | `distance_km` |
| `edge_enabled` | Edge | `enabled`, `disabled_reason` |
| `access_point_add` | Station | Adds an access point |
| `access_point_update` | Access point | The fields that you send |
| `access_point_delete` | Access point | Deletes the access point |
| `transfer_add` | Two stations | Adds an INTERCHANGE edge |
| `transfer_update` | INTERCHANGE edge | The fields that you send |
| `transfer_delete` | INTERCHANGE edge | Deletes the edge |
| `service_area_add` | New line | Adds a tricycle service area line, its boundary, and its terminals |
| `service_area_boundary` | Service area | `boundary` |
| `service_area_fare` | Service area | The fare fields and `accepted_payments` |
| `service_area_timing` | Service area | `speed_kmh`, `detour_factor`, `wait_minutes` |
| `service_area_terminal_add` | Service area | Adds a terminal stop |
| `service_area_terminal_delete` | Station | Deletes a terminal stop and its transfers |
| `payment_method_add` | New payment method | Adds a `payment_methods` row |
| `payment_method_update` | Payment method | The fields that you send |
| `payment_method_delete` | Payment method | Deletes the row |
| `line_payments` | Line | `accepted_payments` on every edge of the line |
| `mode_default_payments` | Mode | `default_accepted_payments` |
| `service_schedule_set` | Line, or one direction | Replaces its `service_schedules` rows |
| `service_schedule_clear` | Line, or one direction | Deletes its `service_schedules` rows |
| `service_exception_add` | Line, or one direction | Adds a `service_schedule_exceptions` row |
| `service_exception_update` | Exception | The fields that you send |
| `service_exception_delete` | Exception | Deletes the row |

### Line changes

```json
{ "type": "line_name", "line_id": "AYALA_ALABANG", "name": "Ayala–Alabang" }
{ "type": "line_color", "line_id": "AYALA_ALABANG", "color_hex": "#A64D0D" }
{ "type": "line_color", "line_id": "AYALA_ALABANG", "color_hex": null }
{ "type": "line_direction", "line_id": "GUADALUPE_BUENDIA", "direction": "one_way" }
{ "type": "line_enabled", "line_id": "UPLB_KANAN", "enabled": false, "reason": "Route suspended" }
{ "type": "line_road_fare", "line_id": "KAYAMANAN_C_PRC", "base_fare": 14, "base_km": 4, "fare_per_km": 1.8 }
{ "type": "line_rail_fares", "line_id": "LRT2", "station_ids": ["LRT2_RECTO", "LRT2_LEGARDA"], "fares": [[null, 15], [15, null]] }
{ "type": "line_delete", "line_id": "STA_CRUZ_BUENDIA" }
```

| `type` | Field | Type | Required |
|---|---|---|---|
| `line_name` | `line_id` | ID | Yes |
| | `name` | Name | Yes |
| `line_color` | `line_id` | ID | Yes |
| | `color_hex` | Color | Yes (send `null` to clear) |
| `line_direction` | `line_id` | ID | Yes |
| | `direction` | `"both"` or `"one_way"` | Yes |
| `line_enabled` | `line_id` | ID | Yes |
| | `enabled` | Bool | Yes |
| | `reason` | Reason | Yes (send `null` for none) |
| `line_road_fare` | `line_id` | ID | Yes |
| | `base_fare` | Number ≥ 0 | Yes |
| | `base_km` | Number ≥ 0 | Yes |
| | `fare_per_km` | Number ≥ 0 | Yes |
| `line_rail_fares` | `line_id` | ID | Yes |
| | `station_ids` | Array of ID, two or more, no repeats | Yes |
| | `fares` | Array of rows. Each row is an array of Number ≥ 0 or `null`. | Yes |
| `line_delete` | `line_id` | ID | Yes |

Rules:

- `line_direction`: `"both"` sets `bidirectional: true` and clears the compass `direction` on every edge of the line. `"one_way"` sets `bidirectional: false` and keeps each edge `direction`.
- The server refuses `"both"` when the edges of the line have two or more compass directions, for example `northbound` and `southbound`. Those edges are separate chains, and two-way chains would duplicate the route.
- The server refuses `"both"` while the line has a `service_schedules` or `service_schedule_exceptions` row with a direction. Such a row matches no edge after the clear. Send `service_schedule_clear` or `service_exception_delete` for that direction first, in the same request or an earlier one.
- `line_road_fare`: the road fare is `base_fare + max(0, km - base_km) * fare_per_km`. The server writes `base_fare` and `fare_per_km` to every edge whose `line` is the line, hidden edges included. It writes `base_km` to the line. It refuses a line whose mode is `train` or `walk`, and a line with no edges.
- `line_rail_fares`: the line mode must be `train`. Every station in `station_ids` must have `line` equal to `line_id`. The table does not need every station of the line. `fares` has one row and one column for each station. The diagonal must be `null` or `0`; the server stores `null`. Every other cell needs a number. The change replaces the whole table. It does not change `fareMatrix`.
- `line_delete`: see [DELETE /api/v1/admin/lines/:id](#delete-apiv1adminlinesid). The rules are the same, but the publish raises the version once for all its changes.
- The `INTERCHANGE` line refuses `line_direction`, `line_enabled`, `line_road_fare`, `line_rail_fares`, and `line_delete`. It accepts `line_name` and `line_color`.

### Stop changes

```json
{ "type": "stop_name", "station_id": "MRT_TAFT_AVE", "name": "Taft Avenue" }
{ "type": "stop_short_name", "station_id": "MRT_TAFT_AVE", "short_name": "TAFT" }
{ "type": "stop_boarding", "station_id": "AYALA_ALABANG_NB_S4", "boarding": "alight_only" }
{ "type": "stop_fare_km", "station_id": "AYALA_ALABANG_NB_S4", "fare_km": 12.5 }
{ "type": "stop_hours", "station_id": "MRT_TAFT_AVE", "open": "04:30", "close": "22:30" }
{ "type": "stop_enabled", "station_id": "AYALA_ALABANG_NB_S4", "enabled": false, "reason": "Closed for road works" }
```

| `type` | Field | Type | Required |
|---|---|---|---|
| all | `station_id` | ID | Yes |
| `stop_name` | `name` | Name | Yes |
| `stop_short_name` | `short_name` | Short name | Yes |
| `stop_boarding` | `boarding` | `"both"` or `"alight_only"` | Yes |
| `stop_fare_km` | `fare_km` | Number of 0 or more, or `null` | Yes (road stops only) |
| `stop_hours` | `open`, `close` | Time | Yes, both |
| `stop_enabled` | `enabled` | Bool | Yes |
| | `reason` | Reason | Yes (send `null` for none) |

Dashboard mapping: `Boarding.pickUpAndDropOff` is `"both"`. `Boarding.dropOffOnly` is `"alight_only"`.
The server has no "no hours" state. A stop always has an open and a close time.

### Edge changes

```json
{ "type": "edge_travel_time", "edge_id": "MRT_TAFT_AVE__MRT_MAGALLANES", "travel_time_minutes": 3.5 }
{ "type": "edge_distance", "edge_id": "MRT_TAFT_AVE__MRT_MAGALLANES", "distance_km": 1.92 }
{ "type": "edge_enabled", "edge_id": "MRT_TAFT_AVE__MRT_MAGALLANES", "enabled": false, "reason": null }
```

| `type` | Field | Type | Required |
|---|---|---|---|
| all | `edge_id` | ID | Yes |
| `edge_travel_time` | `travel_time_minutes` | Number > 0 | Yes |
| `edge_distance` | `distance_km` | Number > 0 | Yes |
| `edge_enabled` | `enabled` | Bool | Yes |
| | `reason` | Reason | Yes (send `null` for none) |

`edge_distance` does not change the travel time or the polyline. These changes work on any edge, INTERCHANGE edges included.

### Access point changes

```json
{ "type": "access_point_add", "station_id": "MRT_TAFT_AVE", "access_point_id": "MRT_TAFT_AVE_AP_3", "name": "Gate 3", "kind": "entrance", "direction": "southbound", "lat": 14.5372, "lng": 121.0013 }
{ "type": "access_point_add", "station_id": "MRT_TAFT_AVE", "kind": "exit", "lat": 14.5372, "lng": 121.0013 }
{ "type": "access_point_update", "access_point_id": "MRT_TAFT_AVE_AP_3", "name": "Gate 3A", "direction": null }
{ "type": "access_point_update", "access_point_id": "MRT_TAFT_AVE_AP_3", "lat": 14.5373, "lng": 121.0015 }
{ "type": "access_point_delete", "access_point_id": "MRT_TAFT_AVE_AP_3" }
```

| `type` | Field | Type | Required |
|---|---|---|---|
| `access_point_add` | `station_id` | ID | Yes |
| | `kind` | `"entrance"`, `"exit"`, or `"both"` | Yes |
| | `lat`, `lng` | Lat, Lng | Yes |
| | `access_point_id` | New ID, not in use | No |
| | `name` | Label | No (default `""`) |
| | `direction` | `"northbound"`, `"southbound"`, or `null` | No (default `null`) |
| `access_point_update` | `access_point_id` | ID | Yes |
| | `name`, `kind`, `direction` | As above | Send one or more fields |
| | `lat`, `lng` | Lat, Lng | Send both or neither |
| `access_point_delete` | `access_point_id` | ID | Yes |

Rules:

- When `access_point_id` is absent, the server makes `<STATION>_AP_<8 hex digits>`. `<STATION>` is the station ID with each run of other characters (such as a dot) replaced by one underscore. The response `created` list and the history row hold the ID.
- Send `access_point_id` when a later change in the same publish must refer to the new access point.
- A new access point goes after the last access point of the station.
- `direction: null` means the access point serves every direction.

### Transfer changes

A transfer is an edge on the reserved `INTERCHANGE` line with mode `walk`.

```json
{ "type": "transfer_add", "from_station_id": "KAYAMANAN_C_PRC_SB_S12", "to_station_id": "MRT_MAGALLANES", "travel_time_minutes": 3, "distance_km": 0.16, "polyline": [{ "lat": 14.5420, "lng": 121.0190 }, { "lat": 14.5418, "lng": 121.0195 }] }
{ "type": "transfer_update", "edge_id": "X__KAYAMANAN_C_PRC_SB_S12__MRT_MAGALLANES", "travel_time_minutes": 4 }
{ "type": "transfer_delete", "edge_id": "X__KAYAMANAN_C_PRC_SB_S12__MRT_MAGALLANES" }
```

| `type` | Field | Type | Required |
|---|---|---|---|
| `transfer_add` | `from_station_id`, `to_station_id` | ID that also matches the New ID rule | Yes |
| | `travel_time_minutes` | Number > 0 | Yes |
| | `distance_km` | Number ≥ 0 | Yes |
| | `polyline` | Path | Yes |
| | `bidirectional` | Bool | No (default `true`) |
| `transfer_update` | `edge_id` | ID of an INTERCHANGE edge | Yes |
| | `travel_time_minutes`, `distance_km`, `polyline` | As above | Send one or more |
| `transfer_delete` | `edge_id` | ID of an INTERCHANGE edge | Yes |

Rules:

- The new edge ID is `X__<FROM_STATION>__<TO_STATION>`. The server refuses a station ID that does not match the New ID rule, because the edge ID would break the graph ID convention. Legacy IDs with a dot cannot take part in a new transfer.
- The two stations must exist and must be different.
- The server refuses a transfer when an INTERCHANGE edge already joins the two stations, in either direction, under any ID.
- The new edge has `baseFare: 0`, `farePerKm: 0`, every payment method, `isAirConditioned: false`, `crowdFactor: 0.8`, `reliability: 1.0`, `direction: null`, `mkDirectionsTransportType: "walking"`, and `isRoadSnapped: false`.
- The server stores `polyline` and `distance_km` as sent. It does not snap the path to the stations and does not compute the distance.
- `transfer_add` sets `isInterchange: true` on both stations. `transfer_delete` sets `isInterchange: false` on each end station that has no other INTERCHANGE edge.
- `transfer_update` and `transfer_delete` refuse an edge whose line is not `INTERCHANGE`.

### Payment changes

```json
{ "type": "payment_method_add", "payment_method_id": "maribank", "name": "MariBank", "sf_symbol": "building.columns.fill", "color_hex": "#FF5722", "is_default": false, "accepted_by_modes": ["jeepney"], "notes": "QR scan on the vehicle terminal." }
{ "type": "payment_method_update", "payment_method_id": "gcash", "accepted_by_modes": ["jeepney", "train"] }
{ "type": "payment_method_delete", "payment_method_id": "maribank" }
{ "type": "line_payments", "line_id": "MRT3", "accepted_payments": ["beep_card", "cash", "gcash", "card"] }
{ "type": "mode_default_payments", "mode_id": "jeepney", "accepted_payments": ["cash"] }
```

| `type` | Field | Type | Required |
|---|---|---|---|
| `payment_method_add` | `payment_method_id` | Payment ID: matches `^[a-z][a-z0-9]*(_[a-z0-9]+)*$`, not in use | Yes |
| | `name` | Name | Yes |
| | `sf_symbol` | Label | No (default `""`) |
| | `color_hex` | `"#RRGGBB"`, any case. Not `null`. | No (default `"#000000"`) |
| | `is_default` | Bool | No (default `false`) |
| | `accepted_by_modes` | Array of mode ID, no repeats, can be empty | No (default `[]`) |
| | `notes` | A string, trimmed, 0 to 500 characters | No (default `""`) |
| `payment_method_update` | `payment_method_id` | ID | Yes |
| | `name`, `sf_symbol`, `color_hex`, `is_default`, `accepted_by_modes`, `notes` | As above | Send one or more |
| `payment_method_delete` | `payment_method_id` | ID | Yes |
| `line_payments` | `line_id` | ID | Yes |
| | `accepted_payments` | Array of payment ID, one or more, no repeats | Yes |
| `mode_default_payments` | `mode_id` | ID | Yes |
| | `accepted_payments` | Array of payment ID, one or more, no repeats | Yes |

Rules:

- `name` writes the `display_name` column.
- Every mode in `accepted_by_modes` must exist in `transport_modes`. Every ID in `accepted_payments` must exist in `payment_methods`. A payment method that an earlier change in the same publish adds counts.
- `payment_method_add` does not add the new ID to any edge or mode default. Send `line_payments` or `mode_default_payments` for that.
- `payment_method_delete` removes the ID from every INTERCHANGE edge and from the default of each mode with `is_always_allowed: true`. Walks pass every payment filter in the app, so these lists have no effect on routes.
- `payment_method_delete` refuses the change while any other edge, any service area, or the default of any other mode lists the ID. The message names the lines, the service areas, and the modes.
- `line_payments` writes every edge whose `line` is the line, hidden edges included. It refuses `INTERCHANGE`, a service area line (use `service_area_fare`), and a line with no edges.
- `mode_default_payments` works on any mode. The default applies to a new line that `POST /api/v1/admin/graph/routes` creates without `acceptedPayments`. It does not change existing edges.

### Service area changes

A service area is a tricycle line that has a boundary and terminal stops, but no edges. The
fields, the rules, and the graph JSON are in [tricycle-service-areas.md](tricycle-service-areas.md).
`line_road_fare` and `line_direction` refuse a service area line. `line_delete` also deletes
the service area and its terminals.

### Service schedule changes

A service schedule gives a line, or one direction of it, service days and trip times. A date
exception changes the service for a date range. The fields, the rules, and the graph JSON are
in [service-schedules.md](service-schedules.md). `service_exception_add` reports the new ID as
`exception_id` in `created`.

---

## GET /api/v1/admin/graph/versions

Lists published versions, newest first. Each row leaves out the change list. The history starts
at the first publish. A version made by another admin endpoint (for example `PATCH
/api/v1/admin/stations/:id`) has no row.

| Query | Default | Rule |
|---|---|---|
| `page` | 1 | 1 or more. A page past the end returns `[]`. |
| `per_page` | 20 | 1 to 100. |

**200**

```json
{
  "data": [
    {
      "version": 205,
      "published_at": "2026-10-12T23:10:02+08:00",
      "published_by": { "id": "bee409c5-57fb-483d-9093-92123a59a19b", "display_name": "Ops Admin" },
      "change_count": 1
    }
  ],
  "meta": { "current_page": 1, "total_pages": 3, "total_count": 41, "per_page": 20 }
}
```

`published_by` is `null` when the user account no longer exists.

## GET /api/v1/admin/graph/versions/:version

**200**

```json
{
  "data": {
    "version": 204,
    "published_at": "2026-10-12T23:04:47+08:00",
    "published_by": { "id": "bee409c5-57fb-483d-9093-92123a59a19b", "display_name": "Ops Admin" },
    "change_count": 2,
    "changes": [
      { "type": "stop_name", "station_id": "MRT_TAFT_AVE", "name": "Taft Avenue" },
      { "type": "access_point_add", "station_id": "MRT_TAFT_AVE", "kind": "exit", "lat": 14.5372, "lng": 121.0013, "access_point_id": "MRT_TAFT_AVE_AP_826846F6" }
    ]
  }
}
```

`changes` holds the clean changes as the server applied them: trimmed text, uppercase colors,
numbers as decimals, and the ID of each created row. The key order inside a change can differ
from the request.

**404**

```json
{ "error": "Version not found" }
```

---

## DELETE /api/v1/admin/lines/:id

Deletes a line that no station and no edge uses. The server also removes the line ID from
`transportModes[*].lines`, and deletes its `fareMatrix` row and its rail fare table. The graph
version goes up by one. This endpoint does not write a history row.

**200**

```json
{ "data": { "line_id": "STA_CRUZ_BUENDIA", "version": 206 } }
```

**404**

```json
{ "error": "Line not found" }
```

**422**

```json
{ "error": "Delete failed", "errors": ["Line 'AYALA_ALABANG' still has 28 stops and 26 edges. Delete the route first."] }
```

The server also gives 422 for `INTERCHANGE`. To delete a line with stops, use `DELETE
/api/v1/admin/graph/routes/:line_id` first, then this endpoint. The route delete keeps the `lines` row.

---

## Database fields behind this API

| Table | Column | Type | Default |
|---|---|---|---|
| `lines`, `stations`, `edges` | `enabled` | boolean, not null | `true` |
| `lines`, `stations`, `edges` | `disabled_reason` | string | `null` |
| `lines` | `base_km` | decimal(6,2), not null, `>= 0` | `0` |
| `lines` | `direction` | string, not null, `both` or `one_way` | `both`. Migration 028 sets `one_way` on each line with a one-way edge. |
| `rail_fare_tables` | `line_id` (key), `station_ids` (jsonb), `fares` (jsonb) | | |
| `graph_versions` | `version` (unique), `published_at`, `published_by_id` (users, null on delete), `change_list` (jsonb), `change_count` | | |
