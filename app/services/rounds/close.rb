module Rounds
  class Close
    def self.call(game, round_id: nil)
      GameSessions::Transition.call(game, "close_question", round_id: round_id)
    end
  end
end
