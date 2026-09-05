require "spec"
require "../../src/cogutil/profiling_cli"

describe CogUtil::ProfilingCLI do
  it "can be instantiated" do
    cli = CogUtil::ProfilingCLI.new
    cli.should_not be_nil
  end

  it "exposes a run method accepting an argument array" do
    cli = CogUtil::ProfilingCLI.new
    cli.responds_to?(:run).should be_true
  end

  # NOTE: ProfilingCLI#run calls `exit` for empty/unknown commands and runs
  # long-lived profiling/monitoring loops for valid commands, so it cannot be
  # safely exercised in-process. Instantiation and interface checks above are
  # the reliable unit-level coverage; end-to-end CLI behavior is covered by the
  # `profiler` binary target.
end
