Rails.application.routes.draw do
  root "pages#home"

  get "about", to: "pages#about", as: :pages_about

  # Options
  post "options", to: "options#create"
  post "options/:id/report", to: "options#report", as: :report_option

  # Votes
  post "votes", to: "votes#create"

  # Pairs
  # (literal paths must come before the :id route)
  get "pairs/controversial", to: "pairs#controversial", as: :pairs_controversial
  get "pairs/day", to: "pairs#day", as: :pairs_day
  get "pairs/:id", to: "pairs#show", as: :pair

  # Admin authentication
  get "admin/login", to: "admin_sessions#new", as: :admin_login
  post "admin/login", to: "admin_sessions#create"
  delete "admin/logout", to: "admin_sessions#destroy", as: :admin_logout

  # Admin panel (requires authentication)
  get "admin", to: "admin#index", as: :admin_index
  post "admin/approve/:id", to: "admin#approve", as: :admin_approve
  post "admin/reject/:id", to: "admin#reject", as: :admin_reject

  get "up" => "rails/health#show", as: :rails_health_check
end
