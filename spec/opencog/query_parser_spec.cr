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
    parse_error("SELECT $x WHERE { $x - y }").should eq(%[expected a predicate, ISA or '->', found "-" at line 1, column 22])
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
    parse_error("GET $x WHERE { $x }").should eq(%(Query must start with SELECT, ASK or CONSTRUCT, found "GET" at line 1, column 1))
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

private def shop : AtomSpace::AtomSpace
  space = AtomSpace::AtomSpace.new
  price = space.add_predicate_node("price")
  fruit = space.add_concept_node("Fruit")
  vegetable = space.add_concept_node("Vegetable")
  {"apple" => {fruit, "3"}, "pear" => {fruit, "5"}, "plum" => {fruit, "5"},
   "leek" => {vegetable, "2"}, "kale" => {vegetable, nil}}.each do |name, (kind, cost)|
    item = space.add_concept_node(name)
    space.add_inheritance_link(item, kind)
    next unless cost
    space.add_evaluation_link(price, space.add_list_link([item, space.add_concept_node(cost)] of AtomSpace::Atom))
  end
  space
end

# The named values of each result, as text.
private def table(results, *columns : String) : Array(Array(String?))
  results.map { |result| columns.map { |column| result.bindings[column]?.try(&.name) }.to_a }
end

describe "OpenCog query arithmetic" do
  it "reads + - * / and brackets as tokens" do
    tokens = OpenCog::QueryLanguage::QueryLexer.new("($a + 2) * $b / 4 - $c -1 a-b").tokens
    tokens.map(&.text).should eq(["(", "a", "+", "2", ")", "*", "b", "/", "4", "-", "c", "-1", "a-b", ""])
  end

  it "computes with the numbers that names stand for" do
    space = shop
    priced = ->(condition : String) { names(ask(space, "SELECT $x WHERE { $x price $p . FILTER(#{condition}) }"), "x") }
    priced.call("$p * 2 > 8").should eq(["pear", "plum"])
    priced.call("$p + 1 = 4").should eq(["apple"])
    priced.call("$p / 2 = 1").should eq(["leek"])
    priced.call("10 - $p >= 7").should eq(["apple", "leek"])
    # Multiplication binds tighter; brackets override.
    priced.call("$p + 2 * 2 = 7").should eq(["apple"])
    priced.call("($p + 2) * 2 = 14").should eq(["pear", "plum"])
    priced.call("($p - 1) / 2 >= 2").should eq(["pear", "plum"])
    # A sign written against the number is still a subtraction.
    priced.call("$p -1 = 2").should eq(["apple"])
    priced.call("-$p < -4").should eq(["pear", "plum"])
    priced.call("$p * $p = 25 AND $x != plum").should eq(["pear"])
  end

  it "has no value for text or a division by zero" do
    space = shop
    names(ask(space, "SELECT $x WHERE { $x price $p . FILTER($x + 1 > 0) }"), "x").should be_empty
    names(ask(space, "SELECT $x WHERE { $x price $p . FILTER($p / 0 > 0) }"), "x").should be_empty
    names(ask(space, "SELECT $x WHERE { $x price $p . FILTER($p / 0 <= 0) }"), "x").should be_empty
    names(ask(space, "SELECT $x WHERE { $x ISA Vegetable . OPTIONAL { $x price $p } . FILTER($p * 2 = 4) }"), "x").should eq(["leek"])
  end

  it "still reads a bracket as a condition where it is one" do
    space = shop
    names(ask(space, "SELECT $x WHERE { $x price $p . FILTER(($x = apple OR $x = leek) AND $p < 3) }"), "x").should eq(["leek"])
    names(ask(space, "SELECT $x WHERE { $x price $p . FILTER(NOT ($p + 1 > 4)) }"), "x").should eq(["apple", "leek"])
    names(ask(space, "SELECT $x WHERE { $x price $p . FILTER((($p)) = 2) }"), "x").should eq(["leek"])
    parse_error("SELECT $x WHERE { $x ISA $y . FILTER(($x + ) > 2) }").should eq(%[expected a value, found ")" at line 1, column 44])
    parse_error("SELECT $x WHERE { $x ISA $y . FILTER(($x = a OR ) AND $x = b) }").should eq(%[expected a value, found ")" at line 1, column 49])
    parse_error("SELECT $x WHERE { $x ISA $y . FILTER($x * > 2) }").should eq(%[expected a value, found ">" at line 1, column 43])
  end

  it "orders by a computed value" do
    space = shop
    ask(space, "SELECT $x WHERE { $x price $p } ORDER BY $p * -1, $x").map { |result| result.bindings["x"].name }.should eq(
      ["pear", "plum", "apple", "leek"])
    ask(space, "SELECT $x WHERE { $x price $p } ORDER BY 10 - $p DESC, $x DESC").map { |result| result.bindings["x"].name }.should eq(
      ["leek", "apple", "plum", "pear"])
  end
end

describe "OpenCog query OFFSET" do
  it "leaves out results from the front, before LIMIT counts" do
    space = shop
    page = ->(tail : String) { ask(space, "SELECT $x WHERE { $x price $p } ORDER BY $x #{tail}").map { |result| result.bindings["x"].name } }
    page.call("").should eq(["apple", "leek", "pear", "plum"])
    page.call("OFFSET 1").should eq(["leek", "pear", "plum"])
    page.call("LIMIT 2 OFFSET 1").should eq(["leek", "pear"])
    page.call("OFFSET 1 LIMIT 2").should eq(["leek", "pear"])
    page.call("OFFSET 3 LIMIT 5").should eq(["plum"])
    page.call("OFFSET 9").should be_empty
    page.call("offset 0").should eq(["apple", "leek", "pear", "plum"])
  end

  it "counts distinct results" do
    space = shop
    ask(space, "SELECT DISTINCT $p WHERE { $x price $p } ORDER BY $p OFFSET 1").map { |result| result.bindings["p"].name }.should eq(["3", "5"])
  end

  it "does not reserve the word" do
    space = AtomSpace::AtomSpace.new
    space.add_inheritance_link(space.add_concept_node("offset"), space.add_concept_node("group"))
    names(ask(space, "SELECT $x WHERE { $x ISA group }"), "x").should eq(["offset"])
    names(ask(space, "SELECT $x WHERE { offset ISA $x } OFFSET 0"), "x").should eq(["group"])
  end

  it "reports a misplaced LIMIT or OFFSET" do
    parse_error("SELECT $x WHERE { $x ISA $y } LIMIT 2 LIMIT 3").should eq(%[expected the end of the query, found "LIMIT" at line 1, column 39])
    parse_error("SELECT $x WHERE { $x ISA $y } OFFSET many").should eq(%[expected a number after OFFSET, found "many" at line 1, column 38])
  end
end

