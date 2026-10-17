require "spec"
require "../../src/integrations/integration"
require "../../src/atomspace/atomspace"
require "../../src/cogutil/logger"

describe CrystalCogIntegration::Manager do
  describe "#initialize" do
    it "creates a new integration manager" do
      manager = CrystalCogIntegration::Manager.new
      manager.should_not be_nil
      manager.initialized.should be_false
    end
  end

  describe "#initialize_integration" do
    it "initializes cogpy integration with cognitive agency" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new

      manager.initialize_integration("cogpy", atomspace)
      manager.cogpy_bridge.should_not be_nil
      manager.cognitive_agency.should_not be_nil
    end

    it "initializes pyg integration" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new

      manager.initialize_integration("pyg", atomspace)
      manager.pyg_adapter.should_not be_nil
    end

    it "initializes pygmalion integration" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new

      manager.initialize_integration("pygmalion", atomspace)
      manager.pygmalion_agent.should_not be_nil
    end

    it "initializes galatea integration with cognitive agency grip" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new

      manager.initialize_integration("galatea", atomspace)
      manager.galatea_frontend.should_not be_nil
      # Galatea frontend should have cognitive agency enabled
    end

    it "initializes paphos integration with cognitive coordination" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new

      manager.initialize_integration("paphos", atomspace)
      manager.paphos_connector.should_not be_nil
    end

    it "initializes accelerator integration" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new

      manager.initialize_integration("accelerator", atomspace)
      manager.crystal_accelerator.should_not be_nil
    end

    it "initializes galatea with custom grip settings" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new
      config = {"grip_strength" => "9", "mode" => "autonomous"}

      manager.initialize_integration("galatea", atomspace, config)
      manager.galatea_frontend.should_not be_nil
    end

    it "initializes paphos with custom coordination mode" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new
      config = {"coordination_mode" => "leader"}

      manager.initialize_integration("paphos", atomspace, config)
      manager.paphos_connector.should_not be_nil
    end
  end

  describe "#initialize_all_integrations" do
    it "initializes all integrations with cognitive agency" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new

      manager.initialize_all_integrations(atomspace)

      manager.cogpy_bridge.should_not be_nil
      manager.pyg_adapter.should_not be_nil
      manager.pygmalion_agent.should_not be_nil
      manager.galatea_frontend.should_not be_nil
      manager.paphos_connector.should_not be_nil
      manager.crystal_accelerator.should_not be_nil
      manager.cognitive_agency.should_not be_nil
      manager.initialized.should be_true
    end
  end

  describe "#get_integration_status" do
    it "returns status for all initialized integrations including cognitive agency" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new
      manager.initialize_all_integrations(atomspace)

      status = manager.get_integration_status

      status.should be_a(Hash(String, Hash(String, String)))
      status.has_key?("cogpy").should be_true
      status.has_key?("pyg").should be_true
      status.has_key?("pygmalion").should be_true
      status.has_key?("galatea").should be_true
      status.has_key?("paphos").should be_true
      status.has_key?("accelerator").should be_true
      status.has_key?("cognitive_agency").should be_true
      status.has_key?("external_repos").should be_true
    end

    it "includes external repository references" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new
      manager.initialize_all_integrations(atomspace)

      status = manager.get_integration_status
      repos = status["external_repos"]

      repos["galatea"].should eq("https://github.com/9cog/galatea-frontend")
      repos["paphos"].should eq("https://github.com/9cog/paphos-backend")
    end
  end

  describe "#execute_cognitive_pipeline" do
    it "executes complete cognitive pipeline with agency coordination" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new
      manager.initialize_all_integrations(atomspace)

      result = manager.execute_cognitive_pipeline("test input")

      result.should be_a(Hash(String, String))
      result["status"].should eq("completed")
      result.has_key?("timestamp").should be_true
      result.has_key?("agency_processed").should be_true
      result["agency_processed"].should eq("true")
    end
  end

  describe "#coordinate_cognitive_grip" do
    it "coordinates grip across all integrations" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new
      manager.initialize_all_integrations(atomspace)

      result = manager.coordinate_cognitive_grip("test coordination")

      result.should be_a(Hash(String, String))
      result.has_key?("coordination_complete").should be_true
      result["coordination_complete"].should eq("true")
    end
  end

  describe "#modulate_agency" do
    it "modulates cognitive agency with signal" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new
      manager.initialize_all_integrations(atomspace)

      # Should not raise
      manager.modulate_agency("focus", 0.8)
      manager.modulate_agency("engage", 0.7)
    end
  end

  describe "#get_thought_stream" do
    it "returns recent thoughts from cognitive stream" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new
      manager.initialize_all_integrations(atomspace)

      # Process some input to generate thoughts
      manager.execute_cognitive_pipeline("generate thought")

      thoughts = manager.get_thought_stream(10)
      thoughts.should be_a(Array(Hash(String, String)))
    end
  end

  describe "#get_attention_focuses" do
    it "returns attention focus weights" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new
      manager.initialize_all_integrations(atomspace)

      # Process input to build attention
      manager.execute_cognitive_pipeline("focus attention")

      focuses = manager.get_attention_focuses(5)
      focuses.should be_a(Array(Tuple(String, Float64)))
    end
  end

  describe "#store_cognitive_snapshot" do
    it "stores cognitive snapshot to Paphos" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new
      manager.initialize_all_integrations(atomspace)

      result = manager.store_cognitive_snapshot("test_snapshot_001")
      result.should be_true
    end
  end

  describe "#load_cognitive_snapshot" do
    it "loads cognitive snapshot from Paphos" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new
      manager.initialize_all_integrations(atomspace)

      snapshot = manager.load_cognitive_snapshot("test_snapshot_001")
      snapshot.should_not be_nil
    end
  end

  describe "#shutdown_all" do
    it "shuts down all integrations including cognitive agency" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration::Manager.new
      manager.initialize_all_integrations(atomspace)

      manager.shutdown_all

      manager.initialized.should be_false
      manager.cognitive_agency.should be_nil
    end
  end
end

describe CrystalCogIntegration do
  describe ".create_manager" do
    it "creates a new integration manager" do
      manager = CrystalCogIntegration.create_manager
      manager.should be_a(CrystalCogIntegration::Manager)
    end
  end

  describe ".create_optimal_manager" do
    it "creates a manager optimized for cognitive grip" do
      manager = CrystalCogIntegration.create_optimal_manager
      manager.should be_a(CrystalCogIntegration::Manager)
    end
  end

  describe ".quick_setup" do
    it "creates and initializes manager in one call" do
      atomspace = AtomSpace::AtomSpace.new
      manager = CrystalCogIntegration.quick_setup(atomspace)

      manager.should be_a(CrystalCogIntegration::Manager)
      manager.initialized.should be_true
      manager.cognitive_agency.should_not be_nil

      manager.shutdown_all
    end
  end

  describe "EXTERNAL_REPOS" do
    it "contains galatea frontend reference" do
      CrystalCogIntegration::EXTERNAL_REPOS["galatea"].should eq("https://github.com/9cog/galatea-frontend")
    end

    it "contains paphos backend reference" do
      CrystalCogIntegration::EXTERNAL_REPOS["paphos"].should eq("https://github.com/9cog/paphos-backend")
    end
  end
end
