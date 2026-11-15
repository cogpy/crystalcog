require "spec"
require "socket"
require "../../src/atomspace/distributed_storage"

private def durable_node(path : String?) : AtomSpace::DistributedAtomSpaceCluster
  node = AtomSpace::DistributedAtomSpaceCluster.new(cluster_id: "durable", local_atomspace: AtomSpace::AtomSpace.new,
    host: "127.0.0.1", adaptive_heartbeat_enabled: false, state_path: path)
  node.vote_timeout = 500.milliseconds
  node.replication_timeout = 500.milliseconds
  node
end

# A state file of its own for each member, removed afterwards.
private def with_state_files(count : Int32, &)
  paths = Array.new(count) { File.tempname("cluster-state", ".journal") }
  begin
    yield paths
  ensure
    paths.each do |path|
      File.delete(path) if File.exists?(path)
      File.delete("#{path}.tmp") if File.exists?("#{path}.tmp")
    end
  end
end

private def settle(limit : Time::Span = 10.seconds, &) : Nil
  deadline = Time.monotonic + limit
  until yield
    break if Time.monotonic > deadline
    sleep 20.milliseconds
  end
end

private def started(node)
  node.start
  sleep 100.milliseconds
  node
end

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

private def entry(term : Int32, text : String)
  {"term" => term, "kind" => "command", "data" => text}
end

private def append(node, term : Int32, prev_index : Int32, prev_term : Int32, entries, commit : Int32) : JSON::Any
  ask_node(node, {"type" => "log_append", "term" => term, "leader_id" => "a-leader", "prev_index" => prev_index,
                  "prev_term" => prev_term, "entries" => entries, "commit" => commit})
end

private def applied_on(node) : Array({UInt64, String})
  seen = [] of {UInt64, String}
  node.on_commit { |index, command| seen << {index, command.as_s} }
  seen
end

