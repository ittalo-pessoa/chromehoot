ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  def make_quiz(user: nil, count: 2)
    user ||= User.create!(name: "Professor", email: "prof-#{SecureRandom.hex(5)}@escola.test", password: "uma-senha-local-segura")
    quiz = user.quizzes.create!(title: "Quiz de informática", subject: "Informática")
    count.times do |i|
      quiz.questions.create!(statement: "Pergunta #{i + 1}", position: i + 1, time_limit_seconds: 30,
        choices_attributes: [ { text: "Alternativa certa", correct: true, position: 1 }, { text: "Alternativa errada", correct: false, position: 2 } ])
    end
    quiz
  end

  def make_game(count: 2)
    GameSessions::Create.call(make_quiz(count: count))
  end

  def join_game(game, nickname: "Aluno")
    ParticipantsJoin.call(code: game.join_code, nickname: nickname).first
  end

  def open_round(game)
    GameSessions::Start.call(game)
    round = game.current_round
    Rounds::Open.call(game, round_id: round.id)
    round.reload
  end
end