describe "OpenCog query aggregates" do
  it "counts all matches" do
    space = shop
    table(ask(space, "SELECT COUNT(*) AS $n WHERE { $x ISA Fruit }"), "n").should eq([["3"]])
    # Without AS the result is named after the function.
    table(ask(space, "SELECT COUNT(*) WHERE { $x ISA Vegetable }"), "count").should eq([["2"]])
    # Nothing matched is still one answer.
    table(ask(space, "SELECT COUNT(*) AS $n WHERE { $x ISA Mineral }"), "n").should eq([["0"]])
  end

  it "groups by a variable" do
    space = shop
    table(ask(space, "SELECT $kind COUNT($x) AS $n WHERE { $x ISA $kind } GROUP BY $kind ORDER BY $kind"), "kind", "n").should eq(
      [["Fruit", "3"], ["Vegetable", "2"]])
    # GROUP BY alone gives one result per group.
    table(ask(space, "SELECT $kind WHERE { $x ISA $kind } GROUP BY $kind ORDER BY $kind DESC"), "kind").should eq([["Vegetable"], ["Fruit"]])
    # No group, no answer.
    ask(space, "SELECT $kind COUNT($x) AS $n WHERE { $x ISA $kind . $x price 99 } GROUP BY $kind").should be_empty
  end

  it "sums, averages and finds the smallest and largest" do
    space = shop
    rows = ask(space, "SELECT $kind (SUM($p) AS $total) (AVG($p) AS $mean) (MIN($p) AS $low) (MAX($p) AS $high) " \
                      "WHERE { $x ISA $kind . $x price $p } GROUP BY $kind ORDER BY $kind")
    table(rows, "kind", "total", "low", "high").should eq([["Fruit", "13", "3", "5"], ["Vegetable", "2", "2", "2"]])
    rows.map { |row| row.bindings["mean"].name.to_f }.should eq([13 / 3, 2.0])
    rows.first.bindings.keys.should eq(["kind", "total", "mean", "low", "high"])

    table(ask(space, "SELECT SUM($p * 2) AS $doubled WHERE { $x price $p }"), "doubled").should eq([["30"]])
    table(ask(space, "SELECT AVG($p + 0.5) AS $mean WHERE { $x ISA Vegetable . $x price $p }"), "mean").should eq([["2.5"]])
  end

  it "gives the atom itself as the smallest or largest of a variable" do
    space = shop
    result = ask(space, "SELECT (MIN($x) AS $first) (MAX($x) AS $last) WHERE { $x ISA Fruit }").first
    result.bindings["first"].should be(space.get_nodes_by_name("apple").first)
    result.bindings["last"].should be(space.get_nodes_by_name("plum").first)
    # Prices are names that read as numbers, and compare as numbers.
    space.add_evaluation_link(space.get_nodes_by_name("price").first,
      space.add_list_link([space.get_nodes_by_name("kale").first, space.add_concept_node("10")] of AtomSpace::Atom))
    table(ask(space, "SELECT MAX($p) AS $dearest WHERE { $x price $p }"), "dearest").should eq([["10"]])
  end

  it "counts what is bound, and distinct values once" do
    space = shop
    table(ask(space, "SELECT $kind COUNT($p) AS $priced COUNT(*) AS $all WHERE { $x ISA $kind . OPTIONAL { $x price $p } } " \
                     "GROUP BY $kind ORDER BY $kind"), "kind", "priced", "all").should eq([["Fruit", "3", "3"], ["Vegetable", "1", "2"]])
    table(ask(space, "SELECT COUNT(DISTINCT $p) AS $prices SUM(DISTINCT $p) AS $sum WHERE { $x price $p }"), "prices", "sum").should eq([["3", "10"]])
  end

  it "has no value for the smallest or the average of nothing" do
    space = shop
    result = ask(space, "SELECT (MAX($p) AS $high) (AVG($p) AS $mean) (SUM($p) AS $total) WHERE { $x ISA Mineral . $x price $p }").first
    result.bindings.keys.should eq(["total"])
    result.bindings["total"].name.should eq("0")
  end

  it "filters groups with HAVING and sorts by an aggregate" do
    space = shop
    table(ask(space, "SELECT $kind COUNT($x) AS $n WHERE { $x ISA $kind } GROUP BY $kind HAVING($n > 2)"), "kind", "n").should eq([["Fruit", "3"]])
    table(ask(space, "SELECT $p COUNT($x) AS $n WHERE { $x price $p } GROUP BY $p ORDER BY $n DESC, $p LIMIT 2"), "p", "n").should eq(
      [["5", "2"], ["2", "1"]])
    table(ask(space, "SELECT $kind WHERE { $x ISA $kind . $x price $p } GROUP BY $kind HAVING($kind != Fruit)"), "kind").should eq([["Vegetable"]])
  end

  it "lists results in the order SELECT names them, and leaves the AtomSpace alone" do
    space = shop
    before = space.size
    ask(space, "SELECT (COUNT($x) AS $n) $kind WHERE { $x ISA $kind } GROUP BY $kind").first.bindings.keys.should eq(["n", "kind"])
    space.size.should eq(before)
    space.get_nodes_by_name("3").size.should eq(1)
  end

  it "groups across the alternatives of a UNION" do
    space = shop
    table(ask(space, "SELECT COUNT(DISTINCT $x) AS $n WHERE { $x ISA Fruit } UNION { $x price $p }"), "n").should eq([["4"]])
  end

  it "keeps the function names usable as names" do
    space = AtomSpace::AtomSpace.new
    space.add_inheritance_link(space.add_concept_node("count"), space.add_concept_node("sum"))
    names(ask(space, "SELECT $x WHERE { $x ISA sum }"), "x").should eq(["count"])
    table(ask(space, "SELECT COUNT($x) AS $having WHERE { count ISA $x }"), "having").should eq([["1"]])
  end

  it "reports aggregates it cannot run" do
    parse_error("SELECT $x COUNT($y) AS $n WHERE { $x ISA $y }").should eq("$x is selected beside an aggregate but is not in GROUP BY")
    parse_error("SELECT * WHERE { $x ISA $y } GROUP BY $x").should eq("SELECT * cannot be used with GROUP BY")
    parse_error("SELECT SUM(*) WHERE { $x ISA $y }").should eq("only COUNT takes * at line 1, column 12")
    parse_error("SELECT COUNT($x) WHERE { $x ISA $y } GROUP BY $z").should eq("$z does not appear in WHERE at line 1, column 47")
    parse_error("SELECT $x WHERE { $x ISA $y } GROUP BY x").should eq(%[GROUP BY takes variables, found "x" at line 1, column 40])
    parse_error("SELECT $x WHERE { $x ISA $y } HAVING($x = a)").should eq("HAVING needs GROUP BY or an aggregate")
    parse_error("SELECT (COUNT($x)) WHERE { $x ISA $y }").should eq(%[expected AS and a variable, found ")" at line 1, column 18])
    parse_error("SELECT COUNT($x) AS n WHERE { $x ISA $y }").should eq(%[expected a variable after AS, found "n" at line 1, column 21])
    parse_error("SELECT COUNT($x) AS $n, COUNT(*) AS $n WHERE { $x ISA $y }").should eq("$n is selected twice at line 1, column 25")
  end
end

