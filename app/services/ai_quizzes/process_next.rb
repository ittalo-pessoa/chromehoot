module AiQuizzes
  class ProcessNext
    LOCK_KEY = 734_152_909

    def self.call(client: nil)
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        return false unless connection.select_value("SELECT pg_try_advisory_lock(#{LOCK_KEY})")
        begin
          # A previous worker may have been interrupted. Never leave its request stuck.
          AiQuizDraft.where(status: "processing").update_all(status: "failed", error_message: "O processo de IA foi interrompido. Gere novamente.", completed_at: Time.current)
          return false if GameSession.exists?(status: "running")
          draft = AiQuizDraft.transaction do
            item = AiQuizDraft.where(status: "queued").order(:created_at).lock("FOR UPDATE SKIP LOCKED").first
            item&.update!(status: "processing", started_at: Time.current)
            item
          end
          return false unless draft
          begin
            content = (client || GroqClient.new).generate(draft)
            # Validate even an alternative client before storing its content.
            content = Content.call(content, count: draft.question_count)
            AiQuizDraft.where(id: draft.id, status: "processing").update_all(status: "ready", content: content, completed_at: Time.current, updated_at: Time.current)
          rescue StandardError => error
            message = error.is_a?(GameError) ? error.message : "A geração falhou. Confira os logs do processo de IA e tente novamente."
            Rails.logger.error("AI draft #{draft.id}: #{error.class}")
            AiQuizDraft.where(id: draft.id, status: "processing").update_all(status: "failed", error_message: message, completed_at: Time.current, updated_at: Time.current)
          end
          true
        ensure
          connection.execute("SELECT pg_advisory_unlock(#{LOCK_KEY})")
        end
      end
    end
  end
end
