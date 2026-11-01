require "minitest/mock"
require "test_helper"
require_relative "../../../script/setup_ai"
require "tmpdir"

class AiDeployEnvironmentTest < ActiveSupport::TestCase
  test "only a matching production process can supply deployment credentials" do
    Dir.mktmpdir do |root|
      app = File.join(root, "app")
      other = File.join(root, "other")
      proc_root = File.join(root, "proc")
      FileUtils.mkdir_p([ app, other, proc_root ])
      [ [ 12345, app, "production" ], [ 12346, other, "production" ], [ 12347, app, "development" ] ].each do |pid, cwd, environment|
        dir = File.join(proc_root, pid.to_s)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "comm"), "ruby")
        File.symlink(cwd, File.join(dir, "cwd"))
        File.write(File.join(dir, "environ"), "RAILS_ENV=#{environment}\0SECRET_KEY_BASE=existing-#{pid}\0UNRELATED=do-not-copy\0")
      end
      found = AiDeployEnvironment.new(app: app, keys: ChromehootAiSetup::ENV_KEYS, proc_root: proc_root).candidates
      assert_equal 1, found.size
      assert_equal({ "SECRET_KEY_BASE" => "existing-12345" }, found.first[:values])
      assert_not_includes found.first[:label], "existing-"
    end
  end

  test "environment files are treated as data and unrelated environment values are ignored" do
    Dir.mktmpdir do |app|
      File.write(File.join(app, ".env.production"), "SECRET_KEY_BASE=existing-key\nOTHER_SECRET=ignored\n")
      File.write(File.join(app, ".env"), "SECRET_KEY_BASE=another-key\n")
      found = AiDeployEnvironment.new(app: app, keys: ChromehootAiSetup::ENV_KEYS, proc_root: File.join(app, "absent")).candidates
      assert_equal 2, found.size
      assert_equal({ "SECRET_KEY_BASE" => "existing-key" }, found.first[:values])
      assert found.last[:confirm]
      File.write(File.join(app, ".env.production"), "export SECRET_KEY_BASE=not-an-environment-file\n")
      assert_equal 1, AiDeployEnvironment.new(app: app, keys: ChromehootAiSetup::ENV_KEYS, proc_root: File.join(app, "absent")).candidates.size
    end
  end

  test "recovery fills missing values without replacing a key already configured and never prints values" do
    setup = ChromehootAiSetup.new([])
    setup.instance_variable_set(:@sudo, [])
    setup.instance_variable_get(:@app_env)["DATABASE_URL"] = "existing-database"
    discovery = Object.new
    discovery.define_singleton_method(:candidates) do
      [ { label: "ChromeHoot em produção (processo 123)", values: { "SECRET_KEY_BASE" => "private-key-not-to-print", "DATABASE_URL" => "runtime-database" } } ]
    end
    AiDeployEnvironment.stub(:new, discovery) do
      output, = capture_io { setup.send(:discover_environment) }
      assert_not_includes output, "private-key-not-to-print"
      assert_not_includes output, "runtime-database"
    end
    assert_equal "private-key-not-to-print", setup.instance_variable_get(:@app_env)["SECRET_KEY_BASE"]
    assert_equal "existing-database", setup.instance_variable_get(:@app_env)["DATABASE_URL"]
  end
  test "development discovery does not use production files or processes" do
    keys = ChromehootAiSetup::ENV_KEYS
    assert_equal({ "DATABASE_URL" => "local-development" }, AiDeployEnvironment.production_values("DATABASE_URL=local-development\0", keys, environment: "development"))
    assert_empty AiDeployEnvironment.production_values("RAILS_ENV=production\0DATABASE_URL=production-db\0", keys, environment: "development")
    Dir.mktmpdir do |app|
      File.write(File.join(app, ".env.production"), "SECRET_KEY_BASE=production-only\n")
      File.write(File.join(app, ".env.development"), "DATABASE_URL=development-only\n")
      found = AiDeployEnvironment.new(app: app, keys: keys, environment: "development", proc_root: File.join(app, "absent")).candidates
      assert_equal 1, found.size
      assert_equal({ "DATABASE_URL" => "development-only" }, found.first[:values])
    end
  end
end