describe "OpenCog query BIND" do
  it "gives a variable a computed value" do
    space = shop
    table(ask(space, "SELECT $x $double WHERE { $x price $p . BIND($p * 2 AS $double) } ORDER BY $x"), "x", "double").should eq(
      [["apple", "6"], ["leek", "4"], ["pear", "10"], ["plum", "10"]])
    # Text, and the atom itself for a plain variable.
    result = ask(space, %[SELECT $x $label $same WHERE { $x ISA Vegetable . BIND(NAME($x) AS $label) . BIND($x AS $same) } ORDER BY $x]).first
    result.bindings["label"].name.should eq("kale")
    result.bindings["same"].should be(space.get_nodes_by_name("kale").first)
    result.bindings["label"].should_not be(space.get_nodes_by_name("kale").first)
  end

  it "can be filtered, sorted and grouped on" do
    space = shop
    names(ask(space, "SELECT $x WHERE { $x price $p . BIND($p * 2 AS $d) . FILTER($d > 8) }"), "x").should eq(["pear", "plum"])
    # A FILTER written before the BIND still sees it: both belong to the block.
    names(ask(space, "SELECT $x WHERE { $x price $p . FILTER($d < 5) . BIND($p * 2 AS $d) }"), "x").should eq(["leek"])
    ask(space, "SELECT $x WHERE { $x price $p . BIND(10 - $p AS $left) } ORDER BY $left, $x").map { |r| r.bindings["x"].name }.should eq(
      ["pear", "plum", "apple", "leek"])
    table(ask(space, "SELECT $d COUNT($x) AS $n WHERE { $x price $p . BIND($p * 2 AS $d) } GROUP BY $d ORDER BY $d"), "d", "n").should eq(
      [["4", "1"], ["6", "1"], ["10", "2"]])
    table(ask(space, "SELECT DISTINCT $d WHERE { $x price $p . BIND($p * 2 AS $d) } ORDER BY $d"), "d").should eq([["4"], ["6"], ["10"]])
  end

  it "leaves the variable unbound where the value does not exist" do
    space = shop
    rows = ask(space, "SELECT $x $d WHERE { $x ISA Vegetable . OPTIONAL { $x price $p } . BIND($p * 2 AS $d) } ORDER BY $x")
    table(rows, "x", "d").should eq([["kale", nil], ["leek", "4"]])
    names(ask(space, "SELECT $x WHERE { $x ISA Vegetable . OPTIONAL { $x price $p } . BIND($p * 2 AS $d) . FILTER(NOT BOUND($d)) }"), "x").should eq(["kale"])
  end

  it "builds on an earlier BIND and labels the branches of a UNION" do
    space = shop
    table(ask(space, "SELECT $x $q WHERE { $x ISA Vegetable . $x price $p . BIND($p * 2 AS $d) . BIND($d + 1 AS $q) }"), "x", "q").should eq([["leek", "5"]])
    rows = ask(space, %[SELECT $x $kind WHERE { $x ISA Fruit . BIND("sweet" AS $kind) } UNION { $x ISA Vegetable . BIND("green" AS $kind) } ORDER BY $kind, $x])
    table(rows, "x", "kind").should eq([["kale", "green"], ["leek", "green"], ["apple", "sweet"], ["pear", "sweet"], ["plum", "sweet"]])
    table(ask(space, %[SELECT $kind COUNT(*) AS $n WHERE { $x ISA Fruit . BIND("sweet" AS $kind) } UNION { $x ISA Vegetable . BIND("green" AS $kind) } GROUP BY $kind ORDER BY $kind]),
      "kind", "n").should eq([["green", "2"], ["sweet", "3"]])
  end

  it "adds nothing to the AtomSpace and keeps the word usable as a name" do
    space = shop
    before = space.size
    ask(space, %[SELECT $x $d $t WHERE { $x price $p . BIND($p * 7 AS $d) . BIND("a new name" AS $t) }]).size.should eq(4)
    space.size.should eq(before)
    space.get_nodes_by_name("a new name").should be_empty

    other = AtomSpace::AtomSpace.new
    other.add_inheritance_link(other.add_concept_node("bind"), other.add_concept_node("as"))
    names(ask(other, "SELECT $x WHERE { bind ISA $x }"), "x").should eq(["as"])
  end

  it "reports a BIND it cannot make" do
    parse_error("SELECT $x WHERE { $x price $p . BIND($p * 2 AS $p) }").should eq("$p already has a value in this block at line 1, column 48")
    parse_error("SELECT $x WHERE { $x price $p . BIND(1 AS $d) . BIND(2 AS $d) }").should eq("$d already has a value in this block at line 1, column 59")
    parse_error("SELECT $x WHERE { $x price $p . BIND($p * 2) }").should eq(%[expected AS in BIND, found ")" at line 1, column 44])
    parse_error("SELECT $x WHERE { $x price $p . BIND($p AS d) }").should eq(%[expected a variable after AS, found "d" at line 1, column 44])
    parse_error("SELECT $x WHERE { $x price $p . BIND($p AS $d }").should eq(%[expected ')' to close BIND, found "}" at line 1, column 47])
    parse_error("SELECT $x WHERE { $x ISA y . OPTIONAL { $x price $p . BIND($p AS $d) } }").should eq(
      "BIND belongs to the block around the OPTIONAL at line 1, column 55")
  end
end

describe "OpenCog query groups" do
  it "joins a UNION inside a block with the rest of the block" do
    space = shop
    names(ask(space, "SELECT $x WHERE { $x price $p . { $x ISA Fruit . FILTER($x != apple) } UNION { $x ISA Vegetable } }"), "x").should eq(["leek", "pear", "plum"])
    # The outer FILTER applies to every alternative.
    names(ask(space, "SELECT $x WHERE { { $x ISA Fruit } UNION { $x ISA Vegetable } . $x price $p . FILTER($p < 5) }"), "x").should eq(["apple", "leek"])
    # A block may be nothing but a group.
    names(ask(space, "SELECT $x WHERE { { $x ISA Fruit } UNION { $x ISA Vegetable } }"), "x").should eq(["apple", "kale", "leek", "pear", "plum"])
  end

  it "lets a FILTER see only what its own block matches" do
    space = shop
    # $p is matched outside the group, so inside it has no value and the
    # comparison fails for every fruit.
    names(ask(space, "SELECT $x WHERE { $x price $p . { $x ISA Fruit . FILTER($p > 3) } UNION { $x ISA Vegetable } }"), "x").should eq(["leek"])
    names(ask(space, "SELECT $x WHERE { { $x ISA Fruit . $x price $p . FILTER($p > 3) } UNION { $x ISA Vegetable } }"), "x").should eq(["kale", "leek", "pear", "plum"])
    names(ask(space, "SELECT $x WHERE { $x price $p . { $x ISA Fruit } UNION { $x ISA Vegetable } . FILTER($p > 3) }"), "x").should eq(["pear", "plum"])
  end

  it "reads a group without UNION as part of the block" do
    space = shop
    names(ask(space, "SELECT $x WHERE { $x ISA Fruit . { $x price $p . FILTER($p = 5) } }"), "x").should eq(["pear", "plum"])
    names(ask(space, "SELECT $x WHERE { { { $x ISA Fruit } } }"), "x").should eq(["apple", "pear", "plum"])
  end

  it "combines several groups" do
    space = shop
    rows = ask(space, "SELECT $x $y WHERE { { $x ISA Fruit } UNION { $x ISA Vegetable } . { $y price 5 } UNION { $y price 2 } . FILTER($x = kale OR $x = apple) } ORDER BY $x, $y")
    table(rows, "x", "y").should eq([["apple", "leek"], ["apple", "pear"], ["apple", "plum"], ["kale", "leek"], ["kale", "pear"], ["kale", "plum"]])
    # No alternative matches: nothing does.
    ask(space, "SELECT $x WHERE { $x ISA Fruit . { $x price 99 } UNION { $x ISA Mineral } }").should be_empty
  end

  it "takes UNION on a later line and OPTIONAL inside a group" do
    space = shop
    text = "SELECT $x $p WHERE {\n  { $x ISA Vegetable . OPTIONAL { $x price $p } }\n  UNION\n  { $x ISA Fruit . $x price $p . FILTER($p = 3) }\n}\nORDER BY $x"
    table(ask(space, text), "x", "p").should eq([["apple", "3"], ["kale", nil], ["leek", "2"]])
    parsed = parse(text)
    parsed.blocks.size.should eq(1)
    parsed.blocks.first.groups.map(&.size).should eq([2])
    parsed.variables.map(&.name).should eq(["x", "p"])
  end

  it "still joins the top-level alternatives of WHERE" do
    space = shop
    names(ask(space, "SELECT $x WHERE { $x ISA Fruit . { $x price 5 } } UNION { $x ISA Vegetable . { $x price 2 } }"), "x").should eq(["leek", "pear", "plum"])
  end

  it "reports groups it cannot read" do
    parse_error("SELECT $x WHERE { $x ISA y . { } }").should eq(%[WHERE needs at least one clause at line 1, column 32])
    parse_error("SELECT $x WHERE { $x ISA y . { $x ISA z } UNION }").should eq(%[expected '{', found "}" at line 1, column 49])
    parse_error("SELECT $x WHERE { $x ISA y . OPTIONAL { { $x ISA z } } }").should eq("a group cannot be inside OPTIONAL at line 1, column 41")
    parse_error("SELECT $x WHERE { $x ISA y . { $x ISA z }").should eq(%[expected '}' to close the block, found the end of the query at line 1, column 42])
  end
end

describe "OpenCog query MINUS" do
  it "leaves out results that agree with one of the MINUS block" do
    space = shop
    names(ask(space, "SELECT $x WHERE { $x ISA Fruit . MINUS { $x price 5 } }"), "x").should eq(["apple"])
    names(ask(space, "SELECT $x WHERE { $x ISA $kind . MINUS { $x price $p . FILTER($p > 2) } }"), "x").should eq(["kale", "leek"])
    names(ask(space, "SELECT $x WHERE { $x ISA $kind . MINUS { $x ISA Fruit } . MINUS { $x price 2 } }"), "x").should eq(["kale"])
  end

  it "leaves everything in when the MINUS block shares no variable or matches nothing" do
    space = shop
    names(ask(space, "SELECT $x WHERE { $x ISA Fruit . MINUS { $y price 5 } }"), "x").should eq(["apple", "pear", "plum"])
    names(ask(space, "SELECT $x WHERE { $x ISA Fruit . MINUS { $x ISA Mineral } }"), "x").should eq(["apple", "pear", "plum"])
  end

  it "does not offer what the MINUS block matches for selection" do
    parse_error("SELECT $x $p WHERE { $x ISA Fruit . MINUS { $x price $p } }").should eq("$p is selected but does not appear in WHERE")
    parse_error("SELECT $x WHERE { $x ISA Fruit . MINUS { } }").should eq("WHERE needs at least one clause at line 1, column 42")
    parse_error("SELECT $x WHERE { $x ISA y . OPTIONAL { $x ISA z . MINUS { $x ISA w } } }").should eq(
      "MINUS belongs to the block around the OPTIONAL at line 1, column 52")
  end
