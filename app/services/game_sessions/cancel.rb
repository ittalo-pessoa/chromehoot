module GameSessions
  class Cancel
    def self.call(game, round_id: nil)
      GameSessions::Transition.call(game, "cancel", round_id: round_id)
    end
  end
end
