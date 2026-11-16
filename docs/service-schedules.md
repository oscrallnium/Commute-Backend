# Service schedules

A service schedule gives a line, or one direction of a line, service days and service times.
A date exception changes the service for a date range. Rails stores both and sends them in the
graph JSON. The A* engine on iOS applies them.

A line that has no schedule rows and no exception runs at all hours that its station windows
allow.

## Tables

### `service_schedules`

| Column | Type | Rule |
|---|---|---|
| `id` | uuid | |
| `line_id` | string, NOT NULL | FK to `lines.id`, `ON DELETE CASCADE` |
| `direction` | string, null allowed | A key of `GraphService::DIRECTION_TAGS`. Null means every direction of the line. |
| `days` | string array | One or more of `GraphService::SERVICE_DAYS` (`mon` to `sun`), no repeats |
| `kind` | string enum | `window` or `departures` (`GraphService::SCHEDULE_KINDS`) |
| `start_time`, `end_time` | string | `HH:mm`. Required for `window`, and not equal. An end before the start crosses midnight. |
| `departure_times` | string array | `HH:mm`, sorted, no repeats. Required for `departures`. Each time is when a trip leaves the first stop of the direction. |
| `note` | string | Optional text for riders |

### `service_schedule_exceptions`

| Column | Type | Rule |
|---|---|---|
| `id` | uuid | |
| `line_id` | string, NOT NULL | FK to `lines.id`, `ON DELETE CASCADE` |
| `direction` | string, null allowed | As above |
| `start_date`, `end_date` | date | Philippine dates, inclusive. `end_date` is not before `start_date` (DB check). |
| `kind` | string enum | `no_service`, `window`, or `departures` (`GraphService::EXCEPTION_KINDS`) |
| `start_time`, `end_time`, `departure_times`, `note` | | As above. `no_service` has no times. |

Two exceptions on one line cannot overlap in dates when their directions are equal or when
either direction is null.

`ServiceTimes` (`app/models/concerns/service_times.rb`) holds the time rules of both models.

### `graph_meta.scheduled_max_wait_minutes`

The longest wait, in minutes, that the app accepts for a scheduled trip. Integer from 1 to 600,
default 60. See [API reference → Admin: settings](api-reference.md#admin-settings).

## How a direction is identified

A line has one `lines` row. Its directions differ only in `edges.direction`. A schedule row with
a direction applies to the edges of the line that have that direction. A row with a null
direction applies to every edge of the line. Never read a direction from a station ID or an
edge ID.

## Graph JSON

`GET /api/v1/graph` and `GET /api/v1/admin/graph` carry three top-level keys:

```json
"scheduledMaxWaitMinutes": 60,
"serviceSchedules": {
  "UP_DILIMAN_UPLB": [
    { "direction": "northbound", "kind": "departures", "departures": ["05:00", "13:00"],
      "days": ["mon", "tue", "wed", "thu", "fri"] },
    { "direction": "southbound", "kind": "window", "start": "18:00", "end": "22:00",
      "days": ["sat"], "note": "Saturday service" }
  ]
},
"serviceScheduleExceptions": {
  "UP_DILIMAN_UPLB": [
    { "id": "<uuid>", "kind": "no_service", "from": "2026-12-24", "to": "2027-01-03",
      "note": "Holiday break" }
  ]
}
```

- `direction` and `note` appear only when set. `start` and `end` appear only for `window`.
  `departures` appears only for `departures`.
- A line without rows is absent. The public graph leaves out lines that riders cannot see.
- Only exceptions with `end_date` today or later (Asia/Manila) are sent.

## Publish changes

Send these through `POST /api/v1/admin/graph/publish`. See [Ops Publish API](ops-publish-api.md).

```json
{ "type": "service_schedule_set", "line_id": "UP_DILIMAN_UPLB", "direction": "southbound",
  "schedules": [
    { "days": ["mon", "tue", "wed", "thu", "fri"], "kind": "departures", "departures": ["09:00", "18:00"] },
    { "days": ["sat"], "kind": "departures", "departures": ["05:00", "18:00"] }
  ] }
{ "type": "service_schedule_clear", "line_id": "UP_DILIMAN_UPLB", "direction": "southbound" }
{ "type": "service_exception_add", "line_id": "UP_DILIMAN_UPLB", "start_date": "2026-12-24",
  "end_date": "2027-01-03", "kind": "no_service", "note": "Holiday break" }
{ "type": "service_exception_update", "exception_id": "<uuid>", "end_date": "2027-01-05" }
{ "type": "service_exception_delete", "exception_id": "<uuid>" }
```

| `type` | Field | Required |
|---|---|---|
| `service_schedule_set` | `line_id` | Yes |
| | `direction` | No. Without it, the change replaces every row of the line. |
| | `schedules`: one or more items `{ days, kind, start?, end?, departures?, note? }`, one kind for all items | Yes |
| `service_schedule_clear` | `line_id`, `direction` (optional) | |
| `service_exception_add` | `line_id`, `start_date`, `end_date`, `kind` | Yes |
| | `direction`, `start`, `end`, `departures`, `note` | No |
| `service_exception_update` | `exception_id` | Yes |
| | Any field of `service_exception_add` except `line_id` | Send one or more |
| `service_exception_delete` | `exception_id` | Yes |

Rules:

- Dates are `YYYY-MM-DD`. Times are `HH:mm`, 24-hour. The validator sorts `departures`.
- The times must fit the kind: `window` needs `start` and `end`, `departures` needs
  `departures`, and `no_service` takes no times.
- An update that sends `kind` must also send the times of the new kind. The old times are
  cleared.
- The writer refuses an unknown line, `INTERCHANGE`, a service area line, a direction that no
  edge of the line uses, and an unknown `exception_id`.
- A `service_schedule_set` with a direction is refused while the line has rows with a null
  direction. Send a set without a direction, or clear first.
- `service_exception_add` reports the new ID as `exception_id` in `created`.
- `ServiceScheduleWriter` (`app/services/service_schedule_writer.rb`) does the database checks
  and the writes.
- Deleting a line deletes its schedule rows and exceptions.

## Rules for the iOS engine

| Case | Rule |
|---|---|
| `enforceOperatingHours` is false | Ignore all schedules |
| Matching rows | A ride edge matches the rows of its `line` whose `direction` equals the edge's `direction`, or is null |
| The date is inside a matching exception | Use the exception. Ignore the regular rows. `no_service` makes the edge not usable. |
| `window` | Boarding is allowed only inside a window for that day. The days of a window that crosses midnight are the days on which it starts. |
| `departures` | A trip reaches a stop at its departure time plus the edge times from the first stop of the direction. The rider boards the next trip at or after the arrival time. The wait counts in the trip time. |
| Station windows | Still apply |

The full product plan, with the Scheduled result card, is outside this repository.
