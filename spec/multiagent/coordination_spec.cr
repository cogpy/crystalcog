require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/temporal/temporal"
require "../../src/behavior/behavior"
require "../../src/multiagent/coordination"

describe MultiAgent do
  describe MultiAgent::AgentID do
    it "creates agent ID" do
      id = MultiAgent::AgentID.new("agent1")
      id.id.should eq("agent1")
      id.group.should be_nil
    end

    it "creates agent ID with group" do
      id = MultiAgent::AgentID.new("agent1", "team1", ["navigate", "manipulate"])
      id.id.should eq("agent1")
      id.group.should eq("team1")
      id.capabilities.should eq(["navigate", "manipulate"])
    end

    it "converts to string" do
      id = MultiAgent::AgentID.new("agent1", "team1")
      id.to_s.should eq("team1/agent1")

      id2 = MultiAgent::AgentID.new("agent2")
      id2.to_s.should eq("agent2")
    end
  end

  describe MultiAgent::Message do
    it "creates message" do
      sender = MultiAgent::AgentID.new("sender")
      receiver = MultiAgent::AgentID.new("receiver")

      msg = MultiAgent::Message.new(
        sender,
        receiver,
        MultiAgent::MessageType::INFORM,
        {"key" => "value"} of String => String | Float64 | Bool | Array(String)
      )

      msg.sender.should eq(sender)
      msg.receiver.should eq(receiver)
      msg.type.should eq(MultiAgent::MessageType::INFORM)
    end

    it "creates reply" do
      sender = MultiAgent::AgentID.new("sender")
      receiver = MultiAgent::AgentID.new("receiver")

      original = MultiAgent::Message.new(sender, receiver, MultiAgent::MessageType::REQUEST)
      reply = original.reply(MultiAgent::MessageType::CONFIRM, {} of String => String | Float64 | Bool | Array(String))

      reply.sender.should eq(receiver)
      reply.receiver.should eq(sender)
      reply.reply_to.should eq(original.id)
      reply.conversation_id.should eq(original.conversation_id)
    end
  end

  describe MultiAgent::MessageQueue do
    it "creates empty queue" do
      queue = MultiAgent::MessageQueue.new
      queue.empty?.should be_true
      queue.size.should eq(0)
    end

    it "pushes and pops messages" do
      queue = MultiAgent::MessageQueue.new
      sender = MultiAgent::AgentID.new("sender")
      receiver = MultiAgent::AgentID.new("receiver")

      msg = MultiAgent::Message.new(sender, receiver, MultiAgent::MessageType::INFORM)
      queue.push(msg)

      queue.size.should eq(1)
      queue.empty?.should be_false

      popped = queue.pop
      popped.should eq(msg)
      queue.empty?.should be_true
    end

    it "filters messages by type" do
      queue = MultiAgent::MessageQueue.new
      sender = MultiAgent::AgentID.new("sender")
      receiver = MultiAgent::AgentID.new("receiver")

      queue.push(MultiAgent::Message.new(sender, receiver, MultiAgent::MessageType::INFORM))
      queue.push(MultiAgent::Message.new(sender, receiver, MultiAgent::MessageType::REQUEST))
      queue.push(MultiAgent::Message.new(sender, receiver, MultiAgent::MessageType::INFORM))

      informs = queue.filter_by_type(MultiAgent::MessageType::INFORM)
      informs.size.should eq(2)
    end
  end

  describe MultiAgent::BDIModel do
    it "manages beliefs" do
      bdi = MultiAgent::BDIModel.new

      bdi.add_belief("location", "kitchen")
      bdi.has_belief?("location").should be_true
      bdi.get_belief("location").should eq("kitchen")

      bdi.remove_belief("location")
      bdi.has_belief?("location").should be_false
    end

    it "manages desires" do
      bdi = MultiAgent::BDIModel.new

      desire = MultiAgent::Desire.new("go_home", 1.0)
      bdi.add_desire(desire)

      bdi.desires.size.should eq(1)
      bdi.desires[0].name.should eq("go_home")

      bdi.remove_desire("go_home")
      bdi.desires.should be_empty
    end

    it "sorts desires by priority" do
      bdi = MultiAgent::BDIModel.new

      bdi.add_desire(MultiAgent::Desire.new("low", 0.5))
      bdi.add_desire(MultiAgent::Desire.new("high", 1.0))
      bdi.add_desire(MultiAgent::Desire.new("medium", 0.7))

      bdi.desires[0].name.should eq("high")
      bdi.desires[1].name.should eq("medium")
      bdi.desires[2].name.should eq("low")
    end

    it "deliberates based on beliefs" do
      bdi = MultiAgent::BDIModel.new

      bdi.add_belief("hungry", true)
      bdi.add_desire(MultiAgent::Desire.new(
        "eat",
        1.0,
        {"hungry" => true} of String => String | Float64 | Bool
      ))
      bdi.add_desire(MultiAgent::Desire.new(
        "sleep",
        0.8,
        {"tired" => true} of String => String | Float64 | Bool
      ))

      active = bdi.deliberate
      active.size.should eq(1)
      active[0].name.should eq("eat")
    end
  end

  describe MultiAgent::Task do
    it "creates task" do
      requester = MultiAgent::AgentID.new("coordinator")
      task = MultiAgent::Task.new("task1", "navigate", requester, ["mobility"])

      task.id.should eq("task1")
      task.name.should eq("navigate")
      task.requester.should eq(requester)
      task.required_capabilities.should eq(["mobility"])
      task.status.should eq(:pending)
    end
  end

  describe MultiAgent::Contract do
    it "creates contract" do
      contract = MultiAgent::Contract.new("task1")
      contract.task_id.should eq("task1")
      contract.bids.should be_empty
      contract.status.should eq(:pending)
    end

    it "collects bids" do
      contract = MultiAgent::Contract.new("task1")

      bidder1 = MultiAgent::AgentID.new("agent1")
      bidder2 = MultiAgent::AgentID.new("agent2")

      contract.bids << MultiAgent::Bid.new(bidder1, 10.0)
      contract.bids << MultiAgent::Bid.new(bidder2, 8.0)

      contract.bids.size.should eq(2)
    end
  end

  describe MultiAgent::Coalition do
    it "creates coalition" do
      coalition = MultiAgent::Coalition.new("c1", "task", 100.0)
      coalition.id.should eq("c1")
      coalition.goal.should eq("task")
      coalition.value.should eq(100.0)
    end

    it "manages members" do
      coalition = MultiAgent::Coalition.new("c1", "task")

      agent1 = MultiAgent::AgentID.new("agent1")
      agent2 = MultiAgent::AgentID.new("agent2")

      coalition.add_member(agent1)
      coalition.add_member(agent2)

      coalition.size.should eq(2)
      coalition.contains?("agent1").should be_true
      coalition.contains?("agent3").should be_false

      coalition.remove_member("agent1")
      coalition.size.should eq(1)
    end

    it "distributes payoffs" do
      coalition = MultiAgent::Coalition.new("c1", "task", 100.0)

      agent1 = MultiAgent::AgentID.new("agent1")
      agent2 = MultiAgent::AgentID.new("agent2")

      coalition.add_member(agent1)
      coalition.add_member(agent2)

      coalition.set_payoff("agent1", 60.0)
      coalition.set_payoff("agent2", 40.0)

      coalition.get_payoff("agent1").should eq(60.0)
      coalition.get_payoff("agent2").should eq(40.0)
    end
  end

  describe MultiAgent::CoalitionFormation do
    it "creates coalition formation" do
      agents = [
        MultiAgent::AgentID.new("a1"),
        MultiAgent::AgentID.new("a2"),
      ]

      formation = MultiAgent::CoalitionFormation.new(agents)
      formation.agents.size.should eq(2)
    end

    it "forms coalitions" do
      agents = [
        MultiAgent::AgentID.new("a1"),
        MultiAgent::AgentID.new("a2"),
        MultiAgent::AgentID.new("a3"),
      ]

      formation = MultiAgent::CoalitionFormation.new(agents)
      formation.set_characteristic_function do |members|
        members.size.to_f64 * 10.0
      end

      coalitions = formation.form_coalitions
      coalitions.should_not be_empty
    end
  end

  describe MultiAgent::Proposal do
    it "creates proposal" do
      proposer = MultiAgent::AgentID.new("agent1")
      proposal = MultiAgent::Proposal.new(
        proposer,
        {"price" => 100.0} of String => String | Float64 | Bool,
        0.8
      )

      proposal.proposer.should eq(proposer)
      proposal.utility.should eq(0.8)
    end

    it "checks acceptance" do
      proposer = MultiAgent::AgentID.new("agent1")
      proposal = MultiAgent::Proposal.new(proposer, utility: 0.7)

      proposal.accept?(0.5).should be_true
      proposal.accept?(0.8).should be_false
    end
  end

  describe MultiAgent::AlternatingOffers do
    it "creates negotiation" do
      agents = [
        MultiAgent::AgentID.new("buyer"),
        MultiAgent::AgentID.new("seller"),
      ]

      negotiation = MultiAgent::AlternatingOffers.new(agents, 10, 0.9)
      negotiation.max_rounds.should eq(10)
      negotiation.participants.size.should eq(2)
    end

    it "manages negotiation rounds" do
      buyer = MultiAgent::AgentID.new("buyer")
      seller = MultiAgent::AgentID.new("seller")

      negotiation = MultiAgent::AlternatingOffers.new([buyer, seller])
      negotiation.start

      negotiation.status.should eq(:active)
      negotiation.current_round.should eq(0)
    end
  end

  describe MultiAgent::ConsensusMechanism do
    it "creates consensus mechanism" do
      agents = [
        MultiAgent::AgentID.new("a1"),
        MultiAgent::AgentID.new("a2"),
        MultiAgent::AgentID.new("a3"),
      ]

      consensus = MultiAgent::ConsensusMechanism.new(agents)
      consensus.has_consensus?.should be_false
    end

    it "reaches consensus" do
      agents = [
        MultiAgent::AgentID.new("a1"),
        MultiAgent::AgentID.new("a2"),
        MultiAgent::AgentID.new("a3"),
      ]

      consensus = MultiAgent::ConsensusMechanism.new(agents)

      consensus.propose(agents[0], 0.5)
      consensus.propose(agents[1], 0.5)
      consensus.propose(agents[2], 0.5)

      consensus.has_consensus?.should be_true
    end
  end

  describe MultiAgent::MessageBus do
    it "manages registrations" do
      bus = MultiAgent::MessageBus.new

      agent = MultiAgent::AgentID.new("agent1")
      bus.register(agent)

      bus.registered.includes?(agent).should be_true

      bus.unregister(agent)
      bus.registered.includes?(agent).should be_false
    end

    it "manages subscriptions" do
      bus = MultiAgent::MessageBus.new

      agent = MultiAgent::AgentID.new("agent1")
      bus.register(agent)
      bus.subscribe(agent, "sensor_data")

      bus.subscribers("sensor_data").should contain(agent)
      bus.subscribers("other_topic").should be_empty
    end
  end

  describe MultiAgent::MultiAgentEnvironment do
    it "creates environment" do
      atomspace = AtomSpace::AtomSpace.new
      env = MultiAgent::MultiAgentEnvironment.new(atomspace)

      env.agents.should be_empty
    end

    it "starts and stops" do
      atomspace = AtomSpace::AtomSpace.new
      env = MultiAgent::MultiAgentEnvironment.new(atomspace)

      env.start
      env.stop
    end
  end

  describe "Module convenience methods" do
    it "creates agent ID" do
      id = MultiAgent.create_agent_id("test", ["cap1", "cap2"])
      id.id.should eq("test")
      id.capabilities.should eq(["cap1", "cap2"])
    end

    it "creates environment" do
      atomspace = AtomSpace::AtomSpace.new
      env = MultiAgent.create_environment(atomspace)
      env.should_not be_nil
    end

    it "creates coordinator" do
      atomspace = AtomSpace::AtomSpace.new
      coordinator = MultiAgent.create_coordinator("coord", atomspace)
      coordinator.id.id.should eq("coord")
    end

    it "creates worker" do
      atomspace = AtomSpace::AtomSpace.new
      worker = MultiAgent.create_worker("worker", atomspace, ["navigate"])
      worker.id.id.should eq("worker")
      worker.id.capabilities.should contain("navigate")
    end

    it "creates task" do
      requester = MultiAgent::AgentID.new("coord")
      task = MultiAgent.create_task("test_task", requester, ["cap1"])
      task.name.should eq("test_task")
    end
  end
end
