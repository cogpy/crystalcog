# Crystal implementation of OpenCog Truth Values
# Converted from atomspace/opencog/atoms/truthvalue/TruthValue.h
#
# Truth values represent degrees of belief and confidence in atomic propositions.

require "../cogutil/logger"

module AtomSpace
  # Type aliases for truth value components
  alias Strength = Float64
  alias Confidence = Float64
  alias Count = Float64

  # Base class for all truth value types
  abstract class TruthValue
    # Default truth values
    DEFAULT_TV = SimpleTruthValue.new(1.0, 0.0)
    TRUE_TV    = SimpleTruthValue.new(1.0, 1.0)
    FALSE_TV   = SimpleTruthValue.new(0.0, 1.0)
    NULL_TV    = SimpleTruthValue.new(0.0, 0.0)

    # Get the strength (degree of belief) [0.0, 1.0]
    abstract def strength : Strength

    # Get the confidence (degree of certainty) [0.0, 1.0]
    abstract def confidence : Confidence

    # Get the count (amount of evidence)
    abstract def count : Count

    # Check if this truth value is the default/null TV
    def null? : Bool
      strength == 0.0 && confidence == 0.0
    end

    # Check if this represents definite truth
    def true? : Bool
      strength > 0.99 && confidence > 0.99
    end

    # Check if this represents definite falsehood
    def false? : Bool
      strength < 0.01 && confidence > 0.99
    end

    # Get the type name of this truth value
    abstract def type_name : String

    # Convert to string representation
    abstract def to_s(io : IO) : Nil

    # Clone this truth value
    abstract def clone : TruthValue

    # Merge with another truth value
    abstract def merge(other : TruthValue) : TruthValue

    # Check equality with another truth value
    def ==(other : TruthValue) : Bool
      return false unless other.class == self.class
      (strength - other.strength).abs < 1e-10 &&
        (confidence - other.confidence).abs < 1e-10
    end

    # Hash function for use in collections
    def hash(hasher)
      hasher = strength.hash(hasher)
      hasher = confidence.hash(hasher)
      hasher
    end

    # Get truth value as float array [strength, confidence]
    def to_a : Array(Float64)
      [strength, confidence]
    end

    # Check if truth value is valid
    def valid? : Bool
      strength >= 0.0 && strength <= 1.0 &&
        confidence >= 0.0 && confidence <= 1.0
    end

    # Create truth value from string representation
    def self.from_string(str : String) : TruthValue
      # Parse different formats like "(0.8,0.9)" or "0.8 0.9"
      if match = str.match(/\(\s*([\d.]+)\s*,\s*([\d.]+)\s*\)/)
        strength = match[1].to_f64
        confidence = match[2].to_f64
        SimpleTruthValue.new(strength, confidence)
      elsif match = str.match(/([\d.]+)\s+([\d.]+)/)
        strength = match[1].to_f64
        confidence = match[2].to_f64
        SimpleTruthValue.new(strength, confidence)
      else
        raise ArgumentError.new("Invalid truth value format: #{str}")
      end
    end
  end

  # Simple truth value with strength and confidence
  class SimpleTruthValue < TruthValue
    getter strength : Strength
    getter confidence : Confidence

    def initialize(@strength : Strength, @confidence : Confidence)
      unless valid?
        raise ArgumentError.new("Invalid truth value: strength=#{@strength}, confidence=#{@confidence}")
      end
    end

    def count : Count
      # Convert confidence to count using standard formula
      confidence == 0.0 ? 0.0 : confidence / (1.0 - confidence)
    end

    def type_name : String
      "SimpleTruthValue"
    end

    def to_s(io : IO) : Nil
      io << "(#{strength}, #{confidence})"
    end

    def clone : TruthValue
      SimpleTruthValue.new(strength, confidence)
    end

    def merge(other : TruthValue) : TruthValue
      # Weighted average based on confidence
      total_conf = confidence + other.confidence
      return clone if total_conf == 0.0

      new_strength = (strength * confidence + other.strength * other.confidence) / total_conf
      new_confidence = total_conf > 1.0 ? 1.0 : total_conf

      SimpleTruthValue.new(new_strength, new_confidence)
    end
  end

  # Count truth value stores explicit count of evidence
  class CountTruthValue < TruthValue
    getter strength : Strength
    getter confidence : Confidence
    getter count : Count

    def initialize(@strength : Strength, @confidence : Confidence, @count : Count)
      unless valid? && @count >= 0.0
        raise ArgumentError.new("Invalid count truth value")
      end
    end

    def type_name : String
      "CountTruthValue"
    end

    def to_s(io : IO) : Nil
      io << "(#{strength}, #{confidence}, #{count})"
    end

    def clone : TruthValue
      CountTruthValue.new(strength, confidence, count)
    end

    def merge(other : TruthValue) : TruthValue
      case other
      when CountTruthValue
        # Add counts and compute new strength/confidence
        new_count = count + other.count
        return clone if new_count == 0.0

        new_strength = (strength * count + other.strength * other.count) / new_count
        new_confidence = new_count / (new_count + 1.0)

        CountTruthValue.new(new_strength, new_confidence, new_count)
      else
        # Convert other to count TV and merge
        other_count = other.count
        merge(CountTruthValue.new(other.strength, other.confidence, other_count))
      end
    end
  end

  # Indefinite truth value with lower and upper bounds
  class IndefiniteTruthValue < TruthValue
    getter lower : Strength
    getter upper : Strength
    getter confidence : Confidence

    def initialize(@lower : Strength, @upper : Strength, @confidence : Confidence = 1.0)
      unless @lower <= @upper && @lower >= 0.0 && @upper <= 1.0 && @confidence >= 0.0 && @confidence <= 1.0
        raise ArgumentError.new("Invalid indefinite truth value bounds")
      end
    end

    def strength : Strength
      (lower + upper) / 2.0
    end

    def count : Count
      confidence == 0.0 ? 0.0 : confidence / (1.0 - confidence)
    end

    def type_name : String
      "IndefiniteTruthValue"
    end

    def to_s(io : IO) : Nil
      io << "[#{lower}, #{upper}] (#{confidence})"
    end

    def clone : TruthValue
      IndefiniteTruthValue.new(lower, upper, confidence)
    end

    def merge(other : TruthValue) : TruthValue
      case other
      when IndefiniteTruthValue
        # Intersection of intervals weighted by confidence
        total_conf = confidence + other.confidence
        return clone if total_conf == 0.0

        new_lower = Math.max(lower, other.lower)
        new_upper = Math.min(upper, other.upper)

        # If intervals don't overlap, take weighted average
        if new_lower > new_upper
          weight1 = confidence / total_conf
          weight2 = other.confidence / total_conf
          new_lower = lower * weight1 + other.lower * weight2
          new_upper = upper * weight1 + other.upper * weight2
        end

        new_confidence = total_conf > 1.0 ? 1.0 : total_conf

        IndefiniteTruthValue.new(new_lower, new_upper, new_confidence)
      else
        # Convert other to indefinite TV and merge
        other_strength = other.strength
        epsilon = 0.01 # Small uncertainty
        other_indefinite = IndefiniteTruthValue.new(
          Math.max(0.0, other_strength - epsilon),
          Math.min(1.0, other_strength + epsilon),
          other.confidence
        )
        merge(other_indefinite)
      end
    end
  end

  # Fuzzy truth value with additional uncertainty
  class FuzzyTruthValue < SimpleTruthValue
    getter uncertainty : Float64

    def initialize(strength : Strength, confidence : Confidence, @uncertainty : Float64 = 0.0)
      super(strength, confidence)
      unless @uncertainty >= 0.0 && @uncertainty <= 1.0
        raise ArgumentError.new("Invalid uncertainty value: #{@uncertainty}")
      end
    end

    def type_name : String
      "FuzzyTruthValue"
    end

    def to_s(io : IO) : Nil
      io << "(#{strength}, #{confidence}, #{uncertainty})"
    end

    def clone : TruthValue
      FuzzyTruthValue.new(strength, confidence, uncertainty)
    end

    def merge(other : TruthValue) : TruthValue
      base_result = super(other)

      case other
      when FuzzyTruthValue
        # Combine uncertainties
        combined_uncertainty = Math.sqrt(uncertainty * uncertainty + other.uncertainty * other.uncertainty)
        FuzzyTruthValue.new(base_result.strength, base_result.confidence, combined_uncertainty)
      else
        FuzzyTruthValue.new(base_result.strength, base_result.confidence, uncertainty)
      end
    end
  end

  # Utility methods for truth value operations
  module TruthValueUtil
    # Logical AND of two truth values
    def self.and_tv(tv1 : TruthValue, tv2 : TruthValue) : TruthValue
      strength = tv1.strength * tv2.strength
      confidence = tv1.confidence * tv2.confidence
      SimpleTruthValue.new(strength, confidence)
    end

    # Logical OR of two truth values
    def self.or_tv(tv1 : TruthValue, tv2 : TruthValue) : TruthValue
      strength = tv1.strength + tv2.strength - tv1.strength * tv2.strength
      confidence = tv1.confidence * tv2.confidence
      SimpleTruthValue.new(strength, confidence)
    end

    # Logical NOT of a truth value
    def self.not_tv(tv : TruthValue) : TruthValue
      SimpleTruthValue.new(1.0 - tv.strength, tv.confidence)
    end

    # Implication of two truth values
    def self.implies_tv(tv1 : TruthValue, tv2 : TruthValue) : TruthValue
      # A → B ≡ ¬A ∨ B
      or_tv(not_tv(tv1), tv2)
    end
  end
end
