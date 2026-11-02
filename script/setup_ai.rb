#!/usr/bin/env ruby
# Run as the same user/Ruby/environment used by the application deploy.
require 'optparse'
require 'open3'
require 'fileutils'
require 'tempfile'
require 'shellwords'
require 'rbconfig'
require 'etc'
require_relative 'ai_deploy_environment'
require_relative "ai_setup_diagnosis"

class ChromehootAiSetup
  ENV_KEYS = %w[DATABASE_URL CHROMEHOOT_DATABASE_PASSWORD SECRET_KEY_BASE RAILS_MASTER_KEY PGHOST PGPORT PGUSER PGPASSWORD PGSSLMODE RAILS_MAX_THREADS GROQ_API_KEY].freeze

  def initialize(args)
    @options = { app: File.expand_path('..', __dir__), dry_run: false, diagnose: true, environment: 'production' }
    parser = OptionParser.new do |p|
      p.banner = 'Uso: ruby script/setup_ai.rb [opções] (Ubuntu com systemd)'
      p.on('--environment NOME', %w[development production], 'Mesmo ambiente do site: development ou production') { |v| @options[:environment] = v }
      p.on('--env-file CAMINHO', 'Arquivo privado KEY=valor usado pelo deploy') { |v| @options[:env_file] = File.expand_path(v) }
      p.on('--app-service NOME', 'Reiniciar também este serviço web, após configurar') { |v| @options[:app_service] = v }
      p.on('--skip-diagnose', 'Não executar uma geração real ao final') { @options[:diagnose] = false }
      p.on('--dry-run', 'Mostrar etapas sem instalar, escrever ou executar comandos') { @options[:dry_run] = true }
      p.on('-h', '--help', 'Mostrar ajuda') { puts p; exit }
    end
    parser.parse!(args)
    raise 'Argumentos inesperados. Use --help.' unless args.empty?
    @ruby = RbConfig.ruby
    @user = Etc.getpwuid(Process.uid).name
    @environment = @options[:environment]
    @worker_service = @environment == 'production' ? 'chromehoot-ai.service' : 'chromehoot-ai-development.service'
    @managed_env = @environment == 'production' ? '/etc/chromehoot/ai.env' : '/etc/chromehoot/ai-development.env'
    @source_env = @options[:env_file] || @managed_env
    @env_path = @managed_env
    @app_env = { 'RAILS_ENV' => @environment }
  end

  # EnvironmentFile format: one literal KEY=value per line, optional shell quotes;
  # no command substitution, expansion, multiline values, or sourcing shell code.
  def self.parse_env(content)
    content.each_line.with_index(1).each_with_object({}) do |(line, number), result|
      line = line.strip
      next if line.empty? || line.start_with?('#')
      match = line.match(/\A([A-Za-z_][A-Za-z0-9_]*)=(.*)\z/)
      raise "Arquivo de ambiente: linha #{number} inválida; use KEY=valor sem export." unless match
      value = match[2]
      if value.start_with?('"', "'")
        parts = Shellwords.split(value)
        raise "Arquivo de ambiente: aspas inválidas na linha #{number}." unless parts.size == 1
        value = parts.first
      end
      raise "Arquivo de ambiente: valor inválido na linha #{number}." if value.include?("\0") || value.include?("\n") || value.include?("\r")
      result[match[1]] = value
    rescue ArgumentError
      raise "Arquivo de ambiente: aspas inválidas na linha #{number}."
    end
  end

  def self.env_file(values)
    values.map do |key, value|
      raise 'Nome de variável inválido.' unless key.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
      raise 'Variável contém quebra de linha ou byte nulo.' if value.match?(/[\n\r\0]/)
      escaped = value.gsub(/([\\"])/) { |char| "\\#{char}" }
      "#{key}=\"#{escaped}\"\n"
    end.join
  end

  def self.unit_quote(value)
    raise 'Caminho inválido para o serviço.' if value.match?(/[\n\r\0]/)
    '"' + value.gsub('%', '%%').gsub(/([\\"])/) { |char| "\\#{char}" } + '"'
  end

  def self.unit_directory(value)
    unless value.start_with?('/') && !value.match?(/[\n\r\0]/) && value == value.strip
      raise 'Diretório inválido para o serviço.'
    end
    # WorkingDirectory consumes one path, not shell words. Wrapping it in
    # quotes makes those quotes part of the path on supported Ubuntu releases.
    value.gsub('%', '%%')
  end

  def run
    raise 'Execute este script em Linux/Ubuntu.' unless RUBY_PLATFORM.include?('linux')
    raise 'Aplicação Rails não encontrada.' unless File.file?(File.join(@options[:app], 'bin/rails'))
    puts "ChromeHoot IA · aplicação: #{@options[:app]} · usuário: #{@user} · Ruby: #{RUBY_VERSION}"
    puts "Ambiente escolhido: #{@environment} · fila: #{@worker_service}"
    puts 'Usa a API Groq com plano gratuito e internet no servidor. Não instala modelos.'
    if @options[:dry_run]
      puts 'SIMULAÇÃO: nenhuma alteração será feita.'
      puts '1. Conferir systemd, sudo, Ruby, dependências e conexão da aplicação ao banco.'
      puts '2. Carregar GROQ_API_KEY ou solicitá-la sem exibir no terminal.'
      puts '3. Conferir os certificados HTTPS do servidor.'
      puts '4. Preservar/carregar variáveis privadas do deploy, migrar e compilar assets.'
      puts "5. Instalar e iniciar #{@worker_service} com o usuário e Ruby atuais."
      puts '6. Executar diagnóstico real.' if @options[:diagnose]
      return
    end
    raise 'systemd não está ativo. No WSL, habilite systemd ou siga docs/IA_LOCAL.md.' unless File.directory?('/run/systemd/system')
    require_command('systemctl')
    require_command('systemd-analyze')
    @sudo = Process.uid.zero? ? [] : [ 'sudo' ]
    command('Autorizar configuração dos serviços', *@sudo, '-v') unless @sudo.empty?
    if @options[:app_service]
      raise 'Nome de serviço inválido.' unless @options[:app_service].match?(/\A[a-zA-Z0-9_.@-]+\z/)
      state = capture('Conferir serviço web', 'systemctl', 'show', @options[:app_service], '--property=LoadState', '--value').strip
      raise 'Serviço web informado não existe.' unless state == 'loaded'
    end
    load_environment
    discover_environment unless @options[:env_file]
    @bundle = capture('Localizar Bundler do Ruby atual', @ruby, '-e', 'require "rubygems"; print Gem.bin_path("bundler", "bundle")').strip
    # Fail before installing OS packages if deployment credentials are unavailable.
    configure_api_key
    preflight_application
    save_environment
    install_dependencies
    # Stop this managed worker before migrating/replacing its unit. Other workers
    # use the same PostgreSQL advisory lock and cannot generate concurrently.
    system(*@sudo, 'systemctl', 'stop', @worker_service, out: File::NULL, err: File::NULL)
    rails('Aplicar migrations', 'db:migrate')
    rails('Compilar assets', 'assets:precompile') if @environment == 'production'
    install_worker
    command('Recarregar serviços', *@sudo, 'systemctl', 'daemon-reload')
    command('Habilitar fila de IA', *@sudo, 'systemctl', 'enable', '--now', @worker_service)
    command('Conferir fila de IA', 'systemctl', 'is-active', '--quiet', @worker_service)
    command('Reiniciar serviço web informado', *@sudo, 'systemctl', 'restart', @options[:app_service]) if @options[:app_service]
    if @options[:diagnose]
      # Stop our worker during the standalone diagnostic so it cannot compete.
      command('Pausar fila para diagnóstico', *@sudo, 'systemctl', 'stop', @worker_service)
      begin
        rails('Medir geração real pela Groq', 'runner', 'script/check_ai.rb')
      ensure
        command('Retomar fila de IA', *@sudo, 'systemctl', 'start', @worker_service)
      end
    end
    puts
    puts 'Instalação concluída. Abra Assistente de IA no painel do professor.'
    puts 'Reinicie o serviço web pelo procedimento habitual do deploy.' unless @options[:app_service]
    puts "Logs: sudo journalctl -u #{@worker_service} -f"
  end

  private

  def load_environment
    exists = File.file?(@source_env) || system(*@sudo, 'test', '-f', @source_env, out: File::NULL, err: File::NULL)
    if exists
      data = if File.readable?(@source_env)
        File.read(@source_env)
      else
        capture('Ler configuração privada existente', *@sudo, 'cat', @source_env)
      end
      values = self.class.parse_env(data)
      if values['RAILS_ENV'] && values['RAILS_ENV'] != @environment
        raise 'O arquivo de configuração pertence a outro ambiente. Escolha o mesmo ambiente do site com --environment.'
      end
      @app_env.merge!(values)
    elsif @options[:env_file]
      raise 'O arquivo --env-file não existe.'
    end
    ENV_KEYS.each { |key| @app_env[key] = ENV[key] if ENV.key?(key) && !@app_env.key?(key) }
    private_api_file = File.join(@options[:app], '.env.ai.local')
    if @app_env['GROQ_API_KEY'].to_s.strip.empty? && File.file?(private_api_file)
      @app_env['GROQ_API_KEY'] = self.class.parse_env(File.read(private_api_file))['GROQ_API_KEY']
    end
    @app_env.delete_if { |key, _| key.start_with?('OLLAMA_') }
    @app_env['GROQ_API_KEY'] = ENV['GROQ_API_KEY'] if ENV['GROQ_API_KEY'].to_s.strip != ''
    @app_env['RAILS_ENV'] = @environment
  end

  def discover_environment
    return if @app_env['SECRET_KEY_BASE'].to_s != '' || @app_env['RAILS_MASTER_KEY'].to_s != ''
    reader = lambda do |path|
      begin
        File.read(path)
      rescue Errno::EACCES
        output, _error, status = Open3.capture3(*@sudo, 'cat', path)
        status.success? ? output : nil
      rescue SystemCallError
        nil
      end
    end
    candidates = AiDeployEnvironment.new(app: @options[:app], keys: ENV_KEYS, reader: reader, environment: @environment).candidates
    return if candidates.empty?
    selected = if candidates.size == 1 && !candidates.first[:confirm]
      candidates.first
    else
      puts "Escolha a configuração de #{@environment}. Nenhum segredo será mostrado:"
      candidates.each_with_index { |candidate, index| puts "  #{index + 1}. #{candidate[:label]}" }
      raise 'Execute no terminal interativo para escolher a configuração.' unless $stdin.tty?
      print 'Digite apenas o número da configuração usada no site: '
      answer = $stdin.gets.to_s.strip
      raise 'Escolha inválida. Execute novamente.' unless answer.match?(/\A[1-9][0-9]*\z/) && answer.to_i <= candidates.size
      candidates[answer.to_i - 1]
    end
    selected[:values].each { |key, value| @app_env[key] = value unless @app_env.key?(key) }
    puts "→ Configuração recuperada: #{selected[:label]} (valores ocultos)."
  end

  def preflight_application
    puts '→ Conferir ambiente e conexão PostgreSQL'
    code = 'ActiveRecord::Base.connection.select_value("SELECT 1"); raise "Configure SECRET_KEY_BASE ou as credenciais de produção" if Rails.application.secret_key_base.blank?'
    output, error, status = Open3.capture3(@app_env, @ruby, File.join(@options[:app], 'bin/rails'), 'runner', code, chdir: @options[:app])
    return if status.success?
    summary = AiSetupDiagnosis.safe_summary(output + "\n" + error, env: @app_env, app: @options[:app])
    warn summary
    raise 'A configuração parou antes de instalar ou alterar o banco. Envie o resumo Diagnóstico acima; ele não contém senhas.'
  end

  def save_environment
    command('Preparar diretório privado', *@sudo, 'install', '-d', '-m', '700', '/etc/chromehoot')
    write_root(@managed_env, self.class.env_file(@app_env), '600')
  end

  def configure_api_key
    if @app_env['GROQ_API_KEY'].to_s.strip.empty?
      raise 'Configure GROQ_API_KEY no ambiente ou no --env-file. Crie uma chave gratuita em https://console.groq.com/keys.' unless $stdin.tty?
      require 'io/console'
      print 'Cole sua GROQ_API_KEY (entrada oculta): '
      @app_env['GROQ_API_KEY'] = $stdin.noecho(&:gets).to_s.strip
      puts
    end
    key = @app_env['GROQ_API_KEY'].to_s.strip
    raise 'GROQ_API_KEY vazia ou inválida.' if key.empty? || key.match?(/[\s\x00-\x1f]/)
    @app_env['GROQ_API_KEY'] = key
  end

  def install_dependencies
    return if File.file?('/etc/ssl/certs/ca-certificates.crt')
    require_command('apt-get')
    command('Atualizar lista de pacotes', *@sudo, 'apt-get', 'update')
    command('Instalar certificados HTTPS', *@sudo, 'apt-get', 'install', '-y', 'ca-certificates')
  end

  def install_worker
    quote = self.class.method(:unit_quote)
    path = ENV.fetch('PATH', '')
    contents = <<~INI
      [Unit]
      Description=ChromeHoot - fila de IA online (Groq)
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=simple
      User=#{@user}
      WorkingDirectory=#{self.class.unit_directory(@options[:app])}
      EnvironmentFile=#{self.class.unit_directory(@env_path)}
      Environment="RAILS_ENV=#{@environment}"
      Environment=#{quote.call("PATH=#{path}")}
      ExecStart=#{quote.call(@ruby)} #{quote.call(@bundle)} exec rake ai:work
      Restart=on-failure
      RestartSec=5
      TimeoutStopSec=150

      [Install]
      WantedBy=multi-user.target
    INI
    verify_worker(contents)
    write_root("/etc/systemd/system/#{@worker_service}", contents, '644')
  end

  def verify_worker(content)
    Tempfile.create([ 'chromehoot-ai-check-', '.service' ]) do |file|
      file.write(content)
      file.flush
      command('Validar unidade com systemd-analyze', 'systemd-analyze', 'verify', '--man=no', file.path)
    end
  end

  def write_root(path, content, mode)
    Tempfile.create('chromehoot-ai-') do |file|
      file.chmod(0o600)
      file.write(content)
      file.flush
      command("Gravar #{path}", *@sudo, 'install', '-m', mode, file.path, path)
    end
  end

  def executable?(name)
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, name)) && !File.directory?(File.join(dir, name)) }
  end

  def require_command(name)
    raise "Comando #{name} não encontrado. Instale-o antes de executar o script." unless executable?(name)
  end

  def command(label, *args)
    puts "→ #{label}"
    raise "Falha: #{label}. A configuração pode estar parcial; corrija o erro e execute novamente." unless system(@app_env, *args, chdir: @options[:app])
  end

  def capture(label, *args)
    # Never print captured data: it can contain private deployment variables.
    output, _error, status = Open3.capture3(@app_env, *args, chdir: @options[:app])
    raise "Falha: #{label}. Confira a configuração e as permissões." unless status.success?
    output
  end

  def rails(label, *args)
    command(label, @ruby, File.join(@options[:app], 'bin/rails'), *args)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    ChromehootAiSetup.new(ARGV).run
  rescue StandardError => error
    warn "Configuração interrompida: #{error.message}"
    exit 1
  end
end
