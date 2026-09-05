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
