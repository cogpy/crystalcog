require "spec"
require "../../src/attention/attention_main"
require "../../src/atomspace/atomspace_module"

describe "Attention Main" do
  describe "initialization" do
    it "initializes Attention system" do
      Attention.initialize
      # Should not crash
    end

    it "has correct version" do
      Attention::VERSION.should eq("0.1.0")
    end

    it "creates attention engine" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention.create_engine(atomspace)
      engine.should be_a(Attention::AllocationEngine)
    end
  end

  describe "attention functionality" do
    it "provides attention allocation" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention.create_engine(atomspace)
      # Should be able to allocate attention
      engine.allocate_attention(1)
      engine.should_not be_nil
    end

    it "provides rent collection" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention.create_engine(atomspace)
      # Should have rent collector
      engine.rent_collector.should_not be_nil
    end

    it "provides diffusion" do
      atomspace = AtomSpace::AtomSpace.new
      engine = Attention.create_engine(atomspace)
      # Should have diffusion
      engine.diffusion.should_not be_nil
    end
  end

  describe "system integration" do
    it "integrates with AtomSpace" do
      CogUtil.initialize
      AtomSpace.initialize
      Attention.initialize

      # Should work with atomspace
      atomspace = AtomSpace.create_atomspace
      engine = Attention.create_engine(atomspace)
      engine.should_not be_nil
    end
  end
end
