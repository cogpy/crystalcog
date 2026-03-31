require "spec"
require "../../src/multi_agent/multi_agent_main"

describe "MultiAgent Main" do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
    MultiAgent.initialize
  end

  describe "initialization" do
    it "initializes the MultiAgent subsystem without errors" do
      MultiAgent.initialize
    end

    it "has correct version" do
      MultiAgent::VERSION.should eq("0.1.0")
    end
  end

  describe "module accessibility" do
    it "exposes Communication module" do
      MultiAgent::Communication::VERSION.should eq("0.1.0")
    end

    it "exposes Coordination module" do
      MultiAgent::Coordination::VERSION.should eq("0.1.0")
    end
  end
end

describe MultiAgent::Communication do
  describe "Message" do
    it "creates a message with required fields" do
      msg = MultiAgent::Communication::Message.new(
        "agent1", "agent2", MultiAgent::Communication::Performative::INFORM, "hello"
      )
      msg.sender.should eq("agent1")
      msg.receiver.should eq("agent2")
      msg.performative.should eq(MultiAgent::Communication::Performative::INFORM)
      msg.content.should eq("hello")
      msg.id.should_not be_empty
    end

    it "generates a reply message" do
      original = MultiAgent::Communication::Message.new(
        "agent1", "agent2", MultiAgent::Communication::Performative::REQUEST, "do task"
      )
      reply = original.reply("agent2", MultiAgent::Communication::Performative::REPLY, "task done")
      reply.sender.should eq("agent2")
      reply.receiver.should eq("agent1")
      reply.in_reply_to.should eq(original.id)
      reply.conversation_id.should eq(original.conversation_id)
    end
  end

  describe "Mailbox" do
    it "delivers and reads messages" do
      mailbox = MultiAgent::Communication::Mailbox.new("agent1")
      msg = MultiAgent::Communication::Message.new("agent2", "agent1", MultiAgent::Communication::Performative::INFORM, "hi")
      mailbox.deliver(msg)
      mailbox.has_messages?.should be_true
      mailbox.unread_count.should eq(1)
      received = mailbox.next_message
      received.should_not be_nil
      received.not_nil!.content.should eq("hi")
      mailbox.has_messages?.should be_false
    end
  end

  describe "MessageBus" do
    it "routes messages between agents" do
      bus = MultiAgent::Communication::MessageBus.new
      bus.register("a1")
      bus.register("a2")
      msg = MultiAgent::Communication::Message.new("a1", "a2", MultiAgent::Communication::Performative::INFORM, "test")
      result = bus.send(msg)
      result.should be_true
      mailbox = bus.mailbox_for("a2")
      mailbox.should_not be_nil
      mailbox.not_nil!.has_messages?.should be_true
    end

    it "returns false for unknown receiver" do
      bus = MultiAgent::Communication::MessageBus.new
      bus.register("a1")
      msg = MultiAgent::Communication::Message.new("a1", "nobody", MultiAgent::Communication::Performative::INFORM, "test")
      bus.send(msg).should be_false
    end

    it "broadcasts to all agents" do
      bus = MultiAgent::Communication::MessageBus.new
      bus.register("coordinator")
      bus.register("worker1")
      bus.register("worker2")
      bus.broadcast("coordinator", MultiAgent::Communication::Performative::INFORM, "ready")
      bus.mailbox_for("worker1").not_nil!.has_messages?.should be_true
      bus.mailbox_for("worker2").not_nil!.has_messages?.should be_true
      bus.mailbox_for("coordinator").not_nil!.has_messages?.should be_false
    end
  end
end

describe MultiAgent::Coordination do
  describe "Agent" do
    it "creates an agent with capabilities" do
      agent = MultiAgent::Coordination::Agent.new("a1", "RobotArm", ["pick", "place"])
      agent.name.should eq("RobotArm")
      agent.capabilities.should contain("pick")
      agent.busy?.should be_false
    end

    it "checks task compatibility" do
      agent = MultiAgent::Coordination::Agent.new("a1", "Arm", ["pick", "weld"])
      task_ok = MultiAgent::Coordination::Task.new("weld_part", "weld", ["weld"])
      task_bad = MultiAgent::Coordination::Task.new("paint", "apply paint", ["paint"])
      agent.can_handle?(task_ok).should be_true
      agent.can_handle?(task_bad).should be_false
    end

    it "accepts a compatible task" do
      agent = MultiAgent::Coordination::Agent.new("a1", "Bot", ["move"])
      task = MultiAgent::Coordination::Task.new("goto_A", "move to A", ["move"])
      result = agent.accept_task(task)
      result.should be_true
      agent.busy?.should be_true
      task.status.should eq(MultiAgent::Coordination::Task::TaskStatus::ASSIGNED)
    end

    it "cannot accept an incompatible task" do
      agent = MultiAgent::Coordination::Agent.new("a1", "Bot", ["move"])
      task = MultiAgent::Coordination::Task.new("weld", "weld", ["weld"])
      agent.accept_task(task).should be_false
    end
  end

  describe "ContractNetCoordinator" do
    it "registers agents" do
      coord = MultiAgent::Coordination::ContractNetCoordinator.new
      agent = MultiAgent::Coordination::Agent.new("a1", "Bot", ["pick"])
      coord.register_agent(agent)
      coord.agents.size.should eq(1)
    end

    it "allocates tasks to capable agents" do
      coord = MultiAgent::Coordination::ContractNetCoordinator.new
      agent = MultiAgent::Coordination::Agent.new("a1", "Bot", ["move"])
      coord.register_agent(agent)
      task = MultiAgent::Coordination::Task.new("go", "go somewhere", ["move"])
      coord.submit_task(task)
      allocated = coord.allocate_tasks
      allocated.should eq(1)
      task.status.should eq(MultiAgent::Coordination::Task::TaskStatus::ASSIGNED)
      task.assigned_to.should eq("a1")
    end

    it "does not allocate tasks with missing capabilities" do
      coord = MultiAgent::Coordination::ContractNetCoordinator.new
      agent = MultiAgent::Coordination::Agent.new("a1", "Bot", ["move"])
      coord.register_agent(agent)
      task = MultiAgent::Coordination::Task.new("weld", "weld", ["weld"])
      coord.submit_task(task)
      allocated = coord.allocate_tasks
      allocated.should eq(0)
    end

    it "stores state in atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      coord = MultiAgent::Coordination::ContractNetCoordinator.new
      agent = MultiAgent::Coordination::Agent.new("a1", "Bot", ["pick"])
      coord.register_agent(agent)
      task = MultiAgent::Coordination::Task.new("pickup", "pick object", ["pick"])
      coord.submit_task(task)
      coord.to_atomspace(atomspace)
      atomspace.size.should be > 0
    end
  end
end
