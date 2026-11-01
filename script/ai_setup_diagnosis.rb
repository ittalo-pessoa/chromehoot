# Classify Rails startup failures without disclosing raw output or credentials.
class AiSetupDiagnosis
  def self.classify(output)
    case output
    when /Missing[^\n]*secret_key_base|secret_key_base[^\n]*(?:missing|not set|blank)|Configure SECRET_KEY_BASE/i
      [ 'CHAVE_AUSENTE', 'O Rails não recebeu a SECRET_KEY_BASE de produção. É necessário reutilizar a chave atual do site; nenhuma chave foi criada ou alterada.' ]
    when /MissingKeyError|Missing encryption key|Missing[^\n]*RAILS_MASTER_KEY/i
      [ 'CHAVE_MESTRA_AUSENTE', 'Falta a chave mestra para ler as credenciais Rails de produção.' ]
    when /ActiveSupport::MessageEncryptor::InvalidMessage|InvalidKeyLength|key must be .* bytes/i
      [ 'CREDENCIAIS_NAO_ABREM', 'O Rails não conseguiu abrir as credenciais criptografadas. A chave mestra pode não corresponder ao arquivo de produção.' ]
    when /password authentication failed|no password supplied|Peer authentication failed|role [^\n]*does not exist/i
      [ 'BANCO_AUTENTICACAO', 'O PostgreSQL recusou a autenticação. Falta a configuração correta de usuário/senha do banco nesse ambiente.' ]
    when /database [^\n]*does not exist/i
      [ 'BANCO_NAO_ENCONTRADO', 'O banco configurado não existe. Confira se a configuração selecionada é a mesma do site em produção.' ]
    when /PG::ConnectionBad|connection to server|could not translate host name/i
      [ 'BANCO_CONEXAO', 'Não foi possível conectar ao PostgreSQL. Confira o serviço do banco e a configuração de conexão do deploy.' ]
    when /Bundler::GemNotFound|Could not find gem|Could not find [^\n]*locally installed gems/i
      [ 'DEPENDENCIAS_RUBY', 'As gems não estão disponíveis nesse Ruby. Execute o instalador com o usuário e Ruby usados pelo deploy, após bundle install.' ]
    when /Your Ruby version[^\n]*Gemfile specified/i
      [ 'RUBY_DIFERENTE', 'O Ruby do terminal é diferente do exigido pela aplicação. Use o mesmo ambiente Ruby do deploy.' ]
    when /Permission denied|Errno::EACCES|read-only file system/i
      [ 'PERMISSAO', 'O usuário atual não consegue acessar um arquivo necessário da aplicação. Use o usuário do deploy e confira permissões.' ]
    else
      [ 'INICIALIZACAO_RAILS', 'A aplicação falhou ao iniciar por outra causa. Envie o código e o resumo seguro exibido abaixo para diagnóstico.' ]
    end
  end

  def self.safe_summary(output, env:, app:)
    code, message = classify(output)
    classes = output.scan(/\b(?:[A-Z]\w*::)*[A-Z]\w*(?:Error|Exception|Violation)\b/).uniq.first(4)
    lines = [ "Diagnóstico: #{code}", message, "Ruby do instalador: #{RUBY_VERSION}" ]
    %w[SECRET_KEY_BASE RAILS_MASTER_KEY DATABASE_URL CHROMEHOOT_DATABASE_PASSWORD].each do |key|
      lines << "#{key}: #{env[key].to_s.empty? ? 'não encontrada' : 'encontrada (valor oculto)'}"
    end
    %w[config/master.key config/credentials/production.key].each do |path|
      lines << "#{path}: #{File.file?(File.join(app, path)) ? 'arquivo encontrado' : 'arquivo não encontrado'}"
    end
    lines << "Classes do erro: #{classes.join(', ')}" unless classes.empty?
    lines << 'Nenhum valor de credencial foi incluído neste resumo.'
    lines.join("\n")
  end
end
