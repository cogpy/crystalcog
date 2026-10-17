require "spec"
require "../../src/temporal/temporal_reasoning"

describe TemporalReasoning::EventCalculus do
  it "initiates and holds fluents after events" do
    ec = TemporalReasoning::EventCalculus.new
    rain = TemporalReasoning::Event.new("rain", TemporalReasoning::Interval.new(0.0, 1.0))
    ec.initiates(rain, "wet", "true", 10.0)

    ec.happens?("rain", 0.5).should be_true
    ec.holds_at?("wet", 2.0).should be_true
    ec.holds_at?("wet", 0.0).should be_false
  end

  it "terminates fluents and detects clipping" do
    timeline = TemporalReasoning::Timeline.new
    wet = TemporalReasoning::Fluent.new("wet", "true")
    wet.initiate(TemporalReasoning::Interval.new(0.0, 100.0))
    timeline.add_fluent(wet)

    ec = TemporalReasoning::EventCalculus.new(timeline)
    dry = TemporalReasoning::Event.new("dry", TemporalReasoning::Interval.new(5.0, 6.0))
    ec.terminates(dry, "wet")

    ec.holds_at?("wet", 3.0).should be_true
    ec.clipped?("wet", 3.0, 7.0).should be_true
  end

  it "lists fluents holding during an interval" do
    timeline = TemporalReasoning::Timeline.new
    a = TemporalReasoning::Fluent.new("a", "true")
    a.initiate(TemporalReasoning::Interval.new(0.0, 10.0))
    b = TemporalReasoning::Fluent.new("b", "true")
    b.initiate(TemporalReasoning::Interval.new(0.0, 2.0))
    timeline.add_fluent(a)
    timeline.add_fluent(b)

    ec = TemporalReasoning::EventCalculus.new(timeline)
    holding = ec.fluents_holding_during(TemporalReasoning::Interval.new(0.0, 5.0))
    holding.should contain("a")
    holding.should_not contain("b")
  end
end

describe TemporalReasoning::SequenceLearner do
  it "learns n-grams and predicts next events" do
    timeline = TemporalReasoning::Timeline.new
    %w[a b c a b d].each_with_index do |name, i|
      timeline.add_event(TemporalReasoning::Event.new(name, TemporalReasoning::Interval.new(i.to_f, i + 0.5)))
    end

    learner = TemporalReasoning::SequenceLearner.new(2)
    learner.learn_from(timeline)
    learner.unique_patterns.should be > 0
    learner.predict(["a"]).should eq("b")
    top = learner.predict_topk(["a"], 2)
    top.first[0].should eq("b")
  end

  it "supports direct sequence observation" do
    learner = TemporalReasoning::SequenceLearner.new(3)
    learner.observe(["x", "y", "z", "x", "y", "w"])
    learner.predict(["x", "y"]).should_not be_nil
    learner.probability(["x", "y", "z"]).should be > 0.0
  end

  it "rejects invalid n" do
    expect_raises(TemporalReasoning::TemporalException) do
      TemporalReasoning::SequenceLearner.new(1)
    end
  end
end

describe "Allen composition table expansions" do
  it "composes BEFORE with BEFORE as BEFORE" do
    result = TemporalReasoning.compose_relations(
      TemporalReasoning::IntervalRelation::BEFORE,
      TemporalReasoning::IntervalRelation::BEFORE
    )
    result.should eq([TemporalReasoning::IntervalRelation::BEFORE])
  end

  it "composes MEETS with MET_BY as finish-related" do
    result = TemporalReasoning.compose_relations(
      TemporalReasoning::IntervalRelation::MEETS,
      TemporalReasoning::IntervalRelation::MET_BY
    )
    result.should contain(TemporalReasoning::IntervalRelation::EQUALS)
  end

  it "preserves relation when composed with EQUALS" do
    result = TemporalReasoning.compose_relations(
      TemporalReasoning::IntervalRelation::OVERLAPS,
      TemporalReasoning::IntervalRelation::EQUALS
    )
    result.should eq([TemporalReasoning::IntervalRelation::OVERLAPS])
  end
end

describe "Timeline sequence and causal inference" do
  it "computes sequence statistics and predict_next" do
    timeline = TemporalReasoning::Timeline.new
    %w[start work work rest].each_with_index do |name, i|
      timeline.add_event(TemporalReasoning::Event.new(name, TemporalReasoning::Interval.new(i.to_f, i + 0.9)))
    end
    stats = timeline.sequence_statistics
    stats[{"work", "work"}].should eq(1)
    timeline.predict_next("work").should_not be_nil
  end

  it "infers causal pairs above threshold" do
    timeline = TemporalReasoning::Timeline.new
    # A before B twice
    timeline.add_event(TemporalReasoning::Event.new("A", TemporalReasoning::Interval.new(0.0, 0.5)))
    timeline.add_event(TemporalReasoning::Event.new("B", TemporalReasoning::Interval.new(1.0, 1.5)))
    timeline.add_event(TemporalReasoning::Event.new("A", TemporalReasoning::Interval.new(2.0, 2.5)))
    timeline.add_event(TemporalReasoning::Event.new("B", TemporalReasoning::Interval.new(3.0, 3.5)))

    pairs = timeline.infer_causal_pairs(2)
    pairs.any? { |from, to, _| from == "A" && to == "B" }.should be_true
  end
end
