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
  struct ClusterNodeInfo
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
    property operation_type : String  # "add", "update", "remove"
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

  # Main distributed AtomSpace cluster coordination class
  class DistributedAtomSpaceCluster
    property cluster_id : String
    property node_id : String
    property local_atomspace : AtomSpace
    property sync_strategy : SyncStrategy
    
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

    def initialize(@cluster_id : String, @local_atomspace : AtomSpace, 
                   host : String = "localhost", port : Int32 = 0,
                   @sync_strategy : SyncStrategy = SyncStrategy::MergeUsingTruthValues)
      @node_id = UUID.random.to_s
      @cluster_nodes = Hash(String, ClusterNodeInfo).new
      @vector_clock = Hash(String, UInt64).new
      @pending_sync_ops = [] of SyncOperation
      @event_observers = [] of Proc(ClusterEvent, String, Nil)

      # Initialize cluster node info for this node
      actual_port = port == 0 ? find_available_port : port
      @local_node = ClusterNodeInfo.new(@node_id, host, actual_port)
      @local_node.status = NodeStatus::Initializing
      @cluster_nodes[@node_id] = @local_node

      @conflict_resolver = ConflictResolver.new(@sync_strategy)
      @membership_manager = ClusterMembershipManager.new(@cluster_id, @node_id)

      # Set up AtomSpace event observers for local changes
      setup_atomspace_observers

      CogUtil::Logger.info("DistributedAtomSpaceCluster #{@cluster_id} node #{@node_id} initialized")
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
      sleep 0.1
      
      emit_event(ClusterEvent::NODE_LEFT, @node_id)
      CogUtil::Logger.info("Cluster node #{@node_id} stopped")
    end

    # Join an existing cluster by connecting to a seed node
    def join_cluster(seed_host : String, seed_port : Int32) : Bool
      begin
        socket = TCPSocket.new(seed_host, seed_port)

        join_request = {
          "type" => "cluster_join_request",
          "cluster_id" => @cluster_id,
          "node_id" => @node_id,
          "host" => @local_node.host,
          "port" => @local_node.port,
          "timestamp" => Time.utc.to_rfc3339
        }

        socket.puts(join_request.to_json)

        response_data = socket.gets
        if response_data
          response = JSON.parse(response_data)
          if response["status"] == "accepted"
            # Update cluster membership from seed response
            if cluster_nodes = response["cluster_nodes"]?
              cluster_nodes.as_a.each do |node_data|
                node_info = ClusterNodeInfo.new(
                  node_data["id"].as_s,
                  node_data["host"].as_s,
                  node_data["port"].as_i
                )
                node_info.status = NodeStatus.parse(node_data["status"].as_s)
                node_info.atomspace_size = node_data["atomspace_size"].as_i64.to_u64
                @cluster_nodes[node_info.id] = node_info
              end
            end

            # Start initial synchronization
            spawn do
              perform_initial_sync
            end

            CogUtil::Logger.info("Successfully joined cluster #{@cluster_id}")
            return true
          end
        end

        socket.close
        return false
      rescue ex
        CogUtil::Logger.error("Failed to join cluster: #{ex.message}")
        return false
      end
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

      {
        "cluster_id" => JSON::Any.new(@cluster_id),
        "total_nodes" => JSON::Any.new(@cluster_nodes.size.to_i64),
        "active_nodes" => JSON::Any.new(active_nodes.to_i64),
        "total_atoms" => JSON::Any.new(total_atoms.to_i64),
        "local_atomspace_size" => JSON::Any.new(@local_atomspace.size.to_i64),
        "pending_sync_operations" => JSON::Any.new(@pending_sync_ops.size.to_i64),
        "sync_strategy" => JSON::Any.new(@sync_strategy.to_s),
        "local_node_status" => JSON::Any.new(@local_node.status.to_s)
      }
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
          spawn do
            handle_cluster_client(client)
          end
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
      when "conflict_resolution"
        handle_conflict_resolution(message)
      else
        CogUtil::Logger.warn("Unknown cluster message type: #{message_type}")
      end
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
      @cluster_nodes[node_id] = new_node

      # Send acceptance response with current cluster state
      response = {
        "status" => "accepted",
        "cluster_nodes" => @cluster_nodes.values.map { |node|
          {
            "id" => node.id,
            "host" => node.host,
            "port" => node.port,
            "status" => node.status.to_s,
            "atomspace_size" => node.atomspace_size
          }
        }
      }

      client.try(&.puts(response.to_json))

      emit_event(ClusterEvent::NODE_JOINED, node_id)
      CogUtil::Logger.info("New node #{node_id} joined cluster")
    end

    private def handle_heartbeat(message : JSON::Any)
      node_id = message["node_id"].as_s
      
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
          "type" => "heartbeat",
          "node_id" => @node_id,
          "status" => @local_node.status.to_s,
          "atomspace_size" => @local_node.atomspace_size,
          "load_factor" => @local_node.load_factor,
          "timestamp" => Time.utc.to_rfc3339
        }

        broadcast_message(heartbeat_message)

        # Clean up stale nodes
        @cluster_nodes.reject! do |node_id, node|
          if node_id != @node_id && node.is_stale?
            emit_event(ClusterEvent::NODE_LEFT, node_id)
            CogUtil::Logger.info("Removed stale node #{node_id} from cluster")
            true
          else
            false
          end
        end

        sleep 30 # Heartbeat every 30 seconds
      end
    end

    private def sync_loop
      while @running
        process_pending_sync_operations
        sleep 5 # Process sync operations every 5 seconds
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
        "type" => "sync_operation",
        "id" => sync_op.id,
        "operation_type" => sync_op.operation_type,
        "atom_handle" => sync_op.atom_handle,
        "source_node" => sync_op.source_node,
        "timestamp" => sync_op.timestamp.to_rfc3339,
        "atom_data" => sync_op.atom_data,
        "vector_clock" => sync_op.vector_clock
      }

      broadcast_message(message)
    end

    private def broadcast_message(message : Hash)
      @cluster_nodes.each_value do |node|
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
          # For links, we'd need to resolve outgoing atoms
          # This is simplified - real implementation would handle recursive resolution
          return Link.new(type, [] of Atom, tv)
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
      base_load = @local_atomspace.size.to_f / 10000.0  # Normalize to 10k atoms
      sync_load = @pending_sync_ops.size.to_f / 100.0   # Normalize to 100 ops
      Math.min(1.0, base_load + sync_load)
    end

    private def find_available_port : Int32
      (25000..26000).each do |port|
        begin
          server = TCPServer.new("localhost", port)
          server.close
          return port
        rescue
          # Port in use, try next
        end
      end
      Random.rand(26000..30000)
    end

    private def emit_event(event : ClusterEvent, node_id : String)
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
        "type" => "cluster_departure",
        "node_id" => @node_id,
        "timestamp" => Time.utc.to_rfc3339
      }

      broadcast_message(departure_message)
    end

    private def handle_departure(message : JSON::Any)
      node_id = message["node_id"].as_s
      if @cluster_nodes.delete(node_id)
        emit_event(ClusterEvent::NODE_LEFT, node_id)
        CogUtil::Logger.info("Node #{node_id} left cluster")
      end
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