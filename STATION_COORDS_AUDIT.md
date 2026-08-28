# Station Coordinates Audit — MRT-3 / LRT-1 / LRT-2

**Date:** 2026-07-16
**Scope:** All 46 rail stations in the Supabase `stations` table (`lat`, `lng` columns).
**Verdict:** 34 of 46 stations have erroneous coordinates, off by **200 m to 4.4 km**.

## Methodology

Each station's DB `lat`/`lng` was compared against two independent map sources:

1. **OpenStreetMap** — centroid of the actual station footprint (Overpass API, `railway=station`). OSM is the base data used by many map apps and matches Google/Apple Maps placement closely.
2. **Wikipedia geodata API** — the surveyed coordinates on each station's article.

The two sources agree with each other within **≤56 m** for every station, so they are treated as ground truth. Corrected values below are the OSM station centroids rounded to 6 decimals (~0.1 m precision). Stations with a DB offset ≤150 m (roughly one platform length) are considered OK.

## Error patterns (why so many are wrong)

- **LRT-1 Taft Avenue stretch (Libertad → United Nations) and northern stretch (Carriedo → 5th Ave):** longitudes drift progressively east of the real line. The seed data appears to have been interpolated along a straight line with the wrong bearing — errors grow from ~270 m to ~4.2 km with distance from the anchor stations (EDSA and Central Terminal, which are correct).
- **LRT1_BALINTAWAK / LRT1_ROOSEVELT:** placed as if LRT-1 continued straight north along Rizal Ave; in reality the line turns east along EDSA after Monumento. Roosevelt is 4.4 km off.
- **LRT-2:** every station between the endpoints is off by 290 m – 2.1 km; the eastern stations (Santolan, Marikina-Pasig) are placed 1.5–2.1 km too far north.
- **MRT-3:** mostly good, but Santolan-Annapolis is 1.3 km off (its latitude is roughly Cubao's), and Quezon Ave / GMA-Kamuning / Araneta-Cubao are 300–560 m off.

---

## Erroneous stations and corrected values

### LRT-1 (17 of 20 wrong)

| station_id | Name | DB lat | DB lng | ✅ Correct lat | ✅ Correct lng | Off by |
|---|---|---|---|---|---|---|
| LRT1_LIBERTAD | Libertad | 14.5437 | 121.0028 | 14.547751 | 120.998637 | 635 m |
| LRT1_GIL_PUYAT | Gil Puyat | 14.5504 | 121.0079 | 14.554181 | 120.997166 | 1.2 km |
| LRT1_VITO_CRUZ | Vito Cruz | 14.5567 | 121.0122 | 14.563470 | 120.994751 | 2.0 km |
| LRT1_QUIRINO | Quirino | 14.5628 | 121.0156 | 14.570288 | 120.991526 | 2.7 km |
| LRT1_PEDRO_GIL | Pedro Gil | 14.5681 | 121.0194 | 14.576575 | 120.988020 | 3.5 km |
| LRT1_UN_AVE | United Nations | 14.5741 | 121.0231 | 14.582526 | 120.984624 | 4.2 km |
| LRT1_CARRIEDO | Carriedo | 14.5994 | 120.9839 | 14.599170 | 120.981364 | 274 m |
| LRT1_DOROTEO_JOSE | Doroteo Jose | 14.6061 | 120.9872 | 14.605309 | 120.982050 | 561 m |
| LRT1_BAMBANG | Bambang | 14.6100 | 120.9889 | 14.611133 | 120.982487 | 701 m |
| LRT1_TAYUMAN | Tayuman | 14.6161 | 120.9922 | 14.616715 | 120.982723 | 1.0 km |
| LRT1_BLUMENTRITT | Blumentritt | 14.6222 | 120.9956 | 14.622784 | 120.982890 | 1.4 km |
| LRT1_ABAD_SANTOS | Abad Santos | 14.6283 | 120.9989 | 14.630606 | 120.981405 | 1.9 km |
| LRT1_R_PAPA | R. Papa | 14.6344 | 121.0022 | 14.636014 | 120.982279 | 2.2 km |
| LRT1_5TH_AVE | 5th Avenue | 14.6406 | 121.0056 | 14.644406 | 120.983536 | 2.4 km |
| LRT1_BALINTAWAK | Balintawak | 14.6628 | 120.9833 | 14.657424 | 121.003896 | 2.3 km |
| LRT1_ROOSEVELT | Roosevelt (Fernando Poe Jr.) | 14.6711 | 120.9828 | 14.657559 | 121.021137 | 4.4 km |

### LRT-2 (12 of 13 wrong)

| station_id | Name | DB lat | DB lng | ✅ Correct lat | ✅ Correct lng | Off by |
|---|---|---|---|---|---|---|
| LRT2_RECTO | Recto | 14.6011 | 120.9844 | 14.603507 | 120.983371 | 290 m |
| LRT2_LEGARDA | Legarda | 14.6011 | 120.9889 | 14.600877 | 120.992569 | 396 m |
| LRT2_PUREZA | Pureza | 14.6011 | 121.0022 | 14.601677 | 121.005094 | 318 m |
| LRT2_V_MAPA | V. Mapa | 14.6011 | 121.0139 | 14.604090 | 121.017114 | 480 m |
| LRT2_J_RUIZ | J. Ruiz | 14.6044 | 121.0189 | 14.610569 | 121.026099 | 1.0 km |
| LRT2_GILMORE | Gilmore | 14.6111 | 121.0256 | 14.613536 | 121.034146 | 959 m |
| LRT2_BETTY_GO_BELMONTE | Betty Go-Belmonte | 14.6144 | 121.0322 | 14.618597 | 121.042706 | 1.2 km |
| LRT2_CUBAO | Araneta Center-Cubao | 14.6194 | 121.0522 | 14.622861 | 121.053125 | 398 m |
| LRT2_ANONAS | Anonas | 14.6194 | 121.0644 | 14.627986 | 121.064723 | 955 m |
| LRT2_KATIPUNAN | Katipunan | 14.6278 | 121.0756 | 14.631083 | 121.072916 | 465 m |
| LRT2_SANTOLAN | Santolan | 14.6361 | 121.0878 | 14.622108 | 121.085964 | 1.6 km |
| LRT2_MARIKINA | Marikina-Pasig | 14.6394 | 121.0978 | 14.620441 | 121.100648 | 2.1 km |

### MRT-3 (5 of 13 wrong)

| station_id | Name | DB lat | DB lng | ✅ Correct lat | ✅ Correct lng | Off by |
|---|---|---|---|---|---|---|
| MRT_QUEZON_AVE | Quezon Avenue | 14.6428 | 121.0356 | 14.642555 | 121.038575 | 321 m |
| MRT_GMA_KAMUNING | GMA-Kamuning | 14.6354 | 121.0381 | 14.635347 | 121.043294 | 559 m |
| MRT_ARANETA_CUBAO | Araneta Center-Cubao | 14.6231 | 121.0524 | 14.619484 | 121.051073 | 427 m |
| MRT_SANTOLAN | Santolan-Annapolis | 14.6194 | 121.0574 | 14.607856 | 121.056524 | 1.3 km |
| MRT_TAFT_AVE | Taft Avenue | 14.5369 | 121.0006 | 14.537564 | 121.001818 | 151 m |

## Stations verified OK (≤150 m, no change needed)

| station_id | Off by | | station_id | Off by |
|---|---|---|---|---|
| LRT1_BACLARAN | 59 m | | MRT_ORTIGAS | 29 m |
| LRT1_EDSA | 5 m | | MRT_SHAW_BLVD | 48 m |
| LRT1_CENTRAL | 62 m | | MRT_GUADALUPE | 135 m |
| LRT1_MONUMENTO | 10 m | | MRT_BUENDIA | 36 m |
| LRT2_ANTIPOLO | 95 m | | MRT_AYALA | 58 m |
| MRT_NORTH_AVE | 33 m | | MRT_MAGALLANES | 28 m |
| MRT_BONI* | 203 m | | MRT_TAFT_AVE* | — |

\* MRT_BONI is 203 m off (DB 14.5756 → correct 14.573774, 121.048189) — just over threshold, included in the fix below. MRT_TAFT_AVE at 151 m is borderline and also included.

---

## Implementation notes (for the agent applying this)

⚠️ **Ownership:** per `CLAUDE.md`, the `stations` table is **owned and seeded by the Hono microservice (`commutebeh-api`)**, not Rails. Do **not** write a Rails migration. The fix has two parts:

1. **Update the Hono seed data** in `commutebeh-api` (the station seed file) with the corrected values so future reseeds are correct.
2. **Apply the SQL below to production Supabase** to fix the live table now.

Also check whether `transit_graph_v3.json` (served via `GET /api/v1/graph`) embeds station coordinates — if so, it must be regenerated after the DB fix, and iOS clients will pick it up via `/graph/version`.

`LRT1_ROOSEVELT` was renamed "Fernando Poe Jr." in 2021 — coordinate fix below uses the real (renamed) station location; renaming is a separate product decision.

### SQL fix

```sql
BEGIN;
-- LRT-1
UPDATE stations SET lat = 14.547751, lng = 120.998637 WHERE station_id = 'LRT1_LIBERTAD';
UPDATE stations SET lat = 14.554181, lng = 120.997166 WHERE station_id = 'LRT1_GIL_PUYAT';
UPDATE stations SET lat = 14.563470, lng = 120.994751 WHERE station_id = 'LRT1_VITO_CRUZ';
UPDATE stations SET lat = 14.570288, lng = 120.991526 WHERE station_id = 'LRT1_QUIRINO';
UPDATE stations SET lat = 14.576575, lng = 120.988020 WHERE station_id = 'LRT1_PEDRO_GIL';
UPDATE stations SET lat = 14.582526, lng = 120.984624 WHERE station_id = 'LRT1_UN_AVE';
UPDATE stations SET lat = 14.599170, lng = 120.981364 WHERE station_id = 'LRT1_CARRIEDO';
UPDATE stations SET lat = 14.605309, lng = 120.982050 WHERE station_id = 'LRT1_DOROTEO_JOSE';
UPDATE stations SET lat = 14.611133, lng = 120.982487 WHERE station_id = 'LRT1_BAMBANG';
UPDATE stations SET lat = 14.616715, lng = 120.982723 WHERE station_id = 'LRT1_TAYUMAN';
UPDATE stations SET lat = 14.622784, lng = 120.982890 WHERE station_id = 'LRT1_BLUMENTRITT';
UPDATE stations SET lat = 14.630606, lng = 120.981405 WHERE station_id = 'LRT1_ABAD_SANTOS';
UPDATE stations SET lat = 14.636014, lng = 120.982279 WHERE station_id = 'LRT1_R_PAPA';
UPDATE stations SET lat = 14.644406, lng = 120.983536 WHERE station_id = 'LRT1_5TH_AVE';
UPDATE stations SET lat = 14.657424, lng = 121.003896 WHERE station_id = 'LRT1_BALINTAWAK';
UPDATE stations SET lat = 14.657559, lng = 121.021137 WHERE station_id = 'LRT1_ROOSEVELT';
-- LRT-2
UPDATE stations SET lat = 14.603507, lng = 120.983371 WHERE station_id = 'LRT2_RECTO';
UPDATE stations SET lat = 14.600877, lng = 120.992569 WHERE station_id = 'LRT2_LEGARDA';
UPDATE stations SET lat = 14.601677, lng = 121.005094 WHERE station_id = 'LRT2_PUREZA';
UPDATE stations SET lat = 14.604090, lng = 121.017114 WHERE station_id = 'LRT2_V_MAPA';
UPDATE stations SET lat = 14.610569, lng = 121.026099 WHERE station_id = 'LRT2_J_RUIZ';
UPDATE stations SET lat = 14.613536, lng = 121.034146 WHERE station_id = 'LRT2_GILMORE';
UPDATE stations SET lat = 14.618597, lng = 121.042706 WHERE station_id = 'LRT2_BETTY_GO_BELMONTE';
UPDATE stations SET lat = 14.622861, lng = 121.053125 WHERE station_id = 'LRT2_CUBAO';
UPDATE stations SET lat = 14.627986, lng = 121.064723 WHERE station_id = 'LRT2_ANONAS';
UPDATE stations SET lat = 14.631083, lng = 121.072916 WHERE station_id = 'LRT2_KATIPUNAN';
UPDATE stations SET lat = 14.622108, lng = 121.085964 WHERE station_id = 'LRT2_SANTOLAN';
UPDATE stations SET lat = 14.620441, lng = 121.100648 WHERE station_id = 'LRT2_MARIKINA';
-- MRT-3
UPDATE stations SET lat = 14.642555, lng = 121.038575 WHERE station_id = 'MRT_QUEZON_AVE';
UPDATE stations SET lat = 14.635347, lng = 121.043294 WHERE station_id = 'MRT_GMA_KAMUNING';
UPDATE stations SET lat = 14.619484, lng = 121.051073 WHERE station_id = 'MRT_ARANETA_CUBAO';
UPDATE stations SET lat = 14.607856, lng = 121.056524 WHERE station_id = 'MRT_SANTOLAN';
UPDATE stations SET lat = 14.537564, lng = 121.001818 WHERE station_id = 'MRT_TAFT_AVE';
UPDATE stations SET lat = 14.573774, lng = 121.048189 WHERE station_id = 'MRT_BONI';
COMMIT;
```

### Post-fix verification

- Re-run the distance check: every station should now be ≤60 m from the OSM/Wikipedia reference.
- Sanity-check adjacent-station spacing: LRT-1 stations along Taft should be ~0.6–1.2 km apart, monotonic south→north.
- If `edges` store distances/durations derived from station coordinates, recompute them — 3–4 km position errors mean the current edge distances between the affected stations are wrong too.
