namespace :ai do
  desc "Processa a fila de quizzes com Groq online (um por vez)"
  task work: :environment do
    stopping = false
    %w[INT TERM].each { |signal| Signal.trap(signal) { stopping = true } }
    puts "ChromeHoot IA: aguardando pedidos. Ctrl+C para encerrar após a geração atual."
    until stopping
      processed = AiQuizzes::ProcessNext.call
      sleep 2 unless processed || stopping
    end
  end
end
