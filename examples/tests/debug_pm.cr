require "../../src/pattern_matching/pattern_matching"
require "../../src/pattern_mining/pattern_mining"
require "../../src/atomspace/atomspace_main"
require "../../src/cogutil/cogutil"

CogUtil.initialize
AtomSpace.initialize
PatternMatching.initialize

atomspace = AtomSpace::AtomSpace.new
dog = atomspace.add_concept_node("dog")
cat = atomspace.add_concept_node("cat")
calculator = PatternMining::SupportCalculator.new(atomspace)
var_x = AtomSpace::VariableNode.new("$X")
pattern = PatternMatching::Pattern.new(var_x)
data_atoms = [dog, cat].map(&.as(AtomSpace::Atom))
valuations = calculator.extract_valuations(pattern, data_atoms)
puts "valuations: #{valuations.size}"
matcher = PatternMatching::PatternMatcher.new(atomspace)
matches = matcher.match(pattern)
puts "matches in full AS: #{matches.size}"
matches.each { |m| puts "  #{m.bindings}" }
