#!/usr/bin/env ruby
# frozen_string_literal: true

# Turns a ruby-bench JSON result into a markdown regression report.
#
# Usage: benchmark_report.rb --baseline NAME --candidate NAME [options] <results.json>
#
#   --baseline NAME   baseline definition name, e.g. 3.4.9-pshopify1
#   --candidate NAME  candidate definition name, e.g. 3.4.10-pshopify1
#   --threshold PCT   percent slowdown before a benchmark is flagged (default: 5)
#   --strict          exit non-zero when a regression is flagged
#   --require-series  comma separated result series that must appear for at
#                     least one benchmark, e.g. bench,rss_samples
#
# The JSON is written by ruby-bench's run_benchmarks.rb and looks like:
#   {"metadata": {"<exe>": "<RUBY_DESCRIPTION>"},
#    "raw_data": {"<exe>": {"<bench>": {"warmup": [s...], "bench": [s...]}}}}
#
# Executables are named "<definition>" and "<definition>+yjit" by the workflow, so
# each "+yjit"-style suffix present for both definitions is compared as its own
# table: interpreter against interpreter, YJIT against YJIT.
#
# Benchmarks run under ruby-bench's gc harness (its "gc" category) also record
# per-iteration GC counters, and --rss records resident set size. Those are
# compared too: a change that makes the GC mark or retain more can show up there
# while still being lost in wall-time noise.

require "json"

threshold = 5.0
strict = false
baseline_def = nil
candidate_def = nil
required_series = []
args = []

until ARGV.empty?
  case (arg = ARGV.shift)
  when "--baseline" then baseline_def = ARGV.shift
  when "--candidate" then candidate_def = ARGV.shift
  when "--threshold" then threshold = Float(ARGV.shift)
  when "--strict" then strict = true
  when "--require-series" then required_series = ARGV.shift.to_s.split(",")
  else args << arg
  end
end

path = args[0]
unless path && baseline_def && candidate_def
  abort("usage: #{$PROGRAM_NAME} --baseline NAME --candidate NAME [--threshold PCT] [--strict] <results.json>")
end

data = JSON.parse(File.read(path))
raw = data.fetch("raw_data")

# "3.4.10-pshopify1+yjit" -> "+yjit", "3.4.10-pshopify1" -> ""
# ruby-bench names an executable after the ruby plus the mode it runs in, as
# "<definition>" or "<definition>+<mode>". Matching the bare prefix would also
# match a longer definition name (baseline 4.0.7 against 4.0.7-pshopify1, which
# is the common case here), so require what follows to be a mode.
def suffixes_for(keys, definition)
  keys.filter_map do |key|
    next unless key == definition || key.start_with?("#{definition}+")

    key.delete_prefix(definition)
  end
end

modes = suffixes_for(raw.keys, baseline_def) & suffixes_for(raw.keys, candidate_def)
if modes.empty?
  abort("no executables for both #{baseline_def.inspect} and #{candidate_def.inspect} in #{path}; got #{raw.keys.inspect}")
end

def mean(values)
  values.sum / values.size.to_f
end

def stddev(values)
  return 0.0 if values.size < 2

  avg = mean(values)
  Math.sqrt(values.sum { |value| (value - avg)**2 } / (values.size - 1).to_f)
end

# How many standard errors of the difference of means a change has to exceed to
# count as real. Two would be the usual ~95% for a single comparison, but a run
# compares around twenty benchmark/metric pairs, so at two one of them would be
# flagged by chance in a typical run. Three is roughly the Bonferroni-corrected
# equivalent for that many comparisons, which matters because a flagged
# regression fails the job.
SIGNIFICANCE_SIGMAS = 3

def significant?(base_values, cand_values)
  standard_error = Math.sqrt(
    (stddev(base_values)**2 / base_values.size) + (stddev(cand_values)**2 / cand_values.size),
  )
  (mean(cand_values) - mean(base_values)).abs > SIGNIFICANCE_SIGMAS * standard_error
end

MS = 1000.0
MIB = 1024.0 * 1024.0

