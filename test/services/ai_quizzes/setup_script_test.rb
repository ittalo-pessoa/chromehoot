require "test_helper"
require_relative "../../../script/setup_ai"

class AiSetupScriptTest < ActiveSupport::TestCase
  test "private configuration is parsed as data and never executed" do
    parsed = ChromehootAiSetup.parse_env(<<~ENV)
      # deploy configuration
      SECRET_KEY_BASE="a value with spaces"
      DATABASE_URL='postgresql://user:password@localhost/database'
      MALICIOUS=$(touch /tmp/never-execute-ai-setup)
      EMPTY=
    ENV
    assert_equal "a value with spaces", parsed["SECRET_KEY_BASE"]
    assert_equal "postgresql://user:password@localhost/database", parsed["DATABASE_URL"]
    assert_equal "$(touch /tmp/never-execute-ai-setup)", parsed["MALICIOUS"]
    assert_equal "", parsed["EMPTY"]
    assert_raises(RuntimeError) { ChromehootAiSetup.parse_env("export SECRET=value") }
    assert_raises(RuntimeError) { ChromehootAiSetup.parse_env('VALUE="broken') }
  end

  test "private environment round trips special characters without exposing or expanding them" do
    values = { "SECRET_KEY_BASE" => 'spaces " quotes \\ $dollar %percent', "EMPTY" => "" }
    assert_equal values, ChromehootAiSetup.parse_env(ChromehootAiSetup.env_file(values))
    assert_raises(RuntimeError) { ChromehootAiSetup.env_file("SECRET" => "a\nb") }
    assert_raises(RuntimeError) { ChromehootAiSetup.unit_quote("a\nUser=root") }
    assert_equal '"/srv/a b/100%%"', ChromehootAiSetup.unit_quote("/srv/a b/100%")
  end

  test "worker uses the deploy ruby and protected normalized environment file" do
    setup = ChromehootAiSetup.new([])
    setup.instance_variable_set(:@bundle, "/usr/local/bin/bundle")
    setup.define_singleton_method(:verify_worker) { |_content| }
    written = {}
    setup.define_singleton_method(:write_root) { |path, content, mode| written[path] = [ content, mode ] }
    setup.send(:install_worker)
    content, mode = written.fetch("/etc/systemd/system/chromehoot-ai.service")
    assert_includes content, RbConfig.ruby
    assert_includes content, "EnvironmentFile=/etc/chromehoot/ai.env"
    assert_includes content, "TimeoutStopSec=780"
    assert_includes content, "exec rake ai:work"
    assert_equal "644", mode
    assert_not_includes content, "SECRET_KEY_BASE="
  end

  test "dry run never executes commands or writes files" do
    setup = ChromehootAiSetup.new([ "--dry-run" ])
    setup.define_singleton_method(:command) { |*| raise "Unexpected command" }
    setup.define_singleton_method(:capture) { |*| raise "Unexpected capture" }
    setup.define_singleton_method(:write_root) { |*| raise "Unexpected write" }
    output, = capture_io { setup.run }
    assert_includes output, "SIMULAÇÃO"
    assert_includes output, "chromehoot-ai.service"
  end
  test "development setup uses its own service and credentials file" do
    setup = ChromehootAiSetup.new([ "--environment", "development" ])
    setup.instance_variable_set(:@bundle, "/usr/local/bin/bundle")
    setup.define_singleton_method(:verify_worker) { |_content| }
    written = {}
    setup.define_singleton_method(:write_root) { |path, content, mode| written[path] = [ content, mode ] }
    setup.send(:install_worker)
    content, = written.fetch("/etc/systemd/system/chromehoot-ai-development.service")
    assert_includes content, 'Environment="RAILS_ENV=development"'
    assert_includes content, "EnvironmentFile=/etc/chromehoot/ai-development.env"
    assert_equal "development", setup.instance_variable_get(:@app_env)["RAILS_ENV"]
    assert_not written.key?("/etc/systemd/system/chromehoot-ai.service")
  end
  test "generated worker passes the real systemd parser without quoted WorkingDirectory" do
    analyzer = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, "systemd-analyze") }.find { |path| File.executable?(path) }
    skip "systemd-analyze indisponível neste ambiente" unless analyzer
    setup = ChromehootAiSetup.new([ "--environment", "development" ])
    setup.instance_variable_set(:@bundle, "/usr/local/bin/bundle")
    setup.define_singleton_method(:verify_worker) { |_content| }
    generated = nil
    setup.define_singleton_method(:write_root) { |_path, content, _mode| generated = content }
    setup.send(:install_worker)
    assert_includes generated, "WorkingDirectory=#{Rails.root}"
    assert_not_includes generated, 'WorkingDirectory="'
    Tempfile.create([ "chromehoot-ai-regression-", ".service" ]) do |file|
      file.write(generated)
      file.flush
      _out, err, status = Open3.capture3(analyzer, "verify", "--man=no", file.path)
      assert status.success?, err
      assert_not_includes err, "path is not absolute"
    end
    assert_equal "/srv/a b/100%%", ChromehootAiSetup.unit_directory("/srv/a b/100%")
    assert_raises(RuntimeError) { ChromehootAiSetup.unit_directory("/srv/app\nUser=root") }
  end
end
