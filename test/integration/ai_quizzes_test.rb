require "test_helper"

class AiQuizzesTest < ActionDispatch::IntegrationTest
  def sign_in(user)
    post login_path, params: { email: user.email, password: "uma-senha-local-segura" }
    assert_redirected_to teacher_quizzes_path
  end

  def request_params
    { topic: "Rede local", subject: "Informática", grade_level: "1º ano", difficulty: "easy", question_count: 3 }
  end

  def generated_content
    { "title" => "Redes locais", "description" => "Sugestão de quiz", "questions" => 3.times.map { |i| { "statement" => "Questão #{i + 1}", "choices" => %w[Roteador Monitor Mouse Teclado], "correct_index" => 0, "time_limit_seconds" => 30 } } }
  end

  test "teacher requests generation reviews edits and saves a real quiz only after confirmation" do
    user = make_quiz.user
    sign_in(user)
    get new_teacher_ai_quiz_path
    assert_response :success
    before = user.quizzes.count
    post teacher_ai_quizzes_path, params: { ai_quiz_draft: request_params.merge(user_id: -1, status: "ready", content: generated_content) }
    draft = user.ai_quiz_drafts.last
    assert_redirected_to teacher_ai_quiz_path(draft)
    assert_equal "queued", draft.status
    assert_nil draft.content
    assert_equal before, user.quizzes.count
    get state_teacher_ai_quiz_path(draft), as: :json
    assert_equal "queued", response.parsed_body["status"]
    client = Object.new
    content = generated_content
    client.define_singleton_method(:generate) { |_draft| content }
    assert AiQuizzes::ProcessNext.call(client: client)
    assert_equal "ready", draft.reload.status
    get teacher_ai_quiz_path(draft)
    assert_response :success
    assert_select 'input[name="reviewed"][required]', 1
    post import_teacher_ai_quiz_path(draft), params: { content: generated_content }
    assert_response :unprocessable_entity
    assert_equal before, user.quizzes.count
    edited = generated_content
    edited["title"] = "Meu quiz revisado"
    edited["questions"][0]["correct_index"] = "2"
    assert_difference "user.quizzes.count", 1 do
      post import_teacher_ai_quiz_path(draft), params: { content: edited, reviewed: "1" }
    end
    quiz = draft.reload.quiz
    assert_redirected_to teacher_quiz_path(quiz)
    assert_equal user.id, quiz.user_id
    assert_equal "Meu quiz revisado", quiz.title
    assert quiz.publishable?
    assert_equal "Mouse", quiz.questions.first.choices.find_by!(correct: true).text
    assert_equal 3, quiz.questions.count
    assert_no_difference "Quiz.count" do
      post import_teacher_ai_quiz_path(draft), params: { content: edited, reviewed: "1" }
    end
    assert_redirected_to teacher_quiz_path(quiz)
  end

  test "ownership applies to draft review state and import" do
    user = make_quiz.user
    other = make_quiz.user
    draft = other.ai_quiz_drafts.create!(request_params)
    get new_teacher_ai_quiz_path
    assert_redirected_to login_path
    sign_in(user)
    get teacher_ai_quiz_path(draft)
    assert_response :not_found
    get state_teacher_ai_quiz_path(draft), as: :json
    assert_response :not_found
    post import_teacher_ai_quiz_path(draft), params: { reviewed: "1", content: generated_content }
    assert_response :not_found
  end

  test "invalid inputs pending duplicate and invalid review do not create quizzes" do
    user = make_quiz.user
    sign_in(user)
    post teacher_ai_quizzes_path, params: { ai_quiz_draft: request_params.merge(question_count: 100) }
    assert_response :unprocessable_entity
    assert_empty user.ai_quiz_drafts
    post teacher_ai_quizzes_path, params: { ai_quiz_draft: request_params }
    draft = user.ai_quiz_drafts.last
    assert_no_difference "AiQuizDraft.count" do
      post teacher_ai_quizzes_path, params: { ai_quiz_draft: request_params }
    end
    assert_response :unprocessable_entity
    post import_teacher_ai_quiz_path(draft), params: { reviewed: "1", content: generated_content }
    assert_response :unprocessable_entity
    draft.update!(status: "ready", content: generated_content)
    invalid = generated_content
    invalid["questions"][1]["correct_index"] = "9"
    assert_no_difference "Quiz.count" do
      post import_teacher_ai_quiz_path(draft), params: { reviewed: "1", content: invalid }
    end
    assert_response :unprocessable_entity
    assert_equal "ready", draft.reload.status
  end

  test "worker reports failure waits during games and recovers an interrupted request" do
    user = make_quiz.user
    draft = user.ai_quiz_drafts.create!(request_params)
    game = GameSessions::Create.call(user.quizzes.first)
    GameSessions::Start.call(game)
    client = Object.new
    client.define_singleton_method(:generate) { |_draft| raise GameError, "Groq indisponível" }
    assert_not AiQuizzes::ProcessNext.call(client: client)
    assert_equal "queued", draft.reload.status
    GameSessions::Finish.call(game)
    assert AiQuizzes::ProcessNext.call(client: client)
    assert_equal "failed", draft.reload.status
    assert_equal "Groq indisponível", draft.error_message
    draft.update!(status: "processing")
    assert_not AiQuizzes::ProcessNext.call(client: client)
    assert_equal "failed", draft.reload.status
    assert_match "interrompido", draft.error_message
  end
  test "review form displays all twenty questions" do
    user = make_quiz.user
    sign_in(user)
    content = generated_content
    content["questions"] = 20.times.map { |i| generated_content["questions"].first.merge("statement" => "Pergunta #{i + 1}") }
    draft = user.ai_quiz_drafts.create!(request_params.merge(question_count: 20, status: "ready", content: content))
    get teacher_ai_quiz_path(draft)
    assert_response :success
    assert_select 'textarea[name="content[questions][19][statement]"]', 1
    assert_select 'select[name$="[correct_index]"]', 20
  end
end
