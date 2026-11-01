class Choice < ApplicationRecord
  belongs_to :question, inverse_of: :choices
  validates :text, presence: true, length: { maximum: 1000 }
end
