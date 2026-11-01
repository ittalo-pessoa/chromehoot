class GameState
  def self.call(game, participant: nil, teacher: false)
    game.with_lock do
      round = game.current_round
      round&.lock!
      GameSessions::Transition.expire!(round)
      data = { status: game.status, server_time: Time.current.iso8601(3), participants: game.participants.where(removed_at: nil).order(:created_at).pluck(:nickname) }
      if participant&.removed_at?
        return { status: "removed", server_time: Time.current.iso8601(3) }
      end
      if round
        data[:round] = { id: round.id, status: round.status, number: game.session_questions.where("position <= ?", round.session_question.position).count, total: game.session_questions.count, closes_at: round.closes_at&.iso8601(3) }
        unless round.status == "pending"
          question = round.session_question
          data[:question] = { statement: question.statement, choices: question.session_choices.map { |c| { id: c.id, text: c.text, letter: ("A".ord + c.position - 1).chr } } }
          data[:question][:image_url] = Rails.application.routes.url_helpers.rails_blob_path(question.image, only_path: true) if question.image.attached?
        end
        answer = participant && round.answers.find_by(participant: participant)
        data[:answered] = answer.present? if participant
        data[:answer_count] = round.answers.count if teacher
        if round.status == "revealed"
          data[:correct_choice_id] = round.session_question.session_choices.find_by!(correct: true).id
          data[:result] = { correct: answer.correct, points: answer.points } if answer
          data[:distribution] = round.answers.group(:session_choice_id).count
        end
      end
      if game.rounds.exists?(status: "revealed") || game.terminal?
        ranking = Rankings::Build.call(game, public_only: true)
        data[:ranking] = ranking.map { |r| r.slice(:rank, :nickname, :points, :correct) }
        if participant && game.status == "finished"
          own = ranking.find { |r| r[:participant].id == participant.id }
          revealed = game.rounds.where(status: "revealed").joins(:session_question).order("session_questions.position")
          answers = participant.answers.where(round_id: revealed.select("rounds.id")).index_by(&:round_id)
          data[:summary] = { nickname: participant.nickname, rank: own[:rank], points: own[:points], correct: own[:correct], total: revealed.size,
            questions: revealed.map { |r| { number: r.session_question.position, correct: answers[r.id]&.correct } } }
        end
      end
      data
    end
  end
end
