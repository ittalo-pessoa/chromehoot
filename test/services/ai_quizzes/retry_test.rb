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

  test "ten questions retry only the batch repeating a previous full statement" do
    first = data
    first["questions"] = 5.times.map { |i| data["questions"].first.merge("statement" => "#{'Enunciado longo ' * 15}#{i}") }
    second = data.merge("questions" => 5.times.map { |i| data["questions"].first.merge("statement" => "Nova pergunta #{i}") })
    repeated = second.deep_dup
    repeated["questions"][0]["statement"] = first["questions"][0]["statement"].upcase
    replacement = second.merge("questions" => [ second["questions"].first ])
    outputs = [ first, repeated, replacement ].map { |content| JSON.generate(done: true, message: { content: JSON.generate(content) }) }
    calls = []
    client = AiQuizzes::OllamaClient.new
    client.define_singleton_method(:request) { |payload| calls << payload; outputs.shift }
    request = draft
    request.question_count = 10

    result = client.generate(request)

    assert_equal 3, calls.size
    assert_equal first["questions"].map { |q| q["statement"] }, result["questions"].first(5).map { |q| q["statement"] }
    assert_equal 10, result["questions"].map { |q| q["statement"].downcase }.uniq.size
    assert_includes calls.last[:messages].last[:content], "repete enunciados"
    assert_equal 1, calls.last[:format][:properties][:questions][:minItems]
    assert_equal 1, JSON.parse(calls.last[:messages][1][:content])["quantidade"]
    assert_equal (first["questions"] + second["questions"].drop(1)).map { |q| q["statement"] }, JSON.parse(calls.last[:messages][1][:content])["evite_repetir_estes_enunciados"]
  end

  test "repeated statements across batches stop after two attempts on the failing batch" do
    content = data.merge("questions" => 5.times.map { |i| data["questions"].first.merge("statement" => "Pergunta #{i}") })
    calls = 0
    client = AiQuizzes::OllamaClient.new
    client.define_singleton_method(:request) do |_payload|
      calls += 1
      JSON.generate(done: true, message: { content: JSON.generate(content) })
    end
    request = draft
    request.question_count = 10

    error = assert_raises(GameError) { client.generate(request) }

    assert_equal 3, calls
    assert_includes error.message, "após duas tentativas"
    assert_includes error.message, "repete enunciados"
  end
end
