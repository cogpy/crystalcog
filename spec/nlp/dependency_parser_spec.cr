require "spec"
require "../../src/nlp/dependency_parser"

describe NLP::DependencyParser do
  describe "RelationType" do
    it "includes common Universal Dependency relations" do
      NLP::DependencyParser::RelationType::NSUBJ.should be_truthy
      NLP::DependencyParser::RelationType::OBJ.should be_truthy
      NLP::DependencyParser::RelationType::DET.should be_truthy
      NLP::DependencyParser::RelationType::ROOT.should be_truthy
      NLP::DependencyParser::RelationType::DEP.should be_truthy
    end
  end

  describe "Dependency struct" do
    it "creates a dependency relation" do
      dep = NLP::DependencyParser::Dependency.new(
        head: 0,
        dependent: 1,
        relation: NLP::DependencyParser::RelationType::NSUBJ,
        head_word: "runs",
        dependent_word: "dog"
      )

      dep.head.should eq(0)
      dep.dependent.should eq(1)
      dep.relation.should eq(NLP::DependencyParser::RelationType::NSUBJ)
      dep.head_word.should eq("runs")
      dep.dependent_word.should eq("dog")
    end

    it "converts to descriptive string" do
      dep = NLP::DependencyParser::Dependency.new(
        head: 0,
        dependent: 1,
        relation: NLP::DependencyParser::RelationType::OBJ,
        head_word: "eats",
        dependent_word: "apple"
      )

      result = dep.to_s
      result.should contain("OBJ")
      result.should contain("eats")
      result.should contain("apple")
    end
  end

  describe "DependencyParse" do
    it "creates a dependency parse" do
      parse = NLP::DependencyParser::DependencyParse.new(
        "The dog runs",
        ["The", "dog", "runs"]
      )

      parse.sentence.should eq("The dog runs")
      parse.words.should eq(["The", "dog", "runs"])
      parse.dependencies.should be_empty
      parse.root_index.should eq(-1)
    end

    it "stores dependencies" do
      dep = NLP::DependencyParser::Dependency.new(
        head: 2,
        dependent: 1,
        relation: NLP::DependencyParser::RelationType::NSUBJ,
        head_word: "runs",
        dependent_word: "dog"
      )

      parse = NLP::DependencyParser::DependencyParse.new(
        "The dog runs",
        ["The", "dog", "runs"],
        [dep],
        2
      )

      parse.dependencies.size.should eq(1)
      parse.root_index.should eq(2)
    end

    describe "get_dependents" do
      it "returns dependents of a word" do
        dep1 = NLP::DependencyParser::Dependency.new(2, 1, NLP::DependencyParser::RelationType::NSUBJ, "runs", "dog")
        dep2 = NLP::DependencyParser::Dependency.new(2, 3, NLP::DependencyParser::RelationType::OBJ, "runs", "ball")

        parse = NLP::DependencyParser::DependencyParse.new(
          "dog runs the ball",
          ["dog", "runs", "the", "ball"],
          [dep1, dep2]
        )

        dependents = parse.get_dependents(2)
        dependents.should contain(1)
        dependents.should contain(3)
      end

      it "returns empty array for a leaf word" do
        dep = NLP::DependencyParser::Dependency.new(1, 0, NLP::DependencyParser::RelationType::NSUBJ, "runs", "dog")
        parse = NLP::DependencyParser::DependencyParse.new(
          "dog runs",
          ["dog", "runs"],
          [dep]
        )

        parse.get_dependents(0).should be_empty
      end
    end

    describe "get_head" do
      it "returns head of a dependent word" do
        dep = NLP::DependencyParser::Dependency.new(1, 0, NLP::DependencyParser::RelationType::NSUBJ, "runs", "dog")
        parse = NLP::DependencyParser::DependencyParse.new(
          "dog runs",
          ["dog", "runs"],
          [dep]
        )

        parse.get_head(0).should eq(1)
      end

      it "returns nil for root word (no head)" do
        dep = NLP::DependencyParser::Dependency.new(1, 0, NLP::DependencyParser::RelationType::NSUBJ, "runs", "dog")
        parse = NLP::DependencyParser::DependencyParse.new(
          "dog runs",
          ["dog", "runs"],
          [dep],
          1
        )

        parse.get_head(1).should be_nil
      end
    end

    describe "get_path" do
      it "returns direct path between connected words" do
        dep = NLP::DependencyParser::Dependency.new(1, 0, NLP::DependencyParser::RelationType::NSUBJ, "runs", "dog")
        parse = NLP::DependencyParser::DependencyParse.new(
          "dog runs",
          ["dog", "runs"],
          [dep]
        )

        path = parse.get_path(0, 1)
        path.should_not be_nil
        path.not_nil!.should contain(0)
      end

      it "returns nil for disconnected words" do
        parse = NLP::DependencyParser::DependencyParse.new(
          "dog runs cat",
          ["dog", "runs", "cat"],
          [] of NLP::DependencyParser::Dependency
        )

        path = parse.get_path(0, 2)
        path.should be_nil
      end

      it "returns empty path from word to itself" do
        parse = NLP::DependencyParser::DependencyParse.new(
          "dog runs",
          ["dog", "runs"],
          [] of NLP::DependencyParser::Dependency
        )

        path = parse.get_path(0, 0)
        path.should_not be_nil
        path.not_nil!.should be_empty
      end
    end

    describe "to_atomspace" do
      it "creates atoms for words and dependencies" do
        dep = NLP::DependencyParser::Dependency.new(1, 0, NLP::DependencyParser::RelationType::NSUBJ, "runs", "dog")
        parse = NLP::DependencyParser::DependencyParse.new(
          "dog runs",
          ["dog", "runs"],
          [dep],
          1
        )

        atomspace = AtomSpace::AtomSpace.new
        atoms = parse.to_atomspace(atomspace)

        atoms.should_not be_empty
        # Should create word instance nodes for each word
        word_instances = atoms.select { |a| a.type == AtomSpace::AtomType::WORD_INSTANCE_NODE }
        word_instances.size.should eq(2)
      end

      it "creates root link when root_index is valid" do
        parse = NLP::DependencyParser::DependencyParse.new(
          "runs",
          ["runs"],
          [] of NLP::DependencyParser::Dependency,
          0
        )

        atomspace = AtomSpace::AtomSpace.new
        atoms = parse.to_atomspace(atomspace)

        eval_links = atoms.select { |a| a.type == AtomSpace::AtomType::EVALUATION_LINK }
        eval_links.should_not be_empty
      end

      it "handles empty dependency list gracefully" do
        parse = NLP::DependencyParser::DependencyParse.new(
          "word",
          ["word"],
          [] of NLP::DependencyParser::Dependency
        )

        atomspace = AtomSpace::AtomSpace.new
        atoms = parse.to_atomspace(atomspace)

        atoms.should_not be_empty
      end
    end
  end

  describe "Parser" do
    describe "initialization" do
      it "creates parser with default English language" do
        parser = NLP::DependencyParser::Parser.new
        parser.language.should eq("en")
      end

      it "creates parser with custom language" do
        parser = NLP::DependencyParser::Parser.new("de")
        parser.language.should eq("de")
      end
    end

    describe "parse" do
      it "parses a simple sentence" do
        parser = NLP::DependencyParser::Parser.new
        result = parser.parse("dog runs")

        result.should be_a(NLP::DependencyParser::DependencyParse)
        result.words.should contain("dog")
        result.words.should contain("runs")
      end

      it "raises exception for empty sentence" do
        parser = NLP::DependencyParser::Parser.new
        expect_raises(NLP::DependencyParser::DependencyParseException) do
          parser.parse("")
        end
      end

      it "creates dependencies for a sentence" do
        parser = NLP::DependencyParser::Parser.new
        result = parser.parse("The dog runs quickly")

        result.should be_a(NLP::DependencyParser::DependencyParse)
        result.words.size.should eq(4)
      end

      it "strips trailing punctuation" do
        parser = NLP::DependencyParser::Parser.new
        result = parser.parse("The dog runs.")

        result.words.should_not contain("runs.")
        result.words.should contain("runs")
      end

      it "has a valid root index" do
        parser = NLP::DependencyParser::Parser.new
        result = parser.parse("The cat sleeps")

        result.root_index.should be >= 0
        result.root_index.should be < result.words.size
      end
    end

    describe "parse_to_atomspace" do
      it "returns atoms for parsed sentence" do
        parser = NLP::DependencyParser::Parser.new
        atomspace = AtomSpace::AtomSpace.new
        atoms = parser.parse_to_atomspace("dog runs", atomspace)

        atoms.should be_a(Array(AtomSpace::Atom))
        atoms.should_not be_empty
      end
    end

    describe "extract_noun_phrases" do
      it "returns an array" do
        parser = NLP::DependencyParser::Parser.new
        result = parser.parse("The big dog runs")
        phrases = parser.extract_noun_phrases(result)

        phrases.should be_a(Array(String))
      end
    end

    describe "extract_verb_phrases" do
      it "returns an array" do
        parser = NLP::DependencyParser::Parser.new
        result = parser.parse("The dog runs quickly")
        phrases = parser.extract_verb_phrases(result)

        phrases.should be_a(Array(String))
      end
    end
  end

  describe "module-level convenience methods" do
    it "parses a sentence via module method" do
      result = NLP::DependencyParser.parse("dog runs")

      result.should be_a(NLP::DependencyParser::DependencyParse)
      result.words.should_not be_empty
    end

    it "parse_to_atomspace returns atoms" do
      atomspace = AtomSpace::AtomSpace.new
      atoms = NLP::DependencyParser.parse_to_atomspace("dog runs", atomspace)

      atoms.should be_a(Array(AtomSpace::Atom))
      atoms.should_not be_empty
    end
  end
end
