---
title: Home
layout: default
nav_order: 1
---

# Gora Backend

`commutebeh-rails` is the Rails 7.1 API-only service behind **Gora**, a multimodal transit
navigation app for Metro Manila and Los Baños. It authors, versions and distributes the transit
graph that the iOS client routes over — and it is the identity provider for that client.

**The one thing to internalise first:** this service does not compute routes. A\* runs entirely
on the device. The backend is a graph authoring and distribution system, plus auth. That is why
the app keeps routing with no connectivity once it has a cached graph.

---

## Documentation

| Page | What it answers |
|:--|:--|
| [Overview]({{ site.baseurl }}/overview) | What the system does, who uses it, the vocabulary |
| [Architecture]({{ site.baseurl }}/architecture) | How the two tiers fit together; request pipeline |
| [Data Model]({{ site.baseurl }}/data-model) | Postgres schema, the graph JSON document, invariants |
| [Backend Internals]({{ site.baseurl }}/backend) | `GraphService`, auth, caching, deployment, migrations |
| [API Reference]({{ site.baseurl }}/api-reference) | Every endpoint, envelope and error code |
| [Graph Sync]({{ site.baseurl }}/graph-sync) | The OTA contract between server and client |

## At a glance

| | |
|:--|:--|
| **Stack** | Ruby 3.4 · Rails 7.1 (`--api`) · Puma · Postgres · Redis · Sidekiq |
| **Auth** | Devise + devise-jwt, JTIMatcher revocation |
| **Database** | Supabase Postgres, `pg_trgm` for station search |
| **Storage** | Active Storage → Supabase S3-compatible (AR world maps) |
| **Deployed** | Render, Singapore, `starter` plan |
| **Base URL** | `https://commute-backend-a6lj.onrender.com` |
| **Health** | `GET /health` |

## Responsibilities

1. **Identity** — register, sign in, refresh, delete account.
2. **Graph authoring** — create and delete lines, insert and remove stops, edit stations, edges
   and station doors, with the domain rules enforced server-side.
3. **Graph distribution** — assemble the whole graph into one versioned JSON document, cache it,
   serve it.
4. **Community + analytics sink** — incidents, saved routes, route-plan events.
5. **AR world map store** — `.arworldmap` uploads anchored to stations.

## Two operational facts worth memorising

**The `starter` plan spins down on idle.** A cold request takes roughly 44 seconds. If the app
appears to hang on first launch, this is usually why — not a client bug.

**Seeds never run on deploy.** The Render pipeline runs `db:migrate` only. Anything the app
requires to *function* must live in a migration, not `seeds.rb`. This was discovered the hard
way: production shipped with an empty `graph_meta` and no admin user.

---

{: .warning }
> The repository root still contains a `README.md` and `CLAUDE.md` describing a proxy to a
> **Hono/TypeScript** service at `:3001` that handles transit graph writes. That service does not
> exist. Graph writes are handled by `GraphService` in this repo, against Postgres. Treat this
> documentation set as current and those two files as historical.
