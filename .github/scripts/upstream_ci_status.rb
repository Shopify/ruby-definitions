#!/usr/bin/env ruby
# frozen_string_literal: true

# Reports the CI status of the upstream ruby commit that a ruby-build definition
# points at (the `install_git` ref, e.g. Shopify/ruby v4.0.5-pshopify3).
#
# Several checks are chronically red on the refs we ship (mmtk, tarball,
# dependency checks), so a raw pass/fail count is not actionable. The report
# therefore compares against the same baseline the benchmarks use, which for the
# first Shopify patch of a release is the release itself (4.0.7-pshopify1 ->
# 4.0.7), and leads with the checks that are failing here but were not failing
# there.
#
# Check runs belong to a repository rather than to a commit, and an upstream
# release tag pushed to the fork carries none, so for a bare upstream version
# the lookup falls back to ruby/ruby for the same commit. That compares two CI
# configurations: most job names line up (69 of 74 for v4.0.7), and a failing
# check with no counterpart in the baseline is reported as new.
#
# Usage: upstream_ci_status.rb [--strict] rubies/<definition> [...]
#
#   --strict  exit non-zero if a check is failing that was not already failing
#             in the comparison ref
#
# Writes a markdown report to $GITHUB_STEP_SUMMARY when set, otherwise stdout.

require "json"
require "net/http"
require "openssl"
require "set"
require "uri"
require_relative "definitions"

API_ROOT = "https://api.github.com"

# How far back to look for a comparison ref. Each candidate costs two API calls,
# and definitions far enough back are too old to be a useful comparison.
MAX_BASELINE_CANDIDATES = 5

UPSTREAM_REPO = "ruby/ruby"

FAILING_CONCLUSIONS = ["failure", "timed_out", "action_required"].freeze

CONCLUSION_ICONS = {
  "success" => "✅",
  "failure" => "❌",
  "timed_out" => "❌",
  "cancelled" => "⚪",
  "skipped" => "⏭️",
  "neutral" => "➖",
  "action_required" => "⚠️",
  nil => "🟡", # still running
}.freeze

# Every failure a request can produce, so that a caller can rescue one thing
# and tell a ref that is simply not there, which is expected while walking back
# through baselines, from being rate limited, which makes the rest of the report
# meaningless.
class ApiError < StandardError
  def initialize(message, status:, rate_limited: false)
    super(message)
    @status = status
    @rate_limited = rate_limited
  end

  attr_reader :status

  def rate_limited?
    @rate_limited
  end
end

def api_get(path)
  uri = URI.join(API_ROOT, path)
  request = Net::HTTP::Get.new(uri)
  request["Accept"] = "application/vnd.github+json"
  request["X-GitHub-Api-Version"] = "2022-11-28"
  token = ENV["GITHUB_TOKEN"].to_s
  request["Authorization"] = "Bearer #{token}" unless token.empty?

  response =
    begin
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    rescue SocketError, SystemCallError, IOError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
           Net::HTTPBadResponse, OpenSSL::SSL::SSLError => error
      raise ApiError.new("GET #{uri} failed: #{error.class}: #{error.message}", status: nil)
    end

  unless response.is_a?(Net::HTTPSuccess)
    rate_limited = ["403", "429"].include?(response.code) &&
      (response["x-ratelimit-remaining"] == "0" || response.body.to_s.include?("rate limit"))

    raise ApiError.new(
      "GET #{uri} failed: #{response.code} #{response.body.to_s[0, 300]}",
      status: response.code,
      rate_limited: rate_limited,
    )
  end

  begin
    JSON.parse(response.body)
  rescue JSON::ParserError => error
    raise ApiError.new("GET #{uri} returned unparseable JSON: #{error.message}", status: response.code)
  end
end

def resolve_sha(repo, ref)
  api_get("/repos/#{repo}/commits/#{ref}")["sha"]
end

def check_runs(repo, sha)
  runs = []
  page = 1
  loop do
    body = api_get("/repos/#{repo}/commits/#{sha}/check-runs?per_page=100&page=#{page}")
    batch = body["check_runs"] || []
    runs.concat(batch)
    break if batch.empty? || runs.size >= body["total_count"].to_i

    page += 1
  end
  runs
end

def failing(runs)
  runs.select { |run| FAILING_CONCLUSIONS.include?(run["conclusion"]) }
end

# Where to look for a baseline's check runs. One of our definitions names the
# repository and ref itself; a bare upstream version is a release tag, which the
# fork may have without having run CI on it.
def baseline_sources(baseline, rubies_dir, repo)
  source = Definitions.source(File.join(rubies_dir, baseline))
  return [[source.repo, source.ref]] if source

  [[repo, "v#{baseline}"], [UPSTREAM_REPO, "v#{baseline}"]]
end

