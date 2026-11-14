require "spec"
require "../../src/opencog/query_language"

private def parse(text : String)
  OpenCog::QueryLanguage::QueryParser.parse(text)
end

private def parse_error(text : String) : String
  expect_raises(OpenCog::QueryLanguage::QueryParseException) { parse(text) }.message.not_nil!
end

private def pets : AtomSpace::AtomSpace
  space = AtomSpace::AtomSpace.new
  animal = space.add_concept_node("Animal")
  likes = space.add_predicate_node("likes")
  dog = space.add_concept_node("Dog")
  cat = space.add_concept_node("Cat")
  whale = space.add_concept_node("Blue Whale")
  [dog, cat, whale].each { |creature| space.add_inheritance_link(creature, animal) }
  space.add_evaluation_link(likes, space.add_list_link([dog, space.add_concept_node("Bone")] of AtomSpace::Atom))
  space.add_evaluation_link(likes, space.add_list_link([dog, space.add_concept_node("Ball")] of AtomSpace::Atom))
  space.add_evaluation_link(likes, space.add_list_link([cat, space.add_concept_node("Fish")] of AtomSpace::Atom))
  space
end

private def names(results, variable : String) : Array(String)
  results.compact_map { |result| result.bindings[variable]?.try(&.name) }.sort
end

describe OpenCog::QueryLanguage::QueryLexer do
  it "splits a query into tokens with their positions" do
    tokens = OpenCog::QueryLanguage::QueryLexer.new("select $x:Concept\nWHERE { $x -> \"Blue Whale\" } # tail").tokens
    tokens.map { |token| {token.kind, token.text} }.should eq([
      {:keyword, "SELECT"}, {:variable, "x"}, {:punctuation, ":"}, {:name, "Concept"}, {:newline, "\n"},
      {:keyword, "WHERE"}, {:punctuation, "{"}, {:variable, "x"}, {:punctuation, "->"}, {:string, "Blue Whale"},
      {:punctuation, "}"}, {:end, ""},
    ])
    {tokens[5].line, tokens[5].column}.should eq({2, 1})
    {tokens[9].line, tokens[9].column}.should eq({2, 15})
  end

  it "reads hyphenated names, escapes and numbers" do
    tokens = OpenCog::QueryLanguage::QueryLexer.new(%(well-known->x "a \\"b\\"" 42)).tokens
    tokens.map(&.text).should eq(["well-known", "->", "x", %(a "b"), "42", ""])
    tokens[4].kind.should eq(:integer)
  end

  it "reports characters and strings it cannot read" do
    parse_error("SELECT $x WHERE { $x ISA @ }").should eq("unexpected character '@' at line 1, column 26")
    parse_error("SELECT $ WHERE { }").should eq("a variable needs a name after '$' at line 1, column 9")
    parse_error("SELECT $x WHERE { $x ISA \"open }").should eq("unterminated quoted name at line 1, column 26")
    parse_error("SELECT $x WHERE { $x - y }").should eq("expected '->' at line 1, column 22")
  end
end

