module Rounds
  class Advance
    def self.call(game, round_id: nil)
      GameSessions::Transition.call(game, "advance", round_id: round_id)
    end
  end
end
