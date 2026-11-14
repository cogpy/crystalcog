# Crystal implementation of OpenCog Query Language (OQL)
# Provides SQL-like query interface for AtomSpace operations
#
# Grammar (keywords in any case; `#` starts a comment):
#
#   query     := SELECT [DISTINCT] ( "*" | variable { [","] variable } )
#                WHERE block { UNION block }
#                [ ORDER BY key { "," key } ] [ LIMIT integer ]
#   variable  := "$" name [ ":" type ]
#   block     := "{" clause { ( "." | newline ) clause } "}"
#   clause    := term ( ISA | inherits_from | "->" ) term
#              | term term term                    (subject predicate object)
#              | OPTIONAL "{" clauses "}"
#              | FILTER "(" condition ")"
#   term      := "$" name | name | "quoted name"
#   condition := condition OR condition | condition AND condition
#              | NOT condition | "(" condition ")"
#              | value ( "=" | "!=" | "<" | "<=" | ">" | ">=" ) value
#              | CONTAINS "(" value "," value ")" | BOUND "(" "$" name ")"
#   value     := "$" name | name | "quoted text" | number
#              | ( NAME | TYPE | STRENGTH | CONFIDENCE ) "(" "$" name ")"
#   key       := value [ ASC | DESC ]
#
# A type is CONCEPT, PREDICATE, NODE, LINK or any AtomType name. Only
# SELECT, DISTINCT, WHERE, ISA, OPTIONAL and LIMIT are reserved; the other
# keywords are read as such only where the grammar expects them, so `order`
# or `filter` can still name a concept.
#
# Running a query does not change the AtomSpace: its patterns are built
# beside it.

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

    # The atom a clause term stands for, without adding anything to the
    # AtomSpace. A `$name` is a variable, one node per name within a query.
    # Another name is the stored node of the preferred type with that name,
    # else any stored node with that name, else a new node beside the
    # AtomSpace (which then matches nothing stored).
    def self.resolve_term(term : String | AtomSpace::Atom, atomspace : AtomSpace::AtomSpace,
                          var_map : Hash(String, AtomSpace::Atom),
                          preferred : AtomSpace::AtomType = AtomSpace::AtomType::CONCEPT_NODE) : AtomSpace::Atom
      return term if term.is_a?(AtomSpace::Atom)

      if term.starts_with?("$")
        var_map[term.lstrip("$")] ||= AtomSpace::VariableNode.new(term)
      else
        atomspace.get_nodes_by_name(term, preferred).first? ||
          atomspace.get_nodes_by_name(term).first? ||
          AtomSpace::Node.new(preferred, term)
      end
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

      # (EvaluationLink predicate (ListLink subject object)), as a pattern.
      # The predicate prefers a PredicateNode of its name.
      def to_atoms(atomspace : AtomSpace::AtomSpace, var_map : Hash(String, AtomSpace::Atom)) : Array(AtomSpace::Atom)
        subj_atom = QueryLanguage.resolve_term(@subject, atomspace, var_map)
        pred_atom = QueryLanguage.resolve_term(@predicate, atomspace, var_map, AtomSpace::AtomType::PREDICATE_NODE)
        obj_atom = QueryLanguage.resolve_term(@object, atomspace, var_map)

        list_link = AtomSpace::Link.new(AtomSpace::AtomType::LIST_LINK, [subj_atom, obj_atom])
        [AtomSpace::Link.new(AtomSpace::AtomType::EVALUATION_LINK, [pred_atom, list_link.as(AtomSpace::Atom)]).as(AtomSpace::Atom)]
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
        child_atom = QueryLanguage.resolve_term(@child, atomspace, var_map)
        parent_atom = QueryLanguage.resolve_term(@parent, atomspace, var_map)

        [AtomSpace::Link.new(AtomSpace::AtomType::INHERITANCE_LINK, [child_atom, parent_atom]).as(AtomSpace::Atom)]
      end

      def to_s(io : IO)
        io << "InheritanceClause(#{@child} -> #{@parent})"
      end
    end

    # What a FILTER or ORDER BY looks at: a variable, a literal, or a
    # property of the atom a variable is bound to.
    record QueryValue, kind : Symbol, text : String, number : Float64 = 0.0 do
      # The value for one result: text, a number, or nil when the variable
      # is not bound (as after an OPTIONAL that did not match).
      def evaluate(bindings : Hash(String, AtomSpace::Atom)) : String | Float64 | Nil
        case kind
        when :text   then text
        when :number then number
        else
          atom = bindings[text]? || return nil
          case kind
          when :strength   then atom.truth_value.strength
          when :confidence then atom.truth_value.confidence
          when :type       then atom.type.to_s
          else                  atom.is_a?(AtomSpace::Node) ? atom.name : atom.to_s
          end
        end
      end

      def to_s(io : IO)
        case kind
        when :variable then io << '$' << text
        when :text     then io << text.inspect
        when :number   then io << number
        else                io << kind.to_s.upcase << "($" << text << ')'
        end
      end
    end

    # A FILTER condition, checked against each candidate result.
    abstract class QueryCondition
      abstract def holds?(bindings : Hash(String, AtomSpace::Atom)) : Bool
    end

    class ComparisonCondition < QueryCondition
      def initialize(@left : QueryValue, @operator : String, @right : QueryValue)
      end

      # Two numbers, or a number and text that reads as one, compare as
      # numbers; anything else compares as text. An unbound side is false.
      def holds?(bindings : Hash(String, AtomSpace::Atom)) : Bool
        left = @left.evaluate(bindings)
        right = @right.evaluate(bindings)
        return false if left.nil? || right.nil?

        left_number = left.is_a?(Float64) ? left : left.to_f?
        right_number = right.is_a?(Float64) ? right : right.to_f?
        order = if (left.is_a?(Float64) || right.is_a?(Float64)) && left_number && right_number
                  left_number <=> right_number
                elsif left.is_a?(String) && right.is_a?(String)
                  left <=> right
                else
                  # A number against text that is not one: only (in)equality
                  # has an answer, and they are not equal.
                  return @operator == "!="
                end
        return false if order.nil? # NaN

        case @operator
        when "="  then order == 0
        when "!=" then order != 0
        when "<"  then order < 0
        when "<=" then order <= 0
        when ">"  then order > 0
        else           order >= 0
        end
      end

      def to_s(io : IO)
        io << @left << ' ' << @operator << ' ' << @right
      end
    end

    class ContainsCondition < QueryCondition
      def initialize(@text : QueryValue, @part : QueryValue)
      end

      def holds?(bindings : Hash(String, AtomSpace::Atom)) : Bool
        text = @text.evaluate(bindings)
        part = @part.evaluate(bindings)
        return false if text.nil? || part.nil?
        text.to_s.includes?(part.to_s)
      end

      def to_s(io : IO)
        io << "CONTAINS(" << @text << ", " << @part << ')'
      end
    end

    class BoundCondition < QueryCondition
      def initialize(@variable : String)
      end

      def holds?(bindings : Hash(String, AtomSpace::Atom)) : Bool
        bindings.has_key?(@variable)
      end

      def to_s(io : IO)
        io << "BOUND($" << @variable << ')'
      end
    end

    class NotCondition < QueryCondition
      def initialize(@inner : QueryCondition)
      end

      def holds?(bindings : Hash(String, AtomSpace::Atom)) : Bool
        !@inner.holds?(bindings)
      end

      def to_s(io : IO)
        io << "NOT (" << @inner << ')'
      end
    end

    class LogicalCondition < QueryCondition
      def initialize(@left : QueryCondition, @conjunction : Bool, @right : QueryCondition)
      end

      def holds?(bindings : Hash(String, AtomSpace::Atom)) : Bool
        @conjunction ? @left.holds?(bindings) && @right.holds?(bindings) : @left.holds?(bindings) || @right.holds?(bindings)
      end

      def to_s(io : IO)
        io << '(' << @left << (@conjunction ? " AND " : " OR ") << @right << ')'
      end
    end

    # One "{ ... }" of a query: what must match, what may, and what the
    # results must satisfy.
    class QueryBlock
      getter clauses = [] of QueryClause
      getter optional_clauses = [] of QueryClause
      getter filters = [] of QueryCondition
    end

    # One ORDER BY key.
    record QueryOrder, value : QueryValue, descending : Bool

    # Represents a complete parsed query
    class ParsedQuery
      getter variables : Array(QueryVariable)
      # The alternatives joined by UNION; a query without UNION has one.
      getter blocks : Array(QueryBlock)
      # Keep one result per distinct set of selected values.
      getter? distinct : Bool
      # Return at most this many results.
      getter limit : Int32?
      getter order : Array(QueryOrder)

      def initialize(@variables : Array(QueryVariable), @blocks : Array(QueryBlock),
                     @distinct : Bool = false, @limit : Int32? = nil,
                     @order : Array(QueryOrder) = [] of QueryOrder)
      end

      # A query of plain clauses, as built by code rather than parsed.
      def self.new(variables : Array(QueryVariable), clauses : Array(QueryClause),
                   optional_clauses : Array(QueryClause) = [] of QueryClause,
                   distinct : Bool = false, limit : Int32? = nil)
        block = QueryBlock.new
        block.clauses.concat(clauses)
        block.optional_clauses.concat(optional_clauses)
        new(variables, [block], distinct, limit)
      end

      # The first block's clauses: all of them when there is no UNION.
      def clauses : Array(QueryClause)
        @blocks.first.clauses
      end

      def optional_clauses : Array(QueryClause)
        @blocks.first.optional_clauses
      end

      def filters : Array(QueryCondition)
        @blocks.first.filters
      end

      def to_s(io : IO)
        io << "ParsedQuery("
        io << "vars: #{@variables.map(&.name).join(", ")}, "
        io << "clauses: #{@blocks.sum(&.clauses.size)}"
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
        when '{', '}', ',', ':', '*', '(', ')', '='
          advance
          Token.new(:punctuation, char.to_s, line, column)
        when '.'
          advance
          Token.new(:punctuation, ".", line, column)
        when '<', '>', '!'
          advance
          if peek == '='
            advance
            Token.new(:punctuation, "#{char}=", line, column)
          else
            error("expected '!='", line, column) if char == '!'
            Token.new(:punctuation, char.to_s, line, column)
          end
        when '-'
          if peek(1) == '>'
            advance
            advance
            Token.new(:punctuation, "->", line, column)
          elsif peek(1).try(&.ascii_number?)
            advance
            Token.new(:number, "-#{read_number}", line, column)
          else
            error("expected '->'")
          end
        when '$'
          advance
          error("a variable needs a name after '$'") unless name_char?(peek)
          Token.new(:variable, read_name, line, column)
        when '"'
          Token.new(:string, read_string(line, column), line, column)
        else
          error("unexpected character #{char.inspect}") unless name_char?(char)
          if char.ascii_number? && (number = decimal_ahead)
            return Token.new(:number, number, line, column)
          end
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

      # Digits, then optionally a point and more digits.
      private def read_number : String
        String.build do |io|
          while (char = peek) && char.ascii_number?
            io << advance
          end
          if peek == '.' && peek(1).try(&.ascii_number?)
            io << advance
            while (char = peek) && char.ascii_number?
              io << advance
            end
          end
        end
      end

      # A number with a decimal point starting here, such as 0.75, and not
      # the start of a name such as 3d-model. Consumes it when found.
      private def decimal_ahead : String?
        offset = 0
        while peek(offset).try(&.ascii_number?)
          offset += 1
        end
        return nil unless peek(offset) == '.' && peek(offset + 1).try(&.ascii_number?)
        offset += 1
        while peek(offset).try(&.ascii_number?)
          offset += 1
        end
        return nil if name_char?(peek(offset))
        read_number
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

        used = [] of String
        blocks = [parse_block(used)]
        loop do
          skip_newlines
          break unless word?("UNION")
          advance
          skip_newlines
          blocks << parse_block(used)
        end

        skip_newlines
        order = [] of QueryOrder
        if word?("ORDER")
          advance
          skip_newlines
          fail("expected BY after ORDER, found #{current.describe}") unless word?("BY")
          advance
          loop do
            skip_newlines
            value = parse_value(used, declare: false)
            descending = false
            if word?("ASC") || word?("DESC")
              descending = advance.text.upcase == "DESC"
            end
            order << QueryOrder.new(value, descending)
            break unless punctuation?(",")
            advance
          end
          skip_newlines
        end

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

        ParsedQuery.new(variables, blocks, distinct, limit, order)
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

      # A word that is a keyword only where the grammar expects it.
      private def word?(text : String, offset : Int32 = 0) : Bool
        token = @tokens[@position + offset]? || return false
        token.kind == :name && token.text.upcase == text
      end

      private def next_is?(text : String) : Bool
        token = @tokens[@position + 1]? || return false
        token.kind == :punctuation && token.text == text
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
      private def parse_block(used : Array(String), into : QueryBlock? = nil) : QueryBlock
        block = into || QueryBlock.new
        nested = !into.nil?
        fail("expected '{', found #{current.describe}") unless punctuation?("{")
        opening = advance
        clauses_before = nested ? block.optional_clauses.size : block.clauses.size

        loop do
          while current.kind == :newline || punctuation?(".")
            advance
          end
          break if punctuation?("}")
          fail("expected '}' to close the block, found #{current.describe}") if current.kind == :end

          if keyword?("OPTIONAL")
            fail("OPTIONAL cannot be nested") if nested
            advance
            skip_newlines
            parse_block(used, block)
          elsif word?("FILTER") && next_is?("(")
            fail("FILTER belongs to the block around the OPTIONAL") if nested
            advance
            advance
            block.filters << parse_condition(used)
            fail("expected ')' to close FILTER, found #{current.describe}") unless punctuation?(")")
            advance
          else
            (nested ? block.optional_clauses : block.clauses) << parse_clause(used)
          end

          # A clause ends at a separator or at the closing brace.
          fail("expected '}' to close the block, found #{current.describe}") if current.kind == :end
          unless current.kind == :newline || punctuation?(".") || punctuation?("}")
            fail("expected '.', a line break or '}' after the clause, found #{current.describe}")
          end
        end
        closing = advance # the closing brace

        if nested
          fail("OPTIONAL needs at least one clause", closing) if block.optional_clauses.size == clauses_before
        elsif block.clauses.empty?
          fail("WHERE needs at least one clause", closing)
        end
        block
      end

      # condition := and { OR and }
      private def parse_condition(used : Array(String)) : QueryCondition
        skip_newlines
        left = parse_conjunction(used)
        loop do
          skip_newlines
          break unless word?("OR")
          advance
          left = LogicalCondition.new(left, false, parse_conjunction(used))
        end
        left
      end

      private def parse_conjunction(used : Array(String)) : QueryCondition
        left = parse_negation(used)
        loop do
          skip_newlines
          break unless word?("AND")
          advance
          left = LogicalCondition.new(left, true, parse_negation(used))
        end
        left
      end

      private def parse_negation(used : Array(String)) : QueryCondition
        skip_newlines
        if word?("NOT")
          advance
          return NotCondition.new(parse_negation(used))
        end

        if punctuation?("(")
          advance
          inner = parse_condition(used)
          fail("expected ')', found #{current.describe}") unless punctuation?(")")
          advance
          return inner
        end

        if word?("BOUND") && next_is?("(")
          advance
          advance
          fail("BOUND takes a variable, found #{current.describe}") unless current.kind == :variable
          name = advance.text
          fail("expected ')', found #{current.describe}") unless punctuation?(")")
          advance
          return BoundCondition.new(name)
        end

        if word?("CONTAINS") && next_is?("(")
          advance
          advance
          text = parse_value(used, declare: false)
          fail("expected ',' between the two values of CONTAINS, found #{current.describe}") unless punctuation?(",")
          advance
          part = parse_value(used, declare: false)
          fail("expected ')', found #{current.describe}") unless punctuation?(")")
          advance
          return ContainsCondition.new(text, part)
        end

        left = parse_value(used, declare: false)
        operator = current
        unless operator.kind == :punctuation && {"=", "!=", "<", "<=", ">", ">="}.includes?(operator.text)
          fail("expected a comparison such as = or <, found #{operator.describe}")
        end
        advance
        ComparisonCondition.new(left, operator.text, parse_value(used, declare: false))
      end

      PROPERTIES = {"NAME" => :name, "TYPE" => :type, "STRENGTH" => :strength, "CONFIDENCE" => :confidence}

      # A value in a FILTER or ORDER BY. These read variables but do not
      # introduce them: a variable must appear in a clause to have a value.
      private def parse_value(used : Array(String), declare : Bool) : QueryValue
        skip_newlines
        token = current
        case token.kind
        when :variable
          advance
          QueryValue.new(:variable, token.text)
        when :string
          advance
          QueryValue.new(:text, token.text)
        when :integer, :number
          advance
          QueryValue.new(:number, token.text, token.text.to_f)
        when :name
          if (property = PROPERTIES[token.text.upcase]?) && next_is?("(")
            advance
            advance
            fail("#{token.text.upcase} takes a variable, found #{current.describe}") unless current.kind == :variable
            name = advance.text
            fail("expected ')', found #{current.describe}") unless punctuation?(")")
            advance
            QueryValue.new(property, name)
          else
            advance
            QueryValue.new(:text, token.text)
          end
        else
          fail("expected a value, found #{token.describe}")
        end
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
        selected = query.variables.map(&.name)
        # Each result with the values ORDER BY sorts on, taken before the
        # result is cut down to the selected variables.
        rows = [] of {Query::QueryResult, Array(String | Float64 | Nil)}

        query.blocks.each do |block|
          solve_block(block, query.variables).each do |(bindings, matched)|
            keys = query.order.map(&.value.evaluate(bindings))
            rows << {Query::QueryResult.new(bindings.select(selected), calculate_confidence(matched)), keys}
          end
        end

        if query.order.empty?
          # Sort by confidence descending
          rows.sort! { |a, b| b[0].confidence <=> a[0].confidence }
        else
          rows.sort! do |a, b|
            order = 0
            query.order.each_with_index do |key, i|
              order = compare_keys(a[1][i], b[1][i])
              order = -order if key.descending
              break unless order == 0
            end
            order
          end
        end
        results = rows.map(&.[0])

        if query.distinct?
          seen = Set(Array(AtomSpace::Handle?)).new
          results.select! { |result| seen.add?(selected.map { |name| result.bindings[name]?.try(&.handle) }) }
        end
        query.limit.try { |limit| results = results.first(limit) }

        results
      end

      # Numbers before text, unbound values last; `sort!` is stable in what
      # it leaves equal.
      private def compare_keys(a : String | Float64 | Nil, b : String | Float64 | Nil) : Int32
        case {a, b}
        when {Float64, Float64} then (a <=> b) || 0
        when {String, String}   then a <=> b
        when {Nil, Nil}         then 0
        when {Nil, _}           then 1
        when {_, Nil}           then -1
        when {Float64, _}       then -1
        else                         1
        end
      end

      # The solutions of one block: every clause matched and joined on
      # shared variables, OPTIONAL clauses joined where they match, and the
      # FILTER conditions applied.
      private def solve_block(block : QueryBlock, variables : Array(QueryVariable)) : Array({Hash(String, AtomSpace::Atom), Array(AtomSpace::Atom)})
        var_map = Hash(String, AtomSpace::Atom).new
        pattern_atoms = block.clauses.flat_map(&.to_atoms(@atomspace, var_map))
        empty = [] of {Hash(String, AtomSpace::Atom), Array(AtomSpace::Atom)}
        return empty if pattern_atoms.empty?

        # Typed query variables become constraints on every clause pattern.
        type_constraints = variables.compact_map do |var|
          next unless allowed = var.type
          var_atom = QueryLanguage.resolve_term("$#{var.name}", @atomspace, var_map)
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
          return empty if solutions.empty?
        end

        # OPTIONAL clauses add bindings where they match and leave a
        # solution as it is where they do not (a left join).
        block.optional_clauses.each do |clause|
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

        block.filters.each do |condition|
          solutions.select! { |(bound, _)| condition.holds?(bound) }
        end
        solutions
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
