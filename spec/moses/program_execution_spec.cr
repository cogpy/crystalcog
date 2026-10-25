require "spec"
require "../../src/moses/moses_framework"

private def bool_run(program : String, inputs : Array(Float64)) : Bool | Float64
  Moses::Candidate.new(program).execute(inputs, Moses::ProblemType::BooleanClassification)
end

describe "Moses program execution" do
  it "parses before executing, so operators are honoured" do
    bool_run("not $1", [0.0, 0.0]).should eq(true)
    bool_run("not $1", [0.0, 1.0]).should eq(false)
    bool_run("$0 and not $1", [1.0, 0.0]).should eq(true)
    bool_run("($0 or $1) and not ($0 and $1)", [1.0, 1.0]).should eq(false)
    bool_run("($0 or $1) and not ($0 and $1)", [0.0, 1.0]).should eq(true)
  end

  it "applies arithmetic precedence and supports * and /" do
    run = ->(p : String, x : Float64) { Moses::Candidate.new(p).execute([x], Moses::ProblemType::Regression) }
    run.call("$0 * 2.0 + 1.0", 3.0).should eq(7.0)
    run.call("1.0 + $0 * 2.0", 3.0).should eq(7.0)
    run.call("($0 + 1.0) / 2.0", 3.0).should eq(2.0)
  end

  it "scores XOR solutions perfectly" do
    scorer = Moses::BooleanTableScoring.new([[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]], [0.0, 1.0, 1.0, 0.0])
    scorer.evaluate(Moses::Candidate.new("($0 or $1) and not ($0 and $1)")).score.should eq(0.0)
    scorer.evaluate(Moses::Candidate.new("$0 and $1")).score.should be < 0.0
  end
end

describe Moses::Representation::ProgramCrossover do
  it "always produces parseable offspring" do
    crossover = Moses::Representation::ProgramCrossover.new
    50.times do
      a, b = crossover.crossover("$0 and ($1 or not $0)", "($1 or $0) and $1")
      Moses::ProgramParser.parse(a).should_not be_nil
      Moses::ProgramParser.parse(b).should_not be_nil
      a.should_not contain("$$")
    end
  end
end

describe Moses::Representation::ProgramMutator do
  it "keeps variable tokens intact when mutating" do
    mutator = Moses::Representation::ProgramMutator.new(1.0, 2)
    100.times do
      mutated = mutator.mutate("$0 and $1")
      mutated.scan(/\$\d*/).each { |m| m[0].should match(/\A\$[01]\z/) }
    end
  end
end
