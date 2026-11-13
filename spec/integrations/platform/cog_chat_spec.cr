require "spec"
require "file_utils"
require "../../../src/tools/engine_cli"
require "./support/tiny_qwen3"

alias CogChat = CrystalCog::CogChat

# Replays scripted replies and records what it was asked.
class ScriptedEngine < CogChat::Engine
  getter calls = [] of {Array(JSON::Any), Array(JSON::Any)?}

  def initialize(@replies : Array(CogChat::Reply))
  end

  def chat(messages : Array(JSON::Any), tools : Array(JSON::Any)?, params : CogChat::SamplingParams,
           &on_text : String ->) : CogChat::Reply
    @calls << {messages.dup, tools}
    reply = @replies.shift? || CogChat::Reply.new("(no more replies)", [] of CogChat::ToolCall, "stop")
    on_text.call(reply.content) unless reply.content.empty?
    reply
  end

  def tokenize(text : String) : Array(Int32)
    text.bytes.map(&.to_i32)
  end

  def detokenize(ids : Array(Int32)) : String
    String.new(Bytes.new(ids.size) { |i| ids[i].to_u8 })
  end

  def describe : String
    "scripted"
  end
end

private def text(s : String) : CogChat::Reply
  CogChat::Reply.new(s, [] of CogChat::ToolCall, "stop")
end

private def call(name : String, args : String) : CogChat::Reply
  CogChat::Reply.new("", [CogChat::ToolCall.new(name, JSON.parse(args))], "tool_calls")
end

