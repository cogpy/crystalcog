require "spec"
require "socket"
require "../../src/atomspace/distributed_storage"

private def log_node(election_timeout : Time::Span? = nil) : AtomSpace::DistributedAtomSpaceCluster
  node = AtomSpace::DistributedAtomSpaceCluster.new(cluster_id: "log", local_atomspace: AtomSpace::AtomSpace.new,
    host: "127.0.0.1", adaptive_heartbeat_enabled: false)
  node.election_timeout = election_timeout
  node.vote_timeout = 500.milliseconds
  node.replication_timeout = 500.milliseconds
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

private def join_all(nodes) : Nil
  seed = nodes[0].local_node
  nodes[1..].each { |node| node.join_cluster(seed.host, seed.port).should be_true }
  everyone = nodes.map(&.node_id).sort
  settle { nodes.all? { |node| node.cluster_nodes.map(&.id).sort == everyone } }
  nodes.each { |node| node.cluster_nodes.map(&.id).sort.should eq(everyone) }
end

# Started nodes that all know one another.
private def log_nodes(count : Int32, election_timeout : Time::Span? = nil) : Array(AtomSpace::DistributedAtomSpaceCluster)
  nodes = Array.new(count) { log_node(election_timeout) }
  nodes.each(&.start)
  sleep 100.milliseconds
  join_all(nodes)
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

private def entry(term : Int32, text : String)
  {"term" => term, "kind" => "command", "data" => text}
end

# What a leader sends: the entry before the new ones, the new ones, and
# how far the log is committed.
private def append(node, term : Int32, prev_index : Int32, prev_term : Int32, entries, commit : Int32) : JSON::Any
  ask_node(node, {"type" => "log_append", "term" => term, "leader_id" => "a-leader", "prev_index" => prev_index,
                  "prev_term" => prev_term, "entries" => entries, "commit" => commit})
end

# Every command a node applies, with its entry number.
private def applied_on(node) : Array({UInt64, String})
  seen = [] of {UInt64, String}
  node.on_commit { |index, command| seen << {index, command.as_s} }
  seen
end

