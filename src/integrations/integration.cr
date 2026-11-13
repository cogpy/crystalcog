# Integration Module - Unified integration interface for CrystalCog
#
# This module provides a unified interface for all integration components:
#
# Phase 5 Integrations:
# - CogPy/PyG Framework Integration
# - Pygmalion AI System
# - Galatea Frontend (github.com/9cog/galatea-frontend)
# - Paphos Backend (github.com/9cog/paphos-backend)
# - Crystal Acceleration Engine
# - Unified Cognitive Agency Controller
#
# Phase 6 Extended Integrations:
# - Neo4j Graph Database Integration
# - IPFS Decentralized Storage Integration
# - MeTTa Hypergraph Rewriting Language
# - TypeScript SDK for Web Bindings

require "./cogpy_bridge"
require "./pyg_adapter"
require "./pygmalion_agent"
require "./galatea_frontend"
require "./paphos_connector"
require "./crystal_accelerator"
require "./cognitive_agency"
require "./neo4j_integration"
require "./ipfs_integration"
require "./metta_integration"
require "./typescript_sdk"
require "../cogutil/logger"
require "../atomspace/atomspace"

module CrystalCogIntegration
  VERSION = "0.3.0"

  # External repository references
  EXTERNAL_REPOS = {
    "galatea" => "https://github.com/9cog/galatea-frontend",
    "paphos"  => "https://github.com/9cog/paphos-backend",
  }

  # Main integration manager with cognitive agency coordination
  class Manager
    # Phase 5 Integrations
    property cogpy_bridge : CogPyBridge::Bridge?
    property pyg_adapter : PygAdapter::Adapter?
    property pygmalion_agent : PygmalionAgent::Agent?
    property galatea_frontend : GalateaFrontend::Interface?
    property paphos_connector : PaphosBackend::Connector?
    property crystal_accelerator : CrystalAccelerator::Engine?
    property cognitive_agency : CognitiveAgency::UnifiedAgencyController?

    # Phase 6 Extended Integrations
    property neo4j_integration : CrystalCog::Integrations::Neo4jIntegration?
    property ipfs_integration : CrystalCog::Integrations::IPFSIntegration?
    property metta_integration : CrystalCog::Integrations::MeTTaIntegration?
    property typescript_sdk : CrystalCog::Integrations::TypeScriptSDKIntegration?

    property atomspace : AtomSpace::AtomSpace?
    property initialized : Bool

    def initialize
      # Phase 5
      @cogpy_bridge = nil
      @pyg_adapter = nil
      @pygmalion_agent = nil
      @galatea_frontend = nil
      @paphos_connector = nil
      @crystal_accelerator = nil
      @cognitive_agency = nil

      # Phase 6
      @neo4j_integration = nil
      @ipfs_integration = nil
      @metta_integration = nil
      @typescript_sdk = nil

      @atomspace = nil
      @initialized = false
    end

    # Initialize all integration components with cognitive agency coordination
    def initialize_all_integrations(atomspace : AtomSpace::AtomSpace)
      CogUtil::Logger.info("Initializing all CrystalCog integrations with cognitive agency")

      @atomspace = atomspace

      # Initialize unified cognitive agency controller first (central coordinator)
      @cognitive_agency = CognitiveAgency.create_optimal_controller
      @cognitive_agency.not_nil!.attach_atomspace(atomspace)
      CogUtil::Logger.info("Unified cognitive agency controller initialized")

      # Initialize CogPy bridge
      @cogpy_bridge = CogPyBridge.create_default_bridge
      @cogpy_bridge.not_nil!.attach_atomspace(atomspace)
      @cogpy_bridge.not_nil!.connect
      link_to_agency("cogpy")

      # Initialize PyG adapter
      @pyg_adapter = PygAdapter.create_default_adapter
      @pyg_adapter.not_nil!.attach_atomspace(atomspace)
      @pyg_adapter.not_nil!.initialize_backend
      link_to_agency("pyg")

      # Initialize Pygmalion agent
      @pygmalion_agent = PygmalionAgent.create_default_agent
      @pygmalion_agent.not_nil!.attach_atomspace(atomspace)
      @pygmalion_agent.not_nil!.initialize_agent
      link_to_agency("pygmalion")

      # Initialize Galatea frontend with optimal cognitive grip
      @galatea_frontend = GalateaFrontend.create_optimal_grip_interface
      @galatea_frontend.not_nil!.attach_atomspace(atomspace)
      @galatea_frontend.not_nil!.initialize_interface
      @galatea_frontend.not_nil!.start
      link_to_agency("galatea")
      CogUtil::Logger.info("Galatea frontend initialized (#{GalateaFrontend::EXTERNAL_REPO})")

      # Initialize Paphos connector with optimal grip coordination
      @paphos_connector = PaphosBackend.create_optimal_grip_connector
      @paphos_connector.not_nil!.attach_atomspace(atomspace)
      @paphos_connector.not_nil!.initialize_connection
      link_to_agency("paphos")
      CogUtil::Logger.info("Paphos backend initialized (#{PaphosBackend::EXTERNAL_REPO})")

      # Initialize Crystal accelerator
      @crystal_accelerator = CrystalAccelerator.create_high_performance_engine
      @crystal_accelerator.not_nil!.attach_atomspace(atomspace)
      @crystal_accelerator.not_nil!.initialize_engine
      link_to_agency("accelerator")

      @initialized = true
      CogUtil::Logger.info("All integrations initialized successfully with cognitive agency coordination")
    end

    # Initialize only specific integrations
    def initialize_integration(
      integration_name : String,
      atomspace : AtomSpace::AtomSpace,
      config : Hash(String, String)? = nil
    )
      @atomspace = atomspace

      # Ensure cognitive agency is initialized
      unless @cognitive_agency
        @cognitive_agency = CognitiveAgency.create_controller
        @cognitive_agency.not_nil!.attach_atomspace(atomspace)
      end

      case integration_name
      when "cogpy"
        @cogpy_bridge = CogPyBridge.create_default_bridge
        @cogpy_bridge.not_nil!.attach_atomspace(atomspace)
        @cogpy_bridge.not_nil!.connect
        link_to_agency("cogpy")
      when "pyg"
        @pyg_adapter = PygAdapter.create_default_adapter
        @pyg_adapter.not_nil!.attach_atomspace(atomspace)
        @pyg_adapter.not_nil!.initialize_backend
        link_to_agency("pyg")
      when "pygmalion"
        @pygmalion_agent = PygmalionAgent.create_default_agent
        @pygmalion_agent.not_nil!.attach_atomspace(atomspace)
        @pygmalion_agent.not_nil!.initialize_agent
        link_to_agency("pygmalion")
      when "galatea"
        grip_strength = config.try(&.["grip_strength"]?.try(&.to_i)) || 8
        mode = config.try(&.["mode"]) || "autonomous"
        mode_sym = case mode
                   when "passive"    then :passive
                   when "active"     then :active
                   when "autonomous" then :autonomous
                   else                   :active
                   end

        @galatea_frontend = GalateaFrontend.create_cognitive_agency_interface(
          grip_strength: grip_strength,
          mode: mode_sym
        )
        @galatea_frontend.not_nil!.attach_atomspace(atomspace)
        @galatea_frontend.not_nil!.initialize_interface
        @galatea_frontend.not_nil!.start
        link_to_agency("galatea")
      when "paphos"
        coordination_mode = config.try(&.["coordination_mode"]) || "peer"
        mode_sym = case coordination_mode
                   when "leader"   then :leader
                   when "follower" then :follower
                   when "peer"     then :peer
                   else                 :peer
                   end

        @paphos_connector = PaphosBackend.create_cognitive_agency_connector(
          coordination_mode: mode_sym
        )
        @paphos_connector.not_nil!.attach_atomspace(atomspace)
        @paphos_connector.not_nil!.initialize_connection
        link_to_agency("paphos")
      when "accelerator"
        @crystal_accelerator = CrystalAccelerator.create_high_performance_engine
        @crystal_accelerator.not_nil!.attach_atomspace(atomspace)
        @crystal_accelerator.not_nil!.initialize_engine
        link_to_agency("accelerator")
      when "cognitive_agency"
        # Already initialized above
        CogUtil::Logger.info("Cognitive agency controller ready")
        # Phase 6 Extended Integrations
      when "neo4j"
        host = config.try(&.["host"]) || "localhost"
        port = (config.try(&.["port"]) || "7474").to_i
        username = config.try(&.["username"]) || "neo4j"
        password = config.try(&.["password"]) || "password"

        @neo4j_integration = CrystalCog::Neo4j.create_integration(host, port, username, password)
        @neo4j_integration.not_nil!.attach_atomspace(atomspace)
        @neo4j_integration.not_nil!.initialize_backend
        link_to_agency("neo4j")
        CogUtil::Logger.info("Neo4j integration initialized")
      when "ipfs"
        host = config.try(&.["host"]) || "localhost"
        port = (config.try(&.["port"]) || "5001").to_i

        @ipfs_integration = CrystalCog::IPFS.create_integration(host, port)
        @ipfs_integration.not_nil!.attach_atomspace(atomspace)
        @ipfs_integration.not_nil!.initialize_backend
        link_to_agency("ipfs")
        CogUtil::Logger.info("IPFS integration initialized")
      when "metta"
        load_stdlib = config.try(&.["load_stdlib"]) != "false"
        max_steps = (config.try(&.["max_steps"]) || "1000").to_i

        @metta_integration = CrystalCog::MeTTa.create_integration(load_stdlib, max_steps)
        @metta_integration.not_nil!.attach_atomspace(atomspace)
        @metta_integration.not_nil!.initialize_backend
        link_to_agency("metta")
        CogUtil::Logger.info("MeTTa integration initialized")
      when "typescript_sdk", "typescript", "sdk"
        host = config.try(&.["host"]) || "0.0.0.0"
        port = (config.try(&.["port"]) || "8080").to_i
        websocket = config.try(&.["websocket"]) != "false"

        @typescript_sdk = CrystalCog::TypeScriptSDK.create_integration(host, port, websocket)
        @typescript_sdk.not_nil!.attach_atomspace(atomspace)
        @typescript_sdk.not_nil!.initialize_backend
        link_to_agency("typescript_sdk")
        CogUtil::Logger.info("TypeScript SDK integration initialized")
      else
        CogUtil::Logger.error("Unknown integration: #{integration_name}")
      end
    end

    # Get status of all integrations including cognitive agency
    def get_integration_status : Hash(String, Hash(String, String))
      status = {} of String => Hash(String, String)

      if agency = @cognitive_agency
        status["cognitive_agency"] = agency.status
      end

      if bridge = @cogpy_bridge
        status["cogpy"] = bridge.status
      end

      if adapter = @pyg_adapter
        status["pyg"] = adapter.status
      end

      if agent = @pygmalion_agent
        status["pygmalion"] = agent.status
      end

      if frontend = @galatea_frontend
        status["galatea"] = frontend.status
      end

      if connector = @paphos_connector
        status["paphos"] = connector.status
      end

      if accelerator = @crystal_accelerator
        status["accelerator"] = accelerator.status
      end

      # Phase 6 integrations
      if neo4j = @neo4j_integration
        status["neo4j"] = neo4j.status
      end

      if ipfs = @ipfs_integration
        status["ipfs"] = ipfs.status
      end

      if metta = @metta_integration
        status["metta"] = metta.status
      end

      if sdk = @typescript_sdk
        status["typescript_sdk"] = sdk.status
      end

      # Add external repo info
      status["external_repos"] = {
        "galatea" => EXTERNAL_REPOS["galatea"],
        "paphos"  => EXTERNAL_REPOS["paphos"],
      }

      status
    end

    # Execute integrated cognitive pipeline with full agency coordination
    def execute_cognitive_pipeline(input : String) : Hash(String, String)
      CogUtil::Logger.info("Executing integrated cognitive pipeline with agency coordination")

      result = {} of String => String

      # Process through unified cognitive agency first
      if agency = @cognitive_agency
        agency_result = agency.process(input, "pipeline_input")
        result["agency_processed"] = "true"
        result["agency_strength"] = agency_result["agency_strength"]? || "0.0"
        result["coherence"] = agency_result["coherence"]? || "0.9"
      end

      # Use accelerator for optimized processing
      if accelerator = @crystal_accelerator
        accelerator.execute_accelerated("cognitive_pipeline") do
          # Process through Pygmalion for conversational understanding
          if agent = @pygmalion_agent
            begin
              pygmalion_response = agent.chat(input)
              result["pygmalion_response"] = pygmalion_response

              # Feed response back through agency
              if agency = @cognitive_agency
                agency.process(pygmalion_response, "pygmalion")
              end
            rescue ex : IO::Error | Socket::Error | PygmalionAgent::BackendError
              # The Pygmalion backend is an external service; the rest of the
              # pipeline still runs without it (unreachable or HTTP error).
              CogUtil::Logger.warn("Pygmalion backend unavailable: #{ex.message}")
              result["pygmalion_status"] = "unavailable"
            end
          end

          # Execute CogPy cognitive functions
          if bridge = @cogpy_bridge
            cognitive_data = bridge.send_cognitive_data({"input" => input})
            result["cogpy_processing"] = cognitive_data["status"]
          end

          # Coordinate grip with Paphos backend
          if connector = @paphos_connector
            if agency = @cognitive_agency
              grip_state = agency.get_state
              coordination = connector.coordinate_cognitive_grip(grip_state)
              result["paphos_coordination"] = coordination["consensus"]? || "true"
            end

            connector.synchronize_state
            result["paphos_sync"] = "completed"
          end

          # Execute Galatea cognitive pipeline
          if frontend = @galatea_frontend
            galatea_result = frontend.execute_cognitive_pipeline(input)
            result["galatea_pipeline"] = galatea_result["pipeline_status"]? || "completed"

            frontend.ws_handlers.broadcast_state_update(result)
            result["galatea_update"] = "broadcasted"
          end
        end
      end

      result["status"] = "completed"
      result["timestamp"] = Time.utc.to_s
      result["version"] = VERSION
      result
    end

    # Execute cognitive grip coordination across all components
    def coordinate_cognitive_grip(input : String) : Hash(String, String)
      CogUtil::Logger.info("Coordinating cognitive grip across all integrations")

      result = {} of String => String

      # Process through unified agency
      if agency = @cognitive_agency
        agency_result = agency.process(input, "grip_coordination")
        result = result.merge(agency_result)
      end

      # Coordinate with Galatea frontend
      if frontend = @galatea_frontend
        galatea_grip = frontend.apply_cognitive_grip(input)
        result["galatea_grip"] = galatea_grip["grip_applied"]? || "false"
      end

      # Coordinate with Paphos backend
      if connector = @paphos_connector
        paphos_grip = connector.coordinate_cognitive_grip(result)
        result["paphos_grip"] = paphos_grip["consensus"]? || "false"
      end

      result["coordination_complete"] = "true"
      result["timestamp"] = Time.utc.to_s

      result
    end

    # Modulate cognitive agency
    def modulate_agency(signal : String, intensity : Float64 = 0.5)
      if agency = @cognitive_agency
        agency.modulate(signal, intensity)
        CogUtil::Logger.info("Agency modulated: #{signal} (intensity: #{intensity})")
      end
    end

    # Get recent thoughts from cognitive stream
    def get_thought_stream(limit : Int32 = 20) : Array(Hash(String, String))
      if agency = @cognitive_agency
        agency.recent_thoughts(limit)
      else
        [] of Hash(String, String)
      end
    end

    # Get attention focuses
    def get_attention_focuses(limit : Int32 = 10) : Array(Tuple(String, Float64))
      if agency = @cognitive_agency
        agency.top_focuses(limit)
      else
        [] of Tuple(String, Float64)
      end
    end

    # Store cognitive snapshot to Paphos
    def store_cognitive_snapshot(snapshot_id : String) : Bool
      if connector = @paphos_connector
        connector.store_snapshot(snapshot_id)
      else
        false
      end
    end

    # Load cognitive snapshot from Paphos
    def load_cognitive_snapshot(snapshot_id : String) : Hash(String, String)?
      if connector = @paphos_connector
        connector.load_snapshot(snapshot_id)
      else
        nil
      end
    end

    # Shutdown all integrations
    def shutdown_all
      CogUtil::Logger.info("Shutting down all integrations")

      # Phase 5 integrations
      @cogpy_bridge.try &.disconnect
      @galatea_frontend.try &.stop
      @paphos_connector.try &.disconnect
      @cognitive_agency.try &.reset

      # Phase 6 integrations
      @neo4j_integration.try &.disconnect
      @ipfs_integration.try &.disconnect
      @metta_integration.try &.disconnect
      @typescript_sdk.try &.disconnect

      # Clear all references
      @paphos_connector = nil
      @pygmalion_agent = nil
      @pyg_adapter = nil
      @crystal_accelerator = nil
      @galatea_frontend = nil
      @cognitive_agency = nil
      @neo4j_integration = nil
      @ipfs_integration = nil
      @metta_integration = nil
      @typescript_sdk = nil

      @initialized = false
      CogUtil::Logger.info("All integrations shut down")
    end

    # Link component to cognitive agency
    private def link_to_agency(component_name : String)
      if agency = @cognitive_agency
        agency.link_component(component_name)
      end
    end
  end

  # Factory method for creating integration manager
  def self.create_manager : Manager
    Manager.new
  end

  # Factory for creating manager with optimal cognitive grip
  def self.create_optimal_manager : Manager
    Manager.new
  end

  # Quick integration helper
  def self.quick_setup(atomspace : AtomSpace::AtomSpace) : Manager
    manager = create_manager
    manager.initialize_all_integrations(atomspace)
    manager
  end
end
