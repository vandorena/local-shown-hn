Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  get "feed" => "posts#feed", as: :feed, defaults: { format: :atom }
  resources :places, only: %i[ index show ], param: :slug

  namespace :admin do
    resources :posts, only: %i[ index update ]
    root "posts#index"
  end

  root "posts#index"
end
