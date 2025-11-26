require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"

describe "AtomSpace variable node and implication link" do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
  end

  it "creates single variable node" do
    atomspace = AtomSpace::AtomSpace.new
    
    var = atomspace.add_variable_node("$X")
    
    var.should be_a(AtomSpace::Node)
    var.type.should eq(AtomSpace::AtomType::VARIABLE_NODE)
    var.as(AtomSpace::Node).name.should eq("$X")
  end

  it "creates variable list from multiple variables" do
    atomspace = AtomSpace::AtomSpace.new
    
    var_list = atomspace.add_variable_node("$X", "$Y")
    
    var_list.should be_a(AtomSpace::ListLink)
    var_list.type.should eq(AtomSpace::AtomType::LIST_LINK)
    
    link = var_list.as(AtomSpace::Link)
    link.outgoing.size.should eq(2)
    link.outgoing[0].type.should eq(AtomSpace::AtomType::VARIABLE_NODE)
    link.outgoing[1].type.should eq(AtomSpace::AtomType::VARIABLE_NODE)
    link.outgoing[0].as(AtomSpace::Node).name.should eq("$X")
    link.outgoing[1].as(AtomSpace::Node).name.should eq("$Y")
  end

  it "creates implication link" do
    atomspace = AtomSpace::AtomSpace.new
    
    # Create predicates
    father_of = atomspace.add_predicate_node("father_of")
    parent_of = atomspace.add_predicate_node("parent_of")
    
    # Create evaluation links with variables
    tv = AtomSpace::SimpleTruthValue.new(0.9, 0.8)
    father_eval = atomspace.add_evaluation_link(
      father_of,
      atomspace.add_variable_node("$X", "$Y")
    )
    parent_eval = atomspace.add_evaluation_link(
      parent_of,
      atomspace.add_variable_node("$X", "$Y")
    )
    
    # Create implication
    implication = atomspace.add_implication_link(father_eval, parent_eval, tv)
    
    implication.should be_a(AtomSpace::ImplicationLink)
    implication.type.should eq(AtomSpace::AtomType::IMPLICATION_LINK)
    
    impl = implication.as(AtomSpace::ImplicationLink)
    impl.antecedent.should eq(father_eval)
    impl.consequent.should eq(parent_eval)
    impl.truth_value.strength.should eq(0.9)
    impl.truth_value.confidence.should eq(0.8)
  end

  it "uses variable nodes in reasoning rules" do
    atomspace = AtomSpace::AtomSpace.new
    
    # Create concrete instances
    john = atomspace.add_concept_node("John")
    bob = atomspace.add_concept_node("Bob")
    
    # Create predicates
    father_of = atomspace.add_predicate_node("father_of")
    parent_of = atomspace.add_predicate_node("parent_of")
    
    # Create fact: John is father of Bob
    tv_certain = AtomSpace::SimpleTruthValue.new(1.0, 0.95)
    fact = atomspace.add_evaluation_link(
      father_of,
      atomspace.add_list_link([john, bob]),
      tv_certain
    )
    
    # Create rule: father_of($X, $Y) implies parent_of($X, $Y)
    tv_rule = AtomSpace::SimpleTruthValue.new(1.0, 0.9)
    rule = atomspace.add_implication_link(
      atomspace.add_evaluation_link(father_of, atomspace.add_variable_node("$X", "$Y")),
      atomspace.add_evaluation_link(parent_of, atomspace.add_variable_node("$X", "$Y")),
      tv_rule
    )
    
    # Verify all atoms are in atomspace
    atomspace.size.should be > 0
    atomspace.contains?(fact).should be_true
    atomspace.contains?(rule).should be_true
    
    # Verify we can retrieve the implication link
    implications = atomspace.get_atoms_by_type(AtomSpace::AtomType::IMPLICATION_LINK)
    implications.size.should eq(1)
    implications[0].should eq(rule)
  end
end
