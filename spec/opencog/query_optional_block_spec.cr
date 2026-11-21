require "spec"
require "../../src/opencog/query_language"

private def optional_pets : AtomSpace::AtomSpace
  space = AtomSpace::AtomSpace.new
  animal = space.add_concept_node("Animal")
  likes = space.add_predicate_node("likes")
  {"Dog" => 0.9, "Cat" => 0.8, "Blue Whale" => 0.7}.each do |name, confidence|
    space.add_inheritance_link(space.add_concept_node(name), animal,
      AtomSpace::SimpleTruthValue.new(1.0, confidence))
  end
  {"Dog" => ["Bone", "Ball"], "Cat" => ["Fish"]}.each do |name, foods|
    foods.each do |food|
      space.add_evaluation_link(likes,
        space.add_list_link([space.get_nodes_by_name(name).first, space.add_concept_node(food)] of AtomSpace::Atom),
        AtomSpace::SimpleTruthValue.new(0.6, 0.2))
    end
  end
  # Deliberately no Ball/Fish ISA Edible: a partial match must not enrich.
  space.add_inheritance_link(space.get_nodes_by_name("Bone").first, space.add_concept_node("Edible"),
    AtomSpace::SimpleTruthValue.new(0.5, 0.4))
  space
end

private def optional_query(space : AtomSpace::AtomSpace, text : String)
  OpenCog::QueryLanguage.create_interface(space).query(text)
end

private def optional_table(results, *columns : String) : Array(Array(String?))
  results.map { |result| columns.map { |column| result.bindings[column]?.try(&.name) }.to_a }
    .sort_by { |row| row.map { |value| value || "" } }
end

private def optional_parse(text : String)
  OpenCog::QueryLanguage::QueryParser.parse(text)
end

