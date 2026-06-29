# CommuteBeh Rails API

User-facing REST API for **CommuteBeh** — a transit navigation app for the Philippines. Handles authentication, user profiles, saved commutes, AR World Map uploads, analytics ingestion, incident reporting, and proxied transit graph reads.

---

## Architecture overview

```
iOS App (Swift / A*)
        │
        ▼
commutebeh-rails  :3000   ← this repo (user API, auth, analytics)
        │
        └──proxy──▶  commutebeh-api  :3001   (Hono — transit graph writes)
                            │
                            ▼
                     PostgreSQL (Supabase)
```

The iOS client runs the A* routing algorithm on-device. Rails handles everything else: auth, persistence, analytics logging, and graph reads proxied from the Hono microservice.

---

## Stack

| Layer | Tech |
|---|---|
| Framework | Rails 7.1 (API-only) |
| Auth | Devise + devise-jwt (JTI denylist) |
| Database | PostgreSQL (Supabase) — UUID PKs via pgcrypto |
| File storage | Active Storage → Supabase Storage (S3-compatible) |
| Background jobs | Sidekiq + Redis |
| Rate limiting | Rack::Attack |
| Deploy | Koyeb + Supabase |

---

## Prerequisites

| Tool | Version |
|---|---|
| Ruby | 3.4.1 |
| Rails | 7.1 |
| PostgreSQL | 14+ |
| Redis | 7+ |
| Bundler | 2+ |

