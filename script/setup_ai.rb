#!/usr/bin/env ruby
# Run as the same user/Ruby/environment used by the application deploy.
require 'optparse'
require 'open3'
require 'fileutils'
require 'tempfile'
require 'shellwords'
require 'rbconfig'
require 'etc'

class ChromehootAiSetup
  ENV_KEYS = %w[DATABASE_URL CHROMEHOOT_DATABASE_PASSWORD SECRET_KEY_BASE RAILS_MASTER_KEY PGHOST PGPORT PGUSER PGPASSWORD PGSSLMODE RAILS_MAX_THREADS].freeze
  OLLAMA_CONFIG = <<~INI.freeze
    [Service]
    Environment="OLLAMA_HOST=127.0.0.1:11434"
    Environment="OLLAMA_NO_CLOUD=1"
    Environment="OLLAMA_NUM_PARALLEL=1"
    Environment="OLLAMA_MAX_LOADED_MODELS=1"
    Environment="OLLAMA_CONTEXT_LENGTH=4096"
    Environment="OLLAMA_KEEP_ALIVE=0"
  INI

  def initialize(args)
    @options = { app: File.expand_path('..', __dir__), dry_run: false, diagnose: true }
    parser = OptionParser.new do |p|
      p.banner = 'Uso: ruby script/setup_ai.rb [opções] (Ubuntu com systemd)'
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
    @managed_env = '/etc/chromehoot/ai.env'
    @source_env = @options[:env_file] || @managed_env
    @env_path = @managed_env
    @app_env = { 'RAILS_ENV' => 'production', 'OLLAMA_URL' => 'http://127.0.0.1:11434', 'OLLAMA_MODEL' => 'qwen2.5:1.5b' }
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

  def run
    raise 'Execute este script em Linux/Ubuntu.' unless RUBY_PLATFORM.include?('linux')
    raise 'Aplicação Rails não encontrada.' unless File.file?(File.join(@options[:app], 'bin/rails'))
    puts "ChromeHoot IA · aplicação: #{@options[:app]} · usuário: #{@user} · Ruby: #{RUBY_VERSION}"
    puts 'Requer internet para instalar e baixar o modelo. Não publica a porta do Ollama.'
    if @options[:dry_run]
      puts 'SIMULAÇÃO: nenhuma alteração será feita.'
      puts '1. Conferir systemd, sudo, Ruby, dependências e conexão da aplicação ao banco.'
      puts '2. Instalar Ollama oficial se ausente e configurar serviço local sem nuvem.'
      puts '3. Baixar qwen2.5:1.5b apenas se ainda não estiver instalado.'
      puts '4. Preservar/carregar variáveis privadas do deploy, migrar e compilar assets.'
      puts '5. Instalar e iniciar chromehoot-ai.service com o usuário e Ruby atuais.'
      puts '6. Executar diagnóstico real.' if @options[:diagnose]
      return
    end
    raise 'systemd não está ativo. No WSL, habilite systemd ou siga docs/IA_LOCAL.md.' unless File.directory?('/run/systemd/system')
    require_command('curl')
    require_command('systemctl')
    @sudo = Process.uid.zero? ? [] : [ 'sudo' ]
    command('Autorizar configuração dos serviços', *@sudo, '-v') unless @sudo.empty?
    if @options[:app_service]
      raise 'Nome de serviço inválido.' unless @options[:app_service].match?(/\A[a-zA-Z0-9_.@-]+\z/)
      state = capture('Conferir serviço web', 'systemctl', 'show', @options[:app_service], '--property=LoadState', '--value').strip
      raise 'Serviço web informado não existe.' unless state == 'loaded'
    end
    load_environment
    @bundle = capture('Localizar Bundler do Ruby atual', @ruby, '-e', 'require "rubygems"; print Gem.bin_path("bundler", "bundle")').strip
    # Fail before installing OS packages if deployment credentials are unavailable.
    rails('Conferir ambiente e conexão PostgreSQL', 'runner', 'ActiveRecord::Base.connection.select_value("SELECT 1"); raise "Configure SECRET_KEY_BASE ou as credenciais de produção" if Rails.application.secret_key_base.blank?; puts "Ambiente de produção e banco OK"')
    save_environment
    install_dependencies
    install_ollama
    configure_ollama
    tags = capture('Conferir modelos locais', 'curl', '--fail', '--silent', '--show-error', '--max-time', '10', 'http://127.0.0.1:11434/api/tags')
    require 'json'
    models = JSON.parse(tags).fetch('models', []).map { |item| item['name'] }
    command('Baixar modelo local (pode demorar)', 'env', 'OLLAMA_HOST=127.0.0.1:11434', 'ollama', 'pull', 'qwen2.5:1.5b') unless models.include?('qwen2.5:1.5b')
    # Stop this managed worker before migrating/replacing its unit. Other workers
    # use the same PostgreSQL advisory lock and cannot generate concurrently.
    system(*@sudo, 'systemctl', 'stop', 'chromehoot-ai.service', out: File::NULL, err: File::NULL)
    rails('Aplicar migrations', 'db:migrate')
    rails('Compilar assets', 'assets:precompile')
    install_worker
    command('Recarregar serviços', *@sudo, 'systemctl', 'daemon-reload')
    command('Habilitar fila de IA', *@sudo, 'systemctl', 'enable', '--now', 'chromehoot-ai.service')
    command('Conferir fila de IA', 'systemctl', 'is-active', '--quiet', 'chromehoot-ai.service')
    command('Reiniciar serviço web informado', *@sudo, 'systemctl', 'restart', @options[:app_service]) if @options[:app_service]
    if @options[:diagnose]
      # Stop our worker during the standalone diagnostic so it cannot compete.
      command('Pausar fila para diagnóstico', *@sudo, 'systemctl', 'stop', 'chromehoot-ai.service')
      begin
        rails('Medir geração real com o modelo local', 'runner', 'script/check_ai.rb')
      ensure
        command('Retomar fila de IA', *@sudo, 'systemctl', 'start', 'chromehoot-ai.service')
      end
    end
    puts
    puts 'Instalação concluída. Abra Assistente de IA no painel do professor.'
    puts 'Reinicie o serviço web pelo procedimento habitual do deploy.' unless @options[:app_service]
    puts 'Logs: sudo journalctl -u chromehoot-ai -f'
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
      @app_env.merge!(self.class.parse_env(data))
    elsif @options[:env_file]
      raise 'O arquivo --env-file não existe.'
    end
    ENV_KEYS.each { |key| @app_env[key] = ENV[key] if ENV.key?(key) && !@app_env.key?(key) }
    @app_env.merge!('RAILS_ENV' => 'production', 'OLLAMA_URL' => 'http://127.0.0.1:11434', 'OLLAMA_MODEL' => 'qwen2.5:1.5b')
  end

  def save_environment
    command('Preparar diretório privado', *@sudo, 'install', '-d', '-m', '700', '/etc/chromehoot')
    write_root(@managed_env, self.class.env_file(@app_env), '600')
  end

  def install_dependencies
    return if executable?("curl") && executable?("zstd") && File.file?("/etc/ssl/certs/ca-certificates.crt")
    require_command("apt-get")
    command("Atualizar lista de pacotes", *@sudo, "apt-get", "update")
    command("Instalar ferramentas de download e extração", *@sudo, "apt-get", "install", "-y", "curl", "ca-certificates", "zstd")
  end

  def install_ollama
    return if executable?('ollama')
    require_command('sh')
    Tempfile.create([ 'chromehoot-ollama-install-', '.sh' ]) do |file|
      command('Baixar instalador oficial do Ollama', 'curl', '--fail', '--silent', '--show-error', '--location', '--proto', '=https', '--tlsv1.2', 'https://ollama.com/install.sh', '-o', file.path)
      command('Instalar Ollama no sistema', *@sudo, 'sh', file.path)
    end
    require_command('ollama')
  end

  def configure_ollama
    command('Preparar configuração do Ollama', *@sudo, 'install', '-d', '-m', '755', '/etc/systemd/system/ollama.service.d')
    write_root('/etc/systemd/system/ollama.service.d/chromehoot.conf', OLLAMA_CONFIG, '644')
    command('Recarregar configuração do Ollama', *@sudo, 'systemctl', 'daemon-reload')
    command('Habilitar Ollama', *@sudo, 'systemctl', 'enable', 'ollama')
    command('Iniciar Ollama com configuração local', *@sudo, 'systemctl', 'restart', 'ollama')
    30.times do
      return if system('curl', '--fail', '--silent', '--max-time', '2', 'http://127.0.0.1:11434/api/tags', out: File::NULL, err: File::NULL)
      sleep 1
    end
    raise 'Ollama não iniciou. Confira: sudo journalctl -u ollama -n 50'
  end

  def install_worker
    quote = self.class.method(:unit_quote)
    path = ENV.fetch('PATH', '')
    contents = <<~INI
      [Unit]
      Description=ChromeHoot - fila de IA local
      After=network.target ollama.service

      [Service]
      Type=simple
      User=#{@user}
      WorkingDirectory=#{quote.call(@options[:app])}
      EnvironmentFile=#{quote.call(@env_path)}
      Environment="RAILS_ENV=production"
      Environment="OLLAMA_URL=http://127.0.0.1:11434"
      Environment="OLLAMA_MODEL=qwen2.5:1.5b"
      Environment=#{quote.call("PATH=#{path}")}
      ExecStart=#{quote.call(@ruby)} #{quote.call(@bundle)} exec rake ai:work
      Restart=on-failure
      RestartSec=5
      TimeoutStopSec=210

      [Install]
      WantedBy=multi-user.target
    INI
    write_root('/etc/systemd/system/chromehoot-ai.service', contents, '644')
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
