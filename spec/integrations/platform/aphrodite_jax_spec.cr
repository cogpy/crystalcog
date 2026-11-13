require "spec"
require "file_utils"
require "http/client"
require "../../../src/integrations/platform/aphrodite_jax_server"
require "./support/tiny_qwen3"

private def tiny_dir : String
  TinyQwen3.write(File.tempname("tiny-qwen3"))
end

describe AphroditeJax::Safetensors do
  it "reads BF16 and F32 tensors with shapes" do
    dir = File.tempname("st")
    Dir.mkdir_p(dir)
    begin
      path = File.join(dir, "a.safetensors")
      TinyQwen3.write_safetensors(path, [{"w", [2, 2], [1.5_f32, -2.0_f32, 0.25_f32, 3.0_f32]}], "F32")
      st = AphroditeJax::Safetensors.new(path)
      st.shape("w").should eq([2_i64, 2_i64])
      st.f32("w").to_a.should eq([1.5_f32, -2.0_f32, 0.25_f32, 3.0_f32])
      expect_raises(KeyError) { st.bf16("missing") }
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "converts between f32, bf16 and f16" do
    AphroditeJax.bf16_to_f32(AphroditeJax.f32_to_bf16(3.140625_f32)).should eq(3.140625_f32)
    AphroditeJax.f16_to_f32(0x3C00_u16).should eq(1.0_f32)
    AphroditeJax.f16_to_f32(0xC000_u16).should eq(-2.0_f32)
  end
end

describe AphroditeJax::Tokenizer do
  it "applies merges, splits specials and round-trips text" do
    dir = tiny_dir
    begin
      t = AphroditeJax::Tokenizer.from_file(File.join(dir, "tokenizer.json"))
      ids = t.encode("<|im_start|>hello<|im_end|>")
      ids.first.should eq(259)
      ids.last.should eq(260)
      ids.should contain(256) # "he"
      ids.should contain(257) # "ll"
      t.decode(ids).should eq("<|im_start|>hello<|im_end|>")
      t.decode(ids, skip_special: true).should eq("hello")
      text = "Héllo, wörld! 日本 😊\n\tok"
      t.decode(t.encode(text)).should eq(text)
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end

describe AphroditeJax::Qwen3 do
  it "gives the same logits through the KV cache as a full recompute" do
    dir = tiny_dir
    begin
      a = AphroditeJax::Qwen3.load(dir, 32)
      b = AphroditeJax::Qwen3.load(dir, 32)
      toks = [259, 104, 256, 257, 111]
      a.forward(toks[0, 4], 0)
      step = a.forward([toks[4]], 4)
      full = b.forward(toks, 0)
      step.size.should eq(TinyQwen3::VOCAB)
      (0...step.size).max_of { |i| (step[i] - full[i]).abs }.should be < 1e-5
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "gives the same logits for a prompt batch (blocked kernel) as token by token" do
    dir = tiny_dir
    begin
      a = AphroditeJax::Qwen3.load(dir, 32)
      b = AphroditeJax::Qwen3.load(dir, 32)
      toks = [259, 104, 256, 257, 111, 104, 105, 259, 256, 111, 257, 104]
      batch = a.forward(toks, 0)
      step = Slice(Float32).new(0)
      toks.each_with_index { |tok, i| step = b.forward([tok], i) }
      (0...step.size).max_of { |i| (step[i] - batch[i]).abs }.should be < 1e-4
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "computes the same products with the blocked and row matmul kernels" do
    rng = Random.new(7)
    n, rows, cols = 9, 37, 19
    x = Slice(Float32).new(n * cols) { rng.rand(-1.0..1.0).to_f32 }
    w = Slice(UInt16).new(rows * cols) { AphroditeJax.f32_to_bf16(rng.rand(-1.0..1.0).to_f32) }
    a = Slice(Float32).new(n * rows)
    b = Slice(Float32).new(n * rows)
    AphroditeJax::Kernels.matmul_blocked(a, x, w, n, rows, cols)
    AphroditeJax::Kernels.matmul_rows(b, x, w, n, rows, cols)
    (0...a.size).max_of { |i| (a[i] - b[i]).abs }.should be < 1e-5
  end

  it "rejects contexts beyond max_len and non-qwen3 configs" do
    dir = tiny_dir
    begin
      m = AphroditeJax::Qwen3.load(dir, 4)
      expect_raises(ArgumentError, /exceeds/) { m.forward([1, 2, 3, 4, 5], 0) }
      expect_raises(ArgumentError, /only qwen3/) do
        AphroditeJax::Qwen3Config.new(JSON.parse(%({"model_type":"llama"})))
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end

