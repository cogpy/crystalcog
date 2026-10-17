require "spec"
require "../../src/temporal/temporal_reasoning"

describe TemporalReasoning do
  before_each do
    CogUtil.initialize
    AtomSpace.initialize
    TemporalReasoning.initialize
  end

  describe "initialization" do
    it "initializes the TemporalReasoning subsystem without errors" do
      TemporalReasoning.initialize
    end

    it "has correct version" do
      TemporalReasoning::VERSION.should eq("0.1.0")
    end
  end

  describe "Interval" do
    it "creates a valid interval" do
      iv = TemporalReasoning::Interval.new(0.0, 5.0)
      iv.start_time.should eq(0.0)
      iv.end_time.should eq(5.0)
      iv.duration.should eq(5.0)
    end

    it "raises when start > end" do
      expect_raises(TemporalReasoning::TemporalException) do
        TemporalReasoning::Interval.new(10.0, 5.0)
      end
    end

    it "contains time points within interval" do
      iv = TemporalReasoning::Interval.new(1.0, 3.0)
      iv.contains?(2.0).should be_true
      iv.contains?(0.9).should be_false
      iv.contains?(3.1).should be_false
    end

    it "detects overlap" do
      a = TemporalReasoning::Interval.new(0.0, 3.0)
      b = TemporalReasoning::Interval.new(2.0, 5.0)
      c = TemporalReasoning::Interval.new(4.0, 6.0)
      a.overlaps?(b).should be_true
      a.overlaps?(c).should be_false
    end
  end

  describe "Allen interval relations" do
    it "identifies BEFORE relation" do
      a = TemporalReasoning::Interval.new(0.0, 1.0)
      b = TemporalReasoning::Interval.new(2.0, 3.0)
      TemporalReasoning.allen_relation(a, b).should eq(TemporalReasoning::IntervalRelation::BEFORE)
    end

    it "identifies MEETS relation" do
      a = TemporalReasoning::Interval.new(0.0, 2.0)
      b = TemporalReasoning::Interval.new(2.0, 4.0)
      TemporalReasoning.allen_relation(a, b).should eq(TemporalReasoning::IntervalRelation::MEETS)
    end

    it "identifies EQUALS relation" do
      a = TemporalReasoning::Interval.new(1.0, 3.0)
      b = TemporalReasoning::Interval.new(1.0, 3.0)
      TemporalReasoning.allen_relation(a, b).should eq(TemporalReasoning::IntervalRelation::EQUALS)
    end

    it "identifies OVERLAPS relation" do
      a = TemporalReasoning::Interval.new(0.0, 3.0)
      b = TemporalReasoning::Interval.new(2.0, 5.0)
      TemporalReasoning.allen_relation(a, b).should eq(TemporalReasoning::IntervalRelation::OVERLAPS)
    end

    it "identifies DURING relation" do
      a = TemporalReasoning::Interval.new(2.0, 4.0)
      b = TemporalReasoning::Interval.new(1.0, 5.0)
      TemporalReasoning.allen_relation(a, b).should eq(TemporalReasoning::IntervalRelation::DURING)
    end

    it "identifies AFTER relation" do
      a = TemporalReasoning::Interval.new(5.0, 7.0)
      b = TemporalReasoning::Interval.new(1.0, 3.0)
      TemporalReasoning.allen_relation(a, b).should eq(TemporalReasoning::IntervalRelation::AFTER)
    end
  end

  describe "Event" do
    it "creates an event with a name and interval" do
      iv = TemporalReasoning::Interval.new(0.0, 1.0)
      event = TemporalReasoning::Event.new("pickup", iv)
      event.name.should eq("pickup")
      event.id.should_not be_empty
    end

    it "checks if event is active at a time" do
      iv = TemporalReasoning::Interval.new(1.0, 3.0)
      event = TemporalReasoning::Event.new("move", iv)
      event.at_time?(2.0).should be_true
      event.at_time?(4.0).should be_false
    end
  end

  describe "Fluent" do
    it "creates a fluent and checks holds_at?" do
      fluent = TemporalReasoning::Fluent.new("door_open", "true")
      fluent.holds_at?(5.0).should be_false
      fluent.initiate(TemporalReasoning::Interval.new(3.0, 7.0))
      fluent.holds_at?(5.0).should be_true
      fluent.holds_at?(8.0).should be_false
    end
  end

  describe "Timeline" do
    it "adds events in order" do
      timeline = TemporalReasoning::Timeline.new
      e1 = TemporalReasoning::Event.new("start", TemporalReasoning::Interval.new(0.0, 1.0))
      e2 = TemporalReasoning::Event.new("middle", TemporalReasoning::Interval.new(2.0, 3.0))
      e3 = TemporalReasoning::Event.new("end", TemporalReasoning::Interval.new(4.0, 5.0))
      timeline.add_event(e3)
      timeline.add_event(e1)
      timeline.add_event(e2)
      timeline.events.first.name.should eq("start")
    end

    it "retrieves events at a specific time" do
      timeline = TemporalReasoning::Timeline.new
      e1 = TemporalReasoning::Event.new("breakfast", TemporalReasoning::Interval.new(8.0, 9.0))
      e2 = TemporalReasoning::Event.new("lunch", TemporalReasoning::Interval.new(12.0, 13.0))
      timeline.add_event(e1)
      timeline.add_event(e2)
      events_at_8_5 = timeline.events_at(8.5)
      events_at_8_5.size.should eq(1)
      events_at_8_5.first.name.should eq("breakfast")
    end

    it "retrieves events during an interval" do
      timeline = TemporalReasoning::Timeline.new
      e1 = TemporalReasoning::Event.new("a", TemporalReasoning::Interval.new(0.0, 2.0))
      e2 = TemporalReasoning::Event.new("b", TemporalReasoning::Interval.new(3.0, 5.0))
      e3 = TemporalReasoning::Event.new("c", TemporalReasoning::Interval.new(7.0, 9.0))
      timeline.add_event(e1)
      timeline.add_event(e2)
      timeline.add_event(e3)
      window = TemporalReasoning::Interval.new(1.0, 4.0)
      found = timeline.events_during(window)
      found.size.should eq(2)
    end

    it "detects causal chains" do
      timeline = TemporalReasoning::Timeline.new
      e1 = TemporalReasoning::Event.new("cause", TemporalReasoning::Interval.new(0.0, 1.0))
      e2 = TemporalReasoning::Event.new("effect", TemporalReasoning::Interval.new(2.0, 3.0))
      timeline.add_event(e1)
      timeline.add_event(e2)
      chains = timeline.causal_chains
      chains.size.should be >= 1
    end

    it "stores events in atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      timeline = TemporalReasoning::Timeline.new
      e = TemporalReasoning::Event.new("boot", TemporalReasoning::Interval.new(0.0, 0.5))
      timeline.add_event(e)
      timeline.to_atomspace(atomspace)
      atomspace.size.should be > 0
    end
  end
