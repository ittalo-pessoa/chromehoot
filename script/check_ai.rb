# Executes a real local-model request without saving a quiz or draft.
require 'json'
draft = AiQuizDraft.new(topic: 'Componentes físicos de um computador e suas funções', subject: 'Informática', grade_level: '1º ano do Ensino Médio', difficulty: 'easy', question_count: 3)
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
begin
  content = AiQuizzes::OllamaClient.new.generate(draft)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  result = { measured_at: Time.current.iso8601, model: ENV.fetch('OLLAMA_MODEL', 'qwen2.5:1.5b'), elapsed_seconds: elapsed.round(2), valid_questions: content['questions'].size, content: content }
  File.write(Rails.root.join('tmp/ai-smoke-test.json'), JSON.pretty_generate(result))
  puts "IA local respondeu em #{elapsed.round(2)}s, com #{content['questions'].size} questões estruturalmente válidas."
  puts 'Confira o conteúdo e o gabarito em tmp/ai-smoke-test.json. Este diagnóstico não salva quizzes.'
rescue GameError => error
  warn error.message
  exit 1
end
