class Answer < ApplicationRecord
  belongs_to :round
  belongs_to :participant
  belongs_to :session_choice
  validates :participant_id, uniqueness: { scope: :round_id }
  validate do
    if participant.game_session_id != round.game_session_id || session_choice.session_question_id != round.session_question_id
      errors.add(:base, "Resposta não pertence à rodada e partida")
    end
  end
end