describe "DistributedAtomSpaceCluster replicated log" do
  it "starts empty" do
    node = log_node
    node.log_size.should eq(0)
    node.commit_index.should eq(0)
    node.last_applied.should eq(0)
    node.committed.should be_empty
    # Nothing can be put to a node that is not running, or follows no one.
    node.propose("x").should be_nil
    node.start
    begin
      node.propose("x").should be_nil
      node.log_size.should eq(0)
    ensure
      node.stop
    end
  end

  it "commits on a node that is alone" do
    node = log_node
    node.start
    begin
      seen = applied_on(node)
      node.start_election.should be_true
      # The leader opened its term with an entry of its own.
      node.log_size.should eq(1)
      node.commit_index.should eq(1)
      node.propose("first").should eq(2)
      node.propose({"set" => "colour", "to" => "red"}).should eq(3)
      node.committed.map(&.to_json).should eq([%("first"), %({"set":"colour","to":"red"})])
      seen.size.should eq(1) # the second command is not a string
      node.last_applied.should eq(3)
      node.log_terms.should eq([1, 1, 1])
    ensure
      node.stop
    end
  end

  it "hands every command to all members, who apply them in the same order" do
    nodes = log_nodes(3)
    begin
      seen = nodes.map { |node| applied_on(node) }
      nodes[0].start_election.should be_true
      %w(a b c d).each_with_index { |command, i| nodes[0].propose(command).should eq(i + 2) }

      settle { nodes.all? { |node| node.last_applied == 5 } }
      nodes.each do |node|
        node.log_size.should eq(5)
        node.commit_index.should eq(5)
        node.committed.map(&.as_s).should eq(["a", "b", "c", "d"])
      end
      seen.each { |applied| applied.should eq([{2_u64, "a"}, {3_u64, "b"}, {4_u64, "c"}, {5_u64, "d"}]) }
      nodes[1].cluster_stats["log_size"].as_i64.should eq(5)
      nodes[1].cluster_stats["commit_index"].as_i64.should eq(5)
      nodes[1].cluster_stats["last_applied"].as_i64.should eq(5)
    ensure
      nodes.each(&.stop)
    end
  end

  it "passes a command put to another member on to the leader" do
    nodes = log_nodes(3)
    begin
      nodes[0].start_election.should be_true
      settle { nodes.all? { |node| node.leader_id == nodes[0].node_id } }
      nodes[1].propose("from the second").should eq(2)
      nodes[2].propose("from the third").should eq(3)
      nodes[0].propose("from the leader").should eq(4)
      # The member that asked has been told by the time it has its answer.
      nodes[1].committed.map(&.as_s).first.should eq("from the second")
      settle { nodes.all? { |node| node.last_applied == 4 } }
      nodes.each { |node| node.committed.map(&.as_s).should eq(["from the second", "from the third", "from the leader"]) }
    ensure
      nodes.each(&.stop)
    end
  end

  it "keeps commands in one order when they are put at the same time" do
    nodes = log_nodes(3)
    begin
      nodes[0].start_election.should be_true
      settle { nodes.all? { |node| node.leader_id == nodes[0].node_id } }
      done = Channel(UInt64?).new(12)
      12.times { |i| spawn { done.send(nodes[i % 3].propose("command #{i}")) } }
      indexes = Array.new(12) { done.receive }
      indexes.compact.sort.should eq((2_u64..13_u64).to_a)

      settle { nodes.all? { |node| node.last_applied == 13 } }
      order = nodes[0].committed.map(&.as_s)
      order.sort.should eq((0...12).map { |i| "command #{i}" }.sort)
      nodes.each { |node| node.committed.map(&.as_s).should eq(order) }
    ensure
      nodes.each(&.stop)
    end
  end

  it "does not commit what fewer than half of the members hold" do
    nodes = log_nodes(3)
    begin
      seen = applied_on(nodes[1])
      nodes[0].start_election.should be_true
      nodes[0].propose("agreed").should eq(2)
      # Four members that cannot be reached: three of seven is not enough.
      4.times do |i|
        tell_node(nodes[0], {"type" => "member_joined", "node" => {"id" => "ghost-#{i}", "host" => "127.0.0.1", "port" => 1, "status" => "Active"}})
      end
      settle { nodes[0].cluster_nodes.size == 7 }

      nodes[0].propose("in doubt").should be_nil
      nodes[0].log_size.should eq(3)
      nodes[0].commit_index.should eq(2)
      # The members that answered hold the entry, uncommitted.
      nodes[1].log_size.should eq(3)
      nodes[1].commit_index.should eq(2)
      seen.should eq([{2_u64, "agreed"}])

      # Once two of the four are gone, three of five hold it.
      2.times { |i| tell_node(nodes[0], {"type" => "cluster_departure", "node_id" => "ghost-#{i}"}) }
      settle { nodes[0].cluster_nodes.size == 5 }
      nodes[0].replicate.should eq(2)
      nodes[0].commit_index.should eq(3)
      settle { nodes[1].last_applied == 3 }
      seen.should eq([{2_u64, "agreed"}, {3_u64, "in doubt"}])
    ensure
      nodes.each(&.stop)
    end
  end

  it "brings a member that joins later up to date" do
    nodes = log_nodes(2)
    late = log_node
    begin
      nodes[0].start_election.should be_true
      %w(a b c).each { |command| nodes[0].propose(command).should_not be_nil }

      late.start
      sleep 100.milliseconds
      seen = applied_on(late)
      late.join_cluster(nodes[0].local_node.host, nodes[0].local_node.port).should be_true
      settle { nodes[0].cluster_nodes.size == 3 }
      nodes[0].replicate.should eq(2)
      late.log_size.should eq(4)
      late.commit_index.should eq(4)
      seen.should eq([{2_u64, "a"}, {3_u64, "b"}, {4_u64, "c"}])
      late.leader_id.should eq(nodes[0].node_id)
      # And it counts from now on.
      nodes[0].propose("d").should eq(5)
      settle { late.last_applied == 5 }
      late.committed.map(&.as_s).should eq(["a", "b", "c", "d"])
    ensure
      nodes.each(&.stop)
      late.stop
    end
  end

  it "lets a new leader settle what the one before left" do
    nodes = log_nodes(3)
    begin
      seen = nodes.map { |node| applied_on(node) }
      nodes[0].start_election.should be_true
      nodes[0].propose("settled").should eq(2)
      # The leader loses its majority, and takes one more entry in.
      4.times do |i|
        tell_node(nodes[0], {"type" => "member_joined", "node" => {"id" => "ghost-#{i}", "host" => "127.0.0.1", "port" => 1, "status" => "Active"}})
      end
      settle { nodes[0].cluster_nodes.size == 7 }
      nodes[0].propose("left over").should be_nil
      nodes[1].commit_index.should eq(2)

      # Another member wins the next term: its opening entry commits, and
      # with it everything before.
      nodes[1].start_election.should be_true
      nodes[1].term.should eq(2)
      nodes[1].log_terms.should eq([1, 1, 1, 2])
      nodes[1].commit_index.should eq(4)
      settle { nodes.all? { |node| node.last_applied == 4 } }
      nodes.each { |node| node.committed.map(&.as_s).should eq(["settled", "left over"]) }
      seen.each { |applied| applied.should eq([{2_u64, "settled"}, {3_u64, "left over"}]) }
      nodes[0].leader?.should be_false

      nodes[1].propose("next").should eq(5)
      nodes[0].propose("through the old leader").should eq(6)
      settle { nodes.all? { |node| node.last_applied == 6 } }
      nodes.each { |node| node.log_terms.should eq([1, 1, 1, 2, 2, 2]) }
    ensure
      nodes.each(&.stop)
    end
  end
