require "../../src/ure/ure"
require "../../src/pln/pln"
require "../../src/atomspace/atomspace_main"
require "../../src/cogutil/cogutil"

CogUtil.initialize
AtomSpace.initialize
URE.initialize
PLN.initialize

aspace = AtomSpace::AtomSpace.new
dog = aspace.add_concept_node("dog")
mammal = aspace.add_concept_node("mammal")
animal = aspace.add_concept_node("animal")
tv = AtomSpace::SimpleTruthValue.new(0.9, 0.9)
aspace.add_inheritance_link(dog, mammal, tv)
aspace.add_inheritance_link(mammal, animal, tv)
puts "Initial size: #{aspace.size}"
engine = URE.create_engine(aspace)
result = engine.forward_chain(5)
puts "URE Result size: #{result.size}"
puts "Final atomspace size: #{aspace.size}"
result.each { |a| puts "  #{a}" }
aspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK).each { |a| puts "LINK: #{a}" }

aspace2 = AtomSpace::AtomSpace.new
d = aspace2.add_concept_node("dog")
m = aspace2.add_concept_node("mammal")
a = aspace2.add_concept_node("animal")
aspace2.add_inheritance_link(d, m, tv)
aspace2.add_inheritance_link(m, a, tv)
puts "PLN initial: #{aspace2.size}"
pln_engine = PLN::PLNEngine.new(aspace2)
nr = pln_engine.reason(5)
puts "PLN result: #{nr.size}, final size: #{aspace2.size}"
nr.each { |x| puts "  #{x}" }