end

describe "OpenCog query VALUES" do
  it "binds a variable to the values listed" do
    space = shop
    table(ask(space, "SELECT $x $p WHERE { VALUES $x { apple leek nothing } . $x price $p } ORDER BY $x"), "x", "p").should eq(
      [["apple", "3"], ["leek", "2"]])
    # After the clauses works the same.
    names(ask(space, "SELECT $x WHERE { $x ISA Fruit . VALUES $x { pear kale } }"), "x").should eq(["pear"])
  end

  it "can stand alone, and adds nothing to the AtomSpace" do
    space = shop
    before = space.size
    results = ask(space, %[SELECT $x WHERE { VALUES $x { apple "a new thing" 7 } }])
    results.map { |result| result.bindings["x"].name }.should eq(["apple", "a new thing", "7"])
    results.first.bindings["x"].should be(space.get_nodes_by_name("apple").first)
    space.size.should eq(before)
    space.get_nodes_by_name("a new thing").should be_empty
  end

  it "takes rows for several variables, with UNDEF for none" do
    space = shop
    rows = ask(space, "SELECT $x $most WHERE { VALUES ($x $most) { (apple 4) (pear 4) (leek UNDEF) } . $x price $p . " \
                      "FILTER(NOT BOUND($most) OR $p < $most) } ORDER BY $x")
    table(rows, "x", "most").should eq([["apple", "4"], ["leek", nil]])
    parsed = parse("SELECT * WHERE { VALUES ($a $b) {\n (x y)\n (z UNDEF)\n } }")
    parsed.blocks.first.values.first.rows.should eq([["x", "y"], ["z", nil]])
    parsed.variables.map(&.name).should eq(["a", "b"])
  end

  it "keeps the word usable as a name" do
    space = AtomSpace::AtomSpace.new
    space.add_inheritance_link(space.add_concept_node("values"), space.add_concept_node("minus"))
    names(ask(space, "SELECT $x WHERE { values ISA $x }"), "x").should eq(["minus"])
    names(ask(space, "SELECT $x WHERE { $x ISA minus }"), "x").should eq(["values"])
  end

  it "reports VALUES it cannot read" do
    parse_error("SELECT $x WHERE { VALUES ($x $y) { (a) } }").should eq("a row of VALUES needs 2 values, found 1 at line 1, column 36")
    parse_error("SELECT $x WHERE { VALUES ($x $y) { a } }").should eq(%[expected '(' to start a row of VALUES, found "a" at line 1, column 36])
    parse_error("SELECT $x WHERE { VALUES () { } }").should eq("VALUES needs at least one variable at line 1, column 27")
    parse_error("SELECT $x WHERE { VALUES $x { $y } }").should eq("expected a value, found $y at line 1, column 31")
  end
end

describe "OpenCog query subqueries" do
  it "joins what a query inside a block selects with the rest of the block" do
    space = shop
    rows = ask(space, "SELECT $x $n WHERE { $x ISA $kind . { SELECT $kind (COUNT($y) AS $n) WHERE { $y ISA $kind } GROUP BY $kind } } ORDER BY $x")
    table(rows, "x", "n").should eq([["apple", "3"], ["kale", "2"], ["leek", "2"], ["pear", "3"], ["plum", "3"]])
  end

  it "applies the inner ORDER BY and LIMIT before joining" do
    space = shop
    names(ask(space, "SELECT $x WHERE { $x ISA $kind . { SELECT $x WHERE { $x price $p } ORDER BY $p DESC, $x LIMIT 2 } }"), "x").should eq(["pear", "plum"])
    # The dearest of each kind: the inner query finds the price, the outer who has it.
    rows = ask(space, "SELECT $x $top WHERE { $x ISA $kind . $x price $top . " \
                      "{ SELECT $kind (MAX($p) AS $top) WHERE { $y ISA $kind . $y price $p } GROUP BY $kind } } ORDER BY $x")
    table(rows, "x", "top").should eq([["leek", "2"], ["pear", "5"], ["plum", "5"]])
  end

  it "shows outside only what the subquery selects" do
    space = shop
    parse_error("SELECT $x $p WHERE { { SELECT $x WHERE { $x price $p } } }").should eq("$p is selected but does not appear in WHERE")
    names(ask(space, "SELECT $x WHERE {\n  {\n    SELECT $x WHERE { $x price $p . FILTER($p > 2) }\n  }\n}"), "x").should eq(["apple", "pear", "plum"])
    before = space.size
    ask(space, "SELECT $n WHERE { { SELECT (COUNT(*) AS $n) WHERE { $x ISA Fruit } } }").first.bindings["n"].name.should eq("3")
    space.size.should eq(before)
  end

  it "reports a subquery it cannot read" do
    parse_error("SELECT $x WHERE { { SELECT $x WHERE { $x ISA y } LIMIT } }").should eq(%[expected a number after LIMIT, found "}" at line 1, column 56])
    parse_error("SELECT $x WHERE { { SELECT $x WHERE { $x ISA y } nonsense } }").should eq(
      %[expected '}' to close the subquery, found "nonsense" at line 1, column 50])
    parse_error("SELECT $x WHERE { $x ISA y . OPTIONAL { { SELECT $x WHERE { $x ISA z } } } }").should eq(
      "a subquery cannot be inside OPTIONAL at line 1, column 41")
  end
end

# Kinds, parts and a circle of seasons.
#
#   Poodle -> Dog -> Mammal -> Animal        Claw part_of Paw part_of Leg part_of Dog
#   Cat -> Mammal    Trout -> Fish -> Animal Fin part_of Trout
private def anatomy : AtomSpace::AtomSpace
  space = AtomSpace::AtomSpace.new
  kind = ->(child : String, parent : String, strength : Float64, confidence : Float64) do
    space.add_inheritance_link(space.add_concept_node(child), space.add_concept_node(parent),
      AtomSpace::SimpleTruthValue.new(strength, confidence))
  end
  kind.call("Poodle", "Dog", 0.9, 0.9)
  kind.call("Dog", "Mammal", 0.8, 0.8)
  kind.call("Mammal", "Animal", 0.7, 0.6)
  kind.call("Cat", "Mammal", 0.9, 0.9)
  kind.call("Trout", "Fish", 0.9, 0.9)
  kind.call("Fish", "Animal", 0.9, 0.9)

  relate = ->(predicate : String, from : String, to : String) do
    space.add_evaluation_link(space.add_predicate_node(predicate),
      space.add_list_link([space.add_concept_node(from), space.add_concept_node(to)] of AtomSpace::Atom),
      AtomSpace::SimpleTruthValue.new(1.0, 0.5))
  end
  relate.call("part_of", "Claw", "Paw")
  relate.call("part_of", "Paw", "Leg")
  relate.call("part_of", "Leg", "Dog")
  relate.call("part_of", "Fin", "Trout")
  %w(Spring Summer Autumn Winter Spring).each_cons_pair { |from, to| relate.call("precedes", from, to) }
  space
end

private def holds(space, text : String) : Bool
  OpenCog::QueryLanguage.create_interface(space).ask(text)
end

private def construct(space, text : String, into : AtomSpace::AtomSpace? = nil)
  OpenCog::QueryLanguage.create_interface(space).construct(text, into)
end

