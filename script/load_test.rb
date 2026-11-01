# Run only against the dedicated local test server; creates real HTTP clients.
ENV['RAILS_ENV'] = 'test'
require_relative '../config/environment'
require 'net/http'
require 'json'
require 'benchmark'
abort 'Use o banco chromehoot_test, sem DATABASE_URL, para este teste.' if ENV['DATABASE_URL'].present? || !ActiveRecord::Base.connection_db_config.database.end_with?('_test')
base = URI('http://127.0.0.1:3100')
measurements = Hash.new { |h, k| h[k] = [] }
errors = Queue.new
mutex = Mutex.new
request = lambda do |stage, method, path, cookie = nil, data = nil|
  response = nil
  elapsed = Benchmark.realtime do
    http = Net::HTTP.new(base.host, base.port, nil)
    http.read_timeout = 30
    req = method == :post ? Net::HTTP::Post.new(path) : Net::HTTP::Get.new(path)
    req['Cookie'] = cookie if cookie
    req['Accept'] = 'application/json' if path.include?('state') || path.include?('answer')
    req.set_form_data(data) if data
    response = http.request(req)
  end
  mutex.synchronize { measurements[stage] << elapsed * 1000 }
  raise "HTTP #{response.code}: #{response.body[0, 160]}" unless response.code.to_i.between?(200, 399)
  response
end
parallel = lambda do |items, &job|
  threads = items.map do |item|
    Thread.new do
      begin
        job.call(item)
      rescue StandardError => e
        errors << e.message
      end
    end
  end
  threads.each(&:join)
end
user = User.create!(name: 'Carga local', email: "load-#{SecureRandom.hex(6)}@escola.test", password: SecureRandom.hex(20))
quiz = user.quizzes.create!(title: 'Validação com 50 participantes', subject: 'Informática')
quiz.questions.create!(statement: 'Qual destes é um hardware?', position: 1, time_limit_seconds: 180,
  choices_attributes: [ { text: 'Teclado', correct: true, position: 1 }, { text: 'Navegador', correct: false, position: 2 } ])
game = GameSessions::Create.call(quiz)
clients = Array.new(50) { |i| { nickname: "Aluno #{i + 1}" } }
begin
  parallel.call(clients) do |client|
    response = request.call('join', :post, '/join', nil, { code: game.join_code, nickname: client[:nickname] })
    raise 'Entrada não confirmada' unless response['location']&.end_with?('/play')
    client[:cookie] = response.get_fields('set-cookie').map { |line| line.split(';').first }.join('; ')
  end
  raise 'Participantes não entraram' unless game.participants.count == 50 && errors.empty?
  GameSessions::Start.call(game)
  round = game.current_round
  Rounds::Open.call(game, round_id: round.id)
  choice = round.session_question.session_choices.find_by!(correct: true)
  3.times do
    parallel.call(clients) do |client|
      state = JSON.parse(request.call('poll_open', :get, '/play/state', client[:cookie]).body)
      raise 'Vazamento do gabarito' if state.key?('correct_choice_id') || state.key?('result')
    end
  end
  parallel.call(clients) do |client|
    2.times do
      response = request.call('answer', :post, '/play/answer', client[:cookie], { round_id: round.id, choice_id: choice.id })
      raise 'Confirmação inválida' unless JSON.parse(response.body) == { 'accepted' => true }
    end
  end
  Rounds::Close.call(game, round_id: round.id)
  Rounds::Reveal.call(game, round_id: round.id)
  GameSessions::Finish.call(game)
  parallel.call(clients) do |client|
    state = JSON.parse(request.call('poll_final', :get, '/play/state', client[:cookie]).body)
    raise 'Placar incompleto' unless state['ranking'].size == 50 && state.dig('result', 'correct')
  end
  consistent = round.answers.count == 50 && round.answers.sum(:points) == Rankings::Build.call(game).sum { |row| row[:points] }
  stats = measurements.transform_values do |values|
    sorted = values.sort
    { requests: values.size, median_ms: sorted[values.size / 2].round(2), p95_ms: sorted[(values.size * 0.95).ceil - 1].round(2), max_ms: sorted.last.round(2) }
  end
  result = { measured_at: Time.current.iso8601, rails: Rails.version, ruby: RUBY_VERSION, participants: 50, requests: measurements.values.sum(&:size), errors: errors.size, error_messages: errors.size.times.map { errors.pop }, unique_answers: round.answers.count, consistent: consistent, stages: stats }
  File.write(Rails.root.join('tmp/load-test.json'), JSON.pretty_generate(result))
  puts JSON.pretty_generate(result)
  abort 'Falha na carga' unless result[:errors].zero? && consistent
ensure
  Answer.where(round_id: game.rounds.select(:id)).delete_all
  Round.where(game_session_id: game.id).delete_all
  Participant.where(game_session_id: game.id).delete_all
  SessionChoice.where(session_question_id: game.session_questions.select(:id)).delete_all
  SessionQuestion.where(game_session_id: game.id).delete_all
  game.delete
  Choice.where(question_id: quiz.questions.select(:id)).delete_all
  Question.where(quiz_id: quiz.id).delete_all
  quiz.delete
  user.delete
end
