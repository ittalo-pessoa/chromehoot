class GameSession < ApplicationRecord
  has_one_attached :background_music
  belongs_to :user
  belongs_to :quiz
  has_many :session_questions, -> { order(:position) }, dependent: :restrict_with_error
  has_many :participants, dependent: :restrict_with_error
  has_many :rounds, dependent: :restrict_with_error
  validates :status, inclusion: { in: %w[waiting running finished cancelled] }

  def current_round
    rounds.joins(:session_question).order("session_questions.position DESC").first
  end

  def terminal?
    %w[finished cancelled].include?(status)
  end
end
