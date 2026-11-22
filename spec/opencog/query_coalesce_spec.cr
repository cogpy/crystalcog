require "spec"
require "../../src/opencog/query_language"

alias CoalesceOQL = OpenCog::QueryLanguage

private def coalesce_shop : AtomSpace::AtomSpace
  space = AtomSpace::AtomSpace.new
  product = space.add_concept_node("Product")
  price = space.add_predicate_node("price")
  {"Apple" => 0.9, "Pear" => 0.8, "Kale" => 0.7}.each do |name, confidence|
    item = space.add_concept_node(name)
    space.add_inheritance_link(item, product, AtomSpace::SimpleTruthValue.new(1.0, confidence))
  end
  {"Apple" => "3", "Pear" => "5"}.each do |name, cost|
    space.add_evaluation_link(price,
      space.add_list_link([space.get_nodes_by_name(name).first, space.add_concept_node(cost)] of AtomSpace::Atom),
      AtomSpace::SimpleTruthValue.new(0.6, 0.2))
  end
  space.add_inheritance_link(space.get_nodes_by_name("3").first, space.add_concept_node("Usable"))
  space
end

private def coalesce_query(space : AtomSpace::AtomSpace, text : String)
  CoalesceOQL.create_interface(space).query(text)
end

private def coalesce_table(results, *columns : String) : Array(Array(String?))
  results.map { |result| columns.map { |column| result.bindings[column]?.try(&.name) }.to_a }
end

# A programmatic operand that fails if a later candidate is evaluated.
class CoalesceUnexpectedArithmetic < CoalesceOQL::QueryArithmetic
  def evaluate(bindings : Hash(String, AtomSpace::Atom)) : String | Float64 | Nil
    raise "COALESCE evaluated an unused candidate"
  end
end