Install Ruby via [rbenv](https://github.com/rbenv/rbenv) or [mise](https://mise.jdx.dev/):

```bash
rbenv install 3.4.1
rbenv local 3.4.1
```

---

## Local setup

### 1. Clone and install gems

```bash
git clone https://github.com/oscrallnium/commutebeh-rails.git
cd commutebeh-rails
bundle install
```

### 2. Configure environment variables

```bash
cp .env.example .env
```

Open `.env` and fill in each value:

```env
# PostgreSQL — point to your local Postgres instance
DATABASE_URL=postgresql://postgres:password@localhost:5432/commutebeh_development

# Generate with: rails secret
SECRET_KEY_BASE=

# Generate with: openssl rand -hex 64
DEVISE_JWT_SECRET_KEY=

# Hono microservice URL (must be running on :3001)
HONO_API_URL=http://localhost:3001

# Redis for Sidekiq + Rack::Attack
REDIS_URL=redis://localhost:6379/0

# Supabase Storage (only needed for AR map uploads)
SUPABASE_S3_ENDPOINT=https://<project-ref>.supabase.co/storage/v1/s3
SUPABASE_S3_ACCESS_KEY=
SUPABASE_S3_SECRET_KEY=
SUPABASE_S3_REGION=ap-southeast-1
SUPABASE_STORAGE_BUCKET=commute-navigator-maps

# CORS — add any origin that needs to hit the API
ALLOWED_ORIGINS=http://localhost:5173,commutenavigator://
```

Generate the two secret values:

```bash
rails secret                # paste output into SECRET_KEY_BASE
openssl rand -hex 64        # paste output into DEVISE_JWT_SECRET_KEY
```

### 3. Start PostgreSQL

Make sure Postgres is running locally. On macOS with Homebrew:

```bash
brew services start postgresql@14
```

Or use [Postgres.app](https://postgresapp.com/) — just ensure it's running on port 5432.

### 4. Create and migrate the database

```bash
rails db:create
rails db:migrate
```

This runs all 9 migrations including extensions (`pgcrypto`, `pg_trgm`, `unaccent`), the user table, AR world maps, analytics, incidents, and the transit graph tables.

### 5. Seed the database

```bash
rails db:seed
```

This seeds:
- An admin user: `admin@commutebeh.ph` / `Admin1234!`
- `GraphMeta` from `data/transit_graph_v3.json`
- Stations and edges from the transit graph JSON

> **Note:** Stations and edges are owned by the Hono microservice. If you need full graph data, run the Hono seed first (`npm run db:migrate && npm run db:seed` in the `commutebeh-api` repo). Rails reads those tables but does not create them.

### 6. Start Redis

Sidekiq and Rack::Attack require Redis. Start it locally:

```bash
brew services start redis
# or
redis-server
```

### 7. Run the app

Using Foreman (runs Rails + Sidekiq together):

```bash
foreman start
```

Or run each process separately:

```bash
# Terminal 1 — Rails API on :3000
rails s

# Terminal 2 — Sidekiq background worker
bundle exec sidekiq
```

### 8. Verify

```bash
curl http://localhost:3000/health
# → { "status": "ok", "database": "connected" }
```

---

## Running alongside the Hono microservice

Some endpoints (graph version check, full graph fetch, admin graph mutations) proxy to the Hono service on `:3001`. Without it running, those endpoints return errors but the rest of the API stays functional.

Clone and start the Hono service in a separate terminal:

```bash
# in commutebeh-api/
npm install
npm run db:migrate
npm run db:seed
npm run dev          # starts on :3001
```

---

## Key endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/health` | None | Liveness + DB check |
| POST | `/auth/register` | None | Create account |
| POST | `/auth/sign_in` | None | Login → JWT |
| DELETE | `/auth/sign_out` | Bearer | Logout (JTI revoked) |
| POST | `/api/v1/auth/refresh` | Bearer | Rotate token |
| DELETE | `/api/v1/auth/account` | Bearer | Delete account (App Store) |
| GET | `/api/v1/me` | Bearer | Current user profile |
| PATCH | `/api/v1/me` | Bearer | Update display name / home station |
| GET | `/api/v1/graph/version` | None | Graph staleness check |
| GET | `/api/v1/graph` | None | Full transit graph JSON |
| GET | `/api/v1/stations` | None | Station list |
| GET | `/api/v1/routes` | None | Route list |
| GET | `/api/v1/saved_routes` | Bearer | User's saved commutes |
| POST | `/api/v1/saved_routes` | Bearer | Save a commute |
| GET | `/api/v1/ar_world_maps` | Bearer | List AR maps |
| POST | `/api/v1/ar_world_maps` | Bearer | Upload ARWorldMap (multipart, max 150 MB) |
| POST | `/api/v1/ar_world_maps/:id/relocalize` | Bearer | Log relocalization event |
| POST | `/api/v1/analytics/route_plan` | Bearer | Log iOS A* route plan |
| GET | `/api/v1/incidents` | Bearer | Active incidents |
| POST | `/api/v1/incidents` | Bearer | Report incident |
| GET | `/api/v1/admin/analytics/summary` | Admin | DAU/WAU, mode share |
| GET | `/api/v1/admin/analytics/hotspots` | Admin | Top origins (30 d) |
| GET | `/api/v1/admin/users` | Admin | User list |

JWT must be sent as `Authorization: Bearer <token>` on all authenticated routes. The token is issued on sign-in and rotated on refresh (old JTI is revoked immediately).

---

## Rate limits (Rack::Attack)

| Scope | Limit |
|---|---|
| Auth endpoints (by IP) | 10 req / 20 s |
| Sign-in by email | 5 req / 5 min |
| API endpoints (by IP) | 60 req / min |
| Analytics writes (by user) | 30 req / min |

Exceeded limits return `429` with `{ "error": "Too many requests. Please try again later." }`.

---

## Running tests

```bash
bundle exec rspec
```

---

## Deploy (Koyeb + Supabase)

1. Create a Supabase project and copy the `DATABASE_URL`.
2. Create a Supabase Storage bucket named `commute-navigator-maps`.
3. Push this repo to GitHub and connect it to a Koyeb service.
4. Set all variables from `.env.example` in the Koyeb dashboard.
5. `railway.toml` runs `db:migrate` automatically on each deploy.

---

## What's not built yet

- Email verification and password reset (Devise mailer not configured)
- Push notifications (APNs)
- Explore tab: Places and Events endpoints
- WebSocket / SSE for live incident feed
- Admin: AR map approval workflow UI
