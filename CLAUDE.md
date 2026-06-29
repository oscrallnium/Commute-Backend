# CLAUDE.md — commutebeh-rails

> Read this at the start of every session. Single source of truth for this service.

---

## Role in the architecture

`commutebeh-rails` is the **user-facing API** for CommuteBeh. It handles:
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

## Shared tables with Hono microservice

`stations` and `edges` tables are **owned and seeded by the Hono microservice** (`npm run db:migrate && npm run db:seed`). Rails reads them via the `Station` and `Edge` models using TEXT primary keys (`station_id`, `edge_id`).

**Do not run Rails migrations that create or alter these tables.** If the schema changes, update the Hono migration first, then update the Rails models to match.

---

## Invariants

- **JWT in memory only** — iOS stores token in Keychain; web admin stores in memory variable. Never localStorage.
- **isTerminal is Hono-owned** — inferred by the Hono seed, never set by Rails or the client.
- **N+1 is a bug** — all list endpoints must use `includes()` for associated records.
- **150 MB upload cap** — enforced before Active Storage processing in `ArWorldMapsController`.
- **100-entry ring buffer** — relocalization events on `ar_world_maps.metadata` capped at 100.
- **Analytics never block** — `AnalyticsController#route_plan` rescues all errors and returns 201 regardless, so iOS commutes are never blocked by a logging failure.

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