describe "OpenCog query paths" do
  it "reads + and * after a relation as a path" do
    query = parse("SELECT * WHERE { $x ISA+ Animal . $x ->* $y . $a part_of+ $b . Claw part_of * $w . $x inherits_from + $z }")
    query.clauses.map(&.to_s).should eq([
      "PathClause($x ISA+ Animal)", "PathClause($x ISA* $y)", "PathClause($a part_of+ $b)",
      "PathClause(Claw part_of* $w)", "PathClause($x ISA+ $z)",
    ])
    query.variables.map(&.name).should eq(["x", "y", "a", "b", "w", "z"])
    # A single step is still the clause it was.
    parse("SELECT $x WHERE { $x ISA Animal . $x part_of $y }").clauses.map(&.to_s).should eq([
      "InheritanceClause($x -> Animal)", "TripleClause($x part_of $y)",
    ])
  end

  it "refuses a path over a variable predicate or without an end" do
    parse_error("SELECT $a WHERE { $a $p+ $b }").should eq("a path follows a named predicate, not $p at line 1, column 22")
    parse_error("SELECT $a WHERE { $a part_of+ }").should eq(%(expected the object of the triple, found "}" at line 1, column 31))
    parse_error("SELECT $a WHERE { $a ISA* }").should eq(%(expected a term, found "}" at line 1, column 27))
  end

  it "follows inheritance for one or more steps" do
    space = anatomy
    names(ask(space, "SELECT $x WHERE { $x ISA+ Animal }"), "x").should eq(["Cat", "Dog", "Fish", "Mammal", "Poodle", "Trout"])
    names(ask(space, "SELECT $x WHERE { Poodle ISA+ $x }"), "x").should eq(["Animal", "Dog", "Mammal"])
    names(ask(space, "SELECT $x WHERE { $x ISA Animal }"), "x").should eq(["Fish", "Mammal"])
    names(ask(space, "SELECT $x WHERE { $x ISA+ Poodle }"), "x").should be_empty
  end

  it "lets a * path take no step" do
    space = anatomy
    names(ask(space, "SELECT $x WHERE { Poodle ISA* $x }"), "x").should eq(["Animal", "Dog", "Mammal", "Poodle"])
    names(ask(space, "SELECT $x WHERE { $x ISA* Mammal }"), "x").should eq(["Cat", "Dog", "Mammal", "Poodle"])
    # With both ends open, every atom the relation touches is joined to itself.
    pairs = table(ask(space, "SELECT $a $b WHERE { $a part_of* $b }"), "a", "b")
    pairs.size.should eq(7 + 6)
    pairs.count { |(a, b)| a == b }.should eq(6)
    pairs.should contain(["Dog", "Dog"])
  end

  it "follows a predicate, between any two atoms it joins" do
    space = anatomy
    pairs = table(ask(space, "SELECT $a $b WHERE { $a part_of+ $b }"), "a", "b").map { |(a, b)| "#{a}<#{b}" }.sort
    pairs.should eq(["Claw<Dog", "Claw<Leg", "Claw<Paw", "Fin<Trout", "Leg<Dog", "Paw<Dog", "Paw<Leg"])
    names(ask(space, "SELECT $x WHERE { $x part_of+ Dog }"), "x").should eq(["Claw", "Leg", "Paw"])
    names(ask(space, "SELECT $x WHERE { Paw part_of+ $x }"), "x").should eq(["Dog", "Leg"])
    names(ask(space, "SELECT $x WHERE { $x made_of+ Dog }"), "x").should be_empty
  end

  it "decides a path between two given atoms" do
    space = anatomy
    holds(space, "ASK { Claw part_of+ Dog }").should be_true
    holds(space, "ASK { Dog part_of+ Claw }").should be_false
    holds(space, "ASK { Dog part_of+ Dog }").should be_false
    holds(space, "ASK { Dog part_of* Dog }").should be_true
    holds(space, "ASK { Poodle ISA+ Animal }").should be_true
    holds(space, "ASK { Poodle ISA+ Fish }").should be_false
    # A name the AtomSpace does not know is not even joined to itself.
    holds(space, "ASK { Unicorn ISA* Unicorn }").should be_false
    holds(space, "ASK { Unicorn ISA+ Animal }").should be_false
  end

  it "comes round a circle once" do
    space = anatomy
    names(ask(space, "SELECT $x WHERE { Spring precedes+ $x }"), "x").should eq(["Autumn", "Spring", "Summer", "Winter"])
    names(ask(space, "SELECT $x WHERE { Spring precedes* $x }"), "x").should eq(["Autumn", "Spring", "Summer", "Winter"])
    names(ask(space, "SELECT $x WHERE { $x precedes+ Spring }"), "x").should eq(["Autumn", "Spring", "Summer", "Winter"])
    # The same variable at both ends asks what leads back to itself.
    names(ask(space, "SELECT $x WHERE { $x precedes+ $x }"), "x").should eq(["Autumn", "Spring", "Summer", "Winter"])
    names(ask(space, "SELECT $x WHERE { $x part_of+ $x }"), "x").should be_empty
    ask(space, "SELECT $a $b WHERE { $a precedes+ $b }").size.should eq(16)
  end

  it "takes the links of a shortest chain as what was matched" do
    space = anatomy
    # Poodle -> Dog -> Mammal -> Animal: confidences 0.9, 0.8 and 0.6.
    ask(space, "SELECT $x WHERE { Poodle ISA+ $x . FILTER($x = Animal) }").first.confidence.should be_close(2.3 / 3, 1e-9)
    # A short cut is the chain that counts.
    space.add_inheritance_link(space.get_nodes_by_name("Poodle").first, space.get_nodes_by_name("Mammal").first,
      AtomSpace::SimpleTruthValue.new(0.5, 0.2))
    ask(space, "SELECT $x WHERE { Poodle ISA+ $x . FILTER($x = Animal) }").first.confidence.should be_close(0.4, 1e-9)
    ask(space, "SELECT $x WHERE { $x ISA+ Animal . FILTER($x = Poodle) }").first.confidence.should be_close(0.4, 1e-9)
    # No step, nothing matched.
    ask(space, "SELECT $x WHERE { Animal ISA* $x }").map(&.confidence).should eq([0.0])
  end

  it "joins paths with the rest of the block" do
    space = anatomy
    size = space.size
    rows = table(ask(space, "SELECT $part $whole WHERE { $whole ISA+ Animal . $part part_of+ $whole } ORDER BY $part"), "part", "whole")
    rows.should eq([["Claw", "Dog"], ["Fin", "Trout"], ["Leg", "Dog"], ["Paw", "Dog"]])
    rows = table(ask(space, "SELECT $part $whole WHERE { $part part_of+ $whole . $whole ISA+ Animal } ORDER BY $part"), "part", "whole")
    rows.should eq([["Claw", "Dog"], ["Fin", "Trout"], ["Leg", "Dog"], ["Paw", "Dog"]])

    names(ask(space, "SELECT $x WHERE { $x ISA+ Animal . FILTER($x != Mammal) . MINUS { $x ISA+ Fish } }"), "x").should eq(["Cat", "Dog", "Fish", "Poodle"])
    rows = table(ask(space, "SELECT $x $part WHERE { $x ISA Mammal . OPTIONAL { $part part_of+ $x } } ORDER BY $x, $part"), "x", "part")
    rows.should eq([["Cat", nil], ["Dog", "Claw"], ["Dog", "Leg"], ["Dog", "Paw"]])
    rows = table(ask(space, "SELECT $whole (COUNT($part) AS $n) WHERE { $part part_of+ $whole } GROUP BY $whole ORDER BY $whole"), "whole", "n")
    rows.should eq([["Dog", "3"], ["Leg", "2"], ["Paw", "1"], ["Trout", "1"]])
    space.size.should eq(size)
  end

  it "holds a typed variable to its type" do
    space = anatomy
    names(ask(space, "SELECT $x:CONCEPT WHERE { $x ISA+ Animal }"), "x").size.should eq(6)
    ask(space, "SELECT $x:PREDICATE WHERE { $x ISA+ Animal }").should be_empty
  end
end

