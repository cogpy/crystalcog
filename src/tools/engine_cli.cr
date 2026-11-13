# Command-line front ends for the native Crystal engine and the CogTools.
#
#   crystalcog chat        [engine] [sampling] [--no-tools] [--system TEXT] [--atomspace FILE] [-e MSG]...
#   crystalcog generate    [engine] [sampling] [--chat] PROMPT...      (stdin when PROMPT is omitted)
#   crystalcog tokenize    [engine] TEXT...
#   crystalcog detokenize  [engine] ID...
#   crystalcog cog         [--atomspace FILE] COGSHELL-COMMAND...
#   crystalcog tool        [--atomspace FILE] NAME [JSON]
#   crystalcog tools       [--json]
#   crystalcog engine      serve --model M [aphrodite_jax_server options]
#
# engine:   --model DIR|REPO_ID  (load in-process; or CRYSTALCOG_MODEL / APHRODITE_MODEL)
#           --url URL            (use a running OpenAI-compatible server; or APHRODITE_URL)
#           --max-model-len N
# sampling: --max-tokens N --temperature T --top-p P --top-k K --seed S --think

require "option_parser"
require "./cog_chat"
require "../integrations/platform/aphrodite_jax_server"

module CrystalCog
  module EngineCLI
    COMMANDS = %w(chat generate tokenize detokenize cog tool tools engine)

    class Options
      property model : String? = ENV["CRYSTALCOG_MODEL"]?.presence || ENV["APHRODITE_MODEL"]?.presence
      property url : String? = ENV["APHRODITE_URL"]?.presence
      property max_len : Int32 = 2048
      property params = AphroditeJax::SamplingParams.new(temperature: 0.6, top_p: 0.95, top_k: 20, max_tokens: 256)
      property tools = true
      property system : String? = nil
      property atomspace_file : String? = nil
      property messages = [] of String
      property chat = false
      property think = false
      property json = false
      property rest = [] of String
    end

    def self.command?(name : String?) : Bool
      COMMANDS.includes?(name)
    end

    def self.run(command : String, args : Array(String), output : IO = STDOUT) : Int32
      CogUtil::Logger.set_level(CogUtil::LogLevel::WARN) unless ENV["CRYSTALCOG_LOG_LEVEL"]?
      if command == "engine"
        return engine(args, output)
      end
      opts = parse(command, args)
      case command
      when "chat"       then chat(opts, output)
      when "generate"   then generate(opts, output)
      when "tokenize"   then output.puts engine_for(opts).tokenize(opts.rest.join(' ')).join(' ')
      when "detokenize" then output.puts engine_for(opts).detokenize(opts.rest.flat_map(&.split(',')).reject(&.empty?).map(&.to_i))
      when "cog"        then with_tools(opts) { |t| output.puts CogChat.command(opts.rest.join(' '), t) }
      when "tool"
        name = opts.rest.first? || raise ArgumentError.new("usage: crystalcog tool NAME [JSON]")
        with_tools(opts) { |t| output.puts t.call(name, opts.rest[1..].join(' ').presence || "{}") }
      when "tools"
        t = CogTools.new
        output.puts(opts.json ? t.schemas.to_pretty_json : "Tools:\n#{t.help}")
      end
      0
    end

    def self.parse(command : String, args : Array(String)) : Options
      opts = Options.new
      parser = OptionParser.new do |p|
        p.banner = "Usage: crystalcog #{command} [options]#{command == "cog" ? " COMMAND..." : ""}"
        unless {"cog", "tool", "tools"}.includes?(command)
          p.on("--model MODEL", "Model to load in-process (HF snapshot dir or cached repo id)") { |v| opts.model = v }
          p.on("--url URL", "OpenAI-compatible engine to use instead of loading a model") { |v| opts.url = v }
          p.on("--max-model-len N", "Context length when loading in-process (default 2048)") { |v| opts.max_len = v.to_i }
          p.on("--max-tokens N", "Tokens to generate per reply (default 256)") { |v| opts.params.max_tokens = v.to_i }
          p.on("--temperature T", "Sampling temperature (default 0.6; 0 = greedy)") { |v| opts.params.temperature = v.to_f }
          p.on("--top-p P", "Nucleus sampling (default 0.95)") { |v| opts.params.top_p = v.to_f }
          p.on("--top-k K", "Top-k sampling (default 20)") { |v| opts.params.top_k = v.to_i }
          p.on("--seed S", "Random seed") { |v| opts.params.seed = v.to_i64 }
          p.on("--think", "Let Qwen3 reason (<think>) before answering; the reasoning is not shown") { opts.think = true }
        end
        if command == "chat"
          p.on("--no-tools", "Do not let the model call crystalcog tools") { opts.tools = false }
          p.on("--system TEXT", "System prompt") { |v| opts.system = v }
          p.on("-e MSG", "--message MSG", "Send MSG (repeatable) and exit instead of starting the REPL") { |v| opts.messages << v }
        end
        if command == "generate"
          p.on("--chat", "Wrap PROMPT as a user message in the chat format") { opts.chat = true }
        end
        if {"chat", "cog", "tool"}.includes?(command)
          p.on("--atomspace FILE", "Load the AtomSpace from FILE and save it back afterwards") { |v| opts.atomspace_file = v }
        end
        p.on("--json", "Print tool schemas as JSON") { opts.json = true } if command == "tools"
        p.on("-h", "--help", "Show help") { puts p; exit 0 }
        p.unknown_args { |before, after| opts.rest = before + after }
      end
      parser.parse(args.dup)
      opts
    end

    def self.engine_for(opts : Options) : CogChat::Engine
      engine = if url = opts.url
                 CogChat::RemoteEngine.new(url)
               elsif model = opts.model
                 CogChat::LocalEngine.load(model, opts.max_len)
               else
                 raise ArgumentError.new("no engine: pass --model DIR|REPO_ID (or set CRYSTALCOG_MODEL) or --url URL (or APHRODITE_URL)")
               end
      engine.thinking = opts.think
      engine
    end

    # Run the block with tools over an AtomSpace that is loaded from, and
    # saved back to, --atomspace FILE when given.
    def self.with_tools(opts : Options, &)
      atomspace = AtomSpace::AtomSpace.new
      storage = opts.atomspace_file.try do |file|
        s = AtomSpace::FileStorageNode.new("cli", file)
        raise "cannot open AtomSpace file #{file}" unless s.open
        atomspace.load_from(s) if File.size(file) > 0
        s
      end
      begin
        yield CogTools.new(atomspace)
      ensure
        if s = storage
          raise "cannot save AtomSpace to #{opts.atomspace_file}" unless atomspace.store_to(s)
          s.close
        end
      end
    end

    def self.chat(opts : Options, output : IO)
      engine = engine_for(opts)
      with_tools(opts) do |tools|
        session = CogChat::Session.new(engine, tools, opts.params)
        session.tools_enabled = opts.tools
        opts.system.try { |s| session.system_prompt = s }
        if opts.messages.empty?
          session.repl(STDIN, output)
        else
          session.on_tool = ->(name : String, args : String, result : String) do
            output.puts "[tool] #{name}(#{args})"
            result.each_line { |l| output.puts "  #{l}" }
            nil
          end
          opts.messages.each do |m|
            output.puts "you> #{m}"
            if m.lstrip.starts_with?('/')
              output.puts session.send(m)
            else
              output.print "cog> "
              session.send(m) { |piece| output.print piece; output.flush }
              output.puts
            end
          end
        end
      end
    end

    def self.generate(opts : Options, output : IO)
      prompt = opts.rest.join(' ')
      prompt = STDIN.gets_to_end if prompt.empty?
      raise ArgumentError.new("empty prompt") if prompt.strip.empty?
      engine = engine_for(opts)
      case engine
      when CogChat::LocalEngine
        gen = engine.generator
        if opts.chat
          msgs = [JSON::Any.new({"role" => JSON::Any.new("user"), "content" => JSON::Any.new(prompt)})]
          engine.chat(msgs, nil, opts.params) { |piece| output.print piece; output.flush }
        else
          gen.generate(prompt, opts.params) { |piece| output.print piece; output.flush }
        end
      else
        messages = [JSON::Any.new({"role" => JSON::Any.new("user"), "content" => JSON::Any.new(prompt)})]
        engine.chat(messages, nil, opts.params) { |piece| output.print piece; output.flush }
      end
      output.puts
    end

    def self.engine(args : Array(String), output : IO) : Int32
      sub = args.first?
      case sub
      when "serve"
        AphroditeJax.main(args[1..])
      when "info"
        opts = parse("engine", args[1..])
        output.puts engine_for(opts).describe
      else
        output.puts "Usage: crystalcog engine serve --model DIR|REPO_ID [--port N] [--host H] [--max-model-len N]"
        output.puts "       crystalcog engine info  --model DIR|REPO_ID | --url URL"
        return sub.nil? ? 0 : 1
      end
      0
    end
  end
end
