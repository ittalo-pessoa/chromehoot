require "test_helper"

class DeletionsTest < ActionDispatch::IntegrationTest
  def login(user)
    post login_path, params: { email: user.email, password: "uma-senha-local-segura" }
  end

  def draft_for(user, **options)
    user.ai_quiz_drafts.create!({ topic: "Hardware", subject: "Informática", grade_level: "Ensino Médio", difficulty: "easy", question_count: 3 }.merge(options))
  end

  def content
    { "title" => "Hardware", "description" => "", "questions" => 3.times.map { |i| { "statement" => "Pergunta #{i + 1}", "choices" => %w[Mouse Teclado Monitor Cabo], "correct_index" => 0 } } }
  end

  test "delete unused quiz and its choices without breaking the associated AI history" do
    quiz = make_quiz
    draft = draft_for(quiz.user, quiz: quiz, status: "imported", content: content)
    login(quiz.user)
    get teacher_quiz_path(quiz)
    assert_select "button", text: "Excluir quiz"
    assert_difference "Quiz.count", -1 do
      assert_difference "Question.count", -2 do
        assert_difference "Choice.count", -4 do
          delete teacher_quiz_path(quiz)
        end
      end
    end
    assert_redirected_to teacher_quizzes_path
    assert_nil draft.reload.quiz_id
    assert_equal "failed", draft.status
    get teacher_ai_quiz_path(draft)
    assert_response :success
  end

  test "quiz with sessions is removed from dashboard while preserving game snapshots and reports" do
    quiz = make_quiz
    game = GameSessions::Create.call(quiz)
    original = game.session_questions.pluck(:statement)
    login(quiz.user)
    assert_no_difference "Quiz.count" do
      delete teacher_quiz_path(quiz)
    end
    assert quiz.reload.archived_at?
    assert_equal original, game.reload.session_questions.pluck(:statement)
    get teacher_quizzes_path
    assert_select ".quiz-card", 0
    get report_teacher_game_session_path(game)
    assert_response :success
  end

  test "delete a queued request unblocks a new request and never deletes an imported quiz" do
    user = make_quiz.user
    login(user)
    draft = draft_for(user)
    get new_teacher_ai_quiz_path
    assert_select "form[action='#{teacher_ai_quiz_path(draft)}'] input[name='_method'][value='delete']"
    assert_difference "AiQuizDraft.count", -1 do
      delete teacher_ai_quiz_path(draft)
    end
    assert_redirected_to new_teacher_ai_quiz_path
    post teacher_ai_quizzes_path, params: { ai_quiz_draft: { topic: "Nova tentativa", subject: "Informática", grade_level: "Ensino Médio", difficulty: "easy", question_count: 3 } }
    assert_redirected_to teacher_ai_quiz_path(user.ai_quiz_drafts.last)
    imported = draft_for(user, status: "imported", quiz: user.quizzes.first)
    assert_no_difference "Quiz.count" do
      delete teacher_ai_quiz_path(imported)
    end
  end

  test "another teacher cannot delete quizzes or AI requests" do
    own = make_quiz
    other = make_quiz
    draft = draft_for(other.user)
    login(own.user)
    assert_no_difference "Quiz.count" do
      delete teacher_quiz_path(other)
    end
    assert_response :not_found
    assert_no_difference "AiQuizDraft.count" do
      delete teacher_ai_quiz_path(draft)
    end
    assert_response :not_found
    assert_nil other.reload.archived_at
  end

  test "worker discards both success and failure if the request was deleted while generating" do
    user = make_quiz.user
    [ false, true ].each do |failure|
      draft = draft_for(user)
      generated = content
      client = Object.new
      client.define_singleton_method(:generate) do |active|
        AiQuizDraft.find(active.id).destroy!
        raise GameError, "Falhou depois de excluir" if failure
        generated
      end
      assert AiQuizzes::ProcessNext.call(client: client)
      assert_not AiQuizDraft.exists?(draft.id)
      assert_empty user.ai_quiz_drafts.where(status: %w[queued processing ready])
    end
  end
end
