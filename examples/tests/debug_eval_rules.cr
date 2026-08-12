require "../../src/ure/ure"
require "../../src/pln/pln"
require "../../src/atomspace/atomspace_main"
require "../../src/cogutil/cogutil"

CogUtil.initialize
AtomSpace.initialize
URE.initialize

# Spatial
aspace = AtomSpace::AtomSpace.new
cat = aspace.add_concept_node("cat")
mat = aspace.add_concept_node("mat")
floor = aspace.add_concept_node("floor")
on = aspace.add_predicate_node("on")
tv = AtomSpace::SimpleTruthValue.new(0.9, 0.8)
aspace.add_evaluation_link(on, aspace.add_list_link([cat, mat]), tv)
aspace.add_evaluation_link(on, aspace.add_list_link([mat, floor]), tv)
engine = URE.create_engine(aspace)
r = engine.forward_chain(5)
puts "Spatial results: #{r.size}"
r.each { |a| puts "  #{a}" }

# Family
aspace2 = AtomSpace::AtomSpace.new
john = aspace2.add_concept_node("John")
bob = aspace2.add_concept_node("Bob")
father_of = aspace2.add_predicate_node("father_of")
parent_of = aspace2.add_predicate_node("parent_of")
tv_c = AtomSpace::SimpleTruthValue.new(1.0, 0.95)
tv_l = AtomSpace::SimpleTruthValue.new(0.9, 0.8)
aspace2.add_evaluation_link(father_of, aspace2.add_list_link([john, bob]), tv_c)
aspace2.add_implication_link(
  aspace2.add_evaluation_link(father_of, aspace2.add_variable_node("$X", "$Y")),
  aspace2.add_evaluation_link(parent_of, aspace2.add_variable_node("$X", "$Y")),
  tv_l
)
engine2 = URE.create_engine(aspace2)
r2 = engine2.forward_chain(5)
puts "Family results: #{r2.size}"
r2.each { |a| puts "  #{a}" }
parent_facts = aspace2.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK).select { |l|
  l.is_a?(AtomSpace::EvaluationLink) && l.predicate == parent_of
}
puts "Parent facts: #{parent_facts.size}"
parent_facts.each { |a| puts "  #{a}" }

# Link grammar
require "../../src/nlp/link_grammar"
NLP.initialize if NLP.responds_to?(:initialize)
parser = NLP::LinkGrammar::Parser.new
linkages = parser.parse("The cat sits")
puts "LG linkages: #{linkages.size}, links: #{linkages.first.links.size}"
linkages.first.links.each { |l| puts "  #{l}" }
