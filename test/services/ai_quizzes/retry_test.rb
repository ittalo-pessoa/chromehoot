require "test_helper"

class AiQuizRetryTest < ActiveSupport::TestCase
  def data
    { "title" => "Hardware", "description" => "", "questions" => 3.times.map { |i| { "statement" => "Pergunta #{i + 1}", "choices" => %w[Teclado Monitor Mouse Cabo], "correct_index" => 0 } } }
  end

  def draft
    AiQuizDraft.new(topic: "Hardware", subject: "Informática", grade_level: "Ensino Médio", difficulty: "easy", question_count: 3)
  end

  test "retries duplicate alternatives with corrective feedback and preserves the correct choice" do
    bad = data
    bad["questions"][0]["choices"][1] = "Teclado"
    outputs = [ bad, data ].map { |content| JSON.generate(done: true, message: { content: JSON.generate(content) }) }
    calls = []
    client = AiQuizzes::OllamaClient.new
    client.define_singleton_method(:request) { |payload| calls << payload; outputs.shift }
    result = client.generate(draft)
    assert_equal 2, calls.size
    assert_includes calls.last[:messages].last[:content], "alternativas de uma questão precisam ser diferentes"
    assert_equal 0, result["questions"][0]["correct_index"]
    assert_equal %w[Teclado Monitor Mouse Cabo], result["questions"][0]["choices"]
  end

  test "invalid output is rejected after two attempts and network failures are not retried" do
    bad = data
    bad["questions"][0]["choices"][1] = "Teclado"
    output = JSON.generate(done: true, message: { content: JSON.generate(bad) })
    attempts = 0
    client = AiQuizzes::OllamaClient.new
    client.define_singleton_method(:request) { |_payload| attempts += 1; output }
    error = assert_raises(GameError) { client.generate(draft) }
    assert_equal 2, attempts
    assert_includes error.message, "após duas tentativas"
    attempts = 0
    client.define_singleton_method(:request) { |_payload| attempts += 1; raise GameError, "Sem conexão" }
    assert_raises(GameError) { client.generate(draft) }
    assert_equal 1, attempts
  end
end
