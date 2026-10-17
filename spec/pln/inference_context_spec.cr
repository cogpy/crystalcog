require "spec"
require "../../src/pln/pln"

# Adding a rule disables the stock-rule context, providing a live-scan control
# without changing the stock inference rules or adding facts of its own.
private class ContextLegacyControlRule < PLN::PLNRule
  def name : String
    "ContextLegacyControlRule"
  end

  def applies_to?(premise : AtomSpace::Atom) : Bool
    false
  end

  def apply(premise : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom?
    nil
  end
end

private def context_chain : AtomSpace::AtomSpace
  space = AtomSpace::AtomSpace.new
  nodes = Array(AtomSpace::Atom).new
  6.times do |index|
    nodes << space.add_concept_node("context-#{index}", AtomSpace::SimpleTruthValue.new(0.8, 0.9))
  end
  5.times do |index|
    space.add_inheritance_link(nodes[index], nodes[index + 1], AtomSpace::SimpleTruthValue.new(0.7, 0.8))
  end
  space
end

private def context_detached_graph : AtomSpace::AtomSpace
  space = AtomSpace::AtomSpace.new
  a = space.add_concept_node("detached-a", AtomSpace::SimpleTruthValue.new(0.9, 0.9))
  c = space.add_concept_node("detached-c", AtomSpace::SimpleTruthValue.new(0.2, 0.1))
  # These two equivalent nodes have different handles and neither is a fact yet.
  b1 = AtomSpace::ConceptNode.new("detached-b", AtomSpace::SimpleTruthValue.new(0.3, 0.1))
  b2 = AtomSpace::ConceptNode.new("detached-b", AtomSpace::SimpleTruthValue.new(0.3, 0.1))
  space.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [a, b1], AtomSpace::SimpleTruthValue.new(0.8, 0.9))
  space.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [b2, c], AtomSpace::SimpleTruthValue.new(0.7, 0.9))
  space
end

private def context_graph_signature(space : AtomSpace::AtomSpace) : Array(String)
  space.get_all_atoms.map do |atom|
    "#{atom}|#{atom.truth_value.type_name}|#{atom.truth_value.strength}|#{atom.truth_value.confidence}"
  end.sort
end

describe "PLN stock inference context" do
  it "preserves canonical graph closure and truth values against direct live scans" do
    optimized = context_chain
    control = context_chain
    optimized_engine = PLN::PLNEngine.new(optimized)
    control_engine = PLN::PLNEngine.new(control)
    control_engine.add_rule(ContextLegacyControlRule.new)
    optimized_results = optimized_engine.reason(3)
    control_results = control_engine.reason(3)
    optimized_results.size.should eq(control_results.size)
    context_graph_signature(optimized).should eq(context_graph_signature(control))
  end

  it "preserves detached endpoint equality and same-iteration fact creation for three iterations" do
    optimized = context_detached_graph
    control = context_detached_graph
    optimized_engine = PLN::PLNEngine.new(optimized)
    control_engine = PLN::PLNEngine.new(control)
    control_engine.add_rule(ContextLegacyControlRule.new)
    3.times do
      optimized_engine.reason(1)
      control_engine.reason(1)
      context_graph_signature(optimized).should eq(context_graph_signature(control))
    end
    optimized.get_nodes_by_name("detached-b").size.should eq(1)
    optimized.get_nodes_by_name("detached-c").first.truth_value.confidence.should be > 0.1
  end

  it "constructs only accepted canonical atoms rather than discarded duplicate candidates" do
    space = context_chain
    initial_size = space.size
    before = AtomSpace::ConceptNode.new("context-handle-before").handle
    results = PLN::PLNEngine.new(space).reason(2)
    after = AtomSpace::ConceptNode.new("context-handle-after").handle
    constructed = after - before - 1
    constructed.should eq(space.size - initial_size)
    results.size.should eq(constructed)
  end
end
