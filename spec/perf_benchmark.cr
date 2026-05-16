require "spec"
require "../src/cogutil/cogutil"
require "../src/atomspace/atomspace"
require "../src/pln/pln"
require "../src/ure/ure"
require "../src/opencog/opencog"

# Performance and benchmarking tests for CrystalCog
describe "CrystalCog Performance Tests" do
  describe "AtomSpace performance" do
    before_each do
    end

    it "benchmarks atom creation" do
      num_atoms = 1000

      start_time = Time.instant

      atoms = num_atoms.times.map { |i|
        atomspace.add_concept_node("concept_#{i}")
      }.to_a

      end_time = Time.instant
      duration = end_time - start_time

      # Should create atoms quickly
      duration.should be < 1.second

      # Should have created all atoms
      atomspace.size.should eq(num_atoms)

      # Rate should be reasonable (>500 atoms/second)
      rate = num_atoms / duration.total_seconds
      rate.should be > 500.0

      puts "Atom creation rate: #{rate.round(2)} atoms/second"
      puts "Duration: #{duration.total_milliseconds.round(2)}ms"
      puts "Average per atom: #{(duration.total_milliseconds / num_atoms).round(4)}ms"
    end

    it "benchmarks atom retrieval" do
      # Pre-populate atomspace
      num_atoms = 500
      atoms = num_atoms.times.map { |i|
        atomspace.add_concept_node("concept_#{i}")
      }.to_a

      # Benchmark retrieval
      num_retrievals = 1000

      start_time = Time.instant

      num_retrievals.times do
        random_atom = atoms.sample
        retrieved = atomspace.get_atom(random_atom.handle)
        retrieved.should eq(random_atom)
      end

      end_time = Time.instant
      duration = end_time - start_time

      # Should retrieve quickly
      duration.should be < 0.5.seconds

      rate = num_retrievals / duration.total_seconds
      rate.should be > 1000.0

      puts "Atom retrieval rate: #{rate.round(2)} retrievals/second"
      puts "Duration: #{duration.total_milliseconds.round(2)}ms"
    end
  end
end
