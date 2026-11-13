# Qwen3 causal language model, the architecture aphrodite-jax implements:
# RMSNorm, rotary embeddings (rotate-half), grouped-query attention with
# per-head q/k RMSNorm, SwiGLU MLP, optionally tied embeddings.

require "json"
require "./safetensors"
require "./kernels"

module AphroditeJax
  class Qwen3Config
    getter hidden : Int32
    getter layers : Int32
    getter heads : Int32
    getter kv_heads : Int32
    getter head_dim : Int32
    getter intermediate : Int32
    getter vocab : Int32
    getter rope_theta : Float64
    getter eps : Float32
    getter tie_embeddings : Bool
    getter eos_ids : Array(Int32)
    getter bos_id : Int32?

    def initialize(json : JSON::Any)
      type = json["model_type"]?.try(&.as_s?)
      raise ArgumentError.new("unsupported model_type #{type.inspect}; only qwen3 is implemented") unless type == "qwen3"
      @hidden = json["hidden_size"].as_i
      @layers = json["num_hidden_layers"].as_i
      @heads = json["num_attention_heads"].as_i
      @kv_heads = json["num_key_value_heads"]?.try(&.as_i?) || @heads
      @head_dim = json["head_dim"]?.try(&.as_i?) || @hidden // @heads
      @intermediate = json["intermediate_size"].as_i
      @vocab = json["vocab_size"].as_i
      @rope_theta = json["rope_theta"]?.try { |v| v.as_f? || v.as_i64?.try(&.to_f) } || 10000.0
      @eps = (json["rms_norm_eps"]?.try(&.as_f?) || 1e-6).to_f32
      @tie_embeddings = json["tie_word_embeddings"]?.try(&.as_bool?) || false
      eos = json["eos_token_id"]?
      @eos_ids = eos.try(&.as_a?).try(&.map(&.as_i)) || eos.try(&.as_i?).try { |i| [i] } || [] of Int32
      @bos_id = json["bos_token_id"]?.try(&.as_i?)
    end
  end

  class Qwen3
    class Layer
      getter attn_norm : Slice(Float32)
      getter mlp_norm : Slice(Float32)
      getter q_norm : Slice(Float32)
      getter k_norm : Slice(Float32)
      getter wq : Slice(UInt16)
      getter wk : Slice(UInt16)
      getter wv : Slice(UInt16)
      getter wo : Slice(UInt16)
      getter w_gate : Slice(UInt16)
      getter w_up : Slice(UInt16)
      getter w_down : Slice(UInt16)

      def initialize(t : TensorSet, i : Int32)
        p = "model.layers.#{i}."
        @attn_norm = t.f32("#{p}input_layernorm.weight")
        @mlp_norm = t.f32("#{p}post_attention_layernorm.weight")
        @q_norm = t.f32("#{p}self_attn.q_norm.weight")
        @k_norm = t.f32("#{p}self_attn.k_norm.weight")
        @wq = t.bf16("#{p}self_attn.q_proj.weight")
        @wk = t.bf16("#{p}self_attn.k_proj.weight")
        @wv = t.bf16("#{p}self_attn.v_proj.weight")
        @wo = t.bf16("#{p}self_attn.o_proj.weight")
        @w_gate = t.bf16("#{p}mlp.gate_proj.weight")
        @w_up = t.bf16("#{p}mlp.up_proj.weight")
        @w_down = t.bf16("#{p}mlp.down_proj.weight")
      end
    end

    getter config : Qwen3Config
    getter max_len : Int32
    @embed : Slice(UInt16)
    @lm_head : Slice(UInt16)
    @final_norm : Slice(Float32)
    @layers : Array(Layer)
    @k_cache : Array(Slice(Float32))
    @v_cache : Array(Slice(Float32))
    @inv_freq : Array(Float64)
    @logits : Slice(Float32)
    @buffers : Buffers? = nil

    def self.load(dir : String, max_len : Int32 = 2048) : Qwen3
      config = Qwen3Config.new(JSON.parse(File.read(File.join(dir, "config.json"))))
      new(config, TensorSet.new(dir), max_len)
    end

    def initialize(@config : Qwen3Config, tensors : TensorSet, @max_len : Int32)
      c = @config
      @embed = tensors.bf16("model.embed_tokens.weight")
      @lm_head = tensors.has?("lm_head.weight") ? tensors.bf16("lm_head.weight") : @embed
      @final_norm = tensors.f32("model.norm.weight")
      @layers = (0...c.layers).map { |i| Layer.new(tensors, i) }
      kv = c.kv_heads * c.head_dim
      @k_cache = (0...c.layers).map { Slice(Float32).new(@max_len * kv) }
      @v_cache = (0...c.layers).map { Slice(Float32).new(@max_len * kv) }
      half = c.head_dim // 2
      @logits = Slice(Float32).new(c.vocab)
      @inv_freq = (0...half).map { |i| 1.0 / (c.rope_theta ** (2.0 * i / c.head_dim)) }
    end

    # Run `tokens` at positions start_pos... through the model, filling the
    # KV cache, and return the logits of the last token. The returned slice
    # is reused: it is valid until the next call.
    def forward(tokens : Array(Int32), start_pos : Int32) : Slice(Float32)
      c = @config
      n = tokens.size
      raise ArgumentError.new("context length #{start_pos + n} exceeds #{@max_len}") if start_pos + n > @max_len
      d = c.hidden
      q_dim = c.heads * c.head_dim
      kv_dim = c.kv_heads * c.head_dim
      hd = c.head_dim
      group = c.heads // c.kv_heads
      scale = (1.0 / Math.sqrt(hd)).to_f32

      buf = buffers(n)
      x = buf.x[0, n * d]
      tokens.each_with_index do |tok, t|
        raise ArgumentError.new("token id #{tok} out of range") unless 0 <= tok < c.vocab
        row = @embed.to_unsafe + tok.to_i64 * d
        d.times { |i| x[t * d + i] = AphroditeJax.bf16_to_f32(row[i]) }
      end

      h = buf.h[0, n * d]
      q = buf.q[0, n * q_dim]
      k = buf.k[0, n * kv_dim]
      v = buf.v[0, n * kv_dim]
      attn = buf.attn[0, n * q_dim]
      o = buf.o[0, n * d]
      gate = buf.gate[0, n * c.intermediate]
      up = buf.up[0, n * c.intermediate]
      tmp = buf.tmp

      @layers.each_with_index do |layer, li|
        n.times { |t| Kernels.rmsnorm(h[t * d, d], x[t * d, d], layer.attn_norm, c.eps) }
        Kernels.matmul(q, h, layer.wq, n, q_dim, d)
        Kernels.matmul(k, h, layer.wk, n, kv_dim, d)
        Kernels.matmul(v, h, layer.wv, n, kv_dim, d)

        kc = @k_cache[li]
        vc = @v_cache[li]
        n.times do |t|
          pos = start_pos + t
          c.heads.times do |hh|
            head = q[t * q_dim + hh * hd, hd]
            Kernels.rmsnorm(tmp, head, layer.q_norm, c.eps)
            rope(head, tmp, pos)
          end
          c.kv_heads.times do |hh|
            head = k[t * kv_dim + hh * hd, hd]
            Kernels.rmsnorm(tmp, head, layer.k_norm, c.eps)
            rope(head, tmp, pos)
          end
          (kc.to_unsafe + pos.to_i64 * kv_dim).copy_from(k.to_unsafe + t * kv_dim, kv_dim)
          (vc.to_unsafe + pos.to_i64 * kv_dim).copy_from(v.to_unsafe + t * kv_dim, kv_dim)
        end

        # Causal attention over the cache (positions 0..pos), heads in parallel.
        Kernels.parallel_for(c.heads, n * (start_pos + n) >= 4096 ? 2 : Int32::MAX) do |h0, h1|
          Kernels.scratch(start_pos + n) do |sp|
            scores = Slice.new(sp, start_pos + n)
            n.times do |t|
              pos = start_pos + t
              (h0...h1).each do |hh|
                qp = q.to_unsafe + t * q_dim + hh * hd
                kvh = hh // group
                (pos + 1).times do |j|
                  scores[j] = Kernels.dot(qp, kc.to_unsafe + j.to_i64 * kv_dim + kvh * hd, hd) * scale
                end
                Kernels.softmax(scores, pos + 1)
                acc_out = attn.to_unsafe + t * q_dim + hh * hd
                hd.times { |i| acc_out[i] = 0_f32 }
                (pos + 1).times do |j|
                  w = scores[j]
                  vp = vc.to_unsafe + j.to_i64 * kv_dim + kvh * hd
                  hd.times { |i| acc_out[i] += w * vp[i] }
                end
              end
            end
          end
        end

        Kernels.matmul(o, attn, layer.wo, n, d, q_dim)
        (n * d).times { |i| x[i] += o[i] }

        n.times { |t| Kernels.rmsnorm(h[t * d, d], x[t * d, d], layer.mlp_norm, c.eps) }
        Kernels.matmul(gate, h, layer.w_gate, n, c.intermediate, d)
        Kernels.matmul(up, h, layer.w_up, n, c.intermediate, d)
        (n * c.intermediate).times { |i| gate[i] = Kernels.silu(gate[i]) * up[i] }
        Kernels.matmul(o, gate, layer.w_down, n, d, c.intermediate)
        (n * d).times { |i| x[i] += o[i] }
      end

      last = buf.h[0, d]
      Kernels.rmsnorm(last, x[(n - 1) * d, d], @final_norm, c.eps)
      Kernels.matmul(@logits, last, @lm_head, 1, c.vocab, d)
      @logits
    end

    # Activation buffers for `n` tokens, reused across calls and grown on
    # demand (allocating them per call stalls Boehm GC on large blocks).
    private def buffers(n : Int32) : Buffers
      b = @buffers
      return b if b && b.tokens >= n
      @buffers = Buffers.new(@config, Math.max(n, b.try(&.tokens) || 0))
    end

    private class Buffers
      getter tokens : Int32
      getter x : Slice(Float32)
      getter h : Slice(Float32)
      getter q : Slice(Float32)
      getter k : Slice(Float32)
      getter v : Slice(Float32)
      getter attn : Slice(Float32)
      getter o : Slice(Float32)
      getter gate : Slice(Float32)
      getter up : Slice(Float32)
      getter tmp : Slice(Float32)

      def initialize(c : Qwen3Config, @tokens : Int32)
        q_dim = c.heads * c.head_dim
        kv_dim = c.kv_heads * c.head_dim
        @x = Slice(Float32).new(@tokens * c.hidden)
        @h = Slice(Float32).new(@tokens * c.hidden)
        @q = Slice(Float32).new(@tokens * q_dim)
        @k = Slice(Float32).new(@tokens * kv_dim)
        @v = Slice(Float32).new(@tokens * kv_dim)
        @attn = Slice(Float32).new(@tokens * q_dim)
        @o = Slice(Float32).new(@tokens * c.hidden)
        @gate = Slice(Float32).new(@tokens * c.intermediate)
        @up = Slice(Float32).new(@tokens * c.intermediate)
        @tmp = Slice(Float32).new(c.head_dim)
      end
    end

    # Rotate-half RoPE: pairs (i, i + d/2). `src` is the normalised head;
    # the result is written into `dst`.
    private def rope(dst : Slice(Float32), src : Slice(Float32), pos : Int32)
      half = @config.head_dim // 2
      half.times do |i|
        angle = pos * @inv_freq[i]
        cos = Math.cos(angle).to_f32
        sin = Math.sin(angle).to_f32
        a = src[i]
        b = src[i + half]
        dst[i] = a * cos - b * sin
        dst[i + half] = b * cos + a * sin
      end
    end
  end
end
