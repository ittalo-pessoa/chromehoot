require "test_helper"
require "csv"

class GameFlowTest < ActiveSupport::TestCase
  test "complete game preserves snapshots and hides results until revealed" do
    quiz = make_quiz
    game = GameSessions::Create.call(quiz)
    participant = join_game(game)
    join_game(game, nickname: "Ainda não respondeu")
    question = quiz.questions.first
    question.update!(statement: "Enunciado alterado")
    assert_equal "Pergunta 1", game.session_questions.first.statement
    assert_raises(ActiveRecord::ReadOnlyRecord) { game.session_questions.first.update!(statement: "Não") }
    round = open_round(game)
    choice = round.session_question.session_choices.find_by!(correct: true)
    travel_to(round.opened_at + 15.seconds, with_usec: true) do
      answer = Answers::Submit.call(participant, round_id: round.id, choice_id: choice.id)
      assert_in_delta 750, answer.points, 1
      assert_equal answer.id, Answers::Submit.call(participant, round_id: round.id, choice_id: choice.id).id
      wrong = round.session_question.session_choices.find_by!(correct: false)
      assert_raises(GameError) { Answers::Submit.call(participant, round_id: round.id, choice_id: wrong.id) }
      state = GameState.call(game, participant: participant)
      assert state[:answered]
      assert_nil state[:correct_choice_id]
      assert_nil state[:result]
      assert_nil state[:ranking]
      assert state[:question][:choices].all? { |c| c.keys.sort == [ :id, :letter, :text ] }
      assert_raises(GameError) { Rounds::Reveal.call(game, round_id: round.id) }
      Rounds::Close.call(game, round_id: round.id)
      assert_nil GameState.call(game, participant: participant)[:result]
      Rounds::Reveal.call(game, round_id: round.id)
      assert_equal answer.points, GameState.call(game, participant: participant).dig(:result, :points)
      assert_equal 1, Rankings::Build.call(game).first[:rank]
      Rounds::Advance.call(game, round_id: round.id)
      assert_equal "pending", game.current_round.status
      assert_raises(GameError) { Rounds::Open.call(game, round_id: round.id) }
      Rounds::Advance.call(game, round_id: round.id)
      assert_equal 2, game.rounds.count
      assert_raises(GameError) { Answers::Submit.call(participant, round_id: round.id, choice_id: choice.id) }
    end
    GameSessions::Finish.call(game)
    GameSessions::Finish.call(game)
    assert game.reload.terminal?
    assert_equal 1, participant.answers.count
    assert_raises(GameError) { ParticipantsJoin.call(code: game.join_code, nickname: "Novo") }
  end

  test "invalid content cannot start a game" do
    quiz = make_quiz(count: 0)
    assert_raises(GameError) { GameSessions::Create.call(quiz) }
    question = make_quiz.questions.first
    question.choices.each { |c| c.update_column(:correct, false) }
    assert_raises(GameError) { GameSessions::Create.call(question.quiz) }
    question.choices.each { |c| c.update_column(:correct, true) }
    assert_raises(GameError) { GameSessions::Create.call(question.quiz) }
  end

  test "join validates codes nickname normalization and game state" do
    game = make_game
    game.update!(join_code: "000123")
    assert_equal 6, game.join_code.length
    join_game(game, nickname: " Ana ")
    assert_raises(ActiveRecord::RecordInvalid) { join_game(game, nickname: "ANA") }
    assert_raises(GameError) { ParticipantsJoin.call(code: "000124", nickname: "Ana") }
    GameSessions::Cancel.call(game)
    assert_raises(GameError) { join_game(game, nickname: "Outro") }
  end

  test "deadline foreign choices removed participants and early close" do
    game = make_game
    participant = join_game(game)
    round = open_round(game)
    foreign = game.session_questions.last.session_choices.first
    assert_raises(GameError) { Answers::Submit.call(participant, round_id: round.id, choice_id: foreign.id) }
    choice = round.session_question.session_choices.first
    travel_to(round.closes_at, with_usec: true) do
      assert_raises(GameError) { Answers::Submit.call(participant, round_id: round.id, choice_id: choice.id) }
      assert_equal "closed", GameState.call(game, participant: participant).dig(:round, :status)
    end
    assert_empty participant.answers
    Rounds::Reveal.call(game, round_id: round.id)
    Rounds::Advance.call(game, round_id: round.id)
    round = game.current_round
    Rounds::Open.call(game, round_id: round.id)
    participant.update!(removed_at: Time.current)
    assert_raises(GameError) { Answers::Submit.call(participant, round_id: round.id, choice_id: foreign.id) }
    assert_equal "removed", GameState.call(game, participant: participant)[:status]
    original_deadline = round.reload.closes_at
    Rounds::Close.call(game, round_id: round.id)
    assert_equal original_deadline, round.reload.closes_at
  end

  test "start open close reveal and finish are idempotent" do
    game = make_game
    2.times { GameSessions::Start.call(game) }
    assert_equal 1, game.rounds.count
    round = game.current_round
    2.times { Rounds::Open.call(game, round_id: round.id) }
    deadline = round.reload.closes_at
    Rounds::Open.call(game, round_id: round.id)
    assert_equal deadline, round.reload.closes_at
    2.times { Rounds::Close.call(game, round_id: round.id) }
    2.times { Rounds::Reveal.call(game, round_id: round.id) }
    2.times { GameSessions::Finish.call(game) }
    assert_equal "finished", game.reload.status
    assert_equal 1, game.rounds.count
  end

  test "ties share rank and csv includes absent participants and neutralizes formulas" do
    game = make_game(count: 1)
    a = join_game(game, nickname: "=SUM(A1)")
    b = join_game(game, nickname: "Bia")
    join_game(game, nickname: "Caio")
    round = open_round(game)
    travel_to(round.opened_at + 10.seconds, with_usec: true) do
      [ a, b ].each { |p| Answers::Submit.call(p, round_id: round.id, choice_id: round.session_question.session_choices.first.id) }
    end
    Rounds::Close.call(game, round_id: round.id)
    Rounds::Reveal.call(game, round_id: round.id)
    GameSessions::Finish.call(game)
    rows = Rankings::Build.call(game)
    assert_equal [ 1, 1, 3 ], rows.map { |r| r[:rank] }
    csv = CSV.parse(Reports::ExportCsv.call(game), col_sep: ";")
    assert_equal "'=SUM(A1)", csv[1][1]
    assert_equal [ "3", "Caio", "0", "0", "0", "1" ], csv[3]
    assert_equal rows.first[:points].to_s, csv[1][2]
  end

  test "question images are local validated and copied into snapshots" do
    quiz = make_quiz(count: 1)
    question = quiz.questions.first
    # One pixel PNG, no external asset needed.
    png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK3sAAAAASUVORK5CYII=")
    question.image.attach(io: StringIO.new(png), filename: "pixel.png", content_type: "image/png")
    assert question.valid?
    game = GameSessions::Create.call(quiz)
    assert_equal question.image.blob_id, game.session_questions.first.image.blob_id
    copy = game.session_questions.first
    question.image.detach
    assert copy.image.attached?
    question.image.attach(io: StringIO.new("<svg/>"), filename: "bad.svg", content_type: "image/svg+xml")
    assert_not question.valid?
  end
end
