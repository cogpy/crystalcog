require "spec"
require "../../src/cogserver/cogserver_shell"

# Direct coverage for src/cogserver/cogserver_shell.cr, which installs the
# CogShell command set as CogServer::Server.shell_factory. These examples
# never call Server#start, so no listener ports are opened.
describe "CogServer shell factory (cogserver_shell.cr)" do
  it "installs a factory when the file is required" do
    CogServer::Server.shell_factory.should_not be_nil
  end

  it "binds each shell to the AtomSpace it is given" do
    factory = CogServer::Server.shell_factory.not_nil!
    first = AtomSpace::AtomSpace.new
    second = AtomSpace::AtomSpace.new
    shell_one = factory.call(first)
    shell_two = factory.call(second)

    shell_one.call("concept dog").should contain("dog")
    shell_one.call("concept cat")
    shell_two.call("concept fish")

    first.size.should eq(2)
    first.get_nodes_by_name("dog").size.should eq(1)
    first.get_nodes_by_name("fish").should be_empty
    second.size.should eq(1)
    shell_two.call("size").should contain("size=1")
    shell_one.call("bogus").should contain("Unknown command: bogus")
  end

  it "gives a new server a shell that works on that server's AtomSpace" do
    server = CogServer::Server.new("127.0.0.1", 19480, 19481)
    output = server.run_shell_command("concept whale")
    output.should contain("whale")
    output.should eq(output.rstrip)
    server.atomspace.get_nodes_by_name("whale").size.should eq(1)

    server.run_shell_command("inherit whale mammal")
    server.atomspace.link_count.should eq(1)
    server.run_shell_command("size").should contain("size=3")
    server.run_shell_command("bogus").should contain("Unknown command: bogus")

    other = CogServer::Server.new("127.0.0.1", 19482, 19483)
    other.atomspace.size.should eq(0)
  end

  it "keeps every command from concurrent fibers on one server" do
    server = CogServer::Server.new("127.0.0.1", 19484, 19485)
    done = Channel(Nil).new
    20.times do |i|
      spawn do
        server.run_shell_command("concept parallel_#{i}")
        done.send(nil)
      end
    end
    20.times { done.receive }
    server.atomspace.size.should eq(20)
  end

  it "reports a missing shell when no factory is installed" do
    factory = CogServer::Server.shell_factory
    CogServer::Server.shell_factory = nil
    begin
      server = CogServer::Server.new("127.0.0.1", 19486, 19487)
      server.run_shell_command("concept x").should eq("Unknown command: concept x. The knowledge base shell is not loaded.")
      server.atomspace.size.should eq(0)
    ensure
      CogServer::Server.shell_factory = factory
    end
    CogServer::Server.shell_factory.should_not be_nil
  end
end
