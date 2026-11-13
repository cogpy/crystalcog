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
