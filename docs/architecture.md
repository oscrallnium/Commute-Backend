---
title: Architecture
layout: default
nav_order: 3
---

# Architecture
{: .no_toc }

1. TOC
{:toc}

---

## System context

```mermaid
graph TB
    subgraph Device["iOS device"]
        UI["SwiftUI views"]
        VM["RouteStore"]
        ENG["TransitGraphEngine<br/><i>actor · A* search</i>"]
        CACHE[("Documents/<br/>transit_graph_v3.json")]
        KC[("Keychain · JWT")]
    end

    subgraph Render["Render — Singapore"]
        API["commutebeh-rails<br/>Rails 7.1 · Puma"]
        RC[("Redis cache")]
    end

    SB[("Supabase Postgres<br/>graph · users · events")]
    S3[("Supabase S3<br/>AR world maps")]

    UI <--> VM
    VM <--> ENG
    ENG -.reads at init.-> CACHE
    VM -->|HTTPS + Bearer JWT| API
    KC -.token.-> API
    API --> SB
    API --> RC
    API --> S3
    API -->|graph JSON| CACHE

    style ENG fill:#1f7a4d,color:#fff
    style API fill:#8b2635,color:#fff
    style SB fill:#3a3a6b,color:#fff
```

Two things to internalise:

1. **Routing is entirely client-side.** The server never computes a path.
2. **The graph is not bundled with the app.** The only copy on a device is the one downloaded
   from `GET /api/v1/graph`. There is no bundle fallback — a first launch with no network cannot
   route at all.

## Request pipeline

```mermaid
graph LR
    R[Request] --> CORS[rack-cors]
    CORS --> RA[rack-attack<br/>rate limit]
    RA --> RT["Rails router<br/><i>GRAPH_ID constraint</i>"]
    RT --> AC{authenticate_user!}
    AC -->|"public: graph,<br/>stations, routes, health"| CTRL
    AC -->|401| E401[Unauthorized]
    AC -->|valid JWT| ADM{require_admin!}
    ADM -->|403| E403[Forbidden]
    ADM -->|ok| CTRL[Controller]
    CTRL --> CACHE{Rails.cache}
    CACHE -->|hit| RESP
    CACHE -->|miss| GS[GraphService]
    GS --> PG[(Postgres)]
    PG --> RESP["{ data: …, meta: … }"]

    style E401 fill:#8b2635,color:#fff
    style E403 fill:#8b2635,color:#fff
```

### The `GRAPH_ID` router constraint

Graph IDs are author-supplied and can contain dots — the line `STACRUZ.LRT_BUENDIA`, for
instance. Rails' default dynamic segment stops at a dot and hands the rest to `:format`, so

```
DELETE /admin/graph/routes/STACRUZ.LRT_BUENDIA
```

arrived as `line_id: "STACRUZ"`, `format: "LRT_BUENDIA"` — **deleting nothing while still
reporting success**. Every route carrying a graph ID now uses

```ruby
GRAPH_ID = /[^\/]+/
# …
get "stations/:id", to: "stations#show",
    constraints: { id: GRAPH_ID }, format: false
```

If you add a route whose path carries a station, edge or line ID, it needs both the constraint
and `format: false`. `config/routes.rb:15`.

## Cold start, end to end

```mermaid
sequenceDiagram
    autonumber
    participant App as iOS app
    participant S as UserSession
    participant API as Rails API
    participant GS as GraphService
    participant PG as Postgres

    App->>S: init()
    alt cached token + profile
        S-->>App: isLoggedIn = true (optimistic)
        S->>API: POST /api/v1/auth/refresh
        API->>PG: rotate JTI
        API-->>S: new token + user
    else no token
        S-->>App: show LoginView
    end

    App->>API: GET /api/v1/graph (first launch only)
    API->>GS: assemble_graph (cached 5 min)
    GS->>PG: stations + edges + modes + payments + lines
    PG-->>GS: rows
    GS-->>API: one camelCase JSON document
    API-->>App: { data: { … } }
    Note over App: write to Documents/,<br/>build adjacency, ready to route

    App->>API: GET /api/v1/graph/version (subsequent launches)
    API-->>App: { version: 43 }
    Note over App: differs from cached? → re-download
```

Note the optimistic login: the client shows its cached profile immediately and refreshes behind
it. A 401 on refresh forces a sign-out.

## Layering

```mermaid
graph TD
    RT["config/routes.rb"] --> CTRL["Controllers<br/><i>api/v1/**</i>"]
    CTRL --> BC["BaseController<br/><i>auth · json_response · cache busting</i>"]
    CTRL --> GS["GraphService<br/><i>all graph mutation</i>"]
    CTRL --> MOD["Models<br/><i>as_api_json</i>"]
    GS --> MOD
    MOD --> PG[(Postgres)]
    CTRL -.->|never| PG

    style GS fill:#8b2635,color:#fff
```

**Controllers never mutate graph tables directly.** Every write goes through `GraphService`, which
owns the transaction boundary and the version bump. A controller that writes a station row itself
will produce a graph the clients never learn about, because nothing bumped the version.

The one sanctioned exception is `EdgesController#update`, which mutates a single edge and then
calls `GraphService.bump_version!` explicitly — a public class method that exists for exactly this
case.

## Concurrency and background work

| Concern | Mechanism |
|:--|:--|
| Web | Puma, `config/puma.rb` |
| Background jobs | Sidekiq, `worker` process in the `Procfile` |
| Cache | `Rails.cache` → Redis via `REDIS_URL` |
| Rate limiting | rack-attack |

Redis is treated as **optional**. `bust_graph_cache!` rescues every error, so an unset or
unreachable `REDIS_URL` degrades to "cache entries expire on their TTL" rather than failing
requests. See [Backend Internals → Caching]({{ site.baseurl }}/backend#caching).
