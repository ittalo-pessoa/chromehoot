require "test_helper"
require "socket"

class AiQuizzesOllamaClientTest < ActiveSupport::TestCase
  def with_server(status: 200, body:)
    server = TCPServer.new("127.0.0.1", 0)
    original = ENV["OLLAMA_URL"]
    ENV["OLLAMA_URL"] = "http://127.0.0.1:#{server.addr[1]}"
    captured = Queue.new
    thread = Thread.new do
      socket = server.accept
      first = socket.gets
      headers = {}
      while (line = socket.gets) && line != "\r\n"
        key, value = line.split(":", 2)
        headers[key.downcase] = value.strip
      end
      request_body = socket.read(headers.fetch("content-length").to_i)
      captured << [ first, JSON.parse(request_body) ]
      socket.write("HTTP/1.1 #{status} Test\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n")
      socket.write(body)
      socket.close
    end
    yield captured
  ensure
    ENV["OLLAMA_URL"] = original
    server&.close
    thread&.join(2)
    thread&.kill if thread&.alive?
  end

  def draft
    AiQuizDraft.new(topic: "Redes", subject: "Informática", grade_level: "Ensino Médio", difficulty: "easy", question_count: 3)
  end

  def valid_response
    content = { title: "Redes", description: "Atividade", questions: 3.times.map { |i| { statement: "Qual dispositivo #{i}?", choices: %w[Roteador Monitor Mouse Teclado], correct_index: 0 } } }
    JSON.generate(done: true, done_reason: "stop", message: { content: JSON.generate(content) })
  end

  test "sends a real local HTTP request with schema low memory options and unload setting" do
    with_server(body: valid_response) do |captured|
      result = AiQuizzes::OllamaClient.new.generate(draft)
      assert_equal 3, result["questions"].size
      first, payload = captured.pop
      assert_match "POST /api/chat", first
      assert_equal false, payload["stream"]
      assert_equal 0, payload["keep_alive"]
      assert_equal 4096, payload.dig("options", "num_ctx")
      assert_equal 2, payload.dig("options", "num_thread")
      assert_equal 3, payload.dig("format", "properties", "questions", "minItems")
      assert_match "Redes", payload["messages"].last["content"]
    end
  end

  test "missing model malformed output and oversized responses give actionable errors" do
    with_server(status: 404, body: "{}") do
      assert_match "Modelo local não encontrado", assert_raises(GameError) { AiQuizzes::OllamaClient.new.generate(draft) }.message
    end
    with_server(body: '{"done":true,"message":{"content":"invalid"}}') do
      assert_match "formato inválido", assert_raises(GameError) { AiQuizzes::OllamaClient.new.generate(draft) }.message
    end
    with_server(body: "x" * (AiQuizzes::OllamaClient::MAX_BYTES + 1)) do
      assert_match "tamanho permitido", assert_raises(GameError) { AiQuizzes::OllamaClient.new.generate(draft) }.message
    end
  end

  test "remote endpoints are rejected instead of sending teacher data outside the server" do
    original = ENV["OLLAMA_URL"]
    ENV["OLLAMA_URL"] = "https://example.com"
    assert_raises(GameError) { AiQuizzes::OllamaClient.new }
  ensure
    ENV["OLLAMA_URL"] = original
  end
end
