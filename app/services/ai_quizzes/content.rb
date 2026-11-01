module AiQuizzes
  class Content
    def self.call(data, count:, form: false)
      raise GameError, "A IA não devolveu um quiz válido. Tente novamente." unless data.is_a?(Hash)
      items = data["questions"]
      if form && items.is_a?(Hash) && items.keys.all? { |key| key.match?(/\A\d+\z/) }
        items = items.sort_by { |key, _| key.to_i }.map(&:last)
      end
      raise GameError, "O quiz precisa conter #{count} questões completas." unless items.is_a?(Array) && items.size == count
      result = { "title" => text(data["title"], 160, "Título"), "description" => text(data["description"], 3000, "Descrição", optional: true) }
      result["questions"] = items.map do |question|
        raise GameError, "Formato de questão inválido." unless question.is_a?(Hash)
        choices = question["choices"]
        raise GameError, "Cada questão precisa ter quatro alternativas." unless choices.is_a?(Array) && choices.size == 4
        choices = choices.map { |choice| text(choice, 1000, "Alternativa") }
        raise GameError, "As alternativas de uma questão precisam ser diferentes." unless choices.map(&:downcase).uniq.size == 4
        correct = question["correct_index"]
        correct = correct.to_i if form && correct.is_a?(String) && correct.match?(/\A[0-3]\z/)
        raise GameError, "Selecione exatamente uma alternativa correta por questão." unless correct.is_a?(Integer) && (0..3).cover?(correct)
        time = form ? question["time_limit_seconds"].to_s : "30"
        raise GameError, "O tempo precisa ser um número inteiro entre 10 e 180 segundos." unless time.match?(/\A\d{2,3}\z/) && (10..180).cover?(time.to_i)
        { "statement" => text(question["statement"], 3000, "Enunciado"), "choices" => choices, "correct_index" => correct, "time_limit_seconds" => time.to_i }
      end
      statements = result["questions"].map { |q| q["statement"].downcase }
      raise GameError, "As questões precisam ter enunciados diferentes." unless statements.uniq.size == count
      result
    end

    def self.text(value, limit, label, optional: false)
      value = "" if optional && value.nil?
      raise GameError, "#{label}: informe um texto com até #{limit} caracteres." unless value.is_a?(String) && value.length <= limit && (optional || value.strip.present?)
      value.strip
    end
  end
end
