require "spec"
require "../../src/cogserver/cogserver_main"

describe "CogServer Main" do
  describe "initialization" do
    it "initializes CogServer system" do
      CogServer.initialize
      # Should not crash
    end

    it "has correct version" do
      CogServer::VERSION.should eq("0.1.0")
    end

    it "creates server instance" do
      server = CogServer::Server.new("localhost", 17001, 18080)
      server = CogServer::Server.new
      server.should be_a(CogServer::Server)
    end
  end

  describe "server configuration" do
    it "configures default port" do
      CogServer::DEFAULT_PORT.should eq(17001)
    end

    it "configures default WebSocket port" do
      CogServer::DEFAULT_WS_PORT.should eq(18080)
    end

    it "configures default host" do
      CogServer::DEFAULT_HOST.should eq("localhost")
    end
  end

  describe "main entry point" do
    it "has main function" do
      # The main function should be callable
      CogServer.responds_to?(:main).should be_true
  describe "system integration" do
    it "integrates with AtomSpace" do
      CogUtil.initialize
      AtomSpace.initialize
      CogServer.initialize

      # Should be able to create server with atomspace
      server = CogServer::Server.new
      server.should_not be_nil
      server.atomspace.should be_a(AtomSpace::AtomSpace)
    end

    it "provides server statistics" do
      server = CogServer::Server.new
      stats = server.stats
      
      stats.should be_a(Hash(String, Int32 | String | Bool | UInt64))
      stats["running"].should be_a(Bool)
      stats["host"].should be_a(String)
      stats["port"].should be_a(Int32)
    end
  end
end
