class Question < ApplicationRecord
  belongs_to :quiz
  has_many :choices, -> { order(:position) }, dependent: :destroy, inverse_of: :question
  has_one_attached :image
  accepts_nested_attributes_for :choices, allow_destroy: true, reject_if: ->(attrs) { attrs["text"].blank? && attrs["id"].blank? }
  validates :statement, presence: true, length: { maximum: 3000 }
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :time_limit_seconds, inclusion: { in: 10..180 }
  validate :complete_choices
  validate :safe_image

  def complete_choices
    items = choices.reject(&:marked_for_destruction?)
    errors.add(:base, "Informe de duas a cinco alternativas e exatamente uma correta.") unless (2..5).cover?(items.size) && items.count(&:correct?) == 1
  end

  def safe_image
    return unless image.attached?
    errors.add(:image, "deve ser PNG, JPEG ou WebP, com até 5 MB") unless %w[image/png image/jpeg image/webp].include?(image.blob.content_type) && image.blob.byte_size <= 5.megabytes
  end
end
