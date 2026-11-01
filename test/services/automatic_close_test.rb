require "test_helper"

class AutomaticCloseTest < ActiveSupport::TestCase
  test "last active answer closes immediately without releasing results or changing score deadline" do
    game = make_game(count: 1)
    first = join_game(game, nickname: "Primeiro")
    last = join_game(game, nickname: "Último")
    removed = join_game(game, nickname: "Removido")
    removed.update!(removed_at: Time.current)
    round = open_round(game)
    deadline = round.closes_at
    choice = round.session_question.session_choices.first
    travel_to(round.opened_at + 10.seconds, with_usec: true) do
      Answers::Submit.call(first, round_id: round.id, choice_id: choice.id)
      assert_equal "open", round.reload.status
      answer = Answers::Submit.call(last, round_id: round.id, choice_id: choice.id)
      assert_equal "closed", round.reload.status
      assert_equal deadline, round.closes_at
      assert_operator round.closed_at, :<, deadline
      assert_in_delta 833, answer.points, 1
      state = GameState.call(game, participant: last)
      assert_nil state[:result]
      assert_nil state[:correct_choice_id]
      assert_nil state[:ranking]
      assert_equal answer.id, Answers::Submit.call(last, round_id: round.id, choice_id: choice.id).id
      Rounds::Reveal.call(game, round_id: round.id)
      assert GameState.call(game, participant: last).dig(:result, :correct)
    end
  end

  test "removing the remaining participant allows state polling to close the round" do
    game = make_game(count: 1)
    first = join_game(game, nickname: "Respondeu")
    other = join_game(game, nickname: "Saiu")
    round = open_round(game)
    Answers::Submit.call(first, round_id: round.id, choice_id: round.session_question.session_choices.first.id)
    assert_equal "open", round.reload.status
    other.update!(removed_at: Time.current)
    assert_equal "closed", GameState.call(game, participant: first).dig(:round, :status)
  end

  test "empty rooms do not close before the deadline" do
    game = make_game(count: 1)
    open_round(game)
    assert_equal "open", GameState.call(game).dig(:round, :status)
  end
end
