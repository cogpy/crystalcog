require "spec"
require "file_utils"
require "random/secure"
require "../../src/atomspace/distributed_storage"

private def make_dist_cluster(name : String)
  atomspace = AtomSpace::AtomSpace.new
  cluster = AtomSpace::DistributedAtomSpaceCluster.new(
    cluster_id: "#{name}_cluster",
    local_atomspace: atomspace
  )
  {atomspace, cluster}
end

private def cleanup_dist_storage(storage : AtomSpace::DistributedStorageNode, cluster : AtomSpace::DistributedAtomSpaceCluster, storage_path : String)
  storage.close if storage.connected?
  cluster.stop
  FileUtils.rm_rf(storage_path) if Dir.exists?(storage_path)
end

describe AtomSpace::PartitionStrategy do
  it "defines expected partitioning strategies" do
    AtomSpace::PartitionStrategy::RoundRobin.to_s.should eq("RoundRobin")
    AtomSpace::PartitionStrategy::HashBased.to_s.should eq("HashBased")
    AtomSpace::PartitionStrategy::TypeBased.to_s.should eq("TypeBased")
    AtomSpace::PartitionStrategy::LoadBalanced.to_s.should eq("LoadBalanced")
  end
end

describe AtomSpace::ReplicationStrategy do
  it "defines expected replication strategies" do
    AtomSpace::ReplicationStrategy::SingleCopy.to_s.should eq("SingleCopy")
    AtomSpace::ReplicationStrategy::PrimaryBackup.to_s.should eq("PrimaryBackup")
    AtomSpace::ReplicationStrategy::FullReplication.to_s.should eq("FullReplication")
    AtomSpace::ReplicationStrategy::QuorumBased.to_s.should eq("QuorumBased")
  end
end

describe AtomSpace::LRUCacheEntry do
  it "tracks access time and count on touch" do
    atom = AtomSpace::ConceptNode.new("lru_entry_atom")
    entry = AtomSpace::LRUCacheEntry.new(atom)

    entry.atom.should eq(atom)
    entry.access_count.should eq(1_u64)
    initial_access = entry.last_access

    sleep 0.002.seconds
    entry.touch

    entry.access_count.should eq(2_u64)
    entry.last_access.should be > initial_access
  end
end

describe AtomSpace::LRUCache do
  it "stores and retrieves atoms with hit/miss stats" do
    cache = AtomSpace::LRUCache.new(10)
    atom = AtomSpace::ConceptNode.new("cached_atom")

    cache.get(atom.handle).should be_nil
    cache.put(atom)

    retrieved = cache.get(atom.handle)
    retrieved.should_not be_nil
    if retrieved
      retrieved.handle.should eq(atom.handle)
    end

    stats = cache.stats
    stats["size"].should eq(1)
    stats["hits"].should eq(1_u64)
    stats["misses"].should eq(1_u64)
    stats["hit_rate_percent"].as(Float64).should be > 0.0
  end

  it "invalidates and clears cached atoms" do
    cache = AtomSpace::LRUCache.new(10)
    atom = AtomSpace::ConceptNode.new("invalidate_me")

    cache.put(atom)
    cache.size.should eq(1)

    cache.invalidate(atom.handle)
    cache.get(atom.handle).should be_nil
    cache.size.should eq(0)

    cache.put(atom)
    cache.clear
    cache.size.should eq(0)
  end

  it "evicts least recently used entries when full" do
    cache = AtomSpace::LRUCache.new(2)
    a1 = AtomSpace::ConceptNode.new("evict_1")
    a2 = AtomSpace::ConceptNode.new("evict_2")
    a3 = AtomSpace::ConceptNode.new("evict_3")

    cache.put(a1)
    sleep 0.002.seconds
    cache.put(a2)
    sleep 0.002.seconds

    # Touch a1 so a2 is older if needed, then insert a3 to force eviction
    cache.get(a1.handle)
    sleep 0.002.seconds
    cache.put(a3)

    cache.size.should eq(2)
    cache.get(a3.handle).should_not be_nil
    # One of the earlier entries should have been evicted
    remaining = [a1, a2].count { |a| !cache.get(a.handle).nil? }
    remaining.should eq(1)
  end
