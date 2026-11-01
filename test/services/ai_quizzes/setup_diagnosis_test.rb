require "minitest/mock"
require "test_helper"
require_relative "../../../script/setup_ai"

class AiSetupDiagnosisTest < ActiveSupport::TestCase
  test "identifies the actual cause instead of calling every failure a credential error" do
    {
      "Missing `secret_key_base` for 'production' environment" => "CHAVE_AUSENTE",
      "ActiveSupport::EncryptedFile::MissingKeyError" => "CHAVE_MESTRA_AUSENTE",
      "ActiveSupport::MessageEncryptor::InvalidMessage" => "CREDENCIAIS_NAO_ABREM",
      "PG::ConnectionBad: password authentication failed" => "BANCO_AUTENTICACAO",
      'PG::ConnectionBad: database "app" does not exist' => "BANCO_NAO_ENCONTRADO",
      "PG::ConnectionBad: connection to server failed" => "BANCO_CONEXAO",
      "Bundler::GemNotFound: Could not find gem" => "DEPENDENCIAS_RUBY",
      "Errno::EACCES: Permission denied" => "PERMISSAO",
      "NameError: undefined constant" => "INICIALIZACAO_RAILS"
    }.each do |output, expected|
      assert_equal expected, AiSetupDiagnosis.classify(output).first
    end
  end

  test "summary never copies raw output URLs or secret values" do
    output = "PG::ConnectionBad: password authentication failed password=do-not-print postgresql://private:password@localhost/app"
    summary = AiSetupDiagnosis.safe_summary(output, env: { "SECRET_KEY_BASE" => "secret-not-to-print", "DATABASE_URL" => "postgresql://private:password@localhost/app" }, app: Rails.root.to_s)
    assert_includes summary, "BANCO_AUTENTICACAO"
    assert_includes summary, "SECRET_KEY_BASE: encontrada (valor oculto)"
    assert_not_includes summary, "secret-not-to-print"
    assert_not_includes summary, "postgresql://"
    assert_not_includes summary, "do-not-print"
  end

  test "preflight reports a safe summary without printing the stacktrace or installing anything" do
    setup = ChromehootAiSetup.new([])
    status = Object.new
    status.define_singleton_method(:success?) { false }
    response = [ "", "Missing `secret_key_base` for production: private-should-not-print", status ]
    Open3.stub(:capture3, response) do
      _out, err = capture_io do
        error = assert_raises(RuntimeError) { setup.send(:preflight_application) }
        assert_includes error.message, "antes de instalar"
      end
      assert_includes err, "CHAVE_AUSENTE"
      assert_not_includes err, "private-should-not-print"
    end
  end
end
