require "test_helper"

class ApplicationFlowTest < ActionDispatch::IntegrationTest
  def login(user)
    post login_path, params: { email: user.email, password: "uma-senha-local-segura" }
    assert_redirected_to teacher_quizzes_path
  end

  test "teacher authentication ownership editor reporting and logout" do
    mine = make_quiz
    other = make_quiz
    game = GameSessions::Create.call(other)
    get teacher_quizzes_path
    assert_redirected_to login_path
    post login_path, params: { email: mine.user.email, password: "errada" }
    assert_redirected_to login_path
    login(mine.user)
    [ teacher_quiz_path(other), edit_teacher_quiz_path(other), teacher_game_session_path(game), projector_teacher_game_session_path(game), state_teacher_game_session_path(game), report_teacher_game_session_path(game), report_teacher_game_session_path(game, format: :csv) ].each do |path|
      get path
      assert_response :not_found
    end
    patch teacher_quiz_path(other), params: { quiz: { title: "Invasão" } }
    assert_response :not_found
    post command_teacher_game_session_path(game), params: { command: "start" }
    assert_response :not_found
    get teacher_quizzes_path
    assert_response :success
    get teacher_quiz_path(mine)
    assert_response :success
    get new_teacher_quiz_question_path(mine)
    assert_response :success
    post teacher_quiz_questions_path(mine), params: { question: { statement: "Nova questão", time_limit_seconds: 30, choices_attributes: { "0" => { text: "Sim", correct: "1" }, "1" => { text: "Não", correct: "0" }, "2" => { text: "" } } } }
    assert_redirected_to teacher_quiz_path(mine)
    assert_equal 3, mine.questions.count
    q = mine.questions.last
    patch move_teacher_quiz_question_path(mine, q), params: { direction: "up" }
    assert_equal 2, q.reload.position
    get edit_teacher_quiz_question_path(mine, q)
    assert_response :success
    patch teacher_quiz_question_path(mine, q), params: { question: { statement: "Atualizada", choices_attributes: q.choices.each_with_index.to_h { |c, i| [ i.to_s, { id: c.id, text: c.text, correct: c.correct ? "1" : "0" } ] } } }
    assert_redirected_to teacher_quiz_path(mine)
    assert_equal "Atualizada", q.reload.statement
    post duplicate_teacher_quiz_path(mine)
    assert_equal 2, mine.user.quizzes.count
    post teacher_game_sessions_path, params: { quiz_id: mine.id }
    own_game = mine.user.game_sessions.last
    assert_redirected_to teacher_game_session_path(own_game)
    [ teacher_game_session_path(own_game), projector_teacher_game_session_path(own_game), report_teacher_game_session_path(own_game), report_teacher_game_session_path(own_game, format: :csv), teacher_game_sessions_path ].each do |path|
      get path
      assert_response :success
    end
    delete teacher_quiz_path(mine)
    assert mine.reload.archived_at?
    assert own_game.reload.persisted?
    delete logout_path
    get teacher_quizzes_path
    assert_redirected_to login_path
  end

  test "student recovers signed credential and never receives answer before reveal" do
    game = make_game(count: 1)
    get root_path
    assert_response :success
    post join_path, params: { code: game.join_code, nickname: "Lia" }
    assert_redirected_to play_path
    assert_match(/httponly/i, response.headers["set-cookie"].join)
    token_count = game.participants.count
    2.times { get play_path; assert_response :success }
    post join_path, params: { code: game.join_code, nickname: "Lia" }
    assert_equal token_count, game.participants.count
    round = open_round(game)
    get play_state_path, as: :json
    assert_response :success
    choice = round.session_question.session_choices.find_by!(correct: true)
    assert_not response.body.include?("correct")
    assert_not response.body.include?("points")
    post play_answer_path, params: { round_id: round.id, choice_id: choice.id, participant_id: -1 }, as: :json
    assert_equal({ "accepted" => true }, response.parsed_body)
    get play_state_path, as: :json
    assert response.parsed_body["answered"]
    assert_not response.body.include?("correct")
    assert_not response.body.include?("points")
    Rounds::Close.call(game, round_id: round.id)
    get play_state_path, as: :json
    assert_not response.body.include?("correct")
    Rounds::Reveal.call(game, round_id: round.id)
    get play_state_path, as: :json
    assert response.parsed_body.dig("result", "correct")
    stranger = open_session
    stranger.get play_state_path, as: :json
    assert_equal 401, stranger.response.status
    stranger.post play_answer_path, params: { participant_id: game.participants.first.id, round_id: round.id, choice_id: choice.id }, as: :json
    assert_equal 401, stranger.response.status
  end

  test "login and join throttling does not use shared classroom IP" do
    user = make_quiz.user
    12.times { post login_path, params: { email: user.email, password: "errada" } }
    post login_path, params: { email: user.email, password: "uma-senha-local-segura" }
    assert_match "Muitas tentativas", flash[:alert]
    game = make_game
    31.times { post join_path, params: { code: "invalid", nickname: "Teste" } }
    assert_match "Muitas tentativas", flash[:alert]
    other_browser = open_session
    other_browser.post join_path, params: { code: game.join_code, nickname: "Outro navegador" }
    assert_equal 302, other_browser.response.status
    assert_equal 1, game.participants.count
  end
end
