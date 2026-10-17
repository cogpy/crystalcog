# Temporal Reasoning Module for CrystalCog
#
# This module provides temporal reasoning capabilities including:
# - Time point and interval representation
# - Allen's Interval Algebra for temporal relationships
# - Event processing and temporal patterns
# - Temporal logic operators
#
# References:
# - Allen's Interval Algebra: Allen, 1983
# - Temporal Logic: Prior, 1967
# - Complex Event Processing: Luckham, 2002

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module Temporal
  VERSION = "0.1.0"

  # Exception classes
  class TemporalException < Exception
  end

  class InvalidTimeException < TemporalException
  end

  class InvalidIntervalException < TemporalException
  end

  # Time point representation (milliseconds since epoch)
  struct TimePoint
    getter timestamp : Int64

    def initialize(@timestamp : Int64)
    end

    def self.now : TimePoint
      new(Time.utc.to_unix_ms)
    end

    def self.from_time(time : Time) : TimePoint
      new(time.to_unix_ms)
    end

    def to_time : Time
      Time.unix_ms(@timestamp)
    end

    def +(duration : Duration) : TimePoint
      TimePoint.new(@timestamp + duration.milliseconds)
    end

    def -(other : TimePoint) : Duration
      Duration.new(@timestamp - other.timestamp)
    end

    def -(duration : Duration) : TimePoint
      TimePoint.new(@timestamp - duration.milliseconds)
    end

    def <(other : TimePoint) : Bool
      @timestamp < other.timestamp
    end

    def >(other : TimePoint) : Bool
      @timestamp > other.timestamp
    end

    def <=(other : TimePoint) : Bool
      @timestamp <= other.timestamp
    end

    def >=(other : TimePoint) : Bool
      @timestamp >= other.timestamp
    end

    def ==(other : TimePoint) : Bool
      @timestamp == other.timestamp
    end

    def to_s(io : IO)
      io << to_time.to_s("%Y-%m-%d %H:%M:%S.%L")
    end
  end

  # Duration representation
  struct Duration
    getter milliseconds : Int64

    def initialize(@milliseconds : Int64)
    end

    def self.zero : Duration
      new(0)
    end

    def self.milliseconds(ms : Int64) : Duration
      new(ms)
    end

    def self.seconds(s : Float64) : Duration
      new((s * 1000).to_i64)
    end

    def self.minutes(m : Float64) : Duration
      seconds(m * 60)
    end

    def self.hours(h : Float64) : Duration
      minutes(h * 60)
    end

    def self.days(d : Float64) : Duration
      hours(d * 24)
    end

    def +(other : Duration) : Duration
      Duration.new(@milliseconds + other.milliseconds)
    end

    def -(other : Duration) : Duration
      Duration.new(@milliseconds - other.milliseconds)
    end

    def *(scalar : Float64) : Duration
      Duration.new((@milliseconds * scalar).to_i64)
    end

    def /(scalar : Float64) : Duration
      Duration.new((@milliseconds / scalar).to_i64)
    end

    def <(other : Duration) : Bool
      @milliseconds < other.milliseconds
    end

    def >(other : Duration) : Bool
      @milliseconds > other.milliseconds
    end

    def <=(other : Duration) : Bool
      @milliseconds <= other.milliseconds
    end

    def >=(other : Duration) : Bool
      @milliseconds >= other.milliseconds
    end

    def ==(other : Duration) : Bool
      @milliseconds == other.milliseconds
    end

    def to_seconds : Float64
      @milliseconds / 1000.0
    end

    def to_s(io : IO)
      if @milliseconds < 1000
        io << "#{@milliseconds}ms"
      elsif @milliseconds < 60000
        io << "#{to_seconds.round(2)}s"
      elsif @milliseconds < 3600000
        io << "#{(@milliseconds / 60000.0).round(2)}m"
      else
        io << "#{(@milliseconds / 3600000.0).round(2)}h"
      end
    end
  end

  # Time interval with start and end points
  struct Interval
    getter start_time : TimePoint
    getter end_time : TimePoint

    def initialize(@start_time : TimePoint, @end_time : TimePoint)
      if @end_time < @start_time
        raise InvalidIntervalException.new("End time must be >= start time")
      end
    end

    def self.from_duration(start : TimePoint, duration : Duration) : Interval
      new(start, start + duration)
    end

    def duration : Duration
      @end_time - @start_time
    end

    def contains?(point : TimePoint) : Bool
      point >= @start_time && point <= @end_time
    end

    def overlaps?(other : Interval) : Bool
      @start_time <= other.end_time && @end_time >= other.start_time
    end

    def intersection(other : Interval) : Interval?
      return nil unless overlaps?(other)

      new_start = @start_time > other.start_time ? @start_time : other.start_time
      new_end = @end_time < other.end_time ? @end_time : other.end_time

      Interval.new(new_start, new_end)
    end

    def union(other : Interval) : Interval?
      return nil unless overlaps?(other)

      new_start = @start_time < other.start_time ? @start_time : other.start_time
      new_end = @end_time > other.end_time ? @end_time : other.end_time

      Interval.new(new_start, new_end)
    end

    def to_s(io : IO)
      io << "[#{@start_time} - #{@end_time}]"
    end
  end

  # Allen's Interval Algebra relations
  enum IntervalRelation
    BEFORE           # X ends before Y starts
    AFTER            # X starts after Y ends
    MEETS            # X ends exactly when Y starts
    MET_BY           # X starts exactly when Y ends
    OVERLAPS         # X starts before Y and ends during Y
    OVERLAPPED_BY    # X starts during Y and ends after Y
    STARTS           # X starts with Y but ends before Y
    STARTED_BY       # X starts with Y but ends after Y
    DURING           # X is contained within Y
    CONTAINS         # X contains Y
    FINISHES         # X ends with Y but starts after Y
    FINISHED_BY      # X ends with Y but starts before Y
    EQUALS           # X and Y are identical
  end

  # Compute Allen relation between two intervals
  def self.allen_relation(a : Interval, b : Interval) : IntervalRelation
    if a.end_time < b.start_time
      IntervalRelation::BEFORE
    elsif a.start_time > b.end_time
      IntervalRelation::AFTER
    elsif a.end_time == b.start_time
      IntervalRelation::MEETS
    elsif a.start_time == b.end_time
      IntervalRelation::MET_BY
    elsif a.start_time == b.start_time && a.end_time == b.end_time
      IntervalRelation::EQUALS
    elsif a.start_time == b.start_time
      if a.end_time < b.end_time
        IntervalRelation::STARTS
      else
        IntervalRelation::STARTED_BY
      end
    elsif a.end_time == b.end_time
      if a.start_time > b.start_time
        IntervalRelation::FINISHES
      else
        IntervalRelation::FINISHED_BY
      end
    elsif a.start_time < b.start_time && a.end_time > b.end_time
      IntervalRelation::CONTAINS
    elsif a.start_time > b.start_time && a.end_time < b.end_time
      IntervalRelation::DURING
    elsif a.start_time < b.start_time && a.end_time < b.end_time
      IntervalRelation::OVERLAPS
    else
      IntervalRelation::OVERLAPPED_BY
    end
  end

  # Represents a temporal event
  class Event
    getter id : String
    getter type : String
    getter timestamp : TimePoint
    getter interval : Interval?
    getter properties : Hash(String, String | Float64 | Bool)
    getter source : String?

    def initialize(@id : String, @type : String,
                   @timestamp : TimePoint = TimePoint.now,
                   @interval : Interval? = nil,
                   @source : String? = nil)
      @properties = {} of String => String | Float64 | Bool
    end

    def set_property(key : String, value : String | Float64 | Bool)
      @properties[key] = value
    end

    def get_property(key : String) : (String | Float64 | Bool)?
      @properties[key]?
    end

    def is_instantaneous? : Bool
      @interval.nil?
    end

    def duration : Duration
      @interval.try(&.duration) || Duration.zero
    end

    # Convert to AtomSpace representation
    def to_atomspace(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
      atoms = [] of AtomSpace::Atom

      event_node = atomspace.add_node(
        AtomSpace::AtomType::CONCEPT_NODE,
        "event_#{@id}"
      )
      atoms << event_node

      # Add event type
      type_node = atomspace.add_node(
        AtomSpace::AtomType::CONCEPT_NODE,
        @type
      )

      type_link = atomspace.add_link(
        AtomSpace::AtomType::INHERITANCE_LINK,
        [event_node, type_node]
      )
      atoms << type_link

      # Add timestamp
      time_pred = atomspace.add_node(
        AtomSpace::AtomType::PREDICATE_NODE,
        "occurs_at"
      )

      time_node = atomspace.add_node(
        AtomSpace::AtomType::CONCEPT_NODE,
        @timestamp.to_s
      )

      time_link = atomspace.add_link(
        AtomSpace::AtomType::EVALUATION_LINK,
        [time_pred, atomspace.add_link(
          AtomSpace::AtomType::LIST_LINK,
          [event_node, time_node]
        )]
      )
      atoms << time_link

      atoms
    end

    def to_s(io : IO)
      io << "Event(#{@id}: #{@type} at #{@timestamp})"
    end
  end

  # Event pattern for matching
  abstract class EventPattern
    abstract def matches?(event : Event) : Bool
  end

  # Simple type-based pattern
  class TypePattern < EventPattern
    getter event_type : String

    def initialize(@event_type : String)
    end

    def matches?(event : Event) : Bool
      event.type == @event_type
    end
  end

  # Property-based pattern
  class PropertyPattern < EventPattern
    getter conditions : Hash(String, String | Float64 | Bool)

    def initialize(@conditions : Hash(String, String | Float64 | Bool) = {} of String => String | Float64 | Bool)
    end

    def matches?(event : Event) : Bool
      @conditions.all? do |key, value|
        event.properties[key]? == value
      end
    end
  end

  # Sequence pattern (A followed by B within time window)
  class SequencePattern < EventPattern
    getter patterns : Array(EventPattern)
    getter max_gap : Duration

    def initialize(@patterns : Array(EventPattern), @max_gap : Duration = Duration.seconds(60))
    end

    def matches?(event : Event) : Bool
      # Single event can't match sequence
      false
    end

    # Check if sequence of events matches
    def matches_sequence?(events : Array(Event)) : Bool
      return false if events.size < @patterns.size

      pattern_idx = 0
      last_match_time : TimePoint? = nil

      events.each do |event|
        if @patterns[pattern_idx].matches?(event)
          if last_time = last_match_time
            gap = event.timestamp - last_time
            return false if gap > @max_gap
          end

          last_match_time = event.timestamp
          pattern_idx += 1

          return true if pattern_idx >= @patterns.size
        end
      end

      false
    end
  end

  # Complex Event Processor
  class EventProcessor
    getter events : Array(Event)
    getter patterns : Array(EventPattern)
    getter window_size : Duration
    getter handlers : Hash(String, Proc(Event, Nil))

    def initialize(@window_size : Duration = Duration.minutes(5))
      @events = [] of Event
      @patterns = [] of EventPattern
      @handlers = {} of String => Proc(Event, Nil)
      CogUtil::Logger.info("EventProcessor initialized with window #{@window_size}")
    end

    def add_pattern(pattern : EventPattern)
      @patterns << pattern
    end

    def on_event(event_type : String, &handler : Proc(Event, Nil))
      @handlers[event_type] = handler
    end

    # Process incoming event
    def process(event : Event)
      CogUtil::Logger.debug("Processing event: #{event}")

      # Add to event buffer
      @events << event

      # Clean old events outside window
      cutoff = event.timestamp - @window_size
      @events.reject! { |e| e.timestamp < cutoff }

      # Invoke type-specific handler
      if handler = @handlers[event.type]?
        handler.call(event)
      end

      # Check patterns
      @patterns.each do |pattern|
        if pattern.is_a?(SequencePattern)
          if pattern.matches_sequence?(@events)
            CogUtil::Logger.info("Sequence pattern matched!")
          end
        elsif pattern.matches?(event)
          CogUtil::Logger.info("Pattern matched for event: #{event.id}")
        end
      end
    end

    # Query events by type
    def events_of_type(type : String) : Array(Event)
      @events.select { |e| e.type == type }
    end

    # Query events in time range
    def events_in_range(start_time : TimePoint, end_time : TimePoint) : Array(Event)
      @events.select do |e|
        e.timestamp >= start_time && e.timestamp <= end_time
      end
    end

    # Get event frequency
    def frequency(type : String, window : Duration = @window_size) : Float64
      now = TimePoint.now
      cutoff = now - window

      count = @events.count { |e| e.type == type && e.timestamp >= cutoff }
      count.to_f / window.to_seconds
    end
  end

  # Temporal constraint network
  class TemporalNetwork
    getter nodes : Hash(String, TimePoint?)
    getter constraints : Array(Tuple(String, String, Duration, Duration))

    def initialize
      @nodes = {} of String => TimePoint?
      @constraints = [] of Tuple(String, String, Duration, Duration)
    end

    def add_node(name : String, time : TimePoint? = nil)
      @nodes[name] = time
    end

    # Add constraint: min_gap <= (b - a) <= max_gap
    def add_constraint(from : String, to : String, min_gap : Duration, max_gap : Duration)
      @constraints << {from, to, min_gap, max_gap}
    end

    def set_time(name : String, time : TimePoint)
      @nodes[name] = time
    end

    # Check if all constraints are satisfied
    def consistent? : Bool
      @constraints.all? do |from, to, min_gap, max_gap|
        from_time = @nodes[from]?
        to_time = @nodes[to]?

        if from_time && to_time
          gap = to_time.not_nil! - from_time.not_nil!
          gap >= min_gap && gap <= max_gap
        else
          true  # Unknown times don't violate constraints
        end
      end
    end

    # Propagate constraints (simple forward propagation)
    def propagate
      changed = true

      while changed
        changed = false

        @constraints.each do |from, to, min_gap, max_gap|
          if from_time = @nodes[from]?
            unless @nodes[to]?
              # Infer to_time from from_time + average gap
              avg_gap = (min_gap + max_gap) / 2.0
              @nodes[to] = from_time + avg_gap
              changed = true
            end
          elsif to_time = @nodes[to]?
            unless @nodes[from]?
              # Infer from_time from to_time - average gap
              avg_gap = (min_gap + max_gap) / 2.0
              @nodes[from] = to_time - avg_gap
              changed = true
            end
          end
        end
      end
    end
  end

  # Timeline for managing events and intervals
  class Timeline
    getter name : String
    getter events : Array(Event)
    getter intervals : Hash(String, Interval)

    def initialize(@name : String)
      @events = [] of Event
      @intervals = {} of String => Interval
    end

    def add_event(event : Event)
      @events << event
      @events.sort_by! { |e| e.timestamp.timestamp }
    end

    def add_interval(name : String, interval : Interval)
      @intervals[name] = interval
    end

    def events_during(interval : Interval) : Array(Event)
      @events.select { |e| interval.contains?(e.timestamp) }
    end

    def first_event : Event?
      @events.first?
    end

    def last_event : Event?
      @events.last?
    end

    def span : Interval?
      return nil if @events.empty?
      Interval.new(@events.first.timestamp, @events.last.timestamp)
    end

    # Convert to AtomSpace
    def to_atomspace(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
      atoms = [] of AtomSpace::Atom

      timeline_node = atomspace.add_node(
        AtomSpace::AtomType::CONCEPT_NODE,
        "timeline_#{@name}"
      )
      atoms << timeline_node

      @events.each do |event|
        atoms.concat(event.to_atomspace(atomspace))

        # Link event to timeline
        event_node = atomspace.add_node(
          AtomSpace::AtomType::CONCEPT_NODE,
          "event_#{event.id}"
        )

        member_link = atomspace.add_link(
          AtomSpace::AtomType::MEMBER_LINK,
          [event_node, timeline_node]
        )
        atoms << member_link
      end

      atoms
    end
  end

  # Module-level convenience methods
  def self.now : TimePoint
    TimePoint.now
  end

  def self.event(id : String, type : String) : Event
    Event.new(id, type)
  end

  def self.interval(start_time : TimePoint, end_time : TimePoint) : Interval
    Interval.new(start_time, end_time)
  end

  def self.create_processor(window : Duration = Duration.minutes(5)) : EventProcessor
    EventProcessor.new(window)
  end

  def self.create_timeline(name : String) : Timeline
    Timeline.new(name)
  end
end