describe "OpenCog OPTIONAL blocks" do
  it "enriches only complete conjunctions and preserves unmatched outer rows once" do
    results = optional_query(optional_pets,
      "SELECT $x $food WHERE { $x ISA Animal . OPTIONAL { $x likes $food . $food ISA Edible } }")
    optional_table(results, "x", "food").should eq([["Blue Whale", nil], ["Cat", nil], ["Dog", "Bone"]])
  end

  it "applies local FILTERs after the complete join regardless of their placement" do
    space = optional_pets
    [
      "FILTER($food = Bone) . $x likes $food . $food ISA Edible",
      "$x likes $food . FILTER($food = Bone) . $food ISA Edible",
      "$x likes $food . $food ISA Edible . FILTER($food = Bone)",
    ].each do |unit|
      results = optional_query(space, "SELECT $x $food WHERE { $x ISA Animal . OPTIONAL { #{unit} } }")
      optional_table(results, "x", "food").should eq([["Blue Whale", nil], ["Cat", nil], ["Dog", "Bone"]])
    end
  end

  it "lets local FILTERs read merged outer and inner bindings and requires every filter" do
    results = optional_query(optional_pets,
      "SELECT $x $food WHERE { $x ISA $kind . OPTIONAL { FILTER($kind = Animal) . " \
      "$x likes $food . $food ISA Edible . FILTER($food = Bone) } . FILTER($kind = Animal) }")
    optional_table(results, "x", "food").should eq([["Blue Whale", nil], ["Cat", nil], ["Dog", "Bone"]])
    rejected = optional_query(optional_pets,
      "SELECT $x $food WHERE { $x ISA Animal . OPTIONAL { $x likes $food . $food ISA Edible . " \
      "FILTER($food = Bone) . FILTER($x = Cat) } }")
    optional_table(rejected, "x", "food").should eq([["Blue Whale", nil], ["Cat", nil], ["Dog", nil]])
  end

  it "retains outer evidence only when a local filter rejects every candidate" do
    space = optional_pets
    baseline = optional_query(space, "SELECT $x WHERE { $x ISA Animal }")
    rejected = optional_query(space,
      "SELECT $x $food WHERE { $x ISA Animal . OPTIONAL { $x likes $food . $food ISA Edible . FILTER($food = Ball) } }")
    rejected.size.should eq(baseline.size)
    rejected.each do |row|
      row.bindings.has_key?("food").should be_false
      original = baseline.find! { |candidate| candidate.bindings["x"].same?(row.bindings["x"]) }
      row.confidence.should eq(original.confidence)
    end
  end

  it "discards evidence and bindings from partial matches when a later clause has no solutions" do
    space = optional_pets
    results = optional_query(space,
      "SELECT $x $food WHERE { $x ISA Animal . OPTIONAL { $x likes $food . $food ISA Unheard } }")
    optional_table(results, "x", "food").should eq([["Blue Whale", nil], ["Cat", nil], ["Dog", nil]])
    results.find! { |row| row.bindings["x"].name == "Dog" }.confidence.should eq(0.9)
  end

  it "adds evidence only from the successful complete candidate without double evaluation" do
    results = optional_query(optional_pets,
      "SELECT $x $food WHERE { $x ISA Animal . OPTIONAL { $x likes $food . $food ISA Edible } }")
    results.find! { |row| row.bindings["x"].name == "Dog" }.confidence.should be_close((0.9 + 0.2 + 0.4) / 3, 1e-9)
    results.find! { |row| row.bindings["x"].name == "Cat" }.confidence.should eq(0.8)
    results.find! { |row| row.bindings["x"].name == "Blue Whale" }.confidence.should eq(0.7)
  end

  it "keeps separate OPTIONAL blocks independent" do
    results = optional_query(optional_pets,
      "SELECT $x $food $toy WHERE { $x ISA Animal . " \
      "OPTIONAL { $x likes $food . $food ISA Edible } . OPTIONAL { $x likes $toy . FILTER($toy != Bone) } }")
    optional_table(results, "x", "food", "toy").should eq([
      ["Blue Whale", nil, nil], ["Cat", nil, "Fish"], ["Dog", "Bone", "Ball"],
    ])
  end

  it "expands each outer row for several complete optional matches" do
    space = optional_pets
    biscuit = space.add_concept_node("Biscuit")
    space.add_inheritance_link(biscuit, space.get_nodes_by_name("Edible").first)
    space.add_evaluation_link(space.get_nodes_by_name("likes").first,
      space.add_list_link([space.get_nodes_by_name("Dog").first, biscuit] of AtomSpace::Atom))
    results = optional_query(space,
      "SELECT $x $food WHERE { $x ISA Animal . OPTIONAL { $x likes $food . $food ISA Edible } }")
    optional_table(results, "x", "food").should eq([
      ["Blue Whale", nil], ["Cat", nil], ["Dog", "Biscuit"], ["Dog", "Bone"],
    ])
  end

  it "respects existing shared bindings when joining the optional unit" do
    results = optional_query(optional_pets,
      "SELECT $x $food WHERE { $x ISA Animal . $x likes $food . OPTIONAL { $food ISA $kind . FILTER($kind = Edible) } }")
    optional_table(results, "x", "food").should eq([["Cat", "Fish"], ["Dog", "Ball"], ["Dog", "Bone"]])
    results.find! { |row| row.bindings["food"].name == "Ball" }.confidence.should be_close((0.9 + 0.2) / 2, 1e-9)
    shared = optional_query(optional_pets,
      "SELECT $x $choice $food WHERE { $x ISA Animal . $x likes $choice . " \
      "OPTIONAL { $x likes $food . $food ISA Edible . FILTER($food = $choice) } }")
    optional_table(shared, "x", "choice", "food").should eq([
      ["Cat", "Fish", nil], ["Dog", "Ball", nil], ["Dog", "Bone", "Bone"],
    ])
  end

  it "applies selected variable type constraints inside the optional block" do
    space = optional_pets
    concepts = optional_query(space,
      "SELECT $x:CONCEPT $food:CONCEPT WHERE { $x ISA Animal . OPTIONAL { $x likes $food . $food ISA Edible } }")
    optional_table(concepts, "x", "food").should eq([["Blue Whale", nil], ["Cat", nil], ["Dog", "Bone"]])
    predicates = optional_query(space,
      "SELECT $x $food:PREDICATE WHERE { $x ISA Animal . OPTIONAL { $x likes $food . $food ISA Edible } }")
    optional_table(predicates, "x", "food").should eq([["Blue Whale", nil], ["Cat", nil], ["Dog", nil]])
  end

  it "joins path clauses inside the unit and applies their constraints and local filters" do
    space = optional_pets
    ["$x likes+ $food . $food ISA+ Edible", "$food ISA+ Edible . $x likes+ $food"].each do |unit|
      results = optional_query(space,
        "SELECT $x $food:CONCEPT WHERE { $x ISA Animal . OPTIONAL { #{unit} . FILTER($food = Bone) } }")
      optional_table(results, "x", "food").should eq([["Blue Whale", nil], ["Cat", nil], ["Dog", "Bone"]])
    end
    results = optional_query(space,
      "SELECT $x $food:PREDICATE WHERE { $x ISA Animal . OPTIONAL { $x likes+ $food . $food ISA+ Edible } }")
    optional_table(results, "x", "food").should eq([["Blue Whale", nil], ["Cat", nil], ["Dog", nil]])
  end

  it "applies an outer BOUND filter after optional enrichment" do
    results = optional_query(optional_pets,
      "SELECT $x $food WHERE { $x ISA Animal . FILTER(BOUND($food)) . " \
      "OPTIONAL { $x likes $food . $food ISA Edible . FILTER($food = Bone) } }")
    optional_table(results, "x", "food").should eq([["Dog", "Bone"]])
  end

  it "preserves legacy flat construction as independent single-clause left joins" do
    clauses = [OpenCog::QueryLanguage::InheritanceClause.new("$x", "Animal").as(OpenCog::QueryLanguage::QueryClause)]
    optional = [
      OpenCog::QueryLanguage::TripleClause.new("$x", "likes", "$food").as(OpenCog::QueryLanguage::QueryClause),
      OpenCog::QueryLanguage::InheritanceClause.new("$food", "Edible").as(OpenCog::QueryLanguage::QueryClause),
    ]
    query = OpenCog::QueryLanguage::ParsedQuery.new(
      ["x", "food"].map { |name| OpenCog::QueryLanguage::QueryVariable.new(name) }, clauses, optional_clauses: optional)
    query.optional_clauses.should eq(optional)
    results = OpenCog::QueryLanguage::QueryExecutor.new(optional_pets).execute(query)
    # The caller supplied no block boundaries; do not reinterpret this as one conjunction.
    optional_table(results, "x", "food").should eq([
      ["Blue Whale", "Bone"], ["Cat", "Fish"], ["Dog", "Ball"], ["Dog", "Bone"],
    ])
  end

  it "supports explicit programmatic units with conjunction and local filters" do
    block = OpenCog::QueryLanguage::QueryBlock.new
    block.clauses << OpenCog::QueryLanguage::InheritanceClause.new("$x", "Animal")
    clauses = [
      OpenCog::QueryLanguage::TripleClause.new("$x", "likes", "$food").as(OpenCog::QueryLanguage::QueryClause),
      OpenCog::QueryLanguage::InheritanceClause.new("$food", "Edible").as(OpenCog::QueryLanguage::QueryClause),
    ]
    filters = [OpenCog::QueryLanguage::ComparisonCondition.new(
      OpenCog::QueryLanguage::QueryValue.new(:variable, "food"), "=",
      OpenCog::QueryLanguage::QueryValue.new(:text, "Bone")).as(OpenCog::QueryLanguage::QueryCondition)]
    block.optional_blocks << OpenCog::QueryLanguage::QueryOptionalBlock.new(clauses, filters)
    query = OpenCog::QueryLanguage::ParsedQuery.new(
      ["x", "food"].map { |name| OpenCog::QueryLanguage::QueryVariable.new(name) }, [block])
    results = OpenCog::QueryLanguage::QueryExecutor.new(optional_pets).execute(query)
    optional_table(results, "x", "food").should eq([["Blue Whale", nil], ["Cat", nil], ["Dog", "Bone"]])
  end

  it "adapts added legacy clause objects without re-evaluating parsed units" do
    query = optional_parse("SELECT $x $food $toy WHERE { $x ISA Animal . " \
                           "OPTIONAL { $x likes $food . $food ISA Edible } . OPTIONAL { $x likes $toy . FILTER($toy = Ball) } }")
    block = query.blocks.first
    # A separate, structurally identical clause object is a legacy unit;
    # object identity, not clause text, distinguishes inspection entries.
    block.optional_clauses << OpenCog::QueryLanguage::TripleClause.new("$x", "likes", "$toy")
    block.optional_units.size.should eq(3)
    results = OpenCog::QueryLanguage::QueryExecutor.new(optional_pets).execute(query)
    optional_table(results, "x", "food", "toy").should eq([
      ["Blue Whale", nil, nil], ["Cat", nil, "Fish"], ["Dog", "Bone", "Ball"],
    ])
    results.find! { |row| row.bindings["x"].name == "Dog" }.confidence.should be_close((0.9 + 0.2 + 0.4 + 0.2 + 0.2) / 5, 1e-9)
  end

  it "rejects explicit programmatic units without any matching clause" do
    [
      [] of OpenCog::QueryLanguage::QueryCondition,
      [OpenCog::QueryLanguage::BoundCondition.new("x").as(OpenCog::QueryLanguage::QueryCondition)],
    ].each do |filters|
      expect_raises(OpenCog::QueryLanguage::QueryExecutionException, "OPTIONAL needs at least one clause") do
        OpenCog::QueryLanguage::QueryOptionalBlock.new([] of OpenCog::QueryLanguage::QueryClause, filters)
      end
    end
  end

  it "keeps single-clause OPTIONAL queries and the flattened inspection API compatible" do
    query = optional_parse("SELECT $x $food WHERE { $x ISA Animal . OPTIONAL { $x likes $food } }")
    query.optional_clauses.map(&.to_s).should eq(["TripleClause($x likes $food)"])
    results = OpenCog::QueryLanguage::QueryExecutor.new(optional_pets).execute(query)
    optional_table(results, "x", "food").should eq([
      ["Blue Whale", nil], ["Cat", "Fish"], ["Dog", "Ball"], ["Dog", "Bone"],
    ])
  end

  it "does not mutate stored atom identity, count, truth values or VariableNodes" do
    space = optional_pets
    atoms = space.get_all_atoms
    truth = atoms.map { |atom| {atom.truth_value, atom.truth_value.strength, atom.truth_value.confidence} }
    count = space.size
    [
      "$x likes $food . $food ISA Edible . FILTER($food = Bone)",
      "$x likes $food . $food ISA Edible . FILTER($food = Ball)",
      "$x likes+ $food . $food ISA+ Edible . FILTER($food = Bone)",
      "$x unknown-relation $food . $food ISA UnknownKind",
    ].each do |unit|
      optional_query(space, "SELECT $x $food WHERE { $x ISA Animal . OPTIONAL { #{unit} } }")
    end
    space.size.should eq(count)
    after = space.get_all_atoms
    after.size.should eq(atoms.size)
    atoms.each_with_index do |atom, index|
      after.find! { |stored| stored.handle == atom.handle }.should be(atom)
      atom.truth_value.should be(truth[index][0])
      {atom.truth_value.strength, atom.truth_value.confidence}.should eq({truth[index][1], truth[index][2]})
    end
    space.get_atoms_by_type(AtomSpace::AtomType::VARIABLE_NODE).should be_empty
    space.get_nodes_by_name("UnknownKind").should be_empty
    space.get_nodes_by_name("unknown-relation").should be_empty
  end

  it "explicitly rejects empty, filter-only and unsupported nested optional constructs" do
    {
      ""                                          => "OPTIONAL needs at least one clause",
      "FILTER($x = Dog)"                          => "OPTIONAL needs at least one clause",
      "OPTIONAL { $x ISA Animal }"                => "OPTIONAL cannot be nested",
      "BIND($x AS $same)"                         => "BIND belongs to the block around the OPTIONAL",
      "VALUES $food { Bone }"                     => "VALUES belongs to the block around the OPTIONAL",
      "MINUS { $x ISA Animal }"                   => "MINUS belongs to the block around the OPTIONAL",
      "{ SELECT $x WHERE { $x ISA Animal } }"     => "a subquery cannot be inside OPTIONAL",
      "{ $x ISA Animal }"                         => "a group cannot be inside OPTIONAL",
      "{ $x ISA Animal } UNION { $x ISA Edible }" => "a group cannot be inside OPTIONAL",
    }.each do |unit, message|
      error = expect_raises(OpenCog::QueryLanguage::QueryParseException) do
        optional_parse("SELECT $x WHERE { $x ISA Animal . OPTIONAL { #{unit} } }")
      end
      error.message.not_nil!.should contain(message)
      error.message.not_nil!.should contain("line 1, column")
    end
  end
end
