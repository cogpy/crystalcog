# Program Tree Representation for Genetic Programming
#
# This module provides an AST (Abstract Syntax Tree) representation for
# evolved programs. It integrates with AtomSpace for knowledge representation
# and provides the foundation for genetic programming operations.
#
# References:
# - Genetic Programming: On the Programming of Computers by Means of Natural Selection (Koza, 1992)
# - MOSES (Meta-Optimizing Semantic Evolutionary Search) integration

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module GeneticProgramming
  VERSION = "0.1.0"

  # Exception classes for Genetic Programming
  class GPException < CogUtil::OpenCogException
  end

  class InvalidProgramException < GPException
  end

  class TypeMismatchException < GPException
  end

  class EvaluationException < GPException
  end

  # Program node types for the AST
  enum NodeType
    # Terminal nodes (leaves)
    Constant      # Numeric or boolean constant
    Variable      # Input variable reference
    EphemeralRandom # Randomly generated constant

    # Function nodes (internal)
    # Boolean operations
    And
    Or
    Not
    Xor
    Implies
    Equivalent

    # Arithmetic operations
    Add
    Subtract
    Multiply
    Divide
    Modulo
    Power
    Negate
    Abs

    # Comparison operations
    LessThan
    GreaterThan
    LessEqual
    GreaterEqual
    Equal
    NotEqual

    # Control flow
    If
    IfThenElse

    # Mathematical functions
    Sin
    Cos
    Tan
    Log
    Exp
    Sqrt
    Max
    Min

    # List/sequence operations
    Head
    Tail
    Cons
    Length
    Map
    Filter
    Reduce

    # Custom user-defined function
    UserDefined
  end

  # Return type of program nodes
  enum ReturnType
    Boolean
    Integer
    Float
    List
    Any
  end

  # Represents a single node in the program tree
  class ProgramNode
    getter node_type : NodeType
    getter return_type : ReturnType
    getter children : Array(ProgramNode)
    property value : Float64 | Bool | Nil
    property variable_index : Int32?
    property function_name : String?

    def initialize(@node_type : NodeType, @return_type : ReturnType = ReturnType::Any)
      @children = [] of ProgramNode
      @value = nil
      @variable_index = nil
      @function_name = nil
    end

    # Factory methods for creating different node types

    # Create a constant node
    def self.constant(value : Float64 | Bool) : ProgramNode
      node = if value.is_a?(Bool)
               new(NodeType::Constant, ReturnType::Boolean)
             else
               new(NodeType::Constant, ReturnType::Float)
             end
      node.value = value
      node
    end

    # Create a variable reference node
    def self.variable(index : Int32) : ProgramNode
      node = new(NodeType::Variable, ReturnType::Any)
      node.variable_index = index
      node
    end

    # Create an ephemeral random constant
    def self.ephemeral_random(min : Float64 = -1.0, max : Float64 = 1.0) : ProgramNode
      node = new(NodeType::EphemeralRandom, ReturnType::Float)
      node.value = Random.rand(max - min) + min
      node
    end

    # Create a function node
    def self.function(node_type : NodeType, *children : ProgramNode) : ProgramNode
      return_type = infer_return_type(node_type)
      node = new(node_type, return_type)
      children.each { |child| node.add_child(child) }
      node
    end

    # Infer return type based on node type
    private def self.infer_return_type(node_type : NodeType) : ReturnType
      case node_type
      when .and?, .or?, .not?, .xor?, .implies?, .equivalent?
        ReturnType::Boolean
      when .less_than?, .greater_than?, .less_equal?, .greater_equal?, .equal?, .not_equal?
        ReturnType::Boolean
      when .add?, .subtract?, .multiply?, .divide?, .modulo?, .power?, .negate?, .abs?
        ReturnType::Float
      when .sin?, .cos?, .tan?, .log?, .exp?, .sqrt?, .max?, .min?
        ReturnType::Float
      when .length?
        ReturnType::Integer
      when .head?, .tail?, .cons?, .map?, .filter?, .reduce?
        ReturnType::List
      else
        ReturnType::Any
      end
    end

    # Add a child node
    def add_child(child : ProgramNode)
      @children << child
    end

    # Remove a child at index
    def remove_child(index : Int32) : ProgramNode?
      return nil if index < 0 || index >= @children.size
      @children.delete_at(index)
    end

    # Replace a child at index
    def replace_child(index : Int32, new_child : ProgramNode)
      if index >= 0 && index < @children.size
        @children[index] = new_child
      end
    end

    # Check if this is a terminal node (leaf)
    def terminal? : Bool
      @node_type.constant? || @node_type.variable? || @node_type.ephemeral_random?
    end

    # Check if this is a function node (internal)
    def function? : Bool
      !terminal?
    end

    # Get the arity (number of expected children) for this node type
    def expected_arity : Int32
      case @node_type
      when .constant?, .variable?, .ephemeral_random?
        0
      when .not?, .negate?, .abs?, .sin?, .cos?, .tan?, .log?, .exp?, .sqrt?, .head?, .tail?, .length?
        1
      when .and?, .or?, .xor?, .implies?, .equivalent?
        2
      when .add?, .subtract?, .multiply?, .divide?, .modulo?, .power?
        2
      when .less_than?, .greater_than?, .less_equal?, .greater_equal?, .equal?, .not_equal?
        2
      when .max?, .min?, .cons?
        2
      when .if?
        2
      when .if_then_else?
        3
      when .map?, .filter?
        2
      when .reduce?
        3
      else
        -1 # Variable arity
      end
    end

    # Calculate the depth of this subtree
    def depth : Int32
      return 0 if terminal?
      1 + (@children.map(&.depth).max? || 0)
    end

    # Calculate the size (number of nodes) of this subtree
    def size : Int32
      1 + @children.sum(&.size)
    end

    # Deep clone this node and its children
    def clone : ProgramNode
      new_node = ProgramNode.new(@node_type, @return_type)
      new_node.value = @value
      new_node.variable_index = @variable_index
      new_node.function_name = @function_name
      @children.each do |child|
        new_node.add_child(child.clone)
      end
      new_node
    end

    # Evaluate this program node with given variable bindings
    def evaluate(variables : Array(Float64 | Bool)) : Float64 | Bool
      case @node_type
      when .constant?, .ephemeral_random?
        @value.not_nil!
      when .variable?
        idx = @variable_index.not_nil!
        if idx < variables.size
          variables[idx]
        else
          raise EvaluationException.new("Variable index #{idx} out of bounds")
        end

      # Boolean operations
      when .and?
        left = @children[0].evaluate(variables)
        right = @children[1].evaluate(variables)
        (left.as(Bool) && right.as(Bool))
      when .or?
        left = @children[0].evaluate(variables)
        right = @children[1].evaluate(variables)
        (left.as(Bool) || right.as(Bool))
      when .not?
        child = @children[0].evaluate(variables)
        !child.as(Bool)
      when .xor?
        left = @children[0].evaluate(variables)
        right = @children[1].evaluate(variables)
        (left.as(Bool) != right.as(Bool))
      when .implies?
        left = @children[0].evaluate(variables)
        right = @children[1].evaluate(variables)
        (!left.as(Bool) || right.as(Bool))
      when .equivalent?
        left = @children[0].evaluate(variables)
        right = @children[1].evaluate(variables)
        (left.as(Bool) == right.as(Bool))

      # Arithmetic operations
      when .add?
        left = @children[0].evaluate(variables).as(Float64)
        right = @children[1].evaluate(variables).as(Float64)
        left + right
      when .subtract?
        left = @children[0].evaluate(variables).as(Float64)
        right = @children[1].evaluate(variables).as(Float64)
        left - right
      when .multiply?
        left = @children[0].evaluate(variables).as(Float64)
        right = @children[1].evaluate(variables).as(Float64)
        left * right
      when .divide?
        left = @children[0].evaluate(variables).as(Float64)
        right = @children[1].evaluate(variables).as(Float64)
        # Protected division to avoid division by zero
        right == 0.0 ? 1.0 : left / right
      when .modulo?
        left = @children[0].evaluate(variables).as(Float64)
        right = @children[1].evaluate(variables).as(Float64)
        right == 0.0 ? 0.0 : left % right
      when .power?
        base = @children[0].evaluate(variables).as(Float64)
        exp = @children[1].evaluate(variables).as(Float64)
        # Protected power to avoid invalid operations
        result = base ** exp
        result.nan? || result.infinite? ? 0.0 : result
      when .negate?
        child = @children[0].evaluate(variables).as(Float64)
        -child
      when .abs?
        child = @children[0].evaluate(variables).as(Float64)
        child.abs

      # Comparison operations
      when .less_than?
        left = @children[0].evaluate(variables).as(Float64)
        right = @children[1].evaluate(variables).as(Float64)
        left < right
      when .greater_than?
        left = @children[0].evaluate(variables).as(Float64)
        right = @children[1].evaluate(variables).as(Float64)
        left > right
      when .less_equal?
        left = @children[0].evaluate(variables).as(Float64)
        right = @children[1].evaluate(variables).as(Float64)
        left <= right
      when .greater_equal?
        left = @children[0].evaluate(variables).as(Float64)
        right = @children[1].evaluate(variables).as(Float64)
        left >= right
      when .equal?
        left = @children[0].evaluate(variables).as(Float64)
        right = @children[1].evaluate(variables).as(Float64)
        (left - right).abs < 1e-10
      when .not_equal?
        left = @children[0].evaluate(variables).as(Float64)
        right = @children[1].evaluate(variables).as(Float64)
        (left - right).abs >= 1e-10

      # Mathematical functions
      when .sin?
        child = @children[0].evaluate(variables).as(Float64)
        Math.sin(child)
      when .cos?
        child = @children[0].evaluate(variables).as(Float64)
        Math.cos(child)
      when .tan?
        child = @children[0].evaluate(variables).as(Float64)
        result = Math.tan(child)
        result.nan? || result.infinite? ? 0.0 : result
      when .log?
        child = @children[0].evaluate(variables).as(Float64)
        # Protected log to avoid invalid operations
        child <= 0.0 ? 0.0 : Math.log(child)
      when .exp?
        child = @children[0].evaluate(variables).as(Float64)
        result = Math.exp(child.clamp(-700.0, 700.0))
        result.infinite? ? Float64::MAX : result
      when .sqrt?
        child = @children[0].evaluate(variables).as(Float64)
        # Protected sqrt to avoid invalid operations
        child < 0.0 ? 0.0 : Math.sqrt(child)
      when .max?
        left = @children[0].evaluate(variables).as(Float64)
        right = @children[1].evaluate(variables).as(Float64)
        Math.max(left, right)
      when .min?
        left = @children[0].evaluate(variables).as(Float64)
        right = @children[1].evaluate(variables).as(Float64)
        Math.min(left, right)

      # Control flow
      when .if?
        condition = @children[0].evaluate(variables).as(Bool)
        if condition
          @children[1].evaluate(variables)
        else
          0.0 # Default for if without else
        end
      when .if_then_else?
        condition = @children[0].evaluate(variables).as(Bool)
        if condition
          @children[1].evaluate(variables)
        else
          @children[2].evaluate(variables)
        end

      else
        raise EvaluationException.new("Unsupported node type: #{@node_type}")
      end
    end

    # Convert to a human-readable string representation
    def to_s : String
      to_s_impl
    end

    def to_s_impl : String
      case @node_type
      when .constant?, .ephemeral_random?
        @value.to_s
      when .variable?
        "$#{@variable_index}"

      # Boolean operations
      when .and?
        "(#{@children[0].to_s_impl} AND #{@children[1].to_s_impl})"
      when .or?
        "(#{@children[0].to_s_impl} OR #{@children[1].to_s_impl})"
      when .not?
        "NOT(#{@children[0].to_s_impl})"
      when .xor?
        "(#{@children[0].to_s_impl} XOR #{@children[1].to_s_impl})"
      when .implies?
        "(#{@children[0].to_s_impl} => #{@children[1].to_s_impl})"
      when .equivalent?
        "(#{@children[0].to_s_impl} <=> #{@children[1].to_s_impl})"

      # Arithmetic operations
      when .add?
        "(#{@children[0].to_s_impl} + #{@children[1].to_s_impl})"
      when .subtract?
        "(#{@children[0].to_s_impl} - #{@children[1].to_s_impl})"
      when .multiply?
        "(#{@children[0].to_s_impl} * #{@children[1].to_s_impl})"
      when .divide?
        "(#{@children[0].to_s_impl} / #{@children[1].to_s_impl})"
      when .modulo?
        "(#{@children[0].to_s_impl} % #{@children[1].to_s_impl})"
      when .power?
        "(#{@children[0].to_s_impl} ^ #{@children[1].to_s_impl})"
      when .negate?
        "-(#{@children[0].to_s_impl})"
      when .abs?
        "abs(#{@children[0].to_s_impl})"

      # Comparison operations
      when .less_than?
        "(#{@children[0].to_s_impl} < #{@children[1].to_s_impl})"
      when .greater_than?
        "(#{@children[0].to_s_impl} > #{@children[1].to_s_impl})"
      when .less_equal?
        "(#{@children[0].to_s_impl} <= #{@children[1].to_s_impl})"
      when .greater_equal?
        "(#{@children[0].to_s_impl} >= #{@children[1].to_s_impl})"
      when .equal?
        "(#{@children[0].to_s_impl} == #{@children[1].to_s_impl})"
      when .not_equal?
        "(#{@children[0].to_s_impl} != #{@children[1].to_s_impl})"

      # Mathematical functions
      when .sin?
        "sin(#{@children[0].to_s_impl})"
      when .cos?
        "cos(#{@children[0].to_s_impl})"
      when .tan?
        "tan(#{@children[0].to_s_impl})"
      when .log?
        "log(#{@children[0].to_s_impl})"
      when .exp?
        "exp(#{@children[0].to_s_impl})"
      when .sqrt?
        "sqrt(#{@children[0].to_s_impl})"
      when .max?
        "max(#{@children[0].to_s_impl}, #{@children[1].to_s_impl})"
      when .min?
        "min(#{@children[0].to_s_impl}, #{@children[1].to_s_impl})"

      # Control flow
      when .if?
        "if(#{@children[0].to_s_impl}, #{@children[1].to_s_impl})"
      when .if_then_else?
        "if(#{@children[0].to_s_impl}, #{@children[1].to_s_impl}, #{@children[2].to_s_impl})"

      else
        "#{@node_type}(#{@children.map(&.to_s_impl).join(", ")})"
      end
    end

    # Convert program tree to AtomSpace representation
    def to_atomspace(atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom
      case @node_type
      when .constant?, .ephemeral_random?
        atomspace.add_node(AtomSpace::AtomType::NUMBER_NODE, @value.to_s)
      when .variable?
        atomspace.add_node(AtomSpace::AtomType::VARIABLE_NODE, "$#{@variable_index}")
      else
        # Create function node
        func_node = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, @node_type.to_s)

        # Convert children
        child_atoms = @children.map { |child| child.to_atomspace(atomspace) }

        # Create list of children
        list_link = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, child_atoms)

        # Create evaluation link
        atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [func_node, list_link])
      end
    end
  end

  # Represents a complete evolved program
  class Program
    getter root : ProgramNode
    property fitness : Float64
    property generation : Int32
    property id : String

    def initialize(@root : ProgramNode)
      @fitness = Float64::MIN
      @generation = 0
      @id = Random::Secure.hex(8)
    end

    # Evaluate the program with given inputs
    def evaluate(inputs : Array(Float64 | Bool)) : Float64 | Bool
      @root.evaluate(inputs)
    end

    # Get program depth
    def depth : Int32
      @root.depth
    end

    # Get program size (number of nodes)
    def size : Int32
      @root.size
    end

    # Deep clone the program
    def clone : Program
      new_program = Program.new(@root.clone)
      new_program.fitness = @fitness
      new_program.generation = @generation
      new_program
    end

    # String representation
    def to_s : String
      @root.to_s
    end

    # Convert to AtomSpace
    def to_atomspace(atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom
      program_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "Program_#{@id}")

      # Store the program tree
      tree_atom = @root.to_atomspace(atomspace)

      # Store fitness
      fitness_node = atomspace.add_node(AtomSpace::AtomType::NUMBER_NODE, @fitness.to_s)
      fitness_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "fitness")
      fitness_list = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [program_node, fitness_node])
      atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [fitness_pred, fitness_list])

      # Link program to tree
      tree_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "has_tree")
      tree_list = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [program_node, tree_atom])
      atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [tree_pred, tree_list])

      program_node
    end

    # Get all nodes in the program tree (flattened)
    def all_nodes : Array(ProgramNode)
      collect_nodes(@root)
    end

    private def collect_nodes(node : ProgramNode) : Array(ProgramNode)
      result = [node]
      node.children.each do |child|
        result.concat(collect_nodes(child))
      end
      result
    end

    # Get a random node from the program tree
    def random_node : ProgramNode
      nodes = all_nodes
      nodes.sample
    end

    # Get a random subtree (node and its children)
    def random_subtree : ProgramNode
      random_node
    end

    # Find parent of a given node (nil if root)
    def find_parent(target : ProgramNode) : ProgramNode?
      find_parent_impl(@root, target)
    end

    private def find_parent_impl(current : ProgramNode, target : ProgramNode) : ProgramNode?
      current.children.each do |child|
        return current if child == target
        result = find_parent_impl(child, target)
        return result if result
      end
      nil
    end

    # Replace a subtree at a given node with a new subtree
    def replace_subtree(old_node : ProgramNode, new_node : ProgramNode)
      if old_node == @root
        @root = new_node
      else
        parent = find_parent(old_node)
        if parent
          index = parent.children.index(old_node)
          if index
            parent.replace_child(index, new_node)
          end
        end
      end
    end
  end

  # Function set for program generation
  class FunctionSet
    getter terminals : Array(NodeType)
    getter functions : Array(NodeType)
    getter num_variables : Int32
    getter constant_range : Tuple(Float64, Float64)

    def initialize(@num_variables : Int32 = 2,
                   @constant_range : Tuple(Float64, Float64) = {-10.0, 10.0})
      @terminals = [NodeType::Variable, NodeType::EphemeralRandom]
      @functions = [] of NodeType
    end

    # Add boolean function set
    def add_boolean_functions
      @functions.concat([
        NodeType::And, NodeType::Or, NodeType::Not, NodeType::Xor,
        NodeType::Implies, NodeType::Equivalent,
      ])
      self
    end

    # Add arithmetic function set
    def add_arithmetic_functions
      @functions.concat([
        NodeType::Add, NodeType::Subtract, NodeType::Multiply, NodeType::Divide,
        NodeType::Negate, NodeType::Abs,
      ])
      self
    end

    # Add comparison function set
    def add_comparison_functions
      @functions.concat([
        NodeType::LessThan, NodeType::GreaterThan, NodeType::Equal,
      ])
      self
    end

    # Add mathematical function set
    def add_math_functions
      @functions.concat([
        NodeType::Sin, NodeType::Cos, NodeType::Log, NodeType::Exp, NodeType::Sqrt,
        NodeType::Max, NodeType::Min, NodeType::Power,
      ])
      self
    end

    # Add control flow functions
    def add_control_flow
      @functions.concat([NodeType::IfThenElse])
      self
    end

    # Create a random terminal node
    def random_terminal : ProgramNode
      case @terminals.sample
      when NodeType::Variable
        ProgramNode.variable(Random.rand(@num_variables))
      when NodeType::Constant, NodeType::EphemeralRandom
        ProgramNode.ephemeral_random(@constant_range[0], @constant_range[1])
      else
        ProgramNode.constant(Random.rand)
      end
    end

    # Create a random function node (without children)
    def random_function : ProgramNode
      if @functions.empty?
        raise GPException.new("No functions defined in function set")
      end
      ProgramNode.new(@functions.sample)
    end

    # Get arity of a function
    def arity(node_type : NodeType) : Int32
      temp_node = ProgramNode.new(node_type)
      temp_node.expected_arity
    end
  end
end
