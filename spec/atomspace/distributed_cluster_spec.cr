require "spec"
require "../../src/atomspace/distributed_cluster"
require "../../src/atomspace/distributed_storage"

describe AtomSpace::DistributedAtomSpaceCluster do
  describe "initialization and basic operations" do
    it "creates a cluster node with proper configuration" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "test_cluster",
        local_atomspace: atomspace,
        host: "localhost",
        port: 0
      )

      cluster.cluster_id.should eq("test_cluster")
      cluster.node_id.should_not be_empty
      cluster.local_atomspace.should eq(atomspace)
      cluster.sync_strategy.should eq(AtomSpace::SyncStrategy::MergeUsingTruthValues)
    end

    it "provides cluster statistics" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "stats_test",
        local_atomspace: atomspace
      )

      cluster.start
      sleep 0.01  # Give cluster time to start

      stats = cluster.cluster_stats
      stats["cluster_id"].as_s.should eq("stats_test")
      stats["total_nodes"].as_i64.should eq(1)
      stats["active_nodes"].as_i64.should eq(1)
      stats["local_atomspace_size"].as_i64.should eq(0)
      stats["pending_sync_operations"].as_i64.should eq(0)

      cluster.stop
    end

    it "manages cluster nodes correctly" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "node_test",
        local_atomspace: atomspace
      )

      cluster.start
      sleep 0.01  # Give cluster time to start

      nodes = cluster.cluster_nodes
      nodes.size.should eq(1)
      nodes.first.id.should eq(cluster.node_id)
      nodes.first.status.should eq(AtomSpace::NodeStatus::Active)

      cluster.stop
    end
  end

  describe "atom synchronization" do
    it "queues local atom additions for cluster sync" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "sync_test",
        local_atomspace: atomspace
      )

      cluster.start

      # Add an atom through the cluster interface
      concept = AtomSpace::ConceptNode.new("test_concept")
      added_atom = cluster.add_atom(concept)

      # Should be added to local atomspace
      atomspace.size.should eq(1)
      atomspace.contains?(added_atom).should be_true

      # Should queue sync operation
      stats = cluster.cluster_stats
      stats["pending_sync_operations"].as_i64.should be > 0

      cluster.stop
    end

    it "handles different sync strategies" do
      atomspace = AtomSpace::AtomSpace.new
      
      # Test with LastWriteWins strategy
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "strategy_test",
        local_atomspace: atomspace,
        sync_strategy: AtomSpace::SyncStrategy::LastWriteWins
      )

      cluster.sync_strategy.should eq(AtomSpace::SyncStrategy::LastWriteWins)
    end

    it "removes atoms and queues removal operations" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "remove_test",
        local_atomspace: atomspace
      )

      cluster.start

      # Add an atom first
      concept = AtomSpace::ConceptNode.new("test_removal")
      added_atom = cluster.add_atom(concept)
      atomspace.size.should eq(1)

      # Remove the atom
      success = cluster.remove_atom(added_atom)
      success.should be_true
      atomspace.size.should eq(0)

      # Should queue sync operation for removal
      stats = cluster.cluster_stats
      stats["pending_sync_operations"].as_i64.should be > 0

      cluster.stop
    end
  end

  describe "cluster membership and networking" do
    it "starts and stops network services" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "network_test",
        local_atomspace: atomspace,
        port: 25555
      )

      # Should not be running initially
      cluster_stats = cluster.cluster_stats
      cluster_stats["local_node_status"].as_s.should eq("Initializing")

      cluster.start
      
      # Should be active after starting
      sleep 0.1  # Give time for async startup
      cluster_stats = cluster.cluster_stats
      cluster_stats["local_node_status"].as_s.should eq("Active")

      cluster.stop
      
      # Should be offline after stopping
      cluster_stats = cluster.cluster_stats
      cluster_stats["local_node_status"].as_s.should eq("Offline")
    end

    it "handles event observers" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "events_test",
        local_atomspace: atomspace
      )

      events = [] of AtomSpace::ClusterEvent
      node_ids = [] of String

      observer = ->(event : AtomSpace::ClusterEvent, node_id : String) {
        events << event
        node_ids << node_id
      }

      cluster.add_event_observer(observer)
      cluster.start

      # Should receive NODE_JOINED event
      sleep 0.1
      events.should contain(AtomSpace::ClusterEvent::NODE_JOINED)
      node_ids.should contain(cluster.node_id)

      cluster.stop

      # Should receive NODE_LEFT event
      sleep 0.1
      events.should contain(AtomSpace::ClusterEvent::NODE_LEFT)
    end
  end

  describe "vector clocks and conflict detection" do
    it "maintains vector clocks for operations" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "vector_test",
        local_atomspace: atomspace
      )

      cluster.start

      # Add atoms to increment vector clock
      concept1 = AtomSpace::ConceptNode.new("concept1")
      concept2 = AtomSpace::ConceptNode.new("concept2")
      
      cluster.add_atom(concept1)
      cluster.add_atom(concept2)

      # Vector clock should be incremented
      # This is tested indirectly through sync operations
      stats = cluster.cluster_stats
      stats["pending_sync_operations"].as_i64.should eq(2)

      cluster.stop
    end
  end

  describe "manual synchronization triggers" do
    it "allows manual sync triggering" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "manual_sync_test",
        local_atomspace: atomspace
      )

      cluster.start

      # Add some atoms
      cluster.add_atom(AtomSpace::ConceptNode.new("test1"))
      cluster.add_atom(AtomSpace::ConceptNode.new("test2"))

      # Trigger manual sync
      success = cluster.trigger_sync
      success.should be_true

      cluster.stop
    end

    it "supports full cluster synchronization" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "full_sync_test",
        local_atomspace: atomspace
      )

      cluster.start

      # Trigger full cluster sync
      success = cluster.full_cluster_sync
      success.should be_true

      cluster.stop
    end
  end
