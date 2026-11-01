class ParticipantsJoin
  def self.call(code:, nickname:)
    game = GameSession.find_by(join_code: code.to_s.strip)
    raise GameError, "Código inválido. Confira os seis dígitos." unless game
    token = SecureRandom.hex(32)
    participant = game.with_lock do
      raise GameError, "Esta sala não aceita mais entradas." unless game.status == "waiting"
      game.participants.create!(nickname: nickname, credential_digest: Digest::SHA256.hexdigest(token))
    end
    [ participant, token ]
  end
end
