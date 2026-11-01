class SessionsController < ApplicationController
  def new; end

  def create
    email = params[:email].to_s.strip.downcase
    AccessAttempt.check!("login:#{email}", limit: 12)
    user = User.find_by(email: email)
    if user&.authenticate(params[:password].to_s)
      reset_session
      session[:user_id] = user.id
      session[:authenticated_at] = Time.current.to_i
      redirect_to teacher_quizzes_path, notice: "Bem-vindo ao ChromeHoot!"
    else
      redirect_to login_path, alert: "E-mail ou senha inválidos.", status: :see_other
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Você saiu da conta.", status: :see_other
  end
end
