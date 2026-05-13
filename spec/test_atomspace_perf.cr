require "spec"
require "../src/atomspace/atomspace"

# Basic AtomSpace performance test
describe "AtomSpace Performance" do
  it "measures atom creation performance" do
    atomspace = AtomSpace::AtomSpace.new

    start_time = Time.instant

    num_atoms = 1000
    atoms = num_atoms.times.map { |i|
      atomspace.add_concept_node("concept_#{i}")
    }.to_a

    end_time = Time.instant
    duration = end_time - start_time

    # Should create atoms quickly
    duration.should be < 5.seconds

    # Should have created all atoms
    atomspace.size.should eq(num_atoms)

    # Calculate rate
    rate = num_atoms / duration.total_seconds
    puts "Atom creation rate: #{rate.round(2)} atoms/second"
    puts "Duration: #{duration.total_milliseconds.round(2)}ms"
    puts "Average per atom: #{(duration.total_milliseconds / num_atoms).round(4)}ms"
  end
end
