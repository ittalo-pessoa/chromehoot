module Answers
  class Submit
    def self.call(participant, round_id:, choice_id:)
      game = participant.game_session
      game.with_lock do
        participant.reload
        raise GameError, "Você foi removido desta partida." if participant.removed_at?
        round = game.current_round
        raise GameError, "A rodada mudou." unless round && round.id.to_s == round_id.to_s
        round.lock!
        choice = round.session_question.session_choices.find_by(id: choice_id)
        raise GameError, "Alternativa inválida." unless choice
        existing = round.answers.find_by(participant: participant)
        if existing
          raise GameError, "Sua resposta já foi enviada e não pode ser alterada." unless existing.session_choice_id == choice.id
          return existing
        end
        received_at = Time.current
        GameSessions::Transition.expire!(round)
        raise GameError, "O prazo para responder terminou." unless game.status == "running" && round.status == "open" && received_at < round.closes_at
        duration_ms = ((round.closes_at - round.opened_at) * 1000).round
        elapsed_ms = ((received_at - round.opened_at) * 1000).round.clamp(0, duration_ms)
        points = choice.correct? ? 500 + (500 * (duration_ms - elapsed_ms) / duration_ms) : 0
        answer = round.answers.create!(participant: participant, session_choice: choice, received_at: received_at, correct: choice.correct?, points: points)
        GameSessions::Transition.expire!(round)
        answer
      end
    end
  end
end