describe OpenCog::QueryLanguage::QueryParser do
  it "parses variables whose names contain any letter" do
    # The old pattern stopped the variable list at the first "W".
    query = parse("SELECT $Who, $What WHERE { $Who likes $What }")
    query.variables.map(&.name).should eq(["Who", "What"])
    query.clauses.size.should eq(1)
    query.clauses.first.to_s.should eq("TripleClause($Who likes $What)")
  end

  it "accepts every inheritance spelling and clause separator" do
    query = parse("SELECT $x WHERE {\n  $x ISA Animal\n  $x inherits_from Pet . $x -> \"Blue Whale\"\n}")
    query.clauses.map(&.to_s).should eq([
      "InheritanceClause($x -> Animal)", "InheritanceClause($x -> Pet)", "InheritanceClause($x -> Blue Whale)",
    ])
    parse("select $x where { $x isa Animal. }").clauses.size.should eq(1)
  end

  it "reads types, DISTINCT, LIMIT, OPTIONAL and SELECT *" do
    query = parse("SELECT DISTINCT $c:Concept $p:PREDICATE_NODE WHERE { $c $p $o . OPTIONAL { $c ISA $kind } } LIMIT 5")
    query.variables.map(&.type).should eq([AtomSpace::AtomType::CONCEPT_NODE, AtomSpace::AtomType::PREDICATE_NODE])
    query.distinct?.should be_true
    query.limit.should eq(5)
    query.clauses.size.should eq(1)
    query.optional_clauses.map(&.to_s).should eq(["InheritanceClause($c -> $kind)"])

    everything = parse("SELECT * WHERE { $a likes $b . $b ISA $c }")
    everything.variables.map(&.name).should eq(["a", "b", "c"])
    everything.distinct?.should be_false
    everything.limit.should be_nil
  end

  it "says what it expected, what it found and where" do
    parse_error("GET $x WHERE { $x }").should eq(%(Query must start with SELECT, found "GET" at line 1, column 1))
    parse_error("SELECT $x").should eq("Missing WHERE clause: expected WHERE, found the end of the query at line 1, column 10")
    parse_error("SELECT x WHERE { x ISA y }").should eq("Variables must start with $ : x at line 1, column 8")
    parse_error("SELECT $x:Blob WHERE { $x ISA y }").should eq("unknown type Blob at line 1, column 11")
    parse_error("SELECT $x, $x WHERE { $x ISA y }").should eq("$x is selected twice at line 1, column 12")
    parse_error("SELECT $x WHERE { }").should eq("WHERE needs at least one clause at line 1, column 19")
    parse_error("SELECT $x WHERE { $x ISA }").should eq(%(expected a term, found "}" at line 1, column 26))
    parse_error("SELECT $x WHERE { $x likes }").should eq(%(expected the object of the triple, found "}" at line 1, column 28))
    parse_error("SELECT $x WHERE { $x likes y z }").should eq(%(expected '.', a line break or '}' after the clause, found "z" at line 1, column 30))
    parse_error("SELECT $x WHERE { $x ISA y").should eq("expected '}' to close the block, found the end of the query at line 1, column 27")
    parse_error("SELECT $x WHERE { $x ISA y } LIMIT many").should eq(%(expected a number after LIMIT, found "many" at line 1, column 36))
    parse_error("SELECT $x WHERE { $x ISA y } extra").should eq(%(expected the end of the query, found "extra" at line 1, column 30))
    parse_error("SELECT $x WHERE { $y ISA Animal }").should eq("$x is selected but does not appear in WHERE")
    parse_error("SELECT $x WHERE { $x ISA y . OPTIONAL { OPTIONAL { $x ISA z } } }").should eq("OPTIONAL cannot be nested at line 1, column 41")
    parse_error("SELECT $x WHERE {\n  $x ISA\n}").should eq("expected a term, found a line break at line 2, column 9")
  end
end

describe "OpenCog query execution" do
  it "matches quoted names and returns only the selected variables" do
    interface = OpenCog::QueryLanguage.create_interface(pets)
    names(interface.query(%(SELECT $x WHERE { $x ISA Animal })), "x").should eq(["Blue Whale", "Cat", "Dog"])

    results = interface.query("SELECT $who WHERE { $who likes $what }")
    names(results, "who").should eq(["Cat", "Dog", "Dog"])
    results.all? { |result| result.bindings.keys == ["who"] }.should be_true
  end

  it "applies DISTINCT and LIMIT" do
    interface = OpenCog::QueryLanguage.create_interface(pets)
    names(interface.query("SELECT DISTINCT $who WHERE { $who likes $what }"), "who").should eq(["Cat", "Dog"])
    interface.query("SELECT $who WHERE { $who likes $what } LIMIT 2").size.should eq(2)
    interface.query("SELECT * WHERE { $who likes $what } LIMIT 0").should be_empty
  end

  it "keeps a result whose OPTIONAL part does not match" do
    interface = OpenCog::QueryLanguage.create_interface(pets)
    results = interface.query("SELECT $x $what WHERE { $x ISA Animal . OPTIONAL { $x likes $what } }")
    pairs = results.map { |result| {result.bindings["x"].name, result.bindings["what"]?.try(&.name)} }.sort_by { |pair| {pair[0], pair[1] || ""} }
    pairs.should eq([{"Blue Whale", nil}, {"Cat", "Fish"}, {"Dog", "Ball"}, {"Dog", "Bone"}])
  end
