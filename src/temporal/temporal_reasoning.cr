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

  # Inverse of an Allen relation: if allen_relation(a, b) == r,
  # then allen_relation(b, a) == inverse_relation(r).
  def self.inverse_relation(rel : IntervalRelation) : IntervalRelation
    case rel
    when IntervalRelation::BEFORE        then IntervalRelation::AFTER
    when IntervalRelation::AFTER         then IntervalRelation::BEFORE
    when IntervalRelation::MEETS         then IntervalRelation::MET_BY
    when IntervalRelation::MET_BY        then IntervalRelation::MEETS
    when IntervalRelation::OVERLAPS      then IntervalRelation::OVERLAPPED_BY
    when IntervalRelation::OVERLAPPED_BY then IntervalRelation::OVERLAPS
    when IntervalRelation::STARTS        then IntervalRelation::STARTED_BY
    when IntervalRelation::STARTED_BY    then IntervalRelation::STARTS
    when IntervalRelation::DURING        then IntervalRelation::CONTAINS
    when IntervalRelation::CONTAINS      then IntervalRelation::DURING
    when IntervalRelation::FINISHES      then IntervalRelation::FINISHED_BY
    when IntervalRelation::FINISHED_BY   then IntervalRelation::FINISHES
    else                                      IntervalRelation::EQUALS
    end
  end

  # Compose two Allen relations: given allen_relation(a, b) == r1 and
  # allen_relation(b, c) == r2, returns the set of possible relations
  # between a and c. Implements key entries of Allen's composition table;
  # unconstrained combinations return all 13 relations.
  def self.compose_relations(r1 : IntervalRelation, r2 : IntervalRelation) : Array(IntervalRelation)
    all = IntervalRelation.values

    # Identity: composing with EQUALS preserves the other relation
    return [r2] if r1 == IntervalRelation::EQUALS
    return [r1] if r2 == IntervalRelation::EQUALS

    before_ish = [IntervalRelation::BEFORE, IntervalRelation::MEETS,
                  IntervalRelation::OVERLAPS, IntervalRelation::STARTS,
                  IntervalRelation::DURING]

    case {r1, r2}
    when {IntervalRelation::BEFORE, IntervalRelation::BEFORE},
         {IntervalRelation::BEFORE, IntervalRelation::MEETS},
         {IntervalRelation::MEETS, IntervalRelation::BEFORE}
      [IntervalRelation::BEFORE]
    when {IntervalRelation::AFTER, IntervalRelation::AFTER},
         {IntervalRelation::AFTER, IntervalRelation::MET_BY},
         {IntervalRelation::MET_BY, IntervalRelation::AFTER}
      [IntervalRelation::AFTER]
    when {IntervalRelation::MEETS, IntervalRelation::MEETS}
      [IntervalRelation::BEFORE]
    when {IntervalRelation::MET_BY, IntervalRelation::MET_BY}
      [IntervalRelation::AFTER]
    when {IntervalRelation::DURING, IntervalRelation::DURING}
      [IntervalRelation::DURING]
    when {IntervalRelation::CONTAINS, IntervalRelation::CONTAINS}
      [IntervalRelation::CONTAINS]
    when {IntervalRelation::BEFORE, IntervalRelation::DURING}
      before_ish
    when {IntervalRelation::OVERLAPS, IntervalRelation::OVERLAPS}
      [IntervalRelation::BEFORE, IntervalRelation::MEETS, IntervalRelation::OVERLAPS]
    when {IntervalRelation::STARTS, IntervalRelation::STARTS}
      [IntervalRelation::STARTS]
    when {IntervalRelation::FINISHES, IntervalRelation::FINISHES}
      [IntervalRelation::FINISHES]
    else
      all
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

    # Terminate the fluent at time t (Event Calculus "terminates"):
    # clips any interval containing t so the fluent no longer holds after t.
    def terminate(t : Float64)
      @holds_during = @holds_during.compact_map do |iv|
        if iv.contains?(t)
          t > iv.start_time ? Interval.new(iv.start_time, t) : nil
        else
          iv.end_time <= t ? iv : nil
        end
      end
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

    # Learn frequent event-name sequences (bigrams) from the timeline,
    # enabling simple sequence prediction from temporal data.
    def sequence_statistics : Hash(Tuple(String, String), Int32)
      stats = Hash(Tuple(String, String), Int32).new(0)
      @events.each_cons_pair do |e1, e2|
        stats[{e1.name, e2.name}] += 1
      end
      stats
    end

    # Predict the most likely next event name after the given event name,
    # based on observed sequence statistics. Returns nil if unknown.
    def predict_next(event_name : String) : String?
      stats = sequence_statistics
      candidates = stats.select { |(from, _), _| from == event_name }
      return nil if candidates.empty?
      candidates.max_by { |_, count| count }[0][1]
    end

    # Infer causal relationships: pairs of event names where the first
    # consistently precedes (meets or is before) the second. Returns pairs
    # with their co-occurrence counts.
    def infer_causal_pairs(min_occurrences : Int32 = 2) : Array(Tuple(String, String, Int32))
      pair_counts = Hash(Tuple(String, String), Int32).new(0)

      @events.each_with_index do |e1, i|
        @events[(i + 1)..].each do |e2|
          rel = Temporal.allen_relation(e1.interval, e2.interval)
          if rel == IntervalRelation::BEFORE || rel == IntervalRelation::MEETS
            pair_counts[{e1.name, e2.name}] += 1
          end
        end
      end

      pair_counts
        .select { |_, count| count >= min_occurrences }
        .map { |(from, to), count| {from, to, count} }
        .sort_by { |_, _, count| -count }
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

  # A temporal plan step: an action to execute during an interval
  struct PlanStep
    getter action : String
    getter interval : Interval
    getter preconditions : Array(String)
    getter effects : Array(String)

    def initialize(@action : String, @interval : Interval,
                   @preconditions : Array(String) = [] of String,
                   @effects : Array(String) = [] of String)
    end
  end

  # Temporal planner using Allen relations and event-calculus fluents
  class TemporalPlanner
    getter timeline : Timeline
    getter actions : Hash(String, PlanStep)

    def initialize(@timeline : Timeline = Timeline.new)
      @actions = {} of String => PlanStep
    end

    def register_action(step : PlanStep)
      @actions[step.action] = step
    end

    # Check whether preconditions of a step hold at the start of its interval
    def preconditions_hold?(step : PlanStep) : Bool
      t = step.interval.start_time
      step.preconditions.all? do |fluent_name|
        @timeline.fluent_value_at(fluent_name, t) == "true"
      end
    end

    # Apply effects of a step: initiate effect fluents from action start through horizon
    def apply_effects(step : PlanStep, horizon : Float64 = step.interval.end_time)
      effect_interval = Interval.new(step.interval.start_time, Math.max(step.interval.end_time, horizon))
      step.effects.each do |fluent_name|
        fluent = @timeline.fluents[fluent_name]? || Fluent.new(fluent_name, "true")
        fluent.initiate(effect_interval)
        @timeline.add_fluent(fluent) unless @timeline.fluents.has_key?(fluent_name)
      end

      # Record the action as an event
      event = Event.new(step.action, step.interval)
      @timeline.add_event(event)
    end

    # Greedy temporal planning: select registered actions whose preconditions
    # hold and whose intervals don't conflict, ordered by start time.
    # goal_fluents lists fluent names that should hold at the end.
    def plan(goal_fluents : Array(String), horizon : Float64 = 100.0) : Array(PlanStep)
      selected = [] of PlanStep
      candidates = @actions.values.select { |s| s.interval.end_time <= horizon }
      candidates.sort_by! { |s| s.interval.start_time }

      candidates.each do |step|
        # Skip if overlaps an already selected step incompatibly
        conflicts = selected.any? do |prev|
          rel = Temporal.allen_relation(prev.interval, step.interval)
          rel == IntervalRelation::OVERLAPS ||
            rel == IntervalRelation::OVERLAPPED_BY ||
            rel == IntervalRelation::CONTAINS ||
            rel == IntervalRelation::DURING ||
            rel == IntervalRelation::EQUALS
        end
        next if conflicts
        next unless preconditions_hold?(step)

        apply_effects(step, horizon)
        selected << step
      end

      # Verify goals
      if goal_fluents.all? { |g| @timeline.fluent_value_at(g, horizon) == "true" }
        CogUtil::Logger.info("TemporalPlanner", "Plan succeeded with #{selected.size} steps")
      else
        CogUtil::Logger.info("TemporalPlanner", "Plan incomplete: goals not fully satisfied")
      end

      selected
    end

    # Find a sequence of existing timeline events that achieve a causal chain
    # ending with an event of the given name (simple backward search).
    def find_causal_plan(goal_event_name : String) : Array(Event)
      chains = @timeline.causal_chains
      best = chains.select { |c| c.last.name == goal_event_name }
      return [] of Event if best.empty?
      best.max_by(&.size)
    end
  end

  # Optimized temporal queries over a timeline
  class TemporalQueryEngine
    getter timeline : Timeline
    # Index: event name -> events
    @name_index : Hash(String, Array(Event))
    # Sorted by start time for range queries
    @sorted_events : Array(Event)

    def initialize(@timeline : Timeline)
      @name_index = Hash(String, Array(Event)).new { |h, k| h[k] = [] of Event }
      @sorted_events = [] of Event
      rebuild_index
    end

    def rebuild_index
      @name_index.clear
      @sorted_events = @timeline.events.sort_by { |e| e.interval.start_time }
      @sorted_events.each do |e|
        @name_index[e.name] << e
      end
    end

    # Find events by name (O(1) lookup)
    def events_named(name : String) : Array(Event)
      @name_index[name]
    end

    # Range query: events starting within [t0, t1]
    def events_starting_between(t0 : Float64, t1 : Float64) : Array(Event)
      @sorted_events.select { |e| e.interval.start_time >= t0 && e.interval.start_time <= t1 }
    end

    # Find all event pairs satisfying a given Allen relation
    def pairs_with_relation(rel : IntervalRelation) : Array(Tuple(Event, Event))
      pairs = [] of Tuple(Event, Event)
      n = @sorted_events.size
      (0...n).each do |i|
        ((i + 1)...n).each do |j|
          e1 = @sorted_events[i]
          e2 = @sorted_events[j]
          # Early exit: if e1 is fully before e2 start with gap and we want non-before, skip deeper when sorted
          if Temporal.allen_relation(e1.interval, e2.interval) == rel
            pairs << {e1, e2}
          end
        end
      end
      pairs
    end

    # Query fluents holding at time t
    def fluents_at(t : Float64) : Array(Fluent)
      @timeline.fluents.values.select { |f| f.holds_at?(t) }
    end
  end

  # Initialize Temporal subsystem
  def self.initialize
    CogUtil::Logger.info("Initializing Temporal subsystem...")
    CogUtil::Logger.info("Temporal subsystem initialized successfully")
  end
end
