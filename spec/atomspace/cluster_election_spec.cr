require "spec"
require "socket"
require "../../src/atomspace/distributed_storage"

private def election_node(election_timeout : Time::Span? = nil) : AtomSpace::DistributedAtomSpaceCluster
  node = AtomSpace::DistributedAtomSpaceCluster.new(cluster_id: "election", local_atomspace: AtomSpace::AtomSpace.new,
    host: "127.0.0.1", adaptive_heartbeat_enabled: false)
  node.election_timeout = election_timeout
  node.vote_timeout = 500.milliseconds
  node
end

# Cluster messages travel over real sockets; wait for the block to hold.
private def settle(limit : Time::Span = 10.seconds, &) : Nil
  deadline = Time.monotonic + limit
  until yield
    break if Time.monotonic > deadline
    sleep 20.milliseconds
  end
end

# Started nodes that all know one another.
private def joined_nodes(count : Int32, election_timeout : Time::Span? = nil) : Array(AtomSpace::DistributedAtomSpaceCluster)
  nodes = Array.new(count) { election_node(election_timeout) }
  nodes.each(&.start)
  sleep 100.milliseconds
  seed = nodes[0].local_node
  nodes[1..].each { |node| node.join_cluster(seed.host, seed.port).should be_true }
  everyone = nodes.map(&.node_id).sort
  settle { nodes.all? { |node| node.cluster_nodes.map(&.id).sort == everyone } }
  nodes.each { |node| node.cluster_nodes.map(&.id).sort.should eq(everyone) }
  nodes
end

# One JSON line to a node, and its one-line answer.
private def ask_node(node, message) : JSON::Any
  socket = TCPSocket.new(node.local_node.host, node.local_node.port)
  begin
    socket.read_timeout = 5.seconds
    socket.puts(message.to_json)
    JSON.parse(socket.gets.not_nil!)
  ensure
    socket.close
  end
end

private def tell_node(node, message) : Nil
  socket = TCPSocket.new(node.local_node.host, node.local_node.port)
  socket.puts(message.to_json)
  socket.close
end

