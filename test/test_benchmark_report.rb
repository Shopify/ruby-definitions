# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"
require "open3"

# The report is a script rather than a library, so these drive it the way CI
# does: fixture results in, markdown and an exit status out.
class TestBenchmarkReport < Minitest::Test
  SCRIPT = File.expand_path("../.github/scripts/benchmark_report.rb", __dir__)

  def test_flags_a_regression_that_is_well_outside_the_noise
    report = run_report(
      raw_data: {
        "base+yjit" => { "a_bench" => { "bench" => samples(100, 1) } },
        "cand+yjit" => { "a_bench" => { "bench" => samples(120, 1) } },
      },
    )

    assert_equal(1, report.status)
    assert_includes(report.out, "🔴 slower")
    assert_includes(report.out, "1 possible regression(s)")
    assert_includes(report.out, "a_bench+yjit time (+20.0%)")
    assert_includes(report.out, "::error title=Benchmark regression::")
  end

  def test_does_not_flag_a_difference_that_is_within_the_noise
    report = run_report(
      raw_data: {
        "base+yjit" => { "a_bench" => { "bench" => samples(100, 20) } },
        "cand+yjit" => { "a_bench" => { "bench" => samples(108, 20) } },
      },
    )

    assert_equal(0, report.status)
    assert_includes(report.out, "slower, within noise")
    refute_includes(report.out, "🔴")
  end

  def test_does_not_flag_a_significant_change_below_the_threshold
    report = run_report(
      raw_data: {
        "base+yjit" => { "a_bench" => { "bench" => samples(100, 0.1) } },
        "cand+yjit" => { "a_bench" => { "bench" => samples(103, 0.1) } },
      },
    )

    assert_equal(0, report.status)
    assert_includes(report.out, "No significant regressions")
  end

  def test_reports_an_improvement_without_failing
    report = run_report(
      raw_data: {
        "base+yjit" => { "a_bench" => { "bench" => samples(120, 1) } },
        "cand+yjit" => { "a_bench" => { "bench" => samples(100, 1) } },
      },
    )

    assert_equal(0, report.status)
    assert_includes(report.out, "🟢 faster")
  end

  def test_flags_a_gc_time_regression_on_its_own
    report = run_report(
      raw_data: {
        "base+yjit" => { "gcbench" => gc_data(time_ms: 100, gc_ms: 10) },
        "cand+yjit" => { "gcbench" => gc_data(time_ms: 100, gc_ms: 30) },
      },
    )

    assert_equal(1, report.status)
    assert_includes(report.out, "gcbench+yjit GC ms (+200.0%)")
  end

  # Counts are context for a flagged change rather than a reason to fail.
  def test_does_not_flag_gc_counts
    report = run_report(
      raw_data: {
        "base+yjit" => { "gcbench" => gc_data(time_ms: 100, gc_ms: 10, minor: 10) },
        "cand+yjit" => { "gcbench" => gc_data(time_ms: 100, gc_ms: 10, minor: 40) },
      },
    )

    assert_equal(0, report.status)
    assert_includes(report.out, "No significant regressions")
  end

  def test_notes_a_benchmark_only_one_side_could_run
    report = run_report(
      raw_data: {
        "base+yjit" => {
          "a_bench" => { "bench" => samples(100, 1) },
          "only_base" => { "bench" => samples(100, 1) },
        },
        "cand+yjit" => { "a_bench" => { "bench" => samples(100, 1) } },
      },
    )

    assert_equal(0, report.status)
    assert_includes(report.out, "no data for `cand+yjit`")
  end

  # A baseline name that is a prefix of the candidate is the common case here
  # (4.0.7 against 4.0.7-pshopify1), so the mode has to be matched exactly.
  def test_matches_modes_exactly_rather_than_by_prefix
    report = run_report(
      raw_data: {
        "4.0.7+yjit" => { "a_bench" => { "bench" => samples(100, 1) } },
        "4.0.7-pshopify1+yjit" => { "a_bench" => { "bench" => samples(120, 1) } },
      },
      baseline: "4.0.7",
      candidate: "4.0.7-pshopify1",
    )

    assert_equal(1, report.status)
    assert_includes(report.out, "a_bench+yjit time (+20.0%)")
  end

  def test_aborts_when_the_two_rubies_have_no_benchmarks_in_common
    report = run_report(
      raw_data: {
        "base+yjit" => { "only_base" => { "bench" => samples(100, 1) } },
        "cand+yjit" => { "only_cand" => { "bench" => samples(100, 1) } },
      },
    )

    refute_equal(0, report.status)
    assert_includes(report.err, "no benchmarks in common")
  end

  def test_aborts_when_a_required_series_is_missing_everywhere
    report = run_report(
      raw_data: {
        "base+yjit" => { "a_bench" => { "bench" => samples(100, 1) } },
        "cand+yjit" => { "a_bench" => { "bench" => samples(100, 1) } },
      },
      require_series: "bench,rss_samples",
    )

    refute_equal(0, report.status)
    assert_includes(report.err, "reports rss_samples")
  end

  def test_accepts_a_required_series_present_on_any_benchmark
    report = run_report(
      raw_data: {
        "base+yjit" => {
          "a_bench" => { "bench" => samples(100, 1) },
          "gcbench" => gc_data(time_ms: 100, gc_ms: 10),
        },
        "cand+yjit" => {
          "a_bench" => { "bench" => samples(100, 1) },
          "gcbench" => gc_data(time_ms: 100, gc_ms: 10),
        },
      },
      require_series: "bench,gc_total_time_bench",
    )

    assert_equal(0, report.status)
    assert_includes(report.out, "No significant regressions")
  end

  def test_aborts_when_neither_ruby_is_in_the_results
    report = run_report(
      raw_data: { "other+yjit" => { "a_bench" => { "bench" => samples(100, 1) } } },
    )

    refute_equal(0, report.status)
    assert_includes(report.err, "no executables for")
  end

  private

  Report = Struct.new(:out, :err, :status, keyword_init: true)

  # Deterministic samples with a known mean and spread, so a test can ask for a
  # difference that is either far outside the noise or buried in it. ruby-bench
  # records times in seconds.
  def samples(mean_ms, spread_ms, count: 10)
    (0...count).map { |i| (mean_ms + (spread_ms * Math.sin(i * 2.1))) / 1000.0 }
  end

  def gc_data(time_ms:, gc_ms:, minor: 10)
    {
      "bench" => samples(time_ms, 1),
      "gc_total_time_bench" => samples(gc_ms, 0.1),
      "gc_marking_time_bench" => samples(gc_ms / 2.0, 0.1),
      "gc_sweeping_time_bench" => samples(gc_ms / 2.0, 0.1),
      "gc_minor_count_bench" => Array.new(10, minor),
      "gc_major_count_bench" => Array.new(10, 1),
    }
  end

  def run_report(raw_data:, baseline: "base", candidate: "cand", threshold: "5", require_series: nil)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "compare.json")
      File.write(path, JSON.generate({ "metadata" => {}, "raw_data" => raw_data }))

      series = require_series ? ["--require-series", require_series] : []
      out, err, status = Open3.capture3(
        RbConfig.ruby,
        SCRIPT,
        "--strict",
        "--baseline",
        baseline,
        "--candidate",
        candidate,
        "--threshold",
        threshold,
        *series,
        path,
      )

      Report.new(out: out, err: err, status: status.exitstatus)
    end
  end
end
