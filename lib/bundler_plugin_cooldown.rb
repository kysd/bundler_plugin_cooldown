require "net/http"
require "json"
require "time"
require "date"

module BundlerPluginCooldown
  DEFAULT_COOLDOWN_DAYS = 2

  # rubygems.org rate limit: 10 req/s
  # https://guides.rubygems.org/rubygems-org-rate-limits/
  REQUEST_DELAY = 0.15

  def self.cooldown_days
    raw = Bundler.settings["bundler_plugin_cooldown.days"]
    raw ? Integer(raw) : DEFAULT_COOLDOWN_DAYS
  end

  def self.check!(specs)
    targets = specs.select do |s|
      s.source.is_a?(Bundler::Source::Rubygems) &&
        s.name != "bundler"
    end
    return if targets.empty?

    days = cooldown_days
    today = Date.today
    violators = []

    targets.each do |spec|
      sleep(REQUEST_DELAY)
      Bundler.ui.info "[bundler-cooldown] checking #{spec.name} #{spec.version}..."
      created_at = fetch_created_at(spec)
      next unless created_at

      released_on = created_at.to_date
      violators << [spec, created_at] if today < released_on + days
    end

    return if violators.empty?

    lines = violators.map do |spec, created_at|
      age = ((Time.now - created_at) / 86400.0).round(1)
      "  - #{spec.name} #{spec.version} (published #{created_at.utc.strftime('%Y-%m-%d')}, #{age}d ago)"
    end
    raise Bundler::InstallError, <<~MSG
      [bundler-cooldown] Refusing to install #{violators.size} gem(s) within #{days}-day cooldown:
      #{lines.join("\n")}
    MSG
  end

  def self.fetch_created_at(spec)
    uri = URI("https://rubygems.org/api/v1/versions/#{spec.name}.json")
    res = Net::HTTP.get_response(uri)
    return nil unless res.is_a?(Net::HTTPSuccess)
    versions = JSON.parse(res.body)
    match = versions.find do |v|
      v["number"] == spec.version.to_s && v["platform"] == spec.platform.to_s
    end
    match && Time.parse(match["created_at"])
  rescue StandardError => e
    Bundler.ui.warn "[bundler-cooldown] #{spec.name}: #{e.message}"
    nil
  end
end

Bundler::Plugin.add_hook("before-install-all") do |_deps|
  puts "BundlerPluginCooldown >>>"
  BundlerPluginCooldown.check!(Bundler.definition.resolve)
end
