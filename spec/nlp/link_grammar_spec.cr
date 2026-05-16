require "spec"
require "../../src/nlp/nlp"

describe NLP::LinkGrammar do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
    NLP.initialize
  end

  describe "Parser" do
    it "initializes parser for English" do
      parser = NLP::LinkGrammar::Parser.new("en")
      parser.language.should eq("en")
    end

    it "initializes parser with custom dictionary path" do
      parser = NLP::LinkGrammar::Parser.new("en", "/custom/path")
      parser.dictionary_path.should eq("/custom/path")
    end
  end

  describe "parsing sentences" do
    it "parses a simple sentence" do
      parser = NLP::LinkGrammar::Parser.new
      linkages = parser.parse("The cat sits")

      linkages.should be_a(Array(NLP::LinkGrammar::Linkage))
      linkages.size.should be > 0

      linkage = linkages.first
      linkage.sentence.should eq("The cat sits")
      linkage.words.size.should eq(3)
      linkage.words.should eq(["The", "cat", "sits"])
    end

    it "parses a complex sentence" do
      parser = NLP::LinkGrammar::Parser.new
      linkages = parser.parse("The quick brown fox jumps over the lazy dog")

      linkages.size.should be > 0
      linkage = linkages.first
      linkage.words.size.should eq(9)
    end

    it "raises exception for empty sentence" do
      parser = NLP::LinkGrammar::Parser.new

      expect_raises(NLP::LinkGrammar::ParserException) do
        parser.parse("")
      end
    end

    it "handles sentences with punctuation" do
      parser = NLP::LinkGrammar::Parser.new
      linkages = parser.parse("Hello world!")

      linkages.size.should be > 0
      linkage = linkages.first
      linkage.words.should eq(["Hello", "world"])
    end
  end

  describe "Linkage" do
    it "contains words from the sentence" do
      parser = NLP::LinkGrammar::Parser.new
      linkages = parser.parse("Dogs are animals")

      linkage = linkages.first
      linkage.words.should contain("Dogs")
      linkage.words.should contain("are")
      linkage.words.should contain("animals")
    end

    it "contains links between words" do
      parser = NLP::LinkGrammar::Parser.new
      linkages = parser.parse("The cat sits")

      linkage = linkages.first
      linkage.links.should be_a(Array(NLP::LinkGrammar::Link))
      linkage.links.size.should be > 0
    end

    it "contains disjuncts for words" do
      parser = NLP::LinkGrammar::Parser.new
      linkages = parser.parse("The cat sits")

      linkage = linkages.first
      linkage.disjuncts.should be_a(Array(NLP::LinkGrammar::Disjunct))
      linkage.disjuncts.size.should be > 0
    end
  end

  describe "Link" do
    it "represents connection between words" do
      link = NLP::LinkGrammar::Link.new(
        left_word: 0,
        right_word: 1,
        label: "D",
        left_connector: "D+",
        right_connector: "D-"
      )

      link.left_word.should eq(0)
      link.right_word.should eq(1)
      link.label.should eq("D")
    end

    it "converts to string representation" do
      link = NLP::LinkGrammar::Link.new(0, 1, "S")
      link.to_s.should contain("0")
      link.to_s.should contain("1")
      link.to_s.should contain("S")
    end
  end

  describe "Connector" do
    it "represents a connector with direction" do
      connector = NLP::LinkGrammar::Connector.new("S", "+", false)
      connector.label.should eq("S")
      connector.direction.should eq("+")
      connector.multi.should be_false
    end

    it "handles multi-connector" do
      connector = NLP::LinkGrammar::Connector.new("O", "-", true)
      connector.multi.should be_true
      connector.to_s.should contain("@")
    end
  end

  describe "Disjunct" do
    it "represents word with connectors" do
      connectors = [
        NLP::LinkGrammar::Connector.new("S", "-", false),
        NLP::LinkGrammar::Connector.new("O", "+", false),
      ]

      disjunct = NLP::LinkGrammar::Disjunct.new(1, "cat", connectors)
      disjunct.word.should eq("cat")
      disjunct.word_index.should eq(1)
      disjunct.connectors.size.should eq(2)
    end
  end

  describe "AtomSpace integration" do
    it "converts linkage to AtomSpace atoms" do
      atomspace = AtomSpace::AtomSpace.new
      parser = NLP::LinkGrammar::Parser.new

      linkages = parser.parse("The cat sits")
      linkage = linkages.first

      atoms = linkage.to_atomspace(atomspace)
      atoms.should be_a(Array(AtomSpace::Atom))
      atoms.size.should be > 0
    end

    it "creates word instance nodes" do
      atomspace = AtomSpace::AtomSpace.new
      parser = NLP::LinkGrammar::Parser.new

      atoms = parser.parse_to_atomspace("The dog runs", atomspace)

      word_instances = atomspace.get_atoms_by_type(AtomSpace::AtomType::WORD_INSTANCE_NODE)
      word_instances.size.should be >= 3
    end

    it "creates word nodes" do
      atomspace = AtomSpace::AtomSpace.new
      parser = NLP::LinkGrammar::Parser.new

      atoms = parser.parse_to_atomspace("The dog runs", atomspace)

      word_nodes = atomspace.get_atoms_by_type(AtomSpace::AtomType::WORD_NODE)
      word_nodes.size.should be >= 3
    end

    it "creates parse node" do
      atomspace = AtomSpace::AtomSpace.new
      parser = NLP::LinkGrammar::Parser.new

      atoms = parser.parse_to_atomspace("The cat sits", atomspace)

      parse_nodes = atomspace.get_atoms_by_type(AtomSpace::AtomType::PARSE_NODE)
      parse_nodes.size.should be >= 1
    end

    it "creates link nodes for connections" do
      atomspace = AtomSpace::AtomSpace.new
      parser = NLP::LinkGrammar::Parser.new

      atoms = parser.parse_to_atomspace("The cat sits", atomspace)

      link_nodes = atomspace.get_atoms_by_type(AtomSpace::AtomType::LG_LINK_NODE)
      link_nodes.size.should be >= 1
    end

    it "creates sentence link" do
      atomspace = AtomSpace::AtomSpace.new
      parser = NLP::LinkGrammar::Parser.new

      atoms = parser.parse_to_atomspace("The cat sits", atomspace)

      sentence_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::SENTENCE_LINK)
      sentence_links.size.should be >= 1
    end

    it "integrates with existing AtomSpace content" do
      atomspace = AtomSpace::AtomSpace.new

      # Add some existing atoms
      cat = atomspace.add_concept_node("cat")
      animal = atomspace.add_concept_node("animal")
      atomspace.add_inheritance_link(cat, animal)

      initial_size = atomspace.size

      # Parse and add linguistic structure
      parser = NLP::LinkGrammar::Parser.new
      atoms = parser.parse_to_atomspace("The cat sits", atomspace)

      # Should have added new atoms
      atomspace.size.should be > initial_size
      atoms.size.should be > 0

      # Original atoms should still exist
      atomspace.contains?(cat).should be_true
      atomspace.contains?(animal).should be_true
    end
  end

  describe "module-level convenience methods" do
    it "creates parser via module method" do
      parser = NLP::LinkGrammar.create_parser("en")
      parser.should be_a(NLP::LinkGrammar::Parser)
      parser.language.should eq("en")
    end

    it "parses via module method" do
      linkages = NLP::LinkGrammar.parse("The dog runs")
      linkages.should be_a(Array(NLP::LinkGrammar::Linkage))
      linkages.size.should be > 0
    end

    it "parses to atomspace via module method" do
      atomspace = AtomSpace::AtomSpace.new
      atoms = NLP::LinkGrammar.parse_to_atomspace("The cat sits", atomspace)

      atoms.should be_a(Array(AtomSpace::Atom))
      atoms.size.should be > 0
      atomspace.size.should be > 0
    end
  end

  describe "dictionary lookup" do
    it "looks up word in dictionary" do
      parser = NLP::LinkGrammar::Parser.new
      disjuncts = parser.dictionary_lookup("cat")

      disjuncts.should be_a(Array(NLP::LinkGrammar::Disjunct))
      disjuncts.size.should be > 0
    end
  end

  describe "integration with existing NLP module" do
    it "works alongside tokenizer" do
      atomspace = AtomSpace::AtomSpace.new
      text = "The quick brown fox"

      # Use both tokenizer and link-grammar
      tokens = NLP::Tokenizer.tokenize(text)
      lg_atoms = NLP::LinkGrammar.parse_to_atomspace(text, atomspace)

      tokens.size.should eq(4)
      lg_atoms.size.should be > 0
    end

    it "works alongside text processor" do
      atomspace = AtomSpace::AtomSpace.new
      text = "Natural language processing"

      # Use both text processor and link-grammar
      keywords = NLP::TextProcessor.extract_keywords(text, 3)
      lg_atoms = NLP::LinkGrammar.parse_to_atomspace(text, atomspace)

      keywords.size.should be > 0
      lg_atoms.size.should be > 0
    end

    it "enhances linguistic atoms module" do
      atomspace = AtomSpace::AtomSpace.new
      text = "The cat chases the mouse"

      # Use link-grammar to create detailed parse
      lg_atoms = NLP::LinkGrammar.parse_to_atomspace(text, atomspace)

      # Use linguistic atoms to query
      word_atoms = NLP::LinguisticAtoms.get_word_atoms(atomspace)

      lg_atoms.size.should be > 0
      word_atoms.size.should be >= 5 # the, cat, chases, the, mouse
    end
  end
end
