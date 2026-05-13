# Link Grammar Parser Integration for CrystalCog
#
# This module provides integration with the Link Grammar Parser,
# a natural language parsing system that creates typed links between words.
#
# References:
# - Link Grammar: https://www.abisource.com/projects/link-grammar/
# - lg-atomese: https://github.com/opencog/lg-atomese

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "./nlp"

module NLP
  module LinkGrammar
    VERSION = "0.1.0"

    # Exception classes
    class LinkGrammarException < NLP::NLPException
    end

    class ParserException < LinkGrammarException
    end

    class DictionaryException < LinkGrammarException
    end

    # Parse result representing a single linkage (parse) of a sentence
    class Linkage
      getter sentence : String
      getter words : Array(String)
      getter links : Array(Link)
      getter disjuncts : Array(Disjunct)
      getter cost : Float64

      def initialize(@sentence : String, @words : Array(String),
                     @links : Array(Link) = [] of Link,
                     @disjuncts : Array(Disjunct) = [] of Disjunct,
                     @cost : Float64 = 0.0)
      end

      # Convert linkage to AtomSpace representation
      def to_atomspace(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
        atoms = [] of AtomSpace::Atom

        # Create word instance nodes for each word
        word_instances = words.map_with_index do |word, idx|
          word_instance = atomspace.add_node(
            AtomSpace::AtomType::WORD_INSTANCE_NODE,
            "#{word}_#{idx}"
          )

          # Link to the word node
          word_node = atomspace.add_node(AtomSpace::AtomType::WORD_NODE, word)
          word_instance_link = atomspace.add_link(
            AtomSpace::AtomType::WORD_INSTANCE_LINK,
            [word_instance, word_node]
          )

          atoms << word_instance
          atoms << word_node
          atoms << word_instance_link
          word_instance
        end

        # Create parse node for this linkage
        parse_node = atomspace.add_node(
          AtomSpace::AtomType::PARSE_NODE,
          "parse_#{sentence.hash}"
        )
        atoms << parse_node

        # Create links between word instances
        links.each do |link|
          if link.left_word < word_instances.size && link.right_word < word_instances.size
            left_word = word_instances[link.left_word]
            right_word = word_instances[link.right_word]

            # Create link node representing the link type
            link_node = atomspace.add_node(
              AtomSpace::AtomType::LG_LINK_NODE,
              link.label
            )
            atoms << link_node

            # Create link instance connecting the words
            link_instance = atomspace.add_link(
              AtomSpace::AtomType::LG_LINK_INSTANCE_LINK,
              [link_node, left_word, right_word]
            )
            atoms << link_instance
          end
        end

        # Create sentence structure
        sentence_link = atomspace.add_link(
          AtomSpace::AtomType::SENTENCE_LINK,
          word_instances
        )
        atoms << sentence_link

        # Associate parse with sentence
        parse_link = atomspace.add_link(
          AtomSpace::AtomType::PARSE_LINK,
          [parse_node, sentence_link]
        )
        atoms << parse_link

        atoms
      end
    end

    # Represents a link between two words in a parse
    struct Link
      getter left_word : Int32
      getter right_word : Int32
      getter label : String
      getter left_connector : String
      getter right_connector : String

      def initialize(@left_word : Int32, @right_word : Int32, @label : String,
                     @left_connector : String = "", @right_connector : String = "")
      end

      def to_s(io : IO)
        io << "#{left_word} -#{label}-> #{right_word}"
      end
    end

    # Represents a disjunct (connector set) used in a parse
    struct Disjunct
      getter word_index : Int32
      getter word : String
      getter connectors : Array(Connector)

      def initialize(@word_index : Int32, @word : String, @connectors : Array(Connector))
      end

      def to_s(io : IO)
        io << "#{word}[#{word_index}]: #{connectors.join(" ")}"
      end
    end

    # Represents a connector in a disjunct
    struct Connector
      getter label : String
      getter direction : String # "+" for right, "-" for left
      getter multi : Bool       # true if multi-connector "@"

      def initialize(@label : String, @direction : String, @multi : Bool = false)
      end

      def to_s(io : IO)
        io << label << direction
        io << "@" if multi
      end
    end

    # Main Link Grammar Parser class
    class Parser
      getter language : String
      getter dictionary_path : String?

      def initialize(@language : String = "en", @dictionary_path : String? = nil)
        CogUtil::Logger.info("Initializing Link Grammar Parser for language: #{@language}")
        # In a full implementation, this would initialize the LG dictionary
      end

      # Parse a sentence and return all possible linkages
      def parse(sentence : String, max_linkages : Int32 = 10) : Array(Linkage)
        CogUtil::Logger.debug("Parsing sentence: #{sentence}")

        # Tokenize the sentence
        words = tokenize_for_parse(sentence)

        if words.empty?
          raise ParserException.new("Empty sentence")
        end

        # For now, return a mock parse result
        # In a full implementation, this would call the Link Grammar C library
        linkages = [] of Linkage

        # Create a simple mock linkage
        links = generate_mock_links(words)
        disjuncts = generate_mock_disjuncts(words)

        linkage = Linkage.new(
          sentence: sentence,
          words: words,
          links: links,
          disjuncts: disjuncts,
          cost: 0.0
        )

        linkages << linkage

        CogUtil::Logger.debug("Generated #{linkages.size} linkage(s)")
        linkages
      end

      # Parse sentence and store result in AtomSpace
      def parse_to_atomspace(sentence : String, atomspace : AtomSpace::AtomSpace,
                             max_linkages : Int32 = 1) : Array(AtomSpace::Atom)
        linkages = parse(sentence, max_linkages)

        all_atoms = [] of AtomSpace::Atom
        linkages.each do |linkage|
          atoms = linkage.to_atomspace(atomspace)
          all_atoms.concat(atoms)
        end

        all_atoms
      end

      # Lookup a word in the dictionary
      def dictionary_lookup(word : String) : Array(Disjunct)
        # In a full implementation, this would query the LG dictionary
        # For now, return mock data
        generate_mock_disjuncts([word])
      end

      private def tokenize_for_parse(sentence : String) : Array(String)
        # Simple tokenization - in practice would use LG's tokenizer
        sentence.gsub(/[.!?]/, "").split(/\s+/).reject(&.empty?)
      end

      private def generate_mock_links(words : Array(String)) : Array(Link)
        links = [] of Link

        # Generate simple left-to-right links
        (0...words.size - 1).each do |i|
          link = Link.new(
            left_word: i,
            right_word: i + 1,
            label: determine_link_type(words[i], words[i + 1]),
            left_connector: "S+",
            right_connector: "S-"
          )
          links << link
        end

        links
      end

      private def generate_mock_disjuncts(words : Array(String)) : Array(Disjunct)
        disjuncts = [] of Disjunct

        words.each_with_index do |word, idx|
          connectors = [] of Connector

          # Add basic connectors based on word position
          if idx == 0
            connectors << Connector.new("S", "+", false)
          elsif idx == words.size - 1
            connectors << Connector.new("S", "-", false)
          else
            connectors << Connector.new("S", "-", false)
            connectors << Connector.new("S", "+", false)
          end

          disjunct = Disjunct.new(idx, word, connectors)
          disjuncts << disjunct
        end

        disjuncts
      end

      private def determine_link_type(word1 : String, word2 : String) : String
        # Simple heuristic for link types
        # In practice, this would come from the LG parser
        articles = ["a", "an", "the"]

        if articles.includes?(word1.downcase)
          "D" # Determiner
        elsif word1.downcase.ends_with?("ly")
          "E" # Adverb
        else
          "S" # Subject-verb or generic
        end
      end
    end

    # Module-level convenience methods
    def self.create_parser(language : String = "en", dictionary_path : String? = nil) : Parser
      Parser.new(language, dictionary_path)
    end

    def self.parse(sentence : String, language : String = "en") : Array(Linkage)
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
