Rails.application.routes.draw do
  # Health check — no auth, used by Railway + UptimeRobot
  get "/health", to: "health#show"

  devise_for :users,
             path: "",
             path_names: { sign_in: "auth/sign_in", sign_out: "auth/sign_out", registration: "auth/register" },
             controllers: {
               sessions: "api/v1/auth/sessions",
               registrations: "api/v1/auth/registrations"
             }

  # Graph ids (station_id, edge_id, line) are author-supplied strings that can contain
  # dots — e.g. the line "STACRUZ.LRT_BUENDIA" and its "STACRUZ.LRT_BUENDIA_STOP3"
  # stations. Rails' default dynamic segment stops at a dot and hands the rest to
  # `:format`, so `DELETE /admin/graph/routes/STACRUZ.LRT_BUENDIA` arrived as
  # line_id: "STACRUZ", format: "LRT_BUENDIA" — deleting nothing while still reporting
  # success. Every route below that carries a graph id in its path uses this constraint
  # plus `format: false` so the whole segment, dots included, lands in the param.
  GRAPH_ID = /[^\/]+/

  namespace :api do
    namespace :v1 do
      # ── Auth extras ──────────────────────────────────────────────────────────
      post   "auth/refresh",         to: "auth/sessions#refresh"
      delete "auth/account",         to: "auth/registrations#destroy" # App Store requirement

      # ── Current user ─────────────────────────────────────────────────────────
      get    "me",                   to: "users#me"
      patch  "me",                   to: "users#update"

      # ── Transit graph ────────────────────────────────────────────────────────
      get    "graph/version",        to: "graph#version"
      get    "graph",                to: "graph#show"
      get    "stations",             to: "stations#index"
      get    "stations/:id",         to: "stations#show",
             constraints: { id: GRAPH_ID }, format: false
      get    "routes",               to: "routes#index"
      get    "routes/:line_id",      to: "routes#show",
             constraints: { line_id: GRAPH_ID }, format: false

      # ── Saved routes (user commutes) ──────────────────────────────────────────
      resources :saved_routes, only: %i[index create destroy]

      # ── AR World Maps ─────────────────────────────────────────────────────────
      resources :ar_world_maps, only: %i[index show create] do
        member do
          post :relocalize
        end
      end

      # ── Analytics (iOS logs route plans here) ─────────────────────────────────
      post "analytics/route_plan", to: "analytics#route_plan"

      # ── Incidents (community-reported service disruptions) ────────────────────
      resources :incidents, only: %i[index create]

      # ── Explore tab ───────────────────────────────────────────────────────────
      resources :places, only: %i[index show]
      resources :events, only: %i[index show]

      # ── Admin (admin role required) ───────────────────────────────────────────
      namespace :admin do
        resources :users,         only: %i[index show destroy]
        resources :ar_world_maps, only: %i[index show update destroy]
        resources :incidents,     only: %i[index update destroy]
        resources :stations,      only: %i[create update destroy],
                                  constraints: { id: GRAPH_ID }, format: false
        resources :edges,         only: %i[update],
                                  constraints: { id: GRAPH_ID }, format: false
        get    "analytics/summary",      to: "analytics#summary"
        get    "analytics/hotspots",     to: "analytics#hotspots"
        post   "graph/routes",           to: "graph#create_route"
        delete "graph/routes/:line_id",  to: "graph#delete_route",
               constraints: { line_id: GRAPH_ID }, format: false
        get    "settings",               to: "settings#show"
        patch  "settings",               to: "settings#update"
      end
    end
  end
end
