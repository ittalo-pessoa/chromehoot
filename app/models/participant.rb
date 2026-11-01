class Participant < ApplicationRecord
  belongs_to :game_session
  has_many :answers, dependent: :restrict_with_error
  before_validation do
    self.nickname = nickname.to_s.strip
    self.normalized_nickname = nickname.unicode_normalize(:nfkc).downcase
  end
  validates :nickname, presence: true, length: { maximum: 30 }
  validates :normalized_nickname, uniqueness: { scope: :game_session_id, message: "já está em uso nesta sala" }
  validates :credential_digest, presence: true
end
