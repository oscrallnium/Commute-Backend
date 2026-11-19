# Toll fares

A road line that uses an expressway adds a toll share to the rider's fare. The rider pays the
vehicle toll divided by the toll load factor of the line, rounded to the nearest ₱0.25.
Example: Calamba to Buendia is ₱582.00. With a load factor of 20, the share is ₱29.10, which
rounds to ₱29.00.

## Data

| Table | Columns | Notes |
|---|---|---|
| `toll_plazas` | `id` TEXT PK, `name` TEXT not null | `id` follows the graph ID characters rule: `^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$`. |
| `toll_fares` | `entry_plaza_id` FK, `exit_plaza_id` FK, `amount` decimal(8,2) >= 0 | One row for each pair. The pair is unique. Entry and exit differ. A missing pair means that no toll fare exists. |
| `edges` | `toll_entry_plaza_id` FK null, `toll_exit_plaza_id` FK null | The vehicle enters the expressway on this edge, or leaves it on this edge. |
| `lines` | `toll_load_factor` integer null, > 0 | The number of riders that share one vehicle toll. Null means that the line adds no toll share. |

The matrix holds Class 2 (bus) tolls. There is one matrix and no vehicle class column.

## Plaza IDs from `data/toll_matrix.json`

The file is `{ "<entry name>": { "<exit name>": amount | null } }`. The row is the entry plaza.
The column is the exit plaza. A null cell is not imported.

| Name | ID | Name | ID |
|---|---|---|---|
| Magallanes | `MAGALLANES` | Susana Heights | `SUSANA_HEIGHTS` |
| Buendia | `BUENDIA` | San Pedro | `SAN_PEDRO` |
| C-5 | `C5` | Southwoods | `SOUTHWOODS` |
| Amorsolo | `AMORSOLO` | Carmona | `CARMONA` |
| Bicutan | `BICUTAN` | Mamplasan | `MAMPLASAN` |
| Magallanes (Skyway) | `MAGALLANES_SKYWAY` | Sta. Rosa | `STA_ROSA` |
| NAIAX | `NAIAX` | ABI/Greenfield | `ABI_GREENFIELD` |
| Sucat | `SUCAT` | Cabuyao | `CABUYAO` |
| Alabang | `ALABANG` | Silangan | `SILANGAN` |
| Filinvest | `FILINVEST` | Calamba | `CALAMBA` |
| MCX | `MCX` | Merville | `MERVILLE` |
| | | Don Bosco | `DON_BOSCO` |

## Graph JSON (`GET /api/v1/graph`)

```json
{
  "tollPlazas": [{ "id": "BUENDIA", "name": "Buendia" }],
  "tollFares": { "CALAMBA": { "BUENDIA": 582.0 } },
  "lines": { "LINE_ID": { "tollLoadFactor": 20 } },
  "edges": [{ "id": "...", "tollEntryPlaza": "CALAMBA", "tollExitPlaza": null }]
}
```

- `tollFares` is keyed by entry plaza, then by exit plaza.
- An edge omits `tollEntryPlaza` and `tollExitPlaza` when they are null.
- A line has `tollLoadFactor: null` when no load factor is set.
- Clients decode all of these keys as optional. An older graph has none of them.

## Publish changes (`POST /api/v1/admin/graph/publish`)

| Type | Fields | Rules |
|---|---|---|
| `toll_matrix` | `plazas`: `[{id, name}]`, `fares`: `[{entry, exit, amount}]` | Replaces every plaza and every fare. Refuses an ID that breaks the ID rule, a duplicate ID, an unknown plaza in a fare, an entry equal to its exit, a duplicate pair, and a negative amount. Refuses removal of a plaza that an edge references. |
| `edge_toll` | `edge_id`, `entry_plaza_id` (string or null), `exit_plaza_id` (string or null) | Sets both edge columns. Refuses an unknown plaza. Refuses an INTERCHANGE edge and an edge whose mode is `train` or `walk`. |
| `line_toll_load_factor` | `line_id`, `load_factor` (integer > 0, or null) | Sets `lines.toll_load_factor`. Refuses INTERCHANGE and lines whose mode is `train` or `walk`. |

The server applies `toll_matrix` before `edge_toll`, so one publish can add a plaza and tag an
edge with it.

## Fare rule (iOS)

For each ride leg, in edge order:

1. An edge with `tollEntryPlaza` opens a toll segment at that plaza.
2. An edge with `tollExitPlaza` closes the open segment at that plaza.
3. On an edge that has both plazas: if a segment is open, close it first, then open the new one.
   If no segment is open, open the segment and then close it on the same edge.
4. The toll of a closed segment is `tollFares[entry][exit]`. A missing pair adds nothing.
5. A segment that is still open at the end of the leg adds nothing.
6. The leg's toll share is `sum of segment tolls / tollLoadFactor`, rounded to the nearest
   ₱0.25. No `tollLoadFactor` adds nothing.

The fare of the leg is the road fare plus the toll share.
