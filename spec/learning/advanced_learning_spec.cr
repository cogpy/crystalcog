require "spec"
require "../../src/learning/learning_main"

describe Learning::Advanced::SupervisedLearner do
  it "learns centroids and predicts labels" do
    learner = Learning::Advanced::SupervisedLearner.new
    examples = [
      Learning::Advanced::LabeledExample.new({"x" => 0.0, "y" => 0.0}, "A"),
      Learning::Advanced::LabeledExample.new({"x" => 0.1, "y" => 0.1}, "A"),
      Learning::Advanced::LabeledExample.new({"x" => 5.0, "y" => 5.0}, "B"),
      Learning::Advanced::LabeledExample.new({"x" => 5.1, "y" => 4.9}, "B"),
    ]
    learner.train(examples)
    learner.predict({"x" => 0.05, "y" => 0.05}).should eq("A")
    learner.predict({"x" => 5.0, "y" => 5.0}).should eq("B")
    learner.accuracy(examples).should be > 0.5
  end

  it "exports to atomspace" do
    atomspace = AtomSpace::AtomSpace.new
    learner = Learning::Advanced::SupervisedLearner.new
    learner.train([Learning::Advanced::LabeledExample.new({"x" => 1.0}, "cat")])
    count = learner.to_atomspace(atomspace)
    count.should eq(1)
  end
end

describe Learning::Advanced::ReinforcementLearner do
  it "updates Q-values and selects actions" do
    rl = Learning::Advanced::ReinforcementLearner.new(0.5, 0.9, 0.0) # greedy
    actions = ["left", "right"]
    rl.ensure_actions("s0", actions)
    rl.update("s0", "right", 1.0, "s1", actions)
    rl.q_value("s0", "right").should be > rl.q_value("s0", "left")
    rl.select_action("s0", actions).should eq("right")
    rl.best_action("s0").should eq("right")
  end

  it "builds a policy" do
    rl = Learning::Advanced::ReinforcementLearner.new(0.5, 0.9, 0.0)
    rl.update("s0", "go", 2.0, "s1", ["go", "stop"])
    rl.update("s0", "stop", 0.0, "s1", ["go", "stop"])
    policy = rl.policy
    policy["s0"].should eq("go")
  end

  it "rejects invalid learning rate" do
    expect_raises(Learning::Advanced::LearningException) do
      Learning::Advanced::ReinforcementLearner.new(0.0)
    end
  end
end

describe Learning::Advanced::OnlineLearner do
  it "observes stream and predicts" do
    online = Learning::Advanced::OnlineLearner.new(10)
    5.times do |i|
      online.observe(Learning::Advanced::LabeledExample.new({"x" => i.to_f}, i < 3 ? "low" : "high"))
    end
    online.window_count.should eq(5)
    online.updates.should eq(5)
    online.predict({"x" => 0.0}).should_not be_nil
  end

  it "evicts old examples beyond window" do
    online = Learning::Advanced::OnlineLearner.new(3)
    5.times do |i|
      online.observe(Learning::Advanced::LabeledExample.new({"x" => i.to_f}, "a"))
    end
    online.window_count.should eq(3)
  end
end

describe Learning::Advanced::TransferLearner do
  it "transfers knowledge from source to target" do
    source = Learning::Advanced::SupervisedLearner.new
    source.train([
      Learning::Advanced::LabeledExample.new({"color" => 1.0}, "fruit"),
      Learning::Advanced::LabeledExample.new({"color" => 0.0}, "veggie"),
    ])

    transfer = Learning::Advanced::TransferLearner.new(source, {"color" => "hue"}, 0.8)
    transfer.transfer_knowledge
    transfer.fine_tune([
      Learning::Advanced::LabeledExample.new({"hue" => 1.0}, "fruit"),
    ])
    transfer.predict({"hue" => 1.0}).should eq("fruit")
  end
end

describe Learning::Advanced::CurriculumLearner do
  it "trains in difficulty stages" do
    curriculum = Learning::Advanced::CurriculumLearner.new
    examples = [
      Learning::Advanced::LabeledExample.new({"x" => 10.0}, "hard"),
      Learning::Advanced::LabeledExample.new({"x" => 0.0}, "easy"),
      Learning::Advanced::LabeledExample.new({"x" => 5.0}, "med"),
      Learning::Advanced::LabeledExample.new({"x" => 0.1}, "easy"),
      Learning::Advanced::LabeledExample.new({"x" => 9.0}, "hard"),
      Learning::Advanced::LabeledExample.new({"x" => 4.0}, "med"),
    ]
    curriculum.train_curriculum(examples, 3)
    curriculum.predict({"x" => 0.0}).should_not be_nil
  end
end

describe "Learning convenience API" do
  it "creates advanced learners" do
    Learning.initialize
    Learning.supervised_learner.should be_a(Learning::Advanced::SupervisedLearner)
    Learning.reinforcement_learner.should be_a(Learning::Advanced::ReinforcementLearner)
    Learning.online_learner.should be_a(Learning::Advanced::OnlineLearner)
    Learning.curriculum_learner.should be_a(Learning::Advanced::CurriculumLearner)
  end
end
