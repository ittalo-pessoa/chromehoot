class AccessAttempt < ApplicationRecord
  def self.check!(key, limit:)
    digest = Digest::SHA256.hexdigest(key)
    transaction do
      connection.execute("SELECT pg_advisory_xact_lock(#{digest.first(15).to_i(16)})")
      where("created_at < ?", 15.minutes.ago).delete_all
      raise GameError, "Muitas tentativas. Aguarde 15 minutos e tente novamente." if where(key: digest).count >= limit
      create!(key: digest, created_at: Time.current)
    end
  end
end
