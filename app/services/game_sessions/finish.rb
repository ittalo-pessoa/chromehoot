module GameSessions
  class Finish
    def self.call(game, round_id: nil)
      GameSessions::Transition.call(game, "finish", round_id: round_id)
    end
  end
end
