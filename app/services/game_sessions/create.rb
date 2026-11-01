module GameSessions
  class Create
    def self.call(quiz)
      attempts = 0
      begin
        Quiz.transaction do
          quiz.lock!
          raise GameError, "O quiz precisa ter questões válidas com exatamente uma alternativa correta." if quiz.archived_at? || !quiz.publishable?
          game = quiz.user.game_sessions.create!(quiz: quiz, join_code: format("%06d", SecureRandom.random_number(1_000_000)))
          game.background_music.attach(quiz.background_music.blob) if quiz.background_music.attached?
          quiz.questions.includes(:choices).each do |question|
            copy = game.session_questions.new(statement: question.statement, position: question.position, time_limit_seconds: question.time_limit_seconds)
            copy.image.attach(question.image.blob) if question.image.attached?
            copy.save!
            question.choices.each { |choice| copy.session_choices.create!(text: choice.text, correct: choice.correct, position: choice.position) }
          end
          game
        end
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts < 10
        raise GameError, "Não foi possível gerar código. Tente novamente."
      end
    end
  end
end
