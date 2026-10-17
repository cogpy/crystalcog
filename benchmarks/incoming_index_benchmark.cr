require "../src/atomspace/atomspace"
require "../src/cogutil/cogutil"

# Compare exactly the same incoming-link query using the index and a linear scan.
# No absolute timing gate: measurements vary by CPU and graph degree.
CogUtil::Logger.set_level(CogUtil::LogLevel::ERROR)
size = ARGV[0]?.try(&.to_i) || 10_000
iterations = ARGV[1]?.try(&.to_i) || 1_000
raise ArgumentError.new("size and iterations must be positive") unless size > 0 && iterations > 0

space = AtomSpace::AtomSpace.new
target = space.add_concept_node("target")
size.times do |i|
  a = space.add_concept_node("a#{i}")
  b = i < 10 ? target : space.add_concept_node("b#{i}")
  space.add_inheritance_link(a, b)
end
links = space.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)
adjacency = links.map { |link| {link.handle, link.outgoing.map(&.handle)} }
expected = adjacency.select { |_, outgoing| outgoing.includes?(target.handle) }.map(&.[0]).sort
actual = space.get_incoming(target).map(&.handle).sort
raise "Index differs from scan" unless expected == actual

indexed_count = 0
scan_count = 0
indexed_time = Time.measure do
  iterations.times { indexed_count += space.get_incoming(target).size }
end
scan_time = Time.measure do
  iterations.times do
    scan_count += adjacency.count { |_, outgoing| outgoing.includes?(target.handle) }
  end
end
raise "Benchmark query counts differ" unless indexed_count == scan_count
puts "Links: #{size}; incoming degree: #{actual.size}; queries: #{iterations}"
puts "Indexed: #{indexed_time.total_milliseconds.round(3)} ms"
puts "Linear scan: #{scan_time.total_milliseconds.round(3)} ms"
puts "Speedup: #{(scan_time.total_seconds / indexed_time.total_seconds).round(2)}x"