describe "OpenCog query COALESCE" do
  it "parses case-insensitive, nested and multiline operands without reserving the word" do
    parsed = CoalesceOQL::QueryParser.parse("SELECT $cost WHERE { VALUES $x { Apple } . " \
                                            "BIND(coalesce(\n$missing,\nCOALESCE(1 / 0, 2 + 3)) AS $cost) }")
    value = parsed.blocks.first.binds.first.value.as(CoalesceOQL::QueryCoalesce)
    value.arguments.size.should eq(2)
    value.arguments.last.should be_a(CoalesceOQL::QueryCoalesce)
    value.to_s.should eq("COALESCE($missing, COALESCE((1.0 / 0.0), (2.0 + 3.0)))")
    coalesce_table(CoalesceOQL::QueryExecutor.new(coalesce_shop).execute(parsed), "cost").should eq([["5"]])
  end

  it "provides fallbacks after complete OPTIONAL conjunctions without altering row evidence" do
    space = coalesce_shop
    baseline = coalesce_query(space,
      "SELECT $x $p WHERE { $x ISA Product . OPTIONAL { $x price $p . $p ISA Usable } } ORDER BY $x")
    rows = coalesce_query(space,
      "SELECT $x $p $cost WHERE { $x ISA Product . OPTIONAL { $x price $p . $p ISA Usable } . " \
      "BIND(COALESCE($p * 1, 0) AS $cost) } ORDER BY $x")
    coalesce_table(rows, "x", "p", "cost").should eq([["Apple", "3", "3"], ["Kale", nil, "0"], ["Pear", nil, "0"]])
    rows.map(&.confidence).should eq(baseline.map(&.confidence))
    rows.last.confidence.should eq(0.8)
  end

  it "uses fallback values when OPTIONAL-local filters reject enrichment" do
    rows = coalesce_query(coalesce_shop,
      "SELECT $x $cost WHERE { $x ISA Product . OPTIONAL { $x price $p . FILTER($p = 5) } . " \
      "BIND(COALESCE($p * 1, 0) AS $cost) } ORDER BY $x")
    coalesce_table(rows, "x", "cost").should eq([["Apple", "0"], ["Kale", "0"], ["Pear", "5"]])
  end

  it "takes the first available value including zero and empty text" do
    rows = coalesce_query(coalesce_shop,
      "SELECT $zero $empty $first WHERE { VALUES $x { Apple } . " \
      "BIND(COALESCE($missing, 0, 7) AS $zero) . BIND(COALESCE($missing, \"\", backup) AS $empty) . " \
      "BIND(COALESCE(4, 8) AS $first) }")
    coalesce_table(rows, "zero", "empty", "first").should eq([["0", "", "4"]])
    rows.first.bindings["zero"].type.should eq(AtomSpace::AtomType::NUMBER_NODE)
  end

  it "skips invalid arithmetic and supports nested fallback arithmetic" do
    rows = coalesce_query(coalesce_shop,
      "SELECT $cost WHERE { VALUES $x { Apple } . " \
      "BIND(COALESCE($missing, 1 / 0, Apple + 1, COALESCE($other, 2) * 3) + 1 AS $cost) }")
    coalesce_table(rows, "cost").should eq([["7"]])
  end

  it "accepts a single operand and leaves an unavailable result unbound" do
    rows = coalesce_query(coalesce_shop,
      "SELECT $cost $absent WHERE { VALUES $x { Apple } . " \
      "BIND(COALESCE(3) AS $cost) . BIND(COALESCE($missing) AS $absent) }")
    coalesce_table(rows, "cost", "absent").should eq([["3", nil]])
    unavailable = coalesce_query(coalesce_shop,
      "SELECT $cost WHERE { VALUES $x { Apple } . BIND(COALESCE($missing, 1 / 0) AS $cost) }")
    unavailable.first.bindings.should be_empty
    {"=", "!="}.each do |operator|
      coalesce_query(coalesce_shop,
        "SELECT $x WHERE { VALUES $x { Apple } . FILTER(COALESCE($missing, 1 / 0) #{operator} 0) }").should be_empty
    end
  end

  it "short-circuits later operands in both scalar evaluation and BIND" do
    first = CoalesceOQL::QueryValue.new(:number, "4", 4.0)
    unused = CoalesceUnexpectedArithmetic.new(first, '+', first)
    value = CoalesceOQL::QueryCoalesce.new([first.as(CoalesceOQL::QueryOperand), unused.as(CoalesceOQL::QueryOperand)])
    value.evaluate(Hash(String, AtomSpace::Atom).new).should eq(4.0)
    parsed = CoalesceOQL::QueryParser.parse("SELECT $cost WHERE { VALUES $x { Apple } . BIND(1 AS $cost) }")
    parsed.blocks.first.binds.clear
    parsed.blocks.first.binds << CoalesceOQL::QueryBind.new(value, "cost")
    coalesce_table(CoalesceOQL::QueryExecutor.new(coalesce_shop).execute(parsed), "cost").should eq([["4"]])
  end

  it "preserves the selected plain variable atom through BIND, even in nested fallback" do
    space = coalesce_shop
    predicate = space.add_predicate_node("chosen")
    rows = coalesce_query(space,
      "SELECT $same WHERE { VALUES $x { chosen } . BIND(COALESCE($missing, COALESCE($x, backup)) AS $same) }")
    rows.first.bindings["same"].should be(predicate)
    rows.first.bindings["same"].type.should eq(AtomSpace::AtomType::PREDICATE_NODE)
  end

  it "works in outer and OPTIONAL-local FILTERs using their existing scopes" do
    space = coalesce_shop
    rows = coalesce_query(space,
      "SELECT $x WHERE { $x ISA Product . OPTIONAL { $x price $p } . FILTER(COALESCE($p * 1, 0) < 4) } ORDER BY $x")
    coalesce_table(rows, "x").should eq([["Apple"], ["Kale"]])
    rows = coalesce_query(space,
      "SELECT $x $p WHERE { $x ISA Product . OPTIONAL { $x price $p . FILTER(COALESCE($missing, $p * 1) = 3) } } ORDER BY $x")
    coalesce_table(rows, "x", "p").should eq([["Apple", "3"], ["Kale", nil], ["Pear", nil]])
  end

  it "works in sorting, aggregates and HAVING" do
    space = coalesce_shop
    rows = coalesce_query(space,
      "SELECT $x WHERE { $x ISA Product . OPTIONAL { $x price $p } } ORDER BY COALESCE($p * 1, 0) DESC")
    coalesce_table(rows, "x").should eq([["Pear"], ["Apple"], ["Kale"]])
    rows = coalesce_query(space,
      "SELECT SUM(COALESCE($p * 1, 0)) AS $total COUNT(COALESCE($p, backup)) AS $n " \
      "WHERE { $x ISA Product . OPTIONAL { $x price $p } } HAVING(COALESCE($missing, $total) = 8)")
    coalesce_table(rows, "total", "n").should eq([["8", "3"]])
  end

  it "does not introduce variables referenced only by fallback expressions" do
    error = expect_raises(CoalesceOQL::QueryParseException) do
      CoalesceOQL::QueryParser.parse("SELECT $missing WHERE { VALUES $x { Apple } . FILTER(COALESCE($missing, 0) = 0) }")
    end
    error.message.should eq("$missing is selected but does not appear in WHERE")
    parsed = CoalesceOQL::QueryParser.parse("SELECT * WHERE { VALUES $x { Apple } . BIND(COALESCE($missing, 0) AS $cost) }")
    parsed.columns.should eq(["x", "cost"])
  end

  it "retains coalesce as an atom name in terms and bare values" do
    space = AtomSpace::AtomSpace.new
    space.add_inheritance_link(space.add_concept_node("coalesce"), space.add_concept_node("Function"))
    rows = coalesce_query(space,
      "SELECT $x $label WHERE { $x ISA Function . FILTER($x = coalesce) . BIND(coalesce AS $label) }")
    coalesce_table(rows, "x", "label").should eq([["coalesce", "coalesce"]])
    coalesce_table(coalesce_query(space, "SELECT $kind WHERE { coalesce ISA $kind }"), "kind").should eq([["Function"]])
  end

  it "reports empty, malformed and unterminated argument lists with positions" do
    {
      "COALESCE()"             => "COALESCE needs at least one value",
      "COALESCE(1 2)"          => "expected ',' or ')' in COALESCE",
      "COALESCE(1,)"           => "expected a value",
      "COALESCE(,1)"           => "expected a value",
      "COALESCE(1, 2"          => "expected ',' or ')' in COALESCE",
      "COALESCE(1, 2, )"       => "expected a value",
      "COALESCE(1 +, 2)"       => "expected a value",
      "COALESCE(BOUND($x), 0)" => "expected ',' or ')' in COALESCE",
    }.each do |value, message|
      error = expect_raises(CoalesceOQL::QueryParseException) do
        CoalesceOQL::QueryParser.parse("SELECT $cost WHERE { VALUES $x { Apple } . BIND(#{value} AS $cost) }")
      end
      error.message.not_nil!.should contain(message)
      error.message.not_nil!.should contain("line 1, column")
    end
  end

  it "rejects programmatic expressions without arguments" do
    expect_raises(CoalesceOQL::QueryExecutionException, "COALESCE needs at least one value") do
      CoalesceOQL::QueryCoalesce.new([] of CoalesceOQL::QueryOperand)
    end
  end

  it "leaves stored identities, truth values and unknown fallback names unchanged" do
    space = coalesce_shop
    atoms = space.get_all_atoms
    truth = atoms.map { |atom| {atom.truth_value, atom.truth_value.strength, atom.truth_value.confidence} }
    coalesce_query(space,
      "SELECT $x $cost WHERE { $x ISA Product . OPTIONAL { $x price $p } . " \
      "BIND(COALESCE($p, \"unknown fallback\") AS $cost) }")
    space.size.should eq(atoms.size)
    atoms.each_with_index do |atom, i|
      space.get_all_atoms.find! { |stored| stored.handle == atom.handle }.should be(atom)
      atom.truth_value.should be(truth[i][0])
      {atom.truth_value.strength, atom.truth_value.confidence}.should eq({truth[i][1], truth[i][2]})
    end
    space.get_nodes_by_name("unknown fallback").should be_empty
    space.get_atoms_by_type(AtomSpace::AtomType::VARIABLE_NODE).should be_empty
  end
end
