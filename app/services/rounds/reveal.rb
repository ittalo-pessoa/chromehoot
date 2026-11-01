module Rounds
  class Reveal
    def self.call(game, round_id: nil)
      GameSessions::Transition.call(game, "reveal", round_id: round_id)
    end
  end
end
