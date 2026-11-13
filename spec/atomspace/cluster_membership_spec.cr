require "spec"
require "socket"
require "../../src/atomspace/distributed_storage"

private def cluster_node(id : String = "members") : AtomSpace::DistributedAtomSpaceCluster
  AtomSpace::DistributedAtomSpaceCluster.new(cluster_id: id, local_atomspace: AtomSpace::AtomSpace.new,
    host: "127.0.0.1", adaptive_heartbeat_enabled: false)
end

# Cluster messages travel over real sockets; wait for the block to hold.
private def settle(limit : Time::Span = 10.seconds, &) : Nil
  deadline = Time.monotonic + limit
  until yield
    break if Time.monotonic > deadline
    sleep 20.milliseconds
  end
end

private def member_ids(node) : Array(String)
  node.cluster_nodes.map(&.id).sort
end

private def send_line(node, message) : Nil
  socket = TCPSocket.new(node.local_node.host, node.local_node.port)
  socket.puts(message.to_json)
  socket.close
end

describe "DistributedAtomSpaceCluster membership" do
  it "tells earlier members about a node that joins later" do
    nodes = Array.new(3) { cluster_node }
    nodes.each(&.start)
    begin
      sleep 100.milliseconds
      seed = nodes[0].local_node
      joined = [] of String
      nodes[1].add_event_observer(->(event : AtomSpace::ClusterEvent, id : String) {
        joined << id if event == AtomSpace::ClusterEvent::NODE_JOINED
        nil
      })

      nodes[1].join_cluster(seed.host, seed.port).should be_true
      nodes[2].join_cluster(seed.host, seed.port).should be_true

      everyone = nodes.map(&.node_id).sort
      settle { nodes.all? { |node| member_ids(node) == everyone } }
      nodes.each { |node| member_ids(node).should eq(everyone) }
      # The second node heard of the third from the seed's announcement.
      joined.should contain(nodes[2].node_id)
      third = nodes[1].cluster_nodes.find!(&.id.==(nodes[2].node_id))
      third.port.should eq(nodes[2].local_node.port)
    ensure
      nodes.each(&.stop)
    end
  end

  it "spreads a join made through a node that is not the first seed" do
    nodes = Array.new(3) { cluster_node }
    nodes.each(&.start)
    begin
      sleep 100.milliseconds
      nodes[1].join_cluster(nodes[0].local_node.host, nodes[0].local_node.port).should be_true
      settle { member_ids(nodes[0]).size == 2 }
      # The third node only ever talks to the second.
      nodes[2].join_cluster(nodes[1].local_node.host, nodes[1].local_node.port).should be_true

      everyone = nodes.map(&.node_id).sort
      settle { nodes.all? { |node| member_ids(node) == everyone } }
      nodes.each { |node| member_ids(node).should eq(everyone) }
    ensure
      nodes.each(&.stop)
    end
  end

  it "drops a member that leaves and is not talked back into listing it" do
    nodes = Array.new(3) { cluster_node }
    nodes.each(&.start)
    begin
      sleep 100.milliseconds
      seed = nodes[0].local_node
      nodes[1].join_cluster(seed.host, seed.port).should be_true
      nodes[2].join_cluster(seed.host, seed.port).should be_true
      everyone = nodes.map(&.node_id).sort
      settle { nodes.all? { |node| member_ids(node) == everyone } }

      leaver = nodes[2]
      leaver_record = {"id" => leaver.node_id, "host" => leaver.local_node.host, "port" => leaver.local_node.port}
      leaver.stop
      remaining = [nodes[0].node_id, nodes[1].node_id].sort
      settle { member_ids(nodes[0]) == remaining && member_ids(nodes[1]) == remaining }
      member_ids(nodes[0]).should eq(remaining)
      member_ids(nodes[1]).should eq(remaining)

      # A member list written before the departure still names the leaver.
      send_line(nodes[0], {"type" => "member_joined", "source_node" => nodes[1].node_id, "members" => [leaver_record]})
      sleep 200.milliseconds
      member_ids(nodes[0]).should eq(remaining)
    ensure
      nodes.each(&.stop)
    end
  end

  it "learns a node from its heartbeat and from the members a heartbeat lists" do
    node = cluster_node
    node.start
    begin
      sleep 100.milliseconds
      send_line(node, {
        "type" => "heartbeat", "node_id" => "beat-1", "host" => "127.0.0.1", "port" => 41001,
        "status" => "Active", "atomspace_size" => 12, "load_factor" => 0.25,
        "members" => [
          {"id" => "beat-2", "host" => "127.0.0.1", "port" => 41002, "status" => "Active", "atomspace_size" => 3},
          {"id" => node.node_id, "host" => "127.0.0.1", "port" => 1}, # itself: ignored
          {"id" => "broken"},                                         # no address: ignored
        ],
      })
      settle { node.cluster_nodes.size == 3 }
      member_ids(node).should eq(["beat-1", "beat-2", node.node_id].sort)
      sender = node.cluster_nodes.find!(&.id.==("beat-1"))
      sender.port.should eq(41001)
      sender.atomspace_size.should eq(12)
      sender.load_factor.should eq(0.25)
      node.local_node.port.should_not eq(1)
    ensure
      node.stop
    end
  end

  it "refuses a node from another cluster and announces nothing" do
    home = cluster_node("home")
    member = cluster_node("home")
    stranger = cluster_node("elsewhere")
    [home, member, stranger].each(&.start)
    begin
      sleep 100.milliseconds
      member.join_cluster(home.local_node.host, home.local_node.port).should be_true
      stranger.join_cluster(home.local_node.host, home.local_node.port).should be_false
      sleep 200.milliseconds
      member_ids(home).should eq([home.node_id, member.node_id].sort)
      member_ids(member).should eq([home.node_id, member.node_id].sort)
      member_ids(stranger).should eq([stranger.node_id])
    ensure
      [home, member, stranger].each(&.stop)
    end
  end
end
