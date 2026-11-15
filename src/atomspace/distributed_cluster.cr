# Crystal implementation of Distributed AtomSpace Clustering and Synchronization
# This module provides multi-node AtomSpace clustering with automatic synchronization,
# conflict resolution, and load balancing capabilities.
#
# Based on OpenCog's distributed AtomSpace concepts and the existing Crystal
# Agent-Zero distributed networking infrastructure.

require "./atomspace"
require "./storage"
require "../agent-zero/distributed_agents"
require "../cogutil/cogutil"
require "socket"
require "json"
require "uuid"

module AtomSpace
  # Events emitted by the distributed cluster
  enum ClusterEvent
    NODE_JOINED
    NODE_LEFT
    SYNC_STARTED
    SYNC_COMPLETED
    CONFLICT_DETECTED
    CONFLICT_RESOLVED
    PARTITION_REBALANCED
    # A node learned who leads the cluster; the id is the leader's.
    LEADER_ELECTED
    # The leader a node followed left or was replaced; the id is the old leader's.
    LEADER_LOST
  end

  # One entry of a cluster's replicated log: the term of the leader that
  # took it in, what kind of entry it is, and what it carries. A "command"
  # is something a member proposed, an "atom" an atom to be placed in
  # every member's AtomSpace, and a "term" entry is the one a new leader
  # opens its term with.
  record ClusterLogEntry, term : UInt64, kind : String, data : JSON::Any do
    def to_h : Hash(String, JSON::Any)
      {"term" => JSON::Any.new(term.to_i64), "kind" => JSON::Any.new(kind), "data" => data}
    end

    def self.from(raw : JSON::Any) : ClusterLogEntry
      new(raw["term"].as_i64.to_u64, raw["kind"].as_s, raw["data"])
    end
  end

  # What a node is in the election of a leader.
  enum ClusterRole
    Follower
    Candidate
    Leader
  end

  # Cluster node status
  enum NodeStatus
    Initializing
    Active
    Synchronizing
    Degraded
    Offline
    Failed
  end

  # Synchronization strategy for resolving conflicts
  enum SyncStrategy
    LastWriteWins
    MergeUsingTruthValues
    VectorClock
    ConsensusVoting
  end

  # Information about a cluster node
  class ClusterNodeInfo
    property id : String
    property host : String
    property port : Int32
    property status : NodeStatus
    property last_heartbeat : Time
    property atomspace_size : UInt64
    property load_factor : Float64
    property data_partitions : Array(String)

    def initialize(@id : String, @host : String, @port : Int32)
      @status = NodeStatus::Initializing
      @last_heartbeat = Time.utc
      @atomspace_size = 0_u64
      @load_factor = 0.0
      @data_partitions = [] of String
    end

    def is_stale?(threshold_seconds : Int32 = 60) : Bool
      (Time.utc - @last_heartbeat).total_seconds > threshold_seconds
    end

    def update_heartbeat
      @last_heartbeat = Time.utc
    end
  end

  # Represents a sync operation between nodes
  struct SyncOperation
    property id : String
    property source_node : String
    property target_node : String
    property operation_type : String # "add", "update", "remove"
    property atom_handle : String
    property atom_data : Hash(String, JSON::Any)?
    property timestamp : Time
    property vector_clock : Hash(String, UInt64)?

    def initialize(@operation_type : String, @atom_handle : String, @source_node : String, @target_node : String = "*")
      @id = UUID.random.to_s
      @timestamp = Time.utc
      @atom_data = nil
      @vector_clock = nil
    end
  end

  # Adaptive heartbeat configuration for reducing network overhead by 20-30%
  class AdaptiveHeartbeatConfig
    property base_interval : Time::Span
    property min_interval : Time::Span
    property max_interval : Time::Span
    property current_interval : Time::Span
    property stability_threshold : Int32 # Number of stable cycles before increasing interval
    property stable_cycles : Int32
    property last_cluster_change : Time
    property enabled : Bool

    def initialize(
      @base_interval : Time::Span = 30.seconds,
      @min_interval : Time::Span = 5.seconds,
      @max_interval : Time::Span = 120.seconds,
      @stability_threshold : Int32 = 5,
      @enabled : Bool = true,
    )
      @current_interval = @base_interval
      @stable_cycles = 0
      @last_cluster_change = Time.utc
    end

    # Record a stable cycle (no changes detected)
    def record_stable_cycle
      return unless @enabled
      @stable_cycles += 1
      if @stable_cycles >= @stability_threshold
        increase_interval
        @stable_cycles = 0
      end
    end

    # Record cluster activity (changes detected)
    def record_activity
      return unless @enabled
      @stable_cycles = 0
      @last_cluster_change = Time.utc
      decrease_interval
    end

    # Increase interval when cluster is stable
    private def increase_interval
      new_interval = @current_interval * 1.5
      @current_interval = new_interval > @max_interval ? @max_interval : new_interval
    end

    # Decrease interval when activity is detected
    private def decrease_interval
      new_interval = @current_interval / 2
      @current_interval = new_interval < @min_interval ? @min_interval : new_interval
    end

    # Get time since last cluster change
    def time_since_last_change : Time::Span
      Time.utc - @last_cluster_change
    end

    # Check if cluster has been stable for a while
    def is_stable?(threshold : Time::Span = 5.minutes) : Bool
      time_since_last_change > threshold
    end

    def stats : Hash(String, String | Int32 | Float64)
      {
        "enabled"                        => @enabled.to_s,
        "current_interval_seconds"       => @current_interval.total_seconds,
        "base_interval_seconds"          => @base_interval.total_seconds,
        "min_interval_seconds"           => @min_interval.total_seconds,
        "max_interval_seconds"           => @max_interval.total_seconds,
        "stable_cycles"                  => @stable_cycles,
        "stability_threshold"            => @stability_threshold,
        "time_since_last_change_seconds" => time_since_last_change.total_seconds,
      }
    end
  end

  # Main distributed AtomSpace cluster coordination class
  class DistributedAtomSpaceCluster
    property cluster_id : String
    property node_id : String
    property local_atomspace : AtomSpace
    property sync_strategy : SyncStrategy
    property adaptive_heartbeat : AdaptiveHeartbeatConfig

    @cluster_nodes : Hash(String, ClusterNodeInfo)
    @server : TCPServer?
    @running : Bool = false
    @sync_thread : Fiber?
    @heartbeat_thread : Fiber?
    @vector_clock : Hash(String, UInt64)
    @pending_sync_ops : Array(SyncOperation)
    @conflict_resolver : ConflictResolver
    @membership_manager : ClusterMembershipManager
    @event_observers : Array(Proc(ClusterEvent, String, Nil))
    @previous_node_count : Int32 = 0
    @message_handlers = Hash(String, Proc(JSON::Any, TCPSocket?, Nil)).new
    # Nodes that announced their departure, and when. A member list from a
    # node that has not heard yet must not bring them back.
    @departed = Hash(String, Time).new

    # How long a departure outweighs second-hand news of that node.
    DEPARTURE_MEMORY = 2.minutes

    # Leadership. The members choose one leader by majority vote. Votes are
    # held in numbered terms: a node votes once per term, a candidate needs
    # more than half of the members it knows, and whoever sees a higher
    # term than its own gives way to it. Two leaders can therefore never
    # hold the same term. A vote goes only to a candidate whose log is at
    # least as far along as the voter's, so a new leader has every entry
    # the members agreed on. (This is the election half of Raft; the log
    # half is further down.)
    getter term : UInt64 = 0_u64
    getter role : ClusterRole = ClusterRole::Follower
    # The leader this node follows, itself when it leads, nil when it
    # knows of none.
    getter leader_id : String?
    @voted_for : String?
    @last_leader_contact : Time::Span = Time.monotonic
    # When set, a node that hears from no leader for between one and two
    # of these spans stands for election itself, and a leader tells the
    # others it is there three times in each. Set before `start`.
    property election_timeout : Time::Span? = nil
    # How long a candidate waits for one member's vote.
    property vote_timeout : Time::Span = 1.second

    # The replicated log. The leader takes in entries and hands them to
    # the others; an entry is committed once more than half of the members
    # hold it, and every member applies the committed entries in the same
    # order. Entries are numbered from 1.
    @log = [] of ClusterLogEntry
    # How many entries, from the first, this node knows to be committed.
    getter commit_index : UInt64 = 0_u64
    # How many of them it has applied.
    getter last_applied : UInt64 = 0_u64
    # As leader: for each member, the entry to hand it next and how many
    # entries it is known to hold.
    @next_index = Hash(String, UInt64).new
    @match_index = Hash(String, UInt64).new
    @replication_locks = Hash(String, Mutex).new
    @commit_handlers = [] of Proc(UInt64, JSON::Any, Nil)
    @applying = false
    @replicating = false
    # How long the leader waits for one member to answer for the log.
    property replication_timeout : Time::Span = 1.second
    # Where this member keeps what it must not forget: who it is, its
    # term, its vote and its log. nil keeps them in memory alone.
    getter state_path : String?

    # With a `state_path` the member is the same member after a restart:
    # it comes back under its old id, in the term it had reached, bound
    # by the vote it gave, and with its log. Without one it is a new
    # member each time.
    def initialize(@cluster_id : String, @local_atomspace : AtomSpace,
                   host : String = "localhost", port : Int32 = 0,
                   @sync_strategy : SyncStrategy = SyncStrategy::MergeUsingTruthValues,
                   adaptive_heartbeat_enabled : Bool = true,
                   @state_path : String? = nil)
      kept_id, @term, @voted_for, @log = DistributedAtomSpaceCluster.read_state(@state_path)
      @node_id = kept_id || UUID.random.to_s
      @cluster_nodes = Hash(String, ClusterNodeInfo).new
      @vector_clock = Hash(String, UInt64).new
      @pending_sync_ops = [] of SyncOperation
      @event_observers = [] of Proc(ClusterEvent, String, Nil)
      @adaptive_heartbeat = AdaptiveHeartbeatConfig.new(enabled: adaptive_heartbeat_enabled)

      # Initialize cluster node info for this node
      actual_port = port == 0 ? find_available_port(host) : port
      @local_node = ClusterNodeInfo.new(@node_id, host, actual_port)
      @local_node.status = NodeStatus::Initializing
      @cluster_nodes[@node_id] = @local_node
      @previous_node_count = 1

      @conflict_resolver = ConflictResolver.new(@sync_strategy)
      @membership_manager = ClusterMembershipManager.new(@cluster_id, @node_id)

      # Set up AtomSpace event observers for local changes
      setup_atomspace_observers

      # What was read is written back in its shortest form, and a new
      # member's id is on disk before it first speaks to another.
      write_state

      CogUtil::Logger.info("DistributedAtomSpaceCluster #{@cluster_id} node #{@node_id} initialized (adaptive_heartbeat=#{adaptive_heartbeat_enabled})")
    end

    # Start the cluster node and begin operations
    def start
      return if @running

      @running = true
      @local_node.status = NodeStatus::Active
      @vector_clock[@node_id] = 0_u64

      # Start network server
      spawn do
        start_cluster_server
      end

      # Start heartbeat thread
      @heartbeat_thread = spawn do
        heartbeat_loop
      end

      # Start synchronization thread
      @sync_thread = spawn do
        sync_loop
      end

      # Keep a leader in place when asked to
      if timeout = @election_timeout
        @last_leader_contact = Time.monotonic
        spawn election_loop(timeout)
      end

      emit_event(ClusterEvent::NODE_JOINED, @node_id)
      CogUtil::Logger.info("Cluster node #{@node_id} started on #{@local_node.host}:#{@local_node.port}")
    end

    # Stop the cluster node
    def stop
      return unless @running

      @running = false
      @local_node.status = NodeStatus::Offline

      # Notify other nodes of departure
      broadcast_departure_message

      @server.try(&.close)

      # Fibers will exit naturally when @running becomes false
      # Give them time to complete their current iteration
      sleep 0.1.seconds

      emit_event(ClusterEvent::NODE_LEFT, @node_id)
      CogUtil::Logger.info("Cluster node #{@node_id} stopped")
    end

    # Join an existing cluster by connecting to a seed node. The seed answers
    # with the members it knows and announces this node to each of them.
    def join_cluster(seed_host : String, seed_port : Int32) : Bool
      socket = TCPSocket.new(seed_host, seed_port)
      begin
        join_request = {
          "type"       => "cluster_join_request",
          "cluster_id" => @cluster_id,
          "node_id"    => @node_id,
          "host"       => @local_node.host,
          "port"       => @local_node.port,
          "timestamp"  => Time.utc.to_rfc3339,
        }

        socket.puts(join_request.to_json)

        response_data = socket.gets || return false
        response = JSON.parse(response_data)
        return false unless response["status"] == "accepted"

        response["cluster_nodes"]?.try(&.as_a?).try(&.each { |node_data| learn_node(node_data, first_hand: true) })

        # Start initial synchronization
        spawn do
          perform_initial_sync
        end

        CogUtil::Logger.info("Successfully joined cluster #{@cluster_id}")
        true
      ensure
        socket.close
      end
    rescue ex
      CogUtil::Logger.error("Failed to join cluster: #{ex.message}")
      false
    end

    # Add a new atom to the local AtomSpace and propagate to cluster
    def add_atom(atom : Atom) : Atom
      # Add to local atomspace first
      added_atom = @local_atomspace.add_atom(atom)

      # Create sync operation for cluster propagation
      sync_op = SyncOperation.new("add", added_atom.handle.to_s, @node_id)
      sync_op.atom_data = serialize_atom(added_atom)
      sync_op.vector_clock = increment_vector_clock

      # Queue for synchronization
      @pending_sync_ops << sync_op

      CogUtil::Logger.debug("Queued atom addition for cluster sync: #{added_atom}")
      added_atom
    end

    # Remove an atom from the local AtomSpace and propagate to cluster
    def remove_atom(atom : Atom) : Bool
      # Remove from local atomspace first
      success = @local_atomspace.remove_atom(atom)

      if success
        # Create sync operation for cluster propagation
        sync_op = SyncOperation.new("remove", atom.handle.to_s, @node_id)
        sync_op.vector_clock = increment_vector_clock

        # Queue for synchronization
        @pending_sync_ops << sync_op

        CogUtil::Logger.debug("Queued atom removal for cluster sync: #{atom}")
      end

      success
    end

    # Get cluster-wide statistics
    def cluster_stats : Hash(String, JSON::Any)
      total_atoms = @cluster_nodes.values.sum(&.atomspace_size)
      active_nodes = @cluster_nodes.values.count { |node| node.status == NodeStatus::Active }

      stats = {
        "cluster_id"                 => JSON::Any.new(@cluster_id),
        "total_nodes"                => JSON::Any.new(@cluster_nodes.size.to_i64),
        "active_nodes"               => JSON::Any.new(active_nodes.to_i64),
        "total_atoms"                => JSON::Any.new(total_atoms.to_i64),
        "local_atomspace_size"       => JSON::Any.new(@local_atomspace.size.to_i64),
        "pending_sync_operations"    => JSON::Any.new(@pending_sync_ops.size.to_i64),
        "sync_strategy"              => JSON::Any.new(@sync_strategy.to_s),
        "local_node_status"          => JSON::Any.new(@local_node.status.to_s),
        "adaptive_heartbeat_enabled" => JSON::Any.new(@adaptive_heartbeat.enabled),
        "heartbeat_interval_seconds" => JSON::Any.new(@adaptive_heartbeat.current_interval.total_seconds),
        "term"                       => JSON::Any.new(@term.to_i64),
        "role"                       => JSON::Any.new(@role.to_s),
        "leader_id"                  => JSON::Any.new(@leader_id),
        "log_size"                   => JSON::Any.new(@log.size.to_i64),
        "commit_index"               => JSON::Any.new(@commit_index.to_i64),
        "last_applied"               => JSON::Any.new(@last_applied.to_i64),
      }

      stats
    end

    # Get adaptive heartbeat statistics
    def heartbeat_stats : Hash(String, String | Int32 | Float64)
      @adaptive_heartbeat.stats
    end

    # Get information about all cluster nodes
    def cluster_nodes : Array(ClusterNodeInfo)
      @cluster_nodes.values
    end

    # Add event observer
    def add_event_observer(observer : Proc(ClusterEvent, String, Nil))
      @event_observers << observer
    end

    # Manual synchronization trigger
    def trigger_sync : Bool
      return false unless @running

      spawn do
        process_pending_sync_operations
      end

      true
    end

    # Force full cluster synchronization
    def full_cluster_sync : Bool
      return false unless @running

      emit_event(ClusterEvent::SYNC_STARTED, @node_id)

      success = true
      @cluster_nodes.each_key do |node_id|
        next if node_id == @node_id
        success = false unless sync_with_node(node_id)
      end

      emit_event(ClusterEvent::SYNC_COMPLETED, @node_id)
      success
    end

    private def setup_atomspace_observers
      # Observe local AtomSpace changes for automatic cluster synchronization
      @local_atomspace.add_observer(->(event : AtomSpaceEvent, atom : Atom) {
        case event
        when AtomSpaceEvent::ATOM_ADDED
          # This is handled by our add_atom method
        when AtomSpaceEvent::ATOM_REMOVED
          # This is handled by our remove_atom method
        when AtomSpaceEvent::TRUTH_VALUE_CHANGED
          # Create update sync operation
          sync_op = SyncOperation.new("update", atom.handle.to_s, @node_id)
          sync_op.atom_data = serialize_atom(atom)
          sync_op.vector_clock = increment_vector_clock
          @pending_sync_ops << sync_op
        end
      })
    end

    private def start_cluster_server
      @server = TCPServer.new(@local_node.host, @local_node.port)

      while @running && (server = @server)
        begin
          client = server.accept
          # The call form hands this connection to the fiber. A `spawn do`
          # block would share the loop's `client` variable, and when a
          # second connection is already waiting the first is never served.
          spawn handle_cluster_client(client)
        rescue ex
          break unless @running
          CogUtil::Logger.error("Cluster server error: #{ex.message}")
        end
      end
    rescue ex
      CogUtil::Logger.error("Failed to start cluster server: #{ex.message}")
    end

    private def handle_cluster_client(client : TCPSocket)
      begin
        while @running
          message_data = client.gets
          break unless message_data

          message = JSON.parse(message_data)
          process_cluster_message(message, client)
        end
      rescue ex
        CogUtil::Logger.debug("Cluster client error: #{ex.message}")
      ensure
        client.close
      end
    end

    private def process_cluster_message(message : JSON::Any, client : TCPSocket?)
      message_type = message["type"].as_s

      case message_type
      when "cluster_join_request"
        handle_join_request(message, client)
      when "heartbeat"
        handle_heartbeat(message)
      when "sync_operation"
        handle_sync_operation(message)
      when "cluster_departure"
        handle_departure(message)
      when "member_joined"
        handle_member_joined(message)
      when "vote_request"
        handle_vote_request(message, client)
      when "leader_announce"
        handle_leader_announce(message)
      when "log_append"
        handle_log_append(message, client)
      when "log_propose"
        handle_log_propose(message, client)
      when "conflict_resolution"
        handle_conflict_resolution(message)
      else
        if handler = @message_handlers[message_type]?
          handler.call(message, client)
        else
          CogUtil::Logger.warn("Unknown cluster message type: #{message_type}")
        end
      end
    end

    # Let another component (such as DistributedStorageNode) serve its own
    # message types on this node's cluster port. The handler may answer on
    # the client socket with one JSON line.
    def on_message(type : String, &handler : JSON::Any, TCPSocket? -> Nil)
      @message_handlers[type] = handler
    end

    private def handle_join_request(message : JSON::Any, client : TCPSocket?)
      cluster_id = message["cluster_id"].as_s

      if cluster_id != @cluster_id
        response = {"status" => "rejected", "reason" => "cluster_id_mismatch"}
        client.try(&.puts(response.to_json))
        return
      end

      node_id = message["node_id"].as_s
      host = message["host"].as_s
      port = message["port"].as_i

      # Add new node to cluster
      new_node = ClusterNodeInfo.new(node_id, host, port)
      new_node.status = NodeStatus::Active
      @departed.delete(node_id)
      @cluster_nodes[node_id] = new_node

      # Send acceptance response with current cluster state
      response = {
        "status"        => "accepted",
        "cluster_nodes" => member_records,
      }

      client.try(&.puts(response.to_json))

      emit_event(ClusterEvent::NODE_JOINED, node_id)
      CogUtil::Logger.info("New node #{node_id} joined cluster")

      # Tell the members already here. Without this only the seed and the
      # newcomer would know of each other.
      announcement = {
        "type"        => JSON::Any.new("member_joined"),
        "source_node" => JSON::Any.new(@node_id),
        "node"        => JSON.parse(node_record(new_node).to_json),
        "members"     => JSON.parse(member_records.to_json),
      }
      @cluster_nodes.values.each do |node|
        next if node.id == @node_id || node.id == node_id
        send_message_to_node(node, announcement)
      end
    end

    private def node_record(node : ClusterNodeInfo)
      {
        "id"             => node.id,
        "host"           => node.host,
        "port"           => node.port,
        "status"         => node.status.to_s,
        "atomspace_size" => node.atomspace_size,
      }
    end

    private def member_records
      @cluster_nodes.values.map { |node| node_record(node) }
    end

    # Record a member described by another node. Returns true when it was
    # not known before. `first_hand` news comes from the node itself or from
    # the seed that just accepted us; anything else yields to a departure
    # this node heard about recently.
    private def learn_node(data : JSON::Any, first_hand : Bool = false) : Bool
      id = data["id"]?.try(&.as_s?) || return false
      return false if id == @node_id
      host = data["host"]?.try(&.as_s?) || return false
      port = data["port"]?.try(&.as_i?) || return false

      if left_at = @departed[id]?
        return false if !first_hand && Time.utc - left_at < DEPARTURE_MEMORY
        @departed.delete(id)
      end

      if known = @cluster_nodes[id]?
        if first_hand
          # A member that came back may listen somewhere else.
          known.host = host
          known.port = port
          known.update_heartbeat
        end
        return false
      end

      node = ClusterNodeInfo.new(id, host, port)
      node.status = data["status"]?.try(&.as_s?).try { |status| NodeStatus.parse?(status) } || NodeStatus::Active
      node.atomspace_size = data["atomspace_size"]?.try(&.as_i64?).try(&.to_u64) || 0_u64
      @cluster_nodes[id] = node
      emit_event(ClusterEvent::NODE_JOINED, id)
      CogUtil::Logger.info("Learned of cluster node #{id} at #{host}:#{port}")
      true
    end

    # Another member accepted a node: learn it, and any member in the
    # sender's list this node had missed.
    private def handle_member_joined(message : JSON::Any)
      message["node"]?.try { |node| learn_node(node, first_hand: true) }
      message["members"]?.try(&.as_a?).try(&.each { |node| learn_node(node) })
    end

    private def handle_heartbeat(message : JSON::Any)
      node_id = message["node_id"].as_s

      # A heartbeat names its sender's address and the members it knows, so
      # a node that missed an announcement catches up on the next beat.
      if message["host"]? && message["port"]?
        learn_node(JSON.parse({"id" => node_id, "host" => message["host"], "port" => message["port"],
                               "status" => message["status"]}.to_json), first_hand: true)
      end
      message["members"]?.try(&.as_a?).try(&.each { |node| learn_node(node) })

      if node = @cluster_nodes[node_id]?
        node.update_heartbeat
        node.status = NodeStatus.parse(message["status"].as_s)
        node.atomspace_size = message["atomspace_size"].as_i64.to_u64
        node.load_factor = message["load_factor"].as_f
      end
    end

    private def handle_sync_operation(message : JSON::Any)
      sync_op = SyncOperation.new(
        message["operation_type"].as_s,
        message["atom_handle"].as_s,
        message["source_node"].as_s
      )
      sync_op.id = message["id"].as_s
      sync_op.timestamp = Time.parse_rfc3339(message["timestamp"].as_s)

      if atom_data = message["atom_data"]?
        sync_op.atom_data = atom_data.as_h
      end

      if vector_clock = message["vector_clock"]?
        sync_op.vector_clock = vector_clock.as_h.transform_values(&.as_i64.to_u64)
      end

      apply_sync_operation(sync_op)
    end

    private def apply_sync_operation(sync_op : SyncOperation) : Bool
      case sync_op.operation_type
      when "add", "update"
        return false unless sync_op.atom_data

        atom = deserialize_atom(sync_op.atom_data.not_nil!)
        return false unless atom

        # Check for conflicts using vector clocks
        if conflict = detect_conflict(sync_op)
          emit_event(ClusterEvent::CONFLICT_DETECTED, sync_op.id)
          resolved_atom = @conflict_resolver.resolve(conflict, atom)
          @local_atomspace.add_atom(resolved_atom)
          emit_event(ClusterEvent::CONFLICT_RESOLVED, sync_op.id)
        else
          @local_atomspace.add_atom(atom)
        end

        update_vector_clock(sync_op.vector_clock)
        return true
      when "remove"
        if existing_atom = @local_atomspace.get_atom(Handle.new(sync_op.atom_handle))
          @local_atomspace.remove_atom(existing_atom)
          update_vector_clock(sync_op.vector_clock)
          return true
        end
      end

      false
    end

    private def heartbeat_loop
      while @running
        # Update local node status
        @local_node.update_heartbeat
        @local_node.atomspace_size = @local_atomspace.size
        @local_node.load_factor = calculate_load_factor

        # Send heartbeat to all cluster nodes
        heartbeat_message = {
          "type"           => JSON::Any.new("heartbeat"),
          "node_id"        => JSON::Any.new(@node_id),
          "host"           => JSON::Any.new(@local_node.host),
          "port"           => JSON::Any.new(@local_node.port.to_i64),
          "status"         => JSON::Any.new(@local_node.status.to_s),
          "atomspace_size" => JSON::Any.new(@local_node.atomspace_size.to_i64),
          "load_factor"    => JSON::Any.new(@local_node.load_factor),
          "timestamp"      => JSON::Any.new(Time.utc.to_rfc3339),
          "members"        => JSON.parse(member_records.to_json),
        }
        @departed.reject! { |_, left_at| Time.utc - left_at > DEPARTURE_MEMORY }

        broadcast_message(heartbeat_message)

        # Detect cluster changes for adaptive heartbeat
        current_node_count = @cluster_nodes.size
        cluster_changed = false

        # Clean up stale nodes
        @cluster_nodes.reject! do |node_id, node|
          if node_id != @node_id && node.is_stale?
            @departed[node_id] = Time.utc
            emit_event(ClusterEvent::NODE_LEFT, node_id)
            CogUtil::Logger.info("Removed stale node #{node_id} from cluster")
            cluster_changed = true
            true
          else
            false
          end
        end

        # Check if node count changed
        if current_node_count != @previous_node_count
          cluster_changed = true
          @previous_node_count = @cluster_nodes.size
        end

        # Check if there are pending sync operations (indicates activity)
        if !@pending_sync_ops.empty?
          cluster_changed = true
        end

        # Update adaptive heartbeat based on cluster state
        if cluster_changed
          @adaptive_heartbeat.record_activity
          CogUtil::Logger.debug("Cluster activity detected, heartbeat interval: #{@adaptive_heartbeat.current_interval.total_seconds}s")
        else
          @adaptive_heartbeat.record_stable_cycle
          CogUtil::Logger.debug("Cluster stable, heartbeat interval: #{@adaptive_heartbeat.current_interval.total_seconds}s")
        end

        # Sleep for the adaptive interval
        sleep @adaptive_heartbeat.current_interval
      end
    end

    private def sync_loop
      while @running
        process_pending_sync_operations
        sleep 5.seconds # Process sync operations every 5 seconds
      end
    end

    private def process_pending_sync_operations
      return if @pending_sync_ops.empty?

      ops_to_process = @pending_sync_ops.dup
      @pending_sync_ops.clear

      ops_to_process.each do |sync_op|
        broadcast_sync_operation(sync_op)
      end
    end

    private def broadcast_sync_operation(sync_op : SyncOperation)
      message = {
        "type"           => "sync_operation",
        "id"             => sync_op.id,
        "operation_type" => sync_op.operation_type,
        "atom_handle"    => sync_op.atom_handle,
        "source_node"    => sync_op.source_node,
        "timestamp"      => sync_op.timestamp.to_rfc3339,
        "atom_data"      => sync_op.atom_data,
        "vector_clock"   => sync_op.vector_clock,
      }

      broadcast_message(message)
    end

    private def broadcast_message(message : Hash)
      # Sending yields to other fibers, which may add or drop members.
      @cluster_nodes.values.each do |node|
        next if node.id == @node_id
        send_message_to_node(node, message)
      end
    end

    private def send_message_to_node(node : ClusterNodeInfo, message : Hash) : Bool
      begin
        socket = TCPSocket.new(node.host, node.port)
        socket.puts(message.to_json)
        socket.close
        true
      rescue ex
        CogUtil::Logger.error("Failed to send message to node #{node.id}: #{ex.message}")
        false
      end
    end

    private def serialize_atom(atom : Atom) : Hash(String, JSON::Any)
      data = Hash(String, JSON::Any).new
      data["handle"] = JSON::Any.new(atom.handle.to_s)
      data["type"] = JSON::Any.new(atom.type.to_s)
      data["truth_strength"] = JSON::Any.new(atom.truth_value.strength)
      data["truth_confidence"] = JSON::Any.new(atom.truth_value.confidence)

      if atom.is_a?(Node)
        data["name"] = JSON::Any.new(atom.name)
      elsif atom.is_a?(Link)
        data["outgoing"] = JSON::Any.new(atom.outgoing.map { |a| JSON::Any.new(a.handle.to_s) })
        # Handles are node-local, so ship the outgoing atoms by content too.
        data["outgoing_atoms"] = JSON::Any.new(atom.outgoing.map { |a| JSON::Any.new(serialize_atom(a)) })
      end

      data
    end

    private def deserialize_atom(data : Hash(String, JSON::Any)) : Atom?
      begin
        type = AtomType.parse(data["type"].as_s)
        strength = data["truth_strength"].as_f
        confidence = data["truth_confidence"].as_f
        tv = SimpleTruthValue.new(strength, confidence)

        if type.node?
          name = data["name"].as_s
          return Node.new(type, name, tv)
        else
          # Rebuild children from content and intern them locally, so the
          # link points at this node's atoms rather than remote handles.
          children = data["outgoing_atoms"]?.try(&.as_a?)
          unless children
            CogUtil::Logger.warn("Link sync without outgoing_atoms; cannot resolve remote handles")
            return nil
          end
          outgoing = children.map do |child|
            atom = deserialize_atom(child.as_h)
            return nil unless atom
            @local_atomspace.add_atom(atom)
          end
          return Link.new(type, outgoing, tv)
        end
      rescue ex
        CogUtil::Logger.error("Failed to deserialize atom: #{ex.message}")
        nil
      end
    end

    private def increment_vector_clock : Hash(String, UInt64)
      @vector_clock[@node_id] = @vector_clock[@node_id] + 1
      @vector_clock.dup
    end

    private def update_vector_clock(remote_clock : Hash(String, UInt64)?)
      return unless remote_clock

      remote_clock.each do |node_id, timestamp|
        current = @vector_clock[node_id]? || 0_u64
        @vector_clock[node_id] = Math.max(current, timestamp)
      end
    end

    private def detect_conflict(sync_op : SyncOperation) : ConflictInfo?
      # Simplified conflict detection based on vector clocks
      return nil unless sync_op.vector_clock

      remote_clock = sync_op.vector_clock.not_nil!

      # Check if this operation is concurrent with local changes
      remote_clock.each do |node_id, timestamp|
        local_timestamp = @vector_clock[node_id]? || 0_u64
        if timestamp < local_timestamp
          return ConflictInfo.new(sync_op, "concurrent_modification")
        end
      end

      nil
    end

    private def calculate_load_factor : Float64
      # Simple load factor based on atomspace size and pending operations
      base_load = @local_atomspace.size.to_f / 10000.0 # Normalize to 10k atoms
      sync_load = @pending_sync_ops.size.to_f / 100.0  # Normalize to 100 ops
      Math.min(1.0, base_load + sync_load)
    end

    @@reserved_ports = Set(Int32).new
    @@reserved_ports_mutex = Mutex.new

    # A free port chosen by the OS. A port is not bound until `start`, so
    # ports already handed out in this process are never offered twice.
    private def find_available_port(host : String) : Int32
      @@reserved_ports_mutex.synchronize do
        20.times do
          server = TCPServer.new(host, 0)
          port = server.local_address.port
          server.close
          return port if @@reserved_ports.add?(port)
        end
      end
      Random.rand(26000..30000)
    end

    # Public so DistributedStorageNode and other cluster participants can notify observers
    def emit_event(event : ClusterEvent, node_id : String)
      @event_observers.each do |observer|
        begin
          observer.call(event, node_id)
        rescue ex
          CogUtil::Logger.error("Error in cluster event observer: #{ex.message}")
        end
      end
    end

    private def broadcast_departure_message
      departure_message = {
        "type"      => "cluster_departure",
        "node_id"   => @node_id,
        "timestamp" => Time.utc.to_rfc3339,
      }

      broadcast_message(departure_message)
    end

    private def handle_departure(message : JSON::Any)
      node_id = message["node_id"].as_s
      return if node_id == @node_id
      @departed[node_id] = Time.utc
      if @cluster_nodes.delete(node_id)
        emit_event(ClusterEvent::NODE_LEFT, node_id)
        CogUtil::Logger.info("Node #{node_id} left cluster")
      end
      if @leader_id == node_id
        @leader_id = nil
        emit_event(ClusterEvent::LEADER_LOST, node_id)
      end
    end

    # ------------------------------------------------------------ leadership

    def leader? : Bool
      @role.leader?
    end

    # The member that leads, as far as this node knows.
    def leader : ClusterNodeInfo?
      @leader_id.try { |id| @cluster_nodes[id]? }
    end

    # Stand for leader: open a new term and ask every member for its vote.
    # Returns true when more than half of the members, this one included,
    # gave theirs and no higher term turned up meanwhile; this node then
    # leads and has told the others. A node that is not running, or that
    # loses, returns false.
    def start_election : Bool
      return false unless @running

      @term += 1
      term = @term
      @role = ClusterRole::Candidate
      @voted_for = @node_id
      persist_term
      follow(nil)

      members = @cluster_nodes.values
      others = members.reject { |node| node.id == @node_id }
      needed = members.size // 2 + 1
      votes = 1
      answers = Channel(Bool).new(Math.max(others.size, 1))
      others.each { |node| spawn request_vote(node, term, answers) }

      others.size.times do
        break if votes >= needed
        votes += 1 if answers.receive
        # A vote request or an announcement of a higher term ends this try.
        break unless @term == term && @role.candidate?
      end

      if @term == term && @role.candidate? && votes >= needed
        @role = ClusterRole::Leader
        follow(@node_id)
        announce_leadership
        CogUtil::Logger.info("Node #{@node_id} leads cluster #{@cluster_id} in term #{term} with #{votes} of #{members.size} votes")
        open_term
        # Opening the term talks to the members; a higher term may have
        # turned up meanwhile.
        @term == term && leader?
      else
        @role = ClusterRole::Follower if @term == term && @role.candidate?
        false
      end
    end

    # Tell every member who leads this term. A leader repeats it to show
    # it is still there.
    def announce_leadership : Nil
      return unless leader?
      broadcast_message({"type" => "leader_announce", "term" => @term.to_i64, "leader_id" => @node_id})
    end

    private def request_vote(node : ClusterNodeInfo, term : UInt64, answers : Channel(Bool)) : Nil
      granted = false
      begin
        socket = TCPSocket.new(node.host, node.port, connect_timeout: @vote_timeout)
        begin
          socket.read_timeout = @vote_timeout
          socket.puts({"type" => "vote_request", "term" => term.to_i64, "candidate_id" => @node_id,
                       "last_log_index" => @log.size.to_i64,
                       "last_log_term" => (@log.last?.try(&.term) || 0_u64).to_i64}.to_json)
          if line = socket.gets
            answer = JSON.parse(line)
            theirs = answer["term"].as_i64.to_u64
            give_way(theirs) if theirs > @term
            granted = answer["granted"].as_bool && theirs == term
          end
        ensure
          socket.close
        end
      rescue ex
        CogUtil::Logger.debug("No vote from node #{node.id}: #{ex.message}")
      end
      answers.send(granted)
    end

    # One vote per term, for whoever asks first and has a log at least as
    # far along as this node's: a later last term, or the same and no
    # fewer entries. A candidate of an older term is told the newer one.
    private def handle_vote_request(message : JSON::Any, client : TCPSocket?)
      term = message["term"].as_i64.to_u64
      candidate = message["candidate_id"].as_s
      give_way(term) if term > @term

      their_last = message["last_log_term"]?.try(&.as_i64.to_u64) || 0_u64
      their_size = message["last_log_index"]?.try(&.as_i64.to_u64) || 0_u64
      my_last = @log.last?.try(&.term) || 0_u64
      far_enough = their_last > my_last || (their_last == my_last && their_size >= @log.size)
      granted = term == @term && far_enough && (@voted_for.nil? || @voted_for == candidate)
      if granted
        @voted_for = candidate
        # The vote is on disk before the candidate hears of it.
        persist_term
        # Having voted, give the candidate time to win before standing.
        @last_leader_contact = Time.monotonic
      end
      client.try(&.puts({"term" => @term.to_i64, "granted" => granted}.to_json))
    rescue ex
      CogUtil::Logger.debug("Vote request not answered: #{ex.message}")
    end

    private def handle_leader_announce(message : JSON::Any)
      term = message["term"].as_i64.to_u64
      leader = message["leader_id"].as_s
      # A leader of a term that is over has been replaced; it will hear so
      # from the next vote request or announcement that reaches it.
      return if term < @term
      return if leader == @node_id

      give_way(term) if term > @term
      @role = ClusterRole::Follower
      @last_leader_contact = Time.monotonic
      follow(leader)
    end

    # A higher term exists: join it as a follower with a vote to give.
    private def give_way(term : UInt64) : Nil
      @term = term
      @role = ClusterRole::Follower
      @voted_for = nil
      persist_term
      follow(nil) if @leader_id == @node_id
    end

    # Set the leader this node follows and tell the observers of a change.
    private def follow(leader : String?) : Nil
      previous = @leader_id
      return if previous == leader
      @leader_id = leader
      emit_event(ClusterEvent::LEADER_LOST, previous) if previous
      emit_event(ClusterEvent::LEADER_ELECTED, leader) if leader
    end

    # Keeps a leader in place: a leader shows it is there, and a node that
    # has heard from none for a while stands for election. The wait is
    # drawn afresh each time, between one and two timeouts, so that two
    # nodes seldom stand at once, and when they do one of them soon tries
    # again alone.
    private def election_loop(timeout : Time::Span) : Nil
      patience = timeout * (1.0 + rand)
      while @running
        sleep timeout / 3
        break unless @running
        if leader?
          announce_leadership
          # Bring along whoever fell behind, without holding up the next
          # announcement while a member is slow to answer.
          spawn keep_up unless @replicating
        elsif Time.monotonic - @last_leader_contact >= patience
          @last_leader_contact = Time.monotonic
          patience = timeout * (1.0 + rand)
          start_election
        end
      end
    end

    # ------------------------------------------------------ replicated log

    def log_size : UInt64
      @log.size.to_u64
    end

    # The term of each log entry, in order.
    def log_terms : Array(UInt64)
      @log.map(&.term)
    end

    # The commands the members have agreed on, in the order every member
    # applies them.
    def committed : Array(JSON::Any)
      @log.first(@commit_index).select { |entry| entry.kind == "command" }.map(&.data)
    end

    # Called on this node for every committed command, in log order, with
    # the entry's number and the command.
    def on_commit(&handler : UInt64, JSON::Any -> Nil)
      @commit_handlers << handler
    end

    # Put a command to the cluster. The leader takes it into its log and
    # hands it to the others; any other member passes it to the leader it
    # follows. Returns the entry's number once more than half of the
    # members hold it and those that answered have been told, or nil when
    # that could not be established: no leader, no majority within the
    # time allowed, or a change of leader on the way. After nil the
    # command may still be committed later.
    def propose(command) : UInt64?
      data = command.is_a?(JSON::Any) ? command : JSON.parse(command.to_json)
      submit("command", data)
    end

    # Add an atom to every member's AtomSpace through the log. All
    # members place it in the same order, so they end with the same truth
    # value without resolving conflicts: an atom that is already there
    # takes the truth value given, and its parts are used as they are.
    # Returns this node's atom once that is done, nil as `propose` does.
    def add_atom_in_order(atom : Atom) : Atom?
      index = submit("atom", JSON::Any.new(serialize_atom(atom))) || return nil
      @last_applied >= index ? stored(atom) : nil
    end

    # As leader, hand every member the entries it lacks and the commit
    # point. Returns how many of the others are up to date.
    def replicate : Int32
      return 0 unless @running && leader?
      before = @commit_index
      advance_commit
      reached = sync(other_members)
      reached = sync(reached) if @commit_index > before && leader?
      reached.size
    end

    # The leader's regular round, one at a time.
    private def keep_up : Nil
      return if @replicating
      @replicating = true
      begin
        replicate
      ensure
        @replicating = false
      end
    end

    private def other_members : Array(ClusterNodeInfo)
      @cluster_nodes.values.reject { |node| node.id == @node_id }
    end

    private def submit(kind : String, data : JSON::Any) : UInt64?
      return nil unless @running
      return take_in(kind, data) if leader?

      target = leader || return nil
      answer = request(target, {"type" => "log_propose", "kind" => kind, "data" => data}, @replication_timeout * 4) || return nil
      answer["index"]?.try(&.as_i64?).try(&.to_u64)
    end

    # As leader: append an entry, hand it round, and say whether it was
    # committed in this term.
    private def take_in(kind : String, data : JSON::Any) : UInt64?
      return nil unless @running && leader?
      term = @term
      entry = ClusterLogEntry.new(term, kind, data)
      @log << entry
      persist([{"entry" => entry.to_h}.to_json])
      index = @log.size.to_u64
      settle_log
      @term == term && @commit_index >= index ? index : nil
    end

    # A new leader opens its term with an entry of its own. Entries are
    # committed by counting only in the leader's own term, so this is what
    # settles whatever earlier leaders left behind.
    private def open_term : Nil
      @next_index.clear
      @match_index.clear
      entry = ClusterLogEntry.new(@term, "term", JSON::Any.new(@node_id))
      @log << entry
      persist([{"entry" => entry.to_h}.to_json])
      settle_log
    end

    # Hand the log round, and tell the members that answered when that
    # moved the commit point.
    private def settle_log : Nil
      before = @commit_index
      advance_commit
      reached = sync(other_members)
      sync(reached) if @commit_index > before && leader?
    end

    # Bring each of these members up to date, all at once; those that
    # are, when it is done.
    private def sync(nodes : Array(ClusterNodeInfo)) : Array(ClusterNodeInfo)
      reached = [] of ClusterNodeInfo
      return reached if nodes.empty?
      term = @term
      answers = Channel({ClusterNodeInfo, Bool}).new(nodes.size)
      nodes.each { |node| spawn sync_node(node, term, answers) }
      nodes.size.times do
        node, up_to_date = answers.receive
        reached << node if up_to_date
      end
      reached
    end

    private def sync_node(node : ClusterNodeInfo, term : UInt64, answers : Channel({ClusterNodeInfo, Bool})) : Nil
      up_to_date = false
      begin
        up_to_date = bring_up_to_date(node, term)
      rescue ex
        CogUtil::Logger.debug("Log not handed to node #{node.id}: #{ex.message}")
      end
      answers.send({node, up_to_date})
    end

    # Hand one member what follows the entries it is known to hold. Each
    # message names the entry before the new ones; a member whose log does
    # not have that entry says how far its log goes, and the leader starts
    # from there.
    private def bring_up_to_date(node : ClusterNodeInfo, term : UInt64) : Bool
      lock = @replication_locks[node.id] ||= Mutex.new
      lock.synchronize do
        loop do
          return false unless @running && leader? && @term == term
          size = @log.size.to_u64
          following = Math.min(@next_index[node.id]? || size + 1, size + 1)
          before = following - 1
          entries = @log[before.to_i..]
          message = {
            "type"       => "log_append",
            "term"       => term.to_i64,
            "leader_id"  => @node_id,
            "prev_index" => before.to_i64,
            "prev_term"  => (before > 0 ? @log[before - 1].term : 0_u64).to_i64,
            "entries"    => entries.map(&.to_h),
            "commit"     => @commit_index.to_i64,
          }
          answer = request(node, message, @replication_timeout) || return false
          theirs = answer["term"].as_i64.to_u64
          if theirs > @term
            give_way(theirs)
            return false
          end
          return false unless leader? && @term == term

          if answer["success"].as_bool
            held = before + entries.size
            @match_index[node.id] = Math.max(@match_index[node.id]? || 0_u64, held)
            @next_index[node.id] = held + 1
            advance_commit
            return true
          end
          return false if before == 0
          have = answer["have"]?.try(&.as_i64.to_u64) || before - 1
          @next_index[node.id] = Math.min(before, have + 1)
        end
      end
    end

    # As leader: the furthest entry of this term that more than half of
    # the members hold is committed, and with it all before it.
    private def advance_commit : Nil
      return unless leader?
      needed = @cluster_nodes.size // 2 + 1
      others = other_members
      at = @log.size.to_u64
      while at > @commit_index && @log[at - 1].term == @term
        holders = 1 + others.count { |node| (@match_index[node.id]? || 0_u64) >= at }
        if holders >= needed
          @commit_index = at
          apply_committed
          break
        end
        at -= 1
      end
    end

    # Apply what is committed and not yet applied, in order, once.
    private def apply_committed : Nil
      return if @applying
      @applying = true
      begin
        while @last_applied < @commit_index
          @last_applied += 1
          index = @last_applied
          entry = @log[index - 1]
          case entry.kind
          when "command"
            @commit_handlers.each do |handler|
              begin
                handler.call(index, entry.data)
              rescue ex
                CogUtil::Logger.error("Commit handler failed on entry #{index}: #{ex.message}")
              end
            end
          when "atom"
            place(entry.data)
          end
        end
      ensure
        @applying = false
      end
    end

    # A leader hands over entries. They are taken when this node's log
    # has the entry they follow; an entry already there from another term
    # goes, with all after it, since that leader did not prevail.
    private def handle_log_append(message : JSON::Any, client : TCPSocket?)
      term = message["term"].as_i64.to_u64
      if term < @term
        client.try(&.puts({"term" => @term.to_i64, "success" => false, "have" => @log.size.to_i64}.to_json))
        return
      end
      give_way(term) if term > @term
      @role = ClusterRole::Follower
      @last_leader_contact = Time.monotonic
      follow(message["leader_id"].as_s)

      before = message["prev_index"].as_i64.to_u64
      fits = before == 0 || (@log.size >= before && @log[before - 1].term == message["prev_term"].as_i64.to_u64)
      unless fits
        have = Math.min(@log.size.to_u64, before - 1)
        client.try(&.puts({"term" => @term.to_i64, "success" => false, "have" => have.to_i64}.to_json))
        return
      end

      entries = message["entries"].as_a
      # What changes in the log goes to disk in one write, before the
      # leader is told the entries are held.
      changes = [] of String
      entries.each_with_index do |raw, i|
        entry = ClusterLogEntry.from(raw)
        index = before + i + 1
        if @log.size >= index
          next if @log[index - 1].term == entry.term
          if index <= @commit_index
            CogUtil::Logger.error("Node #{@node_id} was handed another entry #{index} than the one it committed")
            persist(changes)
            client.try(&.puts({"term" => @term.to_i64, "success" => false, "have" => @commit_index.to_i64}.to_json))
            return
          end
          @log.pop(@log.size - (index - 1).to_i)
          changes << {"truncate" => (index - 1).to_i64}.to_json
        end
        @log << entry
        changes << {"entry" => entry.to_h}.to_json
      end
      persist(changes)

      # Committed is what the leader says, as far as this log is known to
      # agree with the leader's.
      known = Math.min(message["commit"].as_i64.to_u64, before + entries.size)
      if known > @commit_index
        @commit_index = known
        apply_committed
      end
      client.try(&.puts({"term" => @term.to_i64, "success" => true, "have" => @log.size.to_i64}.to_json))
    rescue ex
      CogUtil::Logger.debug("Log entries not taken: #{ex.message}")
    end

    # A member passes on what was proposed to it.
    private def handle_log_propose(message : JSON::Any, client : TCPSocket?)
      kind = message["kind"].as_s
      index = (kind == "command" || kind == "atom") ? take_in(kind, message["data"]) : nil
      client.try(&.puts({"index" => index.try(&.to_i64)}.to_json))
    rescue ex
      CogUtil::Logger.debug("Proposal not answered: #{ex.message}")
    end

    # --------------------------------------------------------- kept state

    # What a state file holds: the member's id, its term, its vote and
    # its log. The file is a journal of JSON lines, each a change: the
    # id, a term with the vote given in it, an entry added to the log, or
    # the log cut back to a length. A last line torn by a crash is not a
    # change that was ever answered for, and is left out.
    def self.read_state(path : String?) : {String?, UInt64, String?, Array(ClusterLogEntry)}
      id = nil
      term = 0_u64
      voted_for = nil
      log = [] of ClusterLogEntry
      return {id, term, voted_for, log} unless path && File.exists?(path)

      File.each_line(path) do |line|
        record = (JSON.parse(line) rescue nil).try(&.as_h?) || next
        if kept = record["node_id"]?
          id = kept.as_s?
        elsif kept = record["term"]?
          term = kept.as_i64.to_u64
          voted_for = record["voted_for"]?.try(&.as_s?)
        elsif kept = record["entry"]?
          log << ClusterLogEntry.from(kept)
        elsif kept = record["truncate"]?
          length = kept.as_i64.to_i
          log.pop(log.size - length) if log.size > length
        end
      end
      {id, term, voted_for, log}
    end

    # Write the whole state afresh, in place of the journal so far.
    private def write_state : Nil
      path = @state_path || return
      Dir.mkdir_p(File.dirname(path))
      fresh = "#{path}.tmp"
      File.open(fresh, "w") do |file|
        file.puts({"node_id" => @node_id}.to_json)
        file.puts({"term" => @term.to_i64, "voted_for" => @voted_for}.to_json)
        @log.each { |entry| file.puts({"entry" => entry.to_h}.to_json) }
        file.fsync
      end
      File.rename(fresh, path)
    end

    # Add changes to the journal, and have them on disk before going on.
    private def persist(lines : Array(String)) : Nil
      path = @state_path || return
      return if lines.empty?
      File.open(path, "a") do |file|
        lines.each { |line| file.puts(line) }
        file.fsync
      end
    rescue ex
      CogUtil::Logger.error("Cluster state not written to #{@state_path}: #{ex.message}")
    end

    private def persist_term : Nil
      persist([{"term" => @term.to_i64, "voted_for" => @voted_for}.to_json])
    end

    # One JSON line to a member and its one-line answer, nil when there
    # is none in time.
    private def request(node : ClusterNodeInfo, message, timeout : Time::Span) : JSON::Any?
      socket = TCPSocket.new(node.host, node.port, connect_timeout: timeout)
      begin
        socket.read_timeout = timeout
        socket.puts(message.to_json)
        socket.gets.try { |line| JSON.parse(line) }
      ensure
        socket.close
      end
    rescue ex
      CogUtil::Logger.debug("No answer from node #{node.id}: #{ex.message}")
      nil
    end

    # This node's atom of the same content, if it has one.
    private def stored(atom : Atom) : Atom?
      return @local_atomspace.get_nodes_by_name(atom.name, atom.type).first? unless atom.is_a?(Link)
      parts = [] of Atom
      atom.outgoing.each do |part|
        parts << (stored(part) || return nil)
      end
      link_over(atom.type, parts)
    end

    private def link_over(type : AtomType, parts : Array(Atom)) : Atom?
      first = parts.first? || return nil
      handles = parts.map(&.handle)
      @local_atomspace.get_incoming(first).find do |candidate|
        candidate.type == type && candidate.outgoing.map(&.handle) == handles
      end
    end

    # Put a committed atom in the local AtomSpace. One that is there
    # takes the truth value given, with no merging; its parts are made
    # where they are missing and otherwise left as they are.
    private def place(data : JSON::Any, top : Bool = true) : Atom?
      type = AtomType.parse(data["type"].as_s)
      truth = SimpleTruthValue.new(data["truth_strength"].as_f, data["truth_confidence"].as_f)

      existing = nil
      parts = [] of Atom
      if type.node?
        existing = @local_atomspace.get_nodes_by_name(data["name"].as_s, type).first?
      else
        data["outgoing_atoms"].as_a.each do |part|
          parts << (place(part, false) || return nil)
        end
        existing = link_over(type, parts)
      end

      if existing
        existing.truth_value = truth if top
        return existing
      end
      if type.node?
        @local_atomspace.add_node(type, data["name"].as_s, truth)
      elsif type == AtomType::INHERITANCE_LINK && parts.size == 2
        @local_atomspace.add_inheritance_link(parts[0], parts[1], truth)
      elsif type == AtomType::EVALUATION_LINK && parts.size == 2
        @local_atomspace.add_evaluation_link(parts[0], parts[1], truth)
      elsif type == AtomType::LIST_LINK
        @local_atomspace.add_list_link(parts, truth)
      else
        @local_atomspace.add_link(type, parts, truth)
      end
    rescue ex
      CogUtil::Logger.error("Committed atom not placed: #{ex.message}")
      nil
    end

    private def handle_conflict_resolution(message : JSON::Any)
      # Handle conflict resolution messages
      CogUtil::Logger.debug("Received conflict resolution message")
    end

    private def perform_initial_sync
      # Perform initial synchronization when joining cluster
      CogUtil::Logger.info("Starting initial cluster synchronization")
      full_cluster_sync
    end

    private def sync_with_node(node_id : String) : Bool
      # Synchronize with a specific node
      node = @cluster_nodes[node_id]?
      return false unless node

      # Implementation would involve requesting missing atoms
      # and sending local atoms that the remote node is missing
      true
    end

    getter :local_node
  end

  # Conflict information structure
  struct ConflictInfo
    property sync_operation : SyncOperation
    property conflict_type : String
    property timestamp : Time

    def initialize(@sync_operation : SyncOperation, @conflict_type : String)
      @timestamp = Time.utc
    end
  end

  # Handles conflict resolution using different strategies
  class ConflictResolver
    def initialize(@strategy : SyncStrategy)
    end

    def resolve(conflict : ConflictInfo, incoming_atom : Atom) : Atom
      case @strategy
      when SyncStrategy::LastWriteWins
        # Return the atom from the most recent operation
        incoming_atom
      when SyncStrategy::MergeUsingTruthValues
        # Merge truth values if possible
        merge_truth_values(incoming_atom, conflict)
      when SyncStrategy::VectorClock
        # Use vector clock to determine precedence
        resolve_using_vector_clock(incoming_atom, conflict)
      when SyncStrategy::ConsensusVoting
        # Would require network consensus - simplified here
        incoming_atom
      else
        incoming_atom
      end
    end

    private def merge_truth_values(atom : Atom, conflict : ConflictInfo) : Atom
      # Simple truth value merging - in practice would be more sophisticated
      atom
    end

    private def resolve_using_vector_clock(atom : Atom, conflict : ConflictInfo) : Atom
      # Vector clock based resolution
      atom
    end
  end

  # Manages cluster membership and discovery
  class ClusterMembershipManager
    def initialize(@cluster_id : String, @node_id : String)
    end

    def discover_peers : Array(ClusterNodeInfo)
      # Implement peer discovery mechanism
      # Could use multicast, service discovery, etc.
      [] of ClusterNodeInfo
    end
  end
end
