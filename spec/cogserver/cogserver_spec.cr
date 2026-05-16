require "spec"
require "../../src/cogserver/cogserver"

describe CogServer do
  describe "initialization" do
    it "initializes successfully" do
      # This should not raise any exceptions
      CogServer.initialize
    end
  end

  describe "Server" do
    it "creates server with default settings" do
      server = CogServer::Server.new

      server.host.should eq(CogServer::DEFAULT_HOST)
      server.port.should eq(CogServer::DEFAULT_PORT)
      server.ws_port.should eq(CogServer::DEFAULT_WS_PORT)
      server.running?.should be_false
    end

    it "creates server with custom settings" do
      server = CogServer::Server.new("192.168.1.1", 17002, 18082)

      server.host.should eq("192.168.1.1")
      server.port.should eq(17002)
      server.ws_port.should eq(18082)
      server.running?.should be_false
    end

    it "provides server statistics" do
      server = CogServer::Server.new
      stats = server.stats

      stats["running"].should eq(false)
      stats["host"].should eq(CogServer::DEFAULT_HOST)
      stats["port"].should eq(CogServer::DEFAULT_PORT)
      stats["ws_port"].should eq(CogServer::DEFAULT_WS_PORT)
      stats["active_sessions"].should eq(0)
      stats["atomspace_size"].should be_a(UInt64)
      stats["atomspace_nodes"].should be_a(UInt64)
      stats["atomspace_links"].should be_a(UInt64)
    end

    it "has access to atomspace" do
      server = CogServer::Server.new

      server.atomspace.should be_a(AtomSpace::AtomSpace)
      server.atomspace.size.should be_a(UInt64)
    end
  end

  describe "Session" do
    it "creates session with correct attributes" do
      atomspace = AtomSpace::AtomSpace.new
      session = CogServer::Session.new("test123", atomspace, :telnet)

      session.id.should eq("test123")
      session.atomspace.should eq(atomspace)
      session.session_type.should eq(:telnet)
      session.closed?.should be_false
      session.created_at.should be_a(Time)
      session.duration.should be >= Time::Span.zero
    end

    it "can be closed" do
      atomspace = AtomSpace::AtomSpace.new
      session = CogServer::Session.new("test456", atomspace, :websocket)

      session.close
      session.closed?.should be_true
    end

    it "tracks session duration" do
      atomspace = AtomSpace::AtomSpace.new
      session = CogServer::Session.new("test789", atomspace, :http)

      sleep 0.01.seconds # Small delay to ensure duration > 0
      session.duration.should be > Time::Span.zero
    end
  end

  describe "exception classes" do
    it "defines CogServerException" do
      ex = CogServer::CogServerException.new("test")
      ex.should be_a(CogUtil::OpenCogException)
      ex.message.should eq("test")
    end

    it "defines NetworkException" do
      ex = CogServer::NetworkException.new("network error")
      ex.should be_a(CogServer::CogServerException)
      ex.message.should eq("network error")
    end

    it "defines SessionException" do
      ex = CogServer::SessionException.new("session error")
      ex.should be_a(CogServer::CogServerException)
      ex.message.should eq("session error")
    end
  end
end
