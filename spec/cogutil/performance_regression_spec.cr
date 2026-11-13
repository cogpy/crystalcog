require "spec"
require "file_utils"
require "../../src/cogutil/performance_regression"

private def with_temp_storage(&)
  dir = File.join("/tmp", "crystalcog_regression_spec_#{Random::Secure.hex(8)}")
  Dir.mkdir_p(dir)
  begin
    yield File.join(dir, "history.json")
  ensure
    FileUtils.rm_rf(dir)
  end
end

describe CogUtil::PerformanceRegression do
  describe "initialization" do
    it "creates a regression detector with a fresh storage path" do
      with_temp_storage do |path|
        detector = CogUtil::PerformanceRegression.new(storage_path: path)
        detector.should_not be_nil
      end
    end
  end

  describe "record_metrics and analyze_regressions" do
    it "records metrics and reports no regression with insufficient history" do
      with_temp_storage do |path|
        detector = CogUtil::PerformanceRegression.new(storage_path: path)

        session = CogUtil::PerformanceProfiler.start_session
        CogUtil::PerformanceProfiler.profile("op") { 1 + 1 }
        ended = CogUtil::PerformanceProfiler.end_session.not_nil!

        detector.record_metrics(ended, "v1")
        File.exists?(path).should be_true

        # Fewer than 2 historical entries -> no regressions
        detector.analyze_regressions(ended).should be_empty
      end
    end
  end

  describe "history across restarts" do
    it "keeps the recorded metrics when the history file is reloaded" do
      with_temp_storage do |path|
        recorder = CogUtil::PerformanceRegression.new(storage_path: path)
        2.times do |i|
          session = CogUtil::PerformanceProfiler::Session.new
          session.all_metrics["op"] = CogUtil::PerformanceProfiler::Metrics.new.tap do |m|
            m.wall_time = 1.0
            m.call_count = 20_u64
            m.memory_peak = 1000_u64
          end
          recorder.record_metrics(session, "v#{i}")
        end

        # A new process only has the file: the baseline must come from it.
        reloaded = CogUtil::PerformanceRegression.new(storage_path: path)
        slow = CogUtil::PerformanceProfiler::Session.new
        slow.all_metrics["op"] = CogUtil::PerformanceProfiler::Metrics.new.tap do |m|
          m.wall_time = 2.0
          m.call_count = 20_u64
          m.memory_peak = 1000_u64
        end
        regressions = reloaded.analyze_regressions(slow)
        regressions.size.should eq(1)
        regressions[0].function_name.should eq("op")
        regressions[0].regression_type.should eq("execution_time")
        regressions[0].baseline_value.should eq(1.0)
        regressions[0].change_percentage.should eq(100.0)

        entry = JSON.parse(File.read(path))["data"][0]
        parsed = CogUtil::PerformanceRegression::HistoricalData.from_json(JSON::PullParser.new(entry.to_json))
        parsed.version.should eq("v0")
        parsed.metrics["op"].wall_time.should eq(1.0)
        parsed.metrics["op"].call_count.should eq(20)
      end
    end
  end

  describe "RegressionResult" do
    it "classifies critical and warning regressions" do
      critical = CogUtil::PerformanceRegression::RegressionResult.new(
        function_name: "op",
        regression_type: "time",
        severity: 0.9,
        baseline_value: 100.0,
        current_value: 130.0,
        change_percentage: 30.0,
        confidence: 0.95
      )
      critical.critical?.should be_true
      critical.warning?.should be_true

      minor = CogUtil::PerformanceRegression::RegressionResult.new(
        function_name: "op",
        regression_type: "time",
        severity: 0.2,
        baseline_value: 100.0,
        current_value: 101.0,
        change_percentage: 1.0,
        confidence: 0.5
      )
      minor.critical?.should be_false
      minor.warning?.should be_false
    end
  end
end
