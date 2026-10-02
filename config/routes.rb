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

  resources :event_types, only: :index
  get "event_type", to: "event_types#show", as: :event_type

  resources :groups, only: :index
  get "group", to: "groups#show", as: :group
end
