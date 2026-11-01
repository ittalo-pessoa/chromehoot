class SessionQuestion < ApplicationRecord
  belongs_to :game_session
  has_many :session_choices, -> { order(:position) }, dependent: :restrict_with_error
  has_one_attached :image
  def readonly?
    persisted?
  end
end