end

describe AtomSpace::NetworkCompression do
  it "round-trips compression and decompression" do
    original = "hello distributed storage " * 20
    compressed = AtomSpace::NetworkCompression.compress(original)
    compressed.should_not be_empty

    restored = AtomSpace::NetworkCompression.decompress(compressed)
    restored.should eq(original)
  end

  it "decides compression based on threshold" do
    small = "tiny"
    large = "x" * 600

    AtomSpace::NetworkCompression.should_compress?(small).should be_false
    AtomSpace::NetworkCompression.should_compress?(large).should be_true
    AtomSpace::NetworkCompression.should_compress?(small, 1).should be_true
  end
end

describe AtomSpace::PartitionInfoCache do
  it "caches partition ownership and tracks stats" do
    cache = AtomSpace::PartitionInfoCache.new(100, 5.minutes)

    cache.get("handle-1").should be_nil
    cache.put("handle-1", "node-a", ["node-b"], verified: true)

    info = cache.get("handle-1")
    info.should_not be_nil
    if info
      info.node_id.should eq("node-a")
      info.replicas.should eq(["node-b"])
      info.verified.should be_true
      info.expired?(5.minutes).should be_false
    end

    stats = cache.stats
    stats["size"].should eq(1)
    stats["hits"].should eq(1_u64)
    stats["misses"].should eq(1_u64)
  end

  it "invalidates entries by handle and node" do
    cache = AtomSpace::PartitionInfoCache.new(100, 5.minutes)
    cache.put("h1", "node-a", ["node-b"])
    cache.put("h2", "node-b", ["node-a"])
    cache.put("h3", "node-c", [] of String)

    cache.invalidate("h1")
    cache.get("h1").should be_nil

    cache.invalidate_node("node-b")
    cache.get("h2").should be_nil

    cache.size.should eq(1)
    cache.clear
    cache.size.should eq(0)
  end

  it "treats expired entries as misses" do
    cache = AtomSpace::PartitionInfoCache.new(100, 1.milliseconds)
    cache.put("expired-handle", "node-a")
    sleep 0.005.seconds

    cache.get("expired-handle").should be_nil
    stats = cache.stats
    stats["misses"].as(UInt64).should be >= 1_u64
  end
end

