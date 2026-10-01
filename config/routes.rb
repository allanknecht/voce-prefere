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
  get "pairs/:id/results", to: "pairs#results", as: :pair_results
  get "pairs/:id", to: "pairs#show", as: :pair

  # Admin authentication
  get "admin/login", to: "admin_sessions#new", as: :admin_login
  post "admin/login", to: "admin_sessions#create"
  delete "admin/logout", to: "admin_sessions#destroy", as: :admin_logout

  # Admin panel (requires authentication)
  get "admin", to: "admin#index", as: :admin_index
  get "admin/review", to: "admin#review", as: :admin_review
  post "admin/approve/:id", to: "admin#approve", as: :admin_approve

  # Admin: manage ALL options (list / search / edit / delete with confirmation page)
  get "admin/options", to: "admin_options#index", as: :admin_options
  get "admin/options/:id/edit", to: "admin_options#edit", as: :edit_admin_option
  get "admin/options/:id/delete", to: "admin_options#confirm_destroy", as: :confirm_delete_admin_option
  patch "admin/options/:id", to: "admin_options#update", as: :admin_option
  delete "admin/options/:id", to: "admin_options#destroy"

  # Admin: read-only log of deleted option texts
  get "admin/deleted", to: "admin_deleted#index", as: :admin_deleted

  get "up" => "rails/health#show", as: :rails_health_check
end
