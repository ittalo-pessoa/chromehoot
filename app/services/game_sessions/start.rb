module GameSessions
  class Start
    def self.call(game, round_id: nil)
      GameSessions::Transition.call(game, "start", round_id: round_id)
    end
  end
end
