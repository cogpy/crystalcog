# Semantic Understanding for CrystalCog
#
# This module provides semantic analysis and understanding capabilities,
# extracting meaning from text and building semantic representations
# in the AtomSpace.
#
# References:
# - Semantic Role Labeling: https://en.wikipedia.org/wiki/Semantic_role_labeling
# - FrameNet: https://framenet.icsi.berkeley.edu/

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "./dependency_parser"

module NLP
  module SemanticUnderstanding
    VERSION = "0.1.0"

    # Exception classes
    class SemanticException < NLP::NLPException
    end

    # Semantic roles (based on FrameNet/PropBank)
    enum SemanticRole
      AGENT       # Entity performing action
      PATIENT     # Entity affected by action
      THEME       # Entity moved/changed
      EXPERIENCER # Entity experiencing event
      INSTRUMENT  # Tool used
      LOCATION    # Where event occurs
      SOURCE      # Origin
      GOAL        # Destination
      BENEFICIARY # Who benefits
      TIME        # When event occurs
      MANNER      # How event occurs
      CAUSE       # Why event occurs
      PURPOSE     # Intended result
      RESULT      # Actual result
      ATTRIBUTE   # Property
    end

    # Represents a semantic frame (event/state)
    class Frame
      getter name : String
      getter frame_elements : Hash(SemanticRole, String)
      getter confidence : Float64

      def initialize(@name : String,
                     @frame_elements : Hash(SemanticRole, String) = {} of SemanticRole => String,
                     @confidence : Float64 = 1.0)
      end

      def add_element(role : SemanticRole, filler : String)
        @frame_elements[role] = filler
      end

      # Convert to AtomSpace representation
      def to_atomspace(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
        atoms = [] of AtomSpace::Atom

        # Create frame node
        frame_node = atomspace.add_node(
          AtomSpace::AtomType::CONCEPT_NODE,
          "frame_#{name}"
        )
        atoms << frame_node

        # Create frame elements
        @frame_elements.each do |role, filler|
          role_node = atomspace.add_node(
            AtomSpace::AtomType::CONCEPT_NODE,
            "role_#{role.to_s.downcase}"
          )
          atoms << role_node

          filler_node = atomspace.add_node(
            AtomSpace::AtomType::CONCEPT_NODE,
            filler
          )
          atoms << filler_node

          # Link role to filler
          role_link = atomspace.add_link(
            AtomSpace::AtomType::EVALUATION_LINK,
            [role_node, atomspace.add_link(
              AtomSpace::AtomType::LIST_LINK,
              [frame_node, filler_node]
            )],
            AtomSpace::SimpleTruthValue.new(@confidence, 0.9)
          )
          atoms << role_link
        end

        atoms
      end

      def to_s(io : IO)
        io << "Frame[#{name}]: "
        io << @frame_elements.map { |k, v| "#{k}=#{v}" }.join(", ")
      end
    end

    # Represents semantic analysis result
    class SemanticAnalysis
      getter text : String
      getter frames : Array(Frame)
      getter entities : Array(String)
      getter relations : Array(Tuple(String, String, String)) # (entity1, relation, entity2)

      def initialize(@text : String, @frames : Array(Frame) = [] of Frame,
                     @entities : Array(String) = [] of String,
                     @relations : Array(Tuple(String, String, String)) = [] of Tuple(String, String, String))
      end

      # Convert to AtomSpace
      def to_atomspace(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
        atoms = [] of AtomSpace::Atom

        # Add frames
        @frames.each do |frame|
          atoms.concat(frame.to_atomspace(atomspace))
        end

        # Add entities
        @entities.each do |entity|
          entity_node = atomspace.add_node(
            AtomSpace::AtomType::CONCEPT_NODE,
            entity
          )
          atoms << entity_node
        end

        # Add relations
        @relations.each do |rel|
          entity1 = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, rel[0])
          entity2 = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, rel[2])
          relation = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, rel[1])

          atoms << entity1
          atoms << entity2
          atoms << relation

          rel_link = atomspace.add_link(
            AtomSpace::AtomType::EVALUATION_LINK,
            [relation, atomspace.add_link(
              AtomSpace::AtomType::LIST_LINK,
              [entity1, entity2]
            )]
          )
          atoms << rel_link
        end

        atoms
      end
    end

    # Main semantic understanding analyzer
    class Analyzer
      getter language : String
      getter dependency_parser : DependencyParser::Parser

      def initialize(@language : String = "en")
        @dependency_parser = DependencyParser::Parser.new(@language)
        CogUtil::Logger.info("Semantic Analyzer initialized for #{@language}")
      end

      # Analyze text and extract semantic information
      def analyze(text : String) : SemanticAnalysis
        CogUtil::Logger.debug("Analyzing semantic content of: #{text}")

        # Parse dependencies first
        dep_parse = @dependency_parser.parse(text)

        # Extract frames
        frames = extract_frames(dep_parse)

        # Extract entities
        entities = extract_entities(dep_parse)

        # Extract relations
        relations = extract_relations(dep_parse)

        SemanticAnalysis.new(text, frames, entities, relations)
      end

      # Analyze and store in AtomSpace
      def analyze_to_atomspace(text : String,
                               atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
        analysis = analyze(text)
        analysis.to_atomspace(atomspace)
      end

      # Extract named entities from text
      def extract_named_entities(text : String) : Array(String)
        entities = [] of String

        # Simple heuristic: capitalized words (except sentence start)
        words = text.split
        words.each_with_index do |word, i|
          if i > 0 && word[0].uppercase?
            entities << word
          end
        end

        entities
      end

      # Determine semantic similarity between two texts
      def semantic_similarity(text1 : String, text2 : String) : Float64
        analysis1 = analyze(text1)
        analysis2 = analyze(text2)

        # Simple similarity based on shared entities and frames
        shared_entities = (analysis1.entities & analysis2.entities).size
        total_entities = (analysis1.entities | analysis2.entities).size

        if total_entities == 0
          0.0
        else
          shared_entities.to_f / total_entities.to_f
        end
      end

      # Extract key concepts from text
      def extract_key_concepts(text : String, max_concepts : Int32 = 5) : Array(String)
        dep_parse = @dependency_parser.parse(text)
        concepts = [] of String

        # Extract nouns (simplified)
        dep_parse.words.each_with_index do |word, idx|
          # Heuristic: words that are heads of dependencies
          if dep_parse.get_dependents(idx).size > 0
            concepts << word
          end
        end

        concepts[0...max_concepts]
      end

      # Infer implicit information
      def infer_implications(text : String,
                             atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
        atoms = [] of AtomSpace::Atom
        analysis = analyze(text)

        # Simple inference: if X is agent of action, X is capable
        analysis.frames.each do |frame|
          if agent = frame.frame_elements[SemanticRole::AGENT]?
            capability = atomspace.add_node(
              AtomSpace::AtomType::CONCEPT_NODE,
              "capable_of_#{frame.name}"
            )
            agent_node = atomspace.add_node(
              AtomSpace::AtomType::CONCEPT_NODE,
              agent
            )

            # Create implication
            impl_link = atomspace.add_link(
              AtomSpace::AtomType::IMPLICATION_LINK,
              [agent_node, capability],
              AtomSpace::SimpleTruthValue.new(0.7, 0.8)
            )

            atoms << capability
            atoms << agent_node
            atoms << impl_link
          end
        end

        atoms
      end

      private def extract_frames(dep_parse : DependencyParser::DependencyParse) : Array(Frame)
        frames = [] of Frame

        # Find verbal predicates
        dep_parse.words.each_with_index do |word, idx|
          if is_verb?(word)
            frame = build_frame_from_verb(word, idx, dep_parse)
            frames << frame if frame
          end
        end

        frames
      end

      private def build_frame_from_verb(verb : String, verb_idx : Int32,
                                        dep_parse : DependencyParser::DependencyParse) : Frame?
        frame = Frame.new(verb)

        # Find arguments based on dependency relations
        dep_parse.dependencies.each do |dep|
          if dep.head == verb_idx
            role = map_dependency_to_role(dep.relation)
            frame.add_element(role, dep.dependent_word)
          elsif dep.dependent == verb_idx
            # Verb might be dependent (e.g., in subordinate clause)
            role = SemanticRole::AGENT # Simplified
            frame.add_element(role, dep.head_word)
          end
        end

        frame
      end

      private def map_dependency_to_role(dep_relation : DependencyParser::RelationType) : SemanticRole
        case dep_relation
        when DependencyParser::RelationType::NSUBJ
          SemanticRole::AGENT
        when DependencyParser::RelationType::OBJ
          SemanticRole::PATIENT
        when DependencyParser::RelationType::IOBJ
          SemanticRole::BENEFICIARY
        when DependencyParser::RelationType::OBL
          SemanticRole::LOCATION
        when DependencyParser::RelationType::ADVMOD
          SemanticRole::MANNER
        else
          SemanticRole::THEME
        end
      end

      private def extract_entities(dep_parse : DependencyParser::DependencyParse) : Array(String)
        entities = [] of String

        # Extract nouns and proper nouns
        dep_parse.words.each do |word|
          if is_noun?(word)
            entities << word
          end
        end

        entities.uniq
      end

      private def extract_relations(dep_parse : DependencyParser::DependencyParse) : Array(Tuple(String, String, String))
        relations = [] of Tuple(String, String, String)

        # Extract subject-verb-object triples
        dep_parse.dependencies.each do |dep|
          if dep.relation == DependencyParser::RelationType::NSUBJ
            subject = dep.dependent_word
            verb_idx = dep.head

            # Find object
            dep_parse.dependencies.each do |obj_dep|
              if obj_dep.head == verb_idx && obj_dep.relation == DependencyParser::RelationType::OBJ
                object = obj_dep.dependent_word
                verb = dep_parse.words[verb_idx]
                relations << {subject, verb, object}
              end
            end
          end
        end

        relations
      end

      private def is_verb?(word : String) : Bool
        # Simple heuristic - in real implementation would use POS tagger
        verb_endings = ["s", "ed", "ing"]
        common_verbs = ["is", "are", "was", "were", "be", "has", "have", "had",
                        "do", "does", "did", "can", "could", "will", "would",
                        "make", "get", "go", "see", "take", "give"]

        common_verbs.includes?(word.downcase) ||
          verb_endings.any? { |e| word.ends_with?(e) }
      end

      private def is_noun?(word : String) : Bool
        # Simple heuristic - in real implementation would use POS tagger
        # Assume words that aren't obviously verbs are potentially nouns
        !is_verb?(word) && word.size > 2
      end
    end

    # Module-level convenience methods
    def self.analyze(text : String, language : String = "en") : SemanticAnalysis
      analyzer = Analyzer.new(language)
      analyzer.analyze(text)
    end

    def self.analyze_to_atomspace(text : String, atomspace : AtomSpace::AtomSpace,
                                  language : String = "en") : Array(AtomSpace::Atom)
      analyzer = Analyzer.new(language)
      analyzer.analyze_to_atomspace(text, atomspace)
    end
  end
end
