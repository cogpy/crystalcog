require "spec"
require "../../src/temporal/temporal_reasoning"

describe Temporal::TemporalPlanner do
  it "plans actions when preconditions hold" do
    timeline = Temporal::Timeline.new
    # Initial fluent: door_closed holds from 0
    door = Temporal::Fluent.new("door_open", "true")
    # Don't initiate yet — start closed
    closed = Temporal::Fluent.new("door_closed", "true")
    closed.initiate(Temporal::Interval.new(0.0, 100.0))
    timeline.add_fluent(closed)

    planner = Temporal::TemporalPlanner.new(timeline)

    open_door = Temporal::PlanStep.new(
      "open_door",
      Temporal::Interval.new(1.0, 2.0),
      ["door_closed"],
      ["door_open"]
    )
    planner.register_action(open_door)

    plan = planner.plan(["door_open"], 50.0)
    plan.size.should eq(1)
    plan.first.action.should eq("open_door")
  end

  it "skips actions with unmet preconditions" do
    timeline = Temporal::Timeline.new
    planner = Temporal::TemporalPlanner.new(timeline)

    step = Temporal::PlanStep.new(
      "fly",
      Temporal::Interval.new(0.0, 1.0),
      ["has_wings"],
      ["airborne"]
    )
    planner.register_action(step)
    plan = planner.plan(["airborne"], 10.0)
    plan.should be_empty
  end

  it "finds causal plans from timeline events" do
    timeline = Temporal::Timeline.new
    e1 = Temporal::Event.new("start", Temporal::Interval.new(0.0, 1.0))
    e2 = Temporal::Event.new("middle", Temporal::Interval.new(1.0, 2.0))
    e3 = Temporal::Event.new("goal", Temporal::Interval.new(2.0, 3.0))
    timeline.add_event(e1)
    timeline.add_event(e2)
    timeline.add_event(e3)

    planner = Temporal::TemporalPlanner.new(timeline)
    chain = planner.find_causal_plan("goal")
    chain.should_not be_empty
    chain.last.name.should eq("goal")
  end
end

describe Temporal::TemporalQueryEngine do
  it "indexes events by name" do
    timeline = Temporal::Timeline.new
    timeline.add_event(Temporal::Event.new("a", Temporal::Interval.new(0.0, 1.0)))
    timeline.add_event(Temporal::Event.new("a", Temporal::Interval.new(2.0, 3.0)))
    timeline.add_event(Temporal::Event.new("b", Temporal::Interval.new(1.0, 2.0)))

    engine = Temporal::TemporalQueryEngine.new(timeline)
    engine.events_named("a").size.should eq(2)
    engine.events_named("b").size.should eq(1)
  end

  it "queries events starting in a range" do
    timeline = Temporal::Timeline.new
    timeline.add_event(Temporal::Event.new("early", Temporal::Interval.new(0.0, 1.0)))
    timeline.add_event(Temporal::Event.new("mid", Temporal::Interval.new(5.0, 6.0)))
    timeline.add_event(Temporal::Event.new("late", Temporal::Interval.new(10.0, 11.0)))

    engine = Temporal::TemporalQueryEngine.new(timeline)
    mid = engine.events_starting_between(4.0, 6.0)
    mid.size.should eq(1)
    mid.first.name.should eq("mid")
  end

  it "finds pairs with a given Allen relation" do
    timeline = Temporal::Timeline.new
    timeline.add_event(Temporal::Event.new("a", Temporal::Interval.new(0.0, 1.0)))
    timeline.add_event(Temporal::Event.new("b", Temporal::Interval.new(1.0, 2.0)))

    engine = Temporal::TemporalQueryEngine.new(timeline)
    meets = engine.pairs_with_relation(Temporal::IntervalRelation::MEETS)
    meets.size.should eq(1)
  end

  it "queries fluents at a time" do
    timeline = Temporal::Timeline.new
    f = Temporal::Fluent.new("raining", "true")
    f.initiate(Temporal::Interval.new(0.0, 5.0))
    timeline.add_fluent(f)

    engine = Temporal::TemporalQueryEngine.new(timeline)
    engine.fluents_at(2.0).size.should eq(1)
    engine.fluents_at(10.0).should be_empty
  end
end

describe "Allen composition completeness" do
  it "composes BEFORE with BEFORE as BEFORE" do
    result = Temporal.compose_relations(
      Temporal::IntervalRelation::BEFORE,
      Temporal::IntervalRelation::BEFORE
    )
    result.should eq([Temporal::IntervalRelation::BEFORE])
  end

  it "inverse of inverse is identity for all relations" do
    Temporal::IntervalRelation.values.each do |rel|
      Temporal.inverse_relation(Temporal.inverse_relation(rel)).should eq(rel)
    end
  end
end
