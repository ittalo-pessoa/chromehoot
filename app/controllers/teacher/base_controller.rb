module Teacher
  class BaseController < ApplicationController
    before_action :require_teacher
    before_action do
      response.headers["Cache-Control"] = "no-store"
      if current_user && session[:authenticated_at].to_i < 12.hours.ago.to_i
        reset_session
        redirect_to login_path, alert: "Sua sessão expirou. Entre novamente."
      end
    end
  end
end