describe "OpenCog query ASK" do
  it "parses ASK with or without WHERE" do
    query = parse("ASK { Dog ISA Mammal }")
    query.form.should eq(:ask)
    query.variables.should be_empty
    query.clauses.map(&.to_s).should eq(["InheritanceClause(Dog -> Mammal)"])
    parse("ask where { $x ISA Mammal . $x part_of $y }").form.should eq(:ask)
    parse("ASK\n{ Dog ISA Mammal }\nUNION\n{ Dog ISA Fish }").blocks.size.should eq(2)
    parse("SELECT $x WHERE { $x ISA Mammal }").form.should eq(:select)
    # The word is still a name anywhere else.
    parse("SELECT $x WHERE { $x ISA ask . ask likes $x }").clauses.size.should eq(2)
  end

  it "refuses what an answer of yes or no has no use for" do
    parse_error("ASK { Dog ISA Mammal } LIMIT 1").should eq(%(expected the end of the query, found "LIMIT" at line 1, column 24))
    parse_error("ASK { }").should eq(%(WHERE needs at least one clause at line 1, column 7))
    parse_error("ASK Dog ISA Mammal").should eq(%(Query must start with SELECT, ASK or CONSTRUCT, found "ASK" at line 1, column 1))
    parse_error("SELECT $x WHERE { { ASK { $x ISA Dog } } }").should contain("expected")
  end

  it "says whether anything matches" do
    space = anatomy
    holds(space, "ASK { Dog ISA Mammal }").should be_true
    holds(space, "ASK { Dog ISA Fish }").should be_false
    holds(space, "ASK { $x ISA Mammal . $part part_of $x }").should be_true
    holds(space, "ASK { $x ISA Fish . $part part_of $x . FILTER($part != Fin) }").should be_false
    holds(space, "ASK { Dog ISA Fish } UNION { Trout ISA Fish }").should be_true
    holds(space, "ASK WHERE { Dog ISA Fish } UNION { Trout ISA Mammal }").should be_false
    # Any other query can be asked the same way.
    holds(space, "SELECT $x WHERE { $x ISA Mammal }").should be_true
    holds(space, "SELECT $x WHERE { $x ISA Poodle }").should be_false
  end

  it "answers a plain query call with one empty result or none" do
    space = anatomy
    yes = ask(space, "ASK { $x ISA Mammal }")
    yes.size.should eq(1)
    yes.first.bindings.should be_empty
    # The most confident match speaks for the answer.
    yes.first.confidence.should be_close(0.9, 1e-9)
    ask(space, "ASK { $x ISA Poodle }").should be_empty
  end
end

describe "OpenCog query CONSTRUCT" do
  it "parses a template and the block it is filled from" do
    query = parse("CONSTRUCT { $x ISA Animal . $x seen_with $y\n$y ISA Thing } WHERE { $x ISA+ Animal . $x part_of $y }")
    query.form.should eq(:construct)
    query.template.map(&.to_s).should eq([
      "InheritanceClause($x -> Animal)", "TripleClause($x seen_with $y)", "InheritanceClause($y -> Thing)",
    ])
    query.variables.map(&.name).should eq(["x", "y"])
    query.clauses.size.should eq(2)
    parse("construct\n{ $x ISA Animal }\nwhere { $x ISA Mammal } UNION { $x ISA Fish }").blocks.size.should eq(2)
  end

  it "refuses a template it cannot fill" do
    parse_error("CONSTRUCT { $x ISA $kind } WHERE { $x ISA Mammal }").should eq("$kind is in the template but does not appear in WHERE at line 1, column 20")
    parse_error("CONSTRUCT { $x ISA+ Animal } WHERE { $x ISA Mammal }").should eq("a path cannot be built: the template takes single steps at line 1, column 19")
    parse_error("CONSTRUCT { } WHERE { $x ISA Mammal }").should eq("CONSTRUCT needs at least one clause at line 1, column 13")
    parse_error("CONSTRUCT { $x ISA Animal }").should eq("Missing WHERE clause: expected WHERE, found the end of the query at line 1, column 28")
    parse_error("CONSTRUCT { $x ISA Animal } WHERE { $x ISA Mammal } GROUP BY $x").should eq(%(expected the end of the query, found "GROUP" at line 1, column 53))
    parse_error("CONSTRUCT { FILTER($x = Dog) } WHERE { $x ISA Mammal }").should contain("expected")
  end

  it "builds its template once for each match, beside the AtomSpace" do
    space = anatomy
    size = space.size
    built = construct(space, "CONSTRUCT { $x ISA Animal } WHERE { $x ISA+ Animal }")
    built.map { |atom| atom.outgoing.first.name }.sort.should eq(["Cat", "Dog", "Fish", "Mammal", "Poodle", "Trout"])
    built.all? { |atom| atom.type == AtomSpace::AtomType::INHERITANCE_LINK && atom.outgoing.last.name == "Animal" }.should be_true
    # The nodes are the stored ones; the links are not stored.
    built.all? { |atom| atom.outgoing.all? { |node| space.contains?(node) } }.should be_true
    space.size.should eq(size)

    # As strong as the weakest link of the chain, as confident as the match.
    poodle = built.find! { |atom| atom.outgoing.first.name == "Poodle" }
    poodle.truth_value.strength.should be_close(0.7, 1e-9)
    poodle.truth_value.confidence.should be_close(2.3 / 3, 1e-9)
  end

  it "makes the nodes its template names and builds each atom once" do
    space = anatomy
    built = construct(space, "CONSTRUCT { $part belongs_to $whole . $part ISA Part } WHERE { $part part_of+ $whole }")
    triples = built.select(&.is_a?(AtomSpace::EvaluationLink))
    triples.size.should eq(7)
    triples.all? { |atom| atom.outgoing.first.type == AtomSpace::AtomType::PREDICATE_NODE && atom.outgoing.first.name == "belongs_to" }.should be_true
    triples.map { |atom| atom.outgoing.last.outgoing.map(&.name).join("<") }.sort.first(3).should eq(["Claw<Dog", "Claw<Leg", "Claw<Paw"])
    # Claw matches three times and is a Part once.
    parts = built.select(&.is_a?(AtomSpace::InheritanceLink))
    parts.map { |atom| atom.outgoing.first.name }.sort.should eq(["Claw", "Fin", "Leg", "Paw"])
    space.get_nodes_by_name("Part").should be_empty
    space.get_nodes_by_name("belongs_to").should be_empty
  end

  it "keeps the most confident of the matches that build one atom" do
    space = AtomSpace::AtomSpace.new
    likes = space.add_predicate_node("likes")
    ann = space.add_concept_node("Ann")
    {"tea" => 0.3, "jam" => 0.8, "rye" => 0.5}.each do |name, confidence|
      space.add_evaluation_link(likes, space.add_list_link([ann, space.add_concept_node(name)] of AtomSpace::Atom),
        AtomSpace::SimpleTruthValue.new(confidence, confidence))
    end
    built = construct(space, "CONSTRUCT { $who ISA Fan } WHERE { $who likes $what }")
    built.size.should eq(1)
    built.first.truth_value.strength.should be_close(0.8, 1e-9)
    built.first.truth_value.confidence.should be_close(0.8, 1e-9)
  end

  it "leaves out a clause whose variable a match does not bind" do
    space = anatomy
    built = construct(space, "CONSTRUCT { $x ISA Pet . $part found_on $x } WHERE { $x ISA Mammal . OPTIONAL { $part part_of $x } }")
    built.map { |atom| atom.type.to_s }.sort.should eq(["EVALUATION_LINK", "INHERITANCE_LINK", "INHERITANCE_LINK"])
    built.select(&.is_a?(AtomSpace::InheritanceLink)).map { |atom| atom.outgoing.first.name }.sort.should eq(["Cat", "Dog"])
  end

  it "adds what it builds to the AtomSpace it is given" do
    space = anatomy
    size = space.size
    stored = construct(space, "CONSTRUCT { $x ISA Animal } WHERE { $x ISA+ Animal }", into: space)
    stored.size.should eq(6)
    stored.all? { |atom| space.contains?(atom) }.should be_true
    # Fish and Mammal were Animals already; four links are new.
    space.size.should eq(size + 4)
    names(ask(space, "SELECT $x WHERE { $x ISA Animal }"), "x").should eq(["Cat", "Dog", "Fish", "Mammal", "Poodle", "Trout"])
    # What was there keeps its truth value.
    mammal = stored.find! { |atom| atom.outgoing.first.name == "Mammal" }
    mammal.truth_value.strength.should be_close(0.7, 1e-9)
    mammal.truth_value.confidence.should be_close(0.6, 1e-9)

    # Another AtomSpace gets nodes of its own.
    other = AtomSpace::AtomSpace.new
    copied = construct(space, "CONSTRUCT { $part belongs_to $whole } WHERE { $part part_of $whole }", into: other)
    copied.size.should eq(4)
    other.get_nodes_by_name("Claw").size.should eq(1)
    other.get_nodes_by_name("Claw").first.same?(space.get_nodes_by_name("Claw").first).should be_false
    names(ask(other, "SELECT $x WHERE { $x belongs_to Dog }"), "x").should eq(["Leg"])
    space.get_nodes_by_name("belongs_to").should be_empty
  end

  it "lists its matches when run as a plain query" do
    space = anatomy
    results = ask(space, "CONSTRUCT { $part belongs_to Dog } WHERE { $part part_of+ $whole . FILTER($whole = Dog) }")
    names(results, "part").should eq(["Claw", "Leg", "Paw"])
    results.first.bindings.keys.should eq(["part"])
    executor = OpenCog::QueryLanguage::QueryExecutor.new(space)
    expect_raises(OpenCog::QueryLanguage::QueryExecutionException, "Not a CONSTRUCT query") do
      executor.construct(parse("SELECT $x WHERE { $x ISA Mammal }"))
    end
  end
