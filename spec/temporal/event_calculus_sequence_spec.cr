require "spec"
require "../../src/temporal/temporal_reasoning"

describe Temporal::EventCalculus do
  it "initiates and holds fluents after events" do
    ec = Temporal::EventCalculus.new
    rain = Temporal::Event.new("rain", Temporal::Interval.new(0.0, 1.0))
    ec.initiates(rain, "wet", "true", 10.0)

    ec.happens?("rain", 0.5).should be_true
    ec.holds_at?("wet", 2.0).should be_true
    ec.holds_at?("wet", 0.0).should be_false
  end

  it "terminates fluents and detects clipping" do
    timeline = Temporal::Timeline.new
    wet = Temporal::Fluent.new("wet", "true")
    wet.initiate(Temporal::Interval.new(0.0, 100.0))
    timeline.add_fluent(wet)

    ec = Temporal::EventCalculus.new(timeline)
    dry = Temporal::Event.new("dry", Temporal::Interval.new(5.0, 6.0))
    ec.terminates(dry, "wet")

    ec.holds_at?("wet", 3.0).should be_true
    ec.clipped?("wet", 3.0, 7.0).should be_true
  end

  it "lists fluents holding during an interval" do
    timeline = Temporal::Timeline.new
    a = Temporal::Fluent.new("a", "true")
    a.initiate(Temporal::Interval.new(0.0, 10.0))
    b = Temporal::Fluent.new("b", "true")
    b.initiate(Temporal::Interval.new(0.0, 2.0))
    timeline.add_fluent(a)
    timeline.add_fluent(b)

    ec = Temporal::EventCalculus.new(timeline)
    holding = ec.fluents_holding_during(Temporal::Interval.new(0.0, 5.0))
    holding.should contain("a")
    holding.should_not contain("b")
  end
end

describe Temporal::SequenceLearner do
  it "learns n-grams and predicts next events" do
    timeline = Temporal::Timeline.new
    %w[a b c a b d].each_with_index do |name, i|
      timeline.add_event(Temporal::Event.new(name, Temporal::Interval.new(i.to_f, i + 0.5)))
    end

    learner = Temporal::SequenceLearner.new(2)
    learner.learn_from(timeline)
    learner.unique_patterns.should be > 0
    learner.predict(["a"]).should eq("b")
    top = learner.predict_topk(["a"], 2)
    top.first[0].should eq("b")
  end

  it "supports direct sequence observation" do
    learner = Temporal::SequenceLearner.new(3)
    learner.observe(["x", "y", "z", "x", "y", "w"])
    learner.predict(["x", "y"]).should_not be_nil
    learner.probability(["x", "y", "z"]).should be > 0.0
  end

  it "rejects invalid n" do
    expect_raises(Temporal::TemporalException) do
      Temporal::SequenceLearner.new(1)
    end
  end
end

describe "Allen composition table expansions" do
  it "composes BEFORE with BEFORE as BEFORE" do
    result = Temporal.compose_relations(
      Temporal::IntervalRelation::BEFORE,
      Temporal::IntervalRelation::BEFORE
    )
    result.should eq([Temporal::IntervalRelation::BEFORE])
  end

  it "composes MEETS with MET_BY as finish-related" do
    result = Temporal.compose_relations(
      Temporal::IntervalRelation::MEETS,
      Temporal::IntervalRelation::MET_BY
    )
    result.should contain(Temporal::IntervalRelation::EQUALS)
  end

  it "preserves relation when composed with EQUALS" do
    result = Temporal.compose_relations(
      Temporal::IntervalRelation::OVERLAPS,
      Temporal::IntervalRelation::EQUALS
    )
    result.should eq([Temporal::IntervalRelation::OVERLAPS])
  end
end

describe "Timeline sequence and causal inference" do
  it "computes sequence statistics and predict_next" do
    timeline = Temporal::Timeline.new
    %w[start work work rest].each_with_index do |name, i|
      timeline.add_event(Temporal::Event.new(name, Temporal::Interval.new(i.to_f, i + 0.9)))
    end
    stats = timeline.sequence_statistics
    stats[{"work", "work"}].should eq(1)
    timeline.predict_next("work").should_not be_nil
  end

  it "infers causal pairs above threshold" do
    timeline = Temporal::Timeline.new
    # A before B twice
    timeline.add_event(Temporal::Event.new("A", Temporal::Interval.new(0.0, 0.5)))
    timeline.add_event(Temporal::Event.new("B", Temporal::Interval.new(1.0, 1.5)))
    timeline.add_event(Temporal::Event.new("A", Temporal::Interval.new(2.0, 2.5)))
    timeline.add_event(Temporal::Event.new("B", Temporal::Interval.new(3.0, 3.5)))

    pairs = timeline.infer_causal_pairs(2)
    pairs.any? { |from, to, _| from == "A" && to == "B" }.should be_true
  end
end
