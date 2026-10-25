# OpenCog module - Core reasoning and cognitive architecture
# This implements the main OpenCog reasoning components

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "../pln/pln"
require "../ure/ure"
require "./query_language"

module OpenCog
  VERSION = "0.1.0"

  # Initialize the OpenCog subsystem
  def self.initialize
    CogUtil::Logger.info("OpenCog #{VERSION} initializing")

    # Initialize dependencies
    CogUtil.initialize unless @@cogutil_initialized
    AtomSpace.initialize unless @@atomspace_initialized
    PLN.initialize unless @@pln_initialized
    URE.initialize unless @@ure_initialized
    QueryLanguage.initialize unless @@query_language_initialized

    CogUtil::Logger.info("OpenCog #{VERSION} initialized")
  end

  # Track initialization state
  @@cogutil_initialized = false
  @@atomspace_initialized = false
  @@pln_initialized = false
  @@ure_initialized = false
  @@query_language_initialized = false

  # Exception classes for OpenCog
  class OpenCogException < CogUtil::OpenCogException
  end

  class ReasoningException < OpenCogException
  end

  class PatternMatchException < OpenCogException
  end

  class QueryException < OpenCogException
  end

  # Core reasoning algorithms
  module Reasoning
    # Apply basic logical inference to an AtomSpace
    def self.infer(atomspace : AtomSpace::AtomSpace, max_steps : Int32 = 10) : Array(AtomSpace::Atom)
      results = [] of AtomSpace::Atom

      # Create PLN engine for probabilistic reasoning
      pln_engine = PLN.create_engine(atomspace)
      pln_results = pln_engine.reason(max_steps)
      results.concat(pln_results)

      # Create URE engine for rule-based reasoning
      ure_engine = URE.create_engine(atomspace)
      ure_results = ure_engine.forward_chain(max_steps)
      results.concat(ure_results)

      CogUtil::Logger.info("OpenCog: Generated #{results.size} inferences")
      results
    end

    # Check if a conclusion can be reached from premises
    def self.can_conclude?(atomspace : AtomSpace::AtomSpace, goal : AtomSpace::Atom) : Bool
      # Try URE backward chaining
      ure_engine = URE.create_engine(atomspace)
      if ure_engine.backward_chain(goal)
        return true
      end

      # Try PLN backward chaining
      pln_engine = PLN.create_engine(atomspace)
      return pln_engine.backward_chain(goal)
    end

    # Find the most confident atoms of a given type
    def self.find_most_confident(atomspace : AtomSpace::AtomSpace, type : AtomSpace::AtomType, limit : Int32 = 10) : Array(AtomSpace::Atom)
      atoms = atomspace.get_atoms_by_type(type)
      sorted = atoms.sort { |a, b| b.truth_value.confidence <=> a.truth_value.confidence }
      sorted.first(limit)
    end

    # Calculate similarity between two atoms based on their relationships
    def self.similarity(atomspace : AtomSpace::AtomSpace, atom1 : AtomSpace::Atom, atom2 : AtomSpace::Atom) : Float64
      return 1.0 if atom1 == atom2
      return 0.0 if atom1.type != atom2.type

      # Find common neighbors (atoms that reference both)
      incoming1 = atomspace.get_incoming(atom1)
      incoming2 = atomspace.get_incoming(atom2)

      common = incoming1.select { |a| incoming2.includes?(a) }
      union = (incoming1 + incoming2).uniq

      return 0.0 if union.empty?
      common.size.to_f / union.size.to_f
    end
  end

  # Atom manipulation utilities
  module AtomUtils
    # Create a concept hierarchy
    def self.create_hierarchy(atomspace : AtomSpace::AtomSpace, hierarchy : Hash(String, Array(String))) : Array(AtomSpace::Atom)
      created = [] of AtomSpace::Atom

      hierarchy.each do |concept, parents|
        child_node = atomspace.add_concept_node(concept)
        created << child_node

        parents.each do |parent|
          parent_node = atomspace.add_concept_node(parent)
          created << parent_node

          inheritance = atomspace.add_inheritance_link(child_node, parent_node)
          created << inheritance
        end
      end

      CogUtil::Logger.info("Created hierarchy with #{created.size} atoms")
      created
    end

    # Create semantic network from facts
    def self.create_semantic_network(atomspace : AtomSpace::AtomSpace, facts : Array(Hash(String, String))) : Array(AtomSpace::Atom)
      created = [] of AtomSpace::Atom

      facts.each do |fact|
        subject_name = fact["subject"]?
        predicate_name = fact["predicate"]?
        object_name = fact["object"]?

        next unless subject_name && predicate_name && object_name

        subject = atomspace.add_concept_node(subject_name)
        predicate = atomspace.add_predicate_node(predicate_name)
        object_atom = atomspace.add_concept_node(object_name)

        list_link = atomspace.add_list_link([subject, object_atom])
        evaluation = atomspace.add_evaluation_link(predicate, list_link)

        created.concat([subject, predicate, object_atom, list_link, evaluation])
      end

      CogUtil::Logger.info("Created semantic network with #{created.size} atoms")
      created
    end

    # Extract subgraph around an atom
    def self.extract_subgraph(atomspace : AtomSpace::AtomSpace, center : AtomSpace::Atom, depth : Int32 = 2) : Array(AtomSpace::Atom)
      visited = Set(AtomSpace::Atom).new
      queue = [{center, 0}]
      result = [] of AtomSpace::Atom

      while !queue.empty?
        atom, current_depth = queue.shift
        next if visited.includes?(atom) || current_depth > depth

        visited.add(atom)
        result << atom

        if current_depth < depth
          # Add incoming links (atoms that reference this atom)
          incoming = atomspace.get_incoming(atom)
          incoming.each do |incoming_atom|
            queue << {incoming_atom, current_depth + 1}
          end

          # Add outgoing atoms (for links)
          if atom.is_a?(AtomSpace::Link)
            atom.outgoing.each do |outgoing_atom|
              queue << {outgoing_atom, current_depth + 1}
            end
          end
        end
      end

      result
    end

    # Merge two atoms with the same structure
    def self.merge_atoms(atomspace : AtomSpace::AtomSpace, atom1 : AtomSpace::Atom, atom2 : AtomSpace::Atom) : AtomSpace::Atom?
      return nil unless atom1.type == atom2.type

      # For nodes, they must have the same name
      if atom1.is_a?(AtomSpace::Node) && atom2.is_a?(AtomSpace::Node)
        return nil unless atom1.name == atom2.name
      end

      # For links, they must have the same outgoing set
      if atom1.is_a?(AtomSpace::Link) && atom2.is_a?(AtomSpace::Link)
        return nil unless atom1.outgoing == atom2.outgoing
      end

      # Merge truth values
      merged_tv = atom1.truth_value.merge(atom2.truth_value)
      atom1.truth_value = merged_tv

      # Remove the duplicate atom
      atomspace.remove_atom(atom2)

      CogUtil::Logger.debug("Merged atoms: #{atom1}")
      atom1
    end

    # Find atoms matching a pattern
    def self.find_matching_atoms(atomspace : AtomSpace::AtomSpace, pattern : AtomSpace::Atom) : Array(AtomSpace::Atom)
      results = [] of AtomSpace::Atom

      atomspace.get_all_atoms.each do |atom|
        if atoms_match?(atom, pattern)
          results << atom
        end
      end

      results
    end

    private def self.atoms_match?(atom : AtomSpace::Atom, pattern : AtomSpace::Atom) : Bool
      # Simple pattern matching - could be extended with variables
      return false unless atom.type == pattern.type

      if atom.is_a?(AtomSpace::Node) && pattern.is_a?(AtomSpace::Node)
        return atom.name == pattern.name
      end

      if atom.is_a?(AtomSpace::Link) && pattern.is_a?(AtomSpace::Link)
        return false unless atom.outgoing.size == pattern.outgoing.size

        atom.outgoing.zip(pattern.outgoing) do |a_out, p_out|
          return false unless atoms_match?(a_out, p_out)
        end
      end

      true
    end
  end

  # Basic query processing
  module Query
    # Query result structure
    struct QueryResult
      getter bindings : Hash(String, AtomSpace::Atom)
      getter confidence : Float64

      def initialize(@bindings, @confidence)
      end
    end

    # Simple variable for queries
    struct Variable
      getter name : String
      getter type : AtomSpace::AtomType?

      def initialize(@name, @type = nil)
      end

      def to_s(io : IO)
        io << "$#{@name}"
        io << ":#{@type}" if @type
      end
    end

    # String-based query interface using Query Language
    def self.execute_query(atomspace : AtomSpace::AtomSpace, query_string : String) : Array(QueryResult)
      query_interface = QueryLanguage.create_interface(atomspace)
      query_interface.query(query_string)
    end

    # Parse a query string to understand its structure
    def self.parse_query(query_string : String) : QueryLanguage::ParsedQuery
      QueryLanguage.parse_query(query_string)
    end

    # Create a query language interface for an atomspace
    def self.create_query_interface(atomspace : AtomSpace::AtomSpace) : QueryLanguage::QueryLanguageInterface
      QueryLanguage.create_interface(atomspace)
    end

    # Execute a simple pattern query
    def self.query_pattern(atomspace : AtomSpace::AtomSpace, pattern : AtomSpace::Atom, variables : Array(Variable) = [] of Variable) : Array(QueryResult)
      results = [] of QueryResult

      # Patterns with variables go through the pattern matcher, which
      # binds each variable (typed via `variables`) to a grounding.
      if contains_variable?(pattern)
        pattern_obj = PatternMatching::Pattern.new(pattern)
        variables.each do |var|
          next unless allowed = var.type
          var_atom = atomspace.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$#{var.name}")
          pattern_obj.add_constraint(PatternMatching::TypeConstraint.new(var_atom, allowed))
        end

        PatternMatching::PatternMatcher.new(atomspace).match(pattern_obj).each do |match|
          bindings = Hash(String, AtomSpace::Atom).new
          match.bindings.each do |var_atom, bound|
            bindings[var_atom.name.lstrip("$")] = bound if var_atom.type == AtomSpace::AtomType::VARIABLE_NODE
          end
          matched = match.matched_atoms
          confidence = matched.empty? ? 0.0 : matched.sum(&.truth_value.confidence) / matched.size
          results << QueryResult.new(bindings, confidence)
        end
        results.sort! { |a, b| b.confidence <=> a.confidence }
        return results
      end

      matching_atoms = AtomUtils.find_matching_atoms(atomspace, pattern)

      matching_atoms.each do |atom|
        bindings = Hash(String, AtomSpace::Atom).new
        confidence = atom.truth_value.confidence

        # Simple variable binding (would be more complex in practice)
        if variables.size == 1 && atom.is_a?(AtomSpace::Node)
          bindings[variables[0].name] = atom
        end

        results << QueryResult.new(bindings, confidence)
      end

      # Sort by confidence
      results.sort! { |a, b| b.confidence <=> a.confidence }
      results
    end

    # Find all instances of a concept
    def self.find_instances(atomspace : AtomSpace::AtomSpace, concept : AtomSpace::Atom) : Array(AtomSpace::Atom)
      instances = [] of AtomSpace::Atom

      # Find all inheritance links where concept is the parent
      inheritance_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK)

      inheritance_links.each do |link|
        next unless link.is_a?(AtomSpace::Link)
        next unless link.outgoing.size == 2

        child, parent = link.outgoing[0], link.outgoing[1]
        if parent == concept
          instances << child
        end
      end

      instances
    end

    # Find all predicates applied to a subject
    def self.find_predicates(atomspace : AtomSpace::AtomSpace, subject : AtomSpace::Atom) : Hash(AtomSpace::Atom, AtomSpace::Atom)
      predicates = Hash(AtomSpace::Atom, AtomSpace::Atom).new

      # Find evaluation links involving the subject
      evaluation_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)

      evaluation_links.each do |link|
        next unless link.is_a?(AtomSpace::Link)
        next unless link.outgoing.size == 2

        predicate, args = link.outgoing[0], link.outgoing[1]

        # Check if subject is in the arguments
        if args.is_a?(AtomSpace::Link) && args.outgoing.includes?(subject)
          predicates[predicate] = args
        end
      end

      predicates
    end

    # Execute a conjunction query (AND of multiple patterns)
    def self.query_conjunction(atomspace : AtomSpace::AtomSpace, patterns : Array(AtomSpace::Atom)) : Array(QueryResult)
      return [] of QueryResult if patterns.empty?

      results = query_pattern(atomspace, patterns[0])

      # Natural join: keep combinations whose shared variables agree; the
      # joined confidence is the weaker of the two.
      patterns[1..].each do |pattern|
        pattern_results = query_pattern(atomspace, pattern)

        results = results.flat_map do |result|
          pattern_results.compact_map do |pr|
            next unless pr.bindings.all? { |name, atom| (bound = result.bindings[name]?).nil? || bound == atom }
            QueryResult.new(result.bindings.merge(pr.bindings), Math.min(result.confidence, pr.confidence))
          end
        end
      end

      results.uniq(&.bindings)
    end

    private def self.contains_variable?(atom : AtomSpace::Atom) : Bool
      return true if atom.type == AtomSpace::AtomType::VARIABLE_NODE
      atom.link? && atom.outgoing.any? { |child| contains_variable?(child) }
    end

    # Execute a disjunction query (OR of multiple patterns)
    def self.query_disjunction(atomspace : AtomSpace::AtomSpace, patterns : Array(AtomSpace::Atom)) : Array(QueryResult)
      all_results = [] of QueryResult

      patterns.each do |pattern|
        pattern_results = query_pattern(atomspace, pattern)
        all_results.concat(pattern_results)
      end

      # Remove duplicates and sort by confidence
      unique_results = all_results.uniq { |r| r.bindings }
      unique_results.sort! { |a, b| b.confidence <=> a.confidence }
      unique_results
    end
  end

  # Pattern matching engine
  module PatternMatcher
    # This contains the pattern matching engine

    # Match a pattern against the AtomSpace
    def self.match(atomspace : AtomSpace::AtomSpace, pattern : AtomSpace::Atom) : Array(Hash(String, AtomSpace::Atom))
      bindings = [] of Hash(String, AtomSpace::Atom)

      # Simple pattern matching implementation
      atomspace.get_all_atoms.each do |atom|
        if match_result = try_match(atom, pattern)
          bindings << match_result
        end
      end

      bindings
    end

    private def self.try_match(atom : AtomSpace::Atom, pattern : AtomSpace::Atom) : Hash(String, AtomSpace::Atom)?
      # This would contain sophisticated pattern matching logic
      # For now, simple equality check
      if atom == pattern
        return Hash(String, AtomSpace::Atom).new
      end

      nil
    end
  end

  # Learning algorithms
  module Learning
    # This contains learning algorithms

    # Learn new implications from observed patterns
    def self.learn_implications(atomspace : AtomSpace::AtomSpace, confidence_threshold : Float64 = 0.7) : Array(AtomSpace::Atom)
      learned = [] of AtomSpace::Atom

      # Find frequent co-occurrences and create implications
      evaluation_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)

      # Group by subjects and find patterns
      subject_predicates = Hash(AtomSpace::Atom, Array(AtomSpace::Atom)).new

      evaluation_links.each do |link|
        next unless link.is_a?(AtomSpace::Link) && link.outgoing.size == 2

        predicate, args = link.outgoing[0], link.outgoing[1]
        next unless args.is_a?(AtomSpace::Link) && args.outgoing.size > 0

        subject = args.outgoing[0]
        preds = subject_predicates[subject]? || Array(AtomSpace::Atom).new
        preds << predicate
        subject_predicates[subject] = preds
      end

      # Find patterns and create implications
      subject_predicates.each do |subject, predicates|
        predicates.each_with_index do |pred1, i|
          predicates[i + 1..].each do |pred2|
            # Create implication: pred1(subject) -> pred2(subject)

            # Calculate confidence based on co-occurrence
            tv = AtomSpace::SimpleTruthValue.new(0.8, confidence_threshold)

            # Create evaluation links for antecedent and consequent
            args_link = atomspace.add_list_link([subject])
            antecedent = atomspace.add_evaluation_link(pred1, args_link)
            consequent = atomspace.add_evaluation_link(pred2, args_link)

            implication = atomspace.add_link(
              AtomSpace::AtomType::IMPLICATION_LINK,
              [antecedent, consequent],
              tv
            )

            learned << implication
          end
        end
      end

      CogUtil::Logger.info("Learning: Generated #{learned.size} implications")
      learned
    end
  end

  # Main OpenCog reasoner combining all components
  class OpenCogReasoner
    getter atomspace : AtomSpace::AtomSpace

    def initialize(@atomspace : AtomSpace::AtomSpace)
    end

    # Perform comprehensive reasoning
    def reason(steps : Int32 = 10) : Array(AtomSpace::Atom)
      all_results = [] of AtomSpace::Atom

      # Apply core reasoning
      reasoning_results = Reasoning.infer(@atomspace, steps)
      all_results.concat(reasoning_results)

      # Learn new patterns
      learning_results = Learning.learn_implications(@atomspace)
      all_results.concat(learning_results)

      CogUtil::Logger.info("OpenCog: Total reasoning results: #{all_results.size}")
      all_results
    end

    # Query the knowledge base
    def query(pattern : AtomSpace::Atom) : Array(Query::QueryResult)
      Query.query_pattern(@atomspace, pattern)
    end

    # Check if a goal can be achieved
    def can_achieve?(goal : AtomSpace::Atom) : Bool
      Reasoning.can_conclude?(@atomspace, goal)
    end
  end

  # Convenience method to create OpenCog reasoner
  def self.create_reasoner(atomspace : AtomSpace::AtomSpace) : OpenCogReasoner
    OpenCogReasoner.new(atomspace)
  end
end
