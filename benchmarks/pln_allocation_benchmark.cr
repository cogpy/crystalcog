require "../src/cogutil/cogutil"
require "../src/atomspace/atomspace_main"
require "../src/pln/pln"

# Bounded, deterministic workload for comparing PLN allocation behavior.
# The 12-node chain is deliberately small: it exercises deduction, inversion,
# abduction, and modus ponens without attempting a dense whole-graph closure.
NODE_COUNT = 12
ITERATIONS =  2

record GcSnapshot,
  heap_bytes : UInt64,
  free_bytes : UInt64,
  bytes_since_gc : UInt64,
  total_allocated_bytes : UInt64

def gc_snapshot : GcSnapshot
  heap = 0_u64
  free = 0_u64
  unmapped = 0_u64
  since_gc = 0_u64
  total = 0_u64
  LibGC.get_heap_usage_safe(
    pointerof(heap),
    pointerof(free),
    pointerof(unmapped),
    pointerof(since_gc),
    pointerof(total)
  )
  GcSnapshot.new(heap, free, since_gc, total)
end

# AtomSpace does not expose the global next-handle counter. A pair of disposable
# Nodes brackets the workload, so the gap measures all Atom instances created by
# inference (canonical and rejected duplicate candidates) without modifying core.
def handle_checkpoint : UInt64
  AtomSpace::Node.new(AtomSpace::AtomType::CONCEPT_NODE, "pln-allocation-probe").handle
end

def build_chain(node_count : Int32) : AtomSpace::AtomSpace
  atomspace = AtomSpace::AtomSpace.new
  nodes = Array(AtomSpace::Atom).new(node_count)

  node_count.times do |index|
    strength = 0.70 + (index % 3) * 0.05
    confidence = 0.80 + (index % 2) * 0.05
    nodes << atomspace.add_concept_node(
      "pln-allocation-node-#{index}",
      AtomSpace::SimpleTruthValue.new(strength, confidence)
    )
  end

  (node_count - 1).times do |index|
    strength = 0.65 + (index % 4) * 0.05
    confidence = 0.75 + (index % 3) * 0.05
    atomspace.add_inheritance_link(
      nodes[index],
      nodes[index + 1],
      AtomSpace::SimpleTruthValue.new(strength, confidence)
    )
  end

  atomspace
end

CogUtil.initialize
AtomSpace.initialize

atomspace = build_chain(NODE_COUNT)
engine = PLN::PLNEngine.new(atomspace)
initial_atoms = atomspace.size
initial_links = atomspace.link_count

# Keep process-level GC counters comparable between invocations.
GC.collect
before_gc = gc_snapshot
before_handle = handle_checkpoint
started_at = Time.monotonic
results = engine.reason(ITERATIONS)
elapsed = Time.monotonic - started_at
after_handle = handle_checkpoint
after_gc = gc_snapshot
GC.collect
settled_gc = gc_snapshot

constructed_atoms = after_handle - before_handle - 1_u64
canonical_atom_delta = atomspace.size - initial_atoms
canonical_link_delta = atomspace.link_count - initial_links
allocated_bytes = after_gc.total_allocated_bytes - before_gc.total_allocated_bytes

puts "PLN deterministic allocation benchmark"
puts "nodes=#{NODE_COUNT} initial_atoms=#{initial_atoms} initial_links=#{initial_links} iterations=#{ITERATIONS}"
puts "results=#{results.size} canonical_atom_delta=#{canonical_atom_delta} canonical_link_delta=#{canonical_link_delta}"
puts "constructed_atom_delta=#{constructed_atoms} duplicate_or_merged_candidates=#{constructed_atoms - canonical_atom_delta}"
puts "elapsed_ms=#{elapsed.total_milliseconds.round(3)} gc_total_allocated_delta_bytes=#{allocated_bytes}"
puts "gc_before_heap_bytes=#{before_gc.heap_bytes} gc_before_free_bytes=#{before_gc.free_bytes}"
puts "gc_after_heap_bytes=#{after_gc.heap_bytes} gc_after_free_bytes=#{after_gc.free_bytes}"
puts "gc_settled_heap_bytes=#{settled_gc.heap_bytes} gc_settled_free_bytes=#{settled_gc.free_bytes}"
