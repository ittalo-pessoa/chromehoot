module GameSessions
  class Transition
    def self.call(game, action, round_id: nil)
      game.with_lock do
        round = game.current_round
        round&.lock!
        expire!(round)
        case action.to_s
        when "start"
          if game.status == "waiting"
            game.update!(status: "running", started_at: Time.current)
            create_pending(game, game.session_questions.first)
          end
        when "finish", "cancel"
          unless game.terminal?
            round.update!(status: "closed", closed_at: Time.current) if round&.status == "open"
            game.rounds.where(status: "closed").update_all(status: "revealed") if action.to_s == "finish"
            game.update!(status: action.to_s == "finish" ? "finished" : "cancelled", finished_at: Time.current)
          end
        else
          raise GameError, "A partida não está em andamento." unless game.status == "running"
          if action.to_s == "advance" && round && round.id.to_s != round_id.to_s
            previous = game.rounds.find_by(id: round_id, status: "revealed")
            next if previous && previous.session_question.position < round.session_question.position
          end
          raise GameError, "A rodada mudou. Atualize a tela." unless round && round.id.to_s == round_id.to_s
          case action.to_s
          when "open_question"
            if round.status == "pending"
              now = Time.current
              round.update!(status: "open", opened_at: now, closes_at: now + round.session_question.time_limit_seconds.seconds)
            end
          when "close_question"
            round.update!(status: "closed", closed_at: Time.current) if round.status == "open"
          when "reveal"
            raise GameError, "Feche as respostas antes de revelar." if %w[pending open].include?(round.status)
            round.update!(status: "revealed") if round.status == "closed"
          when "advance"
            if round.status == "revealed"
              question = game.session_questions.where("position > ?", round.session_question.position).first
              raise GameError, "Última questão: finalize a partida." unless question
              create_pending(game, question)
            elsif round.status != "pending"
              raise GameError, "Revele o resultado antes de avançar."
            end
          else
            raise GameError, "Comando inválido."
          end
        end
      end
      game
    end

    def self.expire!(round)
      return unless round&.status == "open"
      now = Time.current
      if now >= round.closes_at
        round.update!(status: "closed", closed_at: round.closes_at)
      else
        active = round.game_session.participants.where(removed_at: nil)
        if active.exists? && !active.where.not(id: round.answers.select(:participant_id)).exists?
          round.update!(status: "closed", closed_at: now)
        end
      end
    end

    def self.create_pending(game, question)
      game.rounds.find_or_create_by!(session_question: question)
    end
  end
end
