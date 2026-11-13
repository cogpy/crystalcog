# Text generation on top of Qwen3: prompt-prefix reuse of the KV cache,
# sampling (temperature, top-k, top-p, min-p, repetition penalty, seed),
# EOS / stop-string handling and incremental UTF-8-safe streaming.

require "./qwen3"
require "./tokenizer"
require "./chat_format"

module AphroditeJax
  class SamplingParams
    property temperature : Float64
    property top_k : Int32
    property top_p : Float64
    property min_p : Float64
    property repetition_penalty : Float64
    property max_tokens : Int32
    property stop : Array(String)
    property seed : Int64?
    property ignore_eos : Bool

    def initialize(@temperature = 0.7, @top_k = 0, @top_p = 1.0, @min_p = 0.0,
                   @repetition_penalty = 1.0, @max_tokens = 128, @stop = [] of String,
                   @seed = nil, @ignore_eos = false)
    end

    # Fields of an OpenAI/Aphrodite request body.
    def self.from_json(body : JSON::Any, default_max_tokens : Int32 = 128) : SamplingParams
      num = ->(key : String) { body[key]?.try { |v| v.as_f? || v.as_i64?.try(&.to_f) } }
      stop = body["stop"]?.try { |s| s.as_s?.try { |one| [one] } || s.as_a?.try(&.compact_map(&.as_s?)) } || [] of String
      new(
        temperature: num.call("temperature") || 0.7,
        top_k: num.call("top_k").try(&.to_i) || 0,
        top_p: num.call("top_p") || 1.0,
        min_p: num.call("min_p") || 0.0,
        repetition_penalty: num.call("repetition_penalty") || 1.0,
        max_tokens: num.call("max_tokens").try(&.to_i) || default_max_tokens,
        stop: stop,
        seed: body["seed"]?.try(&.as_i64?),
        ignore_eos: body["ignore_eos"]?.try(&.as_bool?) || false
      )
    end
  end

  # `mean_token_probability` is the geometric mean of the probability the
  # model gave each token it produced: near 1 when it was sure of every
  # step, low when it was choosing among many continuations.
  record Generation, text : String, finish_reason : String, prompt_tokens : Int32, completion_tokens : Int32,
    mean_token_probability : Float64 = 0.0

  class Generator
    getter model : Qwen3
    getter tokenizer : Tokenizer
    @cached = [] of Int32
    @mutex = Mutex.new
    @eos_ids : Set(Int32)

    def initialize(@model : Qwen3, @tokenizer : Tokenizer)
      @eos_ids = Set.new(@model.config.eos_ids)
      {"<|im_end|>", "<|endoftext|>"}.each { |t| @tokenizer.token_id(t).try { |id| @eos_ids << id } }
    end

    def self.load(dir : String, max_len : Int32 = 2048) : Generator
      new(Qwen3.load(dir, max_len), Tokenizer.from_file(File.join(dir, "tokenizer.json")))
    end

    # ChatML prompt (Qwen's chat format); an empty think block turns off
    # Qwen3's reasoning mode.
    def chat_prompt(messages : Array({String, String})) : String
      chat_prompt(messages.map { |(role, content)| JSON::Any.new({"role" => JSON::Any.new(role), "content" => JSON::Any.new(content)}) })
    end

    # Prompt for OpenAI-style messages, with function calling when `tools`
    # (OpenAI tool definitions) are given; see ChatFormat.
    def chat_prompt(messages : Array(JSON::Any), tools : Array(JSON::Any)? = nil, thinking : Bool = false) : String
      ChatFormat.prompt(messages, tools, thinking)
    end

    # Generate a completion. The block, if given, receives each new piece
    # of text as soon as it forms complete UTF-8 and cannot be part of a
    # stop string.
    def generate(prompt : String, params : SamplingParams, &on_text : String ->) : Generation
      @mutex.synchronize { generate_locked(prompt, params, on_text) }
    end

    def generate(prompt : String, params : SamplingParams) : Generation
      generate(prompt, params) { }
    end

    private def generate_locked(prompt, params, on_text) : Generation
      prompt_ids = @tokenizer.encode(prompt)
      raise ArgumentError.new("empty prompt") if prompt_ids.empty?
      budget = @model.max_len - prompt_ids.size
      raise ArgumentError.new("prompt (#{prompt_ids.size} tokens) exceeds the #{@model.max_len}-token context") if budget <= 0
      max_tokens = Math.min(params.max_tokens, budget)

      # Reuse the KV cache for the longest shared prefix (minus one token,
      # so the last prompt token is always run to get fresh logits).
      shared = 0
      limit = Math.min(@cached.size, prompt_ids.size - 1)
      while shared < limit && @cached[shared] == prompt_ids[shared]
        shared += 1
      end
      logits = @model.forward(prompt_ids[shared..], shared)
      @cached = prompt_ids.dup

      rng = params.seed.try { |s| Random.new(s) } || Random.new
      history = Set.new(prompt_ids)
      out_ids = [] of Int32
      emitted = 0
      finish = "length"
      log_probability = 0.0

      max_tokens.times do
        token = sample(logits, params, history, rng)
        if @eos_ids.includes?(token) && !params.ignore_eos
          finish = "stop"
          break
        end
        log_probability += token_log_probability(logits, token)
        out_ids << token
        history << token
        text = @tokenizer.decode(out_ids, skip_special: true)
        if cut = stop_index(text, params.stop)
          on_text.call(text[emitted...cut]) if cut > emitted
          return finish_with(text[0...cut], "stop", prompt_ids, out_ids, log_probability)
        end
        safe = safe_emit_length(text, params.stop)
        if safe > emitted
          on_text.call(text[emitted...safe])
          emitted = safe
        end
        break if out_ids.size >= max_tokens
        logits = @model.forward([token], @cached.size)
        @cached << token
      end

      text = @tokenizer.decode(out_ids, skip_special: true)
      on_text.call(text[emitted..]) if text.size > emitted
      finish_with(text, finish, prompt_ids, out_ids, log_probability)
    end

    private def finish_with(text, reason, prompt_ids, out_ids, log_probability = 0.0) : Generation
      mean = out_ids.empty? ? 0.0 : Math.exp(log_probability / out_ids.size)
      Generation.new(text, reason, prompt_ids.size, out_ids.size, mean)
    end

    # log softmax(logits)[token], at temperature 1.
    private def token_log_probability(logits : Slice(Float32), token : Int32) : Float64
      vocab = Math.min(logits.size, @tokenizer.vocab_size)
      max = logits[0]
      (1...vocab).each { |i| max = logits[i] if logits[i] > max }
      total = 0.0
      vocab.times { |i| total += Math.exp((logits[i] - max).to_f64) }
      (logits[token] - max).to_f64 - Math.log(total)
    end

    private def stop_index(text : String, stops : Array(String)) : Int32?
      stops.compact_map { |s| s.empty? ? nil : text.index(s) }.min?
    end

    # Hold back text that could still grow into a stop string, and a
    # trailing replacement char from an incomplete UTF-8 sequence.
    private def safe_emit_length(text : String, stops : Array(String)) : Int32
      safe = text.size
      safe -= 1 if safe > 0 && text[-1] == '\u{FFFD}'
      stops.each do |s|
        (1...s.size).reverse_each do |k|
          if text.ends_with?(s[0, k])
            safe = Math.min(safe, text.size - k)
            break
          end
        end
      end
      safe
    end

    def sample(logits : Slice(Float32), params : SamplingParams, history : Set(Int32), rng : Random) : Int32
      vocab = Math.min(logits.size, @tokenizer.vocab_size)
      if (rp = params.repetition_penalty) != 1.0
        history.each do |id|
          next unless id < vocab
          logits[id] = logits[id] > 0 ? (logits[id] / rp).to_f32 : (logits[id] * rp).to_f32
        end
      end
      if params.temperature <= 0.0
        best = 0
        (1...vocab).each { |i| best = i if logits[i] > logits[best] }
        return best
      end

      candidates = (0...vocab).to_a
      candidates.sort_by! { |i| -logits[i] }
      candidates = candidates.first(params.top_k) if params.top_k > 0
      max = logits[candidates[0]].to_f64
      probs = candidates.map { |i| Math.exp((logits[i] - max) / params.temperature) }
      total = probs.sum
      probs.map! { |p| p / total }

      keep = probs.size
      if params.top_p < 1.0
        acc = 0.0
        probs.each_with_index do |p, i|
          acc += p
          if acc >= params.top_p
            keep = i + 1
            break
          end
        end
      end
      if params.min_p > 0.0
        floor = probs[0] * params.min_p
        keep = Math.min(keep, probs.count { |p| p >= floor })
      end
      keep = 1 if keep < 1

      total = probs[0, keep].sum
      r = rng.rand * total
      keep.times do |i|
        r -= probs[i]
        return candidates[i] if r <= 0
      end
      candidates[keep - 1]
    end
  end
end