end

describe AtomSpace::DistributedStorageNode do
  describe "initialization and configuration" do
    it "creates distributed storage with proper configuration" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "storage_test",
        local_atomspace: atomspace
      )

      storage = AtomSpace::DistributedStorageNode.new(
        name: "test_storage",
        cluster: cluster,
        partition_strategy: AtomSpace::PartitionStrategy::HashBased,
        replication_strategy: AtomSpace::ReplicationStrategy::PrimaryBackup,
        replication_factor: 2
      )

      storage.partition_strategy.should eq(AtomSpace::PartitionStrategy::HashBased)
      storage.replication_strategy.should eq(AtomSpace::ReplicationStrategy::PrimaryBackup)
      storage.replication_factor.should eq(2)
    end

    it "opens and closes storage backends" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "backend_test",
        local_atomspace: atomspace
      )

      storage = AtomSpace::DistributedStorageNode.new(
        name: "backend_storage",
        cluster: cluster,
        storage_path: "/tmp/test_distributed_storage"
      )

      success = storage.open
      success.should be_true
      storage.connected?.should be_true

      success = storage.close
      success.should be_true
      storage.connected?.should be_false
    end
  end

  describe "storage operations" do
    it "stores and retrieves atoms locally" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "local_storage_test",
        local_atomspace: atomspace
      )

      cluster.start
      sleep 0.01  # Give cluster time to start

      storage = AtomSpace::DistributedStorageNode.new(
        name: "local_test_storage",
        cluster: cluster,
        storage_path: "/tmp/test_local_storage"
      )

      storage.open

      # Create and store an atom
      concept = AtomSpace::ConceptNode.new("test_concept")
      success = storage.store_atom(concept)
      success.should be_true

      # Retrieve the atom
      retrieved = storage.fetch_atom(concept.handle)
      retrieved.should_not be_nil
      if retrieved
        retrieved.handle.should eq(concept.handle)
        retrieved.type.should eq(concept.type)
      end

      storage.close
      cluster.stop
    end

    it "handles atom removal" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "removal_test",
        local_atomspace: atomspace
      )

      cluster.start
      sleep 0.01  # Give cluster time to start

      storage = AtomSpace::DistributedStorageNode.new(
        name: "removal_storage",
        cluster: cluster,
        storage_path: "/tmp/test_removal_storage"
      )

      storage.open

      # Store an atom
      concept = AtomSpace::ConceptNode.new("remove_me")
      storage.store_atom(concept)

      # Verify it exists
      retrieved = storage.fetch_atom(concept.handle)
      retrieved.should_not be_nil

      # Remove the atom
      success = storage.remove_atom(concept)
      success.should be_true

      # Verify it's gone
      retrieved = storage.fetch_atom(concept.handle)
      retrieved.should be_nil

      storage.close
      cluster.stop
    end

    it "stores and loads complete atomspaces" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "atomspace_test",
        local_atomspace: atomspace
      )

      storage = AtomSpace::DistributedStorageNode.new(
        name: "atomspace_storage",
        cluster: cluster,
        storage_path: "/tmp/test_atomspace_storage"
      )

      storage.open

      # Create test atomspace with atoms
      test_atomspace = AtomSpace::AtomSpace.new
      concept1 = test_atomspace.add_concept_node("concept1")
      concept2 = test_atomspace.add_concept_node("concept2")
      inheritance = test_atomspace.add_inheritance_link(concept1, concept2)

      # Store the atomspace
      success = storage.store_atomspace(test_atomspace)
      success.should be_true

      # Load into a new atomspace
      loaded_atomspace = AtomSpace::AtomSpace.new
      success = storage.load_atomspace(loaded_atomspace)
      success.should be_true

      # Verify atoms were loaded
      loaded_atomspace.size.should be > 0

      storage.close
    end
  end

  describe "data partitioning and replication" do
    it "provides distribution metrics" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "metrics_test",
        local_atomspace: atomspace
      )

      storage = AtomSpace::DistributedStorageNode.new(
        name: "metrics_storage",
        cluster: cluster
      )

      storage.open

      # Add some atoms to generate distribution data
      concept1 = AtomSpace::ConceptNode.new("dist_concept1")
      concept2 = AtomSpace::ConceptNode.new("dist_concept2")
      storage.store_atom(concept1)
      storage.store_atom(concept2)

      metrics = storage.distribution_metrics
      metrics["total_atoms"].as_i64.should eq(2)
      metrics["balance_score"].as_f.should be > 0.0

      storage.close
    end

    it "provides comprehensive storage statistics" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "stats_test",
        local_atomspace: atomspace
      )

      storage = AtomSpace::DistributedStorageNode.new(
        name: "stats_storage",
        cluster: cluster,
        partition_strategy: AtomSpace::PartitionStrategy::RoundRobin,
        replication_strategy: AtomSpace::ReplicationStrategy::FullReplication
      )

      storage.open

      stats = storage.get_stats
      stats["type"].should eq("DistributedStorage")
      stats["cluster_id"].should eq("stats_test")
      stats["partition_strategy"].should eq("RoundRobin")
      stats["replication_strategy"].should eq("FullReplication")
      stats["cluster_nodes"].should eq(1_i64)

      storage.close
    end
  end

  describe "different partitioning strategies" do
    it "supports round-robin partitioning" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "round_robin_test",
        local_atomspace: atomspace
      )

      storage = AtomSpace::DistributedStorageNode.new(
        name: "rr_storage",
        cluster: cluster,
        partition_strategy: AtomSpace::PartitionStrategy::RoundRobin
      )

      storage.partition_strategy.should eq(AtomSpace::PartitionStrategy::RoundRobin)
    end

    it "supports hash-based partitioning" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "hash_test",
        local_atomspace: atomspace
      )

      storage = AtomSpace::DistributedStorageNode.new(
        name: "hash_storage",
        cluster: cluster,
        partition_strategy: AtomSpace::PartitionStrategy::HashBased
      )

      storage.partition_strategy.should eq(AtomSpace::PartitionStrategy::HashBased)
    end

    it "supports load-balanced partitioning" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "load_test",
        local_atomspace: atomspace
      )

      storage = AtomSpace::DistributedStorageNode.new(
        name: "load_storage",
        cluster: cluster,
        partition_strategy: AtomSpace::PartitionStrategy::LoadBalanced
      )

      storage.partition_strategy.should eq(AtomSpace::PartitionStrategy::LoadBalanced)
    end
  end

  describe "replication strategies" do
    it "supports single copy replication" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "single_copy_test",
        local_atomspace: atomspace
      )

      storage = AtomSpace::DistributedStorageNode.new(
        name: "single_storage",
        cluster: cluster,
        replication_strategy: AtomSpace::ReplicationStrategy::SingleCopy
      )

      storage.replication_strategy.should eq(AtomSpace::ReplicationStrategy::SingleCopy)
    end

    it "supports primary-backup replication" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "backup_test",
        local_atomspace: atomspace
      )

      storage = AtomSpace::DistributedStorageNode.new(
        name: "backup_storage",
        cluster: cluster,
        replication_strategy: AtomSpace::ReplicationStrategy::PrimaryBackup,
        replication_factor: 3
      )

      storage.replication_strategy.should eq(AtomSpace::ReplicationStrategy::PrimaryBackup)
      storage.replication_factor.should eq(3)
    end

    it "supports full replication" do
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "full_replication_test",
        local_atomspace: atomspace
      )

      storage = AtomSpace::DistributedStorageNode.new(
        name: "full_storage",
        cluster: cluster,
        replication_strategy: AtomSpace::ReplicationStrategy::FullReplication
      )

      storage.replication_strategy.should eq(AtomSpace::ReplicationStrategy::FullReplication)
    end
  end
