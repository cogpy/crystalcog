# Echo State Network reservoir for the Pygmalion agent's cognitive layer.
#
# A reservoir is a fixed random recurrent network. Driving it with a
# sequence leaves a fading trace ("echo") of everything it has seen in its
# state x:
#
#   x <- (1 - a) x + a tanh(W_in u + W x)
#
# W is sparse and scaled so its spectral radius is below 1, which makes the
# influence of old inputs decay instead of growing. Text enters as hashed
# character trigrams, one word per step. Everything is deterministic for a
# given seed, so two agents with the same configuration agree.

module PygmalionAgent
  class EchoStateReservoir
    INPUT_DIM = 64

    getter size : Int32
    getter spectral_radius : Float64
    getter leaking_rate : Float64
    getter state : Array(Float64)
    getter previous_state : Array(Float64)
    getter steps : Int64 = 0_i64

    @row_index : Array(Array(Int32))
    @row_weight : Array(Array(Float64))
    @input_weights : Array(Float64) # size x INPUT_DIM, row-major

    def initialize(@size : Int32 = 1000, @spectral_radius : Float64 = 0.95, sparsity : Float64 = 0.1,
                   input_scaling : Float64 = 1.0, @leaking_rate : Float64 = 0.3, seed : Int32 = 42)
      raise ArgumentError.new("reservoir size must be positive") unless @size > 0
      random = Random.new(seed)
      per_row = (@size * sparsity.clamp(0.0, 1.0)).round.to_i.clamp(1, @size)
      @row_index = Array.new(@size) { (0...@size).to_a.sample(per_row, random).sort! }
      @row_weight = Array.new(@size) { Array.new(per_row) { random.rand * 2.0 - 1.0 } }
      @input_weights = Array.new(@size * INPUT_DIM) { (random.rand * 2.0 - 1.0) * input_scaling }
      @state = Array.new(@size, 0.0)
      @previous_state = Array.new(@size, 0.0)

      radius = estimate_spectral_radius(random)
      scale = radius > 0.0 ? @spectral_radius / radius : 0.0
      @row_weight.each { |row| row.map! { |w| w * scale } }
    end

    # Largest eigenvalue magnitude of W, by power iteration. A random real
    # matrix's dominant eigenvalues may be a complex pair, for which the
    # per-step growth oscillates; the geometric mean over the last steps
    # settles on the magnitude all the same.
    private def estimate_spectral_radius(random : Random) : Float64
      vector = Array.new(@size) { random.rand - 0.5 }
      log_growth = [] of Float64
      60.times do
        product = multiply(vector)
        norm = Math.sqrt(product.sum { |v| v * v })
        return 0.0 if norm == 0.0
        log_growth << Math.log(norm / Math.sqrt(vector.sum { |v| v * v }))
        vector = product.map { |v| v / norm }
      end
      tail = log_growth.last(30)
      Math.exp(tail.sum / tail.size)
    end

    private def multiply(vector : Array(Float64)) : Array(Float64)
      Array.new(@size) do |i|
        index = @row_index[i]
        weight = @row_weight[i]
        sum = 0.0
        index.size.times { |k| sum += weight[k] * vector[index[k]] }
        sum
      end
    end

    # Advance the reservoir one step with an input of INPUT_DIM values.
    def step(input : Array(Float64)) : Array(Float64)
      raise ArgumentError.new("input must have #{INPUT_DIM} values") unless input.size == INPUT_DIM
      recurrent = multiply(@state)
      @previous_state = @state
      leak = @leaking_rate
      @state = Array.new(@size) do |i|
        drive = recurrent[i]
        base = i * INPUT_DIM
        INPUT_DIM.times { |j| drive += @input_weights[base + j] * input[j] }
        (1.0 - leak) * @previous_state[i] + leak * Math.tanh(drive)
      end
      @steps += 1
      @state
    end

    # Feed text through the reservoir, one step per word.
    def feed(text : String) : Array(Float64)
      EchoStateReservoir.words(text).each { |word| step(EchoStateReservoir.encode(word)) }
      @state
    end

    def reset : Nil
      @state = Array.new(@size, 0.0)
      @previous_state = Array.new(@size, 0.0)
      @steps = 0_i64
    end

    def self.words(text : String) : Array(String)
      text.downcase.scan(/[\p{L}\p{N}']+/).map(&.[0])
    end

    # A word as a unit vector of hashed character trigrams, so similar
    # spellings drive the reservoir similarly.
    def self.encode(word : String) : Array(Float64)
      vector = Array.new(INPUT_DIM, 0.0)
      padded = "^#{word}$"
      chars = padded.chars
      (0..Math.max(chars.size - 3, 0)).each do |i|
        gram = chars[i, 3].join
        hash = fnv1a(gram)
        vector[(hash % INPUT_DIM).to_i] += (hash >> 32) & 1 == 0 ? 1.0 : -1.0
      end
      norm = Math.sqrt(vector.sum { |v| v * v })
      norm > 0.0 ? vector.map { |v| v / norm } : vector
    end

    # FNV-1a: `String#hash` is seeded per process and would differ between runs.
    def self.fnv1a(text : String) : UInt64
      hash = 0xcbf29ce484222325_u64
      text.each_byte do |byte|
        hash ^= byte
        hash &*= 0x100000001b3_u64
      end
      hash
    end

    # Cosine similarity of two states (0 when either is all zeros).
    def self.similarity(a : Array(Float64), b : Array(Float64)) : Float64
      dot = 0.0
      norm_a = 0.0
      norm_b = 0.0
      Math.min(a.size, b.size).times do |i|
        dot += a[i] * b[i]
        norm_a += a[i] * a[i]
        norm_b += b[i] * b[i]
      end
      norm_a == 0.0 || norm_b == 0.0 ? 0.0 : dot / Math.sqrt(norm_a * norm_b)
    end

    # A fixed-size summary of the whole state: mean, standard deviation,
    # RMS activation, mean magnitude, peak magnitude, and how much of the
    # previous state still echoes in this one (their cosine similarity).
    def gestalt : Array(Float64)
      mean = @state.sum / @size
      variance = @state.sum { |v| (v - mean) ** 2 } / @size
      [mean, Math.sqrt(variance), Math.sqrt(@state.sum { |v| v * v } / @size),
       @state.sum(&.abs) / @size, @state.max_of(&.abs),
       EchoStateReservoir.similarity(@state, @previous_state)]
    end

    # The prime factors of n in ascending order (the dimensions of the
    # finest tensor shape a reservoir of n units can be folded into).
    def self.prime_factors(n : Int32) : Array(Int32)
      factors = [] of Int32
      rest = n
      divisor = 2
      while divisor.to_i64 * divisor <= rest
        while rest % divisor == 0
          factors << divisor
          rest //= divisor
        end
        divisor += 1
      end
      factors << rest if rest > 1
      factors
    end

    # The number of rooted trees with 1..count nodes (OEIS A000081):
    # 1, 1, 2, 4, 9, 20, 48, ... These count the ways n tensor factors can
    # be nested inside one another.
    def self.rooted_trees(count : Int32) : Array(Int64)
      trees = [0_i64, 1_i64] # trees[n] for n nodes; index 0 unused
      (2..count).each do |n|
        total = 0_i64
        (1...n).each do |k|
          divisor_sum = (1..k).sum { |d| k % d == 0 ? d.to_i64 * trees[d] : 0_i64 }
          total += divisor_sum * trees[n - k]
        end
        trees << total // (n - 1)
      end
      trees[1..count]? || [] of Int64
    end
  end
end
