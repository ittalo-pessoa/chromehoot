class AiQuizDraft < ApplicationRecord
  belongs_to :user
  belongs_to :quiz, optional: true
  validates :topic, :subject, :grade_level, presence: true
  validates :topic, length: { maximum: 250 }
  validates :subject, length: { maximum: 160 }
  validates :grade_level, length: { maximum: 100 }
  validates :difficulty, inclusion: { in: %w[easy medium hard] }
  validates :question_count, inclusion: { in: 3..5 }
  validates :status, inclusion: { in: %w[queued processing ready failed imported] }
end