describe "DistributedAtomSpaceCluster kept state" do
  it "is the same member after a restart" do
    with_state_files(1) do |paths|
      first = durable_node(paths[0])
      first.state_path.should eq(paths[0])
      File.exists?(paths[0]).should be_true
      second = durable_node(paths[0])
      second.node_id.should eq(first.node_id)
      second.term.should eq(0)
      second.log_size.should eq(0)
      # Without a state path every member is a new one.
      durable_node(nil).node_id.should_not eq(first.node_id)
      durable_node(nil).state_path.should be_nil
    end
  end

  it "stays bound by the vote it gave" do
    with_state_files(1) do |paths|
      voter = started(durable_node(paths[0]))
      ask_node(voter, {"type" => "vote_request", "term" => 5, "candidate_id" => "candidate-a"})["granted"].as_bool.should be_true
      voter.stop

      back = started(durable_node(paths[0]))
      begin
        back.term.should eq(5)
        # The vote of term 5 is given: another candidate may not have it.
        ask_node(back, {"type" => "vote_request", "term" => 5, "candidate_id" => "candidate-b"})["granted"].as_bool.should be_false
        ask_node(back, {"type" => "vote_request", "term" => 5, "candidate_id" => "candidate-a"})["granted"].as_bool.should be_true
        ask_node(back, {"type" => "vote_request", "term" => 6, "candidate_id" => "candidate-b"})["granted"].as_bool.should be_true
      ensure
        back.stop
      end
      durable_node(paths[0]).term.should eq(6)
    end
  end

  it "remembers a term it only heard of" do
    with_state_files(1) do |paths|
      node = started(durable_node(paths[0]))
      # A candidate of term 9 whose log is too short gets no vote, but the term is known now.
      append(node, 3, 0, 0, [entry(3, "one")], 0)
      ask_node(node, {"type" => "vote_request", "term" => 9, "candidate_id" => "candidate"})["granted"].as_bool.should be_false
      node.stop
      back = durable_node(paths[0])
      back.term.should eq(9)
      back.log_terms.should eq([3])
    end
  end

  it "comes back with its log, and applies it again once it is known to be committed" do
    with_state_files(1) do |paths|
      node = started(durable_node(paths[0]))
      node.start_election.should be_true
      node.propose("a").should eq(2)
      node.propose("b").should eq(3)
      node.stop

      back = durable_node(paths[0])
      seen = applied_on(back)
      back.log_size.should eq(3)
      back.log_terms.should eq([1, 1, 1])
      back.term.should eq(1)
      # What is committed is learned again from a leader, here itself.
      back.commit_index.should eq(0)
      back.committed.should be_empty
      started(back)
      begin
        back.start_election.should be_true
        back.term.should eq(2)
        back.log_terms.should eq([1, 1, 1, 2])
        back.committed.map(&.as_s).should eq(["a", "b"])
        seen.should eq([{2_u64, "a"}, {3_u64, "b"}])
        back.propose("c").should eq(5)
      ensure
        back.stop
      end
      durable_node(paths[0]).log_size.should eq(5)
    end
  end

  it "keeps what a leader put in place of another leader's entries" do
    with_state_files(1) do |paths|
      node = started(durable_node(paths[0]))
      append(node, 1, 0, 0, [entry(1, "one"), entry(1, "lost"), entry(1, "lost too")], 1)
      append(node, 2, 1, 1, [entry(2, "two")], 1)["success"].as_bool.should be_true
      node.log_terms.should eq([1, 2])
      node.stop

      back = started(durable_node(paths[0]))
      begin
        seen = applied_on(back)
        back.log_terms.should eq([1, 2])
        back.term.should eq(2)
        append(back, 2, 2, 2, [entry(2, "three")], 3)["success"].as_bool.should be_true
        seen.should eq([{1_u64, "one"}, {2_u64, "two"}, {3_u64, "three"}])
      ensure
        back.stop
      end
    end
  end

  it "writes the journal afresh when it is read, and passes over a torn last line" do
    with_state_files(1) do |paths|
      node = started(durable_node(paths[0]))
      append(node, 1, 0, 0, [entry(1, "one"), entry(1, "lost")], 0)
      append(node, 2, 1, 1, [entry(2, "two")], 0)
      append(node, 3, 2, 2, [entry(3, "three")], 0)
      node.stop
      # Id, terms heard, entries taken and a cut: more lines than the state needs.
      File.read_lines(paths[0]).size.should be > 5
      File.open(paths[0], "a") { |file| file.print(%({"entry":{"term":3,"kind":"comm)) }

      back = durable_node(paths[0])
      back.node_id.should eq(node.node_id)
      back.log_terms.should eq([1, 2, 3])
      back.term.should eq(3)
      lines = File.read_lines(paths[0])
      lines.size.should eq(5)
      JSON.parse(lines[0])["node_id"].as_s.should eq(node.node_id)
      JSON.parse(lines[1])["term"].as_i64.should eq(3)
      lines[2..].map { |line| JSON.parse(line)["entry"]["data"].as_s }.should eq(["one", "two", "three"])
    end
  end

  it "rejoins as the member it was and is brought up to date" do
    with_state_files(3) do |paths|
      nodes = paths.map { |path| started(durable_node(path)) }
      everyone = nodes.map(&.node_id).sort
      begin
        seed = nodes[0].local_node
        nodes[1..].each { |node| node.join_cluster(seed.host, seed.port).should be_true }
        settle { nodes.all? { |node| node.cluster_nodes.map(&.id).sort == everyone } }
        nodes[0].start_election.should be_true
        nodes[0].propose("x").should eq(2)
        nodes[0].propose("y").should eq(3)
        settle { nodes[2].last_applied == 3 }

        # The third member goes away; the two that are left carry on.
        nodes[2].stop
        settle { nodes[0].cluster_nodes.size == 2 }
        nodes[0].propose("z").should eq(4)

        back = durable_node(paths[2])
        back.node_id.should eq(nodes[2].node_id)
        back.log_size.should eq(3)
        seen = applied_on(back)
        nodes[2] = started(back)
        back.join_cluster(seed.host, seed.port).should be_true
        settle { nodes[0].cluster_nodes.size == 3 }
        nodes[0].cluster_nodes.map(&.id).sort.should eq(everyone)

        nodes[0].replicate.should eq(2)
        back.log_size.should eq(4)
        back.leader_id.should eq(nodes[0].node_id)
        seen.should eq([{2_u64, "x"}, {3_u64, "y"}, {4_u64, "z"}])
        # It counts toward the majority again, and can lead: its log is as long as any.
        back.start_election.should be_true
        back.propose("after").should eq(6)
        settle { nodes.all? { |node| node.last_applied == 6 } }
        nodes.each { |node| node.committed.map(&.as_s).should eq(["x", "y", "z", "after"]) }
      ensure
        nodes.each(&.stop)
      end
    end
  end
end
