RailsEventViewer::Engine.routes.draw do
  root to: "dashboard#index"

  resources :events, only: [:index, :show] do
    collection do
      get :search
    end
  end

  namespace :analytics do
    get :overview
    get :events_over_time
    get :events_by_type
  end

  resources :event_types, only: [:index, :show], param: :name
  resources :groups, only: [:index, :show]
end
