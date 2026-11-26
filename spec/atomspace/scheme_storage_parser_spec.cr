require "spec"
require "../../src/atomspace/scheme_storage_parser"

# Direct unit coverage for the FileStorage Scheme parser. FileStorage round-trip
# specs exercise it through persistence; these examples pin the parser's own
# contract on detached atoms, including exact error messages and positions.
private def parse_scheme(source : String, max_nesting = AtomSpace::SchemeStorageParser::MAX_NESTING)
  AtomSpace::SchemeStorageParser.new(source, max_nesting).parse_document
end

private def parse_error(source : String, max_nesting = AtomSpace::SchemeStorageParser::MAX_NESTING) : String
  error = expect_raises(AtomSpace::SchemeStorageParseError) do
    parse_scheme(source, max_nesting)
  end
  error.message.not_nil!
end

describe AtomSpace::SchemeStorageParser do
  describe "documents" do
    it "returns no atoms for empty, blank and comment-only input" do
      parse_scheme("").should be_empty
      parse_scheme(" \n\t ").should be_empty
      parse_scheme("; header only\n;; another\n").should be_empty
    end

    it "parses several top-level atoms in order around comments and whitespace" do
      atoms = parse_scheme(<<-SCHEME)
        ; leading comment
        (ConceptNode "first") ; trailing comment
          (PredicateNode "second")

        (ConceptNode "third")
        SCHEME

      atoms.map(&.name).should eq(["first", "second", "third"])
      atoms.map(&.type).should eq([
        AtomSpace::AtomType::CONCEPT_NODE,
        AtomSpace::AtomType::PREDICATE_NODE,
        AtomSpace::AtomType::CONCEPT_NODE,
      ])
    end

    it "returns detached atoms that belong to no AtomSpace" do
      atoms = parse_scheme(%((ListLink (ConceptNode "a") (ConceptNode "b"))))
      link = atoms.first.as(AtomSpace::Link)
      link.atomspace.should be_nil
      link.outgoing.each(&.atomspace.should(be_nil))
    end
  end

  describe "atom types" do
    it "accepts CamelCase, enum-constant and lowercase type names" do
      ["ConceptNode", "CONCEPT_NODE", "conceptnode"].each do |name|
        atom = parse_scheme(%((#{name} "a"))).first
        atom.type.should eq(AtomSpace::AtomType::CONCEPT_NODE)
        atom.should be_a(AtomSpace::ConceptNode)
      end
    end

    it "restores semantic node subclasses and uses the generic Node otherwise" do
      atoms = parse_scheme(<<-SCHEME)
        (ConceptNode "c")
        (PredicateNode "p")
        (VariableNode "$x")
        (NumberNode "3.5")
        (SchemaNode "s")
        SCHEME

      atoms[0].class.should eq(AtomSpace::ConceptNode)
      atoms[1].class.should eq(AtomSpace::PredicateNode)
      atoms[2].class.should eq(AtomSpace::VariableNode)
      atoms[3].class.should eq(AtomSpace::NumberNode)
      atoms[3].as(AtomSpace::NumberNode).value.should eq(3.5)
      atoms[4].class.should eq(AtomSpace::Node)
      atoms[4].type.should eq(AtomSpace::AtomType::SCHEMA_NODE)
    end

    it "rejects unknown names and base types that are neither nodes nor links" do
      parse_error(%((Bogus "a"))).should eq("unknown atom type 'Bogus' at character 6")
      parse_error(%((ATOM "a"))).should eq("unsupported atom type 'ATOM' at character 5")
    end

    it "rejects NumberNode names that are not finite numbers" do
      parse_error(%((NumberNode "nan"))).should eq("invalid NumberNode value 'nan' at character 18")
      parse_error(%((NumberNode "inf"))).should start_with("invalid NumberNode value 'inf'")
      parse_error(%((NumberNode "seven"))).should start_with("invalid NumberNode value 'seven'")
    end
  end

  describe "links" do
    it "preserves nested outgoing order, including empty links" do
      link = parse_scheme(<<-SCHEME).first.as(AtomSpace::Link)
        (ListLink
          (ConceptNode "a")
          (InheritanceLink (ConceptNode "b") (ConceptNode "c"))
          (ListLink)
          (ConceptNode "a"))
        SCHEME

      link.type.should eq(AtomSpace::AtomType::LIST_LINK)
      link.arity.should eq(4)
      link.outgoing[0].name.should eq("a")
      inner = link.outgoing[1].as(AtomSpace::Link)
      inner.type.should eq(AtomSpace::AtomType::INHERITANCE_LINK)
      inner.outgoing.map(&.name).should eq(["b", "c"])
      link.outgoing[2].as(AtomSpace::Link).arity.should eq(0)
      link.outgoing[3].name.should eq("a")
    end

    it "attaches trailing truth and attention metadata to the link itself" do
      link = parse_scheme(%((ListLink (ConceptNode "a" (tv stv 0.9 0.8)) (tv stv 0.5 0.25) (av -3 7 true)))).first
      link.truth_value.should be_a(AtomSpace::SimpleTruthValue)
      link.truth_value.strength.should eq(0.5)
      link.truth_value.confidence.should eq(0.25)
      attention = link.attention_value.not_nil!
      {attention.sti, attention.lti, attention.vlti}.should eq({-3_i16, 7_i16, true})

      child = link.as(AtomSpace::Link).outgoing.first
      child.truth_value.strength.should eq(0.9)
      child.truth_value.confidence.should eq(0.8)
      child.attention_value.should be_nil
    end

    it "rejects an outgoing atom after link metadata" do
      parse_error(%((ListLink (tv stv 0.5 0.25) (ConceptNode "a"))))
        .should eq("atom follows metadata for LISTLINK at character 28")
    end

    it "rejects bare symbols in link bodies" do
      parse_error("(ListLink x)").should eq("expected nested atom, truth value, or ')' for LISTLINK at character 10")
    end

    it "enforces the configured nesting bound at the first excess level" do
      parse_scheme("(ListLink (ListLink))", 2).size.should eq(1)
      parse_error("(ListLink (ListLink (ListLink)))", 2)
        .should eq("maximum nesting depth of 2 exceeded at character 20")
    end
  end

  describe "truth values" do
    it "defaults to the shared default truth value when none is given" do
      parse_scheme(%((ConceptNode "a"))).first.truth_value.should be(AtomSpace::TruthValue::DEFAULT_TV)
    end

    it "parses every tagged class name and its short aliases" do
      {
        {"SimpleTruthValue", "0.5 0.25", AtomSpace::SimpleTruthValue},
        {"simple", "0.5 0.25", AtomSpace::SimpleTruthValue},
        {"stv", "0.5 0.25", AtomSpace::SimpleTruthValue},
        {"CountTruthValue", "0.5 0.25 9", AtomSpace::CountTruthValue},
        {"count", "0.5 0.25 9", AtomSpace::CountTruthValue},
        {"ctv", "0.5 0.25 9", AtomSpace::CountTruthValue},
        {"IndefiniteTruthValue", "0.1 0.9 0.5", AtomSpace::IndefiniteTruthValue},
        {"indefinite", "0.1 0.9 0.5", AtomSpace::IndefiniteTruthValue},
        {"itv", "0.1 0.9 0.5", AtomSpace::IndefiniteTruthValue},
        {"FuzzyTruthValue", "0.5 0.25 0.1", AtomSpace::FuzzyTruthValue},
        {"fuzzy", "0.5 0.25 0.1", AtomSpace::FuzzyTruthValue},
        {"ftv", "0.5 0.25 0.1", AtomSpace::FuzzyTruthValue},
      }.each do |tag, values, klass|
        parse_scheme(%((ConceptNode "a" (tv #{tag} #{values})))).first.truth_value.class.should eq(klass)
      end
    end

    it "keeps each class's distinct fields" do
      count = parse_scheme(%((ConceptNode "a" (tv ctv 0.5 0.25 9)))).first.truth_value.as(AtomSpace::CountTruthValue)
      {count.strength, count.confidence, count.count}.should eq({0.5, 0.25, 9.0})

      indefinite = parse_scheme(%((ConceptNode "a" (tv itv 0.1 0.9 0.5)))).first.truth_value.as(AtomSpace::IndefiniteTruthValue)
      {indefinite.lower, indefinite.upper, indefinite.confidence}.should eq({0.1, 0.9, 0.5})

      fuzzy = parse_scheme(%((ConceptNode "a" (tv ftv 0.5 0.25 0.1)))).first.truth_value.as(AtomSpace::FuzzyTruthValue)
      {fuzzy.strength, fuzzy.confidence, fuzzy.uncertainty}.should eq({0.5, 0.25, 0.1})
    end

    it "accepts the legacy untagged pair with or without a comma" do
      ["(0.5, 0.25)", "(0.5 0.25)", "( 0.5 ,0.25 )"].each do |pair|
        tv = parse_scheme(%((ConceptNode "a" #{pair}))).first.truth_value
        tv.should be_a(AtomSpace::SimpleTruthValue)
        {tv.strength, tv.confidence}.should eq({0.5, 0.25})
      end
    end

    it "rejects wrong arity, unknown classes, non-finite values and duplicates" do
      parse_error(%((ConceptNode "a" (tv stv 0.5)))).should eq("stv expects 2 values, got 1 at character 29")
      parse_error(%((ConceptNode "a" (tv ctv 0.5 0.25)))).should start_with("ctv expects 3 values, got 2")
      parse_error(%((ConceptNode "a" (tv xtv 1 2)))).should eq("unsupported truth value type 'xtv' at character 29")
      parse_error(%((ConceptNode "a" (tv stv inf 1)))).should eq("invalid numeric value 'inf' at character 28")
      parse_error(%((ConceptNode "a" (tv stv nan 1)))).should start_with("invalid numeric value 'nan'")
      parse_error(%((ConceptNode "a" (tv stv 1 1) (tv stv 1 1))))
        .should eq("multiple truth values for CONCEPTNODE at character 30")
      parse_error(%((ListLink (tv stv 1 1) (0.5 0.5)))).should start_with("multiple truth values for LISTLINK")
    end
  end

  describe "attention values" do
    it "parses signed Int16 bounds and both VLTI values" do
      high = parse_scheme(%((ConceptNode "a" (av 32767 -32768 false)))).first.attention_value.not_nil!
      {high.sti, high.lti, high.vlti}.should eq({32767_i16, -32768_i16, false})
      parse_scheme(%((ConceptNode "a" (av 0 0 true)))).first.attention_value.not_nil!.vlti.should be_true
    end

    it "accepts attention before or after the truth value" do
      [
        %((ConceptNode "a" (av 1 2 true) (tv stv 0.5 0.25))),
        %((ConceptNode "a" (tv stv 0.5 0.25) (av 1 2 true))),
      ].each do |source|
        atom = parse_scheme(source).first
        atom.truth_value.strength.should eq(0.5)
        atom.attention_value.not_nil!.lti.should eq(2_i16)
      end
    end

    it "rejects out-of-range importance, invalid VLTI and duplicates" do
      parse_error(%((ConceptNode "a" (av 40000 2 true)))).should eq("invalid Int16 value at character 26")
      parse_error(%((ConceptNode "a" (av 1.5 2 true)))).should start_with("invalid Int16 value")
      parse_error(%((ConceptNode "a" (av 1 2 maybe)))).should eq("attention VLTI must be true or false at character 30")
      parse_error(%((ConceptNode "a" (av 1 1 true) (av 1 1 true))))
        .should eq("multiple attention values for CONCEPTNODE at character 31")
    end
  end

  describe "node bodies and strings" do
    it "decodes every supported escape" do
      name = parse_scheme(%q[(ConceptNode "q\" s\\ n\n r\r t\t b\b f\f u\u00e9\u4e2d")]).first.name
      name.should eq("q\" s\\ n\n r\r t\t b\b f\f u\u00e9\u4e2d")
    end

    it "keeps semicolons and parentheses inside string literals" do
      parse_scheme(%((ConceptNode "a;b (c)"))).first.name.should eq("a;b (c)")
    end

    it "rejects malformed strings and escapes" do
      parse_error(%((ConceptNode "\\q"))).should eq("unsupported string escape \\q at character 16")
      parse_error(%((ConceptNode "\\ud800"))).should eq("UTF-16 surrogate escapes are not supported at character 20")
      parse_error(%((ConceptNode "\\u12g4"))).should start_with("invalid Unicode escape")
      parse_error(%((ConceptNode "line\nbreak"))).should start_with("unterminated string literal")
      parse_error("(ConceptNode \"a").should eq("unexpected end of input at character 15")
      parse_error("(ConceptNode name)").should eq("expected '\"', got 'n' at character 14")
    end

    it "rejects nested atoms and stray tokens in node bodies" do
      parse_error(%((ConceptNode "a" (ListLink)))).should eq("expected truth or attention value for CONCEPTNODE at character 17")
      parse_error(%((ConceptNode "a" \\q))).should eq("expected ')', got '\\' at character 18")
    end
    it "reports error positions in characters, not bytes, after non-ASCII text" do
      # "é中" is 2 characters but 5 UTF-8 bytes; a byte offset would report 22.
      parse_error(%((ConceptNode "é中" \\q))).should eq("expected ')', got '\\' at character 19")
    end

    it "rejects a missing close parenthesis and trailing non-atom input" do
      parse_error("(ConceptNode \"a\"").should start_with("unexpected end of input")
      parse_error(%((ConceptNode "a") trailing)).should start_with("expected '(', got 't'")
      parse_error("(ConceptNode \"a\"))").should start_with("expected '(', got ')'")
    end
  end
end
