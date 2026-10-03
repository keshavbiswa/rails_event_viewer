RailsEventViewer::Engine.routes.draw do
  root to: "dashboard#index"

  resources :events, only: [:index, :show]

  namespace :analytics do
    get :overview
  end

  resources :event_types, only: :index
  get "event_type", to: "event_types#show", as: :event_type

  resources :groups, only: :index
  get "group", to: "groups#show", as: :group
end
