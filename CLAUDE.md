# CLAUDE.md — commutebeh-rails

> Read this at the start of every session. Single source of truth for this service.

---

## Role in the architecture

`commutebeh-rails` is the **user-facing API** for Gora. It handles:
- User auth (register, login, logout, token refresh, account deletion)
- User profile and preferences
- Saved routes (commuter bookmarks)
- AR World Map uploads and relocalization logging
- Analytics ingestion (iOS logs A* route plans here)
- Incidents (community-reported service disruptions)
- Admin dashboard endpoints (analytics summary, hotspots, user management)
- Graph data proxied from the Hono microservice (`commutebeh-api`)

It does **not**:
- Compute routes (A* runs on-device in Swift)
- Write to `transit_graph_v3.json` (that's the Hono microservice)
- Run jobs that require real-time processing

---

## Stack

| Layer | Tech |
|-------|------|
| Framework | Rails 7.1 API-only |
| Auth | Devise + devise-jwt (JTI denylist via `jti` column on users) |
| Database | PostgreSQL (Supabase) — UUID PKs via pgcrypto |
| File storage | Active Storage → Supabase Storage (S3-compatible) |
| Background jobs | Sidekiq + Redis |
| Rate limiting | Rack::Attack |
| Deploy | Koyeb (compute) + Supabase (Postgres + Storage) |

---

## Services

Two services run in this project:

```
commutebeh-rails  →  port 3000  — this Rails app
commutebeh-api    →  port 3001  — Hono microservice (transit graph writes)
```

Rails proxies graph reads from the Hono service via `HONO_API_URL`.

---

## File map

```
app/controllers/
  application_controller.rb        — error rescues, pagination helpers
  health_controller.rb             — GET /health (no auth)
  api/v1/
    base_controller.rb             — authenticate_user!, require_admin!, helpers
    users_controller.rb            — GET/PATCH /me
    stations_controller.rb         — GET /stations, /stations/:id
    routes_controller.rb           — GET /routes, /routes/:line_id
    saved_routes_controller.rb     — CRUD /saved_routes
    ar_world_maps_controller.rb    — CRUD + /relocalize
    analytics_controller.rb        — POST /analytics/route_plan
    incidents_controller.rb        — GET/POST /incidents
    graph_controller.rb            — proxies /graph and /graph/version from Hono
    auth/
      sessions_controller.rb       — sign_in, sign_out, refresh
      registrations_controller.rb  — register, account deletion

app/models/
  user.rb           — Devise + JWT, role enum
  station.rb        — TEXT PK (station_id), maps to Hono-seeded stations table
  edge.rb           — TEXT PK (edge_id), maps to Hono-seeded edges table
  saved_route.rb
  ar_world_map.rb   — has_one_attached :map_file
  route_plan_event.rb
  incident.rb

db/migrate/
  001 — enable_extensions (pgcrypto, pg_trgm, unaccent)
  002 — create_users
  003 — create_saved_routes
  004 — create_ar_world_maps
  005 — create_route_plan_events
  006 — create_incidents
  007 — create_active_storage_tables
  008 — add_trgm_search_indexes
```

---

## Auth flow

```
POST /auth/register   { user: { email, password, password_confirmation, display_name } }
  → 201  { data: { token, user: { id, email, display_name, role } } }

POST /auth/sign_in    { user: { email, password } }
  → 200  { data: { token, user } }

DELETE /auth/sign_out
  Authorization: Bearer <token>
  → 200  { message }

POST /api/v1/auth/refresh
  Authorization: Bearer <token>
  → 200  { data: { token, user } }   # old token revoked, new JTI issued

DELETE /api/v1/auth/account          # App Store compliance
  Authorization: Bearer <token>
  → 200  { message }
```

---

## Key endpoint inventory

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /health | None | Liveness + DB check |
| POST | /auth/register | None | Create account |
| POST | /auth/sign_in | None | Login → JWT |
| DELETE | /auth/sign_out | Bearer | Logout (JTI revoked) |
| POST | /api/v1/auth/refresh | Bearer | Rotate token |
| DELETE | /api/v1/auth/account | Bearer | Delete account |
| GET | /api/v1/me | Bearer | Current user profile |
| PATCH | /api/v1/me | Bearer | Update display_name, home_station_id |
| GET | /api/v1/graph/version | None | Graph staleness check |
| GET | /api/v1/graph | None | Full transit graph JSON |
| GET | /api/v1/stations | None | Station list (filterable) |
| GET | /api/v1/stations/:id | None | Single station |
| GET | /api/v1/routes | None | Route list |
| GET | /api/v1/routes/:line_id | None | Single route + stops + edges |
| GET | /api/v1/saved_routes | Bearer | User's saved commutes |
| POST | /api/v1/saved_routes | Bearer | Save a route |
| DELETE | /api/v1/saved_routes/:id | Bearer | Remove saved route |
| GET | /api/v1/ar_world_maps | Bearer | List AR maps |
| GET | /api/v1/ar_world_maps/:id | Bearer | Single map + download URL |
| POST | /api/v1/ar_world_maps | Bearer | Upload ARWorldMap (multipart) |
| POST | /api/v1/ar_world_maps/:id/relocalize | Bearer | Log relocalization event |
| POST | /api/v1/analytics/route_plan | Bearer | Log iOS A* route plan |
| GET | /api/v1/incidents | Bearer | Active incidents |
| POST | /api/v1/incidents | Bearer | Report incident |
| GET | /api/v1/admin/analytics/summary | Admin | DAU/WAU, mode share |
| GET | /api/v1/admin/analytics/hotspots | Admin | Top origins (30d) |
| GET | /api/v1/admin/users | Admin | User list |

---

## Graph tables

Rails owns the `stations` and `edges` tables. `GraphService` writes them, and Rails migrations
change their schema (for example `020_defer_station_access_points_fk.rb`). Both use TEXT
primary keys (`station_id`, `edge_id`); see "Graph ID convention" below.

---

## Invariants

- **JWT in memory only** — iOS stores token in Keychain; web admin stores in memory variable. Never localStorage.
- **isTerminal is Hono-owned** — inferred by the Hono seed, never set by Rails or the client.
- **N+1 is a bug** — all list endpoints must use `includes()` for associated records.
- **150 MB upload cap** — enforced before Active Storage processing in `ArWorldMapsController`.
- **100-entry ring buffer** — relocalization events on `ar_world_maps.metadata` capped at 100.
- **Analytics never block** — `AnalyticsController#route_plan` rescues all errors and returns 201 regardless, so iOS commutes are never blocked by a logging failure.

---

## Graph ID convention

An ID identifies a record and never changes. Names live in `name` or `display_name`. Meaning
lives in columns: `mode`, `direction`, and `stations.sequence` for stop order. Never encode
order, direction, or mode in an ID so that code can read them back.

Every new ID follows this standard. Existing IDs that do not match stay valid until a rename
migration replaces them. Code must accept both forms until then.

| Key | Format | Example |
|---|---|---|
| Characters (all graph IDs) | `^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$` — uppercase, digits, single underscores. No hyphen, no dot. | |
| Line | A short service code. No mode word. | `MRT3`, `EDSA_CAROUSEL`, `AYALA_ALABANG` |
| Stop chain | `<LINE>` for one chain, `<LINE>_<DIR>` per direction. `<DIR>` is `NB`, `SB`, `EB`, `WB`, `IN`, or `OUT`. | `AYALA_ALABANG_SB` |
| Named station | `<LINE>_<NAME>` | `MRT3_TAFT_AVE` |
| Generated stop | `<CHAIN>_S<n>`. `n` comes from the per-line counter `lines.last_stop_number`, so it is never reused or renumbered. Order comes from `sequence`. | `AYALA_ALABANG_NB_S4` |
| Line edge | `<FROM_STATION>__<TO_STATION>` in the direction of travel. A double underscore separates the stations. | `AYALA_ALABANG_NB_S1__AYALA_ALABANG_NB_S2` |
| Transfer edge | `X__<FROM_STATION>__<TO_STATION>` | `X__LRT1_EDSA__MRT_TAFT_AVE` |
| Mode, payment method | Lowercase snake case | `bus`, `beep_card` |

Rules:

- Validate an ID in one place, `GraphService`, before any write. Reject a new ID that does not
  match its format.
- Read a stop's chain or order from columns, not from its ID. Legacy `_STOP<n>` and `_SEG<n>`
  IDs exist; treat their numbers as names, not as positions.
- Inserting or removing a stop changes `sequence` values only. It never renames a station or
  an edge. Tables such as `saved_routes`, `incidents`, and `ar_world_maps` store station IDs
  with no foreign key, so a rename silently points them at a different stop.
- `INTERCHANGE` is a reserved system line for transfer walks. Do not rename it. The iOS
  engine reads it to skip fares and to stop leg merges.
- Write a `display_name` in Title Case. Put an en dash (–) between the two end points:
  `Ayala–Alabang`, `Guadalupe–LRT Buendia`.

### Direction guide

Pick the chain shape from how the service runs:

| Service shape | Chain ID | `edges.bidirectional` | `edges.direction` |
|---|---|---|---|
| Rail that runs both ways on one track (LRT-1, LRT-2) | One chain, `<LINE>` | `true` | `null` |
| Two one-way paths (MRT-3, most buses and jeepneys) | `<LINE>_<DIR>` for each path | `false` | Required |
| Closed loop in one direction (Guadalupe–LRT Buendia) | One chain, `<LINE>`, with an edge from the last stop to the first | `false` | `null` |

Pick `<DIR>` with these rules:

1. Compare the first stop with the last stop. If the latitude change is larger than the
   longitude change, use `NB` or `SB`. If not, use `EB` or `WB`.
2. Use `IN` or `OUT` only when one end is a hub and a compass word confuses riders. `IN` goes
   toward the hub.
3. Store the full lowercase word in `edges.direction`: `northbound`, `southbound`, `eastbound`,
   `westbound`, `inbound`, or `outbound`.
4. Read a direction from `edges.direction` only. Never parse it from an ID.
5. Show riders the headsign, not the direction code, when a headsign exists.

---

## Writing style — ASD-STE100

Write all prose in this repository in ASD-STE100 (Simplified Technical English). This applies
to code comments, documentation, commit messages, and pull request bodies. It does not apply to
user-facing text in API error messages, which stays natural.

- Use one word for one meaning. Do not call the same thing a "stop" in one place and a
  "station" in another.
- Use the active voice. Write "The service renumbers the stops", not "The stops are renumbered".
- Use the present tense for facts and the imperative for instructions.
- Keep procedural sentences to 20 words or fewer. Keep descriptive sentences to 25 or fewer.
- Write one instruction per sentence.
- Keep articles. Write "Drop the first coordinate", not "Drop first coordinate".
- Avoid gerunds and noun clusters. Write "an edge that has no polyline", not "a polyline-less edge".
- Do not use slang, idioms, or metaphor.
- Start a paragraph with its main point.

---

## Comments

A comment describes what the code does now. **Three lines is a hard ceiling** per method,
class, or constant. Trim to the rule itself and move the rest out.

```ruby
# [Wrong] narrates history and a past bug
# The old code wrote an empty polyline here "for Explore to snap later", but Explore never
# wrote back, so UPLB_KANAN_SEG8 stayed empty. Fixed after the 2026-08 audit.
poly = pin_polyline_ends(supplied_polys.first, from, to)

# [Correct] states the rule and the one fact that explains it
# The client's fetched road route is the only geometry for a head or tail insert.
poly = pin_polyline_ends(supplied_polys.first, from, to)
```

Do not write:

- What a developer asked for, or when.
- What the code used to do, or which bug changed it. Words such as "used to", "previously",
  "now uses", "instead of the old", and "fixed the bug where" do not belong in a comment.
- Dates, ticket numbers, audit references, or names.
- A restatement of the method signature or of what the code already shows.

Do write a constraint when breaking it causes a defect. State it as a present-tense rule:

```ruby
# Renames one stop id in every table that holds it. A table that is missing here keeps the
# old id and points at a different stop after a renumber.
def rename_stop!(old_id, new_id)
```

Rationale that only explains why a change was made belongs in the commit message or the pull
request. A long explanation belongs in a Markdown file next to the code; point to it from a
one-line comment.

---

## Clean code

- Give each name one clear meaning. Name a method after what it returns or does, not how it
  does it. Do not abbreviate.
- Keep a method to one task, and short enough to read on one screen. Extract a block when it
  needs a comment to explain what it does — the extracted name replaces the comment.
- Avoid a boolean argument that switches behaviour inside a method. Split it into two named
  methods instead.
- Keep the argument list short. Use keyword arguments once a method takes more than three.
- Prefer a guard clause and an early return over nested conditionals.
- Remove duplicate logic. Put a shared rule in one place, such as a service method or a
  concern, and call it from every site.
- Handle an error where you can act on it. Do not rescue an error only to re-raise it
  unchanged, and do not rescue `StandardError` to hide a defect.
- Remove dead code and commented-out code. Git history keeps the old version.
- Keep controllers thin. A controller reads params, calls one service, and renders the result.
  Validation and persistence rules live in the service or the model.
- Treat an N+1 query as a defect. Use `includes` for every association that a list endpoint
  serialises.

---

## SOLID

- **Single responsibility** — give each class one reason to change. Split a service that
  parses input, writes rows, and formats output into separate objects.
- **Open/closed** — add behaviour through a new class, method, or strategy. Do not add a branch
  to a shared method for every new case.
- **Liskov substitution** — a subclass or a duck-typed collaborator honours every promise of
  the type it replaces. Do not override a method to raise or to change its return shape.
- **Interface segregation** — depend only on the methods you call. Split a large service so
  that each caller gets the small interface it needs.
- **Dependency inversion** — pass a collaborator in, for example through `initialize`, when a
  test needs to replace it. Do not construct a network client or an external service inside
  the method that uses it.

Apply these principles at the level the code already uses: controllers, service objects such as
`GraphService`, and models. Do not add a layer of indirection where one concrete class already
serves every caller.

---

## Agent orchestration

Opus 5.5 (`claude-opus-5-5`) is the orchestrator. Sonnet 5.5 (`claude-sonnet-5-5`) and Haiku 5.5 (`claude-haiku-5-5`) are the implementors. This is the default for every task in this project.

- **Opus 5.5 does**: read the request, research the codebase, ask the user questions, write the plan, split the work, and review the result.
- **Sonnet 5.5 does**: code edits that need judgement. Start each one with the `Agent` tool and `model: "sonnet"`.
- **Haiku 5.5 does**: code edits that the brief fully defines. Start each one with the `Agent` tool and `model: "haiku"`.
- **Opus 5.5 edits directly only**: documentation (`CLAUDE.md`, `docs/`, memory) and a fix of a few lines after review.

| Task | Implementor |
|---|---|
| Controller actions, strong params, auth and `require_admin!` checks | Sonnet 5.5 |
| Services, the Hono proxy, Sidekiq jobs, Rack::Attack rules | Sonnet 5.5 |
| Models, validations, associations, migrations, tables shared with Hono | Sonnet 5.5 |
| Request specs and model specs | Sonnet 5.5 |
| Bug fixes that need a root cause | Sonnet 5.5 |
| `config/routes.rb` lines for an endpoint that Sonnet 5.5 implements | Haiku 5.5 |
| One constant, one ENV key in `.env.example`, one serializer field from a given column | Haiku 5.5 |
| Copy and error message strings, renames, comment fixes | Haiku 5.5 |

- **Brief each agent fully.** An agent does not see the conversation. Give it the file paths, the exact behavior, the user's answers, and the `CLAUDE.md` rules that apply.
- **Haiku brief**: name the file, the line or symbol, and the exact new code or text. If the brief must ask the agent to decide or choose, give the task to Sonnet 5.5.
- **Split API work by layer.** Haiku 5.5 adds the route lines. Sonnet 5.5 writes the controller, the service, and the spec.
- **Split by file.** Run independent agents in parallel. Do not give two agents the same file.
- **Review every result.** Opus 5.5 reads the diff against the plan and this file before it reports to the user. Send fixes back to the same agent with `SendMessage`.
- **Escalate once.** If a Haiku result fails review, give the task to a new Sonnet 5.5 agent. Do not retry it with Haiku.
- **No migrations run by agents.** An agent does not run `rails db:migrate` or deploy unless the user asks.

---

## Local setup

```bash
git clone <repo>
cd commutebeh-rails
bundle install
cp .env.example .env
# Fill in DATABASE_URL, DEVISE_JWT_SECRET_KEY, SECRET_KEY_BASE

rails secret          # → SECRET_KEY_BASE
openssl rand -hex 64  # → DEVISE_JWT_SECRET_KEY

rails db:create db:migrate db:seed

# Run (requires Hono microservice also running on :3001)
foreman start
# or
rails s              # API on :3000
bundle exec sidekiq  # Background worker
```

---

## Deploy to Koyeb + Supabase

1. Create Supabase project → copy `DATABASE_URL`
2. Create Supabase Storage bucket `commute-navigator-maps`
3. Deploy to Koyeb from GitHub
4. Set all env vars from `.env.example` in Koyeb dashboard
5. `railway.toml` runs `db:migrate` automatically on deploy

---

## What's not built yet

- Email verification / password reset (Devise mailer not configured)
- Push notifications (APNs)
- Explore tab: Places and Events endpoints
- WebSocket/SSE for live incident feed
- Admin: AR map approval workflow UI
