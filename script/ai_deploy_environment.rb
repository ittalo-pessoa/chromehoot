# Discover only this application's production environment; never print values.
require 'open3'

class AiDeployEnvironment
  def initialize(app:, keys:, reader: nil, proc_root: '/proc')
    @app = File.realpath(app)
    @keys = keys
    @proc_root = proc_root
    @allowed_uids = [ Process.uid, File.stat(@app).uid ]
    @reader = reader || ->(path) { File.read(path) }
  end

  def candidates
    (process_candidates + file_candidates).uniq { |candidate| candidate[:values] }
  end

  def process_candidates
    Dir.glob(File.join(@proc_root, '[0-9]*', 'comm')).filter_map do |path|
      pid = File.basename(File.dirname(path)).to_i
      next unless @allowed_uids.include?(File.stat(path).uid)
      next if pid == Process.pid
      comm = read(path)
      next unless comm&.match?(/ruby|puma|passenger/i)
      cwd = begin
        File.realpath(File.join(@proc_root, pid.to_s, 'cwd'))
      rescue SystemCallError
        nil
      end
      next unless cwd == @app
      values = self.class.production_values(read(File.join(@proc_root, pid.to_s, 'environ')), @keys)
      next if values.empty?
      { label: "ChromeHoot em produção (processo #{pid})", values: values }
    rescue SystemCallError
      # Processes may exit while /proc is being inspected.
      next
    end
  end

  def file_candidates
    %w[.env.production.local .env.production .env shared/.env.production shared/.env config/.env.production].filter_map do |name|
      path = File.join(@app, name)
      content = read(path)
      next unless content && content.bytesize <= 65_536
      begin
        parsed = ChromehootAiSetup.parse_env(content)
        next if parsed['RAILS_ENV'] && parsed['RAILS_ENV'] != 'production'
        values = parsed.select { |key, value| @keys.include?(key) && !value.empty? }
        next if values.empty?
        uncertain = File.basename(name) == '.env' && parsed['RAILS_ENV'] != 'production'
        { label: "Arquivo #{name} da aplicação#{uncertain ? ' (confirme que é de produção)' : ''}", values: values, confirm: uncertain }
      rescue RuntimeError
        # A shell script is not an EnvironmentFile. Never execute it.
        next
      end
    end
  end

  def self.production_values(raw, keys)
    return {} unless raw
    values = raw.split("\0").filter_map do |entry|
      key, value = entry.split('=', 2)
      [ key, value ] if value
    end.to_h
    return {} unless values['RAILS_ENV'] == 'production' || values['RACK_ENV'] == 'production'
    values.select { |key, value| keys.include?(key) && !value.empty? }
  end

  private

  def read(path)
    @reader.call(path)
  rescue SystemCallError
    nil
  end
end