end

describe "DistributedAtomSpaceCluster log entries from a leader" do
  it "takes entries that follow what it has, and commits as far as it is told" do
    node = log_node
    node.start
    sleep 100.milliseconds
    begin
      seen = applied_on(node)
      answer = append(node, 1, 0, 0, [entry(1, "one"), entry(1, "two")], 0)
      answer["success"].as_bool.should be_true
      answer["have"].as_i64.should eq(2)
      node.log_size.should eq(2)
      node.commit_index.should eq(0)
      seen.should be_empty
      node.leader_id.should eq("a-leader")
      node.term.should eq(1)

      # No entries, a commit point: what a leader sends to say it is there.
      append(node, 1, 2, 1, [] of String, 1)["success"].as_bool.should be_true
      seen.should eq([{1_u64, "one"}])
      # Never further than this log is known to agree.
      append(node, 1, 2, 1, [entry(1, "three")], 10)["success"].as_bool.should be_true
      node.commit_index.should eq(3)
      seen.should eq([{1_u64, "one"}, {2_u64, "two"}, {3_u64, "three"}])
      # The same entries again change nothing.
      append(node, 1, 0, 0, [entry(1, "one"), entry(1, "two")], 3)["have"].as_i64.should eq(3)
      node.committed.map(&.as_s).should eq(["one", "two", "three"])
      seen.size.should eq(3)
    ensure
      node.stop
    end
  end

  it "refuses entries that do not follow what it has, and says how far it goes" do
    node = log_node
    node.start
    sleep 100.milliseconds
    begin
      append(node, 1, 0, 0, [entry(1, "one"), entry(1, "two")], 0)
      # Entry 5 is not there to be followed.
      gap = append(node, 1, 5, 1, [entry(1, "six")], 0)
      gap["success"].as_bool.should be_false
      gap["have"].as_i64.should eq(2)
      # Entry 2 is there, but from another term.
      other = append(node, 3, 2, 2, [entry(3, "three")], 0)
      other["success"].as_bool.should be_false
      other["have"].as_i64.should eq(1)
      node.log_size.should eq(2)
      node.term.should eq(3)
      # A leader of a term that is over is told the newer one.
      stale = append(node, 2, 2, 1, [entry(2, "three")], 0)
      stale["success"].as_bool.should be_false
      stale["term"].as_i64.should eq(3)
      node.log_size.should eq(2)
    ensure
      node.stop
    end
  end

  it "replaces entries of a leader that did not prevail" do
    node = log_node
    node.start
    sleep 100.milliseconds
    begin
      seen = applied_on(node)
      append(node, 1, 0, 0, [entry(1, "one"), entry(1, "lost"), entry(1, "lost too")], 1)
      seen.should eq([{1_u64, "one"}])
      # The leader of term 2 has another second entry.
      answer = append(node, 2, 1, 1, [entry(2, "two")], 2)
      answer["success"].as_bool.should be_true
      answer["have"].as_i64.should eq(2)
      node.log_terms.should eq([1, 2])
      node.committed.map(&.as_s).should eq(["one", "two"])
      seen.should eq([{1_u64, "one"}, {2_u64, "two"}])
      # What is committed is never replaced.
      refused = append(node, 3, 1, 1, [entry(3, "another two")], 2)
      refused["success"].as_bool.should be_false
      node.committed.map(&.as_s).should eq(["one", "two"])
    ensure
      node.stop
    end
  end

  it "votes only for a candidate whose log is as far along as its own" do
    node = log_node
    node.start
    sleep 100.milliseconds
    begin
      append(node, 3, 0, 0, [entry(2, "one"), entry(3, "two")], 0)
      vote = ->(term : Int32, last_term : Int32, size : Int32) do
        ask_node(node, {"type" => "vote_request", "term" => term, "candidate_id" => "candidate-#{term}",
                        "last_log_term" => last_term, "last_log_index" => size})["granted"].as_bool
      end
      # No log at all, an older last term, the same term and fewer entries.
      ask_node(node, {"type" => "vote_request", "term" => 4, "candidate_id" => "candidate-4"})["granted"].as_bool.should be_false
      vote.call(5, 2, 9).should be_false
      vote.call(6, 3, 1).should be_false
      # The term moved on all the same.
      node.term.should eq(6)
      # As many entries of the same term, or a later last term.
      vote.call(7, 3, 2).should be_true
      vote.call(8, 4, 1).should be_true
    ensure
      node.stop
    end
  end
