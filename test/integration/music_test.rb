require "test_helper"

class MusicTest < ActionDispatch::IntegrationTest
  def wav
    # Valid local PCM WAV, 0.1 seconds of silence, original generated test data.
    samples = "\0" * 1600
    "RIFF" + [ 36 + samples.bytesize ].pack("V") + "WAVEfmt " + [ 16, 1, 1, 8000, 16000, 2, 16 ].pack("VvvVVvv") + "data" + [ samples.bytesize ].pack("V") + samples
  end

  test "uploaded music is local and snapshotted into new games" do
    quiz = make_quiz(count: 1)
    post login_path, params: { email: quiz.user.email, password: "uma-senha-local-segura" }
    file = Tempfile.new([ "music", ".wav" ])
    file.binmode
    file.write(wav)
    file.rewind
    patch teacher_quiz_path(quiz), params: { quiz: { background_music: Rack::Test::UploadedFile.new(file.path, "audio/wav") } }
    assert_redirected_to teacher_quiz_path(quiz)
    assert quiz.reload.background_music.attached?
    game = GameSessions::Create.call(quiz)
    assert_equal quiz.background_music.blob_id, game.background_music.blob_id
    get teacher_game_session_path(game)
    assert_select '[data-controller="music"]', 1
    assert_select 'button[aria-pressed="false"]', text: "♫ Ativar música"
    post join_path, params: { code: game.join_code, nickname: "Ana" }
    get play_path
    assert_select '[data-controller="music"]', 1
    url = css_select('[data-controller="music"]').first["data-music-url-value"]
    assert url.start_with?("/")
    get url
    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_equal wav, response.body
    quiz.background_music.detach
    assert game.reload.background_music.attached?
  ensure
    file&.close!
  end

  test "unsupported audio is rejected and quizzes without audio remain playable" do
    quiz = make_quiz(count: 1)
    quiz.background_music.attach(io: StringIO.new("not music"), filename: "file.html", content_type: "text/html")
    assert_not quiz.valid?
    quiz.background_music.detach
    game = GameSessions::Create.call(quiz)
    post join_path, params: { code: game.join_code, nickname: "Bia" }
    get play_path
    assert_response :success
    assert_select '[data-controller="music"]', 0
  end
end
