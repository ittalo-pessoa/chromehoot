class Quiz < ApplicationRecord
  has_one_attached :background_music
  validate :safe_background_music
  belongs_to :user
  has_many :questions, -> { order(:position) }, dependent: :destroy
  has_many :game_sessions, dependent: :restrict_with_error
  validates :title, :subject, presence: true, length: { maximum: 160 }
  validates :description, length: { maximum: 3000 }

  def safe_background_music
    return unless background_music.attached?
    allowed = %w[audio/mpeg audio/mp3 audio/ogg audio/wav audio/x-wav audio/mp4 audio/x-m4a]
    unless allowed.include?(background_music.blob.content_type) && background_music.blob.byte_size <= 15.megabytes
      errors.add(:background_music, "deve ser MP3, OGG, WAV ou M4A, com até 15 MB")
    end
  end

  def publishable?
    valid? && questions.any? && questions.all?(&:valid?)
  end
end
