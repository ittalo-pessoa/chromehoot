require "test_helper"

class StudentSummaryTest < ActiveSupport::TestCase
  test "final summary contains only the students own revealed outcomes including absence" do
    game = make_game(count: 2)
    first = join_game(game, nickname: "Ana")
    second = join_game(game, nickname: "Bia")
    round = open_round(game)
    choices = round.session_question.session_choices
    Answers::Submit.call(first, round_id: round.id, choice_id: choices.find_by!(correct: true).id)
    assert_nil GameState.call(game, participant: first)[:summary]
    Answers::Submit.call(second, round_id: round.id, choice_id: choices.find_by!(correct: false).id)
    Rounds::Reveal.call(game, round_id: round.id)
    assert_nil GameState.call(game, participant: first)[:summary]
    Rounds::Advance.call(game, round_id: round.id)
    round = game.current_round
    Rounds::Open.call(game, round_id: round.id)
    Answers::Submit.call(second, round_id: round.id, choice_id: round.session_question.session_choices.find_by!(correct: true).id)
    GameSessions::Finish.call(game)
    ana = GameState.call(game, participant: first)[:summary]
    bia = GameState.call(game, participant: second)[:summary]
    assert_equal "Ana", ana[:nickname]
    assert_equal "Bia", bia[:nickname]
    assert_equal [ true, nil ], ana[:questions].map { |q| q[:correct] }
    assert_equal [ false, true ], bia[:questions].map { |q| q[:correct] }
    assert_equal 2, ana[:total]
    assert_equal 1, ana[:correct]
    assert_equal first.answers.sum(:points), ana[:points]
    assert_equal Rankings::Build.call(game).find { |row| row[:participant].id == first.id }[:rank], ana[:rank]
    assert_nil GameState.call(game, teacher: true)[:summary]
    assert ana[:questions].all? { |q| q.keys.sort == [ :correct, :number ] }
  end
end