end

describe AtomSpace::ConflictResolver do
  describe "conflict resolution strategies" do
    it "resolves conflicts using last-write-wins strategy" do
      resolver = AtomSpace::ConflictResolver.new(AtomSpace::SyncStrategy::LastWriteWins)
      
      concept = AtomSpace::ConceptNode.new("test_conflict")
      sync_op = AtomSpace::SyncOperation.new("update", concept.handle.to_s, "node1")
      conflict = AtomSpace::ConflictInfo.new(sync_op, "concurrent_modification")
      
      resolved = resolver.resolve(conflict, concept)
      resolved.should eq(concept)  # Last write wins
    end

    it "supports truth value merging strategy" do
      resolver = AtomSpace::ConflictResolver.new(AtomSpace::SyncStrategy::MergeUsingTruthValues)
      
      concept = AtomSpace::ConceptNode.new("merge_test")
      sync_op = AtomSpace::SyncOperation.new("update", concept.handle.to_s, "node1")
      conflict = AtomSpace::ConflictInfo.new(sync_op, "truth_value_conflict")
      
      resolved = resolver.resolve(conflict, concept)
      resolved.should_not be_nil
    end

    it "supports vector clock strategy" do
      resolver = AtomSpace::ConflictResolver.new(AtomSpace::SyncStrategy::VectorClock)
      
      concept = AtomSpace::ConceptNode.new("vector_test")
      sync_op = AtomSpace::SyncOperation.new("update", concept.handle.to_s, "node1")
      conflict = AtomSpace::ConflictInfo.new(sync_op, "vector_clock_conflict")
      
      resolved = resolver.resolve(conflict, concept)
      resolved.should_not be_nil
    end
  end