describe AtomSpace::DistributedStorageNode do
  describe "initialization and lifecycle" do
    it "creates storage with configuration defaults and overrides" do
      path = "/tmp/crystalcog_dist_storage_init_#{Random::Secure.hex(4)}"
      _, cluster = make_dist_cluster("init_storage")
      storage = AtomSpace::DistributedStorageNode.new(
        name: "init_storage",
        cluster: cluster,
        storage_path: path,
        partition_strategy: AtomSpace::PartitionStrategy::TypeBased,
        replication_strategy: AtomSpace::ReplicationStrategy::QuorumBased,
        replication_factor: 3,
        enable_compression: false,
        enable_cache: false,
        enable_partition_cache: false
      )
      begin
        storage.partition_strategy.should eq(AtomSpace::PartitionStrategy::TypeBased)
        storage.replication_strategy.should eq(AtomSpace::ReplicationStrategy::QuorumBased)
        storage.replication_factor.should eq(3)
        storage.enable_compression.should be_false
        storage.enable_cache.should be_false
        storage.enable_partition_cache.should be_false
        storage.cluster.should eq(cluster)
      ensure
        cleanup_dist_storage(storage, cluster, path)
      end
    end

    it "opens and closes the local backend" do
      path = "/tmp/crystalcog_dist_storage_open_#{Random::Secure.hex(4)}"
      _, cluster = make_dist_cluster("open_storage")
      storage = AtomSpace::DistributedStorageNode.new(
        name: "open_storage",
        cluster: cluster,
        storage_path: path
      )
      begin
        storage.connected?.should be_false
        storage.open.should be_true
        storage.connected?.should be_true
        storage.close.should be_true
        storage.connected?.should be_false
      ensure
        cleanup_dist_storage(storage, cluster, path)
      end
    end
  end

  describe "atom CRUD and atomspace persistence" do
    it "stores, fetches, and removes atoms in a single-node cluster" do
      path = "/tmp/crystalcog_dist_storage_crud_#{Random::Secure.hex(4)}"
      _, cluster = make_dist_cluster("crud_storage")
      storage = AtomSpace::DistributedStorageNode.new(
        name: "crud_storage",
        cluster: cluster,
        storage_path: path
      )
      begin
        cluster.start
        sleep 0.01.seconds
        storage.open

        atom = AtomSpace::ConceptNode.new("dist_crud_atom")
        storage.store_atom(atom).should be_true

        fetched = storage.fetch_atom(atom.handle)
        fetched.should_not be_nil
        if fetched
          fetched.handle.should eq(atom.handle)
          fetched.type.should eq(atom.type)
        end

        storage.remove_atom(atom).should be_true
        storage.fetch_atom(atom.handle).should be_nil
      ensure
        cleanup_dist_storage(storage, cluster, path)
      end
    end

    it "stores and loads a complete atomspace" do
      path = "/tmp/crystalcog_dist_storage_as_#{Random::Secure.hex(4)}"
      _, cluster = make_dist_cluster("atomspace_storage")
      storage = AtomSpace::DistributedStorageNode.new(
        name: "atomspace_storage",
        cluster: cluster,
        storage_path: path
      )
      begin
        storage.open

        source = AtomSpace::AtomSpace.new
        c1 = source.add_concept_node("as_c1")
        c2 = source.add_concept_node("as_c2")
        source.add_inheritance_link(c1, c2)

        storage.store_atomspace(source).should be_true

        loaded = AtomSpace::AtomSpace.new
        storage.load_atomspace(loaded).should be_true
        loaded.size.should be > 0
      ensure
        cleanup_dist_storage(storage, cluster, path)
      end
    end
  end

  describe "caching" do
    it "serves repeated fetches from the LRU cache" do
      path = "/tmp/crystalcog_dist_storage_cache_#{Random::Secure.hex(4)}"
      _, cluster = make_dist_cluster("cache_storage")
      storage = AtomSpace::DistributedStorageNode.new(
        name: "cache_storage",
        cluster: cluster,
        storage_path: path,
        enable_cache: true,
        cache_size: 100
      )
      begin
        cluster.start
        sleep 0.01.seconds
        storage.open

        atom = AtomSpace::ConceptNode.new("cache_hit_atom")
        storage.store_atom(atom).should be_true

        # First fetch may hit cache already populated by store
        storage.fetch_atom(atom.handle).should_not be_nil
        before = storage.cache_stats
        hits_before = before["hits"].as(UInt64)

        storage.fetch_atom(atom.handle).should_not be_nil
        after = storage.cache_stats
        after["hits"].as(UInt64).should be > hits_before

        storage.clear_cache
        storage.cache_stats["size"].should eq(0)
      ensure
        cleanup_dist_storage(storage, cluster, path)
      end
    end

    it "exposes and clears partition cache stats" do
      path = "/tmp/crystalcog_dist_storage_pcache_#{Random::Secure.hex(4)}"
      _, cluster = make_dist_cluster("pcache_storage")
      storage = AtomSpace::DistributedStorageNode.new(
        name: "pcache_storage",
        cluster: cluster,
        storage_path: path,
        enable_partition_cache: true
      )
      begin
        storage.open

        stats = storage.partition_cache_stats
        stats["size"].should eq(0)
        stats.has_key?("hits").should be_true

        storage.clear_partition_cache
        storage.clear_all_caches
        storage.partition_cache_stats["size"].should eq(0)
        storage.cache_stats["size"].should eq(0)
      ensure
        cleanup_dist_storage(storage, cluster, path)
      end
    end
  end

  describe "metrics and rebalancing" do
    it "reports distribution metrics and storage stats" do
      path = "/tmp/crystalcog_dist_storage_metrics_#{Random::Secure.hex(4)}"
      _, cluster = make_dist_cluster("metrics_storage")
      storage = AtomSpace::DistributedStorageNode.new(
        name: "metrics_storage",
        cluster: cluster,
        storage_path: path,
        partition_strategy: AtomSpace::PartitionStrategy::RoundRobin,
        replication_strategy: AtomSpace::ReplicationStrategy::FullReplication
      )
      begin
        storage.open
        storage.store_atom(AtomSpace::ConceptNode.new("m1"))
        storage.store_atom(AtomSpace::ConceptNode.new("m2"))

        metrics = storage.distribution_metrics
        metrics["total_atoms"].as_i64.should eq(2)
        metrics["balance_score"].as_f.should be > 0.0

        stats = storage.get_stats
        stats["type"].should eq("DistributedStorage")
        stats["cluster_id"].should eq(cluster.cluster_id)
        stats["partition_strategy"].should eq("RoundRobin")
        stats["replication_strategy"].should eq("FullReplication")
        stats["cluster_nodes"].should eq(1_i64)
        stats["compression_enabled"].should eq("true")
        stats["cache_enabled"].should eq("true")
        stats["partition_cache_enabled"].should eq("true")
      ensure
        cleanup_dist_storage(storage, cluster, path)
      end
    end

    it "runs rebalance on a single-node cluster" do
      path = "/tmp/crystalcog_dist_storage_rebalance_#{Random::Secure.hex(4)}"
      _, cluster = make_dist_cluster("rebalance_storage")
      storage = AtomSpace::DistributedStorageNode.new(
        name: "rebalance_storage",
        cluster: cluster,
        storage_path: path
      )
      begin
        cluster.start
        sleep 0.01.seconds
        storage.open

        storage.store_atom(AtomSpace::ConceptNode.new("rb1"))
        storage.store_atom(AtomSpace::ConceptNode.new("rb2"))

        storage.rebalance_cluster.should be_true
      ensure
        cleanup_dist_storage(storage, cluster, path)
      end
    end
  end

  describe "partition and replication configuration" do
    it "supports hash-based and load-balanced partitioning" do
      path = "/tmp/crystalcog_dist_storage_part_#{Random::Secure.hex(4)}"
      _, cluster = make_dist_cluster("hash_storage")
      storage = AtomSpace::DistributedStorageNode.new(
        name: "hash_storage",
        cluster: cluster,
        storage_path: path,
        partition_strategy: AtomSpace::PartitionStrategy::HashBased
      )
      begin
        storage.partition_strategy.should eq(AtomSpace::PartitionStrategy::HashBased)
      ensure
        cleanup_dist_storage(storage, cluster, path)
      end

      path2 = "/tmp/crystalcog_dist_storage_load_#{Random::Secure.hex(4)}"
      _, cluster2 = make_dist_cluster("load_storage")
      storage2 = AtomSpace::DistributedStorageNode.new(
        name: "load_storage",
        cluster: cluster2,
        storage_path: path2,
        partition_strategy: AtomSpace::PartitionStrategy::LoadBalanced
      )
      begin
        storage2.partition_strategy.should eq(AtomSpace::PartitionStrategy::LoadBalanced)
      ensure
        cleanup_dist_storage(storage2, cluster2, path2)
      end
    end

    it "supports single-copy and primary-backup replication" do
      path = "/tmp/crystalcog_dist_storage_repl_#{Random::Secure.hex(4)}"
      _, cluster = make_dist_cluster("single_storage")
      storage = AtomSpace::DistributedStorageNode.new(
        name: "single_storage",
        cluster: cluster,
        storage_path: path,
        replication_strategy: AtomSpace::ReplicationStrategy::SingleCopy
      )
      begin
        storage.replication_strategy.should eq(AtomSpace::ReplicationStrategy::SingleCopy)
      ensure
        cleanup_dist_storage(storage, cluster, path)
      end

      path2 = "/tmp/crystalcog_dist_storage_backup_#{Random::Secure.hex(4)}"
      _, cluster2 = make_dist_cluster("backup_storage")
      storage2 = AtomSpace::DistributedStorageNode.new(
        name: "backup_storage",
        cluster: cluster2,
        storage_path: path2,
        replication_strategy: AtomSpace::ReplicationStrategy::PrimaryBackup,
        replication_factor: 3
      )
      begin
        storage2.replication_strategy.should eq(AtomSpace::ReplicationStrategy::PrimaryBackup)
        storage2.replication_factor.should eq(3)
      ensure
        cleanup_dist_storage(storage2, cluster2, path2)
      end
    end
  end
end
