require "spec"
require "../../src/cogutil/performance_profiler"
require "../../src/cogutil/performance_regression"

describe CogUtil::PerformanceProfiler::Session do
  it "rebuilds a session from export_metrics JSON" do
    CogUtil::PerformanceProfiler.start_session
    CogUtil::PerformanceProfiler.profile("io_spec_fn") { 1 + 1 }
    json = CogUtil::PerformanceProfiler.export_metrics
    original = CogUtil::PerformanceProfiler.end_session.not_nil!

    loaded = CogUtil::PerformanceProfiler::Session.from_export(json)
    metrics = loaded.get_metrics("io_spec_fn").not_nil!
    metrics.call_count.should eq(original.get_metrics("io_spec_fn").not_nil!.call_count)
    metrics.wall_time.should be_close(original.get_metrics("io_spec_fn").not_nil!.wall_time, 1e-12)
    loaded.session_duration.should be > 0.0
  end

  it "tolerates integer fields and non-object JSON" do
    loaded = CogUtil::PerformanceProfiler::Session.from_export(%({"metrics":{"f":{"wall_time":2,"call_count":4}}}))
    loaded.get_metrics("f").not_nil!.wall_time.should eq(2.0)
    CogUtil::PerformanceProfiler::Session.from_export("[1,2]").all_metrics.should be_empty
  end
end

describe CogUtil::PerformanceRegression do
  it "compares two sessions directly and counts each regression once" do
    base = CogUtil::PerformanceProfiler::Session.from_export(
      %({"metrics":{"f":{"wall_time":0.1,"call_count":10,"memory_peak":1000},"g":{"wall_time":0.2,"call_count":5}}}))
    cur = CogUtil::PerformanceProfiler::Session.from_export(
      %({"metrics":{"f":{"wall_time":0.3,"call_count":10,"memory_peak":1000},"g":{"wall_time":0.2,"call_count":5}}}))

    detector = CogUtil::PerformanceRegression.new(storage_path: File.tempname("perf", ".json"))
    regressions = detector.compare_sessions(base, cur)
    regressions.map(&.function_name).should eq(["f"])
    regressions.first.regression_type.should eq("execution_time")

    report = detector.generate_regression_report(regressions)
    report.should contain("Critical: 1")
    report.should contain("Warning: 0")
  end
end
