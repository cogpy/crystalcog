# CrystalCog MeTTa Integration
# Hypergraph Rewriting Language for Advanced AGI Reasoning
#
# This module provides MeTTa (Meta Type Talk) integration for CrystalCog,
# enabling hypergraph pattern matching, rewriting rules, and advanced
# meta-level reasoning capabilities.
#
# MeTTa is the core language of OpenCog Hyperon, providing:
# - Hypergraph pattern matching
# - Type-driven reasoning
# - Self-modifying programs
# - Meta-level operations

require "json"

module CrystalCog
  module Integrations
    # MeTTa Expression Types
    enum MeTTaType
      Symbol     # Basic symbol: foo, bar, +, *
      Variable   # Pattern variable: $x, $y
      Grounded   # Grounded atom with external value
      Expression # Compound expression: (foo bar baz)
      Space      # AtomSpace reference
      Lambda     # Lambda expression
      Quote      # Quoted expression
      Type       # Type annotation
      Empty      # Empty/void result
      Error      # Error value
    end

    # Base MeTTa Atom
    abstract class MeTTaAtom
      abstract def atom_type : MeTTaType
      abstract def to_metta : String
      abstract def ==(other : MeTTaAtom) : Bool
      abstract def matches?(pattern : MeTTaAtom) : Bool
      abstract def clone : MeTTaAtom

      def variable? : Bool
        atom_type == MeTTaType::Variable
      end

      def expression? : Bool
        atom_type == MeTTaType::Expression
      end

      def symbol? : Bool
        atom_type == MeTTaType::Symbol
      end

      def grounded? : Bool
        atom_type == MeTTaType::Grounded
      end
    end

    # Symbol Atom
    class MeTTaSymbol < MeTTaAtom
      getter name : String

      def initialize(@name : String)
      end

      def atom_type : MeTTaType
        MeTTaType::Symbol
      end

      def to_metta : String
        @name
      end

      def ==(other : MeTTaAtom) : Bool
        other.is_a?(MeTTaSymbol) && other.name == @name
      end

      def matches?(pattern : MeTTaAtom) : Bool
        pattern.variable? || self == pattern
      end

      def clone : MeTTaAtom
        MeTTaSymbol.new(@name)
      end

      def hash(hasher)
        hasher = @name.hash(hasher)
        hasher
      end
    end

    # Variable Atom (for pattern matching)
    class MeTTaVariable < MeTTaAtom
      getter name : String
      property type_constraint : MeTTaAtom?

      def initialize(@name : String, @type_constraint = nil)
      end

      def atom_type : MeTTaType
        MeTTaType::Variable
      end

      def to_metta : String
        if tc = @type_constraint
          "(: $#{@name} #{tc.to_metta})"
        else
          "$#{@name}"
        end
      end

      def ==(other : MeTTaAtom) : Bool
        other.is_a?(MeTTaVariable) && other.name == @name
      end

      def matches?(pattern : MeTTaAtom) : Bool
        # Variables match anything (subject to type constraints)
        if tc = @type_constraint
          # Type checking would go here
          true
        else
          true
        end
      end

      def clone : MeTTaAtom
        MeTTaVariable.new(@name, @type_constraint.try(&.clone))
      end
    end

    # Grounded Atom (external values)
    class MeTTaGrounded < MeTTaAtom
      getter value : JSON::Any
      getter value_type : String

      def initialize(@value : JSON::Any, @value_type = "Any")
      end

      def initialize(value : Int32 | Int64 | Float64 | String | Bool)
        @value = JSON.parse(value.to_json)
        @value_type = case value
                      when Int32, Int64 then "Number"
                      when Float64      then "Float"
                      when String       then "String"
                      when Bool         then "Bool"
                      else                   "Any"
                      end
      end

      def atom_type : MeTTaType
        MeTTaType::Grounded
      end

      def to_metta : String
        case @value_type
        when "String" then "\"#{@value.as_s}\""
        when "Number" then @value.to_s
        when "Float"  then @value.to_s
        when "Bool"   then @value.as_bool.to_s
        else               @value.to_json
        end
      end

      def ==(other : MeTTaAtom) : Bool
        other.is_a?(MeTTaGrounded) && other.value == @value
      end

      def matches?(pattern : MeTTaAtom) : Bool
        pattern.variable? || self == pattern
      end

      def clone : MeTTaAtom
        MeTTaGrounded.new(@value, @value_type)
      end

      def as_int : Int64?
        @value.as_i64?
      end

      def as_float : Float64?
        @value.as_f?
      end

      def as_string : String?
        @value.as_s?
      end

      def as_bool : Bool?
        @value.as_bool?
      end
    end

    # Expression Atom (compound structure)
    class MeTTaExpression < MeTTaAtom
      getter children : Array(MeTTaAtom)

      def initialize(@children = [] of MeTTaAtom)
      end

      def initialize(*atoms : MeTTaAtom)
        @children = atoms.to_a
      end

      def atom_type : MeTTaType
        MeTTaType::Expression
      end

      def to_metta : String
        "(#{@children.map(&.to_metta).join(" ")})"
      end

      def ==(other : MeTTaAtom) : Bool
        return false unless other.is_a?(MeTTaExpression)
        return false unless other.children.size == @children.size
        @children.each_with_index do |child, i|
          return false unless child == other.children[i]
        end
        true
      end

      def matches?(pattern : MeTTaAtom) : Bool
        return true if pattern.variable?
        return false unless pattern.is_a?(MeTTaExpression)
        return false unless pattern.children.size == @children.size
        @children.each_with_index do |child, i|
          return false unless child.matches?(pattern.children[i])
        end
        true
      end

      def clone : MeTTaAtom
        MeTTaExpression.new(@children.map(&.clone))
      end

      def head : MeTTaAtom?
        @children.first?
      end

      def tail : Array(MeTTaAtom)
        @children.size > 1 ? @children[1..] : [] of MeTTaAtom
      end

      def size : Int32
        @children.size
      end

      def empty? : Bool
        @children.empty?
      end

      def [](index : Int32) : MeTTaAtom?
        @children[index]?
      end

      def each(&block : MeTTaAtom -> Nil)
        @children.each { |c| block.call(c) }
      end

      def map(&block : MeTTaAtom -> MeTTaAtom) : MeTTaExpression
        MeTTaExpression.new(@children.map { |c| block.call(c) })
      end
    end

    # Empty/Unit value
    class MeTTaEmpty < MeTTaAtom
      def atom_type : MeTTaType
        MeTTaType::Empty
      end

      def to_metta : String
        "()"
      end

      def ==(other : MeTTaAtom) : Bool
        other.is_a?(MeTTaEmpty)
      end

      def matches?(pattern : MeTTaAtom) : Bool
        pattern.variable? || pattern.is_a?(MeTTaEmpty)
      end

      def clone : MeTTaAtom
        MeTTaEmpty.new
      end
    end

    # Error value
    class MeTTaError < MeTTaAtom
      getter message : String
      getter source : MeTTaAtom?

      def initialize(@message : String, @source = nil)
      end

      def atom_type : MeTTaType
        MeTTaType::Error
      end

      def to_metta : String
        if src = @source
          "(Error #{src.to_metta} \"#{@message}\")"
        else
          "(Error \"#{@message}\")"
        end
      end

      def ==(other : MeTTaAtom) : Bool
        other.is_a?(MeTTaError) && other.message == @message
      end

      def matches?(pattern : MeTTaAtom) : Bool
        pattern.variable? || self == pattern
      end

      def clone : MeTTaAtom
        MeTTaError.new(@message, @source.try(&.clone))
      end
    end

    # Binding context for pattern matching
    class MeTTaBindings
      @bindings : Hash(String, MeTTaAtom)

      def initialize
        @bindings = {} of String => MeTTaAtom
      end

      def initialize(@bindings : Hash(String, MeTTaAtom))
      end

      def bind(name : String, value : MeTTaAtom) : Bool
        if existing = @bindings[name]?
          existing == value
        else
          @bindings[name] = value
          true
        end
      end

      def get(name : String) : MeTTaAtom?
        @bindings[name]?
      end

      def [](name : String) : MeTTaAtom?
        get(name)
      end

      def has?(name : String) : Bool
        @bindings.has_key?(name)
      end

      def merge(other : MeTTaBindings) : MeTTaBindings?
        new_bindings = @bindings.dup
        other.@bindings.each do |name, value|
          if existing = new_bindings[name]?
            return nil unless existing == value
          else
            new_bindings[name] = value
          end
        end
        MeTTaBindings.new(new_bindings)
      end

      def apply(atom : MeTTaAtom) : MeTTaAtom
        case atom
        when MeTTaVariable
          @bindings[atom.name]? || atom
        when MeTTaExpression
          MeTTaExpression.new(atom.children.map { |c| apply(c) })
        else
          atom
        end
      end

      def clone : MeTTaBindings
        MeTTaBindings.new(@bindings.dup)
      end

      def to_s : String
        @bindings.map { |k, v| "$#{k} = #{v.to_metta}" }.join(", ")
      end

      def empty? : Bool
        @bindings.empty?
      end

      def size : Int32
        @bindings.size
      end
    end

    # Pattern Matcher
    class MeTTaPatternMatcher
      # Match atom against pattern, return bindings if successful
      def match(atom : MeTTaAtom, pattern : MeTTaAtom, bindings : MeTTaBindings = MeTTaBindings.new) : MeTTaBindings?
        case pattern
        when MeTTaVariable
          if bindings.bind(pattern.name, atom)
            bindings
          else
            nil
          end
        when MeTTaExpression
          return nil unless atom.is_a?(MeTTaExpression)
          return nil unless atom.children.size == pattern.children.size

          current_bindings = bindings
          pattern.children.each_with_index do |pat_child, i|
            result = match(atom.children[i], pat_child, current_bindings)
            return nil unless result
            current_bindings = result
          end
          current_bindings
        when MeTTaSymbol, MeTTaGrounded
          atom == pattern ? bindings : nil
        when MeTTaEmpty
          atom.is_a?(MeTTaEmpty) ? bindings : nil
        else
          nil
        end
      end

      # Match all atoms in space against pattern
      def match_all(atoms : Array(MeTTaAtom), pattern : MeTTaAtom) : Array(MeTTaBindings)
        results = [] of MeTTaBindings
        atoms.each do |atom|
          if bindings = match(atom, pattern)
            results << bindings
          end
        end
        results
      end

      # Unification - bidirectional matching
      def unify(atom1 : MeTTaAtom, atom2 : MeTTaAtom, bindings : MeTTaBindings = MeTTaBindings.new) : MeTTaBindings?
        a1 = bindings.apply(atom1)
        a2 = bindings.apply(atom2)

        case {a1, a2}
        when {MeTTaVariable, _}
          if bindings.bind(a1.name, a2)
            bindings
          else
            nil
          end
        when {_, MeTTaVariable}
          if bindings.bind(a2.name, a1)
            bindings
          else
            nil
          end
        when {MeTTaExpression, MeTTaExpression}
          return nil unless a1.children.size == a2.children.size

          current_bindings = bindings
          a1.children.each_with_index do |c1, i|
            result = unify(c1, a2.children[i], current_bindings)
            return nil unless result
            current_bindings = result
          end
          current_bindings
        when {MeTTaSymbol, MeTTaSymbol}
          a1.name == a2.name ? bindings : nil
        when {MeTTaGrounded, MeTTaGrounded}
          a1.value == a2.value ? bindings : nil
        else
          nil
        end
      end
    end

    # Rewrite Rule
    class MeTTaRule
      getter name : String
      getter pattern : MeTTaAtom
      getter template : MeTTaAtom
      getter guard : Proc(MeTTaBindings, Bool)?
      getter priority : Int32

      def initialize(
        @name : String,
        @pattern : MeTTaAtom,
        @template : MeTTaAtom,
        @guard = nil,
        @priority = 0
      )
      end

      def apply(atom : MeTTaAtom, matcher : MeTTaPatternMatcher) : MeTTaAtom?
        if bindings = matcher.match(atom, @pattern)
          # Check guard condition if present
          if g = @guard
            return nil unless g.call(bindings)
          end
          bindings.apply(@template)
        else
          nil
        end
      end

      def to_metta : String
        "(= #{@pattern.to_metta} #{@template.to_metta})"
      end
    end

    # MeTTa Space (AtomSpace equivalent)
    class MeTTaSpace
      @atoms : Array(MeTTaAtom)
      @rules : Array(MeTTaRule)
      @matcher : MeTTaPatternMatcher
      @name : String

      def initialize(@name = "default")
        @atoms = [] of MeTTaAtom
        @rules = [] of MeTTaRule
        @matcher = MeTTaPatternMatcher.new
      end

      # Add atom to space
      def add(atom : MeTTaAtom) : Bool
        return false if @atoms.includes?(atom)
        @atoms << atom
        true
      end

      # Remove atom from space
      def remove(atom : MeTTaAtom) : Bool
        idx = @atoms.index(atom)
        return false unless idx
        @atoms.delete_at(idx)
        true
      end

      # Check if atom exists
      def contains?(atom : MeTTaAtom) : Bool
        @atoms.includes?(atom)
      end

      # Get all atoms
      def atoms : Array(MeTTaAtom)
        @atoms.dup
      end

      # Add rewrite rule
      def add_rule(rule : MeTTaRule)
        @rules << rule
        # Sort by priority
        @rules.sort_by!(&.priority).reverse!
      end

      # Add rule from pattern and template
      def define(name : String, pattern : MeTTaAtom, template : MeTTaAtom, priority : Int32 = 0)
        add_rule(MeTTaRule.new(name, pattern, template, priority: priority))
      end

      # Query space with pattern
      def query(pattern : MeTTaAtom) : Array(MeTTaBindings)
        @matcher.match_all(@atoms, pattern)
      end

      # Query and return matched atoms
      def query_atoms(pattern : MeTTaAtom) : Array(MeTTaAtom)
        results = [] of MeTTaAtom
        @atoms.each do |atom|
          if @matcher.match(atom, pattern)
            results << atom
          end
        end
        results
      end

      # Apply rules to atom
      def reduce(atom : MeTTaAtom, max_steps : Int32 = 100) : MeTTaAtom
        current = atom
        steps = 0

        while steps < max_steps
          changed = false

          # Try each rule
          @rules.each do |rule|
            if result = rule.apply(current, @matcher)
              current = result
              changed = true
              break
            end
          end

          # Also try reducing sub-expressions
          if current.is_a?(MeTTaExpression) && !changed
            new_children = current.children.map do |child|
              reduced_child = reduce(child, max_steps - steps)
              if reduced_child != child
                changed = true
              end
              reduced_child
            end

            if changed
              current = MeTTaExpression.new(new_children)
            end
          end

          break unless changed
          steps += 1
        end

        current
      end

      # Bounds re-interpretation of rule rewrites so cyclic rules terminate
      MAX_INTERPRET_DEPTH = 64
      @interpret_depth = 0

      # Interpret/evaluate expression in this space
      def interpret(atom : MeTTaAtom) : Array(MeTTaAtom)
        case atom
        when MeTTaExpression
          head = atom.head
          case head
          when MeTTaSymbol
            case head.name
            when "match"
              interpret_match(atom)
            when "let"
              interpret_let(atom)
            when "let*"
              interpret_let_star(atom)
            when "if"
              interpret_if(atom)
            when "case"
              interpret_case(atom)
            when "quote"
              interpret_quote(atom)
            when "unquote"
              interpret_unquote(atom)
            when "collapse"
              interpret_collapse(atom)
            when "superpose"
              interpret_superpose(atom)
            when "="
              interpret_equality(atom)
            when "add-atom"
              interpret_add_atom(atom)
            when "remove-atom"
              interpret_remove_atom(atom)
            when "get-atoms"
              interpret_get_atoms(atom)
            when "+"
              interpret_arithmetic(atom, :add)
            when "-"
              interpret_arithmetic(atom, :sub)
            when "*"
              interpret_arithmetic(atom, :mul)
            when "/"
              interpret_arithmetic(atom, :div)
            when "=="
              interpret_comparison(atom, :eq)
            when "<"
              interpret_comparison(atom, :lt)
            when ">"
              interpret_comparison(atom, :gt)
            when "<="
              interpret_comparison(atom, :le)
            when ">="
              interpret_comparison(atom, :ge)
            when "and"
              interpret_logical(atom, :and)
            when "or"
              interpret_logical(atom, :or)
            when "not"
              interpret_logical(atom, :not)
            else
              # Try to apply rules, then evaluate what they rewrote to
              # (e.g. `(double 21)` -> `(* 2 21)` -> `42`)
              reduced = reduce(atom)
              if reduced.to_metta == atom.to_metta || @interpret_depth >= MAX_INTERPRET_DEPTH
                [reduced] of MeTTaAtom
              else
                @interpret_depth += 1
                begin
                  interpret(reduced)
                ensure
                  @interpret_depth -= 1
                end
              end
            end
          else
            # Non-symbol head - evaluate all children
            results = [atom] of MeTTaAtom
            atom.children.each_with_index do |child, i|
              new_results = [] of MeTTaAtom
              results.each do |r|
                interpret(child).each do |interp_child|
                  if r.is_a?(MeTTaExpression)
                    new_children = r.children.dup
                    new_children[i] = interp_child
                    new_results << MeTTaExpression.new(new_children)
                  end
                end
              end
              results = new_results unless new_results.empty?
            end
            results
          end
        when MeTTaVariable
          if bindings = query(atom).first?
            [bindings.apply(atom)] of MeTTaAtom
          else
            [atom] of MeTTaAtom
          end
        else
          [atom] of MeTTaAtom
        end
      end

      # Get space size
      def size : Int32
        @atoms.size
      end

      # Clear all atoms
      def clear
        @atoms.clear
      end

      # Export to MeTTa format
      def to_metta : String
        lines = [] of String
        @atoms.each do |atom|
          lines << atom.to_metta
        end
        @rules.each do |rule|
          lines << rule.to_metta
        end
        lines.join("\n")
      end

      private def interpret_match(expr : MeTTaExpression) : Array(MeTTaAtom)
        return [MeTTaError.new("match requires 3 arguments")] of MeTTaAtom unless expr.size == 4

        space_atom = expr[1]
        pattern = expr[2].not_nil!
        template = expr[3].not_nil!

        # Query this space (or referenced space)
        bindings_list = query(pattern)

        if bindings_list.empty?
          [MeTTaEmpty.new] of MeTTaAtom
        else
          bindings_list.map { |b| b.apply(template) }
        end
      end

      private def interpret_let(expr : MeTTaExpression) : Array(MeTTaAtom)
        return [MeTTaError.new("let requires 3 arguments")] of MeTTaAtom unless expr.size == 4

        var = expr[1]
        value_expr = expr[2].not_nil!
        body = expr[3].not_nil!

        return [MeTTaError.new("let first arg must be variable")] of MeTTaAtom unless var.is_a?(MeTTaVariable)

        values = interpret(value_expr)
        results = [] of MeTTaAtom

        values.each do |value|
          bindings = MeTTaBindings.new
          bindings.bind(var.name, value)
          results.concat(interpret(bindings.apply(body)))
        end

        results.empty? ? [MeTTaEmpty.new] of MeTTaAtom : results
      end

      private def interpret_let_star(expr : MeTTaExpression) : Array(MeTTaAtom)
        return [MeTTaError.new("let* requires 2 arguments")] of MeTTaAtom unless expr.size == 3

        bindings_expr = expr[1]
        body = expr[2].not_nil!

        return [MeTTaError.new("let* bindings must be expression")] of MeTTaAtom unless bindings_expr.is_a?(MeTTaExpression)

        current_bindings = MeTTaBindings.new

        bindings_expr.children.each_slice(2) do |pair|
          next unless pair.size == 2
          var = pair[0]
          value_expr = pair[1]

          next unless var.is_a?(MeTTaVariable)

          values = interpret(current_bindings.apply(value_expr))
          if value = values.first?
            current_bindings.bind(var.name, value)
          end
        end

        interpret(current_bindings.apply(body))
      end

      private def interpret_if(expr : MeTTaExpression) : Array(MeTTaAtom)
        return [MeTTaError.new("if requires 3 arguments")] of MeTTaAtom unless expr.size == 4

        condition = expr[1].not_nil!
        then_branch = expr[2].not_nil!
        else_branch = expr[3].not_nil!

        cond_results = interpret(condition)
        results = [] of MeTTaAtom

        cond_results.each do |cond|
          if is_truthy?(cond)
            results.concat(interpret(then_branch))
          else
            results.concat(interpret(else_branch))
          end
        end

        results.empty? ? [MeTTaEmpty.new] of MeTTaAtom : results
      end

      private def interpret_case(expr : MeTTaExpression) : Array(MeTTaAtom)
        return [MeTTaError.new("case requires at least 2 arguments")] of MeTTaAtom unless expr.size >= 3

        scrutinee = expr[1].not_nil!
        cases = expr.children[2..]

        scrutinee_values = interpret(scrutinee)
        results = [] of MeTTaAtom

        scrutinee_values.each do |value|
          cases.each do |case_expr|
            next unless case_expr.is_a?(MeTTaExpression) && case_expr.size == 2

            pattern = case_expr[0].not_nil!
            body = case_expr[1].not_nil!

            if bindings = @matcher.match(value, pattern)
              results.concat(interpret(bindings.apply(body)))
              break
            end
          end
        end

        results.empty? ? [MeTTaEmpty.new] of MeTTaAtom : results
      end

      private def interpret_quote(expr : MeTTaExpression) : Array(MeTTaAtom)
        return [MeTTaError.new("quote requires 1 argument")] of MeTTaAtom unless expr.size == 2
        [expr[1].not_nil!]
      end

      private def interpret_unquote(expr : MeTTaExpression) : Array(MeTTaAtom)
        return [MeTTaError.new("unquote requires 1 argument")] of MeTTaAtom unless expr.size == 2
        interpret(expr[1].not_nil!)
      end

      private def interpret_collapse(expr : MeTTaExpression) : Array(MeTTaAtom)
        return [MeTTaError.new("collapse requires 1 argument")] of MeTTaAtom unless expr.size == 2
        results = interpret(expr[1].not_nil!)
        [MeTTaExpression.new(results)] of MeTTaAtom
      end

      private def interpret_superpose(expr : MeTTaExpression) : Array(MeTTaAtom)
        return [MeTTaError.new("superpose requires 1 argument")] of MeTTaAtom unless expr.size == 2

        arg = expr[1]
        return [MeTTaEmpty.new] of MeTTaAtom unless arg.is_a?(MeTTaExpression)

        arg.children.flat_map { |child| interpret(child) }
      end

      private def interpret_equality(expr : MeTTaExpression) : Array(MeTTaAtom)
        return [MeTTaError.new("= requires 2 arguments")] of MeTTaAtom unless expr.size == 3

        pattern = expr[1].not_nil!
        template = expr[2].not_nil!

        # Add as rewrite rule
        rule = MeTTaRule.new("user-rule-#{@rules.size}", pattern, template)
        add_rule(rule)

        [MeTTaEmpty.new] of MeTTaAtom
      end

      private def interpret_add_atom(expr : MeTTaExpression) : Array(MeTTaAtom)
        return [MeTTaError.new("add-atom requires 2 arguments")] of MeTTaAtom unless expr.size == 3

        atom = expr[2].not_nil!
        add(atom)
        [MeTTaEmpty.new] of MeTTaAtom
      end

      private def interpret_remove_atom(expr : MeTTaExpression) : Array(MeTTaAtom)
        return [MeTTaError.new("remove-atom requires 2 arguments")] of MeTTaAtom unless expr.size == 3

        atom = expr[2].not_nil!
        remove(atom)
        [MeTTaEmpty.new] of MeTTaAtom
      end

      private def interpret_get_atoms(expr : MeTTaExpression) : Array(MeTTaAtom)
        [MeTTaExpression.new(@atoms.dup)] of MeTTaAtom
      end

      private def interpret_arithmetic(expr : MeTTaExpression, op : Symbol) : Array(MeTTaAtom)
        args = expr.tail.flat_map { |a| interpret(a) }

        numbers = args.compact_map do |a|
          case a
          when MeTTaGrounded then a.as_float || a.as_int.try(&.to_f64)
          else                    nil
          end
        end

        return [MeTTaError.new("Arithmetic requires numeric arguments")] of MeTTaAtom if numbers.size != args.size

        result = case op
                 when :add then numbers.reduce(0.0) { |acc, n| acc + n }
                 when :sub then numbers.size > 1 ? numbers[1..].reduce(numbers[0]) { |acc, n| acc - n } : -numbers[0]
                 when :mul then numbers.reduce(1.0) { |acc, n| acc * n }
                 when :div then numbers[1..].reduce(numbers[0]) { |acc, n| acc / n }
                 else           0.0
                 end

        [MeTTaGrounded.new(result)] of MeTTaAtom
      end

      private def interpret_comparison(expr : MeTTaExpression, op : Symbol) : Array(MeTTaAtom)
        return [MeTTaError.new("Comparison requires 2 arguments")] of MeTTaAtom unless expr.size == 3

        left_results = interpret(expr[1].not_nil!)
        right_results = interpret(expr[2].not_nil!)

        results = [] of MeTTaAtom

        left_results.each do |left|
          right_results.each do |right|
            left_val = extract_number(left)
            right_val = extract_number(right)

            next unless left_val && right_val

            result = case op
                     when :eq then left_val == right_val
                     when :lt then left_val < right_val
                     when :gt then left_val > right_val
                     when :le then left_val <= right_val
                     when :ge then right_val >= right_val
                     else          false
                     end

            results << MeTTaSymbol.new(result ? "True" : "False")
          end
        end

        results.empty? ? [MeTTaError.new("Comparison failed")] of MeTTaAtom : results
      end

      private def interpret_logical(expr : MeTTaExpression, op : Symbol) : Array(MeTTaAtom)
        case op
        when :not
          return [MeTTaError.new("not requires 1 argument")] of MeTTaAtom unless expr.size == 2
          results = interpret(expr[1].not_nil!)
          results.map { |r| MeTTaSymbol.new(is_truthy?(r) ? "False" : "True").as(MeTTaAtom) }
        when :and
          args = expr.tail
          all_true = args.all? do |arg|
            interpret(arg).all? { |r| is_truthy?(r) }
          end
          [MeTTaSymbol.new(all_true ? "True" : "False")] of MeTTaAtom
        when :or
          args = expr.tail
          any_true = args.any? do |arg|
            interpret(arg).any? { |r| is_truthy?(r) }
          end
          [MeTTaSymbol.new(any_true ? "True" : "False")] of MeTTaAtom
        else
          [MeTTaError.new("Unknown logical operation")] of MeTTaAtom
        end
      end

      private def is_truthy?(atom : MeTTaAtom) : Bool
        case atom
        when MeTTaSymbol then atom.name != "False" && atom.name != "Nil"
        when MeTTaGrounded
          if b = atom.as_bool
            b
          elsif n = atom.as_float
            n != 0.0
          elsif s = atom.as_string
            !s.empty?
          else
            true
          end
        when MeTTaEmpty then false
        when MeTTaError then false
        else                 true
        end
      end

      private def extract_number(atom : MeTTaAtom) : Float64?
        case atom
        when MeTTaGrounded then atom.as_float || atom.as_int.try(&.to_f64)
        else                    nil
        end
      end
    end

    # MeTTa Parser
    class MeTTaParser
      @input : String
      @pos : Int32

      def initialize(@input : String)
        @pos = 0
      end

      def parse : Array(MeTTaAtom)
        atoms = [] of MeTTaAtom
        while @pos < @input.size
          skip_whitespace_and_comments
          break if @pos >= @input.size
          atoms << parse_atom
        end
        atoms
      end

      def parse_atom : MeTTaAtom
        skip_whitespace_and_comments
        raise "Unexpected end of input" if @pos >= @input.size

        char = @input[@pos]

        case char
        when '('
          parse_expression
        when '"'
          parse_string
        when '$'
          parse_variable
        when ')'
          raise "Unexpected ')'"
        else
          if char.ascii_number? || (char == '-' && @pos + 1 < @input.size && @input[@pos + 1].ascii_number?)
            parse_number
          else
            parse_symbol
          end
        end
      end

      private def parse_expression : MeTTaExpression
        expect('(')
        children = [] of MeTTaAtom

        loop do
          skip_whitespace_and_comments
          break if @pos >= @input.size
          break if @input[@pos] == ')'
          children << parse_atom
        end

        expect(')')
        MeTTaExpression.new(children)
      end

      private def parse_symbol : MeTTaSymbol
        start = @pos
        while @pos < @input.size && !delimiter?(@input[@pos])
          @pos += 1
        end
        name = @input[start...@pos]
        MeTTaSymbol.new(name)
      end

      private def parse_variable : MeTTaVariable
        expect('$')
        start = @pos
        while @pos < @input.size && !delimiter?(@input[@pos])
          @pos += 1
        end
        name = @input[start...@pos]
        MeTTaVariable.new(name)
      end

      private def parse_string : MeTTaGrounded
        expect('"')
        start = @pos
        escaped = false

        while @pos < @input.size
          char = @input[@pos]
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == '"'
            break
          end
          @pos += 1
        end

        value = @input[start...@pos]
        expect('"')
        MeTTaGrounded.new(value)
      end

      private def parse_number : MeTTaGrounded
        start = @pos
        has_dot = false

        if @input[@pos] == '-'
          @pos += 1
        end

        while @pos < @input.size
          char = @input[@pos]
          if char.ascii_number?
            @pos += 1
          elsif char == '.' && !has_dot
            has_dot = true
            @pos += 1
          else
            break
          end
        end

        num_str = @input[start...@pos]
        if has_dot
          MeTTaGrounded.new(num_str.to_f64)
        else
          MeTTaGrounded.new(num_str.to_i64)
        end
      end

      private def skip_whitespace_and_comments
        while @pos < @input.size
          char = @input[@pos]
          if char.whitespace?
            @pos += 1
          elsif char == ';'
            # Line comment
            while @pos < @input.size && @input[@pos] != '\n'
              @pos += 1
            end
          else
            break
          end
        end
      end

      private def expect(char : Char)
        if @pos >= @input.size || @input[@pos] != char
          raise "Expected '#{char}' at position #{@pos}"
        end
        @pos += 1
      end

      private def delimiter?(char : Char) : Bool
        char.whitespace? || char == '(' || char == ')' || char == '"' || char == ';'
      end
    end

    # MeTTa Interpreter
    class MeTTaInterpreter
      @spaces : Hash(String, MeTTaSpace)
      @current_space : MeTTaSpace
      @stdlib_loaded : Bool

      def initialize
        @spaces = {} of String => MeTTaSpace
        @current_space = MeTTaSpace.new("default")
        @spaces["default"] = @current_space
        @stdlib_loaded = false
      end

      # Load standard library
      def load_stdlib
        return if @stdlib_loaded

        stdlib = <<-METTA
          ; Identity function
          (= (id $x) $x)

          ; Function composition
          (= (compose $f $g $x) ($f ($g $x)))

          ; List operations
          (= (head ($x . $xs)) $x)
          (= (tail ($x . $xs)) $xs)
          (= (cons $x $xs) ($x . $xs))
          (= (nil? ()) True)
          (= (nil? ($x . $xs)) False)

          ; Boolean operations
          (= (bool-not True) False)
          (= (bool-not False) True)

          ; Equality
          (= (eq $x $x) True)

          ; Type predicates
          (= (symbol? $x) (: $x Symbol))
          (= (expression? $x) (: $x Expression))
        METTA

        run(stdlib)
        @stdlib_loaded = true
      end

      # Create or switch to space
      def use_space(name : String) : MeTTaSpace
        unless @spaces.has_key?(name)
          @spaces[name] = MeTTaSpace.new(name)
        end
        @current_space = @spaces[name]
        @current_space
      end

      # Get current space
      def space : MeTTaSpace
        @current_space
      end

      # Run MeTTa code
      def run(code : String) : Array(MeTTaAtom)
        parser = MeTTaParser.new(code)
        atoms = parser.parse

        results = [] of MeTTaAtom
        atoms.each do |atom|
          results.concat(@current_space.interpret(atom))
        end
        results
      end

      # Run and get single result
      def eval(code : String) : MeTTaAtom?
        results = run(code)
        results.first?
      end

      # Add atom to current space
      def add(atom : MeTTaAtom)
        @current_space.add(atom)
      end

      # Query current space
      def query(pattern : String) : Array(MeTTaBindings)
        parser = MeTTaParser.new(pattern)
        atoms = parser.parse
        return [] of MeTTaBindings if atoms.empty?
        @current_space.query(atoms.first)
      end

      # REPL
      def repl
        puts "MeTTa REPL v0.1.0"
        puts "Type 'exit' to quit"
        puts ""

        loop do
          print "metta> "
          line = gets
          break if line.nil? || line.strip == "exit"
          next if line.strip.empty?

          begin
            results = run(line)
            results.each do |result|
              puts "=> #{result.to_metta}"
            end
          rescue ex
            puts "Error: #{ex.message}"
          end
        end
      end
    end

    # MeTTa AtomSpace Bridge
    class MeTTaAtomSpaceBridge
      @interpreter : MeTTaInterpreter

      def initialize(@interpreter = MeTTaInterpreter.new)
      end

      # Convert CrystalCog atom to MeTTa
      def to_metta_atom(
        atom_type : String,
        name : String?,
        outgoing : Array(MeTTaAtom) = [] of MeTTaAtom
      ) : MeTTaAtom
        if outgoing.empty?
          # Node
          children = [MeTTaSymbol.new(atom_type)] of MeTTaAtom
          children << MeTTaGrounded.new(name.not_nil!) if name
          MeTTaExpression.new(children)
        else
          # Link
          children = [MeTTaSymbol.new(atom_type)] of MeTTaAtom
          children.concat(outgoing)
          MeTTaExpression.new(children)
        end
      end

      # Execute MeTTa code and return results
      def execute(code : String) : Array(MeTTaAtom)
        @interpreter.run(code)
      end

      # Apply MeTTa pattern matching on atoms
      def match_pattern(atoms : Array(MeTTaAtom), pattern : String) : Array(MeTTaBindings)
        parser = MeTTaParser.new(pattern)
        parsed = parser.parse
        return [] of MeTTaBindings if parsed.empty?

        matcher = MeTTaPatternMatcher.new
        matcher.match_all(atoms, parsed.first)
      end
    end

    # MeTTa Configuration
    class MeTTaConfig
      property load_stdlib : Bool
      property max_reduction_steps : Int32
      property enable_trace : Bool
      property default_space_name : String

      def initialize(
        @load_stdlib = true,
        @max_reduction_steps = 1000,
        @enable_trace = false,
        @default_space_name = "default"
      )
      end
    end

    # Unified MeTTa Integration wrapper (follows Phase 5 patterns)
    class MeTTaIntegration
      VERSION = "0.3.0"

      property config : MeTTaConfig
      property interpreter : MeTTaInterpreter
      property atomspace : AtomSpace::AtomSpace?
      property bridge : MeTTaAtomSpaceBridge
      property initialized : Bool
      property expressions_evaluated : Int64
      property rules_defined : Int64
      property patterns_matched : Int64

      def initialize(@config = MeTTaConfig.new)
        @interpreter = MeTTaInterpreter.new
        @bridge = MeTTaAtomSpaceBridge.new(@interpreter)
        @atomspace = nil
        @initialized = false
        @expressions_evaluated = 0_i64
        @rules_defined = 0_i64
        @patterns_matched = 0_i64
      end

      # Attach AtomSpace (Phase 5 pattern)
      def attach_atomspace(atomspace : AtomSpace::AtomSpace)
        @atomspace = atomspace
      end

      # Initialize backend (Phase 5 pattern)
      def initialize_backend : Bool
        return true if @initialized

        if @config.load_stdlib
          @interpreter.load_stdlib
        end

        @initialized = true
        true
      end

      # Status reporting (Phase 5 pattern)
      def status : Hash(String, String)
        space = @interpreter.space

        {
          "integration"           => "metta",
          "version"               => VERSION,
          "status"                => @initialized ? "ready" : "not_initialized",
          "atomspace_attached"    => (!@atomspace.nil?).to_s,
          "stdlib_loaded"         => @config.load_stdlib.to_s,
          "space_name"            => space.@name,
          "space_size"            => space.size.to_s,
          "expressions_evaluated" => @expressions_evaluated.to_s,
          "rules_defined"         => @rules_defined.to_s,
          "patterns_matched"      => @patterns_matched.to_s,
          "max_reduction_steps"   => @config.max_reduction_steps.to_s,
          "trace_enabled"         => @config.enable_trace.to_s,
        }
      end

      # Run MeTTa code
      def run(code : String) : Array(MeTTaAtom)
        @expressions_evaluated += 1
        @interpreter.run(code)
      end

      # Evaluate single expression
      def eval(code : String) : MeTTaAtom?
        @expressions_evaluated += 1
        @interpreter.eval(code)
      end

      # Define a rewrite rule
      def define_rule(name : String, pattern : String, template : String)
        @interpreter.run("(= #{pattern} #{template})")
        @rules_defined += 1
      end

      # Query the space
      def query(pattern : String) : Array(MeTTaBindings)
        @patterns_matched += 1
        @interpreter.query(pattern)
      end

      # Add atom to space
      def add_atom(atom : MeTTaAtom)
        @interpreter.add(atom)
      end

      # Create and add atom from string
      def add(metta_code : String)
        parser = MeTTaParser.new(metta_code)
        atoms = parser.parse
        atoms.each { |atom| @interpreter.add(atom) }
      end

      # Use a different space
      def use_space(name : String) : MeTTaSpace
        @interpreter.use_space(name)
      end

      # Get current space
      def space : MeTTaSpace
        @interpreter.space
      end

      # Export space to MeTTa format
      def export : String
        @interpreter.space.to_metta
      end

      # Convert AtomSpace atom to MeTTa
      def atomspace_to_metta(atom_type : String, name : String?, outgoing : Array(MeTTaAtom) = [] of MeTTaAtom) : MeTTaAtom
        @bridge.to_metta_atom(atom_type, name, outgoing)
      end

      # Start REPL
      def repl
        @interpreter.repl
      end

      # Disconnect
      def disconnect
        @initialized = false
      end

      # Link to cognitive agency (Phase 5 pattern)
      def link_component(name : String)
        # Cognitive agency linking support
      end
    end
  end

  # Module-level factory methods (Phase 5 pattern)
  module MeTTa
    def self.create_default_integration : Integrations::MeTTaIntegration
      Integrations::MeTTaIntegration.new
    end

    def self.create_integration(
      load_stdlib : Bool = true,
      max_steps : Int32 = 1000
    ) : Integrations::MeTTaIntegration
      config = Integrations::MeTTaConfig.new(
        load_stdlib: load_stdlib,
        max_reduction_steps: max_steps
      )
      Integrations::MeTTaIntegration.new(config)
    end

    def self.create_integration(config : Integrations::MeTTaConfig) : Integrations::MeTTaIntegration
      Integrations::MeTTaIntegration.new(config)
    end
  end
