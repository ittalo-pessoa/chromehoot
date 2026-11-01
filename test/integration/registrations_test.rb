require "test_helper"

class RegistrationsTest < ActionDispatch::IntegrationTest
  def attributes
    { name: "Professora Ana", email: "nova-#{SecureRandom.hex(4)}@escola.test", password: "senha-local-completa", password_confirmation: "senha-local-completa" }
  end

  test "public signup creates a normalized teacher and signs in to an empty private dashboard" do
    get login_path
    assert_select 'a[href="/signup"]', text: "Criar conta de professor"
    get signup_path
    assert_response :success
    assert_select 'input[autocomplete="new-password"]', 2
    attrs = attributes.merge(email: "  NOVA@ESCOLA.TEST  ", id: -1, authenticated_at: 0)
    assert_difference "User.count", 1 do
      post signup_path, params: { user: attrs }
    end
    assert_redirected_to teacher_quizzes_path
    user = User.find_by!(email: "nova@escola.test")
    assert user.authenticate(attrs[:password])
    assert_not_equal(-1, user.id)
    follow_redirect!
    assert_response :success
    assert_match "Professora Ana", response.body
    assert_empty user.quizzes
    get signup_path
    assert_redirected_to teacher_quizzes_path
    assert_no_difference "User.count" do
      post signup_path, params: { user: attributes }
    end
    assert_redirected_to teacher_quizzes_path
    delete logout_path
    post login_path, params: { email: user.email, password: attrs[:password] }
    assert_redirected_to teacher_quizzes_path
  end

  test "invalid signup preserves fields but never reflects passwords or signs in" do
    attrs = attributes.merge(password_confirmation: "senha-divergente")
    assert_no_difference "User.count" do
      post signup_path, params: { user: attrs }
    end
    assert_response :unprocessable_entity
    assert_select 'input[name="user[name]"][value="Professora Ana"]'
    assert_select 'input[type="password"][value]', 0
    assert_select ".alert", text: /não confere/
    get teacher_quizzes_path
    assert_redirected_to login_path
    assert_no_difference "User.count" do
      post signup_path, params: { user: attributes.merge(password: "123456", password_confirmation: "123456") }
    end
    assert_response :unprocessable_entity
    assert_no_difference "User.count" do
      post signup_path, params: { user: attributes.except(:password_confirmation) }
    end
    assert_response :unprocessable_entity
  end

  test "existing email cannot be used to overwrite a teacher" do
    user = make_quiz.user
    assert_no_difference "User.count" do
      post signup_path, params: { user: attributes.merge(email: user.email.upcase) }
    end
    assert_response :unprocessable_entity
    assert_select ".alert", text: /já está em uso/
    assert user.reload.authenticate("uma-senha-local-segura")
  end

  test "signup attempts are limited per browser without blocking another teacher on the same IP" do
    5.times { post signup_path, params: { user: attributes.merge(name: "") } }
    assert_no_difference "User.count" do
      post signup_path, params: { user: attributes }
    end
    assert_response :too_many_requests
    assert_match "Muitas tentativas", response.body
    other_browser = open_session
    assert_difference "User.count", 1 do
      other_browser.post signup_path, params: { user: attributes }
    end
    assert_equal 302, other_browser.response.status
  end

  test "signup requires CSRF protection" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    assert_no_difference "User.count" do
      post signup_path, params: { user: attributes }
    end
    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
