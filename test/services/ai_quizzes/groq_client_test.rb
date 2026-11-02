require "test_helper"
require "minitest/mock"

class AiQuizzesGroqClientTest < ActiveSupport::TestCase
  setup do
    @original_key = ENV["GROQ_API_KEY"]
    ENV["GROQ_API_KEY"] = "private-test-key"
  end

  teardown do
    ENV["GROQ_API_KEY"] = @original_key
  end

  def draft(count: 10, difficulty: "easy")
    AiQuizDraft.new(topic: "Hardware", subject: "Informática", grade_level: "Ensino Médio", difficulty: difficulty, question_count: count)
  end

  def content(count, offset: 0)
    { "title" => "Hardware", "description" => "Atividade", "questions" => count.times.map { |i|
      { "statement" => "Pergunta #{offset + i}", "choices" => %w[Teclado Monitor Mouse Cabo], "correct_index" => 2 }
    } }
  end

  def response(data, finish: "stop")
    JSON.generate(choices: [ { finish_reason: finish, message: { content: JSON.generate(data) } } ])
  end

  def client_with_outputs(outputs, calls)
    client = AiQuizzes::GroqClient.new
    client.define_singleton_method(:request) do |payload, deadline:|
      calls << [ payload, deadline ]
      outputs.shift || raise("Unexpected API request")
    end
    client
  end

  test "all difficulties generate twenty questions in one structured request" do
    %w[easy medium hard].each do |difficulty|
      calls = []
      result = client_with_outputs([ response(content(20)) ], calls).generate(draft(count: 20, difficulty: difficulty))
      assert_equal 20, result["questions"].size
      assert_equal 1, calls.size
      payload = calls.first.first
      assert_equal "openai/gpt-oss-20b", payload[:model]
      assert_equal true, payload.dig(:response_format, :json_schema, :strict)
      assert_equal 20, JSON.parse(payload[:messages][1][:content])["quantidade"]
      assert_not_includes JSON.generate(payload), "private-test-key"
      assert_equal 2, result["questions"].first["correct_index"]
    end
  end

  test "preserves valid questions and requests only replacements for duplicates and invalid alternatives" do
    original = content(10)
    original["questions"][8]["statement"] = original["questions"][0]["statement"].upcase
    original["questions"][9]["choices"][1] = "Teclado"
    calls = []
    client = client_with_outputs([ response(original), response(content(2, offset: 10)) ], calls)
    result = client.generate(draft)
    assert_equal 10, result["questions"].size
    assert_equal original["questions"].first(8).map { |q| q["statement"] }, result["questions"].first(8).map { |q| q["statement"] }
    retry_data = JSON.parse(calls.last.first[:messages][1][:content])
    assert_equal 2, retry_data["quantidade"]
    assert_equal 8, retry_data["enunciados_ja_aceitos"].size
    assert_equal calls.first.last, calls.last.last
  end

  test "repeated invalid responses stop after one correction" do
    bad = content(3)
    bad["questions"].each { |q| q["choices"] = %w[A A A A] }
    calls = []
    error = assert_raises(GameError) do
      client_with_outputs([ response(bad), response(bad) ], calls).generate(draft(count: 3))
    end
    assert_equal 2, calls.size
    assert_includes error.message, "após uma tentativa de correção"
  end

  test "malformed incomplete and refused responses fail clearly" do
    [ "invalid", response(content(3), finish: "length"), JSON.generate(choices: [ { message: { refusal: "blocked" } } ]), JSON.generate(choices: []) ].each do |output|
      calls = []
      assert_raises(GameError) { client_with_outputs([ output ], calls).generate(draft(count: 3)) }
      assert_equal 1, calls.size
    end
  end

  test "missing key and invalid quantities do not call the API" do
    ENV.delete("GROQ_API_KEY")
    assert_includes assert_raises(GameError) { AiQuizzes::GroqClient.new }.message, "GROQ_API_KEY"
    ENV["GROQ_API_KEY"] = "private-test-key"
    calls = []
    assert_raises(GameError) { client_with_outputs([], calls).generate(draft(count: 21)) }
    assert_empty calls
  end

  def with_http(code:, body:)
    captured = []
    http = Object.new
    http.define_singleton_method(:use_ssl=) { |value| captured << value }
    %i[open_timeout= read_timeout= write_timeout=].each { |name| http.define_singleton_method(name) { |_value| } }
    reply = Object.new
    reply.define_singleton_method(:code) { code.to_s }
    reply.define_singleton_method(:read_body) { |&block| block.call(body) }
    http.define_singleton_method(:request) { |req, &block| captured << req; block.call(reply) }
    factory = lambda do |host, port, proxy|
      assert_equal "api.groq.com", host
      assert_equal 443, port
      assert_nil proxy
      http
    end
    Net::HTTP.stub(:new, factory) { yield captured }
  end

  test "HTTPS transport sends authorization header to fixed endpoint without exposing the key in the body" do
    with_http(code: 200, body: response(content(3))) do |captured|
      result = AiQuizzes::GroqClient.new.generate(draft(count: 3))
      assert_equal 3, result["questions"].size
      assert_equal true, captured.first
      req = captured.last
      assert_equal "/openai/v1/chat/completions", req.path
      assert_equal "Bearer private-test-key", req["Authorization"]
      assert_not_includes req.body, "private-test-key"
    end
  end

  test "HTTP errors are actionable and never expose provider response bodies" do
    { 401 => "chave", 403 => "chave", 429 => "limite gratuito", 400 => "configuração", 404 => "configuração", 503 => "indisponível", 302 => "indisponível" }.each do |code, expected|
      with_http(code: code, body: "private-test-key provider details") do |captured|
        error = assert_raises(GameError) { AiQuizzes::GroqClient.new.generate(draft(count: 3)) }
        assert_includes error.message, expected
        assert_not_includes error.message, "private-test-key"
        assert_equal 2, captured.size
      end
    end
  end

  test "oversized output and connection failures are bounded" do
    with_http(code: 200, body: "x" * (AiQuizzes::GroqClient::MAX_BYTES + 1)) do
      assert_includes assert_raises(GameError) { AiQuizzes::GroqClient.new.generate(draft(count: 3)) }.message, "tamanho permitido"
    end
    Net::HTTP.stub(:new, ->(*) { raise SocketError }) do
      assert_includes assert_raises(GameError) { AiQuizzes::GroqClient.new.generate(draft(count: 3)) }.message, "internet"
    end
    Net::HTTP.stub(:new, ->(*) { raise Timeout::Error }) do
      assert_includes assert_raises(GameError) { AiQuizzes::GroqClient.new.generate(draft(count: 3)) }.message, "dois minutos"
    end
  end
end