# The preferred baseline, then progressively older definitions, so that a
# baseline whose ref has no check runs does not leave the report without a
# comparison (and does not look like "everything got fixed").
def comparison_ref(name, rubies_dir, repo)
  # "none" says there is nothing useful to compare against, so take it at its
  # word rather than falling through to an older definition.
  return nil if Definitions.baseline_override(File.join(rubies_dir, name)) == "none"

  candidates = [
    Definitions.previous(name, rubies_dir),
    *Definitions.earlier(name, rubies_dir).map(&:name),
  ].compact.uniq.first(MAX_BASELINE_CANDIDATES)

  candidates.each do |baseline|
    baseline_sources(baseline, rubies_dir, repo).each do |baseline_repo, ref|
      begin
        sha = resolve_sha(baseline_repo, ref)
        runs = check_runs(baseline_repo, sha)
      rescue ApiError => error
        # A ref we cannot read is just a candidate that does not work out, but
        # once rate limited every further candidate would fail the same way.
        raise if error.rate_limited?

        next
      end

      next if runs.empty?

      return { name: baseline, repo: baseline_repo, ref: ref, sha: sha, runs: runs }
    end
  end

  nil
end

def check_list(report, runs)
  runs.sort_by { |run| run["name"] }.each do |run|
    report << "- [#{run["name"]}](#{run["html_url"]}) — #{run["conclusion"]}\n"
  end
  report << "\n"
end

strict = ARGV.delete("--strict")
definitions = ARGV
abort("usage: #{$PROGRAM_NAME} [--strict] rubies/<definition> [...]") if definitions.empty?

report = +""
new_failures = false

definitions.each do |path|
  name = File.basename(path)
  rubies_dir = File.dirname(path)
  source = Definitions.source(path)

  report << "## Upstream CI for `#{name}`\n\n"

  if source.nil?
    report << "No `install_git` source found; nothing to check.\n\n"
    next
  end

  repo = source.repo
  ref = source.ref

  begin
    sha = resolve_sha(repo, ref)
  rescue => error
    report << "Could not resolve `#{repo}@#{ref}`: #{error.message}\n\n"
    new_failures = true if strict
    next
  end

  report << "Source: [`#{repo}@#{ref}`](https://github.com/#{repo}/tree/#{ref}) " \
    "([`#{sha[0, 12]}`](https://github.com/#{repo}/commit/#{sha}))\n\n" \
    "Checks: https://github.com/#{repo}/commit/#{sha}/checks\n\n"

  begin
    runs = check_runs(repo, sha)
  rescue ApiError => error
    report << "Could not read the check runs for `#{repo}@#{ref}`: #{error.message}\n\n"
    next
  end

  if runs.empty?
    report << "No check runs reported for this commit.\n\n"
    next
  end

  tally = runs.group_by { |run| run["status"] == "completed" ? run["conclusion"] : nil }
  summary = tally.sort_by { |conclusion, _| conclusion.to_s }.map do |conclusion, list|
    "#{CONCLUSION_ICONS.fetch(conclusion, "❔")} #{conclusion || "in progress"}: #{list.size}"
  end
  report << "#{summary.join(" &nbsp;|&nbsp; ")} (#{runs.size} total)\n\n"

  bad = failing(runs)
  baseline =
    begin
      comparison_ref(name, rubies_dir, repo)
    rescue ApiError => error
      report << "Could not look up anything to compare against: #{error.message}\n\n"
      nil
    end

  if baseline.nil?
    unless bad.empty?
      new_failures = true
      report << "<details><summary>#{bad.size} failing check(s)</summary>\n\n"
      check_list(report, bad)
      report << "</details>\n\n"
    end
    next
  end

  baseline_names = failing(baseline[:runs]).map { |run| run["name"] }.to_set
  current_names = bad.map { |run| run["name"] }.to_set
  current_all_names = runs.map { |run| run["name"] }.to_set

  baseline_label = "#{baseline[:repo] == repo ? "" : "#{baseline[:repo]}@"}#{baseline[:ref]}"
  report << "Compared against " \
    "[`#{baseline_label}`](https://github.com/#{baseline[:repo]}/commit/#{baseline[:sha]}/checks) " \
    "(`#{baseline[:name]}`), which has #{baseline_names.size} failing check(s).\n\n"

  introduced = bad.reject { |run| baseline_names.include?(run["name"]) }
  chronic = bad.select { |run| baseline_names.include?(run["name"]) }
  # Only checks this ref actually ran, so that a baseline-only job (a platform
  # the fork does not build, say) is not reported as something we fixed.
  fixed = ((baseline_names & current_all_names) - current_names).sort

  if introduced.empty?
    report << "✅ No checks are failing here that were not already failing in `#{baseline[:name]}`.\n\n"
  else
    new_failures = true
    report << "### ⚠️ #{introduced.size} check(s) failing here but not in `#{baseline[:name]}`\n\n"
    check_list(report, introduced)
  end

  unless chronic.empty?
    report << "<details><summary>#{chronic.size} check(s) also failing in `#{baseline[:name]}`</summary>\n\n"
    check_list(report, chronic)
    report << "</details>\n\n"
  end

  unless fixed.empty?
    report << "<details><summary>#{fixed.size} check(s) failing in `#{baseline[:name]}` but not here</summary>\n\n"
    fixed.each { |check| report << "- #{check}\n" }
    report << "\n</details>\n\n"
  end
end

out = ENV["GITHUB_STEP_SUMMARY"]
if out && !out.empty?
  File.write(out, report, mode: "a")
end
puts report

exit(1) if strict && new_failures
