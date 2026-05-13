# Dependency Parser for CrystalCog
#
# This module provides advanced dependency parsing capabilities,
# building upon link grammar to create structured dependency trees
# that represent syntactic relationships between words.
#
# References:
# - Universal Dependencies: https://universaldependencies.org/
# - Stanford Dependencies: https://nlp.stanford.edu/software/dependencies_manual.pdf

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "./link_grammar"

module NLP
  module DependencyParser
    VERSION = "0.1.0"

    # Exception classes
    class DependencyParseException < NLP::NLPException
    end

    # Dependency relation types (Universal Dependencies)
    enum RelationType
      # Core arguments
      NSUBJ # Nominal subject
      OBJ   # Object
      IOBJ  # Indirect object
      CSUBJ # Clausal subject
      CCOMP # Clausal complement
      XCOMP # Open clausal complement

      # Non-core dependents
      OBL        # Oblique nominal
      VOCATIVE   # Vocative
      EXPL       # Expletive
      DISLOCATED # Dislocated elements
      ADVCL      # Adverbial clause modifier
      ADVMOD     # Adverbial modifier
      DISCOURSE  # Discourse element
      AUX        # Auxiliary
      COP        # Copula
      MARK       # Marker

      # Nominal dependents
      NMOD   # Nominal modifier
      APPOS  # Appositional modifier
      NUMMOD # Numeric modifier
      ACL    # Clausal modifier of noun
      AMOD   # Adjectival modifier
      DET    # Determiner
      CLF    # Classifier
      CASE   # Case marking

      # Coordination
      CONJ # Conjunct
      CC   # Coordinating conjunction

      # MWE
      FIXED    # Fixed multiword expression
      FLAT     # Flat multiword expression
      COMPOUND # Compound

      # Loose
      LIST       # List
      PARATAXIS  # Parataxis
      ORPHAN     # Orphan
      GOESWITH   # Goes with
      REPARANDUM # Reparandum

      # Other
      PUNCT # Punctuation
      ROOT  # Root
      DEP   # Unspecified dependency
    end

    # Represents a dependency relation between two words
    struct Dependency
      getter head : Int32      # Index of head word
      getter dependent : Int32 # Index of dependent word
      getter relation : RelationType
      getter head_word : String
      getter dependent_word : String

      def initialize(@head : Int32, @dependent : Int32, @relation : RelationType,
                     @head_word : String, @dependent_word : String)
      end

      def to_s(io : IO)
        io << "#{relation}(#{head_word}-#{head}, #{dependent_word}-#{dependent})"
      end
    end

    # Represents a complete dependency parse of a sentence
    class DependencyParse
      getter sentence : String
      getter words : Array(String)
      getter dependencies : Array(Dependency)
      getter root_index : Int32

      def initialize(@sentence : String, @words : Array(String),
                     @dependencies : Array(Dependency) = [] of Dependency,
                     @root_index : Int32 = -1)
      end

      # Convert to AtomSpace representation
      def to_atomspace(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
        atoms = [] of AtomSpace::Atom

        # Create word instance nodes
        word_instances = words.map_with_index do |word, idx|
          word_instance = atomspace.add_node(
            AtomSpace::AtomType::WORD_INSTANCE_NODE,
            "#{word}_#{idx}"
          )
          atoms << word_instance
          word_instance
        end

        # Create dependency links
        dependencies.each do |dep|
          if dep.head >= 0 && dep.head < word_instances.size &&
             dep.dependent >= 0 && dep.dependent < word_instances.size
            head_word = word_instances[dep.head]
            dep_word = word_instances[dep.dependent]

            # Create dependency relation node
            relation_node = atomspace.add_node(
              AtomSpace::AtomType::CONCEPT_NODE,
              "dep_#{dep.relation.to_s.downcase}"
            )
            atoms << relation_node

            # Create evaluation link for the dependency
            dep_link = atomspace.add_link(
              AtomSpace::AtomType::EVALUATION_LINK,
              [relation_node, atomspace.add_link(
                AtomSpace::AtomType::LIST_LINK,
                [head_word, dep_word]
              )]
            )
            atoms << dep_link
          end
        end

        # Mark root
        if root_index >= 0 && root_index < word_instances.size
          root_node = atomspace.add_node(
            AtomSpace::AtomType::CONCEPT_NODE,
            "sentence_root"
          )
          atoms << root_node

          root_link = atomspace.add_link(
            AtomSpace::AtomType::EVALUATION_LINK,
            [root_node, word_instances[root_index]]
          )
          atoms << root_link
        end

        atoms
      end

      # Get all dependents of a word
      def get_dependents(word_index : Int32) : Array(Int32)
        dependencies
          .select { |dep| dep.head == word_index }
          .map { |dep| dep.dependent }
      end

      # Get the head of a word
      def get_head(word_index : Int32) : Int32?
        dep = dependencies.find { |d| d.dependent == word_index }
        dep ? dep.head : nil
      end

      # Get dependency path between two words
      def get_path(from : Int32, to : Int32) : Array(Int32)?
        visited = Set(Int32).new
        path = [] of Int32

        if find_path(from, to, visited, path)
          path
        else
          nil
        end
      end

      private def find_path(current : Int32, target : Int32,
                            visited : Set(Int32), path : Array(Int32)) : Bool
        return true if current == target
        return false if visited.includes?(current)

        visited.add(current)
        path << current

        # Try head
        if head = get_head(current)
          return true if find_path(head, target, visited, path)
        end

        # Try dependents
        get_dependents(current).each do |dep|
          return true if find_path(dep, target, visited, path)
        end

        path.pop
        false
      end
    end

    # Main dependency parser class
    class Parser
      getter language : String

      def initialize(@language : String = "en")
        CogUtil::Logger.info("Initializing Dependency Parser for language: #{@language}")
      end

      # Parse sentence into dependency structure
      def parse(sentence : String) : DependencyParse
        CogUtil::Logger.debug("Dependency parsing: #{sentence}")

        # Tokenize
        words = tokenize(sentence)

        if words.empty?
          raise DependencyParseException.new("Empty sentence")
        end

        # Convert link grammar parse to dependency parse
        lg_parser = LinkGrammar::Parser.new(@language)
        linkages = lg_parser.parse(sentence)

        if linkages.empty?
          # Fallback to simple linear structure
          return create_simple_parse(sentence, words)
        end

        # Convert first linkage to dependencies
        linkage = linkages.first
        dependencies = convert_linkage_to_dependencies(linkage)
        root_index = find_root(dependencies, words.size)

        DependencyParse.new(sentence, words, dependencies, root_index)
      end

      # Parse and store in AtomSpace
      def parse_to_atomspace(sentence : String,
                             atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
        parse = self.parse(sentence)
        parse.to_atomspace(atomspace)
      end

      # Extract noun phrases from parse
      def extract_noun_phrases(parse : DependencyParse) : Array(String)
        noun_phrases = [] of String

        parse.words.each_with_index do |word, idx|
          # Find nominal heads
          if is_nominal_head?(parse, idx)
            phrase = build_noun_phrase(parse, idx)
            noun_phrases << phrase if phrase
          end
        end

        noun_phrases
      end

      # Extract verb phrases from parse
      def extract_verb_phrases(parse : DependencyParse) : Array(String)
        verb_phrases = [] of String

        parse.words.each_with_index do |word, idx|
          if is_verbal_head?(parse, idx)
            phrase = build_verb_phrase(parse, idx)
            verb_phrases << phrase if phrase
          end
        end

        verb_phrases
      end

      private def tokenize(sentence : String) : Array(String)
        sentence.gsub(/[.!?]/, "").split(/\s+/).reject(&.empty?)
      end

      private def convert_linkage_to_dependencies(linkage : LinkGrammar::Linkage) : Array(Dependency)
        dependencies = [] of Dependency

        linkage.links.each do |link|
          # Map link grammar links to dependency relations
          relation = map_link_to_dependency(link.label)

          dep = Dependency.new(
            head: link.left_word,
            dependent: link.right_word,
            relation: relation,
            head_word: linkage.words[link.left_word],
            dependent_word: linkage.words[link.right_word]
          )
          dependencies << dep
        end

        dependencies
      end

      private def map_link_to_dependency(link_label : String) : RelationType
        # Simple mapping from Link Grammar to Universal Dependencies
        case link_label
        when "S" then RelationType::NSUBJ
        when "O" then RelationType::OBJ
        when "D" then RelationType::DET
        when "A" then RelationType::AMOD
        when "E" then RelationType::ADVMOD
        when "M" then RelationType::NMOD
        when "J" then RelationType::CONJ
        when "C" then RelationType::MARK
        when "I" then RelationType::IOBJ
        when "P" then RelationType::CASE
        else          RelationType::DEP
        end
      end

      private def find_root(dependencies : Array(Dependency), num_words : Int32) : Int32
        # Find word that is not a dependent of any other word
        dependents = dependencies.map(&.dependent).to_set

        (0...num_words).each do |i|
          return i unless dependents.includes?(i)
        end

        0 # Default to first word
      end

      private def create_simple_parse(sentence : String, words : Array(String)) : DependencyParse
        # Create simple linear dependency structure
        dependencies = [] of Dependency

        (1...words.size).each do |i|
          dep = Dependency.new(
            head: i - 1,
            dependent: i,
            relation: RelationType::DEP,
            head_word: words[i - 1],
            dependent_word: words[i]
          )
          dependencies << dep
        end

        DependencyParse.new(sentence, words, dependencies, 0)
      end

      private def is_nominal_head?(parse : DependencyParse, idx : Int32) : Bool
        # Check if word is head of nominal construction
        parse.dependencies.any? do |dep|
          dep.head == idx &&
            [RelationType::DET, RelationType::AMOD, RelationType::NMOD].includes?(dep.relation)
        end
      end

      private def is_verbal_head?(parse : DependencyParse, idx : Int32) : Bool
        # Check if word is head of verbal construction
        parse.dependencies.any? do |dep|
          dep.head == idx &&
            [RelationType::NSUBJ, RelationType::OBJ, RelationType::ADVMOD].includes?(dep.relation)
        end
      end

      private def build_noun_phrase(parse : DependencyParse, head_idx : Int32) : String?
        words = [parse.words[head_idx]]

        # Collect modifiers
        parse.get_dependents(head_idx).each do |dep_idx|
          dep = parse.dependencies.find { |d| d.dependent == dep_idx }
          if dep && [RelationType::DET, RelationType::AMOD].includes?(dep.relation)
            words << parse.words[dep_idx]
          end
        end

        words.join(" ")
      end

      private def build_verb_phrase(parse : DependencyParse, head_idx : Int32) : String?
        words = [parse.words[head_idx]]

        # Collect objects and modifiers
        parse.get_dependents(head_idx).each do |dep_idx|
          dep = parse.dependencies.find { |d| d.dependent == dep_idx }
          if dep && [RelationType::OBJ, RelationType::ADVMOD].includes?(dep.relation)
            words << parse.words[dep_idx]
          end
        end

        words.join(" ")
      end
    end

    # Module-level convenience methods
    def self.parse(sentence : String, language : String = "en") : DependencyParse
      parser = Parser.new(language)
      parser.parse(sentence)
    end

    def self.parse_to_atomspace(sentence : String, atomspace : AtomSpace::AtomSpace,
                                language : String = "en") : Array(AtomSpace::Atom)
      parser = Parser.new(language)
      parser.parse_to_atomspace(sentence, atomspace)
    end
  end
end
