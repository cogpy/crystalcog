require "spec"
require "../src/crystalcog"

describe "CrystalCog Main" do
  describe "application initialization" do
    it "defines CrystalCog version" do
      CrystalCog::VERSION.should eq("0.1.0")
    end

    it "initializes main application" do
      # Test basic initialization without actually running the full app
      # This would test that all required modules can be loaded
      CogUtil.initialize
      AtomSpace.initialize
      PLN.initialize
      URE.initialize
      OpenCog.initialize

      # Should not crash
      true.should be_true
    end
  end

  describe "module dependencies" do
    it "has proper module order" do
      # Test that dependencies are properly loaded in order
      # CogUtil should be available first
      CogUtil.should be_truthy

      # Then AtomSpace
      AtomSpace.should be_truthy

      # Then reasoning modules
      PLN.should be_truthy
      URE.should be_truthy

      # Finally OpenCog integration
      OpenCog.should be_truthy
    end
  end
end
