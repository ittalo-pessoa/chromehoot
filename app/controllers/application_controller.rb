class ApplicationController < ActionController::Base
  helper_method :current_user
  rescue_from GameError, ActiveRecord::RecordInvalid, with: :handle_error

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def require_teacher
    redirect_to login_path, alert: "Entre como professor para continuar." unless current_user
  end

  def handle_error(error)
    message = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.join(", ") : error.message
    if request.format.json?
      render json: { error: message }, status: :unprocessable_entity
    else
      redirect_back fallback_location: root_path, alert: message, status: :see_other
    end
  end

  def browser_key
    cookies.signed[:browser_key] ||= { value: SecureRandom.hex(24), httponly: true, same_site: :lax, secure: request.ssl? }
    cookies.signed[:browser_key]
  end
end