end

# Places inside places, things in them, and who owns what.
#
#   Lab part_of Wing part_of Hall part_of Campus     Campus has_part Garden
#   Desk, Lamp located_in Lab     Bench located_in Garden     Ann owns Desk
private def campus : AtomSpace::AtomSpace
  space = AtomSpace::AtomSpace.new
  relate = ->(predicate : String, from : String, to : String, confidence : Float64) do
    space.add_evaluation_link(space.add_predicate_node(predicate),
      space.add_list_link([space.add_concept_node(from), space.add_concept_node(to)] of AtomSpace::Atom),
      AtomSpace::SimpleTruthValue.new(1.0, confidence))
  end
  %w(Lab Wing Hall Campus).each_cons_pair { |part, whole| relate.call("part_of", part, whole, 0.9) }
  relate.call("has_part", "Campus", "Garden", 0.9)
  relate.call("located_in", "Desk", "Lab", 0.5)
  relate.call("located_in", "Lamp", "Lab", 0.5)
  relate.call("located_in", "Bench", "Garden", 0.5)
  relate.call("owns", "Ann", "Desk", 0.9)
  furniture = space.add_concept_node("Furniture")
  %w(Desk Bench).each { |name| space.add_inheritance_link(space.get_nodes_by_name(name).first, furniture, AtomSpace::SimpleTruthValue.new(1.0, 0.9)) }
  space
end

describe "OpenCog query path expressions" do
  it "reads ^ | and ? as tokens" do
    tokens = OpenCog::QueryLanguage::QueryLexer.new("$x ^a|(b/c)? $y").tokens
    tokens.map(&.text).should eq(["x", "^", "a", "|", "(", "b", "/", "c", ")", "?", "y", ""])
  end

  it "parses sequences, alternatives, inverses and brackets" do
    shape = ->(path : String) { parse("SELECT * WHERE { $x #{path} $y }").clauses.first.to_s }
    shape.call("a/b").should eq("PathClause($x a/b $y)")
    shape.call("a|b").should eq("PathClause($x a|b $y)")
    shape.call("^a").should eq("PathClause($x ^a $y)")
    shape.call("a?").should eq("PathClause($x a? $y)")
    # A sequence binds tighter than a choice, a mark tighter than either.
    shape.call("a/b|c").should eq("PathClause($x a/b|c $y)")
    shape.call("a/(b|c)").should eq("PathClause($x a/(b|c) $y)")
    shape.call("(a/b)+").should eq("PathClause($x (a/b)+ $y)")
    shape.call("a/b+").should eq("PathClause($x a/b+ $y)")
    shape.call("^(a/b)*").should eq("PathClause($x ^(a/b)* $y)")
    shape.call("a / ISA / ^ -> | inherits_from+").should eq("PathClause($x a/ISA/^ISA|ISA+ $y)")
    shape.call("(a)").should eq("TripleClause($x a $y)")
    shape.call("(ISA)").should eq("InheritanceClause($x -> $y)")
  end

  it "says what is wrong with a path" do
    parse_error("SELECT $x WHERE { $x (a/b $y }").should eq(%[expected ')' to close the path, found $y at line 1, column 27])
    parse_error("SELECT $x WHERE { $x a/ }").should eq(%(expected a predicate, ISA or '->', found "}" at line 1, column 25))
    parse_error("SELECT $x WHERE { $x a/$p $y }").should eq("a path follows a named predicate, not $p at line 1, column 24")
    parse_error("SELECT $x WHERE { $x a|b }").should eq(%(expected the end of the path, found "}" at line 1, column 26))
    parse_error("SELECT $x WHERE { $x $p/a $y }").should eq("a path follows a named predicate, not $p at line 1, column 22")
    parse_error("CONSTRUCT { $x a/b $y } WHERE { $x a $y }").should eq("a path cannot be built: the template takes single steps at line 1, column 17")
    parse_error("CONSTRUCT { $x ^a $y } WHERE { $x a $y }").should eq(%(expected a predicate, ISA or '->', found "^" at line 1, column 16))
    # A misspelt keyword is not taken for the start of a path.
    parse_error("SELECT $x WHERE { $x ISA a . FILTR($x != b) }").should eq(%[expected a predicate, ISA or '->', found "(" at line 1, column 35])
    parse_error("SELECT $x WHERE { $x ^^a $y }").should eq(%(expected a predicate, ISA or '->', found "^" at line 1, column 23))
  end

  it "follows one relation and then another" do
    space = campus
    table(ask(space, "SELECT $x $y WHERE { $x located_in/part_of $y } ORDER BY $x"), "x", "y").should eq([["Desk", "Wing"], ["Lamp", "Wing"]])
    names(ask(space, "SELECT $y WHERE { Desk located_in/part_of+ $y }"), "y").should eq(["Campus", "Hall", "Wing"])
    names(ask(space, "SELECT $y WHERE { Desk located_in/part_of* $y }"), "y").should eq(["Campus", "Hall", "Lab", "Wing"])
    names(ask(space, "SELECT $place WHERE { Ann owns/located_in/part_of* $place }"), "place").should eq(["Campus", "Hall", "Lab", "Wing"])
    names(ask(space, "SELECT $x WHERE { $x located_in/ISA Furniture }"), "x").should be_empty
    names(ask(space, "SELECT $kind WHERE { Ann owns/ISA $kind }"), "kind").should eq(["Furniture"])
  end

  it "takes either of two relations at each step" do
    space = campus
    names(ask(space, "SELECT $x WHERE { $x part_of|located_in Lab }"), "x").should eq(["Desk", "Lamp"])
    names(ask(space, "SELECT $x WHERE { $x (part_of|located_in)+ Campus }"), "x").should eq(["Desk", "Hall", "Lab", "Lamp", "Wing"])
    names(ask(space, "SELECT $x WHERE { Desk located_in|ISA $x }"), "x").should eq(["Furniture", "Lab"])
  end

  it "walks a relation backwards" do
    space = campus
    names(ask(space, "SELECT $x WHERE { Campus ^part_of $x }"), "x").should eq(["Hall"])
    names(ask(space, "SELECT $x WHERE { Campus ^part_of+ $x }"), "x").should eq(["Hall", "Lab", "Wing"])
    # What the campus holds, whichever way round it was said.
    names(ask(space, "SELECT $x WHERE { Campus (^part_of|has_part)+ $x }"), "x").should eq(["Garden", "Hall", "Lab", "Wing"])
    names(ask(space, "SELECT $x WHERE { Wing ^(located_in/part_of) $x }"), "x").should eq(["Desk", "Lamp"])
    names(ask(space, "SELECT $x WHERE { Furniture ^ISA/located_in $x }"), "x").should eq(["Garden", "Lab"])
    # Things in the same place: out by one relation and back by it.
    pairs = table(ask(space, "SELECT $a $b WHERE { $a located_in/^located_in $b . FILTER($a != $b) } ORDER BY $a"), "a", "b")
    pairs.should eq([["Desk", "Lamp"], ["Lamp", "Desk"]])
  end

  it "lets a ? step be left out" do
    space = campus
    names(ask(space, "SELECT $x WHERE { Lab part_of? $x }"), "x").should eq(["Lab", "Wing"])
    names(ask(space, "SELECT $x WHERE { $x located_in/part_of? Lab }"), "x").should eq(["Desk", "Lamp"])
    names(ask(space, "SELECT $x WHERE { $x located_in/part_of? Wing }"), "x").should eq(["Desk", "Lamp"])
    names(ask(space, "SELECT $x WHERE { $x located_in/part_of? Hall }"), "x").should be_empty
  end

  it "repeats a bracketed path as a whole" do
    space = campus
    # Two steps at a time from the lab: itself and the hall, not the wing.
    names(ask(space, "SELECT $x WHERE { Lab (part_of/part_of)* $x }"), "x").should eq(["Hall", "Lab"])
    names(ask(space, "SELECT $x WHERE { Lab (part_of/part_of)+ $x }"), "x").should eq(["Hall"])
    names(ask(space, "SELECT $x WHERE { Wing (part_of/part_of)+ $x }"), "x").should eq(["Campus"])
  end

  it "finds the same pairs from either end" do
    space = campus
    names(ask(space, "SELECT $x WHERE { $x located_in/part_of+ Campus }"), "x").should eq(["Desk", "Lamp"])
    names(ask(space, "SELECT $x WHERE { $x owns/located_in/part_of* Hall }"), "x").should eq(["Ann"])
    names(ask(space, "SELECT $x WHERE { $x (^part_of|has_part)+ Lab }"), "x").should eq(["Campus", "Hall", "Wing"])
    holds(space, "ASK { Ann owns/located_in/part_of+ Campus }").should be_true
    holds(space, "ASK { Ann owns/part_of+ Campus }").should be_false
    holds(space, "ASK { Campus ^part_of+/^located_in/^owns Ann }").should be_true
    # With both ends open every pair comes once.
    pairs = table(ask(space, "SELECT $a $b WHERE { $a located_in/part_of* $b }"), "a", "b").map { |(a, b)| "#{a}>#{b}" }.sort
    pairs.should eq(["Bench>Garden", "Desk>Campus", "Desk>Hall", "Desk>Lab", "Desk>Wing",
                     "Lamp>Campus", "Lamp>Hall", "Lamp>Lab", "Lamp>Wing"])
  end

  it "rests a match on the links of the shortest way" do
    space = campus
    size = space.size
    # located_in at 0.5, then part_of at 0.9.
    ask(space, "SELECT $y WHERE { Desk located_in/part_of $y }").first.confidence.should be_close(0.7, 1e-9)
    ask(space, "SELECT $x WHERE { $x located_in/part_of Wing . FILTER($x = Desk) }").first.confidence.should be_close(0.7, 1e-9)
    ask(space, "SELECT $y WHERE { Desk located_in/part_of+ $y . FILTER($y = Campus) }").first.confidence.should be_close(0.8, 1e-9)
    built = construct(space, "CONSTRUCT { $thing somewhere_in $place } WHERE { $thing located_in/part_of+ $place }")
    built.size.should eq(6)
    space.size.should eq(size)
  end
