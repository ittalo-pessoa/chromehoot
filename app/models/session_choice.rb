class SessionChoice < ApplicationRecord
  belongs_to :session_question
  def readonly?
    persisted?
  end
end
