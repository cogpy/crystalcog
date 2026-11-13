require "../spec_helper"
require "http/server"
require "../../src/integrations/ipfs_integration"

# Stands in for a Kubo daemon's pubsub RPC: /pub fans a message out to
# every open /sub stream of the same topic, as the real daemon does.
private class StubKubo
  getter published = [] of {String, String}
  getter port : Int32

  def initialize
    @streams = Hash(String, Array(Channel(String))).new { |h, k| h[k] = [] of Channel(String) }
    @server = HTTP::Server.new do |ctx|
      topic_arg = ctx.request.query_params["arg"]? || ""
      case ctx.request.path
      when "/api/v0/pubsub/pub"
        message = ""
        HTTP::FormData.parse(ctx.request) { |part| message = part.body.gets_to_end }
        @published << {topic_arg, message}
        @streams[topic_arg].each(&.send(message))
      when "/api/v0/pubsub/sub"
        inbox = Channel(String).new(16)
        @streams[topic_arg] << inbox
        ctx.response.content_type = "application/json"
        ctx.response.print("not json\n") # a daemon hiccup must not end the stream
        ctx.response.flush
        begin
          while message = inbox.receive?
            ctx.response.print({"from" => "12D3KooWStub", "data" => "u" + Base64.urlsafe_encode(message, padding: false),
                                "seqno" => "uAA", "topicIDs" => [topic_arg]}.to_json + "\n")
            ctx.response.flush
          end
        rescue IO::Error
        ensure
          @streams[topic_arg].delete(inbox)
        end
      when "/api/v0/pubsub/ls"
        ctx.response.print({"Strings" => @streams.select { |_, s| !s.empty? }.keys}.to_json)
      else
        ctx.response.status_code = 404
      end
    end
    @port = @server.bind_tcp("127.0.0.1", 0).port
    spawn { @server.listen }
    Fiber.yield
  end

  def close
    @streams.each_value(&.each(&.close))
    @server.close
  end
end

# The subscription stream opens in a fiber; poll until the daemon has it.
private def wait_until(limit : Time::Span = 10.seconds, &) : Nil
  deadline = Time.monotonic + limit
  until yield
    break if Time.monotonic > deadline
    sleep 10.milliseconds
  end
end

private def receive_within(channel : Channel(T), span = 5.seconds) : T forall T
  select
  when value = channel.receive
    value
  when timeout(span)
    raise "nothing received within #{span}"
  end
end

describe CrystalCog::Integrations::IPFSPubsub do
  it "encodes topics and payloads as multibase base64url" do
    client = CrystalCog::Integrations::IPFSClient
    client.multibase("crystalcog/sync").should eq("uY3J5c3RhbGNvZy9zeW5j")
    String.new(client.multibase_decode("uY3J5c3RhbGNvZy9zeW5j")).should eq("crystalcog/sync")
    String.new(client.multibase_decode(client.multibase("héllo ?>"))).should eq("héllo ?>")
    expect_raises(ArgumentError, /multibase/) { client.multibase_decode("zabc") }
  end

  it "publishes to the daemon and receives what peers publish" do
    kubo = StubKubo.new
    begin
      config = CrystalCog::Integrations::IPFSConfig.new(api_host: "127.0.0.1", api_port: kubo.port, timeout: 5.seconds)
      client = CrystalCog::Integrations::IPFSClient.new(config)
      pubsub = CrystalCog::Integrations::IPFSPubsub.new(client)

      received = Channel(String).new(8)
      pubsub.subscribe("crystalcog/test") { |message| received.send(message) }
      wait_until { client.pubsub_topics == ["crystalcog/test"] }
      pubsub.subscribed?("crystalcog/test").should be_true
      client.pubsub_topics.should eq(["crystalcog/test"])

      pubsub.publish("crystalcog/test", %({"cid": "Qm123"})).should be_true
      receive_within(received).should eq(%({"cid": "Qm123"}))
      pubsub.publish("crystalcog/other", "elsewhere").should be_true
      pubsub.publish("crystalcog/test", "second ünïcode").should be_true
      receive_within(received).should eq("second ünïcode")
      kubo.published.map(&.[0]).should eq(["uY3J5c3RhbGNvZy90ZXN0", "uY3J5c3RhbGNvZy9vdGhlcg", "uY3J5c3RhbGNvZy90ZXN0"])

      pubsub.unsubscribe("crystalcog/test")
      pubsub.subscribed?("crystalcog/test").should be_false
      # The stream is closed: later messages no longer arrive.
      pubsub.publish("crystalcog/test", "after unsubscribe")
      select
      when late = received.receive
        fail "received #{late.inspect} after unsubscribing"
      when timeout(300.milliseconds)
      end
    ensure
      kubo.close
    end
  end

  it "reports failure when no daemon is listening" do
    config = CrystalCog::Integrations::IPFSConfig.new(api_host: "127.0.0.1", api_port: 1, timeout: 1.second)
    pubsub = CrystalCog::Integrations::IPFSPubsub.new(CrystalCog::Integrations::IPFSClient.new(config))
    pubsub.publish("topic", "message").should be_false
  end

  it "carries AtomSpace sync announcements between two nodes" do
    kubo = StubKubo.new
    begin
      config = CrystalCog::Integrations::IPFSConfig.new(api_host: "127.0.0.1", api_port: kubo.port, timeout: 5.seconds)
      make_sync = -> do
        client = CrystalCog::Integrations::IPFSClient.new(config)
        CrystalCog::Integrations::IPFSAtomSpaceSync.new(CrystalCog::Integrations::IPFSAtomSpaceStorage.new(client, "shared"), client)
      end
      listener = make_sync.call
      announcer = make_sync.call
      updates = Channel(String).new(4)
      listener.start_sync { |cid| updates.send(cid.hash) }
      probe = CrystalCog::Integrations::IPFSClient.new(config)
      wait_until { probe.pubsub_topics.size == 1 }

      announcer.broadcast_update(CrystalCog::Integrations::IPFSCid.new("QmSnapshot42"))
      receive_within(updates).should eq("QmSnapshot42")
      listener.stop_sync
    ensure
      kubo.close
    end
  end
end
