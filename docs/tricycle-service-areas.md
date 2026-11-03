# Tricycle service areas

A tricycle does not run on a fixed path. It carries a rider between any two points inside a
boundary that its operator association (TODA) serves. Gora models this as a **service area**:
a boundary polygon on a line, plus one or more terminal stops. A service area has no edges.

The server stores and publishes each service area. The iOS router builds the tricycle rides
when it plans a route, in the same way that it builds `ACCESS_WALK` edges.

## Decisions

| Topic | Decision |
|---|---|
| Fare | The line fare rule: `base_fare + max(0, km - base_km) * fare_per_km`. An optional `special_trip_fare` is the fare for a private ride. The router does not use it; the app shows it. |
| Drop-off | A ride can start and end at any point inside the boundary. |
| Overlap | Two service areas can overlap. TODA boundaries often overlap. |
| Mode | `transport_modes.service_shape` is `path` or `area`. `tricycle` is `area`. A write reads this column, never the mode name. |
| `TRICYCLE_MANILA` | It stays a path line until a separate data change converts it. |

## Data model

`transport_modes.service_shape` — string enum, `path` (default) or `area`.

`service_areas` — one row for each line that has `service_shape = area`.

| Column | Type | Rule |
|---|---|---|
| `line_id` | text PK, FK to `lines.id` | The line ID convention in `CLAUDE.md` |
| `boundary` | jsonb `[{ "lat", "lng" }, ...]` | 3 to 200 vertices, an open ring, no self-intersection |
| `base_fare`, `base_km`, `fare_per_km` | decimal | 0 or more |
| `special_trip_fare` | decimal, nullable | 0 or more |
| `speed_kmh` | decimal | More than 0. Default 15 |
| `detour_factor` | decimal | 1 or more. Default 1.3 |
| `wait_minutes` | decimal | 0 or more. Default 3 |
| `accepted_payments` | text[] | One or more ids from `payment_methods` |

A terminal stop is a `stations` row on the service area's line. Its ID is `<LINE>_S<n>`, from
`lines.last_stop_number`. It has `is_terminal = true` and no `sequence`. It must be inside the
boundary. A `transfer_add` change links a terminal to a stop on another line.

The service area uses `lines.enabled` for visibility. A disabled line hides the service area and
its terminals from riders.

## Routing rule for the iOS router

A tricycle ride connects any two points that are inside the same boundary. A point is the
rider's origin pin, the destination pin, a terminal, or an enabled stop of any line.

| Value | Formula |
|---|---|
| Distance (km) | Straight-line distance × `detourFactor` |
| Time (minutes) | `waitMinutes` + distance ÷ `speedKmh` × 60 |
| Fare | `baseFare` + max(0, distance − `baseKm`) × `farePerKm` |

Connect each pin to the 5 nearest stops inside the boundary, so that A* stays fast. Use the
operating hours of the terminals.

## Graph JSON

`GET /api/v1/graph` and `GET /api/v1/admin/graph` carry a top-level `serviceAreas` array. Each
transport mode carries `serviceShape`. An older iOS build ignores both keys.

```json
"serviceAreas": [{
  "line": "SAN_ROQUE_TODA", "mode": "tricycle",
  "boundary": [{ "lat": 14.6512, "lng": 121.0321 }, { "lat": 14.6540, "lng": 121.0365 },
               { "lat": 14.6498, "lng": 121.0390 }],
  "terminalIds": ["SAN_ROQUE_TODA_S1"],
  "baseFare": 15, "baseKm": 1, "farePerKm": 5, "specialTripFare": 50,
  "speedKmh": 15, "detourFactor": 1.3, "waitMinutes": 3,
  "acceptedPayments": ["cash"]
}]
```

The public graph omits a service area whose line is disabled. It also removes the hidden
terminals from `terminalIds`.

## Publish change types

The dashboard sends these changes to `POST /api/v1/admin/graph/publish`. See
[ops-publish-api.md](ops-publish-api.md) for the request rules that every change follows.

| Type | Required | Optional | Effect |
|---|---|---|---|
| `service_area_add` | `line_id`, `name`, `mode`, `boundary`, `terminals`, `base_fare`, `base_km`, `fare_per_km`, `accepted_payments`, `open`, `close` | `color_hex`, `special_trip_fare`, `speed_kmh`, `detour_factor`, `wait_minutes` | Creates the line, the service area, and the terminals. The terminals get `<LINE>_S1` to `<LINE>_S<n>` in the order sent. |
| `service_area_boundary` | `line_id`, `boundary` | | Replaces the boundary. Every terminal must stay inside it. |
| `service_area_fare` | `line_id`, `base_fare`, `base_km`, `fare_per_km` | `special_trip_fare` (null clears it), `accepted_payments` | Sets the fare. |
| `service_area_timing` | `line_id` | `speed_kmh`, `detour_factor`, `wait_minutes` (send at least one) | Sets the values that the router uses for time and distance. |
| `service_area_terminal_add` | `line_id`, `name`, `lat`, `lng` | `short_name` | Adds a terminal. The 201 response lists its ID in `created`. |
| `service_area_terminal_delete` | `station_id` | | Deletes a terminal and its transfers. A service area keeps at least one terminal. |

These existing change types also work on a service area line: `line_name`, `line_color`,
`line_enabled`, `line_delete`, `stop_name`, `stop_short_name`, `stop_hours`, `stop_enabled`,
`access_point_*`, and `transfer_*`. `line_delete` deletes the service area and its terminals.
`line_road_fare` and `line_direction` refuse a service area line.

`POST /api/v1/admin/graph/routes` refuses a mode that has `service_shape = area`.

## Rollout

1. Backend: the migrations, the publish change types, and the graph JSON.
2. Dashboard: a polygon editor on the map, terminal pins, a fare form, and the new change types.
3. iOS: decode `serviceAreas`, and add the tricycle rides to the router.
4. Data: convert `TRICYCLE_MANILA` to a service area through Hachi, after approval.
