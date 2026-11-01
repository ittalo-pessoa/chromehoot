module AiQuizzes
  class Import
    def self.call(draft, data)
      draft.with_lock do
        return draft.quiz if draft.status == "imported"
        raise GameError, "Aguarde a geração terminar antes de salvar." unless draft.status == "ready"
        content = Content.call(data, count: draft.question_count, form: true)
        quiz = draft.user.quizzes.create!(title: content["title"], description: content["description"], subject: draft.subject)
        content["questions"].each_with_index do |question, index|
          quiz.questions.create!(statement: question["statement"], position: index + 1, time_limit_seconds: question["time_limit_seconds"],
            choices_attributes: question["choices"].each_with_index.map { |text, i| { text: text, position: i + 1, correct: i == question["correct_index"] } })
        end
        draft.update!(status: "imported", quiz: quiz, content: content)
        quiz
      end
    end
  end
end
