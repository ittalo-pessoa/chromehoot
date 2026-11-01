class Round < ApplicationRecord
  belongs_to :game_session
  belongs_to :session_question
  has_many :answers, dependent: :restrict_with_error
  validate do
    errors.add(:base, "Questão de outra partida") if session_question.game_session_id != game_session_id
  end
end
