# Main attention allocation engine that coordinates all attention mechanisms
# Integrates attention bank, diffusion, and rent collection

require "./attention"
require "./attention_bank"
require "./diffusion"
require "./rent_collector"
require "./forgetting"
require "./normalization"

module Attention
  # Goal types for attention boosting
  enum Goal
    Reasoning
    Learning
    Memory
    Adaptation
    Processing

    # Get boost factor for this goal
    def boost_factor : Float64
      case self
      in .reasoning?
        0.9
      in .learning?
        0.7
      in .memory?
        0.65
      in .adaptation?
        0.75
      in .processing?
        0.85
      end
    end
  end

  # Central attention allocation engine
  class AllocationEngine
    getter bank : AttentionBank
    getter diffusion : AttentionDiffusion
    getter rent_collector : RentCollector
    getter forgetting_manager : ForgettingManager
    getter normalizer : AttentionNormalizer

    # Current goals and their weights
    getter active_goals : Hash(Goal, Float64)

    def initialize(atomspace : AtomSpace::AtomSpace)
      @bank = AttentionBank.new(atomspace)
      @diffusion = AttentionDiffusion.new(@bank)
      @rent_collector = RentCollector.new(@bank)
      @forgetting_manager = ForgettingManager.new(@bank)
      @normalizer = AttentionNormalizer.new(@bank)
      @active_goals = Hash(Goal, Float64).new

      # Default goal weights
      @active_goals[Goal::Reasoning] = 1.0
      @active_goals[Goal::Learning] = 0.8
      @active_goals[Goal::Memory] = 0.6
      @active_goals[Goal::Processing] = 0.9

      CogUtil::Logger.info("AllocationEngine", "Initialized attention allocation engine")
    end

    # Main attention allocation cycle
    def allocate_attention(cycles : Int32 = 1)
      CogUtil::Logger.info("AllocationEngine", "Starting attention allocation (#{cycles} cycles)")

      results = Hash(String, Float64).new

      cycles.times do |cycle|
        CogUtil::Logger.info("AllocationEngine", "Allocation cycle #{cycle + 1}")

        # 1. Apply goal-based attention boosting
        goal_boost_results = apply_goal_boosting

        # 2. Perform attention diffusion
        @diffusion.neighbor_diffusion(3)
        @diffusion.hebbian_diffusion(2)

        # 3. Collect rent to maintain economic balance
        rent_collected = @rent_collector.adaptive_rent_collection

        # 4. Adjust LTI-based benefits
        @rent_collector.lti_rent_adjustment

        # 5. Apply forgetting to free attention resources
        forget_results = @forgetting_manager.forget
        @forgetting_manager.prune_attentional_focus

        # 6. Normalize attention values periodically
        if (cycle + 1) % 3 == 0
          @normalizer.normalize_sti
        end

        # 7. Calculate priority scores for all atoms
        priority_results = calculate_priorities

        # Collect metrics for this cycle
        results["cycle_#{cycle + 1}_goal_boosts"] = goal_boost_results["total_boosts"]
        results["cycle_#{cycle + 1}_rent_collected"] = rent_collected.to_f64
        results["cycle_#{cycle + 1}_avg_priority"] = priority_results["average_priority"]
        results["cycle_#{cycle + 1}_decay_reclaimed"] = forget_results["decay_reclaimed"].to_f64
        results["cycle_#{cycle + 1}_lru_forgotten"] = forget_results["lru_forgotten"].to_f64
      end

      # Final statistics
      final_stats = get_allocation_statistics
      results.merge!(final_stats)

      CogUtil::Logger.info("AllocationEngine", "Completed #{cycles} allocation cycles")
      results
    end

    # Apply goal-based attention boosting
    def apply_goal_boosting : Hash(String, Float64)
      total_boosts = 0.0
      atoms_boosted = 0_i32

      CogUtil::Logger.info("AllocationEngine", "Applying goal-based attention boosting")

      @active_goals.each do |goal, weight|
        boost_factor = goal.boost_factor * weight

        # Find atoms relevant to this goal and boost them
        relevant_atoms = find_goal_relevant_atoms(goal)

        relevant_atoms.each do |handle|
          av = @bank.get_attention_value(handle)
          next unless av

          # Calculate boost amount
          boost_amount = (av.sti.to_f64 * boost_factor * 0.1).round.to_i16
          next if boost_amount <= 0

          # Apply boost
          new_sti = Math.min(ECANParams::MAX_STI, av.sti + boost_amount)
          new_av = AtomSpace::AttentionValue.new(new_sti, av.lti, av.vlti)

          if @bank.set_attention_value(handle, new_av)
            total_boosts += boost_amount
            atoms_boosted += 1
            @bank.subtract_sti_funds(boost_amount) # Deduct from funds
          end
        end
      end

      CogUtil::Logger.info("AllocationEngine", "Applied boosts to #{atoms_boosted} atoms (total: #{total_boosts})")

      {
        "total_boosts"  => total_boosts,
        "atoms_boosted" => atoms_boosted.to_f64,
      }
    end

    # Calculate priority scores for all atoms
    def calculate_priorities : Hash(String, Float64)
      priorities = Array(Float64).new

      @bank.atomspace.get_all_atoms.each do |atom|
        av = @bank.get_attention_value(atom.handle)
        priority = calculate_atom_priority(atom.handle, av)
        priorities << priority
      end

      avg_priority = priorities.empty? ? 0.0 : (priorities.sum / priorities.size)
      max_priority = priorities.empty? ? 0.0 : priorities.max

      {
        "average_priority" => avg_priority,
        "max_priority"     => max_priority,
        "total_atoms"      => priorities.size.to_f64,
      }
    end

    # Calculate priority score for a single atom
    def calculate_atom_priority(handle : AtomSpace::Handle, av : AtomSpace::AttentionValue?) : Float64
      return 0.0 unless av

      # Base priority from attention values
      base_priority = av.sti.to_f64 + (av.lti.to_f64 * 0.1) + (av.vlti ? 100.0 : 0.0)

      # Apply goal-based multipliers
      goal_multiplier = 1.0
      @active_goals.each do |goal, weight|
        if atom_relevant_to_goal?(handle, goal)
          goal_multiplier *= (1.0 + goal.boost_factor * weight * 0.2)
        end
      end

      # Factor in connectivity (atoms with more connections get priority boost)
      connectivity_boost = calculate_connectivity_boost(handle)

      # Factor in attentional focus membership
      af_boost = @bank.in_attentional_focus?(handle) ? 1.2 : 1.0

      final_priority = base_priority * goal_multiplier * (1.0 + connectivity_boost) * af_boost

      # Categorize priority
      case final_priority
      when .>= 200.0
        final_priority * 1.1 # Critical priority boost
      when .>= 150.0
        final_priority * 1.05 # High priority boost
      else
        final_priority
      end
    end

    # Find atoms relevant to a specific goal
    private def find_goal_relevant_atoms(goal : Goal) : Array(AtomSpace::Handle)
      relevant = Array(AtomSpace::Handle).new

      # This is a simplified heuristic - in a real system, this would be more sophisticated
      case goal
      when .reasoning?
        # Prioritize inference links and high-truth-value atoms
        @bank.atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK).each do |atom|
          if atom.truth_value && atom.truth_value.confidence > 0.8
            relevant << atom.handle
          end
        end
      when .learning?
        # Prioritize recently created or modified atoms
        @bank.atomspace.get_all_atoms.select { |atom| atom.handle.hash % 7 == 0 }.each do |atom| # Simple heuristic
          relevant << atom.handle
        end
      when .memory?
        # Prioritize atoms with high LTI
        @bank.atomspace.get_all_atoms.each do |atom|
          av = @bank.get_attention_value(atom.handle)
          if av && av.lti > 20
            relevant << atom.handle
          end
        end
      when .processing?
        # Prioritize atoms currently in attentional focus
        relevant = @bank.attentional_focus.dup
      when .adaptation?
        # Prioritize atoms with moderate STI (adaptation candidates)
        @bank.atomspace.get_all_atoms.each do |atom|
          av = @bank.get_attention_value(atom.handle)
          if av && av.sti > 10 && av.sti < 100
            relevant << atom.handle
          end
        end
      end

      relevant
    end

    # Check if atom is relevant to a goal
    private def atom_relevant_to_goal?(handle : AtomSpace::Handle, goal : Goal) : Bool
      find_goal_relevant_atoms(goal).includes?(handle)
    end

    # Calculate connectivity boost based on atom connections
    private def calculate_connectivity_boost(handle : AtomSpace::Handle) : Float64
      atom = @bank.atomspace.get_atom(handle)
      return 0.0 unless atom

      connections = 0_i32

      # Count outgoing connections for links
      if atom.is_a?(AtomSpace::Link)
        connections += atom.outgoing.size
      end

      # Count incoming connections (atoms that reference this atom)
      @bank.atomspace.get_all_atoms.each do |other_atom|
        if other_atom.is_a?(AtomSpace::Link) && other_atom.outgoing.any?(&.handle.==(handle))
          connections += 1
        end
      end

      # Diminishing returns on connectivity
      Math.log10(connections + 1) * 0.1
    end

    # Set goal weights for attention allocation
    def set_goals(goal_weights : Hash(Goal, Float64))
      @active_goals.clear
      @active_goals.merge!(goal_weights)

      CogUtil::Logger.info("AllocationEngine", "Updated goals: #{@active_goals}")
    end

    # Add or update a specific goal
    def set_goal(goal : Goal, weight : Float64)
      @active_goals[goal] = weight
      CogUtil::Logger.info("AllocationEngine", "Set goal #{goal} to weight #{weight}")
    end

    # Get comprehensive allocation statistics
    def get_allocation_statistics
      bank_stats = @bank.get_statistics
      diffusion_stats = @diffusion.get_statistics
      rent_stats = @rent_collector.get_statistics

      {
        "bank_sti_funds"      => bank_stats["sti_funds"].to_f64,
        "bank_lti_funds"      => bank_stats["lti_funds"].to_f64,
        "bank_af_size"        => bank_stats["af_size"].to_f64,
        "bank_af_utilization" => (bank_stats["af_size"].to_f64 / bank_stats["af_max_size"].to_f64) * 100.0,
        "diffusion_total_sti" => diffusion_stats["total_sti"].to_f64,
        "diffusion_coverage"  => diffusion_stats["af_coverage"].to_f64,
        "rent_potential"      => rent_stats["average_rent_potential"].to_f64,
        "rent_rate"           => rent_stats["rent_rate"].to_f64,
        "active_goals"        => @active_goals.size.to_f64,
      }
    end

    # Run focused attention allocation for specific atoms
    def focus_attention(target_handles : Array(AtomSpace::Handle), boost_amount : Int16 = 50_i16)
      CogUtil::Logger.info("AllocationEngine", "Focusing attention on #{target_handles.size} targets")

      target_handles.each do |handle|
        @bank.stimulate(handle, boost_amount)
      end

      # Run a single allocation cycle to propagate effects
      allocate_attention(1)
    end

    def to_s(io : IO) : Nil
      stats = get_allocation_statistics
      io << "AllocationEngine[STI Funds:#{stats["bank_sti_funds"]}, AF Utilization:#{stats["bank_af_utilization"]}%, Goals:#{@active_goals.size}]"
    end
  end
end