end

private def graded : AtomSpace::AtomSpace
  space = AtomSpace::AtomSpace.new
  animal = space.add_concept_node("Animal")
  plant = space.add_concept_node("Plant")
  tv = ->(s : Float64, c : Float64) { AtomSpace::SimpleTruthValue.new(s, c) }
  space.add_inheritance_link(space.add_concept_node("Dog"), animal, tv.call(0.95, 0.9))
  space.add_inheritance_link(space.add_concept_node("Cat"), animal, tv.call(0.9, 0.8))
  space.add_inheritance_link(space.add_concept_node("Sponge"), animal, tv.call(0.4, 0.3))
  space.add_inheritance_link(space.add_concept_node("Fern"), plant, tv.call(0.99, 0.9))
  space.add_inheritance_link(space.add_concept_node("Sundew"), plant, tv.call(0.8, 0.5))
  space.add_inheritance_link(space.add_concept_node("Sundew"), animal, tv.call(0.1, 0.5))
  space.add_evaluation_link(space.add_predicate_node("legs"),
    space.add_list_link([space.get_nodes_by_name("Dog").first, space.add_concept_node("4")] of AtomSpace::Atom))
  space.add_evaluation_link(space.get_nodes_by_name("legs").first,
    space.add_list_link([space.get_nodes_by_name("Cat").first, space.get_nodes_by_name("4").first] of AtomSpace::Atom))
  space
end

private def ask(space, text : String)
  OpenCog::QueryLanguage.create_interface(space).query(text)
end

