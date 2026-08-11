# Advanced NLP capabilities for CrystalCog
#
# Implements Phase 3 plan items: coreference resolution, NER, word-sense
# disambiguation, multilingual foundations, discourse planning, and
# stylistic adaptation.

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module NLP
  module Advanced
    VERSION = "0.1.0"

    class AdvancedNLPException < NLP::NLPException
    end

    # ---- Named Entity Recognition ----

    enum EntityType
      PERSON
      ORGANIZATION
      LOCATION
      DATE
      MONEY
      MISC
    end

    struct NamedEntity
      getter text : String
      getter entity_type : EntityType
      getter start_offset : Int32
      getter end_offset : Int32
      getter confidence : Float64

      def initialize(@text : String, @entity_type : EntityType,
                     @start_offset : Int32, @end_offset : Int32,
                     @confidence : Float64 = 0.8)
      end
    end

    class NamedEntityRecognizer
      @gazetteer : Hash(String, EntityType)
      @patterns : Array(Tuple(Regex, EntityType))

      def initialize
        @gazetteer = {
          "john"       => EntityType::PERSON,
          "mary"       => EntityType::PERSON,
          "alice"      => EntityType::PERSON,
          "bob"        => EntityType::PERSON,
          "google"     => EntityType::ORGANIZATION,
          "microsoft"  => EntityType::ORGANIZATION,
          "opencog"    => EntityType::ORGANIZATION,
          "london"     => EntityType::LOCATION,
          "paris"      => EntityType::LOCATION,
          "new york"   => EntityType::LOCATION,
          "tokyo"      => EntityType::LOCATION,
          "monday"     => EntityType::DATE,
          "tuesday"    => EntityType::DATE,
          "january"    => EntityType::DATE,
          "february"   => EntityType::DATE,
        } of String => EntityType

        @patterns = [
          {/\b\d{1,2}\/\d{1,2}\/\d{2,4}\b/, EntityType::DATE},
          {/\b(?:19|20)\d{2}\b/, EntityType::DATE},
          {/\$\d+(?:\.\d{2})?/, EntityType::MONEY},
          {/\b\d+(?:\.\d+)?\s*(?:USD|EUR|GBP)\b/i, EntityType::MONEY},
        ]
      end

      def add_entity(name : String, type : EntityType)
        @gazetteer[name.downcase] = type
      end

      def recognize(text : String) : Array(NamedEntity)
        entities = [] of NamedEntity
        lower = text.downcase

        # Multi-word gazetteer first (longest match)
        @gazetteer.keys.sort_by { |k| -k.size }.each do |key|
          idx = 0
          while (pos = lower.index(key, idx))
            # Word boundary-ish check
            before_ok = pos == 0 || !lower[pos - 1].alphanumeric?
            after = pos + key.size
            after_ok = after >= lower.size || !lower[after].alphanumeric?
            if before_ok && after_ok
              surface = text[pos, key.size]
              entities << NamedEntity.new(surface, @gazetteer[key], pos, after, 0.9)
            end
            idx = pos + 1
          end
        end

        # Regex patterns
        @patterns.each do |regex, etype|
          text.scan(regex) do |match|
            m = match[0]
            pos = match.begin(0) || 0
            entities << NamedEntity.new(m, etype, pos, pos + m.size, 0.85)
          end
        end

        # Capitalized multi-word sequences (MISC / PERSON heuristic)
        text.scan(/\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)+)\b/) do |match|
          m = match[1]
          pos = match.begin(0) || 0
          unless entities.any? { |e| e.start_offset <= pos && e.end_offset >= pos + m.size }
            entities << NamedEntity.new(m, EntityType::PERSON, pos, pos + m.size, 0.6)
          end
        end

        # Deduplicate overlapping by keeping higher confidence / longer span
        entities.sort_by! { |e| {e.start_offset, -e.text.size, -e.confidence} }
        filtered = [] of NamedEntity
        entities.each do |e|
          overlaps = filtered.any? do |f|
            e.start_offset < f.end_offset && e.end_offset > f.start_offset
          end
          filtered << e unless overlaps
        end
        filtered
      end

      def to_atomspace(text : String, atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
        atoms = [] of AtomSpace::Atom
        recognize(text).each do |ent|
          node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "ne:#{ent.text}")
          type_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "entity_type:#{ent.entity_type}")
          tv = AtomSpace::SimpleTruthValue.new(ent.confidence, 0.9)
          link = atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [node, type_node], tv)
          atoms << node
          atoms << type_node
          atoms << link
        end
        atoms
      end
    end

    # ---- Coreference Resolution ----

    class Mention
      getter text : String
      getter index : Int32 # sentence / mention order
      getter is_pronoun : Bool
      property referent : String?

      def initialize(@text : String, @index : Int32, @is_pronoun : Bool = false)
        @referent = nil
      end
    end

    class CoreferenceResolver
      PRONOUNS = Set{
        "he", "she", "it", "they", "him", "her", "them",
        "his", "hers", "its", "their", "theirs",
        "this", "that", "these", "those",
      }

      def resolve(text : String) : Array(Mention)
        # Split into rough sentences then tokens
        sentences = text.split(/[.!?]+/).map(&.strip).reject(&.empty?)
        mentions = [] of Mention
        idx = 0

        sentences.each do |sentence|
          tokens = sentence.split(/\s+/).map { |t| t.gsub(/[^\w'-]/, "") }.reject(&.empty?)
          tokens.each do |tok|
            lower = tok.downcase
            is_pronoun = PRONOUNS.includes?(lower)
            is_np = tok[0]?.try(&.uppercase?) || is_pronoun
            next unless is_np
            mentions << Mention.new(tok, idx, is_pronoun)
            idx += 1
          end
        end

        # Simple left-to-right resolution: pronouns link to nearest prior non-pronoun
        last_antecedent = nil.as(String?)
        mentions.each do |m|
          if m.is_pronoun
            m.referent = last_antecedent
          else
            last_antecedent = m.text
            m.referent = m.text
          end
        end

        mentions
      end

      # Replace pronouns with resolved antecedents where possible
      def rewrite(text : String) : String
        mentions = resolve(text)
        result = text
        # Replace from the end to preserve offsets approximately via word replace
        mentions.reverse_each do |m|
          next unless m.is_pronoun
          next unless ref = m.referent
          # Case-sensitive first occurrence replacement of the pronoun word
          result = result.sub(/\b#{Regex.escape(m.text)}\b/) { ref }
        end
        result
      end

      def clusters(text : String) : Hash(String, Array(String))
        clusters = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }
        resolve(text).each do |m|
          key = m.referent || m.text
          clusters[key] << m.text
        end
        clusters
      end
    end

    # ---- Word Sense Disambiguation ----

    struct Sense
      getter id : String
      getter definition : String
      getter examples : Array(String)
      getter related : Array(String) # related context words

      def initialize(@id : String, @definition : String,
                     @examples : Array(String) = [] of String,
                     @related : Array(String) = [] of String)
      end
    end

    class WordSenseDisambiguator
      @lexicon : Hash(String, Array(Sense))

      def initialize
        @lexicon = Hash(String, Array(Sense)).new { |h, k| h[k] = [] of Sense }
        seed_lexicon
      end

      def add_sense(word : String, sense : Sense)
        @lexicon[word.downcase] << sense
      end

      def senses_for(word : String) : Array(Sense)
        @lexicon[word.downcase]
      end

      # Lesk-like overlap: pick sense whose related/example words overlap context most
      def disambiguate(word : String, context : Array(String) | String) : Sense?
        senses = senses_for(word)
        return nil if senses.empty?

        ctx = case context
              when String
                context.downcase.split(/\W+/).reject(&.empty?).to_set
              else
                context.map(&.downcase).to_set
              end

        best = senses.first
        best_score = -1
        senses.each do |sense|
          bag = (sense.related + sense.examples.flat_map { |e| e.downcase.split(/\W+/) } +
                 sense.definition.downcase.split(/\W+/)).to_set
          score = (bag & ctx).size
          if score > best_score
            best_score = score
            best = sense
          end
        end
        best
      end

      def disambiguate_sentence(sentence : String) : Hash(String, Sense)
        tokens = sentence.downcase.split(/\W+/).reject(&.empty?)
        result = {} of String => Sense
        tokens.each do |tok|
          if sense = disambiguate(tok, tokens)
            result[tok] = sense if senses_for(tok).size > 1
          end
        end
        result
      end

      private def seed_lexicon
        add_sense("bank", Sense.new("bank.n.01", "financial institution",
          ["I deposited money at the bank"],
          ["money", "deposit", "loan", "account", "finance"]))
        add_sense("bank", Sense.new("bank.n.02", "side of a river",
          ["We sat on the river bank"],
          ["river", "water", "shore", "stream", "mud"]))
        add_sense("crane", Sense.new("crane.n.01", "wading bird",
          ["A crane flew over the marsh"],
          ["bird", "fly", "wings", "nest"]))
        add_sense("crane", Sense.new("crane.n.02", "lifting machine",
          ["The crane lifted the steel beam"],
          ["lift", "construction", "machine", "heavy", "build"]))
        add_sense("light", Sense.new("light.n.01", "illumination",
          ["Turn on the light"],
          ["bright", "lamp", "dark", "shine"]))
        add_sense("light", Sense.new("light.a.01", "not heavy",
          ["This box is light"],
          ["heavy", "weight", "carry", "feather"]))
      end
    end

    # ---- Multilingual foundations ----

    class MultilingualSupport
      getter default_language : String
      @stopwords : Hash(String, Set(String))
      @token_splitters : Hash(String, Regex)

      def initialize(@default_language : String = "en")
        @stopwords = {
          "en" => Set{"the", "a", "an", "is", "are", "was", "were", "of", "to", "and", "in", "on", "for"},
          "es" => Set{"el", "la", "los", "las", "un", "una", "es", "son", "de", "y", "en", "por"},
          "fr" => Set{"le", "la", "les", "un", "une", "est", "sont", "de", "et", "en", "pour"},
          "de" => Set{"der", "die", "das", "ein", "eine", "ist", "sind", "und", "in", "auf", "für"},
        } of String => Set(String)

        @token_splitters = {
          "en" => /\s+/,
          "es" => /\s+/,
          "fr" => /\s+/,
          "de" => /\s+/,
          "zh" => //, # character-level fallback
          "ja" => //,
        } of String => Regex
      end

      def supported_languages : Array(String)
        @stopwords.keys.sort
      end

      def stopwords(lang : String = @default_language) : Set(String)
        @stopwords[lang]? || Set(String).new
      end

      def tokenize(text : String, lang : String = @default_language) : Array(String)
        splitter = @token_splitters[lang]? || /\s+/
        if lang == "zh" || lang == "ja"
          # Character tokens excluding whitespace
          return text.chars.map(&.to_s).reject { |c| c.strip.empty? }
        end
        text.split(splitter).map { |t| t.gsub(/[^\w'-]/i, "") }.reject(&.empty?)
      end

      def remove_stopwords(tokens : Array(String), lang : String = @default_language) : Array(String)
        sw = stopwords(lang)
        tokens.reject { |t| sw.includes?(t.downcase) }
      end

      # Extremely lightweight language ID by stopword overlap
      def detect_language(text : String) : String
        tokens = text.downcase.split(/\W+/).reject(&.empty?).to_set
        best_lang = @default_language
        best_score = -1
        @stopwords.each do |lang, sw|
          score = (tokens & sw).size
          if score > best_score
            best_score = score
            best_lang = lang
          end
        end
        best_lang
      end

      def register_language(code : String, stopwords : Array(String), splitter : Regex = /\s+/)
        @stopwords[code] = stopwords.map(&.downcase).to_set
        @token_splitters[code] = splitter
      end
    end

    # ---- Discourse planning ----

    enum DiscourseRelation
      ELABORATION
      CONTRAST
      CAUSE
      RESULT
      SEQUENCE
      EXAMPLE
    end

    struct DiscourseUnit
      getter content : String
      getter relation_to_prev : DiscourseRelation?
      getter importance : Float64

      def initialize(@content : String,
                     @relation_to_prev : DiscourseRelation? = nil,
                     @importance : Float64 = 1.0)
      end
    end

    class DiscoursePlanner
      CONNECTIVES = {
        DiscourseRelation::ELABORATION => ["furthermore", "in addition", "also"],
        DiscourseRelation::CONTRAST    => ["however", "but", "on the other hand"],
        DiscourseRelation::CAUSE       => ["because", "since", "as"],
        DiscourseRelation::RESULT      => ["therefore", "thus", "as a result"],
        DiscourseRelation::SEQUENCE    => ["then", "next", "afterward"],
        DiscourseRelation::EXAMPLE     => ["for example", "for instance", "such as"],
      } of DiscourseRelation => Array(String)

      def plan(units : Array(DiscourseUnit)) : String
        return "" if units.empty?
        parts = [] of String
        units.each_with_index do |unit, i|
          if i == 0 || unit.relation_to_prev.nil?
            parts << unit.content
          else
            rel = unit.relation_to_prev.not_nil!
            connective = CONNECTIVES[rel]?.try(&.first) || ""
            parts << "#{connective.capitalize} #{unit.content.sub(/^[A-Z]/) { |c| c.downcase }}"
          end
        end
        parts.join(" ")
      end

      # Order units by importance descending, preserving relative sequence ties
      def prioritize(units : Array(DiscourseUnit)) : Array(DiscourseUnit)
        units.sort_by { |u| -u.importance }
      end

      def from_sentences(sentences : Array(String),
                         default_relation : DiscourseRelation = DiscourseRelation::SEQUENCE) : String
        units = sentences.map_with_index do |s, i|
          DiscourseUnit.new(s, i == 0 ? nil : default_relation, 1.0 - i * 0.01)
        end
        plan(units)
      end
    end

    # ---- Stylistic adaptation ----

    enum Style
      FORMAL
      CASUAL
      TECHNICAL
      SIMPLE
    end

    class StylisticAdapter
      FORMAL_MAP = {
        "can't"  => "cannot",
        "won't"  => "will not",
        "don't"  => "do not",
        "isn't"  => "is not",
        "aren't" => "are not",
        "yeah"   => "yes",
        "ok"     => "acceptable",
        "okay"   => "acceptable",
        "kids"   => "children",
        "stuff"  => "materials",
        "a lot"  => "considerably",
      } of String => String

      CASUAL_MAP = {
        "cannot"      => "can't",
        "will not"    => "won't",
        "do not"      => "don't",
        "is not"      => "isn't",
        "children"    => "kids",
        "therefore"   => "so",
        "however"     => "but",
        "utilize"     => "use",
        "assist"      => "help",
      } of String => String

      TECHNICAL_MAP = {
        "use"    => "utilize",
        "help"   => "facilitate",
        "show"   => "demonstrate",
        "start"  => "initialize",
        "end"    => "terminate",
        "change" => "mutate",
      } of String => String

      SIMPLE_MAP = {
        "utilize"     => "use",
        "facilitate"  => "help",
        "demonstrate" => "show",
        "initialize"  => "start",
        "terminate"   => "end",
        "approximately" => "about",
        "subsequently"  => "then",
      } of String => String

      def adapt(text : String, style : Style) : String
        map = case style
              in .formal?    then FORMAL_MAP
              in .casual?    then CASUAL_MAP
              in .technical? then TECHNICAL_MAP
              in .simple?    then SIMPLE_MAP
              end

        result = text
        # Apply multi-word replacements first
        map.keys.sort_by { |k| -k.size }.each do |from|
          to = map[from]
          result = result.gsub(/#{Regex.escape(from)}/i) do |matched|
            # Preserve capitalization of first letter
            if matched[0].uppercase?
              to.capitalize
            else
              to
            end
          end
        end
        result
      end
    end
  end
end
