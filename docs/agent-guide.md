# Agent Guide

Last checked against commit `106ae55` on 10/13/26.

---

This page is for AI agents. It gives exact facts about where logic lives and which rules must hold.

## To change X, edit Y

| To change | Edit | Also update |
|:--|:--|:--|
| A route or its constraint | `config/routes.rb` | [API Reference](api-reference.md). A route with a graph ID needs `constraints: { id: GRAPH_ID }` and `format: false`. |
| Authentication or token lifetime | `config/initializers/devise.rb`, `app/models/user.rb` | [Security](security.md) |
| Admin access check | `BaseController#require_admin!` and each admin controller | [Security](security.md) |
| Rate limits | `config/initializers/rack_attack.rb` | API Reference, Security |
| CORS | `config/initializers/cors.rb` | Security |
| Create a line (`POST admin/graph/routes`) | `GraphService#add_route`, `#validate`, `#normalize_passes` | `spec/requests/api/v1/admin/graph_routes_spec.rb` |
| Delete a route | `GraphService#delete_route` | `spec/services/graph_service_delete_route_spec.rb` |
| Insert or remove one stop | `GraphService#insert_stop`, `#remove_stop` | `spec/services/graph_service_*stop*_spec.rb` |
| Delete a line | `LineDeletion` | `spec/requests/api/v1/admin/line_delete_spec.rb` |
| A publish change type | `GraphChangeValidator::TYPES` (shape) and `GraphChangeApplier#apply_<type>` (write) | [Ops Publish API](ops-publish-api.md), `spec/services/graph_change_validator_spec.rb`, `graph_publisher_spec.rb` |
| Publish transaction, conflict rule | `GraphPublisher` | Ops Publish API |
| Which items riders see | `GraphVisibility` | `spec/requests/api/v1/graph_visibility_spec.rb` |
| Public graph JSON | `GraphService#station_json`, `#edge_json`, `#line_json`, `#graph_payload` | `Station#as_api_json` and `Edge#as_api_json` (change both) |
| Admin graph JSON | `GraphService#assemble_admin_graph`, `#ops_state_json`, `#admin_line_json` | Ops Publish API |
| Road travel time rule | `GraphService::SPEED_KMH_BY_MODE`, `#travel_time_minutes` | A data migration if old edges must change |
| Station doors | `StationAccessPoint`, `Admin::StationsController#replace_access_points!` | `GraphService#station_json` |
| Rail fare table | `RailFareTable`, `GraphChangeApplier#apply_line_rail_fares` | Ops Publish API |
| Version bump | `GraphService.bump_version!` | Every write path must call it |
| Cache keys and busting | `BaseController#bust_graph_cache!` | API Reference (caches table) |
| Schema | A new file in `db/migrate/` | `db/schema.rb`, [Data Model](data-model.md) |
| Loop repair | `LoopReslicer`, `lib/tasks/graph_repair.rake` | – |
| Deploy | `render.yaml` | [Backend Internals](backend.md#deployment) |

## Invariants

Do not break these rules.

1. **Graph ID convention.** A graph ID matches `^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$`. Uppercase, digits, single underscores. No hyphen, no dot. Old IDs with a dot stay valid. Code accepts both.
2. **An ID never changes.** Insert and remove change `stations.sequence` only. Order, direction, and mode come from columns, not from an ID. Tables `saved_routes`, `incidents`, `ar_world_maps`, and `route_plan_events` store station IDs with no foreign key.
3. **Generated stop IDs.** `<CHAIN>_S<n>`. `n` comes from `lines.last_stop_number`, which never goes down. A line edge ID is `<FROM>__<TO>`. A transfer edge ID is `X__<FROM>__<TO>`.
4. **One graph version for each publish.** `POST /api/v1/admin/graph/publish` raises `graph_meta.version` by exactly 1 and writes one `graph_versions` row. `GraphPublisher` locks `graph_meta`, and `GraphChangeApplier` never bumps the version.
5. **Every write that changes the graph JSON bumps the version.** If a write skips the bump, installed clients never re-download the graph. `PATCH /api/v1/admin/settings` is an open defect (see [Known issues](backend.md#known-issues)).
6. **The visibility rule.** A disabled line, stop, or edge is hidden from riders. An edge is also hidden when either end is not a visible stop. `GraphVisibility` is the only place for this rule. The admin graph lists everything and reports `hiddenFromRiders`.
7. **`INTERCHANGE` is reserved.** It is the line of transfer walks. Do not rename or delete it. It refuses `line_direction`, `line_enabled`, `line_road_fare`, `line_rail_fares`, and `line_delete`. The iOS engine reads it to skip fares and leg merges.
8. **The public JSON shape stays compatible.** The iOS app decodes `GET /api/v1/graph`. Keep every existing key and type. Add a new key as optional. Add a field to both serializers. Keep the `{ "data": … }` envelope.
9. **Road fare.** `base_fare + max(0, km - base_km) * fare_per_km`. `base_km` is a column of `lines`. Rail lines use `rail_fare_tables`.
10. **Controllers stay thin.** A controller reads params, calls one service, and renders. The service owns the transaction.
11. **Do not hardcode transit data.** Names, fares, coordinates, and modes come from the database.
12. **A mutation that changes data also busts the cache.** Call `bust_graph_cache!` after the commit.

## Run the specs safely

The specs write to the database that `DATABASE_URL` names. `config/database.yml` uses `url: ENV["DATABASE_URL"]`, and that value overrides the `database:` name. `spec/rails_helper.rb` calls `maintain_test_schema!`, which can load the schema into that database. Some specs also change `graph_meta`, lines, and stations.

Follow these steps:

1. Use a disposable local Postgres database. Never use the Supabase database.
2. Set `DATABASE_URL` in the shell to the local database for the command. Do not print the value of the existing variable.
3. Do not run `rails db:migrate` against a shared database.
4. Run `bundle exec rspec`.

```bash
DATABASE_URL=postgres://localhost/commutebeh_test RAILS_ENV=test \
  bundle exec rails db:create db:schema:load
DATABASE_URL=postgres://localhost/commutebeh_test bundle exec rspec
```

Specs use transactional fixtures. The migration specs and `OpsGraphFixture` (IDs that start with `OPST`) assume a database that can hold test rows. The test cache is `:null_store`.

## Deploys

- Render runs `bundle exec rails db:migrate` as `preDeployCommand` before each deploy. A pushed migration runs on production.
- Seeds do not run on deploy. Data the app needs goes in a migration.
- A migration that changes the emitted graph JSON also bumps the version and clears the cache after commit (see migrations 019, 022, 025, 026).
- Ask Hachi to review a pending migration before you push it.
- A cold request on the `starter` plan takes about 44 seconds.
- Render health check: `GET /health`.

## Production writes

Never write to production from a script, a spec, or the Rails console. A production data change goes through the Hachi agent. Hachi takes a snapshot, runs a dry run, waits for the approval of the user, sends the request, and verifies the result.

The Gora Operations Dashboard keeps every edit in a local draft until the user approves a publish.

## Before you finish a change

1. Run the specs that cover the code.
2. Update the pages in the table above.
3. Keep the comments to 3 lines or fewer. Describe the code now, not the change.
