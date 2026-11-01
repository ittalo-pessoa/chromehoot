module Quizzes
  class Delete
    def self.call(quiz)
      quiz.with_lock do
        if quiz.game_sessions.exists?
          quiz.update!(archived_at: Time.current)
          :archived
        else
          AiQuizDraft.where(quiz_id: quiz.id).update_all(quiz_id: nil, status: "failed", content: nil, error_message: "O quiz salvo a partir deste pedido foi excluído.", updated_at: Time.current)
          quiz.destroy!
          :deleted
        end
      end
    end
  end
end
