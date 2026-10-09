# Multi-node AtomSpace cache simulation for Nightly E2E.
#
# Crystal resolves `require` relative to this source file, not the process
# working directory. Keep this script in the repository. A copy under /tmp
# cannot see `src/` and fails the distributed E2E job.
require "../../src/atomspace/distributed_storage"

module NightlyE2E
  # Spread atoms across per-node LRU caches. Handles are assigned by Atom
  # construction and are not settable.
  def self.multi_node_simulation(atom_count : Int32 = 1000, cache_size : Int32 = 100, node_count : Int32 = 3) : Bool
    puts "Multi-Node Simulation Test"
    puts "=========================="

    nodes = (1..node_count).map do |i|
      {
        id:        "node_#{i}",
        cache:     AtomSpace::LRUCache.new(cache_size),
        partition: i,
      }
    end

    puts "✓ Simulated #{node_count} nodes"

    puts "\nTest: Distributed atom storage..."
    atom_count.times do |i|
      node = nodes[i % node_count]
      atom = AtomSpace::ConceptNode.new("distributed_atom_#{i}")
      node[:cache].put(atom)
    end

    puts "✓ Distributed #{atom_count} atoms across #{node_count} nodes"

    failed = false
    nodes.each_with_index do |node, idx|
      size = node[:cache].stats["size"].as(Int32)
      puts "  Node #{idx + 1}: #{size} atoms cached"
      if size <= 0
        puts "✗ Node #{idx + 1} cache is empty"
        failed = true
      end
    end

    if failed
      puts "\n✗ Multi-node simulation failed"
      false
    else
      puts "\n✓ Multi-node simulation completed!"
      true
    end
  end
end

# crystal run names the temp binary crystal-run-<source>.tmp
if PROGRAM_NAME.includes?("multi_node_simulation")
  exit 1 unless NightlyE2E.multi_node_simulation
end
