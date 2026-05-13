# Temporal Reasoning for CrystalCog
#
# This module implements temporal logic and event processing,
# enabling agents to reason about time, sequences, and causal relationships.
#
# References:
# - Allen's Interval Algebra: https://en.wikipedia.org/wiki/Allen%27s_interval_algebra
# - Event Calculus: https://en.wikipedia.org/wiki/Event_calculus

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module Temporal
  VERSION = "0.1.0"

  class TemporalException < Exception
  end

  # A temporal interval [start_time, end_time]
  struct Interval
    getter start_time : Float64 # seconds since epoch (can be relative)
    getter end_time : Float64

    def initialize(@start_time : Float64, @end_time : Float64)
      raise TemporalException.new("start_time must not be greater than end_time") if @start_time > @end_time
    end

    def duration : Float64
      @end_time - @start_time
    end

    def contains?(t : Float64) : Bool
      t >= @start_time && t <= @end_time
    end

    def overlaps?(other : Interval) : Bool
      @start_time < other.end_time && @end_time > other.start_time
    end

    def to_s : String
      "[#{@start_time}, #{@end_time}]"
    end
  end

  # Allen's 13 interval relations
  enum IntervalRelation
    BEFORE        # a ends before b starts
    MEETS         # a ends exactly when b starts
    OVERLAPS      # a starts before b, they overlap, a ends before b ends
    FINISHED_BY   # b ends when a ends, b starts after a
    CONTAINS      # a starts before and ends after b
    STARTS        # a and b start together, a ends before b
    EQUALS        # a and b are identical
    STARTED_BY    # a and b start together, b ends before a
    DURING        # b starts before and ends after a
    FINISHES      # a and b end together, a starts after b
    OVERLAPPED_BY # b starts before a, they overlap
    MET_BY        # b ends exactly when a starts
    AFTER         # b ends before a starts
  end

  # Compute Allen relation between two intervals
  def self.allen_relation(a : Interval, b : Interval) : IntervalRelation
    if a.end_time < b.start_time
      IntervalRelation::BEFORE
    elsif a.end_time == b.start_time
      IntervalRelation::MEETS
    elsif a.start_time < b.start_time && a.end_time < b.end_time
      IntervalRelation::OVERLAPS
    elsif a.start_time < b.start_time && a.end_time == b.end_time
      IntervalRelation::FINISHED_BY
    elsif a.start_time < b.start_time && a.end_time > b.end_time
      IntervalRelation::CONTAINS
    elsif a.start_time == b.start_time && a.end_time < b.end_time
      IntervalRelation::STARTS
    elsif a.start_time == b.start_time && a.end_time == b.end_time
      IntervalRelation::EQUALS
    elsif a.start_time == b.start_time && a.end_time > b.end_time
      IntervalRelation::STARTED_BY
    elsif a.start_time > b.start_time && a.end_time < b.end_time
      IntervalRelation::DURING
    elsif a.start_time > b.start_time && a.end_time == b.end_time
      IntervalRelation::FINISHES
    elsif a.start_time > b.start_time && a.end_time > b.end_time && a.start_time < b.end_time
      IntervalRelation::OVERLAPPED_BY
    elsif a.start_time == b.end_time
      IntervalRelation::MET_BY
    else
      IntervalRelation::AFTER
    end
  end

  # An event that happens at a point in time or over an interval
  class Event
    getter id : String
    getter name : String
    getter interval : Interval
    getter properties : Hash(String, String)

    def initialize(@name : String, @interval : Interval)
      @id = Random::Secure.hex(8)
      @properties = {} of String => String
    end

    def at_time?(t : Float64) : Bool
      @interval.contains?(t)
    end

    def to_s : String
      "Event(#{@name}, #{@interval})"
    end
  end

  # Fluent: a property that holds over time intervals (Event Calculus)
  class Fluent
    getter name : String
    getter value : String
    property holds_during : Array(Interval)

    def initialize(@name : String, @value : String = "true")
      @holds_during = [] of Interval
    end

    def holds_at?(t : Float64) : Bool
      @holds_during.any? { |iv| iv.contains?(t) }
    end

    def initiate(interval : Interval)
      @holds_during << interval
    end
  end

  # Timeline: ordered collection of events
  class Timeline
    getter events : Array(Event)
    getter fluents : Hash(String, Fluent)

    def initialize
      @events = [] of Event
      @fluents = {} of String => Fluent
      CogUtil::Logger.info("Timeline initialized")
    end

    def add_event(event : Event)
      @events << event
      @events.sort_by! { |e| e.interval.start_time }
    end

    def add_fluent(fluent : Fluent)
      @fluents[fluent.name] = fluent
    end

    def events_at(t : Float64) : Array(Event)
      @events.select { |e| e.at_time?(t) }
    end

    def events_during(interval : Interval) : Array(Event)
      @events.select { |e| e.interval.overlaps?(interval) }
    end

    def fluent_value_at(name : String, t : Float64) : String?
      fluent = @fluents[name]?
      return nil unless fluent
      fluent.holds_at?(t) ? fluent.value : nil
    end

    # Find causal chains: sequences of events where consecutive events meet or
    # are immediately adjacent (before with no other event in between).
    def causal_chains : Array(Array(Event))
      chains = [] of Array(Event)
      @events.each_with_index do |event, i|
        chain = [event]
        remaining = @events[(i + 1)..]
        remaining.each do |next_event|
          rel = Temporal.allen_relation(chain.last.interval, next_event.interval)
          # Include MEETS (direct adjacency) and BEFORE (temporal sequence)
          if rel == IntervalRelation::MEETS || rel == IntervalRelation::BEFORE
            chain << next_event
          end
        end
        chains << chain if chain.size > 1
      end
      chains
    end

    # Store timeline in AtomSpace
    def to_atomspace(atomspace : AtomSpace::AtomSpace)
      @events.each do |event|
        event_node = atomspace.add_node(
          AtomSpace::AtomType::CONCEPT_NODE,
          "event_#{event.name}"
        )

        # Encode start/end as predicate evaluations
        start_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "start_time")
        start_val = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, event.interval.start_time.to_s)
        list1 = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [event_node, start_val])
        atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [start_pred, list1])

        end_pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "end_time")
        end_val = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, event.interval.end_time.to_s)
        list2 = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [event_node, end_val])
        atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [end_pred, list2])
      end

      # Add temporal relations between consecutive events
      @events.each_with_index do |e1, i|
        (@events[(i + 1)..]).each do |e2|
          rel = Temporal.allen_relation(e1.interval, e2.interval)
          n1 = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "event_#{e1.name}")
          n2 = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "event_#{e2.name}")
          pred = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, rel.to_s.downcase)
          list = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [n1, n2])
          atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [pred, list])
        end
      end
    end
  end

  # Initialize Temporal subsystem
  def self.initialize
    CogUtil::Logger.info("Initializing Temporal subsystem...")
    CogUtil::Logger.info("Temporal subsystem initialized successfully")
  end
end
