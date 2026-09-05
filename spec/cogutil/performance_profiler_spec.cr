require "spec"
require "../../src/cogutil/performance_profiler"

describe CogUtil::PerformanceProfiler do
  describe "session management" do
    it "starts and ends a profiling session" do
      session = CogUtil::PerformanceProfiler.start_session
      session.should be_a(CogUtil::PerformanceProfiler::Session)
      CogUtil::PerformanceProfiler.current_session.should_not be_nil

      ended = CogUtil::PerformanceProfiler.end_session
      ended.should_not be_nil
      CogUtil::PerformanceProfiler.current_session.should be_nil
    end
  end

  describe "profile" do
    it "profiles a block and records metrics" do
      CogUtil::PerformanceProfiler.start_session
      result = CogUtil::PerformanceProfiler.profile("test_operation") do
        1 + 1
      end
      result.should eq(2)

      session = CogUtil::PerformanceProfiler.current_session.not_nil!
      metrics = session.get_metrics("test_operation")
      metrics.should_not be_nil
      metrics.not_nil!.call_count.should eq(1_u64)
      CogUtil::PerformanceProfiler.end_session
    end

    it "records errors for raising blocks" do
      CogUtil::PerformanceProfiler.start_session
      expect_raises(Exception, "boom") do
        CogUtil::PerformanceProfiler.profile("failing_op") do
          raise "boom"
        end
      end
      session = CogUtil::PerformanceProfiler.current_session.not_nil!
      metrics = session.get_metrics("failing_op").not_nil!
      metrics.errors.should eq(1_u64)
      CogUtil::PerformanceProfiler.end_session
    end
  end

  describe "profile_iterations" do
    it "computes statistics over multiple iterations" do
      CogUtil::PerformanceProfiler.start_session
      stats = CogUtil::PerformanceProfiler.profile_iterations("loop_op", 5) do
        42
      end
      stats[:iterations].should eq(5)
      stats[:minimum].should be <= stats[:average]
      stats[:average].should be <= stats[:maximum]
      CogUtil::PerformanceProfiler.end_session
    end
  end

  describe "generate_report" do
    it "returns a message when no session is active" do
      CogUtil::PerformanceProfiler.end_session
      CogUtil::PerformanceProfiler.generate_report.should eq("No active session")
    end
  end
end