# Per-iteration series recorded by ruby-bench's gc harness (see its harness/gc.rb)
# and, for rss_samples, by --rss. Benchmarks that run under another harness do not
# have these keys, so each metric is only reported where both rubies recorded it.
# GC times are already in milliseconds and counts are per iteration.
#
# Only GC time and RSS are flagged as regressions: the counts move for benign
# reasons (a faster ruby reaching more iterations of work), but they explain
# whichever of the two did move.
GCMetric = Struct.new(:key, :label, :scale, :flag, keyword_init: true)
GC_METRICS = [
  GCMetric.new(key: "gc_total_time_bench", label: "GC ms", scale: 1.0, flag: true),
  GCMetric.new(key: "gc_marking_time_bench", label: "mark ms", scale: 1.0, flag: false),
  GCMetric.new(key: "gc_sweeping_time_bench", label: "sweep ms", scale: 1.0, flag: false),
  GCMetric.new(key: "gc_major_count_bench", label: "major GCs", scale: 1.0, flag: false),
  GCMetric.new(key: "gc_minor_count_bench", label: "minor GCs", scale: 1.0, flag: false),
  GCMetric.new(key: "rss_samples", label: "RSS MiB", scale: 1.0 / MIB, flag: true),
].freeze

# Returns [rows, regressions, compared] for one baseline/candidate executable
# pair, where compared counts the benchmarks both rubies actually ran.
def compare(raw, baseline_name, candidate_name, threshold)
  rows = []
  regressions = []
  compared = 0

  (raw[baseline_name].keys | raw[candidate_name].keys).sort.each do |bench|
    base = raw[baseline_name][bench]
    cand = raw[candidate_name][bench]

    if base.nil? || cand.nil?
      missing = base.nil? ? baseline_name : candidate_name
      rows << [bench, "—", "—", "—", "—", "—", "❔ no data for `#{missing}`"]
      next
    end

    compared += 1

    base_times = base.fetch("bench").map { |value| value * MS }
    cand_times = cand.fetch("bench").map { |value| value * MS }

    base_mean = mean(base_times)
    cand_mean = mean(cand_times)
    base_sd = stddev(base_times)
    cand_sd = stddev(cand_times)

    change = (cand_mean - base_mean) / base_mean * 100.0
    significant = significant?(base_times, cand_times)

    note =
      if change > threshold && significant
        regressions << [bench, "time", change]
        "🔴 slower"
      elsif change > threshold
        "🟡 slower, within noise"
      elsif change < -threshold && significant
        "🟢 faster"
      else
        ""
      end

    rows << [
      bench,
      format("%.1f", base_mean),
      format("%.1f%%", base_sd / base_mean * 100.0),
      format("%.1f", cand_mean),
      format("%.1f%%", cand_sd / cand_mean * 100.0),
      format("%+.1f%%", change),
      note,
    ]
  end

  [rows, regressions, compared]
end

# Compares one per-iteration series, e.g. GC time or RSS, for a single benchmark.
# Returns [cell, change, significant], with cell like "113.1 → 120.4 (+6.5%)".
def compare_metric(base, cand, metric)
  base_values = base[metric.key]
  cand_values = cand[metric.key]
  unless base_values.is_a?(Array) && cand_values.is_a?(Array) &&
      !base_values.empty? && !cand_values.empty?
    return [nil, nil, false]
  end

  base_values = base_values.map { |value| value * metric.scale }
  cand_values = cand_values.map { |value| value * metric.scale }
  base_mean = mean(base_values)
  cand_mean = mean(cand_values)

  cell = format("%.1f → %.1f", base_mean, cand_mean)
  return [cell, nil, false] if base_mean.zero?

  change = (cand_mean - base_mean) / base_mean * 100.0
  ["#{cell} (#{format("%+.1f%%", change)})", change, significant?(base_values, cand_values)]
end

# Returns [rows, regressions] for the GC and memory metrics, covering only the
# benchmarks that recorded at least one of them.
def compare_gc(raw, baseline_name, candidate_name, threshold)
  rows = []
  regressions = []

  (raw[baseline_name].keys & raw[candidate_name].keys).sort.each do |bench|
    base = raw[baseline_name][bench]
    cand = raw[candidate_name][bench]

    cells = GC_METRICS.map do |metric|
      cell, change, significant = compare_metric(base, cand, metric)
      if metric.flag && change && change > threshold && significant
        regressions << [bench, metric.label, change]
        cell = "🔴 #{cell}"
      end
      cell
    end

    rows << [bench, *cells.map { |cell| cell || "—" }] if cells.any?
  end

  [rows, regressions]
end

# The first column is the benchmark name, the rest are numeric and right
# aligned, except for a trailing note column when there is one.
def markdown_table(report, headings, rows, note_column: false)
  numeric = headings.size - (note_column ? 2 : 1)
  report << "| #{headings.join(" | ")} |\n"
  report << "|---#{"|---:" * numeric}#{note_column ? "|---|" : "|"}\n"
  rows.each { |row| report << "| #{row.join(" | ")} |\n" }
  report << "\n"