describe "OpenCog query FILTER, UNION and ORDER BY" do
  it "tokenizes comparison operators, parentheses and decimals" do
    tokens = OpenCog::QueryLanguage::QueryLexer.new("FILTER ( STRENGTH($x) >= 0.75 AND $x != 3d-model ) < > = <= -2.5 7").tokens
    tokens.map(&.text).should eq(["FILTER", "(", "STRENGTH", "(", "x", ")", ">=", "0.75", "AND", "x", "!=", "3d-model", ")",
                                  "<", ">", "=", "<=", "-2.5", "7", ""])
    tokens[7].kind.should eq(:number)
    tokens[11].kind.should eq(:name)
    tokens[17].kind.should eq(:number)
    tokens[18].kind.should eq(:integer)
    parse_error("SELECT $x WHERE { $x ISA y . FILTER($x ! y) }").should eq("expected '!=' at line 1, column 40")
  end

  it "filters on names, on truth values of bound atoms and on combinations" do
    space = graded
    names(ask(space, %(SELECT $x WHERE { $x ISA Animal . FILTER($x != Dog) })), "x").should eq(["Cat", "Sponge", "Sundew"])
    names(ask(space, %(SELECT $x WHERE { $x ISA Animal . FILTER(CONTAINS($x, "S")) })), "x").should eq(["Sponge", "Sundew"])
    names(ask(space, %(SELECT $x WHERE { $x ISA Animal . FILTER(NAME($x) < "D") })), "x").should eq(["Cat"])
    names(ask(space, %(SELECT $x WHERE { $x ISA $kind . FILTER(TYPE($kind) = CONCEPT_NODE AND $kind = Plant) })), "x").should eq(["Fern", "Sundew"])
    names(ask(space, %(SELECT $x WHERE { $x ISA Animal . FILTER(NOT ($x = Dog OR $x = Cat)) })), "x").should eq(["Sponge", "Sundew"])
    # Two FILTERs both have to hold.
    names(ask(space, %(SELECT $x WHERE { $x ISA Animal . FILTER($x != Dog) . FILTER($x != Cat) })), "x").should eq(["Sponge", "Sundew"])
    # A number compares as a number, also against a node named like one.
    names(ask(space, %(SELECT $x WHERE { $x legs $n . FILTER($n >= 4) })), "x").should eq(["Cat", "Dog"])
    names(ask(space, %(SELECT $x WHERE { $x legs $n . FILTER($n > 4.5) })), "x").should be_empty
    # Text against a number is never equal.
    names(ask(space, %(SELECT $x WHERE { $x ISA Animal . FILTER($x = 4) })), "x").should be_empty
    names(ask(space, %(SELECT $x WHERE { $x ISA Animal . FILTER($x != 4) })), "x").size.should eq(4)
  end

  it "uses BOUND with OPTIONAL" do
    space = graded
    names(ask(space, %(SELECT $x WHERE { $x ISA Animal . OPTIONAL { $x legs $n } . FILTER(NOT BOUND($n)) })), "x").should eq(["Sponge", "Sundew"])
    names(ask(space, %(SELECT $x WHERE { $x ISA Animal . OPTIONAL { $x legs $n } . FILTER(BOUND($n)) })), "x").should eq(["Cat", "Dog"])
    # An unbound value makes a comparison false rather than an error.
    names(ask(space, %(SELECT $x WHERE { $x ISA Animal . OPTIONAL { $x legs $n } . FILTER($n = 4) })), "x").should eq(["Cat", "Dog"])
  end

  it "joins the alternatives of a UNION" do
    space = graded
    both = ask(space, %(SELECT $x WHERE { $x ISA Animal } UNION { $x ISA Plant }))
    names(both, "x").should eq(["Cat", "Dog", "Fern", "Sponge", "Sundew", "Sundew"])
    names(ask(space, %(SELECT DISTINCT $x WHERE { $x ISA Animal } UNION { $x ISA Plant })), "x").should eq(["Cat", "Dog", "Fern", "Sponge", "Sundew"])
    # Each alternative keeps its own filters; a variable may be missing from one.
    mixed = ask(space, %(SELECT $x $n WHERE { $x legs $n } UNION { $x ISA Plant . FILTER($x != Fern) }))
    mixed.map { |result| {result.bindings["x"].name, result.bindings["n"]?.try(&.name)} }.sort_by(&.[0]).should eq([
      {"Cat", "4"}, {"Dog", "4"}, {"Sundew", nil},
    ])
    parsed = parse(%(SELECT * WHERE { $a ISA $b } UNION { $c ISA Plant } UNION { $a legs $d }))
    parsed.blocks.size.should eq(3)
    parsed.variables.map(&.name).should eq(["a", "b", "c", "d"])
  end

  it "orders results by one or more keys" do
    space = graded
    ordered = ->(text : String) { ask(space, text).map { |result| result.bindings["x"].name } }
    ordered.call(%(SELECT $x WHERE { $x ISA Animal } ORDER BY $x)).should eq(["Cat", "Dog", "Sponge", "Sundew"])
    ordered.call(%(SELECT $x WHERE { $x ISA Animal } ORDER BY $x DESC LIMIT 2)).should eq(["Sundew", "Sponge"])
    # The kind first, then the name backwards within a kind.
    ordered.call(%(SELECT $x WHERE { $x ISA $kind } ORDER BY $kind ASC, $x DESC)).should eq(
      ["Sundew", "Sponge", "Dog", "Cat", "Sundew", "Fern"])
    # Unbound values sort last.
    ordered.call(%(SELECT $x WHERE { $x ISA Animal . OPTIONAL { $x legs $n } } ORDER BY $n, $x)).should eq(
      ["Cat", "Dog", "Sponge", "Sundew"])
    # A key need not be selected.
    ask(space, %(SELECT $x WHERE { $x ISA $kind } ORDER BY $kind DESC, $x LIMIT 1)).first.bindings.keys.should eq(["x"])
  end

  it "keeps filter and order words usable as names" do
    space = AtomSpace::AtomSpace.new
    order = space.add_concept_node("order")
    %w(filter union by not).each { |name| space.add_inheritance_link(space.add_concept_node(name), order) }
    names(ask(space, %(SELECT $x WHERE { $x ISA order } ORDER BY $x)), "x").should eq(["by", "filter", "not", "union"])
    names(ask(space, %(SELECT $x WHERE { $x ISA order . FILTER($x = filter OR $x = union) })), "x").should eq(["filter", "union"])
    names(ask(space, %(SELECT $x WHERE { filter ISA $x })), "x").should eq(["order"])
  end

  it "reports mistakes in filters and ordering" do
    parse_error("SELECT $x WHERE { $x ISA y . FILTER($x) }").should eq(%[expected a comparison such as = or <, found ")" at line 1, column 39])
    parse_error("SELECT $x WHERE { $x ISA y . FILTER($x = ) }").should eq(%[expected a value, found ")" at line 1, column 42])
    parse_error("SELECT $x WHERE { $x ISA y . FILTER($x = y }").should eq(%[expected ')' to close FILTER, found "}" at line 1, column 44])
    parse_error("SELECT $x WHERE { $x ISA y . FILTER(BOUND(y)) }").should eq(%(BOUND takes a variable, found "y" at line 1, column 43))
    parse_error("SELECT $x WHERE { $x ISA y . FILTER(STRENGTH(y) > 1) }").should eq(%(STRENGTH takes a variable, found "y" at line 1, column 46))
    parse_error("SELECT $x WHERE { $x ISA y } ORDER $x").should eq("expected BY after ORDER, found $x at line 1, column 36")
    parse_error("SELECT $x WHERE { $x ISA y } ORDER BY").should eq("expected a value, found the end of the query at line 1, column 38")
    parse_error("SELECT $x WHERE { $x ISA y } UNION $x").should eq("expected '{', found $x at line 1, column 36")
    parse_error("SELECT $x WHERE { $x ISA y } UNION { }").should eq("WHERE needs at least one clause at line 1, column 38")
    parse_error("SELECT $x WHERE { $x ISA y . OPTIONAL { FILTER($x = y) } }").should eq("FILTER belongs to the block around the OPTIONAL at line 1, column 41")
    # A variable used only in a FILTER has no clause to give it a value.
    parse_error("SELECT $z WHERE { $x ISA y . FILTER($z = y) }").should eq("$z is selected but does not appear in WHERE")
  end
