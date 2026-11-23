# Road fares

A road leg (any mode that is not `train` or `walk`) costs the distance fare plus the toll share.
See `toll-fares.md` for the toll share.

## Distance fare

```
fare km     = |fareKm(alighting stop) - fareKm(boarding stop)|   when both stops have fareKm
            = sum of the leg's edge distanceKm                     otherwise
distance fare = baseFare + max(0, fare km - line baseKm) * farePerKm
```

- `baseFare` and `farePerKm` come from the first edge of the leg.
- `baseKm` comes from the line (`lines[<line>].baseKm` in the graph JSON). A missing value is 0.
- A leg with no edge that has `farePerKm > 0` costs `baseFare` only.

Example: Sta. Cruz–LRT Buendia, Olivarez to Dela Rosa Stop, fare km 60, base fare 12.25, 2.45/km,
base km 5: `12.25 + 55 * 2.45 = 147.00`. With the toll share of 29.00, the total is 176.00.

## Fare km of a stop

A stop's fare km is its fare distance from the start terminal of its line. Stops in one terminal
bracket share one value. The operator sets it in the dashboard. A stop without a value uses the
measured distance.

| Item | Value |
|---|---|
| Column | `stations.fare_km` decimal(7,2) null, >= 0 |
| Graph JSON | station key `fareKm`, omitted when null |
| Publish change | `stop_fare_km`: `station_id`, `fare_km` (number >= 0, or null) |
| Refusals | A stop whose type is `train` or `walk`. A negative value. |

The fare km difference does not depend on the direction of travel, so one value serves both
directions of a two-way line.

## Fare distance step of a line

A line can round the fare km up to the next multiple of a step before the distance fare formula
uses it. A null or 0 step uses the exact fare km.

| Item | Value |
|---|---|
| Column | `lines.fare_step_km` decimal(6,2) null, >= 0 |
| Graph JSON | line key `fareStepKm`, a number or null |
| Publish change | `line_road_fare`, optional `fare_step_km` (number >= 0, or null). An absent key keeps the value. |

## Fare km rounding of a line

A line sets how the app rounds a part step of fare km. `"up"` counts the part step. `"down"` drops it.
A null value means `"up"`.

| Item | Value |
|---|---|
| Column | `lines.fare_km_rounding` string null, one of `up` or `down` |
| Graph JSON | line key `fareKmRounding`, a string or null |
| Publish change | `line_road_fare`, optional `fare_km_rounding` (`"up"`, `"down"`, or null). An absent key keeps the value. |

The server stores and sends both values. It does not compute fares.
