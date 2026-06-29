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
      get    "stations/:id",         to: "stations#show"
      get    "routes",               to: "routes#index"
      get    "routes/:line_id",      to: "routes#show"

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
        get    "analytics/summary",      to: "analytics#summary"
        get    "analytics/hotspots",     to: "analytics#hotspots"
        post   "graph/routes",           to: "graph#create_route"
        delete "graph/routes/:line_id",  to: "graph#delete_route"
      end
    end
  end
end