describe "DistributedAtomSpaceCluster leader election" do
  it "starts every node as a follower of no one, in term 0" do
    node = election_node
    node.term.should eq(0)
    node.role.should eq(AtomSpace::ClusterRole::Follower)
    node.leader_id.should be_nil
    node.leader?.should be_false
    # A node that is not running cannot stand.
    node.start_election.should be_false
    node.term.should eq(0)
  end

  it "elects the node that stands, and tells the others" do
    nodes = joined_nodes(3)
    begin
      nodes[0].start_election.should be_true
      nodes[0].leader?.should be_true
      nodes[0].term.should eq(1)
      nodes[0].leader_id.should eq(nodes[0].node_id)

      settle { nodes.all? { |node| node.leader_id == nodes[0].node_id } }
      nodes.each do |node|
        node.leader_id.should eq(nodes[0].node_id)
        node.term.should eq(1)
      end
      nodes[1].role.should eq(AtomSpace::ClusterRole::Follower)
      nodes[2].leader.not_nil!.port.should eq(nodes[0].local_node.port)
      nodes[1].cluster_stats["leader_id"].as_s.should eq(nodes[0].node_id)
      nodes[1].cluster_stats["term"].as_i64.should eq(1)
      nodes[0].cluster_stats["role"].as_s.should eq("Leader")
    ensure
      nodes.each(&.stop)
    end
  end

  it "replaces the leader when another node wins a later term" do
    nodes = joined_nodes(3)
    begin
      lost = [] of String
      nodes[2].add_event_observer(->(event : AtomSpace::ClusterEvent, id : String) {
        lost << id if event == AtomSpace::ClusterEvent::LEADER_LOST
        nil
      })
      nodes[0].start_election.should be_true
      settle { nodes.all? { |node| node.leader_id == nodes[0].node_id } }

      nodes[1].start_election.should be_true
      nodes[1].term.should eq(2)
      settle { nodes.all? { |node| node.leader_id == nodes[1].node_id } }
      nodes.each { |node| node.leader_id.should eq(nodes[1].node_id) }
      # The old leader gave way to the higher term.
      nodes[0].leader?.should be_false
      nodes[0].role.should eq(AtomSpace::ClusterRole::Follower)
      nodes[0].term.should eq(2)
      nodes.count(&.leader?).should eq(1)
      lost.should eq([nodes[0].node_id])
    ensure
      nodes.each(&.stop)
    end
  end

  it "gives one vote in a term, to whoever asks first" do
    nodes = joined_nodes(2)
    begin
      voter = nodes[1]
      first = ask_node(voter, {"type" => "vote_request", "term" => 5, "candidate_id" => "candidate-a"})
      first["granted"].as_bool.should be_true
      first["term"].as_i64.should eq(5)
      # The same candidate may ask again; another may not have the vote.
      ask_node(voter, {"type" => "vote_request", "term" => 5, "candidate_id" => "candidate-a"})["granted"].as_bool.should be_true
      ask_node(voter, {"type" => "vote_request", "term" => 5, "candidate_id" => "candidate-b"})["granted"].as_bool.should be_false
      # A candidate of an older term is refused and told the newer one.
      stale = ask_node(voter, {"type" => "vote_request", "term" => 3, "candidate_id" => "candidate-c"})
      stale["granted"].as_bool.should be_false
      stale["term"].as_i64.should eq(5)
      # A newer term is a new vote.
      ask_node(voter, {"type" => "vote_request", "term" => 6, "candidate_id" => "candidate-b"})["granted"].as_bool.should be_true
      voter.term.should eq(6)
    ensure
      nodes.each(&.stop)
    end
  end

  it "does not follow a leader of a term that is over" do
    nodes = joined_nodes(2)
    begin
      nodes[0].start_election.should be_true
      settle { nodes[1].leader_id == nodes[0].node_id }
      nodes[0].start_election.should be_true # term 2
      settle { nodes[1].term == 2 }

      tell_node(nodes[1], {"type" => "leader_announce", "term" => 1, "leader_id" => "someone-else"})
      sleep 100.milliseconds
      nodes[1].leader_id.should eq(nodes[0].node_id)
      nodes[1].term.should eq(2)
    ensure
      nodes.each(&.stop)
    end
  end

  it "needs more than half of the members" do
    nodes = joined_nodes(2)
    begin
      # Two members that cannot be reached: one vote of four is not enough.
      2.times do |i|
        tell_node(nodes[0], {"type" => "member_joined", "node" => {"id" => "ghost-#{i}", "host" => "127.0.0.1", "port" => 1, "status" => "Active"}})
      end
      settle { nodes[0].cluster_nodes.size == 4 }
      nodes[0].cluster_nodes.size.should eq(4)

      # Its own vote and the second node's make two of four: not a majority.
      nodes[0].start_election.should be_false
      nodes[0].leader?.should be_false
      nodes[0].role.should eq(AtomSpace::ClusterRole::Follower)
      nodes[0].leader_id.should be_nil
      nodes[0].term.should eq(1)
    ensure
      nodes.each(&.stop)
    end
  end

  it "elects with a member down, as long as most answer" do
    nodes = joined_nodes(3)
    begin
      # The third node dies without saying so: it is still a member.
      tell_node(nodes[0], {"type" => "member_joined", "node" => {"id" => "ghost", "host" => "127.0.0.1", "port" => 1, "status" => "Active"}})
      settle { nodes[0].cluster_nodes.size == 4 }
      # Three of four answer.
      nodes[0].start_election.should be_true
      nodes[0].leader?.should be_true
    ensure
      nodes.each(&.stop)
    end
  end

  it "forgets a leader that leaves" do
    nodes = joined_nodes(3)
    begin
      nodes[0].start_election.should be_true
      settle { nodes.all? { |node| node.leader_id == nodes[0].node_id } }
      nodes[0].stop
      settle { nodes[1].leader_id.nil? && nodes[2].leader_id.nil? }
      nodes[1].leader_id.should be_nil
      nodes[2].leader_id.should be_nil
      # The two that are left can choose again.
      nodes[2].start_election.should be_true
      settle { nodes[1].leader_id == nodes[2].node_id }
      nodes[1].leader_id.should eq(nodes[2].node_id)
    ensure
      nodes.each(&.stop)
    end
  end
end

describe "DistributedAtomSpaceCluster automatic election" do
  it "chooses one leader by itself and all agree on it" do
    nodes = joined_nodes(3, election_timeout: 300.milliseconds)
    begin
      settle(20.seconds) { nodes.count(&.leader?) == 1 && nodes.map(&.leader_id).uniq.size == 1 && !nodes[0].leader_id.nil? }
      nodes.count(&.leader?).should eq(1)
      leader = nodes.find!(&.leader?)
      nodes.each { |node| node.leader_id.should eq(leader.node_id) }
      # It stays leader: its announcements keep the others from standing.
      term = leader.term
      sleep 1.5.seconds
      leader.leader?.should be_true
      leader.term.should eq(term)
    ensure
      nodes.each(&.stop)
    end
  end

  it "chooses a new leader when the leader leaves" do
    nodes = joined_nodes(3, election_timeout: 300.milliseconds)
    begin
      settle(20.seconds) { nodes.count(&.leader?) == 1 && nodes.map(&.leader_id).uniq.size == 1 && !nodes[0].leader_id.nil? }
      first = nodes.find!(&.leader?)
      rest = nodes.reject(&.same?(first))
      first.stop

      settle(20.seconds) { rest.count(&.leader?) == 1 && rest.map(&.leader_id).uniq.size == 1 && !rest[0].leader_id.nil? }
      rest.count(&.leader?).should eq(1)
      second = rest.find!(&.leader?)
      second.node_id.should_not eq(first.node_id)
      rest.each { |node| node.leader_id.should eq(second.node_id) }
      second.term.should be > first.term
    ensure
      nodes.each(&.stop)
    end
  end
end
