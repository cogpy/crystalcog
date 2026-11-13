# Pygmalion platform stack: Aphrodite engine + Paphos backend + Galatea
# frontend server, wired together inside crystalcog.
#
#   Galatea (galatea.v1 Connect API, /api/auth, web app)
#     -> Paphos (/api/v1 accounts, characters, chats, messages)
#     -> Aphrodite engine (OpenAI-compatible inference) via PygmalionAgent
#
# Environment: PAPHOS_PORT (3000), PAPHOS_DATA_FILE, GALATEA_PORT (8080),
# GALATEA_STATIC_DIR, PLATFORM_HOST (127.0.0.1), PLATFORM_MAX_TOKENS (160),
# PLATFORM_TOOLS (1/0: let the model call crystalcog tools; on by default
# for the native aphrodite_jax backend), plus the APHRODITE_* variables read
# by AphroditeEngine::Config.from_env.

require "./aphrodite_engine"
require "./paphos_server"
require "./galatea_server"

module PygmalionPlatform
  class Stack
    getter engine : AphroditeEngine::Engine
    getter paphos : PaphosBackend::Server
    getter galatea : GalateaFrontend::Server
    getter atomspace : AtomSpace::AtomSpace

    def initialize(engine_config : AphroditeEngine::Config = AphroditeEngine::Config.from_env,
                   host : String = ENV["PLATFORM_HOST"]? || "127.0.0.1",
                   paphos_port : Int32 = ENV["PAPHOS_PORT"]?.try(&.to_i?) || 3000,
                   galatea_port : Int32 = ENV["GALATEA_PORT"]?.try(&.to_i?) || 8080,
                   data_file : String? = ENV["PAPHOS_DATA_FILE"]?,
                   static_dir : String? = ENV["GALATEA_STATIC_DIR"]?,
                   max_tokens : Int32 = ENV["PLATFORM_MAX_TOKENS"]?.try(&.to_i?) || 160)
      if engine_config.model.empty? && !engine_config.backend.external?
        # No model to launch: attach to whatever already serves the port.
        engine_config.backend = AphroditeEngine::Backend::External
        engine_config.external_url ||= "http://#{engine_config.host}:#{engine_config.port}"
      end
      @engine = AphroditeEngine::Engine.new(engine_config)
      @atomspace = AtomSpace::AtomSpace.new
      @paphos = PaphosBackend::Server.new(host, paphos_port, data_file: data_file)
      engine = @engine
      factory = GalateaFrontend::Server::AgentFactory.new { engine.agent(max_tokens) }
      @galatea = GalateaFrontend::Server.new(@paphos.url_for(host, paphos_port), factory, host, galatea_port,
        static_dir: static_dir)
      @galatea.atomspace = @atomspace
      @galatea.engine = CrystalCog::CogChat::RemoteEngine.new(engine_config.url)
      @galatea.tools_enabled = case ENV["PLATFORM_TOOLS"]?
                               when "1", "true"  then true
                               when "0", "false" then false
                               else                   engine_config.backend.aphrodite_jax?
                               end
    end

    # Start the engine (waiting until it serves), then Paphos, then Galatea.
    def start : self
      @engine.start
      @paphos.start
      @galatea.paphos_url = @paphos.url
      @galatea.start
      self
    end

    def stop
      @galatea.stop
      @paphos.stop
      @engine.stop
    end

    def status : Hash(String, String)
      {"engine" => @engine.config.url, "engine_backend" => @engine.config.backend.to_s,
       "engine_models" => @engine.models.join(", "), "paphos" => @paphos.url,
       "galatea" => @galatea.url, "atoms" => @atomspace.size.to_s,
       "model_tools" => @galatea.tools_enabled ? "on" : "off"}
    end
  end
end