describe AphroditeJax::Generator do
  it "generates deterministically, honours max_tokens, stops and streams" do
    dir = tiny_dir
    begin
      g = AphroditeJax::Generator.load(dir, 128)
      greedy = AphroditeJax::SamplingParams.new(temperature: 0.0, max_tokens: 12, ignore_eos: true)
      first = g.generate("hello", greedy)
      g.generate("hello", greedy).text.should eq(first.text) # also exercises prefix reuse
      first.completion_tokens.should eq(12)
      first.finish_reason.should eq("length")

      pieces = [] of String
      streamed = g.generate("hello", greedy) { |p| pieces << p }
      pieces.join.should eq(streamed.text)
      streamed.text.should eq(first.text)

      if first.text.size > 2
        stop = first.text[1, 1]
        cut = g.generate("hello", AphroditeJax::SamplingParams.new(temperature: 0.0, max_tokens: 12, stop: [stop], ignore_eos: true))
        cut.finish_reason.should eq("stop")
        cut.text.includes?(stop).should be_false
      end

      seeded = AphroditeJax::SamplingParams.new(temperature: 1.0, top_p: 0.9, max_tokens: 8, seed: 5_i64, ignore_eos: true)
      g.generate("hello", seeded).text.should eq(g.generate("hello", seeded).text)
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "samples greedily with top_k 1 and builds ChatML prompts" do
    dir = tiny_dir
    begin
      g = AphroditeJax::Generator.load(dir, 64)
      logits = Slice(Float32).new(TinyQwen3::VOCAB) { |i| i == 42 ? 5_f32 : 0_f32 }
      params = AphroditeJax::SamplingParams.new(temperature: 1.0, top_k: 1)
      g.sample(logits.dup, params, Set(Int32).new, Random.new(1)).should eq(42)
      g.chat_prompt([{"user", "hi"}]).should eq("<|im_start|>user\nhi<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end

describe AphroditeJax::Server do
  it "serves the OpenAI-compatible API" do
    dir = tiny_dir
    server = AphroditeJax::Server.new(AphroditeJax::Generator.load(dir, 256), "tiny-qwen3", requested_port: 0).start
    json = HTTP::Headers{"Content-Type" => "application/json"}
    begin
      models = JSON.parse(HTTP::Client.get("#{server.url}/v1/models").body)
      models["data"][0]["id"].should eq("tiny-qwen3")
      JSON.parse(HTTP::Client.get("#{server.url}/health").body)["status"].should eq("ok")

      req = {"messages" => [{"role" => "user", "content" => "hello"}], "max_tokens" => 6,
             "temperature" => 0, "ignore_eos" => true}
      chat = JSON.parse(HTTP::Client.post("#{server.url}/v1/chat/completions", headers: json, body: req.to_json).body)
      chat["choices"][0]["message"]["role"].should eq("assistant")
      chat["usage"]["completion_tokens"].should eq(6)
      text = chat["choices"][0]["message"]["content"].as_s

      sse = HTTP::Client.post("#{server.url}/v1/chat/completions", headers: json, body: req.merge({"stream" => true}).to_json).body
      lines = sse.split("\n").select(&.starts_with?("data: "))
      lines.last.should eq("data: [DONE]")
      deltas = lines[0..-2].map { |l| JSON.parse(l[6..])["choices"][0] }
      deltas.compact_map { |c| c["delta"]["content"]?.try(&.as_s) }.join.should eq(text)
      deltas.last["finish_reason"].should eq("length")

      comp = JSON.parse(HTTP::Client.post("#{server.url}/v1/completions", headers: json,
        body: {"prompt" => "hello", "max_tokens" => 4, "temperature" => 0, "ignore_eos" => true}.to_json).body)
      comp["choices"][0]["text"].as_s.should_not be_nil

      tok = JSON.parse(HTTP::Client.post("#{server.url}/v1/tokenize", headers: json, body: {"text" => "hello"}.to_json).body)
      detok = JSON.parse(HTTP::Client.post("#{server.url}/v1/detokenize", headers: json,
        body: {"tokens" => tok["tokens"]}.to_json).body)
      detok["text"].should eq("hello")

      HTTP::Client.post("#{server.url}/v1/chat/completions", headers: json, body: "[1]").status_code.should eq(400)
      HTTP::Client.get("#{server.url}/nope").status_code.should eq(404)
    ensure
      server.stop
      FileUtils.rm_rf(dir)
    end
  end
end

# Real-weights check against an independent reference implementation:
# set QWEN3_MODEL_DIR to a Qwen/Qwen3-0.6B snapshot to run it.
describe "AphroditeJax with Qwen3-0.6B weights" do
  if dir = ENV["QWEN3_MODEL_DIR"]?
    it "matches reference logits for <|im_start|>user\\nHello world" do
      logits = AphroditeJax::Qwen3.load(dir, 16).forward([151644, 872, 198, 9707, 1879], 0)
      top = (0...logits.size).to_a.sort_by { |i| -logits[i] }.first(5)
      top.should eq([198, 0, 4894, 11, 304])
      logits[198].should be_close(15.221, 0.01)
    end

    it "gives the same real-weight logits for a prompt batch as token by token" do
      toks = [151644, 872, 198, 9707, 1879, 0, 3555, 374, 279, 6722, 315, 9625]
      batch = AphroditeJax::Qwen3.load(dir, 16).forward(toks, 0)
      model = AphroditeJax::Qwen3.load(dir, 16)
      step = Slice(Float32).new(0)
      toks.each_with_index { |tok, i| step = model.forward([tok], i) }
      (0...step.size).max_of { |i| (step[i] - batch[i]).abs }.should be < 0.02
    end
  else
    pending "set QWEN3_MODEL_DIR to check real Qwen3-0.6B logits"
  end
end
