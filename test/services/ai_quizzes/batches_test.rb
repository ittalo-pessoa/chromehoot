require "test_helper"

class AiQuizBatchesTest < ActiveSupport::TestCase
  test "twenty questions are generated in bounded batches and all can be saved" do
    user = make_quiz.user
    draft = user.ai_quiz_drafts.create!(topic: "Hardware", subject: "Informática", grade_level: "Ensino Médio", difficulty: "easy", question_count: 20)
    client = AiQuizzes::OllamaClient.new
    calls = []
    client.define_singleton_method(:generate_batch) do |batch, previous_statements:|
      calls << [ batch.question_count, previous_statements.size ]
      offset = previous_statements.size
      { "title" => "Hardware", "description" => "", "questions" => batch.question_count.times.map { |i| { "statement" => "Questão #{offset + i + 1}", "choices" => %w[A B C D], "correct_index" => 0 } } }
    end
    content = client.generate(draft)
    assert_equal [ [ 5, 0 ], [ 5, 5 ], [ 5, 10 ], [ 5, 15 ] ], calls
    assert_equal 20, content["questions"].size
    draft.update!(status: "ready", content: content)
    quiz = AiQuizzes::Import.call(draft, content)
    assert_equal 20, quiz.questions.count
    assert quiz.publishable?
  end

  test "six questions avoid a final batch with only one question and failures do not save a quiz" do
    draft = AiQuizDraft.new(question_count: 6)
    client = AiQuizzes::OllamaClient.new
    sizes = []
    client.define_singleton_method(:generate_batch) do |batch, previous_statements:|
      sizes << batch.question_count
      raise GameError, "Falha no segundo lote" if sizes.size == 2
      { "title" => "Quiz", "description" => "", "questions" => batch.question_count.times.map { |i| { "statement" => "Questão #{i + 1}", "choices" => %w[A B C D], "correct_index" => 0 } } }
    end
    assert_no_difference "Quiz.count" do
      assert_raises(GameError) { client.generate(draft) }
    end
    assert_equal [ 3, 3 ], sizes
  end
end