describe AphroditeJax::ChatFormat do
  tools = [JSON.parse(%({"type": "function", "function": {"name": "query_atoms", "description": "Look up é",
    "parameters": {"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name"]}}}))]

  it "writes Qwen3's tool prompt exactly as the model's chat template does" do
    messages = JSON.parse(%([{"role": "system", "content": "S"}, {"role": "user", "content": "héllo"},
      {"role": "assistant", "content": "", "tool_calls": [{"id": "c1", "type": "function",
        "function": {"name": "query_atoms", "arguments": "{\\"name\\": \\"cat\\", \\"n\\": [1,2]}"}}]},
      {"role": "tool", "tool_call_id": "c1", "content": "r1"}, {"role": "tool", "content": "r2"},
      {"role": "assistant", "content": "done"}, {"role": "user", "content": "again"}])).as_a
    # Rendered with the Jinja chat template from Qwen/Qwen3-0.6B's tokenizer_config.json.
    expected = "<|im_start|>system\nS\n\n# Tools\n\nYou may call one or more functions to assist with the user query.\n\n" \
               "You are provided with function signatures within <tools></tools> XML tags:\n<tools>\n" \
               "{\"type\": \"function\", \"function\": {\"name\": \"query_atoms\", \"description\": \"Look up é\", " \
               "\"parameters\": {\"type\": \"object\", \"properties\": {\"name\": {\"type\": \"string\"}}, \"required\": [\"name\"]}}}\n" \
               "</tools>\n\nFor each function call, return a json object with function name and arguments within " \
               "<tool_call></tool_call> XML tags:\n<tool_call>\n{\"name\": <function-name>, \"arguments\": <args-json-object>}\n" \
               "</tool_call><|im_end|>\n<|im_start|>user\nhéllo<|im_end|>\n<|im_start|>assistant\n<tool_call>\n" \
               "{\"name\": \"query_atoms\", \"arguments\": {\"name\": \"cat\", \"n\": [1, 2]}}\n</tool_call><|im_end|>\n" \
               "<|im_start|>user\n<tool_response>\nr1\n</tool_response>\n<tool_response>\nr2\n</tool_response><|im_end|>\n" \
               "<|im_start|>assistant\ndone<|im_end|>\n<|im_start|>user\nagain<|im_end|>\n" \
               "<|im_start|>assistant\n<think>\n\n</think>\n\n"
    AphroditeJax::ChatFormat.prompt(messages, tools).should eq(expected)
  end

  it "renders plain chats as before when no tools are given" do
    msgs = [JSON.parse(%({"role": "user", "content": "hi"}))]
    AphroditeJax::ChatFormat.prompt(msgs).should eq("<|im_start|>user\nhi<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
  end

  it "parses tool calls out of generated text" do
    content, calls = AphroditeJax::ChatFormat.parse(
      %(Sure.\n<tool_call>\n{"name": "add_inheritance", "arguments": {"child": "cat", "parent": "animal"}}\n</tool_call>\n) +
      %(<tool_call>{"name": "pln_reason", "arguments": "{\\"steps\\": 2}"}</tool_call><tool_call>not json</tool_call>))
    calls.map(&.name).should eq(["add_inheritance", "pln_reason"])
    calls[0].arguments["parent"].should eq("animal")
    calls[1].arguments["steps"].should eq(2)
    content.should eq("Sure.\n\n<tool_call>not json")
  end
end

describe CrystalCog::CogTools do
  it "describes each tool with a JSON schema" do
    tools = CrystalCog::CogTools.new
    schema = tools["add_inheritance"].schema
    schema["function"]["parameters"]["required"].as_a.map(&.as_s).should eq(["child", "parent"])
    tools.names.should contain("pln_reason")
    tools.help.should contain("add_inheritance <child> <parent> [strength] [confidence]")
  end

  it "runs tools against one AtomSpace and reasons over what they added" do
    tools = CrystalCog::CogTools.new
    tools.call("add_inheritance", %({"child": "cat", "parent": "mammal"})).should contain(%(CONCEPTNODE "cat"))
    tools.call("add_inheritance", JSON.parse(%({"child": "mammal", "parent": "animal", "strength": 0.9})))
    tools.call("add_evaluation", %({"predicate": "likes", "arguments": ["alice", "green tea"]})).should contain(%(CONCEPTNODE "green tea"))
    tools.call("pln_reason", %({"steps": 2})).should contain("PLN generated")
    tools.call("list_atoms", %({"type": "inheritance"})).should contain(%((INHERITANCELINK (CONCEPTNODE "cat") (CONCEPTNODE "animal"))))
    tools.call("atomspace_stats").should contain("AtomSpace size=")
  end

  it "rejects unknown tools and missing arguments" do
    tools = CrystalCog::CogTools.new
    expect_raises(ArgumentError, /unknown tool/) { tools.call("nope") }
    expect_raises(ArgumentError, /missing argument "parent"/) { tools.call("add_inheritance", %({"child": "cat"})) }
    expect_raises(ArgumentError, /not JSON/) { tools.call("query_atoms", "{oops") }
  end
end

describe CogChat::Session do
  it "runs the model's tool calls, feeds back the results and returns its answer" do
    engine = ScriptedEngine.new([call("add_inheritance", %({"child": "cat", "parent": "animal"})), text("Noted: cats are animals.")])
    session = CogChat::Session.new(engine)
    seen = [] of String
    session.on_tool = ->(name : String, args : String, result : String) { seen << "#{name} #{args} -> #{result}"; nil }
    streamed = String::Builder.new
    session.send("Cats are animals.") { |piece| streamed << piece }.should eq("Noted: cats are animals.")
    streamed.to_s.should eq("Noted: cats are animals.")

    seen.size.should eq(1)
    seen[0].should start_with(%q[add_inheritance {"child":"cat","parent":"animal"} -> => (INHERITANCELINK])
    session.tools.atomspace.get_nodes_by_name("cat").size.should eq(1)

    engine.calls.size.should eq(2)
    engine.calls[0][1].not_nil!.map(&.["function"]["name"].as_s).should contain("add_inheritance")
    second = engine.calls[1][0]
    second.map(&.["role"].as_s).should eq(["system", "user", "assistant", "tool"])
    second[2]["tool_calls"][0]["function"]["name"].should eq("add_inheritance")
    second[3]["content"].as_s.should contain("INHERITANCELINK")
    session.messages.last["content"].should eq("Noted: cats are animals.")
  end

  it "reports tool errors to the model and stops offering tools after max rounds" do
    engine = ScriptedEngine.new([call("nope", "{}"), call("query_atoms", %({"name": "x"})), text("done")])
    session = CogChat::Session.new(engine)
    session.max_tool_rounds = 1
    session.send("go").should eq("")
    engine.calls[1][0].last["content"].as_s.should start_with("error: unknown tool")
    engine.calls[1][1].should be_nil
  end

  it "handles /commands without calling the model" do
    engine = ScriptedEngine.new([text("hi")])
    session = CogChat::Session.new(engine)
    session.send("/inherit cat animal").should contain("INHERITANCELINK")
    session.send("/query cat").should contain(%(CONCEPTNODE "cat"))
    session.send(%(/tool query_atoms {"name": "animal"})).should contain(%(CONCEPTNODE "animal"))
    session.send("/tokenize hi").should eq("2 token(s): 104 105")
    session.send("/detokenize 104 105").should eq(%("hi"))
    session.send("/engine").should eq("scripted")
    session.send("/tools").should contain("pln_reason")
    session.send("/help").should contain("/tool NAME [JSON]")
    session.send("/tool").should start_with("error: usage")
    engine.calls.should be_empty

    session.send("/tools off").should eq("(tool calling off)")
    session.send("hello").should eq("hi")
    engine.calls[0][1].should be_nil
    session.send("/system Be terse.").should eq("(system prompt replaced)")
    session.send("/reset")
    session.messages.should be_empty
  end

  it "drives a REPL" do
    engine = ScriptedEngine.new([call("add_inheritance", %({"child": "a", "parent": "b"})), text("ok")])
    session = CogChat::Session.new(engine)
    io = IO::Memory.new
    session.repl(IO::Memory.new("/size\nA is a B\n/quit\nnever\n"), io)
    io.to_s.should contain("AtomSpace size=0")
    io.to_s.should contain("[tool] add_inheritance")
    io.to_s.should contain("cog> ok")
    engine.calls.size.should eq(2)
  end
end

describe "CogChat engines on the native Qwen3 engine" do
  it "chats in-process and through the OpenAI-compatible server" do
    dir = TinyQwen3.write(File.tempname("tiny-qwen3"))
    begin
      params = CogChat::SamplingParams.new(temperature: 0.0, max_tokens: 6)
      msgs = [JSON.parse(%({"role": "user", "content": "hello"}))]
      local = CogChat::LocalEngine.load(dir, 2048)
      streamed = String::Builder.new
      reply = local.chat(msgs, CrystalCog::CogTools.new.schemas[0, 1], params) { |p| streamed << p }
      reply.tool_calls.should be_empty
      streamed.to_s.strip.should eq(reply.content)
      local.tokenize("hello").should eq([256, 257, 111])
      local.describe.should contain("2 layers")

      server = AphroditeJax::Server.new(AphroditeJax::Generator.load(dir, 64), "tiny", requested_port: 0).start
      begin
        remote = CogChat::RemoteEngine.new("#{server.url}/v1")
        remote.model_name.should eq("tiny")
        remote.chat(msgs, nil, params) { }.content.should eq(local.chat(msgs, nil, params) { }.content)
        remote.tokenize("hello").should eq([256, 257, 111])
        remote.detokenize([256, 257, 111]).should eq("hello")
      ensure
        server.stop
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end

describe CrystalCog::EngineCLI do
  it "runs cog and tool commands, keeping the AtomSpace in a file between runs" do
    file = File.tempname("cli-atomspace", ".json")
    begin
      io = IO::Memory.new
      CrystalCog::EngineCLI.run("cog", ["--atomspace", file, "inherit", "cat", "mammal"], io)
      CrystalCog::EngineCLI.run("tool", ["--atomspace", file, "add_inheritance", %({"child": "mammal", "parent": "animal"})], io)
      io = IO::Memory.new
      CrystalCog::EngineCLI.run("cog", ["--atomspace", file, "list", "inheritance"], io)
      io.to_s.should contain("2 atom(s)")
      io.to_s.should contain(%((INHERITANCELINK (CONCEPTNODE "mammal") (CONCEPTNODE "animal"))))
    ensure
      File.delete?(file)
    end
  end

  it "lists the tools as JSON and runs tokenize, generate and chat on a model" do
    io = IO::Memory.new
    CrystalCog::EngineCLI.run("tools", ["--json"], io)
    JSON.parse(io.to_s).as_a.map(&.["function"]["name"].as_s).should contain("pln_reason")

    dir = TinyQwen3.write(File.tempname("tiny-qwen3"))
    begin
      io = IO::Memory.new
      CrystalCog::EngineCLI.run("tokenize", ["--model", dir, "hello"], io)
      io.to_s.should eq("256 257 111\n")
      io = IO::Memory.new
      CrystalCog::EngineCLI.run("detokenize", ["--model", dir, "256,257", "111"], io)
      io.to_s.should eq("hello\n")
      io = IO::Memory.new
      CrystalCog::EngineCLI.run("generate", ["--model", dir, "--max-tokens", "4", "--temperature", "0", "hello"], io)
      io.to_s.should_not be_empty
      io = IO::Memory.new
      CrystalCog::EngineCLI.run("chat", ["--model", dir, "--max-tokens", "4", "--no-tools", "-e", "/inherit a b", "-e", "hi"], io)
      io.to_s.should contain("you> /inherit a b\n=> (INHERITANCELINK")
      io.to_s.should contain("you> hi\ncog> ")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "explains how to choose an engine" do
    opts = CrystalCog::EngineCLI.parse("chat", [] of String)
    opts.model = nil
    opts.url = nil
    expect_raises(ArgumentError, /--model/) { CrystalCog::EngineCLI.engine_for(opts) }
    CrystalCog::EngineCLI.parse("generate", ["--seed", "3", "--top-k", "5", "a", "b"]).tap do |o|
      o.params.seed.should eq(3)
      o.params.top_k.should eq(5)
      o.rest.should eq(["a", "b"])
    end
  end
end

describe "Qwen3 thinking mode and lenient tool calls" do
  it "opens the assistant turn for reasoning and strips it from replies" do
    msgs = [JSON.parse(%({"role": "user", "content": "hi"})),
            JSON.parse(%({"role": "assistant", "content": "<think>\\nhmm\\n</think>\\n\\nhello"})),
            JSON.parse(%({"role": "user", "content": "again"}))]
    AphroditeJax::ChatFormat.prompt(msgs, thinking: true).should eq(
      "<|im_start|>user\nhi<|im_end|>\n<|im_start|>assistant\nhello<|im_end|>\n<|im_start|>user\nagain<|im_end|>\n<|im_start|>assistant\n")
    AphroditeJax::ChatFormat.strip_reasoning("<think>\nplan\n</think>\n\nAnswer").should eq("Answer")
    content, calls = AphroditeJax::ChatFormat.parse(%(<think>x</think>\n<tool_call>{"name": "a", "arguments": {}}</tool_call>))
    {content, calls.map(&.name)}.should eq({"", ["a"]})
  end

  it "accepts XML-style calls only for known tool names" do
    content, calls = AphroditeJax::ChatFormat.parse(%(Let me check. <query_atoms name="cat"/>), ["query_atoms"])
    content.should eq("Let me check.")
    calls.map { |c| {c.name, c.arguments_json} }.should eq([{"query_atoms", %({"name":"cat"})}])
    AphroditeJax::ChatFormat.parse(%(<b>bold</b>), ["query_atoms"])[1].should be_empty
    AphroditeJax::ChatFormat.parse(%(<query_atoms name="cat"/>))[1].should be_empty
  end

  it "sends enable_thinking to remote engines" do
    received = [] of JSON::Any
    server = HTTP::Server.new do |ctx|
      received << JSON.parse(ctx.request.body.not_nil!.gets_to_end)
      ctx.response.print({"choices" => [{"finish_reason" => "stop", "message" => {"role" => "assistant", "content" => "ok"}}]}.to_json)
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    Fiber.yield
    begin
      engine = CogChat::RemoteEngine.new("http://127.0.0.1:#{address.port}", "m")
      engine.thinking = true
      engine.chat([JSON.parse(%({"role": "user", "content": "hi"}))], nil, CogChat::SamplingParams.new) { }.content.should eq("ok")
      received[0]["chat_template_kwargs"]["enable_thinking"].should eq(true)
    ensure
      server.close
    end
  end
end
