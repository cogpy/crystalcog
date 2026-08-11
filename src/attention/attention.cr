# Crystal implementation of OpenCog attention allocation mechanisms
# Based on the Economic Attention Allocation (ECAN) model

require "../atomspace/atomspace"
require "../cogutil/logger"

module Attention
  VERSION = "0.1.0"

  # Initialize the attention system
  def self.initialize
    CogUtil::Logger.info("Attention", "Initializing attention allocation system...")
    # Module initialization logic here
  end

  # ECAN Parameters - based on OpenCog's attention system
  module ECANParams
    AF_MAX_SIZE               =   1000_i32 # Maximum attentional focus size
    AF_MIN_SIZE               =    500_i32 # Minimum attentional focus size
    MAX_SPREAD_PERCENTAGE     =    0.4_f64 # 40% of STI can be spread
    DIFFUSION_TOURNAMENT_SIZE =      5_i32 # Tournament size for diffusion
    RENT_TOURNAMENT_SIZE      =      5_i32 # Tournament size for rent collection
    TARGET_STI_FUNDS          =  10000_i16 # Global STI fund target
    TARGET_LTI_FUNDS          =  10000_i16 # Global LTI fund target
    MIN_STI                   = -32768_i16 # Minimum STI value
    MAX_STI                   =  32767_i16 # Maximum STI value
    DEFAULT_DECAY_RATE        =    0.1_f64 # Default exponential forgetting rate
    DEFAULT_FORGET_THRESHOLD  =      0_i16 # STI below which hybrid forget zeros atoms
  end

  # Priority levels for attention allocation
  enum Priority
    Minimal
    Low
    Medium
    High
    Critical

    # Convert priority to boost factor
    def boost_factor : Float64
      case self
      in .critical?
        1.5
      in .high?
        1.2
      in .medium?
        1.0
      in .low?
        0.8
      in .minimal?
        0.6
      end
    end
  end

  # Enhanced attention value with calculation support
  struct AttentionMetrics
    property sti : Int16
    property lti : Int16
    property vlti : Bool
    property priority : Priority
    property rent : Float64
    property spreading_factor : Float64

    def initialize(@sti = 0_i16, @lti = 0_i16, @vlti = false,
                   @priority = Priority::Medium, @rent = 0.0, @spreading_factor = 0.0)
    end

    # Calculate overall importance score
    def importance_score : Float64
      base_score = sti.to_f64 + (lti.to_f64 * 0.1) + (vlti ? 100.0 : 0.0)
      base_score * priority.boost_factor
    end

    # Check if atom should be in attentional focus
    def in_attentional_focus?(min_sti : Int16) : Bool
      sti >= min_sti
    end

    # Calculate rent based on STI
    def calculate_rent(rent_rate : Float64 = 0.01) : Float64
      Math.max(0.0, sti.to_f64 * rent_rate)
    end

    # Apply diffusion from this atom to targets
    def diffuse_to(targets : Array(AttentionMetrics), max_spread : Float64 = ECANParams::MAX_SPREAD_PERCENTAGE)
      return if targets.empty?

      # Amount of STI to spread
      spread_amount = (sti.to_f64 * max_spread / targets.size).round.to_i16

      return if spread_amount <= 0

      # Reduce own STI
      @sti = Math.max(ECANParams::MIN_STI, @sti - (spread_amount * targets.size))

      # Increase target STIs
      targets.each do |target|
        target.sti = Math.min(ECANParams::MAX_STI, target.sti + spread_amount)
      end
    end

    def to_s(io : IO) : Nil
      io << "AV[STI:#{sti}, LTI:#{lti}, VLTI:#{vlti}, Priority:#{priority}]"
    end
  end

  # Exception for attention system errors
  class AttentionError < Exception
  end
end
