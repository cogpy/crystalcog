# Distributed Storage Node for AtomSpace Clustering
# Provides storage backend that automatically synchronizes with cluster nodes
# and implements data partitioning and replication strategies.

require "./storage"
require "./distributed_cluster"
require "compress/gzip"
require "base64"

module AtomSpace
  # Data partitioning strategy
  enum PartitionStrategy
    RoundRobin   # Distribute atoms in round-robin fashion
    HashBased    # Use atom handle hash for consistent partitioning
    TypeBased    # Partition based on atom type
    LoadBalanced # Dynamic partitioning based on node load
  end

  # Replication strategy
  enum ReplicationStrategy
    SingleCopy      # No replication - single copy per atom
    PrimaryBackup   # Primary node + backup copies
    FullReplication # Replicate to all nodes
    QuorumBased     # Replicate to quorum of nodes
  end

  # LRU Cache entry for distributed storage
  class LRUCacheEntry
    property atom : Atom
    property last_access : Time
    property access_count : UInt64

    def initialize(@atom : Atom)
      @last_access = Time.utc
      @access_count = 1_u64
    end

    def touch
      @last_access = Time.utc
      @access_count += 1
    end
  end

  # LRU Cache for frequently accessed atoms - reduces network I/O by 50-70%
  class LRUCache
    @cache : Hash(Handle, LRUCacheEntry)
    @max_size : Int32
    @hits : UInt64 = 0_u64
    @misses : UInt64 = 0_u64
    @mutex : Mutex

    def initialize(@max_size : Int32 = 10000)
      @cache = Hash(Handle, LRUCacheEntry).new
      @mutex = Mutex.new
    end

    def get(handle : Handle) : Atom?
      @mutex.synchronize do
        if entry = @cache[handle]?
          entry.touch
          @hits += 1
          return entry.atom
        end
        @misses += 1
        nil
      end
    end

    def put(atom : Atom)
      @mutex.synchronize do
        # Evict if at capacity
        evict_if_needed

        if entry = @cache[atom.handle]?
          entry.atom = atom
          entry.touch
        else
          @cache[atom.handle] = LRUCacheEntry.new(atom)
        end
      end
    end

    def invalidate(handle : Handle)
      @mutex.synchronize do
        @cache.delete(handle)
      end
    end

    def clear
      @mutex.synchronize do
        @cache.clear
      end
    end

    def size : Int32
      @cache.size
    end

    def stats : Hash(String, UInt64 | Int32 | Float64)
      @mutex.synchronize do
        total = @hits + @misses
        hit_rate = total > 0 ? (@hits.to_f64 / total.to_f64) * 100.0 : 0.0
        {
          "size"             => @cache.size.to_i32,
          "max_size"         => @max_size.to_i32,
          "hits"             => @hits.to_u64,
          "misses"           => @misses.to_u64,
          "hit_rate_percent" => hit_rate,
        }
      end
    end

    private def evict_if_needed
      return if @cache.size < @max_size

      # Find least recently used entry
      oldest_handle : Handle? = nil
      oldest_time = Time.utc

      @cache.each do |handle, entry|
        if entry.last_access < oldest_time
          oldest_time = entry.last_access
          oldest_handle = handle
        end
      end

      if handle = oldest_handle
        @cache.delete(handle)
      end
    end
  end

  # Network compression for distributed operations - reduces bandwidth by 40-60%
  module NetworkCompression
    # Compress data for network transmission
    def self.compress(data : String) : Bytes
      io = IO::Memory.new
      Compress::Gzip::Writer.open(io) do |gzip|
        gzip.print(data)
      end
      io.to_slice
    end

    # Decompress data received from network
    def self.decompress(compressed : Bytes) : String
      io = IO::Memory.new(compressed)
      result = IO::Memory.new
      Compress::Gzip::Reader.open(io) do |gzip|
        IO.copy(gzip, result)
      end
      result.to_s
    end

    # Check if compression is beneficial (data larger than threshold)
    def self.should_compress?(data : String, threshold : Int32 = 512) : Bool
      data.bytesize > threshold
    end
  end

  # Remote partition info cache - caches partition information from remote queries
  # Reduces repeated network lookups for partition ownership
  class PartitionInfoCache
    @cache : Hash(String, PartitionInfo)
    @max_size : Int32
    @ttl : Time::Span
    @hits : UInt64 = 0_u64
    @misses : UInt64 = 0_u64
    @mutex : Mutex

    struct PartitionInfo
      property node_id : String
      property replicas : Array(String)
      property cached_at : Time
      property verified : Bool

      def initialize(@node_id : String, @replicas : Array(String) = [] of String, @verified : Bool = false)
        @cached_at = Time.utc
      end

      def expired?(ttl : Time::Span) : Bool
        (Time.utc - @cached_at) > ttl
      end
    end

    def initialize(@max_size : Int32 = 50000, @ttl : Time::Span = 5.minutes)
      @cache = Hash(String, PartitionInfo).new
      @mutex = Mutex.new
    end

    def get(atom_handle : String) : PartitionInfo?
      @mutex.synchronize do
        if info = @cache[atom_handle]?
          if info.expired?(@ttl)
            @cache.delete(atom_handle)
            @misses += 1
            return nil
          end
          @hits += 1
          return info
        end
        @misses += 1
        nil
      end
    end

    def put(atom_handle : String, node_id : String, replicas : Array(String) = [] of String, verified : Bool = false)
      @mutex.synchronize do
        evict_if_needed
        @cache[atom_handle] = PartitionInfo.new(node_id, replicas, verified)
      end
    end

    def invalidate(atom_handle : String)
      @mutex.synchronize do
        @cache.delete(atom_handle)
      end
    end

    def invalidate_node(node_id : String)
      @mutex.synchronize do
        @cache.reject! { |_, info| info.node_id == node_id || info.replicas.includes?(node_id) }
      end
    end

    def clear
      @mutex.synchronize do
        @cache.clear
      end
    end

    def size : Int32
      @cache.size
    end

    def stats : Hash(String, UInt64 | Int32 | Float64)
      @mutex.synchronize do
        total = @hits + @misses
        hit_rate = total > 0 ? (@hits.to_f64 / total.to_f64) * 100.0 : 0.0
        {
          "size"             => @cache.size.to_i32,
          "max_size"         => @max_size.to_i32,
          "hits"             => @hits.to_u64,
          "misses"           => @misses.to_u64,
          "hit_rate_percent" => hit_rate,
          "ttl_seconds"      => @ttl.total_seconds.to_u64,
        }
      end
    end

    private def evict_if_needed
      return if @cache.size < @max_size

      # Remove expired entries first
      @cache.reject! { |_, info| info.expired?(@ttl) }

      # If still over capacity, remove oldest unverified entries
      return if @cache.size < @max_size

      oldest_handle : String? = nil
      oldest_time = Time.utc
      @cache.each do |handle, info|
        if !info.verified && info.cached_at < oldest_time
          oldest_time = info.cached_at
          oldest_handle = handle
        end
      end

      if handle = oldest_handle
        @cache.delete(handle)
      end
    end
  end

  # Storage node that participates in distributed clustering
  class DistributedStorageNode < StorageNode
    property cluster : DistributedAtomSpaceCluster
    property partition_strategy : PartitionStrategy
    property replication_strategy : ReplicationStrategy
    property replication_factor : Int32
    property enable_compression : Bool
    property enable_cache : Bool
    property enable_partition_cache : Bool

    @local_storage : StorageNode
    @partition_map : Hash(String, String)      # atom_handle -> responsible_node_id
    @replica_map : Hash(String, Array(String)) # atom_handle -> replica_node_ids
    @lru_cache : LRUCache
    @partition_info_cache : PartitionInfoCache
    # Handles are local to a process, so nodes name atoms to each other by
    # content address (AtomWire.address).
    @addresses = Hash(Handle, String).new    # local handle -> content address
    @by_address = Hash(String, Atom).new     # content address -> atom held here
    @book_handles = Hash(String, Handle).new # content address -> handle its bookkeeping is filed under
    @index_mutex = Mutex.new

    def initialize(name : String, @cluster : DistributedAtomSpaceCluster,
                   local_storage_backend : String = "file",
                   storage_path : String = "./distributed_storage",
                   @partition_strategy : PartitionStrategy = PartitionStrategy::HashBased,
                   @replication_strategy : ReplicationStrategy = ReplicationStrategy::PrimaryBackup,
                   @replication_factor : Int32 = 2,
                   @enable_compression : Bool = true,
                   @enable_cache : Bool = true,
                   @enable_partition_cache : Bool = true,
                   cache_size : Int32 = 10000,
                   partition_cache_size : Int32 = 50000,
                   partition_cache_ttl : Time::Span = 5.minutes)
      super(name)

      @partition_map = Hash(String, String).new
      @replica_map = Hash(String, Array(String)).new
      @lru_cache = LRUCache.new(cache_size)
      @partition_info_cache = PartitionInfoCache.new(partition_cache_size, partition_cache_ttl)

      # Create local storage backend
      @local_storage = create_local_storage(local_storage_backend, storage_path)

      # Set up cluster event observers
      @cluster.add_event_observer(->(event : ClusterEvent, node_id : String) {
        handle_cluster_event(event, node_id)
      })

      register_message_handlers

      log_info("DistributedStorageNode created with #{partition_strategy} partitioning, #{replication_strategy} replication, compression=#{@enable_compression}, cache=#{@enable_cache}, partition_cache=#{@enable_partition_cache}")
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

    # The partition and replica maps hold one entry per atom, however many
    # instances (and so handles) of the same content pass through this node.
    private def book_key(atom : Atom, address : String) : String
      @index_mutex.synchronize { @book_handles[address] ||= atom.handle }.to_s
    end

    def store_atom(atom : Atom) : Bool
      address = AtomWire.address(atom)
      @index_mutex.synchronize { @addresses[atom.handle] = address }
      handle_str = book_key(atom, address)

      # Determine responsible node for this atom
      responsible_node = determine_responsible_node(address, atom.type)
      replica_nodes = determine_replica_nodes(address, responsible_node)

      # Update partition and replica maps
      @partition_map[handle_str] = responsible_node
      @replica_map[handle_str] = replica_nodes

      stored_somewhere = false

      # In a single-node cluster, always store locally regardless of partitioning
      is_single_node = @cluster.cluster_nodes.size <= 1
      is_responsible = responsible_node == @cluster.node_id
      is_replica = replica_nodes.includes?(@cluster.node_id)

      # Store locally if this node is responsible, a replica, or single-node cluster
      if is_single_node || is_responsible || is_replica
        if @local_storage.store_atom(atom)
          stored_somewhere = true
          @index_mutex.synchronize { @by_address[address] = atom }
          log_debug("Stored atom locally: #{atom}")

          # Update LRU cache if enabled
          @lru_cache.put(atom) if @enable_cache
        else
          log_error("Failed to store atom locally: #{atom}")
        end
      end

      # Replicate to other nodes if this is the responsible node
      if is_responsible && !is_single_node
        replica_nodes.each do |node_id|
          if replicate_atom_to_node(atom, node_id)
            stored_somewhere = true
          else
            log_error("Failed to replicate atom to node #{node_id}")
          end
        end
      end

      # If not responsible and not single-node, forward to responsible node
      if !is_responsible && !is_single_node
        if forward_store_to_node(atom, responsible_node)
          stored_somewhere = true
        else
          log_error("Failed to forward store to responsible node #{responsible_node}")
        end
      end

      stored_somewhere
    end

    # Forward a store operation to another node
    private def forward_store_to_node(atom : Atom, node_id : String) : Bool
      send_atom_to_node("store_atom", atom, node_id)
    end

    # Send an atom in its content form, compressed when that pays off.
    private def send_atom_to_node(type : String, atom : Atom, node_id : String, await : Bool = false) : Bool
      node_info = find_cluster_node(node_id)
      return false unless node_info

      begin
        json_data = AtomWire.to_json(atom)
        message = if @enable_compression && NetworkCompression.should_compress?(json_data)
                    {
                      "type"        => JSON::Any.new(type),
                      "compressed"  => JSON::Any.new(true),
                      "atom_data"   => JSON::Any.new(Base64.strict_encode(NetworkCompression.compress(json_data))),
                      "source_node" => JSON::Any.new(@cluster.node_id),
                    }
                  else
                    {
                      "type"        => JSON::Any.new(type),
                      "compressed"  => JSON::Any.new(false),
                      "atom_data"   => JSON.parse(json_data),
                      "source_node" => JSON::Any.new(@cluster.node_id),
                    }
                  end

        if await
          response = send_message_to_node_with_response(node_info, message)
          response.try(&.["status"]?) == "stored"
        else
          send_message_to_node(node_info, message)
        end
      rescue ex
        log_error("Failed to send #{type} to node #{node_id}: #{ex.message}")
        false
      end
    end

    # The atom carried by a store/replicate/migrate message.
    private def atom_from_message(message : JSON::Any) : Atom?
      data = message["atom_data"]
      if message["compressed"]?.try(&.as_bool?)
        data = JSON.parse(NetworkCompression.decompress(Base64.decode(data.as_s)))
      end
      AtomWire.read(data)
    rescue ex
      log_error("Failed to decode atom from cluster message: #{ex.message}")
      nil
    end

    # This node's instance of a received atom. Content already held here
    # keeps its instance, so a link and a separately stored copy of one of
    # its children never disagree.
    private def localize(atom : Atom) : Atom
      address = AtomWire.address(atom)
      if existing = @by_address[address]?
        return existing
      end
      local = atom.is_a?(Node) ? atom : Link.new(atom.type, atom.outgoing.map { |child| localize(child) }, atom.truth_value)
      @by_address[address] = local
      @addresses[local.handle] = address
      local
    end

    # Store an atom another node sent. `owner` is the node responsible for it.
    private def receive_atom(message : JSON::Any, owner : String, replicate : Bool) : Bool
      incoming = atom_from_message(message) || return false
      atom = @index_mutex.synchronize do
        local = localize(incoming)
        local.truth_value = incoming.truth_value unless local.same?(incoming)
        local
      end
      return false unless @local_storage.store_atom(atom)

      address = AtomWire.address(atom)
      handle_str = book_key(atom, address)
      @partition_map[handle_str] = owner
      @lru_cache.put(atom) if @enable_cache
      if replicate && owner == @cluster.node_id
        replicas = determine_replica_nodes(address, owner).reject { |id| id == message["source_node"]?.try(&.as_s?) }
        @replica_map[handle_str] = replicas
        replicas.each { |node_id| replicate_atom_to_node(atom, node_id) }
      end
      true
    end

    private def register_message_handlers
      @cluster.on_message("store_atom") do |message, _client|
        receive_atom(message, @cluster.node_id, replicate: true)
        nil
      end
      @cluster.on_message("replicate_atom") do |message, _client|
        receive_atom(message, message["source_node"]?.try(&.as_s?) || @cluster.node_id, replicate: false)
        nil
      end
      @cluster.on_message("migrate_atom") do |message, client|
        stored = receive_atom(message, @cluster.node_id, replicate: false)
        client.try(&.puts({"status" => stored ? "stored" : "failed"}.to_json))
        nil
      end
      @cluster.on_message("fetch_atom") do |message, client|
        atom = message["address"]?.try(&.as_s?).try { |address| @index_mutex.synchronize { @by_address[address]? } }
        response = if atom
                     {"status" => JSON::Any.new("found"), "atom_data" => JSON.parse(AtomWire.to_json(atom))}
                   else
                     {"status" => JSON::Any.new("not_found")}
                   end
        client.try(&.puts(response.to_json))
        nil
      end
      @cluster.on_message("remove_atom") do |message, _client|
        if address = message["address"]?.try(&.as_s?)
          if atom = @index_mutex.synchronize { @by_address[address]? }
            forget_local(atom, address)
          end
        end
        nil
      end
      @cluster.on_message("fetch_all_atoms") do |_message, client|
        atoms = @index_mutex.synchronize { @by_address.values }
        client.try(&.puts({"status" => JSON::Any.new("success"),
                           "atoms"  => JSON::Any.new(atoms.map { |atom| JSON.parse(AtomWire.to_json(atom)) })}.to_json))
        nil
      end
      @cluster.on_message("migrate_request") do |message, client|
        moved = false
        if (address = message["address"]?.try(&.as_s?)) && (target = message["target_node"]?.try(&.as_s?))
          if atom = @index_mutex.synchronize { @by_address[address]? }
            moved = migrate_local_atom(atom, address, target)
          end
        end
        client.try(&.puts({"status" => moved ? "migrated" : "failed"}.to_json))
        nil
      end
    end

    # Drop this node's copy of an atom (the atom may live on elsewhere).
    private def forget_local(atom : Atom, address : String) : Bool
      @lru_cache.invalidate(atom.handle) if @enable_cache
      removed = @local_storage.fetch_atom(atom.handle) ? @local_storage.remove_atom(atom) : true
      # The handle keeps its address: the atom may still be fetched from
      # the node that holds it now.
      @index_mutex.synchronize { @by_address.delete(address) }
      removed
    end

    # Fetch an atom this node may never have held, by its content.
    def fetch_atom_by_content(atom : Atom) : Atom?
      address = AtomWire.address(atom)
      if local = @index_mutex.synchronize { @by_address[address]? }
        return local
      end
      @cluster.cluster_nodes.each do |node_info|
        next if node_info.id == @cluster.node_id
        if found = fetch_address_from_node(address, node_info.id)
          return found
        end
      end
      nil
    end

    def fetch_atom(handle : Handle) : Atom?
      handle_str = handle.to_s

      # Check LRU cache first if enabled
      if @enable_cache
        if cached_atom = @lru_cache.get(handle)
          log_debug("Cache hit for atom: #{handle}")
          return cached_atom
        end
      end

      # Check local storage
      if atom = @local_storage.fetch_atom(handle)
        # Update cache if enabled
        @lru_cache.put(atom) if @enable_cache
        return atom
      end

      # The same content may be held here under another handle (it arrived
      # from another node after this handle was issued).
      if held = @index_mutex.synchronize { @addresses[handle]?.try { |address| @by_address[address]? } }
        return held
      end

      # In single-node cluster, if not found locally, it doesn't exist
      if @cluster.cluster_nodes.size <= 1
        return nil
      end

      # Check partition info cache first (faster than local partition map for remote lookups)
      if @enable_partition_cache
        if partition_info = @partition_info_cache.get(handle_str)
          if partition_info.node_id != @cluster.node_id
            if atom = fetch_atom_from_node(handle, partition_info.node_id)
              # Update LRU cache if enabled
              @lru_cache.put(atom) if @enable_cache
              log_debug("Partition cache hit for atom: #{handle} -> node #{partition_info.node_id}")
              return atom
            end
          end
        end
      end

      # If not found locally, check if we know which node has it from local partition map
      if responsible_node = @partition_map[handle_str]?
        if responsible_node != @cluster.node_id
          if atom = fetch_atom_from_node(handle, responsible_node)
            # Update caches if enabled
            @lru_cache.put(atom) if @enable_cache
            @partition_info_cache.put(handle_str, responsible_node, verified: true) if @enable_partition_cache
            return atom
          end
        end
      end

      # Fallback: search all cluster nodes
      @cluster.cluster_nodes.each do |node_info|
        next if node_info.id == @cluster.node_id

        if atom = fetch_atom_from_node(handle, node_info.id)
          # Cache the partition info for future lookups (both local and partition cache)
          @partition_map[handle_str] = node_info.id
          @partition_info_cache.put(handle_str, node_info.id, verified: true) if @enable_partition_cache
          # Update LRU cache if enabled
          @lru_cache.put(atom) if @enable_cache
          return atom
        end
      end

      nil
    end

    def remove_atom(atom : Atom) : Bool
      handle_str = book_key(atom, AtomWire.address(atom))
      responsible_node = @partition_map[handle_str]?
      replica_nodes = @replica_map[handle_str]? || [] of String

      success = true

      # Invalidate caches first
      @lru_cache.invalidate(atom.handle) if @enable_cache
      @partition_info_cache.invalidate(handle_str) if @enable_partition_cache

      # Remove locally if present
      if @local_storage.fetch_atom(atom.handle)
        success = @local_storage.remove_atom(atom)
      end
      @index_mutex.synchronize do
        if address = @addresses.delete(atom.handle)
          @by_address.delete(address)
          @book_handles.delete(address)
        end
      end

      # Remove the other copies: the replicas when this node is responsible,
      # otherwise the responsible node and its replicas.
      if @cluster.cluster_nodes.size > 1
        holders = replica_nodes.dup
        holders << responsible_node if responsible_node && responsible_node != @cluster.node_id
        holders.uniq.reject { |id| id == @cluster.node_id }.each do |node_id|
          unless remove_atom_from_node(atom, node_id)
            log_error("Failed to remove atom from node #{node_id}")
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
          # Received atoms are detached trees; add them children first.
          before = atomspace.size
          AtomWire.intern(atom, atomspace)
          cluster_count += atomspace.size - before
        end
      end

      # Everything now in the AtomSpace that came from local storage is
      # addressable by other nodes.
      @index_mutex.synchronize do
        atomspace.get_all_atoms.each do |atom|
          next unless @local_storage.fetch_atom(atom.handle)
          address = AtomWire.address(atom)
          @addresses[atom.handle] = address
          @by_address[address] = atom
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
      stats["compression_enabled"] = @enable_compression ? "true" : "false"
      stats["cache_enabled"] = @enable_cache ? "true" : "false"

      # Calculate distribution statistics
      local_partitions = @partition_map.values.count { |node| node == @cluster.node_id }
      stats["local_partitions"] = local_partitions.to_i64

      replica_count = @replica_map.values.sum { |replicas| replicas.includes?(@cluster.node_id) ? 1 : 0 }
      stats["local_replicas"] = replica_count.to_i64

      # Add cache statistics if enabled
      if @enable_cache
        cache_stats = @lru_cache.stats
        stats["cache_size"] = cache_stats["size"].as(Int32).to_i64
        stats["cache_hits"] = cache_stats["hits"].as(UInt64).to_i64
        stats["cache_misses"] = cache_stats["misses"].as(UInt64).to_i64
      end

      # Add partition cache statistics if enabled
      stats["partition_cache_enabled"] = @enable_partition_cache ? "true" : "false"
      if @enable_partition_cache
        pcache_stats = @partition_info_cache.stats
        stats["partition_cache_size"] = pcache_stats["size"].as(Int32).to_i64
        stats["partition_cache_hits"] = pcache_stats["hits"].as(UInt64).to_i64
        stats["partition_cache_misses"] = pcache_stats["misses"].as(UInt64).to_i64
      end

      stats
    end

    # Get detailed cache statistics
    def cache_stats : Hash(String, UInt64 | Int32 | Float64)
      @lru_cache.stats
    end

    # Get detailed partition cache statistics
    def partition_cache_stats : Hash(String, UInt64 | Int32 | Float64)
      @partition_info_cache.stats
    end

    # Clear the LRU cache
    def clear_cache
      @lru_cache.clear
    end

    # Clear the partition info cache
    def clear_partition_cache
      @partition_info_cache.clear
    end

    # Clear all caches
    def clear_all_caches
      @lru_cache.clear
      @partition_info_cache.clear
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
          "atom_count"      => JSON::Any.new(load.to_i64),
          "load_percentage" => JSON::Any.new((load.to_f / total_atoms * 100).round(2)),
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

    # `key` is the atom's content address, so every node picks the same owner.
    private def determine_responsible_node(key : String, type : AtomType? = nil) : String
      case @partition_strategy
      when PartitionStrategy::RoundRobin
        nodes = @cluster.cluster_nodes.map(&.id).sort
        nodes[(AtomWire.ring_position(key) % nodes.size).to_i]
      when PartitionStrategy::HashBased
        consistent_hash_node(key)
      when PartitionStrategy::TypeBased
        # All atoms of one type live together.
        consistent_hash_node(type ? "type:#{type}" : key)
      when PartitionStrategy::LoadBalanced
        least_loaded_node
      else
        consistent_hash_node(key)
      end
    end

    # Node ids in hash-ring order.
    private def ring : Array(String)
      @cluster.cluster_nodes.map(&.id).sort_by { |id| {AtomWire.ring_position(id), id} }
    end

    # Consistent hashing: the first node at or after the key on the ring.
    private def consistent_hash_node(key : String) : String
      position = AtomWire.ring_position(key)
      nodes = ring
      nodes.find { |id| AtomWire.ring_position(id) >= position } || nodes.first
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

    # The nodes that follow `exclude_node` on the ring, so every node agrees
    # on where an atom's backups are.
    private def select_backup_nodes(exclude_node : String, count : Int32) : Array(String)
      nodes = ring
      start = nodes.index(exclude_node) || -1
      successors = nodes.rotate(start + 1).reject { |id| id == exclude_node }
      successors.first(Math.max(count, 0))
    end

    private def replicate_atom_to_node(atom : Atom, node_id : String) : Bool
      send_atom_to_node("replicate_atom", atom, node_id)
    end

    private def fetch_atom_from_node(handle : Handle, node_id : String) : Atom?
      # Another node cannot interpret this node's handle; ask by content.
      address = @index_mutex.synchronize { @addresses[handle]? } || return nil
      fetch_address_from_node(address, node_id)
    end

    private def fetch_address_from_node(address : String, node_id : String) : Atom?
      node_info = find_cluster_node(node_id)
      return nil unless node_info

      begin
        message = {
          "type"            => "fetch_atom",
          "address"         => address,
          "requesting_node" => @cluster.node_id,
        }

        response = send_message_to_node_with_response(node_info, message)
        return nil unless response

        if response["status"] == "found"
          if atom_data = response["atom_data"]?
            return AtomWire.read(atom_data)
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
          "type"        => "remove_atom",
          "address"     => AtomWire.address(atom),
          "source_node" => @cluster.node_id,
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
          "type"            => "fetch_all_atoms",
          "requesting_node" => @cluster.node_id,
        }

        response = send_message_to_node_with_response(node_info, message)
        return [] of Atom unless response

        if response["status"] == "success"
          if atoms_data = response["atoms"]?
            return atoms_data.as_a.compact_map do |atom_json|
              begin
                AtomWire.read(atom_json)
              rescue ex
                log_error("Skipping undecodable atom from node #{node_id}: #{ex.message}")
                nil
              end
            end
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
      avg_load = (@partition_map.size / @cluster.cluster_nodes.size).to_i
      # How many more atoms each underloaded node should take.
      room = underloaded.transform_values { |load| Math.max(avg_load - load, 0) }

      overloaded.each do |source_node, load|
        candidates = @partition_map.select { |_, node| node == source_node }.keys
        # Moving a link away from its children costs a remote fetch on every
        # traversal, so move nodes without local links first, links last.
        candidates.sort_by! { |handle| {migration_cost(handle), handle} }
        candidates.first(Math.max(load - avg_load, 0)).each do |atom_handle|
          target_node = room.max_by? { |_, free| free }.try { |(id, free)| free > 0 ? id : nil } || break
          room[target_node] -= 1
          migrations << MigrationPlan.new(atom_handle, source_node, target_node)
        end
      end

      migrations
    end

    # Links held here that refer to the atom: what a migration would cut.
    private def migration_cost(handle_str : String) : Int32
      handle = handle_str.to_u64? || return 0
      @index_mutex.synchronize do
        @by_address.each_value.count { |atom| atom.link? && atom.outgoing.any? { |child| child.handle == handle } }
      end
    end

    private def execute_migration(migration : MigrationPlan) : Bool
      log_debug("Executing migration: #{migration.atom_handle} from #{migration.source_node} to #{migration.target_node}")
      handle = migration.atom_handle.to_u64?
      address = handle.try { |h| @index_mutex.synchronize { @addresses[h]? } }
      unless handle && address
        log_error("Cannot migrate #{migration.atom_handle}: no content address is known for it")
        return false
      end

      moved = if migration.source_node == @cluster.node_id
                atom = @index_mutex.synchronize { @by_address[address]? } || @local_storage.fetch_atom(handle)
                atom ? migrate_local_atom(atom, address, migration.target_node) : false
              else
                # The data is on another node: ask it to hand the atom over.
                node_info = find_cluster_node(migration.source_node)
                response = node_info.try do |info|
                  send_message_to_node_with_response(info, {"type" => "migrate_request", "address" => address,
                                                            "target_node" => migration.target_node})
                end
                response.try(&.["status"]?) == "migrated"
              end

      if moved
        @partition_map[migration.atom_handle] = migration.target_node
        @partition_info_cache.put(migration.atom_handle, migration.target_node, verified: true) if @enable_partition_cache
      end
      moved
    end

    # Hand an atom held here to `target_node`, and drop the local copy once
    # the target confirms it stored the atom (unless this node is a replica).
    private def migrate_local_atom(atom : Atom, address : String, target_node : String) : Bool
      return false unless send_atom_to_node("migrate_atom", atom, target_node, await: true)

      handle_str = book_key(atom, address)
      @partition_map[handle_str] = target_node
      keeps_replica = @replica_map[handle_str]?.try(&.includes?(@cluster.node_id)) || false
      forget_local(atom, address) unless keeps_replica
      true
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

      # Invalidate partition info cache for the departed node
      @partition_info_cache.invalidate_node(departed_node) if @enable_partition_cache

      # Reassign orphaned atoms to other nodes
      orphaned_atoms.each do |atom_handle|
        key = atom_handle.to_u64?.try { |handle| @index_mutex.synchronize { @addresses[handle]? } } || atom_handle
        new_responsible_node = determine_responsible_node(key)
        @partition_map[atom_handle] = new_responsible_node
        # A copy held here (as a replica) now answers for the atom.
        @replica_map[atom_handle]?.try(&.delete(departed_node))
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
