# Advanced forgetting algorithms for ECAN attention allocation
# Implements exponential decay and LRU-based forgetting to free attention resources

require "./attention"
require "./attention_bank"

module Attention
  # Strategies for forgetting low-importance atoms from active attention
  enum ForgettingStrategy
    ExponentialDecay
    LRU
    Hybrid
  end

  # Tracks last-access times for LRU forgetting
  class AccessTracker
    @access_times : Hash(AtomSpace::Handle, Time)
    @access_order : Deque(AtomSpace::Handle)

    def initialize
      @access_times = {} of AtomSpace::Handle => Time
      @access_order = Deque(AtomSpace::Handle).new
    end

    def touch(handle : AtomSpace::Handle)
      @access_times[handle] = Time.utc
      @access_order.delete(handle)
      @access_order << handle
    end

    def last_access(handle : AtomSpace::Handle) : Time?
      @access_times[handle]?
    end

    def age_seconds(handle : AtomSpace::Handle) : Float64
      t = @access_times[handle]?
      return Float64::INFINITY unless t
      (Time.utc - t).total_seconds
    end

    # Returns handles ordered oldest-first (least recently used first)
    def lru_order : Array(AtomSpace::Handle)
      @access_order.to_a
    end

    def size : Int32
      @access_times.size
    end

    def forget(handle : AtomSpace::Handle)
      @access_times.delete(handle)
      @access_order.delete(handle)
    end

    def clear
      @access_times.clear
      @access_order.clear
    end
  end

  # Applies forgetting to reduce STI of stale or low-importance atoms and
  # optionally remove them from attentional focus.
  class ForgettingManager
    getter bank : AttentionBank
    getter strategy : ForgettingStrategy
    getter decay_rate : Float64
    getter min_sti_threshold : Int16
    getter access_tracker : AccessTracker

    def initialize(@bank : AttentionBank,
                   @strategy : ForgettingStrategy = ForgettingStrategy::Hybrid,
                   @decay_rate : Float64 = 0.1,
                   @min_sti_threshold : Int16 = 0_i16)
      raise AttentionError.new("decay_rate must be in (0, 1]") unless @decay_rate > 0.0 && @decay_rate <= 1.0
      @access_tracker = AccessTracker.new
    end

    # Record that an atom was accessed (for LRU tracking)
    def record_access(handle : AtomSpace::Handle)
      @access_tracker.touch(handle)
    end

    # Apply exponential decay to all atoms' STI values.
    # STI_new = STI_old * (1 - decay_rate)
    # Returns the total STI reclaimed.
    def exponential_decay : Int16
      total_reclaimed = 0_i16
      atoms_decayed = 0

      @bank.atomspace.get_all_atoms.each do |atom|
        av = @bank.get_attention_value(atom.handle)
        next unless av
        next if av.vlti # Never decay VLTI atoms

        old_sti = av.sti
        next if old_sti <= 0

        new_sti = (old_sti.to_f64 * (1.0 - @decay_rate)).round.to_i16
        new_sti = Math.max(ECANParams::MIN_STI, new_sti)
        reclaimed = (old_sti - new_sti).to_i16

        if reclaimed > 0
          new_av = AtomSpace::AttentionValue.new(new_sti, av.lti, av.vlti)
          if @bank.set_attention_value(atom.handle, new_av)
            total_reclaimed += reclaimed
            atoms_decayed += 1
          end
        end
      end

      @bank.add_sti_funds(total_reclaimed) if total_reclaimed > 0
      CogUtil::Logger.info("ForgettingManager", "Exponential decay: reclaimed #{total_reclaimed} STI from #{atoms_decayed} atoms")
      total_reclaimed
    end

    # LRU-based forgetting: reduce STI of least-recently-used atoms outside AF.
    # If no access times are tracked, falls back to lowest-STI atoms.
    # Returns number of atoms forgotten (STI set to 0 or removed from AF).
    def lru_forget(max_forget : Int32 = 10) : Int32
      forgotten = 0

      candidates = lru_candidates
      candidates.first(max_forget).each do |handle|
        av = @bank.get_attention_value(handle)
        next unless av
        next if av.vlti

        # Fully forget: zero STI, keep LTI for long-term memory
        reclaimed = av.sti
        new_av = AtomSpace::AttentionValue.new(0_i16, av.lti, false)
        if @bank.set_attention_value(handle, new_av)
          @bank.add_sti_funds(reclaimed) if reclaimed > 0
          @access_tracker.forget(handle)
          forgotten += 1
        end
      end

      CogUtil::Logger.info("ForgettingManager", "LRU forget: forgot #{forgotten} atoms")
      forgotten
    end

    # Hybrid strategy: decay all, then LRU-forget atoms below threshold
    def forget(max_lru_forget : Int32 = 10) : Hash(String, Int32)
      results = {"decay_reclaimed" => 0, "lru_forgotten" => 0}

      case @strategy
      when ForgettingStrategy::ExponentialDecay
        results["decay_reclaimed"] = exponential_decay.to_i32
      when ForgettingStrategy::LRU
        results["lru_forgotten"] = lru_forget(max_lru_forget)
      when ForgettingStrategy::Hybrid
        results["decay_reclaimed"] = exponential_decay.to_i32
        # After decay, forget atoms that fell below threshold
        below = atoms_below_threshold
        count = 0
        below.first(max_lru_forget).each do |handle|
          av = @bank.get_attention_value(handle)
          next unless av
          next if av.vlti
          reclaimed = av.sti
          new_av = AtomSpace::AttentionValue.new(0_i16, av.lti, false)
          if @bank.set_attention_value(handle, new_av)
            @bank.add_sti_funds(reclaimed) if reclaimed > 0
            @access_tracker.forget(handle)
            count += 1
          end
        end
        results["lru_forgotten"] = count
      end

      results
    end

    # Remove atoms below STI threshold from attentional focus
    def prune_attentional_focus : Int32
      removed = 0
      to_remove = [] of AtomSpace::Handle

      @bank.attentional_focus.each do |handle|
        av = @bank.get_attention_value(handle)
        if av.nil? || av.sti < @min_sti_threshold
          to_remove << handle
        end
      end

      to_remove.each do |handle|
        @bank.attentional_focus.delete(handle)
        removed += 1
      end

      removed
    end

    private def lru_candidates : Array(AtomSpace::Handle)
      order = @access_tracker.lru_order
      if order.empty?
        # Fall back to lowest-STI atoms not protected by VLTI
        scored = [] of Tuple(AtomSpace::Handle, Int16)
        @bank.atomspace.get_all_atoms.each do |atom|
          av = @bank.get_attention_value(atom.handle)
          next unless av
          next if av.vlti
          scored << {atom.handle, av.sti}
        end
        scored.sort_by { |_, sti| sti }.map { |h, _| h }
      else
        # Prefer least recently used that are not VLTI
        order.select do |h|
          av = @bank.get_attention_value(h)
          av && !av.vlti
        end
      end
    end

    private def atoms_below_threshold : Array(AtomSpace::Handle)
      result = [] of AtomSpace::Handle
      @bank.atomspace.get_all_atoms.each do |atom|
        av = @bank.get_attention_value(atom.handle)
        next unless av
        next if av.vlti
        result << atom.handle if av.sti < @min_sti_threshold && av.sti > ECANParams::MIN_STI
      end
      # Prefer LRU order among below-threshold atoms
      lru = @access_tracker.lru_order
      if lru.empty?
        result
      else
        (lru.select { |h| result.includes?(h) } + result).uniq
      end
    end
  end
end
