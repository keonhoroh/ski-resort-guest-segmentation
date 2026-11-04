Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    get "health", to: "health#show"

    # GET    /api/segments          list     (index)
    # POST   /api/segments          create
    # GET    /api/segments/:id      show
    # PATCH  /api/segments/:id      update
    # DELETE /api/segments/:id      destroy
    resources :segments, only: %i[index show create update destroy] do
      collection do
        post :preview  # POST /api/segments/preview
        get :options   # GET  /api/segments/options
      end

      # POST /api/segments/:segment_id/campaigns   launch a campaign for this segment
      resources :campaigns, only: :create
    end

    # GET /api/campaigns       list
    # GET /api/campaigns/:id   progress of one campaign
    resources :campaigns, only: %i[index show]
  end
end
