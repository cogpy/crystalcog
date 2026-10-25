require "spec"
require "../../src/opencog/query_language"

describe "OpenCog::QueryLanguage conjunctive queries" do
  it "parses ISA as an inheritance clause" do
    query = OpenCog::QueryLanguage::QueryParser.parse("SELECT $x WHERE { $x ISA Animal }")
    query.clauses.first.should be_a(OpenCog::QueryLanguage::InheritanceClause)
  end

  it "binds variables from an inheritance clause" do
    space = AtomSpace::AtomSpace.new
    animal = space.add_concept_node("Animal")
    space.add_inheritance_link(space.add_concept_node("Dog"), animal)
    space.add_inheritance_link(space.add_concept_node("Cat"), animal)

    results = OpenCog::QueryLanguage.create_interface(space).query("SELECT $x WHERE { $x ISA Animal }")
    names = results.compact_map { |r| r.bindings["x"]?.try(&.name) }
    names.should contain("Dog")
    names.should contain("Cat")
  end

  it "joins clauses on shared variables" do
    space = AtomSpace::AtomSpace.new
    animal = space.add_concept_node("Animal")
    pet = space.add_concept_node("Pet")
    dog = space.add_concept_node("Dog")
    wolf = space.add_concept_node("Wolf")
    space.add_inheritance_link(dog, animal)
    space.add_inheritance_link(wolf, animal)
    space.add_inheritance_link(dog, pet)

    results = OpenCog::QueryLanguage.create_interface(space).query("SELECT $x WHERE { $x ISA Animal . $x ISA Pet }")
    names = results.compact_map { |r| r.bindings["x"]?.try(&.name) }.uniq
    names.should eq(["Dog"])
  end
end
