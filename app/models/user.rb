class User < ApplicationRecord
  has_secure_password
  validates :password_confirmation, presence: true, on: :registration
  has_many :quizzes, dependent: :restrict_with_error
  has_many :game_sessions, dependent: :restrict_with_error
  normalizes :email, with: ->(value) { value.strip.downcase }
  validates :name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 12 }, allow_nil: true
end