end

describe AtomSpace::ClusterNodeInfo do
  it "tracks node status and heartbeat" do
    node = AtomSpace::ClusterNodeInfo.new("test_node", "localhost", 25000)
    
    node.id.should eq("test_node")
    node.host.should eq("localhost")
    node.port.should eq(25000)
    node.status.should eq(AtomSpace::NodeStatus::Initializing)
    
    initial_time = node.last_heartbeat
    sleep 0.001
    node.update_heartbeat
    node.last_heartbeat.should be > initial_time
  end

  it "detects stale nodes" do
    node = AtomSpace::ClusterNodeInfo.new("stale_test", "localhost", 25001)
    
    # Fresh node should not be stale
    node.is_stale?(60).should be_false
    
    # Manually set old heartbeat
    old_time = Time.utc - Time::Span.new(seconds: 120)
    node.last_heartbeat = old_time
    
    node.is_stale?(60).should be_true
  end
end

describe AtomSpace::SyncOperation do
  it "creates sync operations with proper metadata" do
    sync_op = AtomSpace::SyncOperation.new("add", "test_handle", "source_node", "target_node")
    
    sync_op.operation_type.should eq("add")
    sync_op.atom_handle.should eq("test_handle")
    sync_op.source_node.should eq("source_node")
    sync_op.target_node.should eq("target_node")
    sync_op.id.should_not be_empty
    sync_op.timestamp.should be_close(Time.utc, 1.second)
  end
end