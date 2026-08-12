# Language Generation for CrystalCog
#
# This module provides natural language generation capabilities,
# converting semantic representations in the AtomSpace into natural language text.
#
# References:
# - Natural Language Generation: https://en.wikipedia.org/wiki/Natural_language_generation
# - SimpleNLG: https://github.com/simplenlg/simplenlg

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "./nlp"

module NLP
  module LanguageGeneration
    VERSION = "0.1.0"

    # Exception classes
    class GenerationException < NLP::NLPException
    end

    # Represents a template for generating text
    struct Template
      getter pattern : String
      getter slots : Array(String)

      def initialize(@pattern : String, @slots : Array(String) = [] of String)
      end

      def fill(values : Hash(String, String)) : String
        result = @pattern.dup

        @slots.each do |slot|
          if value = values[slot]?
            result = result.gsub("{#{slot}}", value)
          end
        end

        result
      end
    end

    # Simple sentence structure for generation
    struct Sentence
      getter subject : String?
      getter verb : String?
      getter object : String?
      getter modifiers : Array(String)
      getter tense : Tense

      enum Tense
        PRESENT
        PAST
        FUTURE
      end

      def initialize(@subject : String? = nil, @verb : String? = nil,
                     @object : String? = nil, @modifiers : Array(String) = [] of String,
                     @tense : Tense = Tense::PRESENT)
      end

      def to_s : String
        parts = [] of String

        parts << subject.not_nil! if subject
        if v = conjugate_verb(verb, tense)
          parts << v
        end
        parts << object.not_nil! if object
        parts.concat(modifiers)

        result = parts.join(" ")
        result = result.capitalize if result.size > 0
        result += "." unless result.ends_with?(".")
        result
      end

      private def conjugate_verb(verb : String?, tense : Tense) : String?
        return nil unless verb

        case tense
        when Tense::PRESENT
          verb
        when Tense::PAST
          # Simple past tense (very basic)
          verb.ends_with?("e") ? "#{verb}d" : "#{verb}ed"
        when Tense::FUTURE
          "will #{verb}"
        else
          verb
        end
      end
    end

    # Main language generator class
    class Generator
      getter language : String
      getter templates : Hash(String, Template)

      def initialize(@language : String = "en")
        @templates = {} of String => Template
        initialize_default_templates
        CogUtil::Logger.info("Language Generator initialized for #{@language}")
      end

      # Generate text from an Atom
      def generate_from_atom(atom : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace) : String
        case atom.type
        when AtomSpace::AtomType::CONCEPT_NODE
          generate_from_concept(atom)
        when AtomSpace::AtomType::INHERITANCE_LINK
          generate_from_inheritance(atom, atomspace)
        when AtomSpace::AtomType::EVALUATION_LINK
          generate_from_evaluation(atom, atomspace)
        when AtomSpace::AtomType::LIST_LINK
          generate_from_list(atom, atomspace)
        else
          atom.name
        end
      end

      # Generate text from semantic network
      def generate_from_semantic_network(root : AtomSpace::Atom,
                                         atomspace : AtomSpace::AtomSpace) : String
        sentences = [] of String

        # Find all inheritance relationships
        inheritances = find_inheritances(root, atomspace)
        inheritances.each do |link|
          sentence = generate_from_inheritance(link, atomspace)
          sentences << sentence
        end

        # Find all property evaluations
        evaluations = find_evaluations(root, atomspace)
        evaluations.each do |link|
          sentence = generate_from_evaluation(link, atomspace)
          sentences << sentence
        end

        sentences.join(" ")
      end

      # Generate simple sentence
      def generate_sentence(subject : String, verb : String, object : String? = nil,
                            modifiers : Array(String) = [] of String,
                            tense : Sentence::Tense = Sentence::Tense::PRESENT) : String
        sentence = Sentence.new(subject, verb, object, modifiers, tense)
        sentence.to_s
      end

      # Generate from template
      def generate_from_template(template_name : String,
                                 values : Hash(String, String)) : String
        template = @templates[template_name]?

        if template
          template.fill(values)
        else
          raise GenerationException.new("Template not found: #{template_name}")
        end
      end

      # Add custom template
      def add_template(name : String, pattern : String, slots : Array(String))
        @templates[name] = Template.new(pattern, slots)
      end

      # Generate question from statement
      def generate_question(statement : String, question_type : String = "yes_no") : String
        words = statement.split

        case question_type
        when "yes_no"
          # Simple yes/no question
          if words.size >= 2
            "#{words[1].capitalize} #{words[0]} #{words[2..-1].join(" ")}?"
          else
            statement + "?"
          end
        when "what"
          "What #{statement.downcase}?"
        when "who"
          "Who #{statement.downcase}?"
        when "where"
          "Where #{statement.downcase}?"
        when "when"
          "When #{statement.downcase}?"
        when "why"
          "Why #{statement.downcase}?"
        when "how"
          "How #{statement.downcase}?"
        else
          statement + "?"
        end
      end

      # Generate paraphrase
      def paraphrase(text : String) : String
        # Simple paraphrasing by synonym replacement and structure variation
        words = text.split

        # Very basic paraphrasing - in real implementation would use thesaurus
        paraphrased = words.map do |word|
          case word.downcase
          when "big"   then "large"
          when "small" then "little"
          when "fast"  then "quick"
          when "slow"  then "gradual"
          when "good"  then "excellent"
          when "bad"   then "poor"
          else              word
          end
        end

        paraphrased.join(" ")
      end

      # Generate summary from multiple sentences
      def summarize(sentences : Array(String), max_sentences : Int32 = 3) : String
        # Simple extractive summarization - take first N sentences
        sentences[0...max_sentences].join(" ")
      end

      # Discourse-aware multi-sentence generation
      def generate_discourse(units : Array(NLP::Advanced::DiscourseUnit)) : String
        NLP::Advanced::DiscoursePlanner.new.plan(units)
      end

      # Stylistic adaptation of generated text
      def adapt_style(text : String, style : NLP::Advanced::Style) : String
        NLP::Advanced::StylisticAdapter.new.adapt(text, style)
      end

      # Paraphrase then optionally restyle
      def paraphrase_as(text : String, style : NLP::Advanced::Style) : String
        adapt_style(paraphrase(text), style)
      end

      private def initialize_default_templates
        @templates["inheritance"] = Template.new(
          "{subject} is a {object}",
          ["subject", "object"]
        )

        @templates["property"] = Template.new(
          "{subject} has {property} of {value}",
          ["subject", "property", "value"]
        )

        @templates["action"] = Template.new(
          "{subject} {action} {object}",
          ["subject", "action", "object"]
        )

        @templates["location"] = Template.new(
          "{subject} is in {location}",
          ["subject", "location"]
        )

        @templates["comparison"] = Template.new(
          "{subject} is {comparison} than {object}",
          ["subject", "comparison", "object"]
        )
      end

      private def generate_from_concept(atom : AtomSpace::Atom) : String
        atom.name.gsub("_", " ")
      end

      private def generate_from_inheritance(link : AtomSpace::Atom,
                                            atomspace : AtomSpace::AtomSpace) : String
        if link.outgoing.size >= 2
          subject = link.outgoing[0].name.gsub("_", " ")
          object = link.outgoing[1].name.gsub("_", " ")

          generate_from_template("inheritance", {
            "subject" => subject,
            "object"  => object,
          })
        else
          ""
        end
      end

      private def generate_from_evaluation(link : AtomSpace::Atom,
                                           atomspace : AtomSpace::AtomSpace) : String
        return "" if link.outgoing.size < 2

        predicate = link.outgoing[0].name.gsub("_", " ")

        if link.outgoing[1].type == AtomSpace::AtomType::LIST_LINK
          args = link.outgoing[1].outgoing.map { |a| a.name.gsub("_", " ") }

          if args.size >= 2
            "#{args[0]} #{predicate} #{args[1]}"
          else
            "#{args[0]} #{predicate}" if args.size == 1
          end
        else
          subject = link.outgoing[1].name.gsub("_", " ")
          "#{subject} #{predicate}"
        end || ""
      end

      private def generate_from_list(link : AtomSpace::Atom,
                                     atomspace : AtomSpace::AtomSpace) : String
        items = link.outgoing.map { |atom| generate_from_atom(atom, atomspace) }

        case items.size
        when 0
          ""
        when 1
          items[0]
        when 2
          "#{items[0]} and #{items[1]}"
        else
          "#{items[0..-2].join(", ")}, and #{items[-1]}"
        end
      end

      private def find_inheritances(root : AtomSpace::Atom,
                                    atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
        atomspace.get_incoming(root)
          .select { |atom| atom.type == AtomSpace::AtomType::INHERITANCE_LINK }
      end

      private def find_evaluations(root : AtomSpace::Atom,
                                   atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
        atomspace.get_incoming(root)
          .select { |atom| atom.type == AtomSpace::AtomType::EVALUATION_LINK }
      end
    end

    # Module-level convenience methods
    def self.generate(atom : AtomSpace::Atom, atomspace : AtomSpace::AtomSpace,
                      language : String = "en") : String
      generator = Generator.new(language)
      generator.generate_from_atom(atom, atomspace)
    end

    def self.generate_sentence(subject : String, verb : String, object : String? = nil,
                               language : String = "en") : String
      generator = Generator.new(language)
      generator.generate_sentence(subject, verb, object)
    end
  end
end
