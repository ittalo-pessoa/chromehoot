class RegistrationsController < ApplicationController
  before_action :redirect_authenticated_teacher

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    AccessAttempt.check!("registration:#{browser_key}", limit: 5)
    if @user.save(context: :registration)
      reset_session
      session[:user_id] = @user.id
      session[:authenticated_at] = Time.current.to_i
      redirect_to teacher_quizzes_path, notice: "Conta criada! Bem-vindo ao ChromeHoot."
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    @user.errors.add(:email, :taken)
    render :new, status: :unprocessable_entity
  rescue GameError => error
    @user.errors.add(:base, error.message)
    render :new, status: :too_many_requests
  end

  private

  def redirect_authenticated_teacher
    redirect_to teacher_quizzes_path if current_user
  end

  def registration_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end
end
