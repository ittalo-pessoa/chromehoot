Rails.application.routes.draw do
  root "home#index"
  get "up" => "rails/health#show", as: :rails_health_check
  get "login" => "sessions#new"
  post "login" => "sessions#create"
  delete "logout" => "sessions#destroy"
  post "join" => "play#join"
  get "play" => "play#show"
  get "play/state" => "play#state"
  post "play/answer" => "play#answer"
  delete "play" => "play#leave"
  namespace :teacher do
    resources :quizzes do
      post :duplicate, on: :member
      resources :questions, except: %i[index show] do
        patch :move, on: :member
      end
    end
    resources :game_sessions, only: %i[index create show] do
      member do
        get :projector
        get :state
        get :report
        post :command
        patch :remove_participant
      end
    end
  end
end
