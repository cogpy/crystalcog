# Crystal implementation of OpenCog random number generation
# Converted from cogutil/opencog/util/RandGen.h and mt19937ar.h/cc
#
# This provides high-quality random number generation for OpenCog.

module CogUtil
  # High-quality random number generator based on Mersenne Twister
  # Crystal's built-in Random class already uses a high-quality algorithm,
  # so we wrap it with OpenCog-specific functionality
  class RandGen
    @rng : Random

    # Class-level default instance
    @@default : RandGen?

    def initialize(seed : UInt32? = nil)
      if seed
        @rng = Random.new(seed)
      else
        @rng = Random.new
      end
    end

    # Get default instance
    def self.default
      @@default ||= RandGen.new
    end

    # Seed the default generator
    def self.seed(seed : UInt32)
      @@default = RandGen.new(seed)
    end

    # Generate random boolean
    def randbool : Bool
      @rng.next_bool
    end

    # Generate random integer in range [0, max)
    def randint(max : Int32) : Int32
      @rng.rand(max)
    end

    # Generate random integer in range [min, max)
    def randint(min : Int32, max : Int32) : Int32
      @rng.rand(min...max)
    end

    # Generate random float in range [0.0, 1.0)
    def randfloat : Float64
      @rng.next_float
    end

    # Generate random float in range [0.0, max)
    def randfloat(max : Float64) : Float64
      @rng.next_float * max
    end

    # Generate random float in range [min, max)
    def randfloat(min : Float64, max : Float64) : Float64
      min + @rng.next_float * (max - min)
    end

    # Generate random double (alias for randfloat)
    def randdouble : Float64
      randfloat
    end

    def randdouble(max : Float64) : Float64
      randfloat(max)
    end

    def randdouble(min : Float64, max : Float64) : Float64
      randfloat(min, max)
    end

    # Generate random number from normal distribution
    # Uses Box-Muller transform
    def randnormal(mean : Float64 = 0.0, stddev : Float64 = 1.0) : Float64
      # Box-Muller transform to generate normal distribution
      if @cached_normal.nil?
        u1 = randfloat
        u2 = randfloat

        factor = Math.sqrt(-2.0 * Math.log(u1))
        @cached_normal = factor * Math.sin(2.0 * Math::PI * u2)

        mean + stddev * factor * Math.cos(2.0 * Math::PI * u2)
      else
        result = @cached_normal.not_nil!
        @cached_normal = nil
        mean + stddev * result
      end
    end

    @cached_normal : Float64?

    # Random choice from array
    def choose(array : Array(T)) : T forall T
      array[@rng.rand(array.size)]
    end

    # Random sample from array without replacement
    def sample(array : Array(T), count : Int32) : Array(T) forall T
      array.sample(count, @rng)
    end

    # Shuffle array in place
    def shuffle!(array : Array(T)) : Array(T) forall T
      array.shuffle!(@rng)
    end

    # Return shuffled copy of array
    def shuffle(array : Array(T)) : Array(T) forall T
      array.shuffle(@rng)
    end

    # Generate random bytes
    def randbytes(size : Int32) : Bytes
      bytes = Bytes.new(size)
      @rng.random_bytes(bytes)
      bytes
    end

    # Class methods using default generator
    def self.randbool : Bool
      default.randbool
    end

    def self.randint(max : Int32) : Int32
      default.randint(max)
    end

    def self.randint(min : Int32, max : Int32) : Int32
      default.randint(min, max)
    end

    def self.randfloat : Float64
      default.randfloat
    end

    def self.randfloat(max : Float64) : Float64
      default.randfloat(max)
    end

    def self.randfloat(min : Float64, max : Float64) : Float64
      default.randfloat(min, max)
    end

    def self.randdouble : Float64
      default.randdouble
    end

    def self.randdouble(max : Float64) : Float64
      default.randdouble(max)
    end

    def self.randdouble(min : Float64, max : Float64) : Float64
      default.randdouble(min, max)
    end

    def self.randnormal(mean : Float64 = 0.0, stddev : Float64 = 1.0) : Float64
      default.randnormal(mean, stddev)
    end

    def self.choose(array : Array(T)) : T forall T
      default.choose(array)
    end

    def self.sample(array : Array(T), count : Int32) : Array(T) forall T
      default.sample(array, count)
    end

    def self.shuffle!(array : Array(T)) : Array(T) forall T
      default.shuffle!(array)
    end

    def self.shuffle(array : Array(T)) : Array(T) forall T
      default.shuffle(array)
    end

    def self.randbytes(size : Int32) : Bytes
      default.randbytes(size)
    end
  end

  # Convenience functions for global access
  def self.randbool : Bool
    RandGen.randbool
  end

  def self.randint(max : Int32) : Int32
    RandGen.randint(max)
  end

  def self.randint(min : Int32, max : Int32) : Int32
    RandGen.randint(min, max)
  end

  def self.randfloat : Float64
    RandGen.randfloat
  end

  def self.randfloat(max : Float64) : Float64
    RandGen.randfloat(max)
  end

  def self.randfloat(min : Float64, max : Float64) : Float64
    RandGen.randfloat(min, max)
  end

  def self.randdouble : Float64
    RandGen.randdouble
  end

  def self.randdouble(max : Float64) : Float64
    RandGen.randdouble(max)
  end

  def self.randdouble(min : Float64, max : Float64) : Float64
    RandGen.randdouble(min, max)
  end

  def self.randnormal(mean : Float64 = 0.0, stddev : Float64 = 1.0) : Float64
    RandGen.randnormal(mean, stddev)
  end
end
