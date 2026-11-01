# Create the local teacher; no public registration and no repository password.
if ENV['TEACHER_EMAIL'].present? && ENV['TEACHER_PASSWORD'].present?
  user = User.find_or_initialize_by(email: ENV.fetch('TEACHER_EMAIL').strip.downcase)
  user.name = ENV.fetch('TEACHER_NAME', 'Professor')
  user.password = ENV.fetch('TEACHER_PASSWORD')
  user.save!
end
if ENV['DEMO_SEED'] == '1'
  abort 'Defina TEACHER_EMAIL e TEACHER_PASSWORD para os dados de demonstração.' unless user
  quiz = user.quizzes.find_or_create_by!(title: 'Introdução à Informática') { |q| q.subject = 'Informática'; q.description = 'Cinco descobertas sobre os computadores e a rede da escola.' }
  data = [
    [ 'Qual item é um componente físico do computador?', [ 'Teclado', 'Editor de texto', 'Navegador' ] ],
    [ 'O que é um software?', [ 'Um conjunto de instruções executadas pelo computador', 'Um cabo de rede', 'Uma peça da placa-mãe' ] ],
    [ 'Qual é a função principal da memória RAM?', [ 'Guardar temporariamente dados dos programas em uso', 'Armazenar arquivos para sempre', 'Conectar a tela à tomada' ] ],
    [ 'O que faz um sistema operacional?', [ 'Gerencia recursos e permite executar programas', 'Substitui a energia elétrica', 'Aumenta o tamanho físico da tela' ] ],
    [ 'O que caracteriza uma rede local?', [ 'Conecta dispositivos em uma área limitada', 'Exige sempre acesso à internet', 'Funciona apenas entre países diferentes' ] ]
  ]
  data.each_with_index do |(statement, texts), i|
    next if quiz.questions.exists?(position: i + 1)
    quiz.questions.create!(statement: statement, position: i + 1, time_limit_seconds: 30,
      choices_attributes: texts.each_with_index.map { |text, j| { text: text, correct: j.zero?, position: j + 1 } })
  end
end
