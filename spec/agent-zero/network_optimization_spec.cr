require "spec"
require "../../src/agent-zero/distributed_agents"
require "../../src/agent-zero/agent_network"
require "../../src/agent-zero/network_services"

describe "AgentZero network optimization" do
  it "measures efficiency on the real peer graph and shortens long paths" do
    agents = (0...4).map { |i| AgentZero::AgentNode.new("chain-#{i}", "127.0.0.1") }
    agents.each(&.start)
    sleep 100.milliseconds
    begin
      AgentZero::TaskCoordinator.global_efficiency(agents).should eq(0.0)
      # A chain: 0 - 1 - 2 - 3.
      3.times { |i| agents[i].connect_to_peer(agents[i + 1].host, agents[i + 1].port).should be_true }
      AgentZero::TaskCoordinator.hop_distances(agents)[0].should eq([0, 1, 2, 3])
      # Unordered pair distances 1, 2, 3, 1, 2, 1: mean of 1/d is 13/18.
      AgentZero::TaskCoordinator.global_efficiency(agents).should be_close(13.0 / 18.0, 1e-9)

      coordinator = AgentZero::TaskCoordinator.new(AgentZero::AgentNetwork::NetworkConfig.new)
      task = AgentZero::DistributedTask.new("network_optimization", "Tighten the topology", ["reasoning"])
      result = coordinator.execute_task(task, agents)
      result.success.should be_true

      # Only the ends were more than two hops apart: one link closes the ring.
      result.results["links_added"].as_i.should eq(1)
      result.results["original_efficiency"].as_f.should be_close(13.0 / 18.0, 1e-9)
      result.results["optimized_efficiency"].as_f.should be_close(5.0 / 6.0, 1e-9)
      result.results["improvement"].as_f.should be > 0.1
      agents[0].peer_ids.should contain(agents[3].id)
      AgentZero::TaskCoordinator.hop_distances(agents).flatten.compact.max.should eq(2)

      # Nothing left to do the second time.
      again = coordinator.execute_task(task, agents)
      again.results["links_added"].as_i.should eq(0)
      again.results["improvement"].as_f.should eq(0.0)
    ensure
      agents.each(&.stop)
      sleep 100.milliseconds
    end
  end

  it "treats a single agent as trivially efficient" do
    AgentZero::TaskCoordinator.global_efficiency([] of AgentZero::AgentNode).should eq(1.0)
  end
end