end

report = +"## Benchmarks: `#{candidate_def}` vs `#{baseline_def}`\n\n"
report << "Lower is better. `change` is candidate vs baseline mean time; a benchmark is\n" \
  "flagged only when the change exceeds #{format("%.1f", threshold)}% *and* exceeds #{SIGNIFICANCE_SIGMAS} times the combined\n" \
  "standard error. Wall time, GC time and RSS can be flagged; the GC counts are\n" \
  "reported to explain a flagged change, not to cause one.\n\n"
data.fetch("metadata", {}).each { |name, description| report << "- `#{name}`: #{description}\n" }
report << "\n"

# ruby-bench's result keys are not an interface it promises to keep, and the
# suite is checked out from its default branch. A renamed series would otherwise
# turn into an empty cell and quietly stop being reported, so the caller says
# what it expects to be measuring and this fails when it is not there.
executables = modes.flat_map { |mode| ["#{baseline_def}#{mode}", "#{candidate_def}#{mode}"] }
present_series = executables.flat_map { |name| raw.fetch(name, {}).values.flat_map(&:keys) }.uniq
missing_series = required_series - present_series

all_regressions = []
compared = 0

modes.each do |mode|
  baseline_name = "#{baseline_def}#{mode}"
  candidate_name = "#{candidate_def}#{mode}"
  rows, regressions, mode_compared = compare(raw, baseline_name, candidate_name, threshold)
  gc_rows, gc_regressions = compare_gc(raw, baseline_name, candidate_name, threshold)

  report << "### #{mode.empty? ? "Interpreter" : mode.delete_prefix("+").upcase}\n\n"
  markdown_table(
    report,
    ["bench", "#{baseline_name} (ms)", "±", "#{candidate_name} (ms)", "±", "change", ""],
    rows,
    note_column: true,
  )

  unless gc_rows.empty?
    report << "<details><summary>GC and memory (baseline → candidate, per iteration)</summary>\n\n"
    markdown_table(report, ["bench", *GC_METRICS.map(&:label)], gc_rows)
    report << "</details>\n\n"
  end

  compared += mode_compared
  all_regressions.concat((regressions + gc_regressions).map { |bench, metric, change| [mode, bench, metric, change] })
end

# Without this an empty result file reports "no regressions" and looks like a pass.
if compared.zero?
  abort("no benchmarks in common between #{baseline_def.inspect} and #{candidate_def.inspect} in #{path}")
end

summary_line = all_regressions.map { |mode, bench, metric, change|
  "#{bench}#{mode} #{metric} (#{format("%+.1f%%", change)})"
}.join(", ")

if all_regressions.empty?
  report << "No significant regressions over #{format("%.1f", threshold)}%.\n"
else
  report << "### ⚠️ #{all_regressions.size} possible regression(s)\n\n"
  report << "#{summary_line}\n\n"
  report << "Regression detected, so this job fails. Shared CI runners drift and this\n" \
    "check cannot tell a real regression from a slow neighbour, so please test it\n" \
    "yourself and merge at your own discretion. Re-running the job is a reasonable\n" \
    "first step: a result that does not reproduce was noise.\n"
end

unless missing_series.empty?
  report << "\n### ❌ Missing result series\n\n" \
    "No benchmark reported #{missing_series.join(", ")}, so the report above is incomplete: " \
    "ruby-bench may have renamed the series, or the run did not ask for it (`--rss` records " \
    "`rss_samples`, `--category gc` records the `gc_*` series).\n"
end

summary = ENV["GITHUB_STEP_SUMMARY"].to_s
File.write(summary, report, mode: "a") unless summary.empty?
puts report

# After the report is written, so a missing series does not cost the tables that
# were produced.
unless missing_series.empty?
  abort(
    "no benchmark in #{path} reports #{missing_series.join(", ")}; ruby-bench may have renamed " \
      "it, or the run did not ask for it (--rss records rss_samples, --category gc records gc_*)",
  )
end

if strict && !all_regressions.empty?
  # An annotation, because the step summary is not visible from the checks list
  # or from a notification about the failed job.
  puts("::error title=Benchmark regression::#{candidate_def} vs #{baseline_def}: #{summary_line}. " \
    "Please test it yourself and merge at your own discretion.")
  exit(1)
end
