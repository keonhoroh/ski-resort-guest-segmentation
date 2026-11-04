Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Everything inside this block starts with /api and lives in app/controllers/api/
  namespace :api do
    # GET /api/health  →  Api::HealthController, method `show`
    get "health", to: "health#show"
  end
end
