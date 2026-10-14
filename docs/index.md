# Gora Backend

Last checked against commit `106ae55` on 10/13/26.

`commutebeh-rails` is the Rails API-only service behind Gora, a transit navigation app for Metro Manila and Los Baños. It authors, versions, and distributes the transit graph that the iOS app uses. It is also the identity provider for the app.

The service does not compute routes. A* runs on the device. The app routes with no connection after it caches a graph.

## Pages

| Page | What it answers |
|:--|:--|
| [Overview](overview.md) | What does the system do, who uses it, and what do the terms mean? |
| [Architecture](architecture.md) | How do the app and the server fit together, and how does a request flow? |
| [Data Model](data-model.md) | Which tables exist, what does the graph JSON look like, and which rules hold? |
| [Backend Internals](backend.md) | Where does the logic live, how do caching and deploys work, and which defects are known? |
| [API Reference](api-reference.md) | What are all routes, their auth, bodies, responses, errors, and rate limits? |
| [Ops Publish API](ops-publish-api.md) | How does the ops dashboard read the admin graph, publish changes, and read history? |
| [Graph Sync](graph-sync.md) | How does the app download the graph, and which writes raise the graph version? |
| [Security](security.md) | How do authentication, roles, rate limits, CORS, validation, and secrets work, and which gaps remain? |
| [Agent Guide](agent-guide.md) | Where do I edit to change X, which rules must hold, and how do I run specs and deploy safely? |

## At a glance

| | |
|:--|:--|
| **Stack** | Ruby 3.4, Rails 7.2.3 (API mode), Puma, Postgres, Redis, Sidekiq (installed, no jobs) |
| **Auth** | Devise and devise-jwt, `JTIMatcher` revocation, 24-hour token |
| **Database** | Supabase Postgres, `pg_trgm` for station search |
| **Storage** | Active Storage to Supabase S3-compatible storage (AR world maps) |
| **Deploy** | Render, Singapore, `starter` plan. `db:migrate` runs before each deploy. |
| **Base URL** | `https://commute-backend-a6lj.onrender.com` |
| **Health** | `GET /health` |
| **Specs** | RSpec: request, service, model, and migration specs |
| **Clients** | Gora iOS app, Gora Operations Dashboard (macOS) |

## Responsibilities

1. **Identity.** Register, sign in, refresh, sign out, and delete an account.
2. **Graph authoring.** Create and delete lines, insert and remove stops, edit stops, edges, doors, fares, and visibility. The server enforces the domain rules.
3. **Draft publish.** Apply a list of changes as one graph version, with history.
4. **Graph distribution.** Assemble one versioned JSON document, cache it, and serve it.
5. **Community and analytics.** Incidents, saved routes, and route plan events.
6. **AR world map store.** Uploads that anchor to stations.

## Two facts about operations

The `starter` plan stops the service when idle. A cold request takes about 44 seconds.

Seeds do not run on deploy. The pipeline runs `db:migrate` only. Put data that the app needs in a migration.

## Stale files in the repository root

`README.md`, `CLAUDE.md`, and `.env.example` describe a Hono service at port 3001 and deploys to Koyeb. That service does not exist. `GraphService` writes the graph to Postgres. Use these pages as the current description.
