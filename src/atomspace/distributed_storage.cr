# Distributed Storage Node for AtomSpace Clustering
# Provides storage backend that automatically synchronizes with cluster nodes
# and implements data partitioning and replication strategies.

require "./storage"
require "./distributed_cluster"

module AtomSpace
  # Data partitioning strategy
  enum PartitionStrategy
    RoundRobin      # Distribute atoms in round-robin fashion
    HashBased       # Use atom handle hash for consistent partitioning
    TypeBased       # Partition based on atom type
    LoadBalanced    # Dynamic partitioning based on node load
  end

  # Replication strategy
  enum ReplicationStrategy
    SingleCopy      # No replication - single copy per atom
    PrimaryBackup   # Primary node + backup copies
    FullReplication # Replicate to all nodes
    QuorumBased     # Replicate to quorum of nodes
  end

  # Storage node that participates in distributed clustering
  class DistributedStorageNode < StorageNode
    property cluster : DistributedAtomSpaceCluster
    property partition_strategy : PartitionStrategy
    property replication_strategy : ReplicationStrategy
    property replication_factor : Int32

    @local_storage : StorageNode
    @partition_map : Hash(String, String)  # atom_handle -> responsible_node_id
    @replica_map : Hash(String, Array(String))  # atom_handle -> replica_node_ids

    def initialize(name : String, @cluster : DistributedAtomSpaceCluster,
                   local_storage_backend : String = "file",
                   storage_path : String = "./distributed_storage",
                   @partition_strategy : PartitionStrategy = PartitionStrategy::HashBased,
                   @replication_strategy : ReplicationStrategy = ReplicationStrategy::PrimaryBackup,
                   @replication_factor : Int32 = 2)
      super(name)
      
      @partition_map = Hash(String, String).new
      @replica_map = Hash(String, Array(String)).new
      
      # Create local storage backend
      @local_storage = create_local_storage(local_storage_backend, storage_path)
      
      # Set up cluster event observers
      @cluster.add_event_observer(->(event : ClusterEvent, node_id : String) {
        handle_cluster_event(event, node_id)
      })

      log_info("DistributedStorageNode created with #{partition_strategy} partitioning and #{replication_strategy} replication")
    end

    private def find_cluster_node(node_id : String) : ClusterNodeInfo?
      @cluster.cluster_nodes.find { |node| node.id == node_id }
    end

    def open : Bool
      success = @local_storage.open
      log_info("DistributedStorageNode opened, local backend: #{success}")
      success
    end

    def close : Bool
      success = @local_storage.close
      log_info("DistributedStorageNode closed")
      success
    end

    def connected? : Bool
      @local_storage.connected?
    end

    def store_atom(atom : Atom) : Bool
      handle_str = atom.handle.to_s
      
      # Determine responsible node for this atom
      responsible_node = determine_responsible_node(handle_str)
      replica_nodes = determine_replica_nodes(handle_str, responsible_node)
      
      # Update partition and replica maps
      @partition_map[handle_str] = responsible_node
      @replica_map[handle_str] = replica_nodes

      success = true

      # Store locally if this node is responsible or a replica
      if responsible_node == @cluster.node_id || replica_nodes.includes?(@cluster.node_id)
        success = @local_storage.store_atom(atom)
        log_debug("Stored atom locally: #{atom}") if success
      end

      # Replicate to other nodes if this is the responsible node
      if responsible_node == @cluster.node_id
        replica_nodes.each do |node_id|
          unless replicate_atom_to_node(atom, node_id)
            log_error("Failed to replicate atom to node #{node_id}")
            success = false
          end
        end
      end

      success
    end

    def fetch_atom(handle : Handle) : Atom?
      handle_str = handle.to_s
      
      # Check local storage first
      if atom = @local_storage.fetch_atom(handle)
        return atom
      end

      # If not found locally, check if we know which node has it
      if responsible_node = @partition_map[handle_str]?
        if responsible_node != @cluster.node_id
          return fetch_atom_from_node(handle, responsible_node)
        end
      end

      # Fallback: search all cluster nodes
      @cluster.cluster_nodes.each do |node_info|
        next if node_info.id == @cluster.node_id
        
        if atom = fetch_atom_from_node(handle, node_info.id)
          # Cache the partition info for future lookups
          @partition_map[handle_str] = node_info.id
          return atom
        end
      end

      nil
    end

    def remove_atom(atom : Atom) : Bool
      handle_str = atom.handle.to_s
      responsible_node = @partition_map[handle_str]?
      replica_nodes = @replica_map[handle_str]? || [] of String

      success = true

      # Remove locally if present
      if @local_storage.fetch_atom(atom.handle)
        success = @local_storage.remove_atom(atom)
      end

      # Remove from replica nodes if this is the responsible node
      if responsible_node == @cluster.node_id
        replica_nodes.each do |node_id|
          unless remove_atom_from_node(atom, node_id)
            log_error("Failed to remove atom from replica node #{node_id}")
            success = false
          end
        end
      end

      # Clean up partition maps
      @partition_map.delete(handle_str)
      @replica_map.delete(handle_str)

      success
    end

    def store_atomspace(atomspace : AtomSpace) : Bool
      success = true
      
      atomspace.get_all_atoms.each do |atom|
        success = false unless store_atom(atom)
      end

      log_info("Stored AtomSpace (#{atomspace.size} atoms) with success: #{success}")
      success
    end

    def load_atomspace(atomspace : AtomSpace) : Bool
      # Load from local storage
      local_success = @local_storage.load_atomspace(atomspace)
      local_count = atomspace.size

      # Fetch missing atoms from other cluster nodes
      cluster_count = 0
      @cluster.cluster_nodes.each do |node_info|
        next if node_info.id == @cluster.node_id
        
        node_atoms = fetch_all_atoms_from_node(node_info.id)
        node_atoms.each do |atom|
          unless atomspace.contains?(atom)
            atomspace.add_atom(atom)
            cluster_count += 1
          end
        end
      end

      log_info("Loaded AtomSpace: #{local_count} local atoms, #{cluster_count} from cluster")
      local_success
    end

    def get_stats : Hash(String, String | Int32 | Int64)
      local_stats = @local_storage.get_stats
      
      stats = Hash(String, String | Int32 | Int64).new
      stats["type"] = "DistributedStorage"
      stats["cluster_id"] = @cluster.cluster_id
      stats["node_id"] = @cluster.node_id
      stats["partition_strategy"] = @partition_strategy.to_s
      stats["replication_strategy"] = @replication_strategy.to_s
      stats["replication_factor"] = @replication_factor
      stats["local_backend"] = local_stats["type"]
      stats["local_atoms"] = local_stats["atom_count"]? || 0_i64
      stats["partition_map_size"] = @partition_map.size.to_i64
      stats["replica_map_size"] = @replica_map.size.to_i64
      stats["cluster_nodes"] = @cluster.cluster_nodes.size.to_i64

      # Calculate distribution statistics
      local_partitions = @partition_map.values.count { |node| node == @cluster.node_id }
      stats["local_partitions"] = local_partitions.to_i64
      
      replica_count = @replica_map.values.sum { |replicas| replicas.includes?(@cluster.node_id) ? 1 : 0 }
      stats["local_replicas"] = replica_count.to_i64

      stats
    end

    # Rebalance data across cluster nodes
    def rebalance_cluster : Bool
      log_info("Starting cluster rebalancing")
      
      # Get current load distribution
      node_loads = calculate_node_loads
      
      # Identify over-loaded and under-loaded nodes
      avg_load = node_loads.values.sum / node_loads.size
      overloaded = node_loads.select { |_, load| load > avg_load * 1.2 }
      underloaded = node_loads.select { |_, load| load < avg_load * 0.8 }

      # Move partitions from overloaded to underloaded nodes
      migrations = plan_migrations(overloaded, underloaded)
      
      success = true
      migrations.each do |migration|
        unless execute_migration(migration)
          success = false
          log_error("Failed to execute migration: #{migration}")
        end
      end

      @cluster.emit_event(ClusterEvent::PARTITION_REBALANCED, @cluster.node_id) if success
      log_info("Cluster rebalancing completed: #{success}")
      success
    end

    # Get data distribution metrics
    def distribution_metrics : Hash(String, JSON::Any)
      node_loads = calculate_node_loads
      total_atoms = @partition_map.size

      metrics = Hash(String, JSON::Any).new
      metrics["total_atoms"] = JSON::Any.new(total_atoms.to_i64)
      metrics["average_load"] = JSON::Any.new(total_atoms.to_f / @cluster.cluster_nodes.size)
      
      node_metrics = {} of String => JSON::Any
      node_loads.each do |node_id, load|
        node_data = {
          "atom_count" => JSON::Any.new(load.to_i64),
          "load_percentage" => JSON::Any.new((load.to_f / total_atoms * 100).round(2))
        }
        node_metrics[node_id] = JSON::Any.new(node_data)
      end
      
      metrics["node_distribution"] = JSON::Any.new(node_metrics)
      
      # Calculate load balance score (closer to 1.0 is better)
      if total_atoms > 0
        ideal_load = total_atoms.to_f / @cluster.cluster_nodes.size
        variance = node_loads.values.sum { |load| (load - ideal_load) ** 2 } / @cluster.cluster_nodes.size
        balance_score = 1.0 / (1.0 + Math.sqrt(variance) / ideal_load)
        metrics["balance_score"] = JSON::Any.new(balance_score)
      else
        metrics["balance_score"] = JSON::Any.new(1.0)
      end

      metrics
    end

    private def create_local_storage(backend_type : String, storage_path : String) : StorageNode
      case backend_type.downcase
      when "file"
        FileStorageNode.new("#{name}_local", "#{storage_path}/#{@cluster.node_id}.scm")
      when "sqlite", "db"
        SQLiteStorageNode.new("#{name}_local", "#{storage_path}/#{@cluster.node_id}.db")
      else
        FileStorageNode.new("#{name}_local", "#{storage_path}/#{@cluster.node_id}.scm")
      end
    end

    private def determine_responsible_node(atom_handle : String) : String
      case @partition_strategy
      when PartitionStrategy::RoundRobin
        node_index = atom_handle.hash.abs % @cluster.cluster_nodes.size
        @cluster.cluster_nodes.to_a[node_index].id
      when PartitionStrategy::HashBased
        consistent_hash_node(atom_handle)
      when PartitionStrategy::TypeBased
        # Would need atom type information - simplified here
        consistent_hash_node(atom_handle)
      when PartitionStrategy::LoadBalanced
        least_loaded_node
      else
        consistent_hash_node(atom_handle)
      end
    end

    private def consistent_hash_node(key : String) : String
      # Simple consistent hashing implementation
      node_list = @cluster.cluster_nodes.map(&.id).sort
      hash_value = key.hash.abs.to_u64
      
      node_list.each do |node_id|
        node_hash = node_id.hash.abs.to_u64
        return node_id if hash_value <= node_hash
      end
      
      node_list.first
    end

    private def least_loaded_node : String
      loads = calculate_node_loads
      loads.min_by { |_, load| load }[0]
    end

    private def determine_replica_nodes(atom_handle : String, responsible_node : String) : Array(String)
      case @replication_strategy
      when ReplicationStrategy::SingleCopy
        [] of String
      when ReplicationStrategy::PrimaryBackup
        select_backup_nodes(responsible_node, @replication_factor - 1)
      when ReplicationStrategy::FullReplication
        @cluster.cluster_nodes.map(&.id).reject { |id| id == responsible_node }
      when ReplicationStrategy::QuorumBased
        quorum_size = (@cluster.cluster_nodes.size // 2) + 1
        select_backup_nodes(responsible_node, quorum_size - 1)
      else
        [] of String
      end
    end

    private def select_backup_nodes(exclude_node : String, count : Int32) : Array(String)
      available_nodes = @cluster.cluster_nodes.map(&.id).reject { |id| id == exclude_node }
      available_nodes.sample(Math.min(count, available_nodes.size))
    end

    private def replicate_atom_to_node(atom : Atom, node_id : String) : Bool
      node_info = find_cluster_node(node_id)
      return false unless node_info

      begin
        message = {
          "type" => "replicate_atom",
          "atom_data" => serialize_atom_for_replication(atom),
          "source_node" => @cluster.node_id
        }

        send_message_to_node(node_info, message)
      rescue ex
        log_error("Failed to replicate atom to node #{node_id}: #{ex.message}")
        false
      end
    end

    private def fetch_atom_from_node(handle : Handle, node_id : String) : Atom?
      node_info = find_cluster_node(node_id)
      return nil unless node_info

      begin
        message = {
          "type" => "fetch_atom",
          "atom_handle" => handle.to_s,
          "requesting_node" => @cluster.node_id
        }

        response = send_message_to_node_with_response(node_info, message)
        return nil unless response

        if response["status"] == "found"
          if atom_data = response["atom_data"]?
            return deserialize_atom_from_replication(atom_data.as_h)
          end
        end
      rescue ex
        log_error("Failed to fetch atom from node #{node_id}: #{ex.message}")
      end

      nil
    end

    private def remove_atom_from_node(atom : Atom, node_id : String) : Bool
      node_info = find_cluster_node(node_id)
      return false unless node_info

      begin
        message = {
          "type" => "remove_atom",
          "atom_handle" => atom.handle.to_s,
          "source_node" => @cluster.node_id
        }

        send_message_to_node(node_info, message)
      rescue ex
        log_error("Failed to remove atom from node #{node_id}: #{ex.message}")
        false
      end
    end

    private def fetch_all_atoms_from_node(node_id : String) : Array(Atom)
      node_info = find_cluster_node(node_id)
      return [] of Atom unless node_info

      begin
        message = {
          "type" => "fetch_all_atoms",
          "requesting_node" => @cluster.node_id
        }

        response = send_message_to_node_with_response(node_info, message)
        return [] of Atom unless response

        if response["status"] == "success"
          if atoms_data = response["atoms"]?
            return atoms_data.as_a.compact_map { |atom_json|
              deserialize_atom_from_replication(atom_json.as_h)
            }
          end
        end
      rescue ex
        log_error("Failed to fetch all atoms from node #{node_id}: #{ex.message}")
      end

      [] of Atom
    end

    private def send_message_to_node(node_info : ClusterNodeInfo, message : Hash) : Bool
      begin
        socket = TCPSocket.new(node_info.host, node_info.port)
        socket.puts(message.to_json)
        socket.close
        true
      rescue ex
        log_error("Failed to send message to node #{node_info.id}: #{ex.message}")
        false
      end
    end

    private def send_message_to_node_with_response(node_info : ClusterNodeInfo, message : Hash) : JSON::Any?
      begin
        socket = TCPSocket.new(node_info.host, node_info.port)
        socket.puts(message.to_json)
        
        response_data = socket.gets
        socket.close
        
        return JSON.parse(response_data) if response_data
      rescue ex
        log_error("Failed to send message with response to node #{node_info.id}: #{ex.message}")
      end

      nil
    end

    private def serialize_atom_for_replication(atom : Atom) : Hash(String, JSON::Any)
      # Use the same serialization as the cluster
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

    private def deserialize_atom_from_replication(data : Hash(String, JSON::Any)) : Atom?
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
          # Simplified implementation
          return Link.new(type, [] of Atom, tv)
        end
      rescue ex
        log_error("Failed to deserialize atom from replication: #{ex.message}")
        nil
      end
    end

    private def calculate_node_loads : Hash(String, Int32)
      loads = Hash(String, Int32).new
      
      # Initialize all nodes with zero load
      @cluster.cluster_nodes.each do |node_info|
        loads[node_info.id] = 0
      end

      # Count atoms per node based on partition map
      @partition_map.each_value do |node_id|
        loads[node_id] = loads[node_id] + 1
      end

      loads
    end

    private def plan_migrations(overloaded : Hash(String, Int32), underloaded : Hash(String, Int32)) : Array(MigrationPlan)
      migrations = [] of MigrationPlan
      
      overloaded.each do |source_node, load|
        target_nodes = underloaded.keys
        next if target_nodes.empty?
        
        # Calculate how many atoms to move
        avg_load = (@partition_map.size / @cluster.cluster_nodes.size).to_i
        atoms_to_move = load - avg_load
        
        # Select atoms to migrate (simplified - would use better heuristics)
        atoms_to_migrate = @partition_map.select { |_, node| node == source_node }.keys.first(atoms_to_move)
        
        atoms_to_migrate.each_with_index do |atom_handle, index|
          target_node = target_nodes[index % target_nodes.size]
          migrations << MigrationPlan.new(atom_handle, source_node, target_node)
        end
      end

      migrations
    end

    private def execute_migration(migration : MigrationPlan) : Bool
      # Move atom from source to target node
      # This would involve coordination between nodes
      log_debug("Executing migration: #{migration.atom_handle} from #{migration.source_node} to #{migration.target_node}")
      
      # Update partition map
      @partition_map[migration.atom_handle] = migration.target_node
      
      true  # Simplified - real implementation would handle actual data movement
    end

    private def handle_cluster_event(event : ClusterEvent, node_id : String)
      case event
      when ClusterEvent::NODE_JOINED
        log_info("New node joined cluster: #{node_id}")
        # Could trigger rebalancing
      when ClusterEvent::NODE_LEFT
        log_info("Node left cluster: #{node_id}")
        # Should trigger data redistribution for lost partitions
        handle_node_departure(node_id)
      end
    end

    private def handle_node_departure(departed_node : String)
      # Find atoms that were stored on the departed node
      orphaned_atoms = @partition_map.select { |_, node| node == departed_node }.keys
      
      log_info("Handling departure of node #{departed_node}, #{orphaned_atoms.size} orphaned atoms")
      
      # Reassign orphaned atoms to other nodes
      orphaned_atoms.each do |atom_handle|
        new_responsible_node = determine_responsible_node(atom_handle)
        @partition_map[atom_handle] = new_responsible_node
      end
    end

    # Migration plan structure
    struct MigrationPlan
      property atom_handle : String
      property source_node : String
      property target_node : String

      def initialize(@atom_handle : String, @source_node : String, @target_node : String)
      end
    end
  end
end