require "../spec_helper"
require "../../src/temporal/temporal"

describe Temporal do
  describe "TimePoint" do
    it "creates a time point" do
      tp = Temporal::TimePoint.new(1000)
      tp.timestamp.should eq(1000)
    end

    it "creates time point for now" do
      before = Time.utc.to_unix_ms
      tp = Temporal::TimePoint.now
      after = Time.utc.to_unix_ms

      tp.timestamp.should be >= before
      tp.timestamp.should be <= after
    end

    it "adds duration to time point" do
      tp = Temporal::TimePoint.new(1000)
      dur = Temporal::Duration.seconds(1.0)
      result = tp + dur

      result.timestamp.should eq(2000)
    end

    it "compares time points" do
      earlier = Temporal::TimePoint.new(1000)
      later = Temporal::TimePoint.new(2000)

      (earlier < later).should be_true
      (later > earlier).should be_true
      (earlier <= earlier).should be_true
    end
  end

  describe "Duration" do
    it "creates duration in milliseconds" do
      d = Temporal::Duration.milliseconds(1500)
      d.milliseconds.should eq(1500)
    end

    it "creates duration in seconds" do
      d = Temporal::Duration.seconds(2.5)
      d.milliseconds.should eq(2500)
    end

    it "creates duration in minutes" do
      d = Temporal::Duration.minutes(1.0)
      d.milliseconds.should eq(60000)
    end

    it "creates duration in hours" do
      d = Temporal::Duration.hours(1.0)
      d.milliseconds.should eq(3600000)
    end

    it "adds durations" do
      d1 = Temporal::Duration.seconds(1.0)
      d2 = Temporal::Duration.seconds(2.0)
      result = d1 + d2

      result.to_seconds.should eq(3.0)
    end

    it "compares durations inclusively" do
      one_second = Temporal::Duration.seconds(1.0)
      two_seconds = Temporal::Duration.seconds(2.0)

      (one_second <= one_second).should be_true
      (two_seconds >= one_second).should be_true
    end

    it "multiplies duration by scalar" do
      d = Temporal::Duration.seconds(2.0)
      result = d * 3.0

      result.to_seconds.should eq(6.0)
    end
  end

  describe "Interval" do
    it "creates an interval" do
      start_time = Temporal::TimePoint.new(1000)
      end_time = Temporal::TimePoint.new(2000)
      interval = Temporal::Interval.new(start_time, end_time)

      interval.start_time.should eq(start_time)
      interval.end_time.should eq(end_time)
    end

    it "raises on invalid interval" do
      start_time = Temporal::TimePoint.new(2000)
      end_time = Temporal::TimePoint.new(1000)

      expect_raises(Temporal::InvalidIntervalException) do
        Temporal::Interval.new(start_time, end_time)
      end
    end

    it "calculates duration" do
      interval = Temporal::Interval.new(
        Temporal::TimePoint.new(1000),
        Temporal::TimePoint.new(3000)
      )

      interval.duration.milliseconds.should eq(2000)
    end

    it "checks if contains point" do
      interval = Temporal::Interval.new(
        Temporal::TimePoint.new(1000),
        Temporal::TimePoint.new(3000)
      )

      interval.contains?(Temporal::TimePoint.new(2000)).should be_true
      interval.contains?(Temporal::TimePoint.new(500)).should be_false
      interval.contains?(Temporal::TimePoint.new(4000)).should be_false
    end

    it "checks overlap with another interval" do
      i1 = Temporal::Interval.new(
        Temporal::TimePoint.new(1000),
        Temporal::TimePoint.new(3000)
      )

      i2 = Temporal::Interval.new(
        Temporal::TimePoint.new(2000),
        Temporal::TimePoint.new(4000)
      )

      i3 = Temporal::Interval.new(
        Temporal::TimePoint.new(5000),
        Temporal::TimePoint.new(6000)
      )

      i1.overlaps?(i2).should be_true
      i1.overlaps?(i3).should be_false
    end

    it "computes intersection" do
      i1 = Temporal::Interval.new(
        Temporal::TimePoint.new(1000),
        Temporal::TimePoint.new(3000)
      )

      i2 = Temporal::Interval.new(
        Temporal::TimePoint.new(2000),
        Temporal::TimePoint.new(4000)
      )

      intersection = i1.intersection(i2)
      intersection.should_not be_nil
      intersection.not_nil!.start_time.timestamp.should eq(2000)
      intersection.not_nil!.end_time.timestamp.should eq(3000)
    end
  end

  describe "Allen's Interval Algebra" do
    it "detects BEFORE relation" do
      i1 = Temporal::Interval.new(
        Temporal::TimePoint.new(1000),
        Temporal::TimePoint.new(2000)
      )

      i2 = Temporal::Interval.new(
        Temporal::TimePoint.new(3000),
        Temporal::TimePoint.new(4000)
      )

      relation = Temporal.allen_relation(i1, i2)
      relation.should eq(Temporal::IntervalRelation::BEFORE)
    end

    it "detects AFTER relation" do
      i1 = Temporal::Interval.new(
        Temporal::TimePoint.new(3000),
        Temporal::TimePoint.new(4000)
      )

      i2 = Temporal::Interval.new(
        Temporal::TimePoint.new(1000),
        Temporal::TimePoint.new(2000)
      )

      relation = Temporal.allen_relation(i1, i2)
      relation.should eq(Temporal::IntervalRelation::AFTER)
    end

    it "detects MEETS relation" do
      i1 = Temporal::Interval.new(
        Temporal::TimePoint.new(1000),
        Temporal::TimePoint.new(2000)
      )

      i2 = Temporal::Interval.new(
        Temporal::TimePoint.new(2000),
        Temporal::TimePoint.new(3000)
      )

      relation = Temporal.allen_relation(i1, i2)
      relation.should eq(Temporal::IntervalRelation::MEETS)
    end

    it "detects EQUALS relation" do
      i1 = Temporal::Interval.new(
        Temporal::TimePoint.new(1000),
        Temporal::TimePoint.new(2000)
      )

      i2 = Temporal::Interval.new(
        Temporal::TimePoint.new(1000),
        Temporal::TimePoint.new(2000)
      )

      relation = Temporal.allen_relation(i1, i2)
      relation.should eq(Temporal::IntervalRelation::EQUALS)
    end

    it "detects OVERLAPS relation" do
      i1 = Temporal::Interval.new(
        Temporal::TimePoint.new(1000),
        Temporal::TimePoint.new(3000)
      )

      i2 = Temporal::Interval.new(
        Temporal::TimePoint.new(2000),
        Temporal::TimePoint.new(4000)
      )

      relation = Temporal.allen_relation(i1, i2)
      relation.should eq(Temporal::IntervalRelation::OVERLAPS)
    end

    it "detects CONTAINS relation" do
      i1 = Temporal::Interval.new(
        Temporal::TimePoint.new(1000),
        Temporal::TimePoint.new(5000)
      )

      i2 = Temporal::Interval.new(
        Temporal::TimePoint.new(2000),
        Temporal::TimePoint.new(4000)
      )

      relation = Temporal.allen_relation(i1, i2)
      relation.should eq(Temporal::IntervalRelation::CONTAINS)
    end
  end

  describe "Event" do
    it "creates an event" do
      event = Temporal::Event.new("e1", "sensor_reading")
      event.id.should eq("e1")
      event.type.should eq("sensor_reading")
    end

    it "sets and gets properties" do
      event = Temporal::Event.new("e1", "measurement")
      event.set_property("value", 42.5)
      event.set_property("unit", "celsius")

      event.get_property("value").should eq(42.5)
      event.get_property("unit").should eq("celsius")
    end
  end

  describe "EventProcessor" do
    it "processes events" do
      processor = Temporal::EventProcessor.new

      events_processed = 0
      processor.on_event("test") do |event|
        events_processed += 1
      end

      processor.process(Temporal::Event.new("1", "test"))
      processor.process(Temporal::Event.new("2", "test"))

      events_processed.should eq(2)
    end

    it "filters events by type" do
      processor = Temporal::EventProcessor.new

      processor.process(Temporal::Event.new("1", "typeA"))
      processor.process(Temporal::Event.new("2", "typeB"))
      processor.process(Temporal::Event.new("3", "typeA"))

      type_a = processor.events_of_type("typeA")
      type_a.size.should eq(2)
    end
  end

  describe "TemporalNetwork" do
    it "adds nodes and constraints" do
      network = Temporal::TemporalNetwork.new

      network.add_node("start")
      network.add_node("end")
      network.add_constraint(
        "start",
        "end",
        Temporal::Duration.seconds(1.0),
        Temporal::Duration.seconds(10.0)
      )

      network.nodes.size.should eq(2)
    end

    it "checks consistency" do
      network = Temporal::TemporalNetwork.new

      network.add_node("start")
      network.add_node("end")
      network.add_constraint(
        "start",
        "end",
        Temporal::Duration.seconds(1.0),
        Temporal::Duration.seconds(10.0)
      )

      # Set times that satisfy constraint
      network.set_time("start", Temporal::TimePoint.new(0))
      network.set_time("end", Temporal::TimePoint.new(5000))

      network.consistent?.should be_true
    end

    it "detects inconsistency" do
      network = Temporal::TemporalNetwork.new

      network.add_node("start")
      network.add_node("end")
      network.add_constraint(
        "start",
        "end",
        Temporal::Duration.seconds(5.0),
        Temporal::Duration.seconds(10.0)
      )

      # Set times that violate constraint (gap too small)
      network.set_time("start", Temporal::TimePoint.new(0))
      network.set_time("end", Temporal::TimePoint.new(1000))

      network.consistent?.should be_false
    end
  end

  describe "Timeline" do
    it "adds events in order" do
      timeline = Temporal::Timeline.new("test_timeline")

      # Add events out of order
      timeline.add_event(Temporal::Event.new("3", "event", Temporal::TimePoint.new(3000)))
      timeline.add_event(Temporal::Event.new("1", "event", Temporal::TimePoint.new(1000)))
      timeline.add_event(Temporal::Event.new("2", "event", Temporal::TimePoint.new(2000)))

      # Should be sorted
      timeline.first_event.not_nil!.id.should eq("1")
      timeline.last_event.not_nil!.id.should eq("3")
    end

    it "gets events during interval" do
      timeline = Temporal::Timeline.new("test")

      timeline.add_event(Temporal::Event.new("1", "event", Temporal::TimePoint.new(1000)))
      timeline.add_event(Temporal::Event.new("2", "event", Temporal::TimePoint.new(2000)))
      timeline.add_event(Temporal::Event.new("3", "event", Temporal::TimePoint.new(3000)))
      timeline.add_event(Temporal::Event.new("4", "event", Temporal::TimePoint.new(4000)))

      interval = Temporal::Interval.new(
        Temporal::TimePoint.new(1500),
        Temporal::TimePoint.new(3500)
      )

      events = timeline.events_during(interval)
      events.size.should eq(2)
    end

    it "calculates span" do
      timeline = Temporal::Timeline.new("test")

      timeline.add_event(Temporal::Event.new("1", "event", Temporal::TimePoint.new(1000)))
      timeline.add_event(Temporal::Event.new("2", "event", Temporal::TimePoint.new(5000)))

      span = timeline.span
      span.should_not be_nil
      span.not_nil!.duration.milliseconds.should eq(4000)
    end
  end
end
