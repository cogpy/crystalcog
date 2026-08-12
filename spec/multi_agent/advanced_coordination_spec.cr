require "spec"
require "../../src/multi_agent/multi_agent_main"

describe MultiAgent::Coordination::Negotiator do
  it "reaches agreement within tolerance" do
    neg = MultiAgent::Coordination::Negotiator.new("a", "b")
    deal = neg.negotiate(100.0, 40.0, 5.0)
    deal.should_not be_nil
    deal.not_nil!.should be_close(70.0, 15.0)
    neg.history.should_not be_empty
  end
end

describe MultiAgent::Coordination::ConsensusEngine do
  it "computes majority vote" do
    eng = MultiAgent::Coordination::ConsensusEngine.new
    eng.majority({"a" => "x", "b" => "x", "c" => "y"}).should eq("x")
    eng.majority({"a" => "x", "b" => "y"}).should be_nil # tie, no strict majority
  end

  it "computes weighted consensus" do
    eng = MultiAgent::Coordination::ConsensusEngine.new
    result = eng.weighted(
      {"a" => "yes", "b" => "no"},
      {"a" => 3.0, "b" => 1.0}
    )
    result.should eq("yes")
  end

  it "iterates neighbor opinions to consensus" do
    eng = MultiAgent::Coordination::ConsensusEngine.new
    opinions = {"a" => "red", "b" => "blue", "c" => "red"}
    neighbors = {
      "a" => ["b", "c"],
      "b" => ["a", "c"],
      "c" => ["a", "b"],
    }
    final = eng.iterate(opinions, neighbors)
    final.values.uniq.size.should eq(1)
  end
end

describe MultiAgent::Coordination::CoalitionFormer do
  it "forms a coalition covering required capabilities" do
    a1 = MultiAgent::Coordination::Agent.new("1", "scout", ["vision", "move"])
    a2 = MultiAgent::Coordination::Agent.new("2", "arm", ["grip", "lift"])
    former = MultiAgent::Coordination::CoalitionFormer.new
    coal = former.form([a1, a2], ["vision", "grip"])
    coal.should_not be_nil
    coal.not_nil!.members.size.should eq(2)
    coal.not_nil!.value.should eq(1.0)
  end

  it "partitions agents across tasks" do
    agents = [
      MultiAgent::Coordination::Agent.new("1", "a", ["x"]),
      MultiAgent::Coordination::Agent.new("2", "b", ["y"]),
    ]
    tasks = [
      MultiAgent::Coordination::Task.new("t1", "d1", ["x"], 2.0),
      MultiAgent::Coordination::Task.new("t2", "d2", ["y"], 1.0),
    ]
    former = MultiAgent::Coordination::CoalitionFormer.new
    coals = former.partition_for_tasks(agents, tasks)
    coals.size.should eq(2)
  end
end

describe MultiAgent::Coordination::SharedMentalModel do
  it "aggregates beliefs and detects consensus" do
    smm = MultiAgent::Coordination::SharedMentalModel.new
    smm.assert("a1", "door_open", 0.9)
    smm.assert("a2", "door_open", 0.8)
    smm.consensus?("door_open", 2).should be_true
    smm.common_ground.should contain("door_open")
  end

  it "exports beliefs to atomspace" do
    atomspace = AtomSpace::AtomSpace.new
    smm = MultiAgent::Coordination::SharedMentalModel.new
    smm.assert("a1", "safe", 0.7)
    smm.to_atomspace(atomspace)
    atomspace.size.should be > 0
  end
end
