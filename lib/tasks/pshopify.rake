# frozen_string_literal: true

require "json"
require "open3"

namespace :pshopify do
  desc "Create a new pshopify definition. Usage: rake \"pshopify:create[4.0.2]\" (defaults to latest stable)"
  task :create, [:base_version] do |_t, args|
    creator = PshopifyDefinitionCreator.new(args[:base_version])
    creator.run
  end
end

class PshopifyDefinitionCreator
  SHOPIFY_RUBY_REPO = "Shopify/ruby"
  SHOPIFY_RUBY_GIT_URL = "https://github.com/#{SHOPIFY_RUBY_REPO}.git"
  RUBIES_DIR = File.expand_path("../../rubies", __dir__)

  def initialize(base_version = nil)
    @base_version = base_version
  end

  def run
    @ruby_build_defs_dir = find_ruby_build_defs_dir
    @base_version ||= detect_latest_stable
    @pshopify_num = next_pshopify_number
    @pshopify_version = "#{@base_version}-pshopify#{@pshopify_num}"
    @tag = "v#{@pshopify_version}"

    puts "Creating definition for #{@pshopify_version}..."

    verify_branch_exists
    openssl_line = read_upstream_openssl_line
    compare_base = determine_compare_base
    verify_previous_pshopify_included if @pshopify_num > 1
    commits = fetch_changelog(compare_base)

    content = generate_definition(compare_base, commits, openssl_line)
    output_path = File.join(RUBIES_DIR, @pshopify_version)
    File.write(output_path, content)

    puts "Created #{output_path}"
  end

  private

  def next_pshopify_number
    existing = Dir.children(RUBIES_DIR)
      .filter_map { |f| f[/\A#{Regexp.escape(@base_version)}-pshopify(\d+)\z/, 1]&.to_i }

    (existing.max || 0) + 1
  end

  def verify_branch_exists
    gh_api("repos/#{SHOPIFY_RUBY_REPO}/branches/#{@tag}")
    puts "  Branch #{@tag} exists"
  rescue GhApiError => e
    abort("Error: branch #{@tag} does not exist on #{SHOPIFY_RUBY_REPO}\n#{e.message}")
  end

  def read_upstream_openssl_line
    definition_path = File.join(@ruby_build_defs_dir, @base_version)

    unless File.exist?(definition_path)
      abort("Error: upstream definition for #{@base_version} not found in #{@ruby_build_defs_dir}")
    end

    line = File.readlines(definition_path).find { |l| l.include?("openssl") }
    abort("Error: no openssl line found in #{definition_path}") unless line

    line.chomp
  end

  def find_ruby_build_defs_dir
    candidates = if ENV["RUBY_BUILD_PATH"]
      [ENV["RUBY_BUILD_PATH"]]
    else
      parent = File.dirname(RUBIES_DIR, 2)
      Dir.glob(File.join(parent, "*ruby-build"))
    end

    candidates.each do |dir|
      defs_dir = File.join(dir, "share", "ruby-build")
      return defs_dir if Dir.exist?(defs_dir)
    end

    abort("Error: ruby-build definitions not found.\n" \
      "Set RUBY_BUILD_PATH to your ruby-build checkout.")
  end

  def detect_latest_stable
    versions = Dir.children(@ruby_build_defs_dir)
      .filter_map { |f| f if f.match?(/\A\d+\.\d+\.\d+\z/) }
      .sort_by { |v| Gem::Version.new(v) }

    abort("Error: no stable Ruby versions found in #{@ruby_build_defs_dir}") if versions.empty?

    latest = versions.last
    puts "No version specified, using latest stable: #{latest}"
    latest
  end

  def determine_compare_base
    if @pshopify_num == 1
      resolve_upstream_tag
    else
      "v#{@base_version}-pshopify#{@pshopify_num - 1}"
    end
  end

  # Upstream tags may use dots (v4.0.2) or underscores (v3_4_8).
  def resolve_upstream_tag
    tag_with_dots = "v#{@base_version}"
    tag_with_underscores = "v#{@base_version.tr(".", "_")}"

    [tag_with_dots, tag_with_underscores].each do |tag|
      gh_api("repos/#{SHOPIFY_RUBY_REPO}/git/ref/tags/#{tag}")
      return tag
    rescue GhApiError
      next
    end

    # Fall back to the dotted form for the compare URL even if we can't confirm it
    warn("Warning: could not confirm upstream tag format, using #{tag_with_dots}")
    tag_with_dots
  end

  def verify_previous_pshopify_included
    prev_tag = "v#{@base_version}-pshopify#{@pshopify_num - 1}"
    data = gh_api("repos/#{SHOPIFY_RUBY_REPO}/compare/#{prev_tag}...#{@tag}")

    status = data["status"]
    if status == "behind" || status == "diverged"
      warn("WARNING: #{@tag} is #{status} relative to #{prev_tag}.")
      warn("  The new branch may be missing commits from the previous pshopify.")
      warn("  Ahead: #{data["ahead_by"]}, Behind: #{data["behind_by"]}")
    else
      puts "  #{@tag} includes all commits from #{prev_tag}"
    end
  rescue GhApiError => e
    warn("Warning: could not compare with previous pshopify: #{e.message}")
  end

  def fetch_changelog(compare_base)
    data = gh_api("repos/#{SHOPIFY_RUBY_REPO}/compare/#{compare_base}...#{@tag}")
    commits = data.fetch("commits", [])
    commits.map { |c| c.dig("commit", "message").lines.first.chomp }
  rescue GhApiError => e
    warn("Warning: could not fetch changelog: #{e.message}")
    []
  end

  def generate_definition(compare_base, commits, openssl_line)
    lines = []
    lines << "# https://github.com/#{SHOPIFY_RUBY_REPO}/compare/#{compare_base}...Shopify:#{@tag}"
    lines << ""

    if commits.any?
      lines << "# Based off #{compare_base}, with the following changes:"
      commits.each { |msg| lines << "#   * #{msg}" }
    else
      lines << "# Based off #{compare_base}"
    end

    lines << ""
    lines << openssl_line
    lines << "install_git \"ruby-#{@pshopify_version}\" \"#{SHOPIFY_RUBY_GIT_URL}\" \"#{@tag}\" " \
      "autoconf enable_shared standard"
    lines << ""

    lines.join("\n")
  end

  class GhApiError < StandardError; end

  def gh_api(endpoint)
    out, err, status = Open3.capture3("gh", "api", endpoint)
    raise GhApiError, "gh api #{endpoint} failed: #{err.strip}" unless status.success?

    JSON.parse(out)
  end
end
