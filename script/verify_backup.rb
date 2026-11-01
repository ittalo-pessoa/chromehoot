# A disposable PostgreSQL round trip, including an Active Storage file.
ENV['RAILS_ENV'] = 'test'
require_relative '../config/environment'
require 'pg'
require 'tmpdir'
require 'fileutils'
require 'digest'
require 'stringio'
abort 'Execute sem DATABASE_URL e apenas em teste.' if ENV['DATABASE_URL'].present? || Rails.env != 'test'
source = "chromehoot_backup_source_#{SecureRandom.hex(4)}"
target = "chromehoot_backup_restore_#{SecureRandom.hex(4)}"
admin = PG.connect(dbname: 'postgres')
created = []
Dir.mktmpdir('chromehoot-backup-', Rails.root.join('tmp')) do |dir|
  begin
    [ source, target ].each do |db|
      admin.exec("CREATE DATABASE #{admin.quote_ident(db)}")
      created << db
    end
    ActiveRecord::Base.establish_connection(adapter: 'postgresql', database: source)
    ActiveRecord::Schema.verbose = false
    load Rails.root.join('db/schema.rb')
    ActiveStorage::Blob.services = ActiveStorage::Service::Registry.new('test' => { service: 'Disk', root: "#{dir}/storage" })
    ActiveStorage::Blob.service = ActiveStorage::Blob.services.fetch(:test)
    user = User.create!(name: 'Restauração', email: 'restore@escola.test', password: SecureRandom.hex(24))
    quiz = user.quizzes.create!(title: 'Backup completo', subject: 'Informática')
    question = quiz.questions.create!(statement: 'O arquivo será recuperado?', position: 1, choices_attributes: [ { text: 'Sim', correct: true, position: 1 }, { text: 'Não', correct: false, position: 2 } ])
    png = Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK3sAAAAASUVORK5CYII=')
    question.image.attach(io: StringIO.new(png), filename: 'recuperacao.png', content_type: 'image/png')
    game = GameSessions::Create.call(quiz)
    participant = ParticipantsJoin.call(code: game.join_code, nickname: 'Teste de recuperação').first
    GameSessions::Start.call(game)
    round = game.current_round
    Rounds::Open.call(game, round_id: round.id)
    Answers::Submit.call(participant, round_id: round.id, choice_id: round.session_question.session_choices.first.id)
    GameSessions::Finish.call(game)
    original_points = participant.answers.sum(:points)
    raise 'pg_dump falhou' unless system('pg_dump', '-Fc', '-d', source, '-f', "#{dir}/database.dump")
    raise 'tar falhou' unless system('tar', '-czf', "#{dir}/storage.tgz", '-C', dir, 'storage')
    FileUtils.rm_rf("#{dir}/storage")
    raise 'pg_restore falhou' unless system('pg_restore', '--no-owner', '-d', target, "#{dir}/database.dump")
    raise 'restauração de arquivos falhou' unless system('tar', '-xzf', "#{dir}/storage.tgz", '-C', dir)
    ActiveRecord::Base.establish_connection(adapter: 'postgresql', database: target)
    restored_game = GameSession.first
    raise 'Dados divergentes' unless User.count == 1 && Quiz.count == 1 && Participant.count == 1 && Answer.count == 1 && Rankings::Build.call(restored_game).first[:points] == original_points
    blob = restored_game.session_questions.first.image.blob
    restored_file = ActiveStorage::Blob.service.download(blob.key)
    raise 'Arquivo divergente' unless Digest::SHA256.hexdigest(restored_file) == Digest::SHA256.hexdigest(png)
    puts "Backup e restauração OK: professor, quiz, snapshot, participante, resposta, pontuação e imagem (SHA-256 conferido). Bancos temporários separados."
  ensure
    ActiveRecord::Base.connection_pool.disconnect!
    created.reverse_each { |db| admin.exec("DROP DATABASE #{admin.quote_ident(db)}") }
    admin.close
  end
end