end

describe "OpenCog query CONSTRUCT with ORDER BY, LIMIT and OFFSET" do
  it "parses the modifiers after the block" do
    query = parse("CONSTRUCT { $x ISA Cheap } WHERE { $x price $p } ORDER BY $p DESC, $x LIMIT 2 OFFSET 1")
    query.form.should eq(:construct)
    query.order.size.should eq(2)
    query.limit.should eq(2)
    query.offset.should eq(1)
    parse("CONSTRUCT { $x ISA Cheap } WHERE { $x price $p } OFFSET 1 LIMIT 2").limit.should eq(2)
  end

  it "builds from the matches the modifiers choose" do
    space = shop
    cheap = ->(tail : String) do
      construct(space, "CONSTRUCT { $x ISA Cheap } WHERE { $x price $p } #{tail}").map { |atom| atom.outgoing.first.name }
    end
    cheap.call("ORDER BY $p LIMIT 2").should eq(["leek", "apple"])
    cheap.call("ORDER BY $p LIMIT 1 OFFSET 1").should eq(["apple"])
    cheap.call("ORDER BY $p DESC, $x DESC LIMIT 1").should eq(["plum"])
    cheap.call("ORDER BY $p OFFSET 2").sort.should eq(["pear", "plum"])
    cheap.call("LIMIT 0").should be_empty
    cheap.call("").size.should eq(4)
  end

  it "takes the most confident matches when no order is asked for" do
    space = graded
    built = construct(space, "CONSTRUCT { $x ISA Sure } WHERE { $x ISA Animal } LIMIT 2")
    built.map { |atom| atom.outgoing.first.name }.should eq(["Dog", "Cat"])
  end
end

describe "OpenCog query negated relations in paths" do
  it "parses ! before one relation or several" do
    shape = ->(path : String) { parse("SELECT * WHERE { $x #{path} $y }").clauses.first.to_s }
    shape.call("!part_of").should eq("PathClause($x !part_of $y)")
    shape.call("!^part_of").should eq("PathClause($x !^part_of $y)")
    shape.call("!(part_of|ISA)").should eq("PathClause($x !(part_of|ISA) $y)")
    shape.call("!(owns|^located_in)").should eq("PathClause($x !(owns|^located_in) $y)")
    shape.call("!->").should eq("PathClause($x !ISA $y)")
    shape.call("!part_of+").should eq("PathClause($x !part_of+ $y)")
    shape.call("owns/!ISA").should eq("PathClause($x owns/!ISA $y)")
    shape.call("^!owns").should eq("PathClause($x ^!owns $y)")
  end

  it "says what is wrong after a !" do
    parse_error("SELECT $x WHERE { $x ! $y }").should eq("a path follows a named predicate, not $y at line 1, column 24")
    parse_error("SELECT $x WHERE { $x !(a|b $y }").should eq(%[expected ')' to close the relations after '!', found $y at line 1, column 28])
    parse_error("SELECT $x WHERE { $x !} }").should eq(%(expected a predicate, ISA or '->' after '!', found "}" at line 1, column 23))
    parse_error("CONSTRUCT { $x !a $y } WHERE { $x a $y }").should eq(%(expected a predicate, ISA or '->', found "!" at line 1, column 16))
    # A ! in a FILTER is still a comparison spelt wrong.
    parse_error("SELECT $x WHERE { $x ISA y . FILTER($x ! y) }").should eq("expected '!=' at line 1, column 40")
  end

  it "takes any relation but those named" do
    space = campus
    # Ann owns the desk; the desk is located in the lab and is furniture.
    names(ask(space, "SELECT $y WHERE { Desk !located_in $y }"), "y").should eq(["Furniture"])
    names(ask(space, "SELECT $y WHERE { Desk !ISA $y }"), "y").should eq(["Lab"])
    names(ask(space, "SELECT $y WHERE { Desk !(ISA|located_in) $y }"), "y").should be_empty
    names(ask(space, "SELECT $y WHERE { Lab !located_in $y }"), "y").should eq(["Wing"])
    # Everything the lab is joined to forwards, whatever by.
    names(ask(space, "SELECT $y WHERE { Lab !nothing_at_all+ $y }"), "y").should eq(["Campus", "Garden", "Hall", "Wing"])
  end

  it "walks backwards over any relation but those named" do
    space = campus
    names(ask(space, "SELECT $x WHERE { Lab !^part_of $x }"), "x").should eq(["Desk", "Lamp"])
    names(ask(space, "SELECT $x WHERE { Desk !^ISA $x }"), "x").should eq(["Ann"])
    # Both ways at once: forwards by anything but ISA, backwards by anything but owns.
    names(ask(space, "SELECT $x WHERE { Desk !(ISA|^owns) $x }"), "x").should eq(["Lab"])
    names(ask(space, "SELECT $x WHERE { Desk !(located_in|^ISA) $x }"), "x").should eq(["Ann", "Furniture"])
  end

  it "joins with named relations in one path" do
    space = campus
    # From Ann by owning, then by anything but furniture's ISA.
    names(ask(space, "SELECT $y WHERE { Ann owns/!ISA $y }"), "y").should eq(["Lab"])
    names(ask(space, "SELECT $y WHERE { Ann owns/!ISA/part_of* $y }"), "y").should eq(["Campus", "Hall", "Lab", "Wing"])
    names(ask(space, "SELECT $x WHERE { $x !ISA/part_of+ Campus }"), "x").should eq(["Desk", "Lab", "Lamp", "Wing"])
    holds(space, "ASK { Bench !located_in Furniture }").should be_true
    holds(space, "ASK { Bench !ISA Furniture }").should be_false
  end
end
