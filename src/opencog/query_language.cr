# Crystal implementation of OpenCog Query Language (OQL)
# Provides SQL-like query interface for AtomSpace operations
#
# Grammar (keywords in any case; `#` starts a comment):
#
#   query    := SELECT [DISTINCT] ( "*" | variable { [","] variable } )
#               WHERE "{" clauses "}" [ LIMIT integer ]
#   variable := "$" name [ ":" type ]
#   clauses  := clause { ( "." | newline ) clause }
#   clause   := term ( ISA | inherits_from | "->" ) term
#             | term term term                    (subject predicate object)
#             | OPTIONAL "{" clauses "}"
#   term     := "$" name | name | "quoted name"
#
# A type is CONCEPT, PREDICATE, NODE, LINK or any AtomType name.

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
        pred_atom = resolve_term(@predicate, atomspace, var_map, AtomSpace::AtomType::PREDICATE_NODE)
        obj_atom = resolve_term(@object, atomspace, var_map)

        # Create evaluation link: (EvaluationLink predicate (ListLink subject object))
        list_link = atomspace.add_list_link([subj_atom, obj_atom])
        eval_link = atomspace.add_evaluation_link(pred_atom, list_link)

        [eval_link]
      end

      # A name stands for the node of the preferred type with that name,
      # else for any node with that name, else for a new node of the
      # preferred type. A triple's predicate prefers a PredicateNode.
      private def resolve_term(term : String | AtomSpace::Atom, atomspace : AtomSpace::AtomSpace, var_map : Hash(String, AtomSpace::Atom),
                               preferred : AtomSpace::AtomType = AtomSpace::AtomType::CONCEPT_NODE) : AtomSpace::Atom
        case term
        when String
          if term.starts_with?("$")
            var_name = term.lstrip("$")
            var_map[var_name]? || atomspace.add_node(AtomSpace::AtomType::VARIABLE_NODE, term)
          else
            atomspace.get_nodes_by_name(term, preferred).first? ||
              atomspace.get_nodes_by_name(term).first? ||
              atomspace.add_node(preferred, term)
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
      # Keep one result per distinct set of selected values.
      getter? distinct : Bool
      # Return at most this many results.
      getter limit : Int32?

      def initialize(@variables : Array(QueryVariable),
                     @clauses : Array(QueryClause),
                     @optional_clauses : Array(QueryClause) = [] of QueryClause,
                     @distinct : Bool = false, @limit : Int32? = nil)
      end

      def to_s(io : IO)
        io << "ParsedQuery("
        io << "vars: #{@variables.map(&.name).join(", ")}, "
        io << "clauses: #{@clauses.size}"
        io << ")"
      end
    end

    # One lexical unit of a query, with where it starts.
    record Token, kind : Symbol, text : String, line : Int32, column : Int32 do
      def describe : String
        case kind
        when :end      then "the end of the query"
        when :newline  then "a line break"
        when :string   then %("#{text}")
        when :variable then "$#{text}"
        else                text.inspect
        end
      end
    end

    # Splits a query into tokens: keywords, `$variables`, names, quoted
    # names, integers and punctuation. Line breaks are tokens because they
    # separate clauses.
    class QueryLexer
      KEYWORDS = {"SELECT", "DISTINCT", "WHERE", "ISA", "OPTIONAL", "LIMIT"}

      def initialize(@source : String)
        @chars = @source.chars
        @position = 0
        @line = 1
        @column = 1
      end

      def tokens : Array(Token)
        result = [] of Token
        loop do
          token = next_token
          result << token
          break if token.kind == :end
        end
        result
      end

      private def peek(offset = 0) : Char?
        @chars[@position + offset]?
      end

      private def advance : Char
        char = @chars[@position]
        @position += 1
        if char == '\n'
          @line += 1
          @column = 1
        else
          @column += 1
        end
        char
      end

      private def name_char?(char : Char?) : Bool
        !char.nil? && (char.alphanumeric? || char == '_')
      end

      private def error(message : String, line = @line, column = @column) : NoReturn
        raise QueryParseException.new("#{message} at line #{line}, column #{column}")
      end

      private def next_token : Token
        # Blanks and comments mean nothing; a line break does.
        loop do
          char = peek
          if char == ' ' || char == '\t' || char == '\r'
            advance
          elsif char == '#'
            while (following = peek) && following != '\n'
              advance
            end
          else
            break
          end
        end

        line, column = @line, @column
        char = peek
        return Token.new(:end, "", line, column) if char.nil?

        case char
        when '\n'
          advance
          Token.new(:newline, "\n", line, column)
        when '{', '}', '.', ',', ':', '*'
          advance
          Token.new(:punctuation, char.to_s, line, column)
        when '-'
          error("expected '->'") unless peek(1) == '>'
          advance
          advance
          Token.new(:punctuation, "->", line, column)
        when '$'
          advance
          error("a variable needs a name after '$'") unless name_char?(peek)
          Token.new(:variable, read_name, line, column)
        when '"'
          Token.new(:string, read_string(line, column), line, column)
        else
          error("unexpected character #{char.inspect}") unless name_char?(char)
          text = read_name
          if text.each_char.all?(&.ascii_number?)
            Token.new(:integer, text, line, column)
          elsif KEYWORDS.includes?(text.upcase)
            Token.new(:keyword, text.upcase, line, column)
          else
            Token.new(:name, text, line, column)
          end
        end
      end

      # Letters, digits and underscores, with single hyphens inside
      # (`well-known`), but never the `-` of an arrow.
      private def read_name : String
        String.build do |io|
          loop do
            char = peek
            if name_char?(char)
              io << advance
            elsif char == '-' && name_char?(peek(1))
              io << advance
            else
              break
            end
          end
        end
      end

      private def read_string(line : Int32, column : Int32) : String
        advance # opening quote
        String.build do |io|
          loop do
            char = peek
            error("unterminated quoted name", line, column) if char.nil? || char == '\n'
            advance
            break if char == '"'
            if char == '\\'
              escaped = peek || error("unterminated quoted name", line, column)
              advance
              io << case escaped
              when 'n' then '\n'
              when 't' then '\t'
              else          escaped
              end
            else
              io << char
            end
          end
        end
      end
    end

    # Recursive-descent parser for the grammar at the top of this file.
    # Every error names what was expected, what was found and where.
    class QueryParser
      TYPE_ALIASES = {
        "CONCEPT"   => AtomSpace::AtomType::CONCEPT_NODE,
        "PREDICATE" => AtomSpace::AtomType::PREDICATE_NODE,
        "NODE"      => AtomSpace::AtomType::NODE,
        "LINK"      => AtomSpace::AtomType::LINK,
      }

      # Parse a query string into structured form
      def self.parse(query_string : String) : ParsedQuery
        new(QueryLexer.new(query_string).tokens).parse
      end

      def initialize(@tokens : Array(Token))
        @position = 0
      end

      def parse : ParsedQuery
        skip_newlines
        unless keyword?("SELECT")
          raise QueryParseException.new("Query must start with SELECT, found #{current.describe} at #{where(current)}")
        end
        advance
        skip_newlines

        distinct = false
        if keyword?("DISTINCT")
          distinct = true
          advance
          skip_newlines
        end

        select_all = false
        variables = [] of QueryVariable
        if punctuation?("*")
          select_all = true
          advance
        else
          variables = parse_variables
        end
        skip_newlines

        unless keyword?("WHERE")
          raise QueryParseException.new("Missing WHERE clause: expected WHERE, found #{current.describe} at #{where(current)}")
        end
        advance
        skip_newlines

        clauses = [] of QueryClause
        optional = [] of QueryClause
        used = [] of String
        parse_block(clauses, optional, used, allow_optional: true)
        fail("WHERE needs at least one clause", @tokens[@position - 1]) if clauses.empty?

        skip_newlines
        limit = nil
        if keyword?("LIMIT")
          advance
          fail("expected a number after LIMIT, found #{current.describe}") unless current.kind == :integer
          limit = current.text.to_i? || fail("LIMIT #{current.text} is too large")
          advance
          skip_newlines
        end
        fail("expected the end of the query, found #{current.describe}") unless current.kind == :end

        if select_all
          variables = used.map { |name| QueryVariable.new(name) }
        else
          variables.each do |variable|
            next if used.includes?(variable.name)
            raise QueryParseException.new("$#{variable.name} is selected but does not appear in WHERE")
          end
        end

        ParsedQuery.new(variables, clauses, optional, distinct, limit)
      end

      private def current : Token
        @tokens[@position]
      end

      private def advance : Token
        token = @tokens[@position]
        @position += 1 unless token.kind == :end
        token
      end

      private def where(token : Token) : String
        "line #{token.line}, column #{token.column}"
      end

      private def fail(message : String, token : Token = current) : NoReturn
        raise QueryParseException.new("#{message} at #{where(token)}")
      end

      private def keyword?(word : String) : Bool
        current.kind == :keyword && current.text == word
      end

      private def punctuation?(text : String) : Bool
        current.kind == :punctuation && current.text == text
      end

      private def skip_newlines : Nil
        while current.kind == :newline
          advance
        end
      end

      private def parse_variables : Array(QueryVariable)
        variables = [] of QueryVariable
        loop do
          skip_newlines
          unless current.kind == :variable
            if current.kind == :name
              raise QueryParseException.new("Variables must start with $ : #{current.text} at #{where(current)}")
            end
            fail("expected a variable such as $x, found #{current.describe}")
          end
          name = advance.text
          type = nil
          if punctuation?(":")
            advance
            fail("expected a type after ':', found #{current.describe}") unless current.kind == :name
            type = parse_type(advance)
          end
          fail("$#{name} is selected twice", @tokens[@position - 1]) if variables.any? { |variable| variable.name == name }
          variables << QueryVariable.new(name, type)

          advance if punctuation?(",")
          skip_newlines
          break unless current.kind == :variable
        end
        variables
      end

      private def parse_type(token : Token) : AtomSpace::AtomType
        TYPE_ALIASES[token.text.upcase]? ||
          AtomSpace::AtomType.parse?(token.text) ||
          fail("unknown type #{token.text}", token)
      end

      # "{" clause { separator clause } "}"
      private def parse_block(clauses : Array(QueryClause), optional : Array(QueryClause),
                              used : Array(String), allow_optional : Bool) : Nil
        fail("expected '{', found #{current.describe}") unless punctuation?("{")
        advance

        loop do
          while current.kind == :newline || punctuation?(".")
            advance
          end
          break if punctuation?("}")
          fail("expected '}' to close the block, found #{current.describe}") if current.kind == :end

          if keyword?("OPTIONAL")
            fail("OPTIONAL cannot be nested") unless allow_optional
            advance
            skip_newlines
            before = optional.size
            parse_block(optional, optional, used, allow_optional: false)
            fail("OPTIONAL needs at least one clause", @tokens[@position - 1]) if optional.size == before
          else
            clauses << parse_clause(used)
          end

          # A clause ends at a separator or at the closing brace.
          fail("expected '}' to close the block, found #{current.describe}") if current.kind == :end
          unless current.kind == :newline || punctuation?(".") || punctuation?("}")
            fail("expected '.', a line break or '}' after the clause, found #{current.describe}")
          end
        end
        advance # the closing brace
      end

      private def parse_clause(used : Array(String)) : QueryClause
        first = parse_term(used)
        if keyword?("ISA") || punctuation?("->") || (current.kind == :name && current.text.downcase == "inherits_from")
          advance
          return InheritanceClause.new(first, parse_term(used))
        end

        predicate = parse_term(used, "a predicate, ISA or '->'")
        object = parse_term(used, "the object of the triple")
        TripleClause.new(first, predicate, object)
      end

      # A term as the clause classes take it: "$name" for a variable, the
      # bare name otherwise.
      private def parse_term(used : Array(String), expected : String = "a term") : String
        token = current
        case token.kind
        when :variable
          advance
          used << token.text unless used.includes?(token.text)
          "$#{token.text}"
        when :name, :string, :integer
          advance
          token.text
        else
          fail("expected #{expected}, found #{token.describe}")
        end
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
          clause_solutions = solve(template, type_constraints)

          solutions = solutions.flat_map do |(bound, matched)|
            clause_solutions.compact_map do |(clause_bound, clause_matched)|
              next unless clause_bound.all? { |name, atom| (existing = bound[name]?).nil? || existing == atom }
              {bound.merge(clause_bound), matched + clause_matched}
            end
          end
          break if solutions.empty?
        end

        # OPTIONAL clauses add bindings where they match and leave a
        # solution as it is where they do not (a left join).
        query.optional_clauses.each do |clause|
          clause.to_atoms(@atomspace, var_map).each do |template|
            optional_solutions = solve(template, type_constraints)
            solutions = solutions.flat_map do |(bound, matched)|
              extended = optional_solutions.compact_map do |(clause_bound, clause_matched)|
                next unless clause_bound.all? { |name, atom| (existing = bound[name]?).nil? || existing == atom }
                {bound.merge(clause_bound), matched + clause_matched}
              end
              extended.empty? ? [{bound, matched}] : extended
            end
          end
        end

        # Results carry the selected variables only.
        selected = query.variables.map(&.name)
        solutions.each do |(bindings, matched)|
          results << Query::QueryResult.new(bindings.select(selected), calculate_confidence(matched))
        end

        # Sort by confidence descending
        results.sort! { |a, b| b.confidence <=> a.confidence }

        if query.distinct?
          seen = Set(Array(AtomSpace::Handle?)).new
          results.select! { |result| seen.add?(selected.map { |name| result.bindings[name]?.try(&.handle) }) }
        end
        query.limit.try { |limit| results = results.first(limit) }

        results
      end

      # Every way one clause pattern matches: variable bindings by name and
      # the atoms matched.
      private def solve(template : AtomSpace::Atom, type_constraints) : Array({Hash(String, AtomSpace::Atom), Array(AtomSpace::Atom)})
        pattern = PatternMatching::Pattern.new(template)
        type_constraints.each { |c| pattern.add_constraint(c) }

        @pattern_matcher.match(pattern).map do |match_result|
          bindings = Hash(String, AtomSpace::Atom).new
          match_result.bindings.each do |var_atom, bound_atom|
            if var_atom.type == AtomSpace::AtomType::VARIABLE_NODE
              bindings[var_atom.name.lstrip("$")] = bound_atom
            end
          end
          {bindings, match_result.matched_atoms}
        end
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
