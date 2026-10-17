#!/usr/bin/env crystal

# Integration test for distributed AtomSpace clustering
# Tests basic cluster operations without requiring Crystal to be fully installed

require "../../src/atomspace/atomspace_module"

def test_basic_cluster_functionality
  puts "Testing basic distributed cluster functionality..."
  
  begin
    # Test 1: Create cluster
    atomspace = AtomSpace::AtomSpace.new
    cluster = AtomSpace::DistributedAtomSpaceCluster.new(
      cluster_id: "test_cluster",
      local_atomspace: atomspace,
      host: "localhost",
      port: 0  # Auto-assign port
    )
    
    puts "✓ Cluster created successfully"
    
    # Test 2: Check initial state
    stats = cluster.cluster_stats
    if stats["cluster_id"].as_s == "test_cluster" && stats["total_nodes"].as_i64 == 1
      puts "✓ Initial cluster state correct"
    else
      puts "✗ Initial cluster state incorrect"
      return false
    end
    
    # Test 3: Start cluster
    cluster.start
    puts "✓ Cluster started successfully"
    
    # Test 4: Add atoms
    concept = cluster.add_atom(AtomSpace::ConceptNode.new("test_concept"))
    if atomspace.size == 1 && atomspace.contains?(concept)
      puts "✓ Atom addition works correctly"
    else
      puts "✗ Atom addition failed"
      return false
    end
    
    # Test 5: Check sync operations queued
    stats = cluster.cluster_stats
    if stats["pending_sync_operations"].as_i64 > 0
      puts "✓ Sync operations queued correctly"
    else
      puts "✗ No sync operations queued"
      return false
    end
    
    # Test 6: Manual sync trigger
    if cluster.trigger_sync
      puts "✓ Manual sync trigger works"
    else
      puts "✗ Manual sync trigger failed"
      return false
    end
    
    # Test 7: Remove atom
    success = cluster.remove_atom(concept)
    if success && atomspace.size == 0
      puts "✓ Atom removal works correctly"
    else
      puts "✗ Atom removal failed"
      return false
    end
    
    # Test 8: Stop cluster
    cluster.stop
    puts "✓ Cluster stopped successfully"
    
    return true
    
  rescue ex
    puts "✗ Test failed with exception: #{ex.message}"
    return false
  end
end

def test_distributed_storage_functionality
  puts "\nTesting distributed storage functionality..."
  
  begin
    # Test 1: Create cluster and storage
    atomspace = AtomSpace::AtomSpace.new
    cluster = AtomSpace::DistributedAtomSpaceCluster.new("storage_test", atomspace)
    cluster.start
    
    storage = AtomSpace::DistributedStorageNode.new(
      name: "test_storage",
      cluster: cluster,
      local_storage_backend: "file",
      storage_path: "/tmp/test_distributed_storage",
      partition_strategy: AtomSpace::PartitionStrategy::HashBased,
      replication_strategy: AtomSpace::ReplicationStrategy::SingleCopy
    )
    
    puts "✓ Distributed storage created successfully"
    
    # Test 2: Open storage
    if storage.open
      puts "✓ Storage opened successfully"
    else
      puts "✗ Storage failed to open"
      return false
    end
    
    # Test 3: Store atoms
    concept = AtomSpace::ConceptNode.new("storage_test_concept")
    if storage.store_atom(concept)
      puts "✓ Atom stored successfully"
    else
      puts "✗ Atom storage failed"
      return false
    end
    
    # Test 4: Fetch atoms
    retrieved = storage.fetch_atom(concept.handle)
    if retrieved && retrieved.handle == concept.handle
      puts "✓ Atom fetched successfully"
    else
      puts "✗ Atom fetch failed"
      return false
    end
    
    # Test 5: Storage statistics
    stats = storage.get_stats
    if stats["type"] == "DistributedStorage"
      puts "✓ Storage statistics work correctly"
    else
      puts "✗ Storage statistics incorrect"
      return false
    end
    
    # Test 6: Distribution metrics
    metrics = storage.distribution_metrics
    if metrics["total_atoms"].as_i64 >= 1
      puts "✓ Distribution metrics work correctly"
    else
      puts "✗ Distribution metrics incorrect"
      return false
    end
    
    # Test 7: Close storage
    storage.close
    cluster.stop
    puts "✓ Storage and cluster closed successfully"
    
    return true
    
  rescue ex
    puts "✗ Storage test failed with exception: #{ex.message}"
    return false
  end
end

def test_conflict_resolution
  puts "\nTesting conflict resolution..."
  
  begin
    # Test different conflict resolution strategies
    strategies = [
      AtomSpace::SyncStrategy::LastWriteWins,
      AtomSpace::SyncStrategy::MergeUsingTruthValues,
      AtomSpace::SyncStrategy::VectorClock
    ]
    
    strategies.each do |strategy|
      atomspace = AtomSpace::AtomSpace.new
      cluster = AtomSpace::DistributedAtomSpaceCluster.new(
        cluster_id: "conflict_test",
        local_atomspace: atomspace,
        sync_strategy: strategy
      )
      
      cluster.start
      
      # Create conflicting atoms with different truth values
      tv1 = AtomSpace::SimpleTruthValue.new(0.8, 0.6)
      tv2 = AtomSpace::SimpleTruthValue.new(0.9, 0.7)
      
      concept1 = AtomSpace::ConceptNode.new("conflict_concept", tv1)
      concept2 = AtomSpace::ConceptNode.new("conflict_concept", tv2)
      
      cluster.add_atom(concept1)
      cluster.add_atom(concept2)
      
      # Check that conflict was resolved
      final_concepts = atomspace.get_nodes_by_name("conflict_concept", AtomSpace::AtomType::CONCEPT_NODE)
      if final_concepts.size == 1
        puts "✓ Conflict resolution with #{strategy} works"
      else
        puts "✗ Conflict resolution with #{strategy} failed"
        return false
      end
      
      cluster.stop
    end
    
    return true
    
  rescue ex
    puts "✗ Conflict resolution test failed: #{ex.message}"
    return false
  end
end

def main
  puts "Distributed AtomSpace Clustering Integration Test"
  puts "=" * 50
  
  success = true
  
  success = test_basic_cluster_functionality && success
  success = test_distributed_storage_functionality && success
  success = test_conflict_resolution && success
  
  puts "\n" + "=" * 50
  if success
    puts "✓ All tests passed! Distributed AtomSpace clustering is working correctly."
    exit 0
  else
    puts "✗ Some tests failed. Please check the implementation."
    exit 1
  end
end

main