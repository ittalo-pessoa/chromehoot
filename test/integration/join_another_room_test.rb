require "test_helper"

class JoinAnotherRoomTest < ActionDispatch::IntegrationTest
  test "a finished credential does not override the requested new room" do
    old_game = make_game(count: 1)
    new_game = make_game(count: 1)
    post join_path, params: { code: old_game.join_code, nickname: "Ana" }
    GameSessions::Finish.call(old_game)
    post join_path, params: { code: new_game.join_code, nickname: "Ana" }
    assert_redirected_to play_path
    assert_equal 1, new_game.participants.count
    assert_equal 1, old_game.participants.count
    get play_state_path, as: :json
    assert_equal "waiting", response.parsed_body["status"]
    assert_nil response.parsed_body["summary"]
    post join_path, params: { code: new_game.join_code, nickname: "Ana" }
    assert_equal 1, new_game.participants.count
  end

  test "same ended room shows an explicit message instead of recovering a concluded game" do
    game = make_game(count: 1)
    post join_path, params: { code: game.join_code, nickname: "Ana" }
    GameSessions::Finish.call(game)
    post join_path, params: { code: game.join_code, nickname: "Ana" }
    assert_redirected_to root_path
    assert_match "Esta sala já foi encerrada", flash[:alert]
    assert_equal 1, game.participants.count
  end

  test "different room code is validated even when a participant cookie exists" do
    game = make_game(count: 1)
    post join_path, params: { code: game.join_code, nickname: "Ana" }
    post join_path, params: { code: "invalido", nickname: "Ana" }
    assert_redirected_to root_path
    assert_match "Código inválido", flash[:alert]
    assert_equal 1, game.participants.count
  end
end