end

# Main entry point
if PROGRAM_NAME.includes?("metta_integration")
  puts "🧠 CrystalCog MeTTa Integration v0.1.0"
  puts "=" * 50
  puts ""
  puts "Hypergraph rewriting language for AGI reasoning"
  puts ""
  puts "Features:"
  puts "  • Hypergraph pattern matching"
  puts "  • Rewrite rules and reduction"
  puts "  • Type-driven reasoning"
  puts "  • Meta-level operations"
  puts "  • Non-deterministic computation (superpose)"
  puts "  • REPL for interactive exploration"
  puts ""
  puts "Usage:"
  puts "  interpreter = MeTTaInterpreter.new"
  puts "  interpreter.load_stdlib"
  puts ""
  puts "  # Define a rule"
  puts "  interpreter.run(\"(= (greet $name) (Hello $name))\")"
  puts ""
  puts "  # Apply the rule"
  puts "  result = interpreter.eval(\"(greet World)\")"
  puts "  # => (Hello World)"
  puts ""

  # Demo
  puts "Running demo..."
  puts ""

  interpreter = CrystalCog::Integrations::MeTTaInterpreter.new
  interpreter.load_stdlib

  # Basic arithmetic
  puts "Arithmetic: (+ 1 2 3)"
  result = interpreter.eval("(+ 1 2 3)")
  puts "=> #{result.try(&.to_metta) || "nil"}"
  puts ""

  # Pattern matching
  puts "Pattern matching: (match &self (Person $name) $name)"
  interpreter.run("(add-atom &self (Person Alice))")
  interpreter.run("(add-atom &self (Person Bob))")
  results = interpreter.run("(match &self (Person $name) $name)")
  puts "=> #{results.map(&.to_metta).join(", ")}"
  puts ""

  # Rewrite rules
  puts "Rewrite rule: (= (double $x) (* 2 $x))"
  interpreter.run("(= (double $x) (* 2 $x))")
  result = interpreter.eval("(double 21)")
  puts "=> #{result.try(&.to_metta) || "nil"}"
end
