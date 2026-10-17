# Recursive parser for FileStorage's Scheme-style atom format.
#
# Parsing is deliberately detached from AtomSpace mutation. FileStorage parses the
# entire document first, then canonicalizes the resulting atoms into its target
# AtomSpace, so malformed input cannot leave a partially loaded target graph.

require "./atom"
require "./truthvalue"

module AtomSpace
  class SchemeStorageParseError < Exception
  end

  class SchemeStorageParser
    MAX_NESTING = 256

    @characters : Array(Char)
    @position : Int32

    def initialize(source : String, @max_nesting : Int32 = MAX_NESTING)
      @characters = source.chars
      @position = 0
    end

    def parse_document : Array(Atom)
      atoms = [] of Atom
      skip_ignored

      until eof?
        atoms << parse_atom(1)
        skip_ignored
      end

      atoms
    end

    private def parse_atom(depth : Int32) : Atom
      fail_parse("maximum nesting depth of #{@max_nesting} exceeded") if depth > @max_nesting

      expect('(')
      type_name = read_symbol
      type = parse_atom_type(type_name)

      if type.node?
        parse_node(type)
      else
        parse_link(type, depth)
      end
    end

    private def parse_node(type : AtomType) : Atom
      skip_ignored
      name = parse_string
      truth_value = TruthValue::DEFAULT_TV
      attention_value = nil.as(AttentionValue?)
      found_truth_value = false
      found_attention_value = false

      loop do
        skip_ignored
        break unless current_char == '('

        if starts_truth_value?
          fail_parse("multiple truth values for #{type}") if found_truth_value
          truth_value = parse_truth_value
          found_truth_value = true
        elsif starts_attention_value?
          fail_parse("multiple attention values for #{type}") if found_attention_value
          attention_value = parse_attention_value
          found_attention_value = true
        else
          fail_parse("expected truth or attention value for #{type}")
        end
      end

      expect(')')
      node = build_node(type, name, truth_value)
      node.attention_value = attention_value
      node
    end

    # These subclasses carry semantic API beyond their AtomType (notably
    # NumberNode#value). Other node types currently have no distinct Crystal
    # behavior and are deliberately restored as the generic Node type.
    private def build_node(type : AtomType, name : String, truth_value : TruthValue) : Node
      case type
      when AtomType::CONCEPT_NODE
        ConceptNode.new(name, truth_value)
      when AtomType::PREDICATE_NODE
        PredicateNode.new(name, truth_value)
      when AtomType::VARIABLE_NODE
        VariableNode.new(name, truth_value)
      when AtomType::NUMBER_NODE
        parse_number_node_value(name)
        NumberNode.new(name, truth_value)
      else
        Node.new(type, name, truth_value)
      end
    end

    private def parse_number_node_value(name : String) : Float64
      value = name.to_f64
      fail_parse("invalid NumberNode value '#{name}'") unless value.finite?
      value
    rescue ex : ArgumentError
      fail_parse("invalid NumberNode value '#{name}'")
    end

    private def parse_link(type : AtomType, depth : Int32) : Atom
      outgoing = [] of Atom
      truth_value = TruthValue::DEFAULT_TV
      attention_value = nil.as(AttentionValue?)
      found_truth_value = false
      found_attention_value = false

      loop do
        skip_ignored
        case current_char
        when ')'
          @position += 1
          break
        when '('
          if starts_truth_value?
            fail_parse("multiple truth values for #{type}") if found_truth_value
            truth_value = parse_truth_value
            found_truth_value = true
          elsif starts_attention_value?
            fail_parse("multiple attention values for #{type}") if found_attention_value
            attention_value = parse_attention_value
            found_attention_value = true
          else
            fail_parse("atom follows metadata for #{type}") if found_truth_value || found_attention_value
            outgoing << parse_atom(depth + 1)
          end
        else
          fail_parse("expected nested atom, truth value, or ')' for #{type}")
        end
      end

      link = Link.new(type, outgoing, truth_value)
      link.attention_value = attention_value
      link
    end

    # New files use `(tv TruthValueClass values...)`. The parenthesized numeric
    # pair is also accepted for compatibility with the original FileStorage
    # serializer, which emitted `(strength, confidence)` without a type tag.
    private def parse_truth_value : TruthValue
      expect('(')
      head = read_symbol

      if head == "tv"
        parse_tagged_truth_value
      else
        first = parse_float(head)
        skip_ignored
        @position += 1 if current_char == ','
        second = parse_number
        expect(')')
        SimpleTruthValue.new(first, second)
      end
    end

    private def parse_tagged_truth_value : TruthValue
      type_name = read_symbol
      values = [] of Float64

      loop do
        skip_ignored
        if current_char == ')'
          @position += 1
          break
        end
        values << parse_number
      end

      case type_name
      when "SimpleTruthValue", "simple", "stv"
        expect_truth_value_arity(type_name, values, 2)
        SimpleTruthValue.new(values[0], values[1])
      when "CountTruthValue", "count", "ctv"
        expect_truth_value_arity(type_name, values, 3)
        CountTruthValue.new(values[0], values[1], values[2])
      when "IndefiniteTruthValue", "indefinite", "itv"
        expect_truth_value_arity(type_name, values, 3)
        IndefiniteTruthValue.new(values[0], values[1], values[2])
      when "FuzzyTruthValue", "fuzzy", "ftv"
        expect_truth_value_arity(type_name, values, 3)
        FuzzyTruthValue.new(values[0], values[1], values[2])
      else
        fail_parse("unsupported truth value type '#{type_name}'")
      end
    end

    private def expect_truth_value_arity(type_name : String, values : Array(Float64), expected : Int32)
      return if values.size == expected
      fail_parse("#{type_name} expects #{expected} values, got #{values.size}")
    end

    private def parse_atom_type(type_name : String) : AtomType
      type = AtomType.parse(type_name)
      return type if type.node? || type.link?

      fail_parse("unsupported atom type '#{type_name}'")
    rescue ex : ArgumentError
      fail_parse("unknown atom type '#{type_name}'")
    end

    private def starts_truth_value? : Bool
      saved_position = @position
      begin
        expect('(')
        head = read_symbol
        head == "tv" || numeric_token?(head)
      rescue SchemeStorageParseError
        false
      ensure
        @position = saved_position
      end
    end

    private def starts_attention_value? : Bool
      saved_position = @position
      begin
        expect('(')
        read_symbol == "av"
      rescue SchemeStorageParseError
        false
      ensure
        @position = saved_position
      end
    end

    private def parse_attention_value : AttentionValue
      expect('(')
      head = read_symbol
      fail_parse("expected attention value") unless head == "av"

      sti = parse_int16
      lti = parse_int16
      vlti = case read_symbol
             when "true"
               true
             when "false"
               false
             else
               fail_parse("attention VLTI must be true or false")
             end
      expect(')')
      AttentionValue.new(sti, lti, vlti)
    end

    private def parse_number : Float64
      parse_float(read_symbol)
    end

    private def parse_int16 : Int16
      read_symbol.to_i16
    rescue ex : ArgumentError | OverflowError
      fail_parse("invalid Int16 value")
    end

    private def parse_float(token : String) : Float64
      value = token.to_f64
      fail_parse("invalid numeric value '#{token}'") unless value.finite?
      value
    rescue ex : ArgumentError
      fail_parse("invalid numeric value '#{token}'")
    end

    private def numeric_token?(token : String) : Bool
      parse_float(token)
      true
    rescue SchemeStorageParseError
      false
    end

    private def parse_string : String
      expect('"')
      value = String::Builder.new

      loop do
        char = advance
        case char
        when '"'
          return value.to_s
        when '\\'
          append_escaped_character(value)
        when '\n', '\r'
          fail_parse("unterminated string literal")
        else
          value << char
        end
      end
    end

    private def append_escaped_character(value : String::Builder)
      case escape = advance
      when '"'
        value << '"'
      when '\\'
        value << '\\'
      when 'n'
        value << '\n'
      when 'r'
        value << '\r'
      when 't'
        value << '\t'
      when 'b'
        value << '\b'
      when 'f'
        value << '\f'
      when 'u'
        value << parse_unicode_escape
      else
        fail_parse("unsupported string escape \\#{escape}")
      end
    end

    private def parse_unicode_escape : Char
      digits = String::Builder.new
      4.times do
        digit = advance
        fail_parse("invalid Unicode escape") unless hex_digit?(digit)
        digits << digit
      end

      codepoint = digits.to_s.to_i(16)
      if codepoint >= 0xd800 && codepoint <= 0xdfff
        fail_parse("UTF-16 surrogate escapes are not supported")
      end
      codepoint.chr
    rescue ex : ArgumentError
      fail_parse("invalid Unicode escape")
    end

    private def hex_digit?(char : Char) : Bool
      ('0' <= char && char <= '9') || ('a' <= char && char <= 'f') || ('A' <= char && char <= 'F')
    end

    private def read_symbol : String
      skip_ignored
      start = @position

      while char = current_char
        break if char.whitespace? || char == '(' || char == ')' || char == ',' || char == ';'
        @position += 1
      end

      fail_parse("expected symbol") if start == @position
      @characters[start...@position].join
    end

    private def expect(expected : Char)
      skip_ignored
      actual = advance
      return if actual == expected
      fail_parse("expected '#{expected}', got '#{actual}'")
    end

    private def advance : Char
      char = current_char
      fail_parse("unexpected end of input") unless char
      @position += 1
      char.not_nil!
    end

    private def skip_ignored
      loop do
        while char = current_char
          break unless char.whitespace?
          @position += 1
        end

        break unless current_char == ';'
        @position += 1
        while char = current_char
          @position += 1
          break if char == '\n'
        end
      end
    end

    private def current_char : Char?
      @characters[@position]?
    end

    private def eof? : Bool
      @position >= @characters.size
    end

    private def fail_parse(message : String) : NoReturn
      raise SchemeStorageParseError.new("#{message} at character #{@position}")
    end
  end
end
