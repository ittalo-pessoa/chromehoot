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
    written = {}
    setup.define_singleton_method(:write_root) { |path, content, mode| written[path] = [ content, mode ] }
    setup.send(:install_worker)
    content, mode = written.fetch("/etc/systemd/system/chromehoot-ai.service")
    assert_includes content, RbConfig.ruby
    assert_includes content, 'EnvironmentFile="/etc/chromehoot/ai.env"'
    assert_includes content, "TimeoutStopSec=210"
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
end