end

describe "TemporalReasoning enhancements" do
  describe "inverse_relation" do
    it "inverts BEFORE to AFTER and vice versa" do
      TemporalReasoning.inverse_relation(TemporalReasoning::IntervalRelation::BEFORE).should eq(TemporalReasoning::IntervalRelation::AFTER)
      TemporalReasoning.inverse_relation(TemporalReasoning::IntervalRelation::AFTER).should eq(TemporalReasoning::IntervalRelation::BEFORE)
    end

    it "inverts MEETS to MET_BY" do
      TemporalReasoning.inverse_relation(TemporalReasoning::IntervalRelation::MEETS).should eq(TemporalReasoning::IntervalRelation::MET_BY)
    end

    it "keeps EQUALS as its own inverse" do
      TemporalReasoning.inverse_relation(TemporalReasoning::IntervalRelation::EQUALS).should eq(TemporalReasoning::IntervalRelation::EQUALS)
    end

    it "is consistent with allen_relation" do
      a = TemporalReasoning::Interval.new(0.0, 2.0)
      b = TemporalReasoning::Interval.new(3.0, 5.0)
      rel = TemporalReasoning.allen_relation(a, b)
      TemporalReasoning.allen_relation(b, a).should eq(TemporalReasoning.inverse_relation(rel))
    end
  end

  describe "compose_relations" do
    it "composes BEFORE with BEFORE to BEFORE" do
      result = TemporalReasoning.compose_relations(TemporalReasoning::IntervalRelation::BEFORE, TemporalReasoning::IntervalRelation::BEFORE)
      result.should eq([TemporalReasoning::IntervalRelation::BEFORE])
    end

    it "treats EQUALS as identity" do
      result = TemporalReasoning.compose_relations(TemporalReasoning::IntervalRelation::EQUALS, TemporalReasoning::IntervalRelation::DURING)
      result.should eq([TemporalReasoning::IntervalRelation::DURING])
    end

    it "composes DURING with DURING to DURING" do
      result = TemporalReasoning.compose_relations(TemporalReasoning::IntervalRelation::DURING, TemporalReasoning::IntervalRelation::DURING)
      result.should eq([TemporalReasoning::IntervalRelation::DURING])
    end

    it "returns multiple candidates for ambiguous compositions" do
      result = TemporalReasoning.compose_relations(TemporalReasoning::IntervalRelation::BEFORE, TemporalReasoning::IntervalRelation::DURING)
      result.size.should be > 1
      result.should contain(TemporalReasoning::IntervalRelation::BEFORE)
    end
  end

  describe "Fluent#terminate" do
    it "clips a holding interval at termination time" do
      fluent = TemporalReasoning::Fluent.new("light_on")
      fluent.initiate(TemporalReasoning::Interval.new(0.0, 10.0))
      fluent.terminate(5.0)
      fluent.holds_at?(3.0).should be_true
      fluent.holds_at?(6.0).should be_false
    end

    it "removes intervals entirely after termination time" do
      fluent = TemporalReasoning::Fluent.new("alarm")
      fluent.initiate(TemporalReasoning::Interval.new(5.0, 10.0))
      fluent.terminate(2.0)
      fluent.holds_at?(7.0).should be_false
    end

    it "keeps intervals fully before termination time" do
      fluent = TemporalReasoning::Fluent.new("done")
      fluent.initiate(TemporalReasoning::Interval.new(0.0, 3.0))
      fluent.terminate(5.0)
      fluent.holds_at?(1.0).should be_true
    end
  end

  describe "Timeline sequence learning" do
    it "computes sequence statistics from event bigrams" do
      timeline = TemporalReasoning::Timeline.new
      timeline.add_event(TemporalReasoning::Event.new("wake", TemporalReasoning::Interval.new(0.0, 1.0)))
      timeline.add_event(TemporalReasoning::Event.new("eat", TemporalReasoning::Interval.new(2.0, 3.0)))
      timeline.add_event(TemporalReasoning::Event.new("work", TemporalReasoning::Interval.new(4.0, 5.0)))
      stats = timeline.sequence_statistics
      stats[{"wake", "eat"}].should eq(1)
      stats[{"eat", "work"}].should eq(1)
    end

    it "predicts next event based on observed sequences" do
      timeline = TemporalReasoning::Timeline.new
      timeline.add_event(TemporalReasoning::Event.new("a", TemporalReasoning::Interval.new(0.0, 1.0)))
      timeline.add_event(TemporalReasoning::Event.new("b", TemporalReasoning::Interval.new(2.0, 3.0)))
      timeline.add_event(TemporalReasoning::Event.new("a", TemporalReasoning::Interval.new(4.0, 5.0)))
      timeline.add_event(TemporalReasoning::Event.new("b", TemporalReasoning::Interval.new(6.0, 7.0)))
      timeline.predict_next("a").should eq("b")
    end

    it "returns nil prediction for unknown events" do
      timeline = TemporalReasoning::Timeline.new
      timeline.predict_next("unknown").should be_nil
    end
  end

  describe "Timeline causal inference" do
    it "infers causal pairs from repeated precedence" do
      timeline = TemporalReasoning::Timeline.new
      timeline.add_event(TemporalReasoning::Event.new("rain", TemporalReasoning::Interval.new(0.0, 1.0)))
      timeline.add_event(TemporalReasoning::Event.new("wet", TemporalReasoning::Interval.new(2.0, 3.0)))
      timeline.add_event(TemporalReasoning::Event.new("rain", TemporalReasoning::Interval.new(4.0, 5.0)))
      timeline.add_event(TemporalReasoning::Event.new("wet", TemporalReasoning::Interval.new(6.0, 7.0)))
      pairs = timeline.infer_causal_pairs(2)
      pairs.any? { |from, to, _| from == "rain" && to == "wet" }.should be_true
    end

    it "filters out pairs below the occurrence threshold" do
      timeline = TemporalReasoning::Timeline.new
      timeline.add_event(TemporalReasoning::Event.new("x", TemporalReasoning::Interval.new(0.0, 1.0)))
      timeline.add_event(TemporalReasoning::Event.new("y", TemporalReasoning::Interval.new(2.0, 3.0)))
      timeline.infer_causal_pairs(5).should be_empty
    end
  end
end
