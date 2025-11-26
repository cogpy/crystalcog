# Crystal implementation of OpenCog Atoms
# Converted from atomspace/opencog/atoms/base/Atom.h and related files
#
# Atoms are the fundamental units of knowledge representation in OpenCog.

require "./truthvalue"
require "../cogutil/cogutil"

module AtomSpace
  # Type system for atoms
  enum AtomType
    # Base types
    ATOM = 1
    NODE = 2
    LINK = 3

    # Node types
    CONCEPT_NODE            = 101
    PREDICATE_NODE          = 102
    SCHEMA_NODE             = 103
    PROCEDURE_NODE          = 104
    GROUNDED_SCHEMA_NODE    = 105
    GROUNDED_PREDICATE_NODE = 106
    VARIABLE_NODE           = 107
    TYPE_NODE               = 108
    NUMBER_NODE             = 109
    STORAGE_NODE            = 110

    # NLP-specific node types
    WORD_NODE               = 111
    WORD_CLASS_NODE         = 112
    DOCUMENT_NODE           = 113
    SENTENCE_NODE           = 114
    PHRASE_NODE             = 115
    PARSE_NODE              = 116
    WORD_INSTANCE_NODE      = 117
    LG_DICT_NODE            = 118
    LG_CONN_NODE            = 119
    LG_CONN_MULTI_NODE      = 120
    LG_CONN_DIR_NODE        = 121
    LG_LINK_NODE            = 122
    LG_LINK_INSTANCE_NODE   = 123

    # Link types
    LIST_LINK        = 201
    SET_LINK         = 202
    MEMBER_LINK      = 203
    INHERITANCE_LINK = 204
    EVALUATION_LINK  = 205
    IMPLICATION_LINK = 206
    EQUIVALENCE_LINK = 207
    AND_LINK         = 208
    OR_LINK          = 209
    NOT_LINK         = 210
    LAMBDA_LINK      = 211
    EXECUTION_LINK   = 212

    # NLP-specific link types
    ORDERED_LINK            = 213
    REFERENCE_LINK          = 214
    SENTENCE_LINK           = 215
    PARSE_LINK              = 216
    WORD_INSTANCE_LINK      = 217
    SEQUENCE_LINK           = 218
    WORD_SEQUENCE_LINK      = 219
    SENTENCE_SEQUENCE_LINK  = 220
    DOCUMENT_SEQUENCE_LINK  = 221
    LG_CONNECTOR            = 222
    LG_SEQ                  = 223
    LG_AND                  = 224
    LG_OR                   = 225
    LG_WORD_CSET            = 226
    LG_DISJUNCT             = 227
    LG_LINK_INSTANCE_LINK   = 228
    LG_PARSE_LINK           = 229
    LG_PARSE_MINIMAL        = 230
    LG_PARSE_DISJUNCTS      = 231

    def node? : Bool
      value >= 100 && value < 200
    end

    def link? : Bool
      value >= 200 && value < 300
    end

    def to_s(io : IO) : Nil
      io << self.to_s.gsub('_', "")
    end
  end

  # Unique identifier for atoms
  alias Handle = UInt64

  # Atom base class - fundamental unit of OpenCog knowledge representation
  abstract class Atom
    property truth_value : TruthValue
    property attention_value : AttentionValue?
    getter type : AtomType
    getter handle : Handle

    # Static handle counter for unique IDs
    @@next_handle : Handle = 1_u64
    @@handle_mutex = Mutex.new

    def initialize(@type : AtomType, @truth_value : TruthValue = TruthValue::DEFAULT_TV)
      @handle = Atom.next_handle
      @attention_value = nil
    end

    # Generate next unique handle
    def self.next_handle : Handle
      @@handle_mutex.synchronize do
        handle = @@next_handle
        @@next_handle += 1
        handle
      end
    end

    # Abstract methods to be implemented by subclasses
    abstract def name : String
    abstract def outgoing : Array(Atom)
    abstract def arity : Int32
    abstract def clone : Atom
    abstract def to_s(io : IO) : Nil

    # Check if this is a node
    def node? : Bool
      type.node?
    end

    # Check if this is a link
    def link? : Bool
      type.link?
    end

    # Get all atoms in the incoming set (atoms that reference this one)
    def incoming : Array(Atom)
      # This would be maintained by the AtomSpace
      # For now, return empty array
      [] of Atom
    end

    # Check equality based on type and content
    def ==(other : Atom) : Bool
      return false unless type == other.type
      return false unless truth_value == other.truth_value
      content_equals?(other)
    end

    # Content equality check (implemented by subclasses)
    abstract def content_equals?(other : Atom) : Bool

    # Hash function for use in collections
    # Check if atom satisfies a pattern
    def satisfies?(pattern : Atom) : Bool
      # Basic type checking - more sophisticated pattern matching
      # would be implemented in the pattern matcher
      pattern.type == type || pattern.type == AtomType::ATOM
    end

    # Get string representation for logging/debugging
    def inspect(io : IO) : Nil
      io << "#{type}:#{handle} "
      to_s(io)
      io << " #{truth_value}"
    end

    # Atom type checking predicates
    def concept_node?
      type == AtomType::CONCEPT_NODE
    end

    def predicate_node?
      type == AtomType::PREDICATE_NODE
    end

    def variable_node?
      type == AtomType::VARIABLE_NODE
    end

    def inheritance_link?
      type == AtomType::INHERITANCE_LINK
    end

    def evaluation_link?
      type == AtomType::EVALUATION_LINK
    end

    def list_link?
      type == AtomType::LIST_LINK
    end
  end

  # Node class - atoms with names but no outgoing connections
  class Node < Atom
    getter name : String

    def initialize(type : AtomType, @name : String, truth_value : TruthValue = TruthValue::DEFAULT_TV)
      unless type.node?
        raise ArgumentError.new("Node type expected, got #{type}")
      end
      super(type, truth_value)
    end

    def outgoing : Array(Atom)
      [] of Atom
    end

    def arity : Int32
      0
    end

    def clone : Atom
      Node.new(type, name, truth_value.clone)
    end

    def to_s(io : IO) : Nil
      io << "(#{type} \"#{name}\")"
    end

    def content_equals?(other : Atom) : Bool
      other.is_a?(Node) && other.name == name
    end
  end

  # Link class - atoms that connect other atoms
  class Link < Atom
    getter outgoing : Array(Atom)

    def initialize(type : AtomType, @outgoing : Array(Atom), truth_value : TruthValue = TruthValue::DEFAULT_TV)
      unless type.link?
        raise ArgumentError.new("Link type expected, got #{type}")
      end
      super(type, truth_value)
    end

    def name : String
      ""
    end

    def arity : Int32
      outgoing.size
    end

    def clone : Atom
      cloned_outgoing = outgoing.map(&.clone)
      Link.new(type, cloned_outgoing, truth_value.clone)
    end

    def to_s(io : IO) : Nil
      io << "(#{type}"
      outgoing.each do |atom|
        io << " "
        atom.to_s(io)
      end
      io << ")"
    end

    def content_equals?(other : Atom) : Bool
      return false unless other.is_a?(Link)
      return false unless outgoing.size == other.outgoing.size

      outgoing.zip(other.outgoing) do |a, b|
        return false unless a == b
      end
      true
    end

    # Get atom at specific position
    def [](index : Int32) : Atom
      outgoing[index]
    end

    # Get first atom (common in binary links)
    def first : Atom
      outgoing[0]
    end

    # Get last atom
    def last : Atom
      outgoing[-1]
    end
  end

  # Specific node types for convenience
  class ConceptNode < Node
    def initialize(name : String, truth_value : TruthValue = TruthValue::DEFAULT_TV)
      super(AtomType::CONCEPT_NODE, name, truth_value)
    end
  end

  class PredicateNode < Node
    def initialize(name : String, truth_value : TruthValue = TruthValue::DEFAULT_TV)
      super(AtomType::PREDICATE_NODE, name, truth_value)
    end
  end

  class VariableNode < Node
    def initialize(name : String, truth_value : TruthValue = TruthValue::DEFAULT_TV)
      super(AtomType::VARIABLE_NODE, name, truth_value)
    end
  end

  class NumberNode < Node
    getter value : Float64

    def initialize(@value : Float64, truth_value : TruthValue = TruthValue::DEFAULT_TV)
      super(AtomType::NUMBER_NODE, value.to_s, truth_value)
    end

    def initialize(value : Int32, truth_value : TruthValue = TruthValue::DEFAULT_TV)
      @value = value.to_f64
      super(AtomType::NUMBER_NODE, value.to_s, truth_value)
    end
  end

  # Specific link types
  class InheritanceLink < Link
    def initialize(child : Atom, parent : Atom, truth_value : TruthValue = TruthValue::DEFAULT_TV)
      super(AtomType::INHERITANCE_LINK, [child, parent].map(&.as(Atom)), truth_value)
    end

    def child : Atom
      outgoing[0]
    end

    def parent : Atom
      outgoing[1]
    end
  end

  class EvaluationLink < Link
    def initialize(predicate : Atom, arguments : Atom, truth_value : TruthValue = TruthValue::DEFAULT_TV)
      super(AtomType::EVALUATION_LINK, [predicate, arguments].map(&.as(Atom)), truth_value)
    end

    def predicate : Atom
      outgoing[0]
    end

    def arguments : Atom
      outgoing[1]
    end
  end

  class ListLink < Link
    def initialize(atoms : Array(Atom), truth_value : TruthValue = TruthValue::DEFAULT_TV)
      super(AtomType::LIST_LINK, atoms, truth_value)
    end
  end

  class AndLink < Link
    def initialize(atoms : Array(Atom), truth_value : TruthValue = TruthValue::DEFAULT_TV)
      super(AtomType::AND_LINK, atoms, truth_value)
    end
  end

  class OrLink < Link
    def initialize(atoms : Array(Atom), truth_value : TruthValue = TruthValue::DEFAULT_TV)
      super(AtomType::OR_LINK, atoms, truth_value)
    end
  end

  class NotLink < Link
    def initialize(atom : Atom, truth_value : TruthValue = TruthValue::DEFAULT_TV)
      super(AtomType::NOT_LINK, [atom].map(&.as(Atom)), truth_value)
    end

    def operand : Atom
      outgoing[0]
    end
  end

  class ImplicationLink < Link
    def initialize(antecedent : Atom, consequent : Atom, truth_value : TruthValue = TruthValue::DEFAULT_TV)
      super(AtomType::IMPLICATION_LINK, [antecedent, consequent].map(&.as(Atom)), truth_value)
    end

    def antecedent : Atom
      outgoing[0]
    end

    def consequent : Atom
      outgoing[1]
    end
  end

  # Attention value for atoms (used by attention allocation system)
  class AttentionValue
    getter sti : Int16 # Short-term importance
    getter lti : Int16 # Long-term importance
    getter vlti : Bool # Very long-term importance

    def initialize(@sti : Int16 = 0, @lti : Int16 = 0, @vlti : Bool = false)
    end

    def to_s(io : IO) : Nil
      io << "[#{sti}, #{lti}#{vlti ? ", VLTI" : ""}]"
    end

    def ==(other : AttentionValue) : Bool
      sti == other.sti && lti == other.lti && vlti == other.vlti
    end

    def hash(hasher)
      hasher = sti.hash(hasher)
      hasher = lti.hash(hasher)
      hasher = vlti.hash(hasher)
      hasher
    end
  end
end
