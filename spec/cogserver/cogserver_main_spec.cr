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
    end
  end
end