end

describe "DistributedAtomSpaceCluster atoms through the log" do
  it "gives every member the same atom with the same truth value" do
    nodes = log_nodes(3)
    begin
      nodes[0].start_election.should be_true
      settle { nodes.all? { |node| node.leader_id == nodes[0].node_id } }

      space = nodes[1].local_atomspace
      dog = AtomSpace::Node.new(AtomSpace::AtomType::CONCEPT_NODE, "dog")
      animal = AtomSpace::Node.new(AtomSpace::AtomType::CONCEPT_NODE, "animal")
      link = AtomSpace::InheritanceLink.new(dog, animal, AtomSpace::SimpleTruthValue.new(0.9, 0.5))
      placed = nodes[1].add_atom_in_order(link).not_nil!
      space.contains?(placed).should be_true
      placed.should be_a(AtomSpace::InheritanceLink)

      # Two members say different things about it; the log puts one last.
      nodes[2].add_atom_in_order(AtomSpace::InheritanceLink.new(dog, animal, AtomSpace::SimpleTruthValue.new(0.2, 0.8))).should_not be_nil
      nodes[0].add_atom_in_order(AtomSpace::InheritanceLink.new(dog, animal, AtomSpace::SimpleTruthValue.new(0.7, 0.6))).should_not be_nil

      settle { nodes.all? { |node| node.last_applied == 4 } }
      nodes.each do |node|
        links = node.local_atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
        links.size.should eq(1)
        links.first.outgoing.map(&.name).should eq(["dog", "animal"])
        links.first.truth_value.strength.should be_close(0.7, 1e-9)
        links.first.truth_value.confidence.should be_close(0.6, 1e-9)
        node.local_atomspace.get_nodes_by_name("dog").size.should eq(1)
      end
      # Atoms are not commands.
      nodes[0].committed.should be_empty
      nodes[0].log_size.should eq(4)
    ensure
      nodes.each(&.stop)
    end
  end

  it "is not done without a leader" do
    node = log_node
    node.start
    begin
      node.add_atom_in_order(AtomSpace::Node.new(AtomSpace::AtomType::CONCEPT_NODE, "dog")).should be_nil
      node.local_atomspace.size.should eq(0)
    ensure
      node.stop
    end
  end
end

describe "DistributedAtomSpaceCluster log with automatic election" do
  it "keeps the log through a change of leader" do
    nodes = log_nodes(3, election_timeout: 300.milliseconds)
    begin
      settle(20.seconds) { nodes.count(&.leader?) == 1 && nodes.map(&.leader_id).uniq.size == 1 && !nodes[0].leader_id.nil? }
      first = nodes.find!(&.leader?)
      rest = nodes.reject(&.same?(first))
      rest[0].propose("before").should_not be_nil
      settle { nodes.all? { |node| node.committed.size == 1 } }
      first.stop

      settle(20.seconds) { rest.count(&.leader?) == 1 && rest.map(&.leader_id).uniq.size == 1 && !rest[0].leader_id.nil? }
      second = rest.find!(&.leader?)
      follower = rest.find! { |node| !node.same?(second) }
      # The leader's regular round also carries the log.
      # A try that is not answered in time may still be committed later,
      # so the command can be there more than once.
      index = nil
      settle(10.seconds) { !(index = follower.propose("after")).nil? }
      index.should_not be_nil
      settle { rest.all? { |node| node.committed.last?.try(&.as_s) == "after" && node.last_applied == second.commit_index } }
      rest.each { |node| node.committed.map(&.as_s).uniq.should eq(["before", "after"]) }
      rest[0].committed.should eq(rest[1].committed)
    ensure
      nodes.each(&.stop)
    end
  end
end
