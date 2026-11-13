# Native Crystal port of aphrodite-jax's small-model engine, served over the
# OpenAI-compatible API that Aphrodite exposes:
#
#   GET  /v1/models, /health, /version
#   POST /v1/chat/completions   ("stream": true -> per-token SSE)
#   POST /v1/completions
#   POST /v1/tokenize, /v1/detokenize
#
# Like aphrodite-jax it targets Qwen3 models (e.g. Qwen/Qwen3-0.6B); weights
# load from a local Hugging Face snapshot directory (config.json,
# tokenizer.json, *.safetensors). Build with -Dpreview_mt and set
# CRYSTAL_WORKERS to spread matrix rows over threads.

require "http/server"
require "json"
require "uuid"
require "./aphrodite_jax/generator"

module AphroditeJax
  VERSION = "0.1.0"

  # Resolve a model reference: a local directory, or a Hugging Face repo id
  # already present in the HF cache (HF_HOME / ~/.cache/huggingface).
  def self.resolve_model_dir(model : String) : String
    return model if Dir.exists?(model)
    hub = ENV["HF_HUB_CACHE"]? || File.join(ENV["HF_HOME"]? || File.join(ENV["HOME"]? || "/root", ".cache", "huggingface"), "hub")
    repo_dir = File.join(hub, "models--#{model.gsub('/', "--")}")
    if Dir.exists?(repo_dir)
      ref = File.join(repo_dir, "refs", "main")
      snapshot = File.exists?(ref) ? File.join(repo_dir, "snapshots", File.read(ref).strip) : nil
      snapshots = File.join(repo_dir, "snapshots")
      snapshot ||= Dir.exists?(snapshots) ? Dir.children(snapshots).sort.last?.try { |s| File.join(snapshots, s) } : nil
      return snapshot if snapshot && File.exists?(File.join(snapshot, "config.json"))
    end
    raise ArgumentError.new("model #{model.inspect} is neither a directory nor in the Hugging Face cache (#{hub}); " \
                            "download it first, e.g. with `huggingface-cli download #{model}`")
  end

  class Server
    getter port : Int32 = 0
    getter served_name : String
    @server : HTTP::Server?

    def initialize(@generator : Generator, @served_name : String, @host : String = "127.0.0.1",
                   @requested_port : Int32 = 2242, @default_max_tokens : Int32 = 256)
    end

    def url : String
      "http://#{@host}:#{@port}"
    end

    def start : self
      server = HTTP::Server.new { |ctx| handle(ctx) }
      @port = server.bind_tcp(@host, @requested_port).port
      @server = server
      spawn { server.listen }
      Fiber.yield
      self
    end

    def listen
      server = HTTP::Server.new { |ctx| handle(ctx) }
      @port = server.bind_tcp(@host, @requested_port).port
      @server = server
      server.listen
    end

    def stop
      @server.try(&.close)
    end

    def handle(ctx : HTTP::Server::Context)
      req = ctx.request
      ctx.response.content_type = "application/json"
      case {req.method, req.path}
      when {"GET", "/v1/models"}
        ctx.response.print({"object" => "list", "data" => [{"id" => @served_name, "object" => "model",
                                                            "owned_by" => "crystalcog", "max_model_len" => @generator.model.max_len}]}.to_json)
      when {"GET", "/health"}
        ctx.response.print({"status" => "ok", "model" => @served_name}.to_json)
      when {"GET", "/version"}
        ctx.response.print({"version" => VERSION}.to_json)
      when {"POST", "/v1/chat/completions"}
        chat(ctx, body(ctx))
      when {"POST", "/v1/completions"}
        completion(ctx, body(ctx))
      when {"POST", "/v1/tokenize"}
        b = body(ctx)
        text = b["text"]?.try(&.as_s?) || b["prompt"]?.try(&.as_s?) || ""
        ids = @generator.tokenizer.encode(text)
        ctx.response.print({"tokens" => ids, "count" => ids.size, "max_model_len" => @generator.model.max_len}.to_json)
      when {"POST", "/v1/detokenize"}
        ids = body(ctx)["tokens"]?.try(&.as_a?).try(&.map(&.as_i)) || [] of Int32
        ctx.response.print({"text" => @generator.tokenizer.decode(ids)}.to_json)
      else
        error(ctx, 404, "not found: #{req.method} #{req.path}")
      end
    rescue ex : JSON::ParseException | ArgumentError | TypeCastError | KeyError
      error(ctx, 400, ex.message.to_s)
    rescue ex
      STDERR.puts "aphrodite_jax_server: #{ex.class}: #{ex.message}"
      error(ctx, 500, ex.message.to_s)
    end

    private def body(ctx) : JSON::Any
      json = JSON.parse(ctx.request.body.try(&.gets_to_end).presence || "{}")
      raise ArgumentError.new("request body must be a JSON object") unless json.as_h?
      json
    end

    private def error(ctx, status, message)
      ctx.response.status_code = status
      ctx.response.print({"error" => {"message" => message, "type" => status == 400 ? "invalid_request_error" : "server_error",
                                      "code" => status}}.to_json)
    end

    private def chat(ctx, body)
      messages = body["messages"]?.try(&.as_a?) || raise ArgumentError.new("messages is required")
      tools = body["tools"]?.try(&.as_a?).try { |t| t.empty? ? nil : t }
      tools = nil if body["tool_choice"]?.try(&.as_s?) == "none"
      names = tools.try(&.compact_map { |t| (t["function"]? || t)["name"]?.try(&.as_s?) })
      thinking = body["chat_template_kwargs"]?.try(&.["enable_thinking"]?).try(&.as_bool?) || false
      prompt = @generator.chat_prompt(messages, tools, thinking)
      params = SamplingParams.from_json(body, @default_max_tokens)
      id = "chatcmpl-#{UUID.random.hexstring}"
      created = Time.utc.to_unix

      if body["stream"]?.try(&.as_bool?)
        ctx.response.content_type = "text/event-stream"
        ctx.response.headers["Cache-Control"] = "no-cache"
        send = ->(delta : Hash(String, JSON::Any), finish : String?) do
          chunk = {"id" => id, "object" => "chat.completion.chunk", "created" => created, "model" => @served_name,
                   "choices" => [{"index" => 0, "delta" => delta, "finish_reason" => finish}]}
          ctx.response.print "data: #{chunk.to_json}\n\n"
          ctx.response.flush
        end
        send.call({"role" => JSON::Any.new("assistant")}, nil)
        if tools || thinking
          # Tool calls, and the end of the reasoning block, are only known
          # once the whole reply is in.
          result = @generator.generate(prompt, params)
          content, calls = tools ? ChatFormat.parse(result.text, names) : {ChatFormat.strip_reasoning(result.text), [] of ChatFormat::ToolCall}
          send.call({"content" => JSON::Any.new(content)}, nil) unless content.empty?
          send.call({"tool_calls" => JSON.parse(tool_calls_json(calls).to_json)}, nil) unless calls.empty?
          send.call({} of String => JSON::Any, calls.empty? ? result.finish_reason : "tool_calls")
        else
          result = @generator.generate(prompt, params) { |piece| send.call({"content" => JSON::Any.new(piece)}, nil) }
          send.call({} of String => JSON::Any, result.finish_reason)
        end
        ctx.response.print "data: [DONE]\n\n"
        return
      end

      result = @generator.generate(prompt, params)
      content, calls = tools ? ChatFormat.parse(result.text, names) : {ChatFormat.strip_reasoning(result.text), [] of ChatFormat::ToolCall}
      message = if calls.empty?
                  JSON.parse({"role" => "assistant", "content" => content}.to_json)
                else
                  JSON.parse({"role" => "assistant", "content" => content.presence, "tool_calls" => tool_calls_json(calls)}.to_json)
                end
      finish = calls.empty? ? result.finish_reason : "tool_calls"
      ctx.response.print({"id" => id, "object" => "chat.completion", "created" => created, "model" => @served_name,
                          "choices" => [{"index" => 0, "finish_reason" => finish, "logprobs" => nil, "message" => message}],
                          "usage" => usage(result)}.to_json)
    end

    private def tool_calls_json(calls : Array(ChatFormat::ToolCall))
      calls.map_with_index do |call, i|
        {"index" => i, "id" => "call_#{UUID.random.hexstring[0, 24]}", "type" => "function",
         "function" => {"name" => call.name, "arguments" => call.arguments_json}}
      end
    end

    private def completion(ctx, body)
      prompt = body["prompt"]?.try { |p| p.as_s? || p.as_a?.try(&.first?).try(&.as_s?) } ||
               raise ArgumentError.new("prompt is required")
      result = @generator.generate(prompt, SamplingParams.from_json(body, @default_max_tokens))
      ctx.response.print({"id" => "cmpl-#{UUID.random.hexstring}", "object" => "text_completion",
                          "created" => Time.utc.to_unix, "model" => @served_name,
                          "choices" => [{"index" => 0, "text" => result.text, "finish_reason" => result.finish_reason}],
                          "usage" => usage(result)}.to_json)
    end

    private def usage(result : Generation)
      {"prompt_tokens" => result.prompt_tokens, "completion_tokens" => result.completion_tokens,
       "total_tokens" => result.prompt_tokens + result.completion_tokens}
    end
  end

  # Command-line entry point used by bin/aphrodite_jax_server.
  def self.main(argv = ARGV)
    model = nil
    served = nil
    host = "127.0.0.1"
    port = 2242
    max_len = 2048
    max_tokens = 256
    parser = OptionParser.new do |p|
      p.banner = "Usage: aphrodite_jax_server --model DIR|REPO_ID [options]"
      p.on("--model MODEL", "Local HF snapshot dir or cached repo id (e.g. Qwen/Qwen3-0.6B)") { |v| model = v }
      p.on("--served-model-name NAME", "Model id reported by /v1/models") { |v| served = v }
      p.on("--host HOST", "Bind address (default 127.0.0.1)") { |v| host = v }
      p.on("--port PORT", "Port (default 2242)") { |v| port = v.to_i }
      p.on("--max-model-len N", "Context length / KV cache size (default 2048)") { |v| max_len = v.to_i }
      p.on("--default-max-tokens N", "max_tokens when a request omits it (default 256)") { |v| max_tokens = v.to_i }
      p.on("-h", "--help", "Show help") { puts p; exit 0 }
    end
    parser.parse(argv)
    model_ref = model.to_s
    abort(parser.to_s) if model_ref.empty?
    served_name = served.to_s.presence || model_ref
    dir = resolve_model_dir(model_ref)
    started = Time.monotonic
    generator = Generator.load(dir, max_len)
    server = Server.new(generator, served_name, host, port, max_tokens)
    puts "aphrodite_jax_server: loaded #{model_ref} from #{dir} in #{(Time.monotonic - started).total_seconds.round(1)}s"
    {% if flag?(:preview_mt) %}
      puts "aphrodite_jax_server: multi-threaded kernels (CRYSTAL_WORKERS=#{ENV["CRYSTAL_WORKERS"]? || 4})"
    {% end %}
    puts "aphrodite_jax_server: serving http://#{host}:#{port}"
    STDOUT.flush
    server.listen
  end
end
