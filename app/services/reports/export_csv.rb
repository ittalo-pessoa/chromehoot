require "csv"
module Reports
  class ExportCsv
    def self.safe(value)
      text = value.to_s
      text.match?(/\A[\s]*[=+\-@\t\r\n]/) ? "'#{text}" : text
    end

    def self.call(game)
      rounds = game.rounds.where.not(opened_at: nil).includes(:session_question).to_a
      CSV.generate(col_sep: ";", encoding: "UTF-8") do |csv|
        csv << [ "Colocação", "Apelido", "Pontos", "Acertos", "Erros", "Ausências" ]
        Rankings::Build.call(game).each do |row|
          items = row[:participant].answers.where(round_id: rounds.map(&:id))
          csv << [ row[:rank], safe(row[:nickname]), row[:points], row[:correct], items.where(correct: false).count, rounds.size - items.count ]
        end
        csv << []
        csv << [ "Questão", "Acertos", "Erros", "Ausências" ]
        rounds.each do |round|
          csv << [ safe(round.session_question.statement), round.answers.where(correct: true).count, round.answers.where(correct: false).count, game.participants.count - round.answers.count ]
        end
      end
    end
  end
end
