# Concept Learning for CrystalCog
#
# This module implements concept learning and formation algorithms,
# enabling the system to discover and generalize conceptual knowledge.
#
# References:
# - Concept Learning: https://en.wikipedia.org/wiki/Concept_learning
# - Version Space Learning: Mitchell, 1997

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module Learning
  module ConceptLearning
    VERSION = "0.1.0"

    # Exception classes
    class ConceptLearningException < Exception
    end

    # Represents a learned concept
    class Concept
      getter name : String
      getter features : Hash(String, String | Float64 | Bool)
      getter positive_examples : Array(Hash(String, String | Float64 | Bool))
      getter negative_examples : Array(Hash(String, String | Float64 | Bool))
      getter confidence : Float64

      def initialize(@name : String,
                     @features : Hash(String, String | Float64 | Bool) = {} of String => String | Float64 | Bool,
                     @confidence : Float64 = 0.5)
        @positive_examples = [] of Hash(String, String | Float64 | Bool)
        @negative_examples = [] of Hash(String, String | Float64 | Bool)
      end

      def add_positive_example(example : Hash(String, String | Float64 | Bool))
        @positive_examples << example
        refine_concept
      end

      def add_negative_example(example : Hash(String, String | Float64 | Bool))
        @negative_examples << example
        refine_concept
      end

      # Check if example matches concept
      def matches?(example : Hash(String, String | Float64 | Bool)) : Bool
        @features.all? do |key, value|
          example[key]? == value
        end
      end

      # Convert to AtomSpace representation
      def to_atomspace(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
        atoms = [] of AtomSpace::Atom

        # Create concept node
        concept_node = atomspace.add_node(
          AtomSpace::AtomType::CONCEPT_NODE,
          @name,
          AtomSpace::SimpleTruthValue.new(@confidence, 0.9)
        )
        atoms << concept_node

        # Add features
        @features.each do |feature_name, feature_value|
          feature_node = atomspace.add_node(
            AtomSpace::AtomType::PREDICATE_NODE,
            "has_#{feature_name}"
          )
          atoms << feature_node

          value_node = atomspace.add_node(
            AtomSpace::AtomType::CONCEPT_NODE,
            feature_value.to_s
          )
          atoms << value_node

          # Create evaluation link
          eval_link = atomspace.add_link(
            AtomSpace::AtomType::EVALUATION_LINK,
            [feature_node, atomspace.add_link(
              AtomSpace::AtomType::LIST_LINK,
              [concept_node, value_node]
            )]
          )
          atoms << eval_link
        end

        atoms
      end

      private def refine_concept
        # Simple concept refinement based on positive/negative examples
        if @positive_examples.size > 0
          # Find common features in positive examples
          common_features = @positive_examples.first.keys.to_set

          @positive_examples.each do |example|
            common_features &= example.keys.to_set
          end

          # Update concept features with most specific generalization
          common_features.each do |key|
            values = @positive_examples.map { |ex| ex[key] }.compact.uniq
            if values.size == 1
              @features[key] = values[0]
            else
              @features.delete(key)
            end
          end

          # Update confidence based on example count
          total = @positive_examples.size + @negative_examples.size
          @confidence = @positive_examples.size.to_f / total if total > 0
        end
      end
    end

    # Implements candidate elimination algorithm
    class CandidateElimination
      getter general_boundary : Array(Hypothesis)
      getter specific_boundary : Array(Hypothesis)

      def initialize
        @general_boundary = [Hypothesis.new_most_general]
        @specific_boundary = [Hypothesis.new_most_specific]
      end

      # Learn from a positive example
      def learn_positive(example : Hash(String, String))
        # Remove from general boundary any hypothesis inconsistent with example
        @general_boundary.reject! { |h| !h.matches?(example) }

        # Generalize specific boundary
        @specific_boundary = @specific_boundary.flat_map do |s|
          if s.matches?(example)
            [s]
          else
            s.minimal_generalizations(example)
          end
        end.uniq

        # Remove from specific boundary any hypothesis not covered by general boundary
        @specific_boundary.reject! do |s|
          !@general_boundary.any? { |g| g.more_general_than?(s) || g == s }
        end
      end

      # Learn from a negative example
      def learn_negative(example : Hash(String, String))
        # Remove from specific boundary any hypothesis consistent with example
        @specific_boundary.reject! { |h| h.matches?(example) }

        # Specialize general boundary
        @general_boundary = @general_boundary.flat_map do |g|
          if !g.matches?(example)
            [g]
          else
            g.minimal_specializations(example, @specific_boundary)
          end
        end.uniq

        # Remove from general boundary any hypothesis not covering any specific hypothesis
        @general_boundary.reject! do |g|
          !@specific_boundary.any? { |s| g.more_general_than?(s) || g.constraints == s.constraints }
        end
      end

      # Get learned concept
      def get_concept : Hypothesis?
        if @specific_boundary.size == 1 && @general_boundary.size == 1
          @specific_boundary.first
        else
          nil
        end
      end
    end

    # Represents a hypothesis in version space
    class Hypothesis
      getter constraints : Hash(String, String | Symbol)

      def initialize(@constraints : Hash(String, String | Symbol))
      end

      def self.new_most_general : Hypothesis
        new({} of String => String | Symbol)
      end

      def self.new_most_specific : Hypothesis
        new({"__none__" => :none} of String => String | Symbol)
      end

      def matches?(example : Hash(String, String)) : Bool
        return false if @constraints.has_key?("__none__")

        @constraints.all? do |key, value|
          value.is_a?(Symbol) || example[key]? == value
        end
      end

      def more_general_than?(other : Hypothesis) : Bool
        other.constraints.all? do |key, value|
          @constraints[key]? == value || @constraints[key]?.nil?
        end
      end

      def minimal_generalizations(example : Hash(String, String)) : Array(Hypothesis)
        if @constraints.has_key?("__none__")
          return [Hypothesis.new(example.transform_values { |v| v.as(String | Symbol) })]
        end

        generalizations = [] of Hypothesis

        example.each do |key, value|
          if !@constraints.has_key?(key)
            new_constraints = @constraints.dup
            new_constraints[key] = value
            generalizations << Hypothesis.new(new_constraints)
          elsif @constraints[key] != value
            new_constraints = @constraints.dup
            new_constraints[key] = :any
            generalizations << Hypothesis.new(new_constraints)
          end
        end

        generalizations.empty? ? [self] : generalizations
      end

      def minimal_specializations(example : Hash(String, String),
                                  specific_boundary : Array(Hypothesis)) : Array(Hypothesis)
        specializations = [] of Hypothesis

        @constraints.each do |key, value|
          if value.is_a?(Symbol) && value == :any
            # Try all possible values from specific boundary
            specific_boundary.each do |s|
              if s_value = s.constraints[key]?
                if s_value.is_a?(String)
                  new_constraints = @constraints.dup
                  new_constraints[key] = s_value
                  spec = Hypothesis.new(new_constraints)
                  specializations << spec if !spec.matches?(example)
                end
              end
            end
          end
        end

        specializations.empty? ? [self] : specializations
      end
    end

    # Concept hierarchy builder
    class ConceptHierarchy
      getter concepts : Hash(String, Concept)
      getter hierarchy : Hash(String, Array(String)) # child -> parents

      def initialize
        @concepts = {} of String => Concept
        @hierarchy = {} of String => Array(String)
      end

      def add_concept(concept : Concept)
        @concepts[concept.name] = concept
      end

      def add_is_a_relation(child : String, parent : String)
        @hierarchy[child] ||= [] of String
        @hierarchy[child] << parent
      end

      def inherits_from?(child : String, parent : String) : Bool
        return true if child == parent

        parents = @hierarchy[child]?
        return false unless parents

        parents.any? { |p| inherits_from?(p, parent) }
      end

      def get_ancestors(concept_name : String) : Array(String)
        ancestors = [] of String
        queue = [concept_name]
        visited = Set(String).new

        while !queue.empty?
          current = queue.shift
          next if visited.includes?(current)

          visited.add(current)

          if parents = @hierarchy[current]?
            parents.each do |parent|
              ancestors << parent unless ancestors.includes?(parent)
              queue << parent
            end
          end
        end

        ancestors
      end

      def to_atomspace(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
        atoms = [] of AtomSpace::Atom

        # Add concepts
        @concepts.each_value do |concept|
          atoms.concat(concept.to_atomspace(atomspace))
        end

        # Add hierarchy relationships
        @hierarchy.each do |child, parents|
          child_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, child)

          parents.each do |parent|
            parent_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, parent)

            inheritance = atomspace.add_link(
              AtomSpace::AtomType::INHERITANCE_LINK,
              [child_node, parent_node],
              AtomSpace::SimpleTruthValue.new(0.9, 0.9)
            )
            atoms << inheritance
          end
        end

        atoms
      end
    end

    # Module-level convenience methods
    def self.create_concept(name : String) : Concept
      Concept.new(name)
    end

    def self.create_hierarchy : ConceptHierarchy
      ConceptHierarchy.new
    end
  end
end
