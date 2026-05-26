require "spec"
require "../../src/genetic_programming/genetic_programming_main"

describe GeneticProgramming do
  describe "VERSION" do
    it "has a version number" do
      GeneticProgramming::VERSION.should_not be_nil
    end
  end

  describe GeneticProgramming::ProgramNode do
    describe "factory methods" do
      it "creates constant nodes" do
        node = GeneticProgramming::ProgramNode.constant(42.0)
        node.node_type.should eq(GeneticProgramming::NodeType::Constant)
        node.return_type.should eq(GeneticProgramming::ReturnType::Float)
        node.value.should eq(42.0)
        node.terminal?.should be_true
      end

      it "creates boolean constant nodes" do
        node = GeneticProgramming::ProgramNode.constant(true)
        node.node_type.should eq(GeneticProgramming::NodeType::Constant)
        node.return_type.should eq(GeneticProgramming::ReturnType::Boolean)
        node.value.should eq(true)
      end

      it "creates variable nodes" do
        node = GeneticProgramming::ProgramNode.variable(2)
        node.node_type.should eq(GeneticProgramming::NodeType::Variable)
        node.variable_index.should eq(2)
        node.terminal?.should be_true
      end

      it "creates ephemeral random nodes" do
        node = GeneticProgramming::ProgramNode.ephemeral_random(-10.0, 10.0)
        node.node_type.should eq(GeneticProgramming::NodeType::EphemeralRandom)
        value = node.value.as(Float64)
        (value >= -10.0 && value <= 10.0).should be_true
      end

      it "creates function nodes with children" do
        left = GeneticProgramming::ProgramNode.constant(5.0)
        right = GeneticProgramming::ProgramNode.constant(3.0)
        node = GeneticProgramming::ProgramNode.function(
          GeneticProgramming::NodeType::Add, left, right
        )

        node.node_type.should eq(GeneticProgramming::NodeType::Add)
        node.return_type.should eq(GeneticProgramming::ReturnType::Float)
        node.children.size.should eq(2)
        node.function?.should be_true
      end
    end

    describe "tree properties" do
      it "calculates depth correctly" do
        leaf = GeneticProgramming::ProgramNode.constant(1.0)
        leaf.depth.should eq(0)

        add_node = GeneticProgramming::ProgramNode.function(
          GeneticProgramming::NodeType::Add,
          GeneticProgramming::ProgramNode.constant(1.0),
          GeneticProgramming::ProgramNode.constant(2.0)
        )
        add_node.depth.should eq(1)
      end

      it "calculates size correctly" do
        leaf = GeneticProgramming::ProgramNode.constant(1.0)
        leaf.size.should eq(1)

        add_node = GeneticProgramming::ProgramNode.function(
          GeneticProgramming::NodeType::Add,
          GeneticProgramming::ProgramNode.constant(1.0),
          GeneticProgramming::ProgramNode.constant(2.0)
        )
        add_node.size.should eq(3)
      end

      it "reports expected arity" do
        not_node = GeneticProgramming::ProgramNode.new(GeneticProgramming::NodeType::Not)
        not_node.expected_arity.should eq(1)

        add_node = GeneticProgramming::ProgramNode.new(GeneticProgramming::NodeType::Add)
        add_node.expected_arity.should eq(2)

        ite_node = GeneticProgramming::ProgramNode.new(GeneticProgramming::NodeType::IfThenElse)
        ite_node.expected_arity.should eq(3)
      end
    end

    describe "evaluation" do
      it "evaluates constants" do
        node = GeneticProgramming::ProgramNode.constant(42.0)
        result = node.evaluate([] of Float64 | Bool)
        result.should eq(42.0)
      end

      it "evaluates variables" do
        node = GeneticProgramming::ProgramNode.variable(1)
        result = node.evaluate([10.0, 20.0, 30.0] of Float64 | Bool)
        result.should eq(20.0)
      end

      it "evaluates arithmetic operations" do
        left = GeneticProgramming::ProgramNode.constant(10.0)
        right = GeneticProgramming::ProgramNode.constant(3.0)

        add = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Add, left.clone, right.clone)
        add.evaluate([] of Float64 | Bool).should eq(13.0)

        sub = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Subtract, left.clone, right.clone)
        sub.evaluate([] of Float64 | Bool).should eq(7.0)

        mul = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Multiply, left.clone, right.clone)
        mul.evaluate([] of Float64 | Bool).should eq(30.0)

        div = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Divide, left.clone, right.clone)
        result = div.evaluate([] of Float64 | Bool).as(Float64)
        result.should be_close(3.333, 0.01)
      end

      it "handles protected division by zero" do
        left = GeneticProgramming::ProgramNode.constant(10.0)
        right = GeneticProgramming::ProgramNode.constant(0.0)
        div = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Divide, left, right)

        result = div.evaluate([] of Float64 | Bool)
        result.should eq(1.0) # Protected division returns 1.0
      end

      it "evaluates boolean operations" do
        t = GeneticProgramming::ProgramNode.constant(true)
        f = GeneticProgramming::ProgramNode.constant(false)

        and_node = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::And, t.clone, f.clone)
        and_node.evaluate([] of Float64 | Bool).should eq(false)

        or_node = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Or, t.clone, f.clone)
        or_node.evaluate([] of Float64 | Bool).should eq(true)

        not_node = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Not, t.clone)
        not_node.evaluate([] of Float64 | Bool).should eq(false)
      end

      it "evaluates comparison operations" do
        ten = GeneticProgramming::ProgramNode.constant(10.0)
        five = GeneticProgramming::ProgramNode.constant(5.0)

        lt = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::LessThan, ten.clone, five.clone)
        lt.evaluate([] of Float64 | Bool).should eq(false)

        gt = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::GreaterThan, ten.clone, five.clone)
        gt.evaluate([] of Float64 | Bool).should eq(true)
      end

      it "evaluates mathematical functions" do
        zero = GeneticProgramming::ProgramNode.constant(0.0)
        one = GeneticProgramming::ProgramNode.constant(1.0)
        four = GeneticProgramming::ProgramNode.constant(4.0)

        sin = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Sin, zero.clone)
        sin.evaluate([] of Float64 | Bool).as(Float64).should be_close(0.0, 0.0001)

        cos = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Cos, zero.clone)
        cos.evaluate([] of Float64 | Bool).as(Float64).should be_close(1.0, 0.0001)

        sqrt = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Sqrt, four.clone)
        sqrt.evaluate([] of Float64 | Bool).as(Float64).should be_close(2.0, 0.0001)

        exp = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Exp, one.clone)
        exp.evaluate([] of Float64 | Bool).as(Float64).should be_close(Math::E, 0.0001)
      end
    end

    describe "string representation" do
      it "converts to readable string" do
        left = GeneticProgramming::ProgramNode.variable(0)
        right = GeneticProgramming::ProgramNode.constant(5.0)
        add = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Add, left, right)

        add.to_s.should eq("($0 + 5.0)")
      end
    end

    describe "cloning" do
      it "creates deep copies" do
        left = GeneticProgramming::ProgramNode.constant(5.0)
        right = GeneticProgramming::ProgramNode.constant(3.0)
        add = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Add, left, right)

        cloned = add.clone
        cloned.node_type.should eq(add.node_type)
        cloned.children.size.should eq(add.children.size)
        cloned.children[0].should_not be(add.children[0]) # Different object
        cloned.children[0].value.should eq(add.children[0].value)
      end
    end
  end

  describe GeneticProgramming::Program do
    it "creates programs from root nodes" do
      root = GeneticProgramming::ProgramNode.constant(42.0)
      program = GeneticProgramming::Program.new(root)

      program.root.should eq(root)
      program.fitness.should eq(Float64::MIN)
      program.generation.should eq(0)
      program.id.size.should eq(16) # hex string
    end

    it "evaluates programs" do
      left = GeneticProgramming::ProgramNode.variable(0)
      right = GeneticProgramming::ProgramNode.variable(1)
      root = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Add, left, right)

      program = GeneticProgramming::Program.new(root)
      result = program.evaluate([10.0, 20.0] of Float64 | Bool)
      result.should eq(30.0)
    end

    it "calculates depth and size" do
      left = GeneticProgramming::ProgramNode.constant(5.0)
      right = GeneticProgramming::ProgramNode.constant(3.0)
      root = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Add, left, right)

      program = GeneticProgramming::Program.new(root)
      program.depth.should eq(1)
      program.size.should eq(3)
    end

    it "clones programs" do
      root = GeneticProgramming::ProgramNode.constant(42.0)
      program = GeneticProgramming::Program.new(root)
      program.fitness = 0.95

      cloned = program.clone
      cloned.root.should_not be(program.root)
      cloned.fitness.should eq(program.fitness)
      cloned.id.should_not eq(program.id)
    end

    it "collects all nodes" do
      left = GeneticProgramming::ProgramNode.constant(5.0)
      right = GeneticProgramming::ProgramNode.constant(3.0)
      root = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Add, left, right)

      program = GeneticProgramming::Program.new(root)
      nodes = program.all_nodes
      nodes.size.should eq(3)
    end
  end

  describe GeneticProgramming::FunctionSet do
    it "creates function sets with variables" do
      fs = GeneticProgramming::FunctionSet.new(3)
      fs.num_variables.should eq(3)
      fs.terminals.size.should eq(2) # Variable and EphemeralRandom
    end

    it "adds boolean functions" do
      fs = GeneticProgramming::FunctionSet.new(2).add_boolean_functions
      fs.functions.should contain(GeneticProgramming::NodeType::And)
      fs.functions.should contain(GeneticProgramming::NodeType::Or)
      fs.functions.should contain(GeneticProgramming::NodeType::Not)
    end

    it "adds arithmetic functions" do
      fs = GeneticProgramming::FunctionSet.new(2).add_arithmetic_functions
      fs.functions.should contain(GeneticProgramming::NodeType::Add)
      fs.functions.should contain(GeneticProgramming::NodeType::Subtract)
      fs.functions.should contain(GeneticProgramming::NodeType::Multiply)
    end

    it "generates random terminals" do
      fs = GeneticProgramming::FunctionSet.new(3)
      terminal = fs.random_terminal
      terminal.terminal?.should be_true
    end

    it "generates random functions" do
      fs = GeneticProgramming::FunctionSet.new(2).add_arithmetic_functions
      func = fs.random_function
      func.function?.should be_true
    end
  end

  describe GeneticProgramming::TreeGenerator do
    it "generates random trees with grow method" do
      fs = GeneticProgramming::FunctionSet.new(2).add_arithmetic_functions
      gen = GeneticProgramming::TreeGenerator.new(fs, 3)

      tree = gen.grow
      tree.should_not be_nil
      tree.depth.should be <= 3
    end

    it "generates full trees" do
      fs = GeneticProgramming::FunctionSet.new(2).add_arithmetic_functions
      gen = GeneticProgramming::TreeGenerator.new(fs, 2)

      tree = gen.full
      tree.should_not be_nil
    end

    it "generates complete programs" do
      fs = GeneticProgramming::FunctionSet.new(2).add_arithmetic_functions
      gen = GeneticProgramming::TreeGenerator.new(fs, 3)

      program = gen.generate_program
      program.should_not be_nil
      program.depth.should be <= 3
    end

    it "generates populations" do
      fs = GeneticProgramming::FunctionSet.new(2).add_arithmetic_functions
      gen = GeneticProgramming::TreeGenerator.new(fs, 3)

      population = gen.generate_population(10)
      population.size.should eq(10)
    end
  end

  describe GeneticProgramming::Crossover do
    it "performs subtree crossover" do
      fs = GeneticProgramming::FunctionSet.new(2).add_arithmetic_functions
      gen = GeneticProgramming::TreeGenerator.new(fs, 4)

      parent1 = gen.generate_program
      parent2 = gen.generate_program

      crossover = GeneticProgramming::Crossover.new(10, 100)
      child1, child2 = crossover.subtree_crossover(parent1, parent2)

      child1.should_not be_nil
      child2.should_not be_nil
      child1.depth.should be <= 10
      child2.depth.should be <= 10
    end
  end

  describe GeneticProgramming::Mutation do
    it "performs subtree mutation" do
      fs = GeneticProgramming::FunctionSet.new(2).add_arithmetic_functions
      gen = GeneticProgramming::TreeGenerator.new(fs, 3)
      program = gen.generate_program

      mutation = GeneticProgramming::Mutation.new(fs, 6, 100)
      mutant = mutation.subtree_mutation(program)

      mutant.should_not be_nil
    end

    it "performs point mutation" do
      fs = GeneticProgramming::FunctionSet.new(2).add_arithmetic_functions
      gen = GeneticProgramming::TreeGenerator.new(fs, 3)
      program = gen.generate_program

      mutation = GeneticProgramming::Mutation.new(fs, 6, 100)
      mutant = mutation.point_mutation(program)

      mutant.should_not be_nil
    end

    it "performs hoist mutation" do
      fs = GeneticProgramming::FunctionSet.new(2).add_arithmetic_functions
      gen = GeneticProgramming::TreeGenerator.new(fs, 4)
      program = gen.generate_program

      mutation = GeneticProgramming::Mutation.new(fs, 6, 100)
      mutant = mutation.hoist_mutation(program)

      mutant.should_not be_nil
      mutant.size.should be <= program.size
    end

    it "performs shrink mutation" do
      fs = GeneticProgramming::FunctionSet.new(2).add_arithmetic_functions
      gen = GeneticProgramming::TreeGenerator.new(fs, 4)
      program = gen.generate_program

      mutation = GeneticProgramming::Mutation.new(fs, 6, 100)
      mutant = mutation.shrink_mutation(program)

      mutant.should_not be_nil
    end
  end

  describe GeneticProgramming::Selection do
    it "performs tournament selection" do
      fs = GeneticProgramming::FunctionSet.new(2).add_arithmetic_functions
      gen = GeneticProgramming::TreeGenerator.new(fs, 3)
      population = gen.generate_population(20)

      # Assign random fitness
      population.each { |p| p.fitness = Random.rand }

      selection = GeneticProgramming::Selection.new(5)
      selected = selection.tournament_select(population)

      selected.should_not be_nil
      population.should contain(selected)
    end

    it "selects elite individuals" do
      fs = GeneticProgramming::FunctionSet.new(2).add_arithmetic_functions
      gen = GeneticProgramming::TreeGenerator.new(fs, 3)
      population = gen.generate_population(20)

      # Assign incremental fitness
      population.each_with_index { |p, i| p.fitness = i.to_f }

      selection = GeneticProgramming::Selection.new(5)
      elite = selection.select_elite(population, 3)

      elite.size.should eq(3)
      elite.map(&.fitness).min.should be >= (population.size - 3).to_f
    end
  end

  describe GeneticProgramming::SupervisedFitness do
    it "evaluates programs against examples" do
      inputs = [
        [1.0, 2.0] of Float64 | Bool,
        [3.0, 4.0] of Float64 | Bool,
        [5.0, 6.0] of Float64 | Bool,
      ]
      outputs = [3.0, 7.0, 11.0] of Float64 | Bool

      fitness = GeneticProgramming::SupervisedFitness.new(inputs, outputs)

      # Create a program that computes x + y
      left = GeneticProgramming::ProgramNode.variable(0)
      right = GeneticProgramming::ProgramNode.variable(1)
      root = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Add, left, right)
      program = GeneticProgramming::Program.new(root)

      score = fitness.evaluate(program)
      score.should be_close(0.0, 0.001) # Perfect fit = 0 error
    end
  end

  describe GeneticProgramming::BooleanFitness do
    it "evaluates boolean programs" do
      # Simple AND function
      inputs = [
        [true, true],
        [true, false],
        [false, true],
        [false, false],
      ]
      outputs = [true, false, false, false]

      fitness = GeneticProgramming::BooleanFitness.new(inputs, outputs)

      # Create AND program
      left = GeneticProgramming::ProgramNode.variable(0)
      right = GeneticProgramming::ProgramNode.variable(1)
      root = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::And, left, right)
      program = GeneticProgramming::Program.new(root)

      score = fitness.evaluate(program)
      score.should eq(1.0) # Perfect accuracy
    end

    it "computes confusion matrix" do
      inputs = [
        [true, true],
        [true, false],
        [false, true],
        [false, false],
      ]
      outputs = [true, false, false, false]

      fitness = GeneticProgramming::BooleanFitness.new(inputs, outputs)

      # Create AND program
      left = GeneticProgramming::ProgramNode.variable(0)
      right = GeneticProgramming::ProgramNode.variable(1)
      root = GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::And, left, right)
      program = GeneticProgramming::Program.new(root)

      cm = fitness.confusion_matrix(program)
      cm["tp"].should eq(1)
      cm["tn"].should eq(3)
      cm["fp"].should eq(0)
      cm["fn"].should eq(0)
    end
  end

  describe GeneticProgramming::GPConfig do
    it "has sensible defaults" do
      config = GeneticProgramming::GPConfig.new
      config.population_size.should eq(100)
      config.max_generations.should eq(50)
      config.max_depth.should eq(6)
      config.crossover_rate.should eq(0.8)
      config.mutation_rate.should eq(0.1)
    end

    it "allows customization" do
      config = GeneticProgramming::GPConfig.new(
        population_size: 200,
        max_generations: 100,
        crossover_rate: 0.9
      )
      config.population_size.should eq(200)
      config.max_generations.should eq(100)
      config.crossover_rate.should eq(0.9)
    end
  end

  describe GeneticProgramming::ProgramSynthesizer do
    it "synthesizes simple boolean functions" do
      # Simple AND gate
      spec = GeneticProgramming::SynthesisSpec.new(
        input_types: [GeneticProgramming::ReturnType::Boolean, GeneticProgramming::ReturnType::Boolean],
        output_type: GeneticProgramming::ReturnType::Boolean,
        examples: [
          {[true, true] of Float64 | Bool, true.as(Float64 | Bool)},
          {[true, false] of Float64 | Bool, false.as(Float64 | Bool)},
          {[false, true] of Float64 | Bool, false.as(Float64 | Bool)},
          {[false, false] of Float64 | Bool, false.as(Float64 | Bool)},
        ]
      )

      config = GeneticProgramming::GPConfig.new(
        population_size: 50,
        max_generations: 20,
        max_depth: 4
      )

      synth = GeneticProgramming::ProgramSynthesizer.new(config)
      synth.setup_boolean(2)
      result = synth.synthesize(spec)

      result.generations.should be > 0
      result.evaluations.should be > 0
    end

    it "synthesizes simple regression functions" do
      # f(x) = 2*x
      x_data = [[-2.0], [-1.0], [0.0], [1.0], [2.0]]
      y_data = [-4.0, -2.0, 0.0, 2.0, 4.0]

      config = GeneticProgramming::GPConfig.new(
        population_size: 50,
        max_generations: 30,
        max_depth: 4
      )

      synth = GeneticProgramming::SymbolicRegressionSynthesizer.new(1, config)
      result = synth.synthesize_from_data(x_data, y_data)

      result.generations.should be > 0
      result.evaluations.should be > 0
    end
  end

  describe "Module-level functions" do
    it "provides quick configuration" do
      config = GeneticProgramming.quick_config
      config.population_size.should eq(50)
      config.max_generations.should eq(20)
    end

    it "provides accurate configuration" do
      config = GeneticProgramming.accurate_config
      config.population_size.should eq(200)
      config.max_generations.should eq(100)
    end

    it "provides simple configuration" do
      config = GeneticProgramming.simple_config
      config.max_depth.should eq(4)
      config.parsimony_coefficient.should eq(0.01)
    end

    it "provides boolean function set" do
      fs = GeneticProgramming.boolean_function_set(2)
      fs.functions.should contain(GeneticProgramming::NodeType::And)
    end

    it "provides regression function set" do
      fs = GeneticProgramming.regression_function_set(2)
      fs.functions.should contain(GeneticProgramming::NodeType::Add)
    end
  end

  describe GeneticProgramming::Benchmarks do
    it "generates even parity benchmark" do
      inputs, outputs = GeneticProgramming::Benchmarks.even_parity(3)
      inputs.size.should eq(8)
      outputs.size.should eq(8)
    end

    it "generates multiplexer benchmark" do
      inputs, outputs = GeneticProgramming::Benchmarks.multiplexer_6
      inputs.size.should eq(64)
      outputs.size.should eq(64)
    end

    it "generates polynomial regression benchmark" do
      inputs, outputs = GeneticProgramming::Benchmarks.polynomial_regression(20)
      inputs.size.should eq(20)
      outputs.size.should eq(20)
      inputs.first.size.should eq(1)
    end

    it "generates sine regression benchmark" do
      inputs, outputs = GeneticProgramming::Benchmarks.sine_regression(50)
      inputs.size.should eq(50)
      outputs.size.should eq(50)
    end

    it "generates two-variable regression benchmark" do
      inputs, outputs = GeneticProgramming::Benchmarks.two_var_regression(30)
      inputs.size.should eq(30)
      outputs.size.should eq(30)
      inputs.first.size.should eq(2)
    end
  end

  describe GeneticProgramming::Diversity do
    it "measures structural diversity" do
      fs = GeneticProgramming::FunctionSet.new(2).add_arithmetic_functions
      gen = GeneticProgramming::TreeGenerator.new(fs, 3)
      population = gen.generate_population(20)

      diversity = GeneticProgramming::Diversity.structural_diversity(population)
      diversity.should be >= 0.0
      diversity.should be <= 1.0
    end
  end

  describe GeneticProgramming::BloatControl do
    it "applies parsimony pressure" do
      raw_fitness = 0.9
      size = 10
      coefficient = 0.01

      root = GeneticProgramming::ProgramNode.constant(1.0)
      program = GeneticProgramming::Program.new(root)
      # Manually create a larger program for testing
      10.times do
        left = program.root.clone
        right = GeneticProgramming::ProgramNode.constant(1.0)
        program = GeneticProgramming::Program.new(
          GeneticProgramming::ProgramNode.function(GeneticProgramming::NodeType::Add, left, right)
        )
      end

      adjusted = GeneticProgramming::BloatControl.apply_parsimony(program, raw_fitness, coefficient)
      adjusted.should be < raw_fitness
    end

    it "checks program limits" do
      root = GeneticProgramming::ProgramNode.constant(1.0)
      program = GeneticProgramming::Program.new(root)

      GeneticProgramming::BloatControl.exceeds_limits?(program, 5, 50).should be_false

      # Create a deep tree
      current = GeneticProgramming::ProgramNode.constant(1.0)
      10.times do
        current = GeneticProgramming::ProgramNode.function(
          GeneticProgramming::NodeType::Negate, current
        )
      end
      deep_program = GeneticProgramming::Program.new(current)

      GeneticProgramming::BloatControl.exceeds_limits?(deep_program, 5, 50).should be_true
    end
  end

  describe GeneticProgramming::FitnessStats do
    it "computes population statistics" do
      fs = GeneticProgramming::FunctionSet.new(2).add_arithmetic_functions
      gen = GeneticProgramming::TreeGenerator.new(fs, 3)
      population = gen.generate_population(10)

      # Assign fitness values
      population.each_with_index { |p, i| p.fitness = i.to_f / 10.0 }

      stats = GeneticProgramming::FitnessStats.new(population, 1)
      stats.best_fitness.should eq(0.9)
      stats.worst_fitness.should eq(0.0)
      stats.average_fitness.should be_close(0.45, 0.01)
      stats.generation.should eq(1)
    end
  end
end
