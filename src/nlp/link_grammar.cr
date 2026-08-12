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

    # Built-in English dictionary of connector disjuncts (subset of Link Grammar).
    # Enables real connector-based parsing without requiring the C library.
    class Dictionary
      getter language : String
      getter path : String?

      # word (downcase) => array of alternative connector sequences
      @entries : Hash(String, Array(Array(Connector)))

      ARTICLES     = Set{"a", "an", "the"}
      PRONOUNS     = Set{"i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them"}
      PREPOSITIONS = Set{"in", "on", "at", "to", "for", "with", "by", "from", "of", "over", "under", "about", "into", "onto"}
      AUXILIARIES  = Set{"is", "are", "was", "were", "be", "been", "am", "do", "does", "did", "has", "have", "had", "will", "would", "can", "could", "should", "may", "might"}
      CONJUNCTIONS = Set{"and", "or", "but"}
      ADVERBS_HINT = Set{"very", "really", "always", "never", "here", "there", "now", "then"}

      def initialize(@language : String = "en", @path : String? = nil)
        @entries = Hash(String, Array(Array(Connector))).new
        load_builtin_english if @language == "en"
        if path = @path
          load_from_path(path)
        end
      end

      def lookup(word : String) : Array(Array(Connector))
        key = word.downcase
        return @entries[key] if @entries.has_key?(key)
        infer_disjuncts(word)
      end

      def has_word?(word : String) : Bool
        @entries.has_key?(word.downcase)
      end

      private def load_builtin_english
        # Determiners: D+ links right to a noun
        %w[a an the this that these those].each do |w|
          add(w, [Connector.new("D", "+")])
        end

        # Common adjectives: A+ to noun, optionally A- from prior adj
        %w[quick brown lazy big small happy sad red blue green old young good bad].each do |w|
          add(w, [Connector.new("A", "+")])
          add(w, [Connector.new("A", "-"), Connector.new("A", "+")])
        end

        # Common nouns: D- from determiner, S+ as subject, O- as object, J- from prep
        %w[cat dog fox animal animals dogs cats mat floor room house man woman boy girl
           book table car city world system agent mind memory time day night food water].each do |w|
          add(w, [Connector.new("D", "-"), Connector.new("S", "+")])
          add(w, [Connector.new("D", "-"), Connector.new("O", "-")])
          add(w, [Connector.new("S", "+")])
          add(w, [Connector.new("O", "-")])
          add(w, [Connector.new("J", "-")])
        end

        # Common verbs: S- subject, O+ object, MV+ for modifiers
        %w[sits sat sit runs run ran jumps jump jumped sleeps sleep sleeps
           sees see saw likes like likes eats eat ate goes go went
           makes make made thinks think thought knows know knew].each do |w|
          add(w, [Connector.new("S", "-")])
          add(w, [Connector.new("S", "-"), Connector.new("O", "+")])
          add(w, [Connector.new("S", "-"), Connector.new("MV", "+")])
          add(w, [Connector.new("S", "-"), Connector.new("O", "+"), Connector.new("MV", "+")])
        end

        # Copula / auxiliaries
        AUXILIARIES.each do |w|
          add(w, [Connector.new("S", "-"), Connector.new("P", "+")]) # predicative
          add(w, [Connector.new("S", "-"), Connector.new("O", "+")])
          add(w, [Connector.new("S", "-")])
        end

        # Prepositions: MV- from verb, J+ to noun object of prep
        PREPOSITIONS.each do |w|
          add(w, [Connector.new("MV", "-"), Connector.new("J", "+")])
          add(w, [Connector.new("J", "+")])
        end

        # Pronouns as subjects/objects
        PRONOUNS.each do |w|
          add(w, [Connector.new("S", "+")])
          add(w, [Connector.new("O", "-")])
        end

        # Conjunctions
        CONJUNCTIONS.each do |w|
          add(w, [Connector.new("X", "-"), Connector.new("X", "+")])
        end

        # Adverbs
        %w[quickly slowly very really always never here there now then].each do |w|
          add(w, [Connector.new("E", "+")])
          add(w, [Connector.new("MV", "-")])
        end
      end

      private def add(word : String, connectors : Array(Connector))
        key = word.downcase
        @entries[key] ||= [] of Array(Connector)
        @entries[key] << connectors
      end

      private def infer_disjuncts(word : String) : Array(Array(Connector))
        w = word.downcase
        if ARTICLES.includes?(w)
          [[Connector.new("D", "+")]]
        elsif PREPOSITIONS.includes?(w)
          [[Connector.new("MV", "-"), Connector.new("J", "+")]]
        elsif AUXILIARIES.includes?(w)
          [[Connector.new("S", "-"), Connector.new("O", "+")], [Connector.new("S", "-")]]
        elsif w.ends_with?("ly")
          [[Connector.new("E", "+")], [Connector.new("MV", "-")]]
        elsif w.ends_with?("ing") || w.ends_with?("ed") || w.ends_with?("s")
          # Likely verb forms
          [
            [Connector.new("S", "-")],
            [Connector.new("S", "-"), Connector.new("O", "+")],
            [Connector.new("S", "-"), Connector.new("MV", "+")],
          ]
        elsif w[0]?.try(&.uppercase?) || true
          # Default open-class noun/verb ambiguity
          [
            [Connector.new("D", "-"), Connector.new("S", "+")],
            [Connector.new("D", "-"), Connector.new("O", "-")],
            [Connector.new("S", "+")],
            [Connector.new("O", "-")],
            [Connector.new("S", "-")],
            [Connector.new("S", "-"), Connector.new("O", "+")],
            [Connector.new("J", "-")],
          ]
        else
          [[Connector.new("S", "+")]]
        end
      end

      private def load_from_path(path : String)
        return unless File.exists?(path)
        # Optional simple dictionary format: word: CONN+ CONN- | CONN+
        File.each_line(path) do |line|
          line = line.strip
          next if line.empty? || line.starts_with?("#")
          parts = line.split(":", 2)
          next unless parts.size == 2
          word = parts[0].strip
          parts[1].split("|").each do |alt|
            connectors = alt.strip.split(/\s+/).reject(&.empty?).map do |tok|
              multi = tok.includes?("@")
              tok = tok.gsub("@", "")
              dir = tok.ends_with?("+") ? "+" : tok.ends_with?("-") ? "-" : "+"
              label = tok.rstrip("+-")
              Connector.new(label, dir, multi)
            end
            add(word, connectors) unless connectors.empty?
          end
        end
      rescue ex
        CogUtil::Logger.warn("Failed to load Link Grammar dictionary from #{path}: #{ex.message}")
      end
    end

    # Main Link Grammar Parser class — connector-matching parser
    class Parser
      getter language : String
      getter dictionary_path : String?
      getter dictionary : Dictionary

      def initialize(@language : String = "en", @dictionary_path : String? = nil)
        CogUtil::Logger.info("Initializing Link Grammar Parser for language: #{@language}")
        @dictionary = Dictionary.new(@language, @dictionary_path)
      end

      # Parse a sentence and return all possible linkages via connector matching
      def parse(sentence : String, max_linkages : Int32 = 10) : Array(Linkage)
        CogUtil::Logger.debug("Parsing sentence: #{sentence}")

        words = tokenize_for_parse(sentence)
        raise ParserException.new("Empty sentence") if words.empty?

        word_options = words.map { |w| @dictionary.lookup(w) }
        linkages = [] of Linkage

        # Search disjunct assignments (bounded) and collect valid linkages
        search_linkages(words, word_options, max_linkages) do |chosen_disjuncts, links, cost|
          disjuncts = chosen_disjuncts.map_with_index do |connectors, idx|
            Disjunct.new(idx, words[idx], connectors)
          end
          linkages << Linkage.new(
            sentence: sentence,
            words: words,
            links: links,
            disjuncts: disjuncts,
            cost: cost
          )
        end

        # Always provide at least a best-effort linkage so callers get structure
        if linkages.empty?
          links, disjuncts = greedy_linkage(words)
          linkages << Linkage.new(sentence: sentence, words: words, links: links, disjuncts: disjuncts, cost: 1.0)
        end

        CogUtil::Logger.debug("Generated #{linkages.size} linkage(s)")
        linkages.first(max_linkages)
      end

      def parse_to_atomspace(sentence : String, atomspace : AtomSpace::AtomSpace,
                             max_linkages : Int32 = 1) : Array(AtomSpace::Atom)
        linkages = parse(sentence, max_linkages)
        all_atoms = [] of AtomSpace::Atom
        linkages.each { |linkage| all_atoms.concat(linkage.to_atomspace(atomspace)) }
        all_atoms
      end

      def dictionary_lookup(word : String) : Array(Disjunct)
        @dictionary.lookup(word).map_with_index do |connectors, idx|
          Disjunct.new(idx, word, connectors)
        end
      end

      private def tokenize_for_parse(sentence : String) : Array(String)
        sentence.gsub(/[.!?,;:"]/, "").split(/\s+/).reject(&.empty?)
      end

      # Depth-limited assignment of one disjunct per word; validate connectors form links
      private def search_linkages(words : Array(String),
                                  word_options : Array(Array(Array(Connector))),
                                  max_linkages : Int32,
                                  &block : Array(Array(Connector)), Array(Link), Float64 ->)
        return if words.empty?

        # Cap branching: take top options per word
        capped = word_options.map { |opts| opts.first(4) }
        assignment = Array(Array(Connector)).new(words.size) { [] of Connector }
        count = 0

        search = uninitialized Int32, Float64 -> Nil
        search = ->(idx : Int32, cost : Float64) do
          return if count >= max_linkages
          if idx == words.size
            links = match_connectors(assignment)
            if valid_linkage?(assignment, links)
              count += 1
              block.call(assignment.map(&.dup), links, cost)
            end
            return
          end

          capped[idx].each_with_index do |connectors, opt_i|
            assignment[idx] = connectors
            search.call(idx + 1, cost + opt_i * 0.1)
            break if count >= max_linkages
          end
        end

        search.call(0, 0.0)
      end

      # Match +connectors to -connectors of the same label across word positions
      private def match_connectors(assignment : Array(Array(Connector))) : Array(Link)
        links = [] of Link
        # Collect unused connectors as (word_index, connector)
        rights = [] of Tuple(Int32, Connector) # direction +
        lefts = [] of Tuple(Int32, Connector)  # direction -

        assignment.each_with_index do |connectors, wi|
          connectors.each do |c|
            if c.direction == "+"
              rights << {wi, c}
            else
              lefts << {wi, c}
            end
          end
        end

        used_right = Set(Int32).new
        used_left = Set(Int32).new

        rights.each_with_index do |(r_idx, r_conn), ri|
          lefts.each_with_index do |(l_idx, l_conn), li|
            next if used_right.includes?(ri) || used_left.includes?(li)
            next unless r_conn.label == l_conn.label
            next unless r_idx < l_idx # + must be on the left of -

            links << Link.new(
              left_word: r_idx,
              right_word: l_idx,
              label: r_conn.label,
              left_connector: "#{r_conn.label}+",
              right_connector: "#{l_conn.label}-"
            )
            used_right << ri
            used_left << li
            break
          end
        end

        links
      end

      private def valid_linkage?(assignment : Array(Array(Connector)), links : Array(Link)) : Bool
        return false if assignment.size > 1 && links.empty?

        # Every non-optional connector should be used; require coverage of all words in multi-word sentences
        connected = Set(Int32).new
        links.each do |link|
          connected << link.left_word
          connected << link.right_word
        end

        if assignment.size == 1
          true
        else
          # Prefer fully connected; accept if at least n-1 words participate
          connected.size >= assignment.size - 1 && links.size >= assignment.size - 1
        end
      end

      # Greedy fallback: POS-aware left-to-right links using dictionary labels
      private def greedy_linkage(words : Array(String)) : Tuple(Array(Link), Array(Disjunct))
        links = [] of Link
        disjuncts = [] of Disjunct

        words.each_with_index do |word, idx|
          options = @dictionary.lookup(word)
          connectors = options.first? || [Connector.new("X", idx == words.size - 1 ? "-" : "+")]
          disjuncts << Disjunct.new(idx, word, connectors)
        end

        (0...words.size - 1).each do |i|
          label = determine_link_label(words[i], words[i + 1], i, words)
          links << Link.new(
            left_word: i,
            right_word: i + 1,
            label: label,
            left_connector: "#{label}+",
            right_connector: "#{label}-"
          )
        end

        # Add longer-range subject-verb and verb-object links when detectable
        subject_idx = words.index { |w| !Dictionary::ARTICLES.includes?(w.downcase) && !Dictionary::PREPOSITIONS.includes?(w.downcase) }
        verb_idx = words.each_index.find do |i|
          w = words[i].downcase
          Dictionary::AUXILIARIES.includes?(w) || w.ends_with?("s") || w.ends_with?("ed") || w.ends_with?("ing")
        end
        if subject_idx && verb_idx && subject_idx < verb_idx
          unless links.any? { |l| l.left_word == subject_idx && l.right_word == verb_idx && l.label == "S" }
            links << Link.new(subject_idx, verb_idx, "S", "S+", "S-")
          end
        end

        {links, disjuncts}
      end

      private def determine_link_label(word1 : String, word2 : String, idx : Int32, words : Array(String)) : String
        w1 = word1.downcase
        w2 = word2.downcase
        return "D" if Dictionary::ARTICLES.includes?(w1)
        return "A" if w1.ends_with?("y") && !Dictionary::ADVERBS_HINT.includes?(w1) && idx + 1 < words.size
        return "E" if w1.ends_with?("ly")
        return "J" if Dictionary::PREPOSITIONS.includes?(w1)
        return "S" if idx == 0 || (idx > 0 && Dictionary::ARTICLES.includes?(words[idx - 1]?.try(&.downcase) || ""))
        "W"
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
