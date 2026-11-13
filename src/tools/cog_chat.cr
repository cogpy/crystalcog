# CogChat — a chat session on the native Crystal engine that can use
# crystalcog's components.
#
#   - Plain messages go to the model together with the CogTools schemas.
#     When the model answers with tool calls, they run against the session's
#     AtomSpace, the results go back to the model, and this repeats until it
#     replies in text.
#   - Messages starting with "/" are commands and never reach the model:
#     /help, /tools, /tool NAME {json}, /engine, /tokenize, /detokenize,
#     /reset, /system, /tools on|off, plus every CogShell command
#     (/inherit cat animal, /reason 3, /query cat, ...).
#
# The engine is either the model loaded in this process (LocalEngine) or an
# OpenAI-compatible server such as aphrodite_jax_server (RemoteEngine).

require "http/client"
require "json"
require "uri"
require "../integrations/platform/aphrodite_jax/generator"
require "./cog_tools"

module CrystalCog
  module CogChat
    alias ToolCall = AphroditeJax::ChatFormat::ToolCall
    alias SamplingParams = AphroditeJax::SamplingParams

    # `confidence` is the model's mean per-token probability for the reply
    # (0 when the engine does not report it).
    record Reply, content : String, tool_calls : Array(ToolCall), finish_reason : String, confidence : Float64 = 0.0

    abstract class Engine
      # Qwen3 reasoning mode: the model thinks in <think>...</think> before
      # answering; the reasoning is not part of the reply.
      property thinking : Bool = false

      abstract def chat(messages : Array(JSON::Any), tools : Array(JSON::Any)?, params : SamplingParams,
                        &on_text : String ->) : Reply
      abstract def tokenize(text : String) : Array(Int32)
      abstract def detokenize(ids : Array(Int32)) : String
      abstract def describe : String
    end

    # The Qwen3 model running in this process.
    class LocalEngine < Engine
      getter generator : AphroditeJax::Generator

      def initialize(@generator : AphroditeJax::Generator, @name : String = "local")
      end

      def self.load(model : String, max_len : Int32 = 2048) : LocalEngine
        new(AphroditeJax::Generator.load(AphroditeJax.resolve_model_dir(model), max_len), model)
      end

      def chat(messages : Array(JSON::Any), tools : Array(JSON::Any)?, params : SamplingParams,
               &on_text : String ->) : Reply
        prompt = @generator.chat_prompt(messages, tools, @thinking)
        return plain(prompt, params, on_text) unless tools || @thinking

        # Stream the answer: skip a reasoning block, and stop at the first
        # <tool_call>, holding back a tail that could still start one.
        text = ""
        emitted = 0
        start = @thinking ? nil : 0
        result = @generator.generate(prompt, params) do |piece|
          text += piece
          if start.nil? && (close = text.index("</think>"))
            first = close + "</think>".size
            while first < text.size && text[first].whitespace?
              first += 1
            end
            start = emitted = first
          end
          if s = start
            cut = text.index(AphroditeJax::ChatFormat::TOOL_CALL_OPEN, s) || safe_length(text)
            if cut > emitted
              on_text.call(text[emitted...cut])
              emitted = cut
            end
          end
        end
        names = tools.try(&.compact_map { |t| t["function"]?.try(&.["name"]?).try(&.as_s?) })
        content, calls = AphroditeJax::ChatFormat.parse(result.text, names)
        if calls.empty?
          answer = AphroditeJax::ChatFormat.strip_reasoning(result.text)
          if start.nil?
            on_text.call(answer) unless answer.empty? # reasoning never closed
          elsif result.text.size > emitted
            on_text.call(result.text[emitted..])
          end
          return Reply.new(answer.strip, calls, result.finish_reason, result.mean_token_probability)
        end
        Reply.new(content, calls, "tool_calls", result.mean_token_probability)
      end

      private def plain(prompt, params, on_text) : Reply
        result = @generator.generate(prompt, params) { |piece| on_text.call(piece) }
        Reply.new(result.text.strip, [] of ToolCall, result.finish_reason, result.mean_token_probability)
      end

      private def safe_length(text : String) : Int32
        open = AphroditeJax::ChatFormat::TOOL_CALL_OPEN
        (1...open.size).reverse_each { |k| return text.size - k if text.ends_with?(open[0, k]) }
        text.size
      end

      def tokenize(text : String) : Array(Int32)
        @generator.tokenizer.encode(text)
      end

      def detokenize(ids : Array(Int32)) : String
        @generator.tokenizer.decode(ids)
      end

      def describe : String
        cfg = @generator.model.config
        "#{@name}: Qwen3 in-process, #{cfg.layers} layers, hidden #{cfg.hidden}, " \
        "vocab #{@generator.tokenizer.vocab_size}, context #{@generator.model.max_len}"
      end
    end

    # An OpenAI-compatible server (aphrodite_jax_server, Aphrodite, ...).
    class RemoteEngine < Engine
      getter url : String

      def initialize(url : String, @model : String? = nil, @timeout : Time::Span = 10.minutes)
        @url = url.rstrip('/').chomp("/v1")
      end

      def chat(messages : Array(JSON::Any), tools : Array(JSON::Any)?, params : SamplingParams,
               &on_text : String ->) : Reply
        body = {
          "model"              => JSON::Any.new(model_name),
          "messages"           => JSON::Any.new(messages),
          "max_tokens"         => JSON::Any.new(params.max_tokens.to_i64),
          "temperature"        => JSON::Any.new(params.temperature),
          "top_p"              => JSON::Any.new(params.top_p),
          "top_k"              => JSON::Any.new(params.top_k.to_i64),
          "repetition_penalty" => JSON::Any.new(params.repetition_penalty),
        }
        params.seed.try { |s| body["seed"] = JSON::Any.new(s) }
        body["stop"] = JSON::Any.new(params.stop.map { |s| JSON::Any.new(s) }) unless params.stop.empty?
        body["tools"] = JSON::Any.new(tools) if tools
        body["chat_template_kwargs"] = JSON::Any.new({"enable_thinking" => JSON::Any.new(@thinking)})
        json = post("/v1/chat/completions", body.to_json)
        choice = json["choices"][0]
        message = choice["message"]
        content = message["content"]?.try(&.as_s?) || ""
        calls = message["tool_calls"]?.try(&.as_a?).try(&.map { |c|
          ToolCall.new(c["function"]["name"].as_s, AphroditeJax::ChatFormat.arguments(c["function"]["arguments"]?))
        }) || [] of ToolCall
        on_text.call(content) unless content.empty?
        Reply.new(content.strip, calls, choice["finish_reason"]?.try(&.as_s?) || "stop")
      end

      def tokenize(text : String) : Array(Int32)
        post("/v1/tokenize", {"text" => text}.to_json)["tokens"].as_a.map(&.as_i)
      end

      def detokenize(ids : Array(Int32)) : String
        post("/v1/detokenize", {"tokens" => ids}.to_json)["text"].as_s
      end

      def describe : String
        "#{model_name} at #{@url}"
      end

      def model_name : String
        @model ||= begin
          get("/v1/models")["data"][0]["id"].as_s
        rescue
          "default"
        end
      end

      private def client : HTTP::Client
        uri = URI.parse(@url)
        c = HTTP::Client.new(uri)
        c.read_timeout = @timeout
        c.connect_timeout = 10.seconds
        c
      end

      private def path(p : String) : String
        "#{URI.parse(@url).path.rstrip('/')}#{p}"
      end

      private def get(p : String) : JSON::Any
        response = client.get(path(p))
        raise "GET #{p}: HTTP #{response.status_code}" unless response.success?
        JSON.parse(response.body)
      end

      private def post(p : String, body : String) : JSON::Any
        response = client.post(path(p), headers: HTTP::Headers{"Content-Type" => "application/json"}, body: body)
        raise "POST #{p}: HTTP #{response.status_code}: #{response.body[0, 300]}" unless response.success?
        JSON.parse(response.body)
      end
    end

    DEFAULT_SYSTEM = "You are CogChat. The CrystalCog knowledge base (an AtomSpace with PLN reasoning) is your only " \
                     "memory, and you reach it only through the tools.\n" \
                     "- When the user states a fact such as \"X is a Y\", call add_inheritance to store it.\n" \
                     "- When the user asks what is known about something, call query_atoms or list_atoms before answering.\n" \
                     "- When the user asks whether something follows, call pln_reason and then list_atoms.\n" \
                     "Never claim to have stored or found something without calling a tool. After the tool results, answer briefly."

    HELP = <<-TEXT
    Commands (never sent to the model):
      /help                     this help
      /tools                    list the tools the model can call
      /tools on|off             let the model call tools, or not
      /tool NAME [JSON]         call a tool yourself, e.g. /tool add_inheritance {"child":"cat","parent":"animal"}
      /engine                   describe the engine
      /tokenize TEXT            token ids of TEXT
      /detokenize ID ...        text of token ids
      /reset                    forget the conversation (the AtomSpace stays)
      /system TEXT              replace the system prompt
      /COGSHELL-COMMAND ...     any CogShell command: /concept, /inherit, /eval, /imply,
                                /query, /list, /size, /reason, /ure, /nlp, /parse, /tv, /see, /clear
    TEXT

    # Commands shared by every chat front end. `engine` may be nil where no
    # engine is reachable (then /engine and /tokenize say so).
    def self.command(line : String, tools : CogTools, engine : Engine? = nil) : String
      line = line.lstrip.lchop('/').strip
      name, _, rest = line.partition(/\s+/)
      rest = rest.strip
      case name.downcase
      when "", "help", "?"
        HELP
      when "tools"
        "Tools the model can call:\n#{tools.help}"
      when "tool"
        tool, _, args = rest.partition(/\s+/)
        raise ArgumentError.new("usage: /tool NAME [JSON]") if tool.empty?
        tools.call(tool, args.presence || "{}")
      when "engine"
        engine.try(&.describe) || "no engine attached"
      when "tokenize"
        e = engine || raise ArgumentError.new("no engine attached")
        ids = e.tokenize(rest)
        "#{ids.size} token(s): #{ids.join(' ')}"
      when "detokenize"
        e = engine || raise ArgumentError.new("no engine attached")
        e.detokenize(rest.split(/[\s,]+/).reject(&.empty?).map(&.to_i)).inspect
      else
        out = tools.run(line)
        out.empty? ? "(ok)" : out
      end
    end

    class Session
      getter engine : Engine
      getter tools : CogTools
      getter messages = [] of JSON::Any
      property params : SamplingParams
      property tools_enabled : Bool = true
      property max_tool_rounds : Int32 = 4
      property system_prompt : String
      # Called after each tool runs: (name, arguments JSON, result).
      property on_tool : Proc(String, String, String, Nil)?

      def initialize(@engine : Engine, @tools : CogTools = CogTools.new,
                     @params : SamplingParams = SamplingParams.new(temperature: 0.6, top_p: 0.95, top_k: 20, max_tokens: 256),
                     @system_prompt : String = DEFAULT_SYSTEM)
      end

      def send(text : String) : String
        send(text) { }
      end

      # Handle one user line; streamed reply text goes to the block.
      def send(text : String, &on_text : String ->) : String
        return session_command(text) if text.lstrip.starts_with?('/')

        @messages << msg("user", text)
        rounds = 0
        loop do
          offer = @tools_enabled && rounds < @max_tool_rounds ? @tools.schemas : nil
          reply = @engine.chat(conversation, offer, @params) { |piece| on_text.call(piece) }
          if reply.tool_calls.empty? || offer.nil?
            @messages << msg("assistant", reply.content)
            return reply.content
          end
          rounds += 1
          calls = reply.tool_calls.map_with_index do |call, i|
            {call, "call_#{rounds}_#{i}"}
          end
          @messages << JSON::Any.new({
            "role"       => JSON::Any.new("assistant"),
            "content"    => JSON::Any.new(reply.content),
            "tool_calls" => JSON::Any.new(calls.map { |(call, id)|
              JSON::Any.new({"id" => JSON::Any.new(id), "type" => JSON::Any.new("function"),
                             "function" => JSON::Any.new({"name" => JSON::Any.new(call.name),
                                                          "arguments" => JSON::Any.new(call.arguments_json)})})
            }),
          })
          calls.each do |(call, id)|
            result = begin
              @tools.call(call.name, call.arguments)
            rescue ex
              "error: #{ex.message}"
            end
            @on_tool.try(&.call(call.name, call.arguments_json, result))
            @messages << JSON::Any.new({"role" => JSON::Any.new("tool"), "tool_call_id" => JSON::Any.new(id),
                                        "content" => JSON::Any.new(result)})
          end
        end
      end

      def reset
        @messages.clear
      end

      private def conversation : Array(JSON::Any)
        [msg("system", @system_prompt)] + @messages
      end

      private def msg(role : String, content : String) : JSON::Any
        JSON::Any.new({"role" => JSON::Any.new(role), "content" => JSON::Any.new(content)})
      end

      private def session_command(text : String) : String
        line = text.lstrip.lchop('/').strip
        name, _, rest = line.partition(/\s+/)
        case name.downcase
        when "reset"
          reset
          "(conversation cleared; the AtomSpace is kept)"
        when "system"
          return @system_prompt if rest.strip.empty?
          @system_prompt = rest.strip
          "(system prompt replaced)"
        when "tools"
          case rest.strip.downcase
          when "on"  then @tools_enabled = true; "(tool calling on)"
          when "off" then @tools_enabled = false; "(tool calling off)"
          else            CogChat.command(line, @tools, @engine)
          end
        else
          CogChat.command(line, @tools, @engine)
        end
      rescue ex
        "error: #{ex.message}"
      end

      # Interactive loop: read lines, stream replies, show tool activity.
      def repl(input : IO = STDIN, output : IO = STDOUT, prompt : String = "you> ")
        output.puts "CogChat on #{@engine.describe}"
        output.puts "Type /help for commands, /quit to leave."
        @on_tool ||= ->(name : String, args : String, result : String) do
          output.puts "\n  [tool] #{name}(#{args})"
          result.each_line { |l| output.puts "    #{l}" }
          output.print "cog> "
          output.flush
          nil
        end
        loop do
          output.print prompt
          output.flush
          line = input.gets || break
          line = line.strip
          next if line.empty?
          break if {"/quit", "/exit", "/q"}.includes?(line)
          if line.starts_with?('/')
            output.puts send(line)
            next
          end
          output.print "cog> "
          output.flush
          begin
            send(line) { |piece| output.print piece; output.flush }
          rescue ex
            output.print "error: #{ex.message}"
          end
          output.puts
        end
      end
    end
  end
end
