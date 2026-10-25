# MOSES main entry point
# Command-line interface for running MOSES evolutionary search

require "./moses"
require "./moses_framework"

module Moses
  # Command-line interface for MOSES
  def self.main(args = ARGV)
    puts "MOSES #{VERSION} - Meta-Optimizing Semantic Evolutionary Search"
    puts "Crystal implementation of evolutionary program learning"

    case args.first?
    when "demo"
      run_demo
    when "boolean"
      run_boolean_demo
    when "regression"
      run_regression_demo
    when "test"
      run_test_suite
    else
      puts "Usage: moses [demo|boolean|regression|test]"
      puts "  demo       - Run a comprehensive MOSES demonstration"
      puts "  boolean    - Run boolean classification example"
      puts "  regression - Run regression example"
      puts "  test       - Run MOSES test suite"
    end
  end

  # Run a comprehensive MOSES demonstration
  def self.run_demo
    puts "\n=== MOSES Demonstration ==="
    puts "Running boolean classification and regression examples\n"

    # Show framework info
    puts "Framework: #{MOSES.info["description"]}"
    puts "Version: #{MOSES.info["version"]}"
    puts ""

    run_boolean_demo
    puts "\n" + "="*50 + "\n"
    run_regression_demo

    puts "\n=== MOSES Demonstration Complete ==="
  end

  # Run boolean classification example
  def self.run_boolean_demo
    puts "=== Boolean Classification Example ==="

    # Create simple XOR training data
    training_data = [
      [0.0, 0.0],
      [0.0, 1.0],
      [1.0, 0.0],
      [1.0, 1.0],
    ]

    target_data = [0.0, 1.0, 1.0, 0.0] # XOR outputs

    puts "Training data: XOR function"
    training_data.each_with_index do |input, i|
      puts "  #{input} -> #{target_data[i]}"
    end

    puts "\nRunning MOSES evolutionary search..."

    # Use new framework
    params = MOSES.boolean_params(training_data, target_data, max_evals: 100)
    result = MOSES.optimize(params)

    puts "\nResults:"
    puts "  Evaluations: #{result.evaluations}"
    puts "  Generations: #{result.generations}"
    puts "  Best score: #{result.best_score.try(&.penalized_score)}"

    puts "\nTop candidates:"
    result.candidates[0...5].each_with_index do |candidate, i|
      puts "  #{i + 1}. #{candidate.program} (score: #{candidate.score.try(&.penalized_score)})"
    end

    # Test best candidate
    if best = result.best_candidate
      puts "\nBest candidate: #{best.program}"
      correct = 0
      training_data.each_with_index do |input, i|
        output = begin
          Moses::Candidate.new(best.program).execute(input, Moses::ProblemType::BooleanClassification)
        rescue ex
          "error: #{ex.message}"
        end
        expected = target_data[i] > 0.5
        correct += 1 if output == expected
        puts "  #{input} -> #{output} (expected #{expected})"
      end
      puts "  Accuracy: #{correct}/#{training_data.size}"
    end
  end

  # Run regression example
  def self.run_regression_demo
    puts "=== Regression Example ==="

    # Create simple linear function training data: y = 2*x + 1
    training_data = (0..10).map { |x| [x.to_f] }.to_a
    target_data = training_data.map { |input| 2.0 * input[0] + 1.0 }

    puts "Training data: y = 2*x + 1"
    training_data[0...5].each_with_index do |input, i|
      puts "  x=#{input[0]} -> y=#{target_data[i]}"
    end
    puts "  ..."

    puts "\nRunning MOSES evolutionary search..."

    # Use new framework
    params = MOSES.regression_params(training_data, target_data, max_evals: 50)
    result = MOSES.optimize(params)

    puts "\nResults:"
    puts "  Evaluations: #{result.evaluations}"
    puts "  Generations: #{result.generations}"
    puts "  Best score: #{result.best_score.try(&.penalized_score)}"

    puts "\nTop candidates:"
    result.candidates[0...5].each_with_index do |candidate, i|
      puts "  #{i + 1}. #{candidate.program} (score: #{candidate.score.try(&.penalized_score)})"
    end
  end

  # Run MOSES test suite
  def self.run_test_suite
    puts "=== MOSES Test Suite ==="

    test_count = 0
    passed_count = 0

    # Test 1: Framework initialization
    print "Testing framework initialization... "
    begin
      MOSES.initialize
      puts "PASSED"
      passed_count += 1
    rescue ex
      puts "FAILED - #{ex}"
    end
    test_count += 1

    # Test 2: Framework info
    print "Testing framework info... "
    begin
      info = MOSES.info
      if info.is_a?(Hash) && info["version"]?
        puts "PASSED"
        passed_count += 1
      else
        puts "FAILED - invalid info structure"
      end
    rescue ex
      puts "FAILED - #{ex}"
    end
    test_count += 1

    # Test 3: Basic types
    print "Testing basic types... "
    begin
      score = Moses::CompositeScore.new(-0.5, 10, 0.1, 0.0)
      if score.penalized_score == -0.6
        puts "PASSED"
        passed_count += 1
      else
        puts "FAILED - expected -0.6, got #{score.penalized_score}"
      end
    rescue ex
      puts "FAILED - #{ex}"
    end
    test_count += 1

    # Test 4: Optimizer creation
    print "Testing optimizer creation... "
    begin
      optimizer = MOSES.create_optimizer
      if optimizer.is_a?(MOSES::Optimizer)
        puts "PASSED"
        passed_count += 1
      else
        puts "FAILED - invalid optimizer type"
      end
    rescue ex
      puts "FAILED - #{ex}"
    end
    test_count += 1

    # Test 5: Parameter creation
    print "Testing parameter creation... "
    begin
      params = MOSES.boolean_params([[0.0, 1.0], [1.0, 0.0]], [1.0, 1.0])
      if params.is_a?(Moses::MosesParams)
        puts "PASSED"
        passed_count += 1
      else
        puts "FAILED - invalid parameter type"
      end
    rescue ex
      puts "FAILED - #{ex}"
    end
    test_count += 1

    # Test 6: Scoring function creation
    print "Testing scoring function... "
    begin
      training_data = [[0.0, 0.0], [1.0, 1.0]]
      target_data = [0.0, 1.0]
      scoring = MOSES.create_scorer(Moses::ProblemType::BooleanClassification, training_data, target_data)
      if scoring.is_a?(Moses::ScoringFunction)
        puts "PASSED"
        passed_count += 1
      else
        puts "FAILED - invalid scorer type"
      end
    rescue ex
      puts "FAILED - #{ex}"
    end
    test_count += 1

    puts "\nTest Results: #{passed_count}/#{test_count} tests passed"

    if passed_count == test_count
      puts "All tests PASSED! ✓"
    else
      puts "Some tests FAILED! ✗"
    end
  end
end

# Run if this file is executed directly
if PROGRAM_NAME.includes?("moses")
  Moses.main(ARGV)
end
