require "test_helper"

class FullMatchTest < ActionDispatch::IntegrationTest
  test "teacher and two browsers complete all rounds over HTTP" do
    quiz = make_quiz(count: 5)
    teacher = open_session
    teacher.post login_path, params: { email: quiz.user.email, password: "uma-senha-local-segura" }
    teacher.post teacher_game_sessions_path, params: { quiz_id: quiz.id }
    game = quiz.game_sessions.last
    teacher.get projector_teacher_game_session_path(game)
    assert_equal 200, teacher.response.status
    assert_includes teacher.response.body, "Ir para o controle da partida"
    assert_includes teacher.response.body, teacher_game_session_path(game)
    teacher.get teacher_game_session_path(game)
    assert_includes teacher.response.body, 'data-game-command="start"'
    assert_includes teacher.response.body, 'value="Iniciar partida"'
    students = 2.times.map do |i|
      browser = open_session
      browser.post join_path, params: { code: game.join_code, nickname: "Aluno #{i + 1}" }
      browser
    end
    teacher.post command_teacher_game_session_path(game), params: { command: "start" }
    assert_equal "running", game.reload.status
    5.times do |index|
      round = game.current_round
      teacher.post command_teacher_game_session_path(game), params: { command: "open_question", round_id: round.id }
      students.each_with_index do |browser, student_index|
        browser.get play_state_path, as: :json
        state = browser.response.parsed_body
        assert_equal round.id, state.dig("round", "id")
        browser.post play_answer_path, params: { round_id: round.id, choice_id: state["question"]["choices"][student_index]["id"] }, as: :json
        assert_equal({ "accepted" => true }, browser.response.parsed_body)
      end
      teacher.post command_teacher_game_session_path(game), params: { command: "close_question", round_id: round.id }
      teacher.post command_teacher_game_session_path(game), params: { command: "reveal", round_id: round.id }
      students.first.get play_state_path, as: :json
      assert students.first.response.parsed_body.dig("result", "correct")
      teacher.post command_teacher_game_session_path(game), params: { command: "advance", round_id: round.id } if index < 4
    end
    teacher.post command_teacher_game_session_path(game), params: { command: "finish" }
    assert_equal "finished", game.reload.status
    assert_equal 10, Answer.where(round_id: game.rounds.select(:id)).count
    students.last.get play_state_path, as: :json
    assert_equal "finished", students.last.response.parsed_body["status"]
    assert_equal 5, students.last.response.parsed_body["ranking"].first["correct"]
    teacher.get report_teacher_game_session_path(game)
    assert_equal 200, teacher.response.status
    teacher.get report_teacher_game_session_path(game, format: :csv)
    assert_match "Aluno 1", teacher.response.body
  end

  test "scripts styles importmap and images are served from the same local application" do
    get root_path
    doc = Nokogiri::HTML(response.body)
    urls = doc.css("script[src],link[rel=stylesheet]").map { |node| node["src"] || node["href"] }
    imports = JSON.parse(doc.at_css("script[type=importmap]").text)["imports"].values
    (urls + imports).uniq.each do |url|
      assert url.start_with?("/"), "Recurso externo: #{url}"
      get url
      assert_response :success
    end
    quiz = make_quiz(count: 1)
    q = quiz.questions.first
    png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK3sAAAAASUVORK5CYII=")
    q.image.attach(io: StringIO.new(png), filename: "imagem.png", content_type: "image/png")
    game = GameSessions::Create.call(quiz)
    post join_path, params: { code: game.join_code, nickname: "Ana" }
    open_round(game)
    get play_state_path, as: :json
    path = response.parsed_body.dig("question", "image_url")
    assert path.start_with?("/")
    get path
    assert_response :redirect
    assert_equal "www.example.com", URI(response.location).host
    follow_redirect!
    assert_response :success
    assert_equal png, response.body
  end

  test "mutations reject missing CSRF tokens" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post login_path, params: { email: "teacher@escola.test", password: "qualquer-senha" }
    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
