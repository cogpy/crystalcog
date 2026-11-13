require "json"
require "../../../../src/integrations/platform/aphrodite_jax/safetensors"
require "../../../../src/integrations/platform/aphrodite_jax/tokenizer"

# Writes a tiny random Qwen3 (2 layers, hidden 16) plus a byte-level BPE
# tokenizer with two merges and ChatML specials into a temp directory.
module TinyQwen3
  VOCAB = 261 # 256 bytes + "he" + "ll" + 3 specials

  def self.write(dir : String, seed = 42) : String
    Dir.mkdir_p(dir)
    bytes = AphroditeJax::Tokenizer.bytes_to_unicode
    vocab = {} of String => Int32
    bytes.each_with_index { |c, i| vocab[c.to_s] = i }
    vocab["he"] = 256
    vocab["ll"] = 257
    tokenizer = {
      "normalizer"    => {"type" => "NFC"},
      "pre_tokenizer" => {"type" => "ByteLevel"},
      "model"         => {"type" => "BPE", "vocab" => vocab, "merges" => [["h", "e"], ["l", "l"]]},
      "added_tokens"  => [{"id" => 258, "content" => "<|endoftext|>", "special" => true},
                         {"id" => 259, "content" => "<|im_start|>", "special" => true},
                         {"id" => 260, "content" => "<|im_end|>", "special" => true}],
    }
    File.write(File.join(dir, "tokenizer.json"), tokenizer.to_json)
    File.write(File.join(dir, "config.json"), {
      "model_type" => "qwen3", "hidden_size" => 16, "num_hidden_layers" => 2, "num_attention_heads" => 4,
      "num_key_value_heads" => 2, "head_dim" => 4, "intermediate_size" => 32, "vocab_size" => VOCAB,
      "rope_theta" => 10000, "rms_norm_eps" => 1e-6, "tie_word_embeddings" => true,
      "eos_token_id" => 260, "bos_token_id" => 258,
    }.to_json)

    shapes = {"model.embed_tokens.weight" => [VOCAB, 16], "model.norm.weight" => [16]}
    2.times do |i|
      p = "model.layers.#{i}."
      shapes["#{p}input_layernorm.weight"] = [16]
      shapes["#{p}post_attention_layernorm.weight"] = [16]
      shapes["#{p}self_attn.q_norm.weight"] = [4]
      shapes["#{p}self_attn.k_norm.weight"] = [4]
      shapes["#{p}self_attn.q_proj.weight"] = [16, 16]
      shapes["#{p}self_attn.k_proj.weight"] = [8, 16]
      shapes["#{p}self_attn.v_proj.weight"] = [8, 16]
      shapes["#{p}self_attn.o_proj.weight"] = [16, 16]
      shapes["#{p}mlp.gate_proj.weight"] = [32, 16]
      shapes["#{p}mlp.up_proj.weight"] = [32, 16]
      shapes["#{p}mlp.down_proj.weight"] = [16, 32]
    end
    rng = Random.new(seed)
    tensors = shapes.map do |name, shape|
      count = shape.product
      values = Array(Float32).new(count) { |_| name.includes?("norm") ? 1_f32 : (rng.rand(-0.5..0.5)).to_f32 }
      {name, shape, values}
    end
    write_safetensors(File.join(dir, "model.safetensors"), tensors)
    dir
  end

  def self.write_safetensors(path : String, tensors : Array({String, Array(Int32), Array(Float32)}), dtype = "BF16")
    header = {} of String => JSON::Any
    data = IO::Memory.new
    tensors.each do |(name, shape, values)|
      start = data.pos
      values.each do |v|
        if dtype == "F32"
          data.write_bytes(v, IO::ByteFormat::LittleEndian)
        else
          data.write_bytes(AphroditeJax.f32_to_bf16(v), IO::ByteFormat::LittleEndian)
        end
      end
      header[name] = JSON.parse({"dtype" => dtype, "shape" => shape, "data_offsets" => [start, data.pos]}.to_json)
    end
    json = header.to_json
    File.open(path, "w") do |f|
      f.write_bytes(json.bytesize.to_u64, IO::ByteFormat::LittleEndian)
      f << json
      f.write(data.to_slice)
    end
  end
end
