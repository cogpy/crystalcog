require "spec"
require "../../src/temporal/temporal_reasoning"

describe TemporalReasoning::TemporalPlanner do
  it "plans actions when preconditions hold" do
    timeline = TemporalReasoning::Timeline.new
    # Initial fluent: door_closed holds from 0
    door = TemporalReasoning::Fluent.new("door_open", "true")
    # Don't initiate yet — start closed
    closed = TemporalReasoning::Fluent.new("door_closed", "true")
    closed.initiate(TemporalReasoning::Interval.new(0.0, 100.0))
    timeline.add_fluent(closed)

    planner = TemporalReasoning::TemporalPlanner.new(timeline)

    open_door = TemporalReasoning::PlanStep.new(
      "open_door",
      TemporalReasoning::Interval.new(1.0, 2.0),
      ["door_closed"],
      ["door_open"]
    )
    planner.register_action(open_door)

    plan = planner.plan(["door_open"], 50.0)
    plan.size.should eq(1)
    plan.first.action.should eq("open_door")
  end

  it "skips actions with unmet preconditions" do
    timeline = TemporalReasoning::Timeline.new
    planner = TemporalReasoning::TemporalPlanner.new(timeline)

    step = TemporalReasoning::PlanStep.new(
      "fly",
      TemporalReasoning::Interval.new(0.0, 1.0),
      ["has_wings"],
      ["airborne"]
    )
    planner.register_action(step)
    plan = planner.plan(["airborne"], 10.0)
    plan.should be_empty
  end

  it "finds causal plans from timeline events" do
    timeline = TemporalReasoning::Timeline.new
    e1 = TemporalReasoning::Event.new("start", TemporalReasoning::Interval.new(0.0, 1.0))
    e2 = TemporalReasoning::Event.new("middle", TemporalReasoning::Interval.new(1.0, 2.0))
    e3 = TemporalReasoning::Event.new("goal", TemporalReasoning::Interval.new(2.0, 3.0))
    timeline.add_event(e1)
    timeline.add_event(e2)
    timeline.add_event(e3)

    planner = TemporalReasoning::TemporalPlanner.new(timeline)
    chain = planner.find_causal_plan("goal")
    chain.should_not be_empty
    chain.last.name.should eq("goal")
  end
end

describe TemporalReasoning::TemporalQueryEngine do
  it "indexes events by name" do
    timeline = TemporalReasoning::Timeline.new
    timeline.add_event(TemporalReasoning::Event.new("a", TemporalReasoning::Interval.new(0.0, 1.0)))
    timeline.add_event(TemporalReasoning::Event.new("a", TemporalReasoning::Interval.new(2.0, 3.0)))
    timeline.add_event(TemporalReasoning::Event.new("b", TemporalReasoning::Interval.new(1.0, 2.0)))

    engine = TemporalReasoning::TemporalQueryEngine.new(timeline)
    engine.events_named("a").size.should eq(2)
    engine.events_named("b").size.should eq(1)
  end

  it "queries events starting in a range" do
    timeline = TemporalReasoning::Timeline.new
    timeline.add_event(TemporalReasoning::Event.new("early", TemporalReasoning::Interval.new(0.0, 1.0)))
    timeline.add_event(TemporalReasoning::Event.new("mid", TemporalReasoning::Interval.new(5.0, 6.0)))
    timeline.add_event(TemporalReasoning::Event.new("late", TemporalReasoning::Interval.new(10.0, 11.0)))

    engine = TemporalReasoning::TemporalQueryEngine.new(timeline)
    mid = engine.events_starting_between(4.0, 6.0)
    mid.size.should eq(1)
    mid.first.name.should eq("mid")
  end

  it "finds pairs with a given Allen relation" do
    timeline = TemporalReasoning::Timeline.new
    timeline.add_event(TemporalReasoning::Event.new("a", TemporalReasoning::Interval.new(0.0, 1.0)))
    timeline.add_event(TemporalReasoning::Event.new("b", TemporalReasoning::Interval.new(1.0, 2.0)))

    engine = TemporalReasoning::TemporalQueryEngine.new(timeline)
    meets = engine.pairs_with_relation(TemporalReasoning::IntervalRelation::MEETS)
    meets.size.should eq(1)
  end

  it "queries fluents at a time" do
    timeline = TemporalReasoning::Timeline.new
    f = TemporalReasoning::Fluent.new("raining", "true")
    f.initiate(TemporalReasoning::Interval.new(0.0, 5.0))
    timeline.add_fluent(f)

    engine = TemporalReasoning::TemporalQueryEngine.new(timeline)
    engine.fluents_at(2.0).size.should eq(1)
    engine.fluents_at(10.0).should be_empty
  end
end

describe "Allen composition completeness" do
  it "composes BEFORE with BEFORE as BEFORE" do
    result = TemporalReasoning.compose_relations(
      TemporalReasoning::IntervalRelation::BEFORE,
      TemporalReasoning::IntervalRelation::BEFORE
    )
    result.should eq([TemporalReasoning::IntervalRelation::BEFORE])
  end

  it "inverse of inverse is identity for all relations" do
    TemporalReasoning::IntervalRelation.values.each do |rel|
      TemporalReasoning.inverse_relation(TemporalReasoning.inverse_relation(rel)).should eq(rel)
    end
  end
end
