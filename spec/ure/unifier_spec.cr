require "spec"
require "../../src/ure/ure"

private def var(name : String) : AtomSpace::Atom
  AtomSpace::VariableNode.new(name).as(AtomSpace::Atom)
end

private def concept(name : String) : AtomSpace::Atom
  AtomSpace::ConceptNode.new(name).as(AtomSpace::Atom)
end

private def link(type : AtomSpace::AtomType, *children : AtomSpace::Atom) : AtomSpace::Atom
  AtomSpace::Link.new(type, children.to_a.map(&.as(AtomSpace::Atom))).as(AtomSpace::Atom)
end

private def inherits(a, b)
  link(AtomSpace::AtomType::INHERITANCE_LINK, a, b)
end

private def list(*children : AtomSpace::Atom)
  AtomSpace::Link.new(AtomSpace::AtomType::LIST_LINK, children.to_a.map(&.as(AtomSpace::Atom))).as(AtomSpace::Atom)
end

describe URE::Unifier do
  it "binds a variable to a node of another type, and to a whole link" do
    bindings = URE::Unifier.unify(inherits(var("$X"), concept("animal")), inherits(concept("cat"), concept("animal"))).not_nil!
    bindings.keys.should eq(["$X"])
    bindings["$X"].to_s.should eq(%((CONCEPTNODE "cat")))

    nested = URE::Unifier.unify(list(var("$X"), concept("b")), list(inherits(concept("a"), concept("c")), concept("b"))).not_nil!
    nested["$X"].to_s.should eq(%((INHERITANCELINK (CONCEPTNODE "a") (CONCEPTNODE "c"))))
  end

  it "keeps one value per variable" do
    pattern = list(var("$X"), var("$X"))
    URE::Unifier.unify(pattern, list(concept("a"), concept("a"))).should_not be_nil
    URE::Unifier.unify(pattern, list(concept("a"), concept("b"))).should be_nil
    # Through a chain of variables as well.
    URE::Unifier.unify(list(var("$X"), var("$Y"), var("$Y")), list(var("$Y"), concept("a"), concept("b"))).should be_nil
  end

  it "unifies with variables on both sides" do
    left = list(var("$X"), concept("b"), var("$Z"))
    right = list(concept("a"), var("$Y"), var("$Y"))
    bindings = URE::Unifier.unify(left, right).not_nil!
    URE::Unifier.resolve(left, bindings).to_s.should eq(%((LISTLINK (CONCEPTNODE "a") (CONCEPTNODE "b") (CONCEPTNODE "b"))))
    URE::Unifier.resolve(right, bindings).to_s.should eq(URE::Unifier.resolve(left, bindings).to_s)

    # Two different variables can be made the same without a value.
    shared = URE::Unifier.unify(list(var("$X"), var("$X")), list(var("$Y"), var("$Z"))).not_nil!
    resolved = URE::Unifier.resolve(list(var("$Y"), var("$Z")), shared)
    resolved.as(AtomSpace::Link).outgoing.map(&.name).uniq.size.should eq(1)
  end

  it "refuses a variable inside its own value" do
    URE::Unifier.unify(var("$X"), list(var("$X"), concept("a"))).should be_nil
    URE::Unifier.unify(list(var("$X"), var("$Y")), list(list(var("$Y")), list(var("$X")))).should be_nil
    # A variable does unify with itself.
    URE::Unifier.unify(var("$X"), var("$X")).should eq(URE::Bindings.new)
    # Same name on a different node type is the same variable.
    URE::Unifier.unify(var("$X"), concept("$X")).should eq(URE::Bindings.new)
  end

  it "fails on different constants, link types and arities" do
    URE::Unifier.unify(concept("a"), concept("b")).should be_nil
    URE::Unifier.unify(concept("a"), AtomSpace::PredicateNode.new("a")).should be_nil
    URE::Unifier.unify(inherits(var("$X"), concept("b")), list(concept("a"), concept("b"))).should be_nil
    URE::Unifier.unify(list(var("$X")), list(concept("a"), concept("b"))).should be_nil
    URE::Unifier.unify(concept("a"), list(concept("a"))).should be_nil
    URE::Unifier.unifiable?(concept("a"), concept("a")).should be_true
  end

  it "extends given bindings without changing them" do
    given = URE::Bindings{"$X" => concept("a")}
    URE::Unifier.unify(list(var("$X"), var("$Y")), list(concept("b"), concept("c")), given).should be_nil
    extended = URE::Unifier.unify(list(var("$X"), var("$Y")), list(concept("a"), concept("c")), given).not_nil!
    extended.keys.sort.should eq(["$X", "$Y"])
    given.keys.should eq(["$X"])
  end

  it "lists variables in order and tells ground atoms apart" do
    atom = list(var("$B"), inherits(var("$A"), var("$B")), concept("c"))
    URE::Unifier.variables(atom).should eq(["$B", "$A"])
    URE::Unifier.ground?(atom).should be_false
    URE::Unifier.ground?(list(concept("a"), inherits(concept("b"), concept("c")))).should be_true
    # Resolving leaves an atom without bound variables untouched.
    ground = list(concept("a"))
    URE::Unifier.resolve(ground, URE::Bindings{"$X" => concept("b")}).should be(ground)
  end
end

describe "URE::BackwardChainer#variable_fulfillment_query" do
  it "returns the ground atoms a pattern stands for, not the pattern itself" do
    space = AtomSpace::AtomSpace.new
    chainer = URE::BackwardChainer.new(space)
    dog = space.add_concept_node("dog")
    %w(Fido Rex).each { |name| space.add_inheritance_link(space.add_concept_node(name), dog) }
    space.add_inheritance_link(dog, space.add_concept_node("mammal"))

    x = space.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$x")
    instances = chainer.variable_fulfillment_query(space.add_inheritance_link(x, dog))
    instances.map { |grounding| grounding["$x"].name }.sort.should eq(["Fido", "Rex"])

    parents = chainer.variable_fulfillment_query(space.add_inheritance_link(dog, x))
    parents.map { |grounding| grounding["$x"].name }.should eq(["mammal"])

    # Both ends open: one grounding per stored inheritance link.
    y = space.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$y")
    pairs = chainer.variable_fulfillment_query(space.add_inheritance_link(x, y))
    pairs.map { |grounding| {grounding["$x"].name, grounding["$y"].name} }.sort.should eq(
      [{"Fido", "dog"}, {"Rex", "dog"}, {"dog", "mammal"}])

    # The same variable twice only matches a link from a node to itself.
    chainer.variable_fulfillment_query(space.add_inheritance_link(x, x)).should be_empty
    chainer.variable_fulfillment_query(space.add_inheritance_link(dog, dog)).should be_empty # no variables
  end
end
