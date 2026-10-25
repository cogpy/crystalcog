# Crystal implementation of OpenCog Query Language (OQL)
# Provides SQL-like query interface for AtomSpace operations
#
# Supports syntax similar to:
# SELECT ?var WHERE { pattern }
# with variables, constraints, and boolean operations

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "../pattern_matching/pattern_matching"

module OpenCog
  module QueryLanguage
    VERSION = "0.1.0"

    # Query Language exceptions
    class QueryLanguageException < CogUtil::OpenCogException
    end

    class QueryParseException < QueryLanguageException
    end

    class QueryExecutionException < QueryLanguageException
    end

    # Represents a parsed query variable
    struct QueryVariable
      getter name : String
      getter type : AtomSpace::AtomType?

      def initialize(@name : String, @type : AtomSpace::AtomType? = nil)
      end

      def to_s(io : IO)
        io << "$#{@name}"
        io << ":#{@type}" if @type
      end
    end

    # Represents a query clause (part of WHERE condition)
    abstract class QueryClause
      abstract def to_atoms(atomspace : AtomSpace::AtomSpace, var_map : Hash(String, AtomSpace::Atom)) : Array(AtomSpace::Atom)
      abstract def to_s(io : IO)
    end

    # Atom clause: represents a concrete atom or pattern
    class AtomClause < QueryClause
      getter atom : AtomSpace::Atom

      def initialize(@atom : AtomSpace::Atom)
      end

      def to_atoms(atomspace : AtomSpace::AtomSpace, var_map : Hash(String, AtomSpace::Atom)) : Array(AtomSpace::Atom)
        [substitute_variables(@atom, var_map)]
      end

      private def substitute_variables(atom : AtomSpace::Atom, var_map : Hash(String, AtomSpace::Atom)) : AtomSpace::Atom
        if atom.type == AtomSpace::AtomType::VARIABLE_NODE && atom.responds_to?(:name)
          var_name = atom.name.lstrip("$")
          var_map[var_name]? || atom
        elsif atom.link?
          original = atom.outgoing
          substituted = original.map { |child| substitute_variables(child, var_map) }
          return atom if substituted.zip(original).all? { |a, b| a.same?(b) }
          AtomSpace::Link.new(atom.type, substituted, atom.truth_value)
        else
          atom
        end
      end

      def to_s(io : IO)
        io << "AtomClause(#{@atom})"
      end
    end

    # Triple clause: subject predicate object pattern
    class TripleClause < QueryClause
      getter subject : String | AtomSpace::Atom
      getter predicate : String | AtomSpace::Atom
      getter object : String | AtomSpace::Atom

      def initialize(@subject : String | AtomSpace::Atom,
                     @predicate : String | AtomSpace::Atom,
                     @object : String | AtomSpace::Atom)
      end

      def to_atoms(atomspace : AtomSpace::AtomSpace, var_map : Hash(String, AtomSpace::Atom)) : Array(AtomSpace::Atom)
        # Convert triple to evaluation link pattern
        subj_atom = resolve_term(@subject, atomspace, var_map)
        pred_atom = resolve_term(@predicate, atomspace, var_map)
        obj_atom = resolve_term(@object, atomspace, var_map)

        # Create evaluation link: (EvaluationLink predicate (ListLink subject object))
        list_link = atomspace.add_list_link([subj_atom, obj_atom])
        eval_link = atomspace.add_evaluation_link(pred_atom, list_link)

        [eval_link]
      end

      private def resolve_term(term : String | AtomSpace::Atom, atomspace : AtomSpace::AtomSpace, var_map : Hash(String, AtomSpace::Atom)) : AtomSpace::Atom
        case term
        when String
          if term.starts_with?("$")
            var_name = term.lstrip("$")
            var_map[var_name]? || atomspace.add_node(AtomSpace::AtomType::VARIABLE_NODE, term)
          else
            # Try to find existing atom or create concept node
            existing = atomspace.get_nodes_by_name(term, AtomSpace::AtomType::CONCEPT_NODE).first?
            existing || atomspace.add_concept_node(term)
          end
        when AtomSpace::Atom
          term
        else
          raise QueryLanguageException.new("Invalid term type: #{term}")
        end
      end

      def to_s(io : IO)
        io << "TripleClause(#{@subject} #{@predicate} #{@object})"
      end
    end

    # Inheritance clause: child inherits_from parent
    class InheritanceClause < QueryClause
      getter child : String | AtomSpace::Atom
      getter parent : String | AtomSpace::Atom

      def initialize(@child : String | AtomSpace::Atom, @parent : String | AtomSpace::Atom)
      end

      def to_atoms(atomspace : AtomSpace::AtomSpace, var_map : Hash(String, AtomSpace::Atom)) : Array(AtomSpace::Atom)
        child_atom = resolve_term(@child, atomspace, var_map)
        parent_atom = resolve_term(@parent, atomspace, var_map)

        inheritance = atomspace.add_inheritance_link(child_atom, parent_atom)
        [inheritance]
      end

      private def resolve_term(term : String | AtomSpace::Atom, atomspace : AtomSpace::AtomSpace, var_map : Hash(String, AtomSpace::Atom)) : AtomSpace::Atom
        case term
        when String
          if term.starts_with?("$")
            var_name = term.lstrip("$")
            var_map[var_name]? || atomspace.add_node(AtomSpace::AtomType::VARIABLE_NODE, term)
          else
            existing = atomspace.get_nodes_by_name(term, AtomSpace::AtomType::CONCEPT_NODE).first?
            existing || atomspace.add_concept_node(term)
          end
        when AtomSpace::Atom
          term
        else
          raise QueryLanguageException.new("Invalid term type: #{term}")
        end
      end

      def to_s(io : IO)
        io << "InheritanceClause(#{@child} -> #{@parent})"
      end
    end

    # Represents a complete parsed query
    class ParsedQuery
      getter variables : Array(QueryVariable)
      getter clauses : Array(QueryClause)
      getter optional_clauses : Array(QueryClause)

      def initialize(@variables : Array(QueryVariable),
                     @clauses : Array(QueryClause),
                     @optional_clauses : Array(QueryClause) = [] of QueryClause)
      end

      def to_s(io : IO)
        io << "ParsedQuery("
        io << "vars: #{@variables.map(&.name).join(", ")}, "
        io << "clauses: #{@clauses.size}"
        io << ")"
      end
    end

    # Basic query parser for SQL-like syntax
    class QueryParser
      # Parse a query string into structured form
      def self.parse(query_string : String) : ParsedQuery
        query_string = query_string.strip

        # Very basic parsing - would need proper lexer/parser for production
        unless query_string.upcase.starts_with?("SELECT")
          raise QueryParseException.new("Query must start with SELECT")
        end

        # Extract variables from SELECT clause
        select_match = query_string.match(/SELECT\s+([^W]+)\s+WHERE/i)
        unless select_match
          raise QueryParseException.new("Invalid SELECT syntax")
        end

        var_string = select_match[1].strip
        variables = parse_variables(var_string)

        # Extract WHERE clause content
        where_match = query_string.match(/WHERE\s*\{([^}]+)\}/i)
        unless where_match
          raise QueryParseException.new("Missing WHERE clause")
        end

        where_content = where_match[1].strip
        clauses = parse_where_clauses(where_content)

        ParsedQuery.new(variables, clauses)
      end

      private def self.parse_variables(var_string : String) : Array(QueryVariable)
        variables = Array(QueryVariable).new

        var_string.split(",").each do |var_spec|
          var_spec = var_spec.strip
          if var_spec.starts_with?("$")
            # Extract variable name and optional type
            if var_spec.includes?(":")
              parts = var_spec.split(":", 2)
              name = parts[0].lstrip("$")
              type_name = parts[1].upcase

              # Map type names to AtomType enum
              atom_type = case type_name
                          when "CONCEPT"
                            AtomSpace::AtomType::CONCEPT_NODE
                          when "PREDICATE"
                            AtomSpace::AtomType::PREDICATE_NODE
                          when "NODE"
                            AtomSpace::AtomType::NODE
                          when "LINK"
                            AtomSpace::AtomType::LINK
                          else
                            nil
                          end

              variables << QueryVariable.new(name, atom_type)
            else
              name = var_spec.lstrip("$")
              variables << QueryVariable.new(name)
            end
          else
            raise QueryParseException.new("Variables must start with $ : #{var_spec}")
          end
        end

        variables
      end

      private def self.parse_where_clauses(where_content : String) : Array(QueryClause)
        clauses = Array(QueryClause).new

        # Split by periods or newlines to get individual clauses
        clause_strings = where_content.split(/[.\n]/).map(&.strip).reject(&.empty?)

        clause_strings.each do |clause_str|
          clause = parse_single_clause(clause_str)
          clauses << clause if clause
        end

        clauses
      end

      private def self.parse_single_clause(clause_str : String) : QueryClause?
        clause_str = clause_str.strip
        return nil if clause_str.empty?

        # Inheritance first: the generic triple pattern would also match ISA
        if isa_match = clause_str.match(/(\$?\w+)\s+(?:ISA|inherits_from|->)\s+(\$?\w+)/i)
          child = isa_match[1]
          parent = isa_match[2]

          return InheritanceClause.new(child, parent)
        end

        # Try to parse as triple pattern: subject predicate object
        if triple_match = clause_str.match(/(\$?\w+)\s+(\$?\w+)\s+(\$?\w+)/)
          subject = triple_match[1]
          predicate = triple_match[2]
          object = triple_match[3]

          return TripleClause.new(subject, predicate, object)
        end

        # If we can't parse it, create a note for debugging
        CogUtil::Logger.warn("Could not parse clause: #{clause_str}")
        nil
      end
    end

    # Query execution engine
    class QueryExecutor
      getter atomspace : AtomSpace::AtomSpace
      getter pattern_matcher : PatternMatching::PatternMatcher

      def initialize(@atomspace : AtomSpace::AtomSpace)
        @pattern_matcher = PatternMatching::PatternMatcher.new(@atomspace)
      end

      # Execute a parsed query and return results
      def execute(query : ParsedQuery) : Array(Query::QueryResult)
        results = Array(Query::QueryResult).new

        # Create variable map for binding
        var_map = Hash(String, AtomSpace::Atom).new

        # Convert query clauses to atoms in atomspace
        pattern_atoms = Array(AtomSpace::Atom).new
        query.clauses.each do |clause|
          clause_atoms = clause.to_atoms(@atomspace, var_map)
          pattern_atoms.concat(clause_atoms)
        end

        if pattern_atoms.empty?
          return results
        end

        # Typed query variables become constraints on every clause pattern.
        type_constraints = query.variables.compact_map do |var|
          next unless allowed = var.type
          var_atom = @atomspace.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$#{var.name}")
          PatternMatching::TypeConstraint.new(var_atom, allowed)
        end

        # Match each clause on its own, then natural-join the solutions on
        # shared variable names (a conjunctive query).
        solutions = [{Hash(String, AtomSpace::Atom).new, Array(AtomSpace::Atom).new}]
        pattern_atoms.each do |template|
          pattern = PatternMatching::Pattern.new(template)
          type_constraints.each { |c| pattern.add_constraint(c) }

          clause_solutions = @pattern_matcher.match(pattern).map do |match_result|
            bindings = Hash(String, AtomSpace::Atom).new
            match_result.bindings.each do |var_atom, bound_atom|
              if var_atom.type == AtomSpace::AtomType::VARIABLE_NODE
                bindings[var_atom.name.lstrip("$")] = bound_atom
              end
            end
            {bindings, match_result.matched_atoms}
          end

          solutions = solutions.flat_map do |(bound, matched)|
            clause_solutions.compact_map do |(clause_bound, clause_matched)|
              next unless clause_bound.all? { |name, atom| (existing = bound[name]?).nil? || existing == atom }
              {bound.merge(clause_bound), matched + clause_matched}
            end
          end
          break if solutions.empty?
        end

        solutions.each do |(bindings, matched)|
          results << Query::QueryResult.new(bindings, calculate_confidence(matched))
        end

        # Sort by confidence descending
        results.sort! { |a, b| b.confidence <=> a.confidence }
        results
      end

      private def calculate_confidence(matched_atoms : Array(AtomSpace::Atom)) : Float64
        return 0.0 if matched_atoms.empty?

        # Average confidence of all matched atoms
        total_confidence = matched_atoms.sum { |atom| atom.truth_value.confidence }
        total_confidence / matched_atoms.size
      end
    end

    # Main query language interface
    class QueryLanguageInterface
      getter atomspace : AtomSpace::AtomSpace
      getter executor : QueryExecutor

      def initialize(@atomspace : AtomSpace::AtomSpace)
        @executor = QueryExecutor.new(@atomspace)
      end

      # Execute a query string and return results
      def query(query_string : String) : Array(Query::QueryResult)
        begin
          parsed_query = QueryParser.parse(query_string)
          CogUtil::Logger.debug("Parsed query: #{parsed_query}")

          results = @executor.execute(parsed_query)
          CogUtil::Logger.info("Query returned #{results.size} results")

          results
        rescue ex : QueryLanguageException
          CogUtil::Logger.error("Query language error: #{ex.message}")
          raise ex
        rescue ex : Exception
          CogUtil::Logger.error("Unexpected query error: #{ex.message}")
          raise QueryExecutionException.new("Query execution failed: #{ex.message}")
        end
      end

      # Convenience method for simple queries
      def find_all(concept_name : String) : Array(Query::QueryResult)
        query("SELECT $x WHERE { $x ISA #{concept_name} }")
      end

      # Find relationships
      def find_relations(subject : String, predicate : String) : Array(Query::QueryResult)
        query("SELECT $obj WHERE { #{subject} #{predicate} $obj }")
      end

      # Find common properties
      def find_common_properties(entity1 : String, entity2 : String) : Array(Query::QueryResult)
        query("SELECT $prop WHERE { #{entity1} $prop $x . #{entity2} $prop $x }")
      end
    end

    # Initialize the QueryLanguage subsystem
    def self.initialize
      CogUtil::Logger.info("QueryLanguage #{VERSION} initializing")

      # Initialize dependencies
      CogUtil.initialize unless @@cogutil_initialized
      AtomSpace.initialize unless @@atomspace_initialized
      PatternMatching.initialize unless @@pattern_matching_initialized

      CogUtil::Logger.info("QueryLanguage #{VERSION} initialized")
    end

    # Track initialization state
    @@cogutil_initialized = false
    @@atomspace_initialized = false
    @@pattern_matching_initialized = false

    # Module-level convenience methods
    def self.create_interface(atomspace : AtomSpace::AtomSpace) : QueryLanguageInterface
      QueryLanguageInterface.new(atomspace)
    end

    def self.parse_query(query_string : String) : ParsedQuery
      QueryParser.parse(query_string)
    end
  end
end
