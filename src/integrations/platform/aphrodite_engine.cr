# Aphrodite engine component: launches and supervises an OpenAI-compatible
# inference backend for the Pygmalion platform and hands its endpoint to
# PygmalionAgent.
#
# Backends:
#   Aphrodite    - PygmalionAI's aphrodite-engine (`aphrodite run`), GPU
#   LlamaCpp     - llama-cpp-python's OpenAI server, GGUF models, CPU-friendly
#   AphroditeJax - native Crystal port of aphrodite-jax's small-model engine
#                  (Qwen3), the aphrodite_jax_server binary
#   External     - an already-running server; nothing is launched

require "http/client"
require "json"
require "../pygmalion_agent"
require "../../cogutil/logger"

module AphroditeEngine
  enum Backend
    Aphrodite
    LlamaCpp
    AphroditeJax
    External
  end

  class Error < Exception
  end

  class Config
    property backend : Backend
    property model : String
    property served_name : String?
    property host : String
    property port : Int32
    property python : String
    property max_model_len : Int32
    property extra_args : Array(String)
    property startup_timeout : Time::Span
    property log_path : String?
    property external_url : String?
    property chat_format : String?

    def initialize(@backend = Backend::AphroditeJax, @model = "", @served_name = nil,
                   @host = "127.0.0.1", @port = 2242, @python = "python3",
                   @max_model_len = 2048, @extra_args = [] of String,
                   @startup_timeout = 10.minutes, @log_path = nil, @external_url = nil,
                   @chat_format = nil)
    end

    # Prompt format for llama.cpp: explicit, else Metharme ("pygmalion")
    # for Pygmalion models, else the model's own template.
    def effective_chat_format : String?
      @chat_format || (name.downcase.includes?("pygmalion") ? "pygmalion" : nil)
    end

    def name : String
      @served_name || File.basename(@model).sub(/\.gguf\z/, "")
    end

    def url : String
      @external_url.try(&.rstrip('/')) || "http://#{@host}:#{@port}"
    end

    # Build from environment: APHRODITE_BACKEND (aphrodite_jax, the default
    # native Crystal engine | llama_cpp | aphrodite | external), APHRODITE_MODEL, APHRODITE_SERVED_NAME,
    # APHRODITE_PORT, APHRODITE_PYTHON, APHRODITE_URL (external),
    # APHRODITE_MAX_MODEL_LEN, APHRODITE_CHAT_FORMAT (llama.cpp).
    def self.from_env : Config
      backend = case ENV["APHRODITE_BACKEND"]?.try(&.downcase)
                when "aphrodite"     then Backend::Aphrodite
                when "aphrodite_jax" then Backend::AphroditeJax
                when "external"      then Backend::External
                when "llama_cpp"     then Backend::LlamaCpp
                else                      ENV["APHRODITE_URL"]? ? Backend::External : Backend::AphroditeJax
                end
      new(
        backend: backend,
        model: ENV["APHRODITE_MODEL"]? || "",
        served_name: ENV["APHRODITE_SERVED_NAME"]?,
        port: ENV["APHRODITE_PORT"]?.try(&.to_i?) || 2242,
        python: ENV["APHRODITE_PYTHON"]? || "python3",
        max_model_len: ENV["APHRODITE_MAX_MODEL_LEN"]?.try(&.to_i?) || 2048,
        external_url: ENV["APHRODITE_URL"]?,
        chat_format: ENV["APHRODITE_CHAT_FORMAT"]?
      )
    end
  end

  class Engine
    getter config : Config
    @process : Process?

    def initialize(@config : Config)
    end

    # Command line for the configured backend (empty for External).
    def command : Array(String)
      c = @config
      case c.backend
      when Backend::Aphrodite
        ["aphrodite", "run", c.model, "--host", c.host, "--port", c.port.to_s,
         "--served-model-name", c.name, "--max-model-len", c.max_model_len.to_s] + c.extra_args
      when Backend::LlamaCpp
        cmd = [c.python, "-m", "llama_cpp.server", "--model", c.model, "--model_alias", c.name,
               "--host", c.host, "--port", c.port.to_s, "--n_ctx", c.max_model_len.to_s]
        c.effective_chat_format.try { |f| cmd += ["--chat_format", f] } unless c.extra_args.includes?("--chat_format")
        cmd + c.extra_args
      when Backend::AphroditeJax
        [Engine.jax_server_binary, "--model", c.model, "--served-model-name", c.name,
         "--host", c.host, "--port", c.port.to_s, "--max-model-len", c.max_model_len.to_s] + c.extra_args
      else
        [] of String
      end
    end

    # The aphrodite_jax_server binary: APHRODITE_JAX_SERVER, else next to the
    # running executable, else ./bin (where `shards build` puts it), else PATH.
    def self.jax_server_binary : String
      if path = ENV["APHRODITE_JAX_SERVER"]?
        return path
      end
      candidates = [] of String
      Process.executable_path.try { |exe| candidates << File.join(File.dirname(exe), "aphrodite_jax_server") }
      candidates << File.expand_path("../../../bin/aphrodite_jax_server", __DIR__)
      candidates.find { |c| executable_file?(c) } || Process.find_executable("aphrodite_jax_server") || "aphrodite_jax_server"
    end

    # Portable across Crystal versions (File.executable? is deprecated in
    # 1.14, File::Info.executable? does not exist before it).
    private def self.executable_file?(path : String) : Bool
      info = File.info?(path)
      !info.nil? && info.file? && info.permissions.owner_execute?
    end

    def running? : Bool
      @process.try { |p| !p.terminated? } || false
    end

    # Launch the backend (unless External) and block until it serves
    # /v1/models. Raises Error if the process exits or the timeout passes.
    def start : self
      return wait_ready if @config.backend.external?
      raise Error.new("model is required for #{@config.backend}") if @config.model.empty?
      raise Error.new("port #{@config.port} is already serving") if ready?

      cmd = command
      log = @config.log_path.try { |path| File.open(path, "a") }
      CogUtil::Logger.info("Starting #{@config.backend} engine: #{cmd.join(" ")}")
      @process = Process.new(cmd[0], cmd[1..], output: log || Process::Redirect::Close,
        error: log || Process::Redirect::Close)
      wait_ready
    rescue ex : File::NotFoundError | IO::Error
      raise Error.new("failed to launch #{@config.backend}: #{ex.message}")
    end

    def wait_ready : self
      deadline = Time.instant + @config.startup_timeout
      until ready?
        if (process = @process) && process.terminated?
          raise Error.new("#{@config.backend} engine exited before becoming ready (see #{@config.log_path || "its output"})")
        end
        raise Error.new("#{@config.backend} engine not ready after #{@config.startup_timeout}") if Time.instant > deadline
        sleep 1.second
      end
      CogUtil::Logger.info("#{@config.backend} engine ready at #{@config.url} (models: #{models.join(", ")})")
      self
    end

    def ready? : Bool
      response = HTTP::Client.get("#{@config.url}/v1/models")
      response.status_code == 200
    rescue IO::Error | Socket::Error
      false
    end

    def models : Array(String)
      json = JSON.parse(HTTP::Client.get("#{@config.url}/v1/models").body)
      json["data"]?.try(&.as_a?).try(&.compact_map { |m| m["id"]?.try(&.as_s?) }) || [] of String
    rescue IO::Error | Socket::Error | JSON::ParseException
      [] of String
    end

    def stop
      return unless process = @process
      return if process.terminated?
      {% if flag?(:win32) %}
        process.terminate
      {% else %}
        process.signal(Signal::TERM)
        20.times do
          return if process.terminated?
          sleep 250.milliseconds
        end
        process.signal(Signal::KILL) unless process.terminated?
      {% end %}
    rescue RuntimeError
    ensure
      @process = nil
    end

    # A Pygmalion agent bound to this engine.
    def agent(max_tokens : Int32 = 128, timeout : Time::Span = 600.seconds) : PygmalionAgent::Agent
      model = @config.backend.external? ? (models.first? || @config.name) : @config.name
      agent = PygmalionAgent.create_agent(model, @config.url)
      agent.config.default_max_tokens = max_tokens
      agent.config.api.timeout = timeout
      agent.config.api.max_retries = 1
      agent
    end
  end
end