end

describe "OpenCog queries and the AtomSpace" do
  it "leaves the AtomSpace as it was" do
    space = graded
    before = space.get_all_atoms.map(&.to_s).sort
    truth = space.get_all_atoms.map { |atom| {atom.truth_value.strength, atom.truth_value.confidence} }
    ask(space, %(SELECT $x WHERE { $x ISA Animal }))
    ask(space, %(SELECT $x $y WHERE { $x legs $y . OPTIONAL { $x ISA $kind } . FILTER($y = 4) } ORDER BY $x))
    ask(space, %(SELECT $x WHERE { $x ISA Unheard } UNION { $x unheard-of Animal }))
    space.get_all_atoms.map(&.to_s).sort.should eq(before)
    space.get_all_atoms.map { |atom| {atom.truth_value.strength, atom.truth_value.confidence} }.should eq(truth)
    space.get_atoms_by_type(AtomSpace::AtomType::VARIABLE_NODE).should be_empty
  end

  it "finds nothing for a name the AtomSpace does not have" do
    names(ask(graded, %(SELECT $x WHERE { $x ISA Mineral })), "x").should be_empty
    names(ask(graded, %(SELECT $x WHERE { $x eats $y })), "x").should be_empty
  end

  it "runs a query built from clause objects" do
    query = OpenCog::QueryLanguage::ParsedQuery.new(
      [OpenCog::QueryLanguage::QueryVariable.new("x")],
      [OpenCog::QueryLanguage::InheritanceClause.new("$x", "Plant").as(OpenCog::QueryLanguage::QueryClause)])
    query.blocks.size.should eq(1)
    query.filters.should be_empty
    results = OpenCog::QueryLanguage::QueryExecutor.new(graded).execute(query)
    names(results, "x").should eq(["Fern", "Sundew"])
  end
end
