# Crystal implementation of OpenCog Query Language (OQL)
# Provides SQL-like query interface for AtomSpace operations
#
# Grammar (keywords in any case; `#` starts a comment):
#
#   query     := select | ask | construct
#   ask       := ASK [WHERE] block { UNION block }
#   construct := CONSTRUCT "{" template { ( "." | newline ) template } "}"
#                WHERE block { UNION block }
#                [ ORDER BY key { "," key } ] [ LIMIT integer ] [ OFFSET integer ]
#   template  := term ( ISA | inherits_from | "->" ) term | term term term
#   select    := SELECT [DISTINCT] ( "*" | item { [","] item } )
#                WHERE block { UNION block }
#                [ GROUP BY "$" name { [","] "$" name } ]
#                [ HAVING "(" condition ")" ]
#                [ ORDER BY key { "," key } ]
#                [ LIMIT integer ] [ OFFSET integer ]     (in either order)
#   item      := variable | aggregate [ AS "$" name ]
#              | "(" aggregate AS "$" name ")"
#   aggregate := COUNT "(" ( "*" | [DISTINCT] value ) ")"
#              | ( SUM | AVG | MIN | MAX ) "(" [DISTINCT] value ")"
#   variable  := "$" name [ ":" type ]
#   block     := "{" clause { ( "." | newline ) clause } "}"
#   clause    := term ( ISA | inherits_from | "->" ) term
#              | term term term                    (subject predicate object)
#              | term path term
#              | OPTIONAL "{" optional_item { ( "." | newline ) optional_item } "}"
#              | FILTER "(" condition ")"
#              | BIND "(" value AS "$" name ")"
#              | block { UNION block }             (a group inside the block)
#              | "{" query "}"                     (a subquery)
#              | MINUS block
#              | VALUES "$" name "{" { term | UNDEF } "}"
#              | VALUES "(" { "$" name } ")" "{" { "(" { term | UNDEF } ")" } "}"
#   optional_item := term ( ISA | inherits_from | "->" ) term
#                  | term term term | term path term | FILTER "(" condition ")"
#                    (at least one matching clause; no nested constructs)
#   path      := sequence { "|" sequence }         (one or the other)
#   sequence  := step { "/" step }                 (one after the other)
#   step      := [ "^" ] ( relation | "(" path ")" | negated ) [ "+" | "*" | "?" ]
#   negated   := "!" one | "!" "(" one { "|" one } ")"
#   one       := [ "^" ] relation
#   relation  := ISA | inherits_from | "->" | name
#   term      := "$" name | name | "quoted name"
#   condition := condition OR condition | condition AND condition
#              | NOT condition | "(" condition ")"
#              | value ( "=" | "!=" | "<" | "<=" | ">" | ">=" ) value
#              | CONTAINS "(" value "," value ")" | BOUND "(" "$" name ")"
#   value     := value ( "+" | "-" | "*" | "/" ) value | "-" value
#              | "(" value ")"
#              | COALESCE "(" value { "," value } ")"
#              | "$" name | name | "quoted text" | number
#              | ( NAME | TYPE | STRENGTH | CONFIDENCE ) "(" "$" name ")"
#   key       := value [ ASC | DESC ]
#
# "*" and "/" bind tighter than "+" and "-". A minus needs a blank on one
# side at least, since `a-b` is one name.
#
# A type is CONCEPT, PREDICATE, NODE, LINK or any AtomType name. Only
# SELECT, DISTINCT, WHERE, ISA, OPTIONAL and LIMIT are reserved; the other
# keywords are read as such only where the grammar expects them, so `order`
# or `filter` can still name a concept.
#
# A path says how to get from one atom to another over several links.
# `+` repeats a step once or more, `*` any number of times and `?` once
# or not at all; `/` puts steps one after the other, `|` offers a choice,
# `^` walks a relation backwards and `!` takes any relation but those
# named. So `$x ISA+ Animal` holds when a
# chain of inheritance links leads from $x to Animal, and
# `$part (part_of/ISA)+ $kind | ^has_part $kind` reads as it is written.
#
# ASK says whether anything matches. CONSTRUCT builds the atoms of its
# template once for each match.
#
# Running a query does not change the AtomSpace: its patterns are built
# beside it, and so is what CONSTRUCT builds unless it is told where to
# put it.

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

    # How to get from one atom to another over links: a single relation,
    # or steps put together.
    abstract class QueryPath
      abstract def to_s(io : IO)

      # Brackets where the path is part of a larger one.
      def to_s(io : IO, inside : Bool)
        to_s(io)
      end
    end

    # One link: an inheritance link when no relation is named, else a
    # triple of that predicate.
    class PathStep < QueryPath
      getter relation : String?

      def initialize(@relation : String?)
      end

      def to_s(io : IO)
        io << (@relation || "ISA")
      end
    end

    # One link of any relation but those named: `!a` any forward link
    # whose relation is not `a`, `!^a` any link walked backwards whose
    # relation is not `a`. `forward` and `backward` are the relations
    # left out each way, nil where the set allows no link that way.
    class PathNegated < QueryPath
      getter forward : Array(String?)?
      getter backward : Array(String?)?

      def initialize(@forward : Array(String?)?, @backward : Array(String?)?)
      end

      def to_s(io : IO)
        names = (@forward || [] of String?).map { |name| name || "ISA" } +
                (@backward || [] of String?).map { |name| "^#{name || "ISA"}" }
        io << '!'
        if names.size == 1
          io << names[0]
        else
          io << '(' << names.join('|') << ')'
        end
      end
    end

    # The inner path walked from its end to its start.
    class PathInverse < QueryPath
      getter inner : QueryPath

      def initialize(@inner : QueryPath)
      end

      def to_s(io : IO)
        io << '^'
        @inner.to_s(io, true)
      end
    end

    # The parts one after the other.
    class PathSequence < QueryPath
      getter parts : Array(QueryPath)

      def initialize(@parts : Array(QueryPath))
      end

      def to_s(io : IO)
        @parts.each_with_index do |part, i|
          io << '/' if i > 0
          part.is_a?(PathAlternative) ? part.to_s(io, true) : part.to_s(io)
        end
      end

      def to_s(io : IO, inside : Bool)
        io << '('
        to_s(io)
        io << ')'
      end
    end

    # Any one of the parts.
    class PathAlternative < QueryPath
      getter parts : Array(QueryPath)

      def initialize(@parts : Array(QueryPath))
      end

      def to_s(io : IO)
        @parts.each_with_index do |part, i|
          io << '|' if i > 0
          part.to_s(io)
        end
      end

      def to_s(io : IO, inside : Bool)
        io << '('
        to_s(io)
        io << ')'
      end
    end

    # The inner path once or more (`+`), any number of times (`*`), or
    # once or not at all (`?`).
    class PathRepeat < QueryPath
      getter inner : QueryPath
      getter mark : String

      def initialize(@inner : QueryPath, @mark : String)
      end

      # Whether no step at all will do.
      def optional? : Bool
        @mark != "+"
      end

      # Whether the inner path may be gone through again.
      def again? : Bool
        @mark != "?"
      end

      def to_s(io : IO)
        @inner.to_s(io, true)
        io << @mark
      end
    end

    # A path as a machine: states, moves along one link of a relation in
    # one direction, and moves that cost nothing. Following the path is
    # then a search over pairs of an atom and a state. `inverted` builds
    # the machine of the path read from its end.
    class PathAutomaton
      # A move over one link of `relation`, or with `except`, of any
      # relation but those.
      record Move, relation : String?, forward : Bool, target : Int32, except : Array(String?)? = nil

      getter start : Int32
      getter accept : Int32
      # The relations the path goes over by name.
      getter relations = [] of String?
      # Whether some step takes any relation but those it names.
      getter? any_relation = false

      def initialize(path : QueryPath, inverted : Bool = false)
        @moves = [] of Array(Move)
        @free = [] of Array(Int32)
        @start, @accept = build(path, inverted)
        @closures = Array(Array(Int32)?).new(@moves.size, nil)
      end

      def moves(state : Int32) : Array(Move)
        @moves[state]
      end

      # The states reached from one at no cost, itself among them.
      def closure(state : Int32) : Array(Int32)
        @closures[state] ||= begin
          seen = [state]
          at = 0
          while at < seen.size
            @free[seen[at]].each { |other| seen << other unless seen.includes?(other) }
            at += 1
          end
          seen
        end
      end

      # Whether the path holds between an atom and itself over no link.
      def empty? : Bool
        closure(@start).includes?(@accept)
      end

      private def state : Int32
        @moves << [] of Move
        @free << [] of Int32
        @moves.size - 1
      end

      private def build(path : QueryPath, inverted : Bool) : {Int32, Int32}
        case path
        when PathStep
          from, to = state, state
          @relations << path.relation unless @relations.includes?(path.relation)
          @moves[from] << Move.new(path.relation, !inverted, to)
          {from, to}
        when PathNegated
          from, to = state, state
          @any_relation = true
          path.forward.try { |left_out| @moves[from] << Move.new(nil, !inverted, to, left_out) }
          path.backward.try { |left_out| @moves[from] << Move.new(nil, inverted, to, left_out) }
          {from, to}
        when PathInverse
          build(path.inner, !inverted)
        when PathSequence
          parts = inverted ? path.parts.reverse : path.parts
          first, last = build(parts[0], inverted)
          parts.each_with_index do |part, i|
            next if i == 0
            from, to = build(part, inverted)
            @free[last] << from
            last = to
          end
          {first, last}
        when PathAlternative
          from, to = state, state
          path.parts.each do |part|
            inner_from, inner_to = build(part, inverted)
            @free[from] << inner_from
            @free[inner_to] << to
          end
          {from, to}
        when PathRepeat
          from, to = state, state
          inner_from, inner_to = build(path.inner, inverted)
          @free[from] << inner_from
          @free[inner_to] << to
          @free[inner_to] << inner_from if path.again?
          @free[from] << to if path.optional?
          {from, to}
        else
          raise QueryExecutionException.new("Unknown kind of path: #{path.class}")
        end
      end
    end

    # A clause that holds when its path leads from the subject to the
    # object.
    class PathClause < QueryClause
      getter subject : String
      getter path : QueryPath
      getter object : String

      def initialize(@subject : String, @path : QueryPath, @object : String)
      end

      # A path is not one pattern: the executor follows it.
      def to_atoms(atomspace : AtomSpace::AtomSpace, var_map : Hash(String, AtomSpace::Atom)) : Array(AtomSpace::Atom)
        [] of AtomSpace::Atom
      end

      def to_s(io : IO)
        io << "PathClause(" << @subject << ' '
        @path.to_s(io)
        io << ' ' << @object << ')'
      end
    end

    # One way a block matches: its variables by name, and the atoms matched.
    alias Solution = {Hash(String, AtomSpace::Atom), Array(AtomSpace::Atom)}

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
          else
            # A number an aggregate or BIND made is that number, so that
            # it sorts and compares as one.
            if atom.is_a?(AtomSpace::Node)
              (atom.type == AtomSpace::AtomType::NUMBER_NODE ? atom.name.to_f? : nil) || atom.name
            else
              atom.to_s
            end
          end
        end
      end

      # The variable this is, when it is nothing more.
      def variable? : String?
        kind == :variable ? text : nil
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

    # Two values joined by + - * or /. The sides are read as numbers; a side
    # that is not one, or a division by zero, leaves the result without a
    # value, as an unbound variable would.
    class QueryArithmetic
      getter left : QueryOperand
      getter operator : Char
      getter right : QueryOperand

      def initialize(@left : QueryOperand, @operator : Char, @right : QueryOperand)
      end

      def evaluate(bindings : Hash(String, AtomSpace::Atom)) : String | Float64 | Nil
        left = QueryLanguage.number(@left.evaluate(bindings)) || return nil
        right = QueryLanguage.number(@right.evaluate(bindings)) || return nil
        result = case @operator
                 when '+' then left + right
                 when '-' then left - right
                 when '*' then left * right
                 else
                   return nil if right == 0.0
                   left / right
                 end
        result.finite? ? result : nil
      end

      # The variable this is, when it is nothing more.
      def variable? : String?
        nil
      end

      def to_s(io : IO)
        io << '(' << @left << ' ' << @operator << ' ' << @right << ')'
      end
    end

    # The first available value, evaluated left to right. Unbound variables
    # and invalid arithmetic have no value; zero and empty text do.
    class QueryCoalesce
      getter arguments : Array(QueryOperand)

      def initialize(@arguments : Array(QueryOperand))
        raise QueryExecutionException.new("COALESCE needs at least one value") if @arguments.empty?
      end

      def evaluate(bindings : Hash(String, AtomSpace::Atom)) : String | Float64 | Nil
        @arguments.each do |argument|
          value = argument.evaluate(bindings)
          return value unless value.nil?
        end
        nil
      end

      def variable? : String?
        nil
      end

      def to_s(io : IO)
        io << "COALESCE(" << @arguments.join(", ") << ')'
      end
    end

    alias QueryOperand = QueryValue | QueryArithmetic | QueryCoalesce

    # A value as a number: a number itself, or text that reads as one.
    def self.number(value : String | Float64 | Nil) : Float64?
      value.is_a?(String) ? value.to_f? : value
    end

    # A number as an atom, so that a result can carry one. It stands beside
    # the AtomSpace, as query patterns do.
    def self.number_atom(value : Float64) : AtomSpace::Atom
      whole = value == value.round && value.abs < 1e15
      AtomSpace::Node.new(AtomSpace::AtomType::NUMBER_NODE, whole ? value.to_i64.to_s : value.to_s)
    end

    # COUNT, SUM, AVG, MIN or MAX over the results of a group, named by
    # `name` in the result. `argument` is nil for COUNT(*).
    record QueryAggregate, function : Symbol, argument : QueryOperand?, distinct : Bool, name : String do
      def to_s(io : IO)
        io << function.to_s.upcase << '('
        io << "DISTINCT " if distinct
        if value = argument
          io << value
        else
          io << '*'
        end
        io << ") AS $" << name
      end
    end

    # A FILTER condition, checked against each candidate result.
    abstract class QueryCondition
      abstract def holds?(bindings : Hash(String, AtomSpace::Atom)) : Bool
    end

    class ComparisonCondition < QueryCondition
      def initialize(@left : QueryOperand, @operator : String, @right : QueryOperand)
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
      def initialize(@text : QueryOperand, @part : QueryOperand)
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
    # BIND(value AS $name): a variable given a computed value.
    record QueryBind, value : QueryOperand, name : String

    # One OPTIONAL unit: all clauses must join before its local filters
    # decide whether it can enrich an outer solution.
    class QueryOptionalBlock
      getter clauses : Array(QueryClause)
      getter filters : Array(QueryCondition)

      def initialize(@clauses : Array(QueryClause), @filters : Array(QueryCondition) = [] of QueryCondition)
        raise QueryExecutionException.new("OPTIONAL needs at least one clause") if @clauses.empty?
      end
    end

    class QueryBlock
      getter clauses = [] of QueryClause
      # Flattened inspection/legacy construction API. Parsed units also
      # appear here, but are executed only through optional_blocks.
      getter optional_clauses = [] of QueryClause
      getter optional_blocks = [] of QueryOptionalBlock
      getter filters = [] of QueryCondition
      getter binds = [] of QueryBind
      # Groups inside the block. Each is one block or several joined by
      # UNION, and its results are joined with the rest of this block.
      getter groups = [] of Array(QueryBlock)
      # Whole queries inside the block; what each selects is joined in.
      getter subqueries = [] of ParsedQuery
      # Values given in the query itself.
      getter values = [] of QueryInlineData
      # MINUS blocks: a result that agrees with one of theirs is left out.
      getter minus = [] of QueryBlock

      # True when the block has something to start from.
      def matches_something? : Bool
        !(clauses.empty? && groups.empty? && subqueries.empty? && values.empty?)
      end

      # Flat clause objects have no block boundaries: preserve their old
      # independent left joins rather than treating them as a conjunction.
      # Identity distinguishes the parsed inspection entries from legacy
      # clauses, so parsed units never run a second time.
      def optional_units : Array(QueryOptionalBlock)
        legacy = optional_clauses.reject do |clause|
          optional_blocks.any? { |unit| unit.clauses.any? { |inner| inner.same?(clause) } }
        end
        optional_blocks + legacy.map { |clause| QueryOptionalBlock.new([clause]) }
      end
    end

    # VALUES: variables and rows of terms for them. nil is UNDEF, a place
    # the row leaves unbound.
    record QueryInlineData, names : Array(String), rows : Array(Array(String?))

    # One ORDER BY key.
    record QueryOrder, value : QueryOperand, descending : Bool

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
      # Leave out this many results from the front.
      getter offset : Int32
      # The aggregates in the SELECT list.
      getter aggregates : Array(QueryAggregate)
      # The variables whose values make a group.
      getter group_by : Array(String)
      # Conditions on the groups, which may read the aggregates.
      getter having : Array(QueryCondition)
      # The names a result carries, in the order SELECT lists them.
      getter columns : Array(String)
      # :select, :ask or :construct.
      getter form : Symbol
      # What a CONSTRUCT query builds for each match.
      getter template : Array(QueryClause)

      def initialize(@variables : Array(QueryVariable), @blocks : Array(QueryBlock),
                     @distinct : Bool = false, @limit : Int32? = nil,
                     @order : Array(QueryOrder) = [] of QueryOrder,
                     @offset : Int32 = 0,
                     @aggregates : Array(QueryAggregate) = [] of QueryAggregate,
                     @group_by : Array(String) = [] of String,
                     @having : Array(QueryCondition) = [] of QueryCondition,
                     columns : Array(String)? = nil,
                     @form : Symbol = :select,
                     @template : Array(QueryClause) = [] of QueryClause)
        @columns = columns || @variables.map(&.name)
      end

      # True when results are groups of matches, not the matches themselves.
      def grouped? : Bool
        !@aggregates.empty? || !@group_by.empty?
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
        when '{', '}', ',', ':', '*', '(', ')', '=', '+', '/', '^', '|', '?'
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
            advance
            Token.new(:punctuation, "-", line, column)
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

      def parse(nested : Bool = false) : ParsedQuery
        skip_newlines
        unless nested
          return parse_ask if word?("ASK") && (next_is?("{") || keyword_at?(1, "WHERE") || newline_at?(1))
          return parse_construct if word?("CONSTRUCT") && (next_is?("{") || newline_at?(1))
        end
        unless keyword?("SELECT")
          expected = nested ? "SELECT" : "SELECT, ASK or CONSTRUCT"
          raise QueryParseException.new("Query must start with #{expected}, found #{current.describe} at #{where(current)}")
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
        aggregates = [] of QueryAggregate
        columns = [] of String
        if punctuation?("*")
          select_all = true
          advance
        else
          parse_select_list(variables, aggregates, columns)
        end
        skip_newlines

        unless keyword?("WHERE")
          raise QueryParseException.new("Missing WHERE clause: expected WHERE, found #{current.describe} at #{where(current)}")
        end
        advance
        skip_newlines

        used = [] of String
        blocks = parse_alternatives(used)
        group_by = [] of String
        if word?("GROUP") && word?("BY", 1)
          advance
          advance
          loop do
            skip_newlines
            fail("GROUP BY takes variables, found #{current.describe}") unless current.kind == :variable
            name = advance.text
            fail("$#{name} does not appear in WHERE", @tokens[@position - 1]) unless used.includes?(name)
            group_by << name unless group_by.includes?(name)
            advance if punctuation?(",")
            break unless current.kind == :variable
          end
          skip_newlines
        end

        having = [] of QueryCondition
        while word?("HAVING") && next_is?("(")
          advance
          advance
          having << parse_condition(used)
          skip_newlines
          fail("expected ')' to close HAVING, found #{current.describe}") unless punctuation?(")")
          advance
          skip_newlines
        end

        order = parse_order(used)
        limit, offset = parse_limits
        if nested
          fail("expected '}' to close the subquery, found #{current.describe}") unless punctuation?("}")
        else
          fail("expected the end of the query, found #{current.describe}") unless current.kind == :end
        end

        if select_all
          variables = used.map { |name| QueryVariable.new(name) }
          columns = used.dup
        else
          variables.each do |variable|
            next if used.includes?(variable.name)
            raise QueryParseException.new("$#{variable.name} is selected but does not appear in WHERE")
          end
        end

        grouped = !aggregates.empty? || !group_by.empty?
        if grouped
          raise QueryParseException.new("SELECT * cannot be used with GROUP BY") if select_all
          variables.each do |variable|
            next if group_by.includes?(variable.name)
            raise QueryParseException.new("$#{variable.name} is selected beside an aggregate but is not in GROUP BY")
          end
        elsif !having.empty?
          raise QueryParseException.new("HAVING needs GROUP BY or an aggregate")
        end

        ParsedQuery.new(variables, blocks, distinct, limit, order, offset || 0, aggregates, group_by, having, columns)
      end

      # ASK [WHERE] block { UNION block }
      private def parse_ask : ParsedQuery
        advance
        skip_newlines
        if keyword?("WHERE")
          advance
          skip_newlines
        end
        blocks = parse_alternatives([] of String)
        fail("expected the end of the query, found #{current.describe}") unless current.kind == :end
        ParsedQuery.new([] of QueryVariable, blocks, form: :ask)
      end

      # CONSTRUCT "{" template "}" WHERE block { UNION block }
      private def parse_construct : ParsedQuery
        advance
        skip_newlines
        fail("expected '{' after CONSTRUCT, found #{current.describe}") unless punctuation?("{")
        advance
        wanted = [] of Token
        template = [] of QueryClause
        loop do
          while current.kind == :newline || punctuation?(".")
            advance
          end
          break if punctuation?("}")
          fail("expected '}' to close the template, found #{current.describe}") if current.kind == :end
          first = @position
          template << parse_clause([] of String, paths: false)
          @tokens[first...@position].each { |token| wanted << token if token.kind == :variable }
          unless current.kind == :newline || punctuation?(".") || punctuation?("}")
            fail("expected '.', a line break or '}' after the clause, found #{current.describe}")
          end
        end
        closing = advance
        fail("CONSTRUCT needs at least one clause", closing) if template.empty?
        skip_newlines

        unless keyword?("WHERE")
          raise QueryParseException.new("Missing WHERE clause: expected WHERE, found #{current.describe} at #{where(current)}")
        end
        advance
        skip_newlines
        used = [] of String
        blocks = parse_alternatives(used)
        order = parse_order(used)
        limit, offset = parse_limits
        fail("expected the end of the query, found #{current.describe}") unless current.kind == :end

        wanted.each do |token|
          fail("$#{token.text} is in the template but does not appear in WHERE", token) unless used.includes?(token.text)
        end
        variables = wanted.map(&.text).uniq.map { |name| QueryVariable.new(name) }
        ParsedQuery.new(variables, blocks, false, limit, order, offset || 0, form: :construct, template: template)
      end

      # [ ORDER BY key { "," key } ]
      private def parse_order(used : Array(String)) : Array(QueryOrder)
        order = [] of QueryOrder
        return order unless word?("ORDER")
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
        order
      end

      # [ LIMIT integer ] [ OFFSET integer ], in either order.
      private def parse_limits : {Int32?, Int32?}
        limit = nil
        offset = nil
        loop do
          if keyword?("LIMIT") && limit.nil?
            advance
            fail("expected a number after LIMIT, found #{current.describe}") unless current.kind == :integer
            limit = current.text.to_i? || fail("LIMIT #{current.text} is too large")
          elsif word?("OFFSET") && offset.nil?
            advance
            fail("expected a number after OFFSET, found #{current.describe}") unless current.kind == :integer
            offset = current.text.to_i? || fail("OFFSET #{current.text} is too large")
          else
            break
          end
          advance
          skip_newlines
        end
        {limit, offset}
      end

      # block { UNION block }, up to what follows the last of them.
      private def parse_alternatives(used : Array(String)) : Array(QueryBlock)
        blocks = [parse_block(used)]
        loop do
          skip_newlines
          break unless word?("UNION")
          advance
          skip_newlines
          blocks << parse_block(used)
        end
        skip_newlines
        blocks
      end

      AGGREGATES = {"COUNT" => :count, "SUM" => :sum, "AVG" => :avg, "MIN" => :min, "MAX" => :max}

      # The SELECT list: variables and aggregates, in any order.
      private def parse_select_list(variables : Array(QueryVariable), aggregates : Array(QueryAggregate),
                                    columns : Array(String)) : Nil
        loop do
          skip_newlines
          start = current
          wrapped = punctuation?("(")
          if wrapped || (current.kind == :name && AGGREGATES.has_key?(current.text.upcase) && next_is?("("))
            advance if wrapped
            aggregate = parse_aggregate(wrapped)
            if wrapped
              fail("expected ')' after the aggregate, found #{current.describe}") unless punctuation?(")")
              advance
            end
            fail("$#{aggregate.name} is selected twice", start) if columns.includes?(aggregate.name)
            aggregates << aggregate
            columns << aggregate.name
          else
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
            fail("$#{name} is selected twice", @tokens[@position - 1]) if columns.includes?(name)
            variables << QueryVariable.new(name, type)
            columns << name
          end

          advance if punctuation?(",")
          skip_newlines
          more = current.kind == :variable || punctuation?("(") ||
                 (current.kind == :name && AGGREGATES.has_key?(current.text.upcase) && next_is?("("))
          break unless more
        end
      end

      # COUNT(*), COUNT($x), SUM(DISTINCT $n) and the like, with AS $name.
      # Without AS the result is named after the function, as in $count.
      private def parse_aggregate(needs_name : Bool) : QueryAggregate
        token = current
        function = (token.kind == :name ? AGGREGATES[token.text.upcase]? : nil) ||
                   fail("expected COUNT, SUM, AVG, MIN or MAX, found #{token.describe}")
        advance
        fail("expected '(' after #{token.text.upcase}, found #{current.describe}") unless punctuation?("(")
        advance

        distinct = false
        argument = nil
        if punctuation?("*")
          fail("only COUNT takes *", current) unless function == :count
          advance
        else
          if keyword?("DISTINCT")
            distinct = true
            advance
          end
          argument = parse_value([] of String, declare: false)
        end
        fail("expected ')', found #{current.describe}") unless punctuation?(")")
        advance

        name = token.text.downcase
        if word?("AS")
          advance
          fail("expected a variable after AS, found #{current.describe}") unless current.kind == :variable
          name = advance.text
        elsif needs_name
          fail("expected AS and a variable, found #{current.describe}")
        end
        QueryAggregate.new(function, argument, distinct, name)
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

      private def keyword_at?(offset : Int32, word : String) : Bool
        token = @tokens[@position + offset]? || return false
        token.kind == :keyword && token.text == word
      end

      private def newline_at?(offset : Int32) : Bool
        @tokens[@position + offset]?.try(&.kind) == :newline
      end

      private def skip_newlines : Nil
        while current.kind == :newline
          advance
        end
      end

      private def parse_type(token : Token) : AtomSpace::AtomType
        TYPE_ALIASES[token.text.upcase]? ||
          AtomSpace::AtomType.parse?(token.text) ||
          fail("unknown type #{token.text}", token)
      end

      # "{" clause { separator clause } "}"
      private def parse_block(used : Array(String), nested : Bool = false) : QueryBlock
        block = QueryBlock.new
        fail("expected '{', found #{current.describe}") unless punctuation?("{")
        opening = advance
        bound_here = [] of Token

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
            inner = parse_block(used, nested: true)
            block.optional_blocks << QueryOptionalBlock.new(inner.clauses, inner.filters)
            block.optional_clauses.concat(inner.clauses)
          elsif word?("FILTER") && next_is?("(")
            advance
            advance
            block.filters << parse_condition(used)
            fail("expected ')' to close FILTER, found #{current.describe}") unless punctuation?(")")
            advance
          elsif word?("BIND") && next_is?("(")
            fail("BIND belongs to the block around the OPTIONAL") if nested
            advance
            advance
            value = parse_value(used, declare: false)
            fail("expected AS in BIND, found #{current.describe}") unless word?("AS")
            advance
            fail("expected a variable after AS, found #{current.describe}") unless current.kind == :variable
            target = advance
            fail("expected ')' to close BIND, found #{current.describe}") unless punctuation?(")")
            advance
            bound_here << target
            block.binds << QueryBind.new(value, target.text)
          elsif word?("MINUS") && next_is?("{")
            fail("MINUS belongs to the block around the OPTIONAL") if nested
            advance
            # What a MINUS block matches is not there to be selected.
            block.minus << parse_block(used.dup)
          elsif word?("VALUES") && values_ahead?
            fail("VALUES belongs to the block around the OPTIONAL") if nested
            advance
            block.values << parse_inline_data(used)
          elsif punctuation?("{") && subquery_ahead?
            fail("a subquery cannot be inside OPTIONAL") if nested
            advance
            subquery = parse(nested: true)
            advance # the closing brace
            # Only what the subquery selects is seen outside it.
            subquery.columns.each { |name| used << name unless used.includes?(name) }
            block.subqueries << subquery
          elsif punctuation?("{")
            fail("a group cannot be inside OPTIONAL") if nested
            alternatives = [parse_block(used)]
            loop do
              # UNION may follow on a later line.
              resume = @position
              skip_newlines
              unless word?("UNION")
                @position = resume
                break
              end
              advance
              skip_newlines
              alternatives << parse_block(used)
            end
            block.groups << alternatives
          else
            block.clauses << parse_clause(used)
          end

          # A clause ends at a separator or at the closing brace.
          fail("expected '}' to close the block, found #{current.describe}") if current.kind == :end
          unless current.kind == :newline || punctuation?(".") || punctuation?("}")
            fail("expected '.', a line break or '}' after the clause, found #{current.describe}")
          end
        end
        closing = advance # the closing brace

        if nested
          fail("OPTIONAL needs at least one clause", closing) if block.clauses.empty?
        elsif !block.matches_something?
          fail("WHERE needs at least one clause", closing)
        end

        # A BIND gives a variable its only value: one the block's clauses
        # match, or an earlier BIND set, cannot be bound again.
        matched = (block.clauses + block.optional_clauses).flat_map { |clause| clause_variables(clause) }
        bound_here.each_with_index do |target, i|
          taken = matched.includes?(target.text) || bound_here.first(i).any? { |earlier| earlier.text == target.text }
          fail("$#{target.text} already has a value in this block", target) if taken
          used << target.text unless used.includes?(target.text)
        end
        block
      end

      # Is "{" here the start of a subquery: is SELECT the next thing in it?
      private def subquery_ahead? : Bool
        offset = 1
        while (token = @tokens[@position + offset]?) && token.kind == :newline
          offset += 1
        end
        token = @tokens[@position + offset]?
        !token.nil? && token.kind == :keyword && token.text == "SELECT"
      end

      # Is VALUES here the keyword: followed by "$x {" or by "("?
      private def values_ahead? : Bool
        following = @tokens[@position + 1]? || return false
        return true if following.kind == :punctuation && following.text == "("
        return false unless following.kind == :variable
        opening = @tokens[@position + 2]?
        !opening.nil? && opening.kind == :punctuation && opening.text == "{"
      end

      # $x { a b }  or  ($x $y) { (a b) (c UNDEF) }
      private def parse_inline_data(used : Array(String)) : QueryInlineData
        names = [] of String
        several = punctuation?("(")
        if several
          advance
          while current.kind == :variable
            names << advance.text
          end
          fail("expected a variable or ')', found #{current.describe}") unless punctuation?(")")
          fail("VALUES needs at least one variable") if names.empty?
          advance
        else
          names << advance.text
        end
        names.each { |name| used << name unless used.includes?(name) }

        skip_newlines
        fail("expected '{' after the variables of VALUES, found #{current.describe}") unless punctuation?("{")
        advance
        rows = [] of Array(String?)
        loop do
          skip_newlines
          break if punctuation?("}")
          if several
            fail("expected '(' to start a row of VALUES, found #{current.describe}") unless punctuation?("(")
            opening = advance
            row = [] of String?
            until punctuation?(")")
              row << parse_inline_term
            end
            advance
            fail("a row of VALUES needs #{names.size} values, found #{row.size}", opening) unless row.size == names.size
            rows << row
          else
            rows << [parse_inline_term]
          end
        end
        advance # the closing brace
        QueryInlineData.new(names, rows)
      end

      private def parse_inline_term : String?
        token = current
        case token.kind
        when :name
          advance
          token.text.upcase == "UNDEF" ? nil : token.text
        when :string, :integer, :number
          advance
          token.text
        else
          fail("expected a value, found #{token.describe}")
        end
      end

      private def clause_variables(clause : QueryClause) : Array(String)
        terms = case clause
                when TripleClause      then [clause.subject, clause.predicate, clause.object]
                when InheritanceClause then [clause.child, clause.parent]
                when PathClause        then [clause.subject, clause.object]
                else                        [] of String | AtomSpace::Atom
                end
        terms.compact_map { |term| term.is_a?(String) && term.starts_with?('$') ? term.lchop('$') : nil }
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
          # A bracket opens a condition, as in ($a = b OR $a = c), or a
          # value, as in ($a + 1) * 2 > $b. Read it as a condition first.
          start = @position
          begin
            advance
            inner = parse_condition(used)
            fail("expected ')', found #{current.describe}") unless punctuation?(")")
            advance
            return inner
          rescue as_condition : QueryParseException
            reached = @position
            @position = start
            begin
              return parse_comparison(used)
            rescue as_value : QueryParseException
              # Report whichever reading got further into the query.
              raise @position >= reached ? as_value : as_condition
            end
          end
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

        parse_comparison(used)
      end

      private def parse_comparison(used : Array(String)) : QueryCondition
        left = parse_value(used, declare: false)
        operator = current
        fail("expected '!='") if operator.kind == :punctuation && operator.text == "!"
        unless operator.kind == :punctuation && {"=", "!=", "<", "<=", ">", ">="}.includes?(operator.text)
          fail("expected a comparison such as = or <, found #{operator.describe}")
        end
        advance
        ComparisonCondition.new(left, operator.text, parse_value(used, declare: false))
      end

      PROPERTIES = {"NAME" => :name, "TYPE" => :type, "STRENGTH" => :strength, "CONFIDENCE" => :confidence}

      # A value in a FILTER or ORDER BY. These read variables but do not
      # introduce them: a variable must appear in a clause to have a value.
      private def parse_value(used : Array(String), declare : Bool) : QueryOperand
        skip_newlines
        left = parse_product(used)
        loop do
          if punctuation?("+") || punctuation?("-")
            operator = advance.text[0]
            left = QueryArithmetic.new(left, operator, parse_product(used))
          elsif current.kind == :number && current.text.starts_with?('-')
            # `$n -1` is a subtraction: the lexer took the minus for a sign.
            token = current
            @tokens[@position] = Token.new(:number, token.text.lchop('-'), token.line, token.column + 1)
            left = QueryArithmetic.new(left, '-', parse_product(used))
          else
            break
          end
        end
        left
      end

      private def parse_product(used : Array(String)) : QueryOperand
        left = parse_operand(used)
        while punctuation?("*") || punctuation?("/")
          operator = advance.text[0]
          left = QueryArithmetic.new(left, operator, parse_operand(used))
        end
        left
      end

      private def parse_operand(used : Array(String)) : QueryOperand
        skip_newlines
        token = current
        if punctuation?("(")
          advance
          inner = parse_value(used, declare: false)
          fail("expected ')', found #{current.describe}") unless punctuation?(")")
          advance
          return inner
        end
        if punctuation?("-")
          advance
          return QueryArithmetic.new(QueryValue.new(:number, "0", 0.0), '-', parse_operand(used))
        end
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
          if word?("COALESCE") && next_is?("(")
            parse_coalesce(used)
          elsif (property = PROPERTIES[token.text.upcase]?) && next_is?("(")
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

      # COALESCE(value, ...): one or more operands, not declarations.
      private def parse_coalesce(used : Array(String)) : QueryCoalesce
        advance # COALESCE
        advance # opening bracket
        skip_newlines
        fail("COALESCE needs at least one value") if punctuation?(")")
        arguments = [parse_value(used, declare: false)]
        loop do
          skip_newlines
          break if punctuation?(")")
          fail("expected ',' or ')' in COALESCE, found #{current.describe}") unless punctuation?(",")
          advance
          arguments << parse_value(used, declare: false)
        end
        advance # closing bracket
        QueryCoalesce.new(arguments)
      end

      private def parse_clause(used : Array(String), paths : Bool = true) : QueryClause
        first = parse_term(used)

        # A variable in the predicate's place makes a plain triple.
        if current.kind == :variable
          named = current
          if PATH_MARKS.any? { |mark| next_is?(mark) }
            fail("a path follows a named predicate, not $#{named.text}")
          end
          predicate = parse_term(used)
          return TripleClause.new(first, predicate, parse_term(used, "the object of the triple"))
        end

        path = parse_path(paths)
        single = path.is_a?(PathRepeat) ? path.inner : path
        expected = if single.is_a?(PathStep)
                     single.relation ? "the object of the triple" : "a term"
                   else
                     "the end of the path"
                   end
        second = parse_term(used, expected)
        if path.is_a?(PathStep)
          path.relation.try { |name| TripleClause.new(first, name, second) } || InheritanceClause.new(first, second)
        else
          PathClause.new(first, path, second)
        end
      end

      PATH_MARKS = {"+", "*", "?", "/", "|"}

      # After "!": one relation, or several in brackets, each perhaps
      # walked backwards.
      private def parse_negated : QueryPath
        forward = nil
        backward = nil
        bracketed = punctuation?("(")
        advance if bracketed
        loop do
          inverse = punctuation?("^")
          advance if inverse
          token = current
          relation = if keyword?("ISA") || punctuation?("->") || (token.kind == :name && token.text.downcase == "inherits_from")
                       nil
                     elsif token.kind == :name || token.kind == :string || token.kind == :integer
                       token.text
                     elsif token.kind == :variable
                       fail("a path follows a named predicate, not $#{token.text}")
                     else
                       fail("expected a predicate, ISA or '->' after '!', found #{token.describe}")
                     end
          advance
          if inverse
            (backward ||= [] of String?) << relation
          else
            (forward ||= [] of String?) << relation
          end
          break unless bracketed && punctuation?("|")
          advance
        end
        if bracketed
          fail("expected ')' to close the relations after '!', found #{current.describe}") unless punctuation?(")")
          advance
        end
        PathNegated.new(forward, backward)
      end

      # A template takes single steps: anything that makes a path is
      # refused there.
      private def path_mark(allowed : Bool) : Token
        fail("a path cannot be built: the template takes single steps") unless allowed
        advance
      end

      # path := sequence { "|" sequence }
      private def parse_path(allowed : Bool) : QueryPath
        parts = [parse_path_sequence(allowed)]
        while punctuation?("|")
          path_mark(allowed)
          parts << parse_path_sequence(allowed)
        end
        parts.size == 1 ? parts[0] : PathAlternative.new(parts)
      end

      # sequence := step { "/" step }
      private def parse_path_sequence(allowed : Bool) : QueryPath
        parts = [parse_path_step(allowed)]
        while punctuation?("/")
          path_mark(allowed)
          parts << parse_path_step(allowed)
        end
        parts.size == 1 ? parts[0] : PathSequence.new(parts)
      end

      # step := [ "^" ] ( relation | "(" path ")" ) [ "+" | "*" | "?" ]
      private def parse_path_step(allowed : Bool) : QueryPath
        # Where no path can be, and before a variable, a bracket is not
        # the start of one: `FILTR($x = a)` is a misspelt word, not a path.
        opens = punctuation?("^") || punctuation?("!") ||
                (punctuation?("(") && @tokens[@position + 1]?.try(&.kind) != :variable)
        fail("expected a predicate, ISA or '->', found #{current.describe}") if punctuation?("(") && !opens
        fail("expected a predicate, ISA or '->', found #{current.describe}") if opens && !allowed

        inverse = false
        if punctuation?("^")
          advance
          inverse = true
        end

        token = current
        inner = if punctuation?("!")
                  advance
                  parse_negated
                elsif punctuation?("(")
                  advance
                  bracketed = parse_path(allowed)
                  fail("expected ')' to close the path, found #{current.describe}") unless punctuation?(")")
                  advance
                  bracketed
                elsif keyword?("ISA") || punctuation?("->") || (token.kind == :name && token.text.downcase == "inherits_from")
                  advance
                  PathStep.new(nil)
                elsif token.kind == :name || token.kind == :string || token.kind == :integer
                  advance
                  PathStep.new(token.text)
                elsif token.kind == :variable
                  fail("a path follows a named predicate, not $#{token.text}")
                else
                  fail("expected a predicate, ISA or '->', found #{token.describe}")
                end

        if punctuation?("+") || punctuation?("*") || punctuation?("?")
          inner = PathRepeat.new(inner, path_mark(allowed).text)
        end
        inverse ? PathInverse.new(inner) : inner
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
        rows = matches(query).map { |(bindings, matched)| {bindings, calculate_confidence(matched)} }

        if query.grouped?
          rows = aggregate(query, rows)
          query.having.each do |condition|
            rows.select! { |(bindings, _)| condition.holds?(bindings) }
          end
        end

        rows = ordering(query, rows.map(&.[0]), rows.map(&.[1])).map { |i| rows[i] }

        selected = query.columns
        results = rows.map do |(bindings, confidence)|
          Query::QueryResult.new(query.grouped? ? in_order(bindings, selected) : bindings.select(selected), confidence)
        end

        if query.distinct?
          seen = Set(Array(String | AtomSpace::Handle | Nil)).new
          results.select! { |result| seen.add?(selected.map { |name| identity(result.bindings[name]?) }) }
        end
        results = results.skip(query.offset) if query.offset > 0
        query.limit.try { |limit| results = results.first(limit) }
        # ASK has nothing to list: one empty result says yes, none says no.
        results = results.first(1) if query.form == :ask

        results
      end

      # Whether the query matches anything.
      def ask(query : ParsedQuery) : Bool
        query.blocks.any? { |block| !solve_block(block, query.variables).empty? }
      end

      # The atoms a CONSTRUCT query builds: its template filled in once for
      # each match, each distinct atom once. A template clause is left out
      # for a match that gives one of its variables no value.
      #
      # A built atom is as strong as the weakest atom its match rests on,
      # and as confident as the match (the mean confidence of those atoms).
      # Where several matches build the same atom, the most confident one
      # is kept.
      #
      # The atoms stand beside the AtomSpace unless `into` names one to add
      # them to (the queried one or another), which then merges them with
      # what it already holds in its usual way.
      def construct(query : ParsedQuery, into : AtomSpace::AtomSpace? = nil) : Array(AtomSpace::Atom)
        raise QueryExecutionException.new("Not a CONSTRUCT query") unless query.form == :construct

        # ORDER BY, OFFSET and LIMIT choose among the matches, as they do
        # among the results of a SELECT.
        found = matches(query)
        chosen = ordering(query, found.map(&.[0]), found.map { |(_, matched)| calculate_confidence(matched) })
        chosen = chosen.skip(query.offset) if query.offset > 0
        query.limit.try { |limit| chosen = chosen.first(limit) }

        built = {} of String => AtomSpace::Atom
        chosen.each do |index|
          bindings, matched = found[index]
          truth = if matched.empty?
                    AtomSpace::TruthValue::DEFAULT_TV
                  else
                    AtomSpace::SimpleTruthValue.new(matched.min_of(&.truth_value.strength), calculate_confidence(matched))
                  end
          query.template.each do |clause|
            atom = build(clause, bindings, truth) || next
            shape = shape_of(atom)
            existing = built[shape]?
            built[shape] = atom if existing.nil? || atom.truth_value.confidence > existing.truth_value.confidence
          end
        end
        atoms = built.values
        return atoms unless into
        stored = [] of AtomSpace::Atom
        atoms.each { |atom| stored << store(atom, into) }
        stored
      end

      private def matches(query : ParsedQuery) : Array(Solution)
        query.blocks.flat_map { |block| solve_block(block, query.variables) }
      end

      # The order a query asks for, as positions in its rows: by the
      # ORDER BY keys, or without them by falling confidence. The keys are
      # read from all a row binds, not only what is selected.
      private def ordering(query : ParsedQuery, bindings : Array(Hash(String, AtomSpace::Atom)),
                           confidences : Array(Float64)) : Array(Int32)
        positions = (0...bindings.size).to_a
        if query.order.empty?
          positions.sort! { |a, b| confidences[b] <=> confidences[a] }
        else
          keys = bindings.map { |bound| query.order.map(&.value.evaluate(bound)) }
          positions.sort! do |a, b|
            order = 0
            query.order.each_with_index do |key, i|
              order = compare_keys(keys[a][i], keys[b][i])
              order = -order if key.descending
              break unless order == 0
            end
            order
          end
        end
        positions
      end

      # One template clause with the values of a match in place of its
      # variables, or nil when a variable has none.
      private def build(clause : QueryClause, bindings : Hash(String, AtomSpace::Atom), truth : AtomSpace::TruthValue) : AtomSpace::Atom?
        case clause
        when InheritanceClause
          child = template_term(clause.child, bindings) || return nil
          parent = template_term(clause.parent, bindings) || return nil
          AtomSpace::InheritanceLink.new(child, parent, truth)
        when TripleClause
          subject = template_term(clause.subject, bindings) || return nil
          predicate = template_term(clause.predicate, bindings, AtomSpace::AtomType::PREDICATE_NODE) || return nil
          object = template_term(clause.object, bindings) || return nil
          AtomSpace::EvaluationLink.new(predicate, AtomSpace::ListLink.new([subject, object]), truth)
        end
      end

      private def template_term(term : String | AtomSpace::Atom, bindings : Hash(String, AtomSpace::Atom),
                                preferred : AtomSpace::AtomType = AtomSpace::AtomType::CONCEPT_NODE) : AtomSpace::Atom?
        return bindings[term.lchop('$')]? if term.is_a?(String) && term.starts_with?('$')
        QueryLanguage.resolve_term(term, @atomspace, Hash(String, AtomSpace::Atom).new, preferred)
      end

      # What makes two built atoms the same atom.
      private def shape_of(atom : AtomSpace::Atom) : String
        return "#{atom.type}:#{atom.name}" unless atom.link?
        parts = [] of String
        atom.outgoing.each { |child| parts << shape_of(child) }
        "(#{atom.type} #{parts.join(" ")})"
      end

      # Add a built atom to an AtomSpace, parts first. A node that is
      # already there is used as it is.
      private def store(atom : AtomSpace::Atom, space : AtomSpace::AtomSpace) : AtomSpace::Atom
        unless atom.link?
          return space.get_nodes_by_name(atom.name, atom.type).first? || space.add_node(atom.type, atom.name, atom.truth_value)
        end
        parts = [] of AtomSpace::Atom
        atom.outgoing.each { |child| parts << store(child, space) }
        case atom.type
        when AtomSpace::AtomType::INHERITANCE_LINK then space.add_inheritance_link(parts[0], parts[1], atom.truth_value)
        when AtomSpace::AtomType::EVALUATION_LINK  then space.add_evaluation_link(parts[0], parts[1], atom.truth_value)
        when AtomSpace::AtomType::LIST_LINK        then space.add_list_link(parts, atom.truth_value)
        else                                            space.add_link(atom.type, parts, atom.truth_value)
        end
      end

      private def in_order(bindings : Hash(String, AtomSpace::Atom), names : Array(String)) : Hash(String, AtomSpace::Atom)
        ordered = Hash(String, AtomSpace::Atom).new
        names.each { |name| bindings[name]?.try { |atom| ordered[name] = atom } }
        ordered
      end

      # What makes two bound values the same. A node is its type and name:
      # the AtomSpace has one of each, and a value an aggregate or BIND
      # computed is a node beside it that has to compare equal to another
      # of the same value. A link is the atom itself.
      private def identity(atom : AtomSpace::Atom?) : String | AtomSpace::Handle | Nil
        return nil if atom.nil?
        atom.is_a?(AtomSpace::Node) ? "#{atom.type}:#{atom.name}" : atom.handle
      end

      # One row per group: the GROUP BY variables and each aggregate under
      # its name. Without GROUP BY all rows are one group, which exists even
      # when nothing matched, so that COUNT can say 0.
      private def aggregate(query : ParsedQuery, rows : Array({Hash(String, AtomSpace::Atom), Float64})) : Array({Hash(String, AtomSpace::Atom), Float64})
        groups = {} of Array(String | AtomSpace::Handle | Nil) => Array({Hash(String, AtomSpace::Atom), Float64})
        rows.each do |row|
          key = query.group_by.map { |name| identity(row[0][name]?) }
          (groups[key] ||= [] of {Hash(String, AtomSpace::Atom), Float64}) << row
        end
        if groups.empty? && query.group_by.empty?
          groups[[] of String | AtomSpace::Handle | Nil] = [] of {Hash(String, AtomSpace::Atom), Float64}
        end

        groups.values.map do |members|
          bindings = Hash(String, AtomSpace::Atom).new
          if first = members.first?
            query.group_by.each { |name| first[0][name]?.try { |atom| bindings[name] = atom } }
          end
          query.aggregates.each do |aggregate|
            aggregate_value(aggregate, members.map(&.[0])).try { |atom| bindings[aggregate.name] = atom }
          end
          confidence = members.empty? ? 0.0 : members.sum(&.[1]) / members.size
          {bindings, confidence}
        end
      end

      # The value of one aggregate over the rows of a group, as an atom, or
      # nil when it has none (the smallest of nothing, say).
      private def aggregate_value(aggregate : QueryAggregate, rows : Array(Hash(String, AtomSpace::Atom))) : AtomSpace::Atom?
        argument = aggregate.argument
        return QueryLanguage.number_atom(rows.size.to_f) if argument.nil?

        # MIN and MAX of a plain variable give the atom itself.
        variable = argument.variable?
        valued = rows.compact_map do |bindings|
          value = argument.evaluate(bindings)
          value.nil? ? nil : {value, variable ? bindings[variable]? : nil}
        end
        if aggregate.distinct
          seen = Set(String | Float64 | AtomSpace::Handle).new
          valued.select! { |(value, atom)| seen.add?(atom ? atom.handle : value) }
        end

        case aggregate.function
        when :count
          QueryLanguage.number_atom(valued.size.to_f)
        when :sum, :avg
          numbers = valued.compact_map { |(value, _)| QueryLanguage.number(value) }
          if aggregate.function == :sum
            QueryLanguage.number_atom(numbers.sum(0.0))
          elsif numbers.empty?
            nil
          else
            QueryLanguage.number_atom(numbers.sum / numbers.size)
          end
        else
          # Names that read as numbers compare as numbers here.
          ranked = valued.map { |(value, atom)| {QueryLanguage.number(value) || value, atom} }
          chosen = nil
          ranked.each do |candidate|
            if chosen.nil?
              chosen = candidate
            else
              order = compare_keys(candidate[0], chosen[0])
              chosen = candidate if aggregate.function == :min ? order < 0 : order > 0
            end
          end
          return nil unless chosen
          value, atom = chosen
          atom || (value.is_a?(Float64) ? QueryLanguage.number_atom(value) : AtomSpace::Node.new(AtomSpace::AtomType::CONCEPT_NODE, value.to_s))
        end
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
      # shared variables, OPTIONAL units joined where they match, and the
      # FILTER conditions applied.
      private def solve_block(block : QueryBlock, variables : Array(QueryVariable)) : Array({Hash(String, AtomSpace::Atom), Array(AtomSpace::Atom)})
        var_map = Hash(String, AtomSpace::Atom).new
        empty = [] of {Hash(String, AtomSpace::Atom), Array(AtomSpace::Atom)}
        return empty unless block.matches_something?

        # Typed query variables become constraints on every clause pattern.
        type_constraints = variables.compact_map do |var|
          next unless allowed = var.type
          var_atom = QueryLanguage.resolve_term("$#{var.name}", @atomspace, var_map)
          PatternMatching::TypeConstraint.new(var_atom, allowed)
        end

        # Match each clause on its own, then natural-join the solutions on
        # shared variable names (a conjunctive query).
        solutions = [{Hash(String, AtomSpace::Atom).new, Array(AtomSpace::Atom).new}]
        block.clauses.each do |clause|
          solutions = join(solutions, clause_solutions(clause, var_map, type_constraints, solutions))
          return empty if solutions.empty?
        end

        # VALUES: each row binds its variables to the atoms of those names.
        block.values.each do |data|
          rows = data.rows.map do |row|
            bound = Hash(String, AtomSpace::Atom).new
            row.each_with_index do |term, i|
              bound[data.names[i]] = QueryLanguage.resolve_term(term, @atomspace, var_map) if term
            end
            {bound, [] of AtomSpace::Atom}
          end
          solutions = join(solutions, rows)
          return empty if solutions.empty?
        end

        # A subquery: what it selects, joined with what the block has.
        block.subqueries.each do |subquery|
          rows = execute(subquery).map { |result| {result.bindings, [] of AtomSpace::Atom} }
          solutions = join(solutions, rows)
          return empty if solutions.empty?
        end

        # A group inside the block: the results of its alternatives, taken
        # together, joined with what the block has so far.
        block.groups.each do |alternatives|
          solutions = join(solutions, alternatives.flat_map { |alternative| solve_block(alternative, variables) })
          return empty if solutions.empty?
        end

        # An OPTIONAL enriches only with complete qualifying candidates.
        # Failure keeps each original outer row, with its evidence, once.
        block.optional_units.each do |unit|
          solutions = left_join_optional(solutions, unit, var_map, type_constraints)
        end

        # BIND gives a variable a computed value, where the value exists.
        block.binds.each do |bind|
          solutions = solutions.map do |(bound, matched)|
            atom = value_atom(bind.value, bound)
            atom ? {bound.merge({bind.name => atom}), matched} : {bound, matched}
          end
        end

        # MINUS leaves out a result that shares a variable with a result
        # of its block and agrees with it on all they share.
        block.minus.each do |unwanted|
          found = solve_block(unwanted, variables)
          next if found.empty?
          solutions.reject! do |(bound, _)|
            found.any? do |(other, _)|
              shared = 0
              agrees = other.all? do |name, atom|
                existing = bound[name]? || next true
                shared += 1
                existing.same?(atom) || identity(existing) == identity(atom)
              end
              agrees && shared > 0
            end
          end
        end

        block.filters.each do |condition|
          solutions.select! { |(bound, _)| condition.holds?(bound) }
        end
        solutions
      end

      private def left_join_optional(outer : Array(Solution), unit : QueryOptionalBlock,
                                     var_map : Hash(String, AtomSpace::Atom),
                                     type_constraints : Array(PatternMatching::TypeConstraint)) : Array(Solution)
        outer.flat_map do |row|
          candidates = [row]
          unit.clauses.each do |clause|
            candidates = join(candidates, clause_solutions(clause, var_map, type_constraints, candidates))
            break if candidates.empty?
          end
          # Conditions see both the original outer bindings and everything
          # the unit joined, regardless of where FILTER was written.
          unit.filters.each do |condition|
            candidates.select! { |(bound, _)| condition.holds?(bound) }
          end
          candidates.empty? ? [row] : candidates
        end
      end

      # Every way one clause matches. `known` is what the block has matched
      # so far, which tells a path where it need not look.
      private def clause_solutions(clause : QueryClause, var_map : Hash(String, AtomSpace::Atom),
                                   type_constraints : Array(PatternMatching::TypeConstraint),
                                   known : Array(Solution)) : Array(Solution)
        return path_solutions(clause, var_map, type_constraints, known) if clause.is_a?(PathClause)

        found = [{Hash(String, AtomSpace::Atom).new, Array(AtomSpace::Atom).new}]
        clause.to_atoms(@atomspace, var_map).each do |template|
          found = join(found, solve(template, type_constraints))
        end
        found
      end

      # The single links of a relation: from, to, and the link that says
      # so. Inheritance links when no relation is named, else the triples
      # of that predicate.
      private def path_steps(relation : String?, var_map : Hash(String, AtomSpace::Atom)) : Array({AtomSpace::Atom, AtomSpace::Atom, AtomSpace::Atom})
        steps = [] of {AtomSpace::Atom, AtomSpace::Atom, AtomSpace::Atom}
        if relation
          predicate = QueryLanguage.resolve_term(relation, @atomspace, var_map, AtomSpace::AtomType::PREDICATE_NODE)
          return steps unless @atomspace.contains?(predicate)
          @atomspace.get_incoming(predicate).each do |link|
            next unless link.type == AtomSpace::AtomType::EVALUATION_LINK
            parts = link.outgoing
            next unless parts.size == 2 && parts[0].handle == predicate.handle
            next unless parts[1].type == AtomSpace::AtomType::LIST_LINK
            ends = parts[1].outgoing
            steps << {ends[0], ends[1], link} if ends.size == 2
          end
        else
          @atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK).each do |link|
            parts = link.outgoing
            steps << {parts[0], parts[1], link} if parts.size == 2
          end
        end
        steps
      end

      # Where one end of a path may be: the atom a name stands for, the
      # values every match so far gives its variable, or anywhere (nil).
      # A name the AtomSpace does not know is nowhere.
      private def path_end(term : String, var_map : Hash(String, AtomSpace::Atom), known : Array(Solution)) : Array(AtomSpace::Atom)?
        unless term.starts_with?('$')
          atom = QueryLanguage.resolve_term(term, @atomspace, var_map)
          return @atomspace.contains?(atom) ? [atom] : [] of AtomSpace::Atom
        end
        name = term.lchop('$')
        return nil unless known.all? { |(bound, _)| bound.has_key?(name) }
        known.map { |(bound, _)| bound[name] }.uniq(&.handle)
      end

      # The links of each relation of a path, by the atom they leave and
      # by the atom they reach.
      alias PathLinks = Hash(String?, Hash(AtomSpace::Handle, Array({AtomSpace::Atom, AtomSpace::Atom})))

      # Every pair of atoms a path joins, with the links of a shortest
      # way between them as what was matched. The search goes breadth
      # first from whichever end is given, forwards by preference; from
      # the far end the path is read backwards.
      private def path_solutions(clause : PathClause, var_map : Hash(String, AtomSpace::Atom),
                                 type_constraints : Array(PatternMatching::TypeConstraint),
                                 known : Array(Solution)) : Array(Solution)
        starts = path_end(clause.subject, var_map, known)
        ends = path_end(clause.object, var_map, known)
        forwards = !starts.nil? || ends.nil?
        automaton = PathAutomaton.new(clause.path, inverted: !forwards)

        onward = PathLinks.new
        back = PathLinks.new
        touched = {} of AtomSpace::Handle => AtomSpace::Atom
        add = ->(relation : String?, steps : Array({AtomSpace::Atom, AtomSpace::Atom, AtomSpace::Atom})) do
          leaving = onward[relation] ||= {} of AtomSpace::Handle => Array({AtomSpace::Atom, AtomSpace::Atom})
          reaching = back[relation] ||= {} of AtomSpace::Handle => Array({AtomSpace::Atom, AtomSpace::Atom})
          steps.each do |(from, to, link)|
            (leaving[from.handle] ||= [] of {AtomSpace::Atom, AtomSpace::Atom}) << {to, link}
            (reaching[to.handle] ||= [] of {AtomSpace::Atom, AtomSpace::Atom}) << {from, link}
            touched[from.handle] = from
            touched[to.handle] = to
          end
          nil
        end
        automaton.relations.each { |relation| add.call(relation, path_steps(relation, var_map)) }
        # A step over any relation but some needs every relation there is:
        # inheritance, and the triples of each predicate, by its name.
        if automaton.any_relation?
          add.call(nil, path_steps(nil, var_map)) unless onward.has_key?(nil)
          by_name = {} of String => Array({AtomSpace::Atom, AtomSpace::Atom, AtomSpace::Atom})
          @atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK).each do |link|
            next unless link.is_a?(AtomSpace::Link) && link.arity == 2
            predicate = link[0]
            arguments = link[1]
            next if predicate.link? || !arguments.is_a?(AtomSpace::Link)
            next if arguments.type != AtomSpace::AtomType::LIST_LINK || arguments.arity != 2
            next if onward.has_key?(predicate.name)
            (by_name[predicate.name] ||= [] of {AtomSpace::Atom, AtomSpace::Atom, AtomSpace::Atom}) << {arguments[0], arguments[1], link}
          end
          by_name.each { |name, steps| add.call(name, steps) }
        end

        origins = (forwards ? starts : ends) || touched.values
        allowed = (forwards ? ends : starts).try(&.map(&.handle).to_set)
        subject = clause.subject.starts_with?('$') ? clause.subject.lchop('$') : nil
        object = clause.object.starts_with?('$') ? clause.object.lchop('$') : nil
        typed = type_constraints.map { |constraint| {constraint.variable.name.lchop('$'), constraint.allowed_types} }

        solutions = [] of Solution
        origins.each do |origin|
          reach(origin, automaton, onward, back).each do |(other, links)|
            next if allowed && !allowed.includes?(other.handle)
            from, to = forwards ? {origin, other} : {other, origin}
            next if subject && subject == object && from.handle != to.handle
            bound = Hash(String, AtomSpace::Atom).new
            bound[subject] = from if subject
            bound[object] = to if object
            next unless typed.all? { |(name, types)| (atom = bound[name]?).nil? || types.includes?(atom.type) }
            # The links in the order the path goes over them.
            solutions << {bound, forwards ? links.reverse : links}
          end
        end
        solutions
      end

      # Every atom the path's machine accepts from an origin, each once
      # with the links of a shortest way there, last link first. An atom
      # the path joins to itself over no link comes with no links, and
      # not a second time for a way round a circle.
      private def reach(origin : AtomSpace::Atom, automaton : PathAutomaton,
                        onward : PathLinks, back : PathLinks) : Array({AtomSpace::Atom, Array(AtomSpace::Atom)})
        seen = Set({AtomSpace::Handle, Int32}).new
        # How each pair of atom and state was first come to: the pair
        # before it and the link gone over.
        came = {} of {AtomSpace::Handle, Int32} => { {AtomSpace::Handle, Int32}, AtomSpace::Atom }
        accepted = {} of AtomSpace::Handle => {AtomSpace::Atom, {AtomSpace::Handle, Int32}?}
        waiting = Deque({AtomSpace::Atom, Int32}).new

        automaton.closure(automaton.start).each do |state|
          seen << {origin.handle, state}
          waiting << {origin, state}
        end
        accepted[origin.handle] = {origin, nil} if automaton.empty?

        until waiting.empty?
          atom, state = waiting.shift
          automaton.moves(state).each do |move|
            index = move.forward ? onward : back
            links = if left_out = move.except
                      # Every link of every relation but those left out.
                      found = [] of {AtomSpace::Atom, AtomSpace::Atom}
                      index.each do |relation, by_atom|
                        next if left_out.includes?(relation)
                        by_atom[atom.handle]?.try { |some| found.concat(some) }
                      end
                      found
                    else
                      index[move.relation]?.try(&.[atom.handle]?) || next
                    end
            links.each do |(to, link)|
              automaton.closure(move.target).each do |after|
                pair = {to.handle, after}
                next unless seen.add?(pair)
                came[pair] = { {atom.handle, state}, link }
                waiting << {to, after}
                accepted[to.handle] = {to, pair} if after == automaton.accept && !accepted.has_key?(to.handle)
              end
            end
          end
        end

        accepted.values.map do |(atom, pair)|
          links = [] of AtomSpace::Atom
          while pair && (step = came[pair]?)
            links << step[1]
            pair = step[0]
          end
          {atom, links}
        end
      end

      # Every pairing of a solution from each side that agrees on the
      # variables both have (a natural join).
      private def join(left : Array({Hash(String, AtomSpace::Atom), Array(AtomSpace::Atom)}),
                       right : Array({Hash(String, AtomSpace::Atom), Array(AtomSpace::Atom)})) : Array({Hash(String, AtomSpace::Atom), Array(AtomSpace::Atom)})
        left.flat_map do |(bound, matched)|
          right.compact_map do |(other_bound, other_matched)|
            next unless other_bound.all? { |name, atom| (existing = bound[name]?).nil? || existing.same?(atom) || identity(existing) == identity(atom) }
            {bound.merge(other_bound), matched + other_matched}
          end
        end
      end

      # A computed value as an atom a result can carry: the atom itself
      # for a plain variable, else a number or a name beside the AtomSpace.
      private def value_atom(value : QueryOperand, bindings : Hash(String, AtomSpace::Atom)) : AtomSpace::Atom?
        if value.is_a?(QueryCoalesce)
          value.arguments.each do |argument|
            atom = value_atom(argument, bindings)
            return atom unless atom.nil?
          end
          return nil
        end
        if variable = value.variable?
          return bindings[variable]?
        end
        case result = value.evaluate(bindings)
        when Float64 then QueryLanguage.number_atom(result)
        when String  then AtomSpace::Node.new(AtomSpace::AtomType::CONCEPT_NODE, result).as(AtomSpace::Atom)
        else              nil
        end
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

      # Whether a query matches anything: an ASK query, or any other.
      def ask(query_string : String) : Bool
        parsed = QueryParser.parse(query_string)
        parsed.form == :select ? !@executor.execute(parsed).empty? : @executor.ask(parsed)
      end

      # The atoms a CONSTRUCT query builds. They are added to `into` when
      # it is given, and stand beside the AtomSpace when it is not.
      def construct(query_string : String, into : AtomSpace::AtomSpace? = nil) : Array(AtomSpace::Atom)
        @executor.construct(QueryParser.parse(query_string), into)
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
