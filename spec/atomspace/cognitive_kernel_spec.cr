require "spec"
require "../../src/atomspace/cognitive_kernel"
require "file_utils"

describe AtomSpace::CognitiveKernel do
  describe "initialization" do
    it "creates a kernel with default atomspace and parameters" do
      kernel = AtomSpace::CognitiveKernel.new([4, 2], 0.75, 1, "reasoning")

      kernel.tensor_shape.should eq([4, 2])
      kernel.attention_weight.should eq(0.75)
      kernel.meta_level.should eq(1)
      kernel.cognitive_operation.should eq("reasoning")
      kernel.atomspace.size.should eq(0)
    end

    it "creates a kernel from an existing AtomSpace" do
      atomspace = AtomSpace::AtomSpace.new
      atomspace.add_concept_node("seed")

      kernel = AtomSpace::CognitiveKernel.new(atomspace, [3], 0.4, 2, "memory")

      kernel.atomspace.should be(atomspace)
      kernel.atomspace.size.should eq(1)
      kernel.tensor_shape.should eq([3])
      kernel.attention_weight.should eq(0.4)
      kernel.meta_level.should eq(2)
      kernel.cognitive_operation.should eq("memory")
    end

    it "uses default attention, meta level, and operation" do
      kernel = AtomSpace::CognitiveKernel.new([2, 2])

      kernel.attention_weight.should eq(0.5)
      kernel.meta_level.should eq(0)
      kernel.cognitive_operation.should be_nil
    end
  end

  describe "tensor_field_encoding" do
    it "generates a prime encoding matching tensor shape size" do
      kernel = AtomSpace::CognitiveKernel.new([2, 3, 4], 0.5)
      encoding = kernel.tensor_field_encoding("prime", include_attention: false)

      encoding.size.should eq(3)
      # primes 2,3,5 multiplied by shape dims 2,3,4
      encoding[0].should eq(4.0_f32)
      encoding[1].should eq(9.0_f32)
      encoding[2].should eq(20.0_f32)
    end

    it "applies attention weighting when requested" do
      attention = 0.5
      kernel = AtomSpace::CognitiveKernel.new([2, 3], attention)
      without = kernel.tensor_field_encoding("prime", include_attention: false)
      with_att = kernel.tensor_field_encoding("prime", include_attention: true)

      with_att.size.should eq(without.size)
      with_att.each_with_index do |val, idx|
        val.should be_close(without[idx] * attention.to_f32, 0.0001)
      end
    end

    it "appends meta level when requested" do
      kernel = AtomSpace::CognitiveKernel.new([2, 3], 0.5, 7)
      encoding = kernel.tensor_field_encoding("prime", include_attention: false, include_meta_level: true)

      encoding.size.should eq(3)
      encoding.last.should eq(7.0_f32)
    end

    it "supports fibonacci, harmonic, factorial, and power_of_two encodings" do
      kernel = AtomSpace::CognitiveKernel.new([1, 1, 1], 1.0)

      fib = kernel.tensor_field_encoding("fibonacci", include_attention: false)
      fib.should eq([1.0_f32, 1.0_f32, 2.0_f32])

      harmonic = kernel.tensor_field_encoding("harmonic", include_attention: false)
      harmonic[0].should be_close(1.0_f32, 0.0001)
      harmonic[1].should be_close(0.5_f32, 0.0001)
      harmonic[2].should be_close(1.0_f32 / 3.0_f32, 0.0001)

      factorial = kernel.tensor_field_encoding("factorial", include_attention: false)
      factorial.should eq([1.0_f32, 2.0_f32, 6.0_f32])

      powers = kernel.tensor_field_encoding("power_of_two", include_attention: false)
      powers.should eq([1.0_f32, 2.0_f32, 4.0_f32])
    end

    it "falls back to primes for unknown encoding types" do
      kernel = AtomSpace::CognitiveKernel.new([2], 1.0)
      unknown = kernel.tensor_field_encoding("not-a-real-type", include_attention: false)
      prime = kernel.tensor_field_encoding("prime", include_attention: false)

      unknown.should eq(prime)
    end

    it "normalizes encodings with unit and standard modes" do
      kernel = AtomSpace::CognitiveKernel.new([3, 4], 1.0)

      unit = kernel.tensor_field_encoding("prime", include_attention: false, normalization: "unit")
      magnitude = Math.sqrt(unit.sum { |x| x * x }.to_f64)
      magnitude.should be_close(1.0, 0.001)

      standard = kernel.tensor_field_encoding("prime", include_attention: false, normalization: "standard")
      mean = standard.sum / standard.size
      mean.should be_close(0.0_f32, 0.001)
    end

    it "returns cached results for identical encoding requests" do
      kernel = AtomSpace::CognitiveKernel.new([5, 5, 5], 0.6)
      first = kernel.tensor_field_encoding("prime", include_attention: true)
      second = kernel.tensor_field_encoding("prime", include_attention: true)

      second.should eq(first)

      metrics = kernel.performance_metrics
      metrics.has_key?("tensor_field_encoding").should be_true
      metrics["tensor_field_encoding"].call_count.should be >= 2
    end
  end

  describe "hypergraph_tensor_encoding" do
    it "extends base encoding with connectivity factors" do
      kernel = AtomSpace::CognitiveKernel.new([2, 2], 0.8)
      dog = kernel.add_concept_node("dog")
      animal = kernel.add_concept_node("animal")
      kernel.add_inheritance_link(dog, animal)

      base = kernel.tensor_field_encoding("prime", include_attention: false, include_meta_level: false)
      hyper = kernel.hypergraph_tensor_encoding

      hyper.size.should eq(base.size + 3)
      # connectivity = link_count / node_count = 1/2
      hyper[-3].should be_close(0.5_f32, 0.0001)
      hyper[-2].should be_close(0.8_f32, 0.0001)
      hyper[-1].should eq(2.0_f32)
    end
  end

  describe "cognitive_tensor_field_encoding" do
    it "applies operation weights and records the operation name" do
      kernel = AtomSpace::CognitiveKernel.new([1, 1, 1], 1.0)
      base = kernel.tensor_field_encoding
      reasoning = kernel.cognitive_tensor_field_encoding("reasoning")

      kernel.cognitive_operation.should eq("reasoning")
      reasoning.size.should eq(base.size)
      reasoning[0].should be_close(base[0] * 1.5_f32, 0.0001)
      reasoning[1].should be_close(base[1] * 1.2_f32, 0.0001)
      reasoning[2].should be_close(base[2] * 1.0_f32, 0.0001)
    end

    it "uses identity weights for unknown operations" do
      kernel = AtomSpace::CognitiveKernel.new([2, 2], 1.0)
      base = kernel.tensor_field_encoding
      unknown = kernel.cognitive_tensor_field_encoding("unknown-op")

      unknown.should eq(base)
      kernel.cognitive_operation.should eq("unknown-op")
    end
  end

  describe "hypergraph state" do
    it "extracts hypergraph state from kernel parameters" do
      kernel = AtomSpace::CognitiveKernel.new([64, 32], 0.8, 1, "reasoning")
      kernel.add_concept_node("agent-zero")

      state = kernel.hypergraph_state
      state.tensor_shape.should eq([64, 32])
      state.attention.should eq(0.8)
      state.meta_level.should eq(1)
      state.cognitive_operation.should eq("reasoning")
      state.atomspace.size.should eq(1)
    end

    it "stores and loads hypergraph state via file storage" do
      test_dir = File.join(Dir.tempdir, "crystalcog_cognitive_kernel_spec_#{Random.rand(1_000_000)}")
      FileUtils.mkdir_p(test_dir)

      begin
        kernel = AtomSpace::CognitiveKernel.new([8, 4], 0.9, 3, "learning")
        concept = kernel.add_concept_node("persist-me")
        predicate = kernel.add_predicate_node("knows")
        args = kernel.atomspace.add_list_link([concept])
        kernel.add_evaluation_link(predicate, args)

        storage_path = File.join(test_dir, "state.json")
        storage = AtomSpace::HypergraphStateStorageNode.new("test_storage", storage_path, "file")
        storage.open.should be_true

        kernel.store_hypergraph_state(storage).should be_true

        restored = AtomSpace::CognitiveKernel.new([1], 0.1)
        restored.load_hypergraph_state(storage).should be_true

        restored.tensor_shape.should eq([8, 4])
        restored.attention_weight.should eq(0.9)
        restored.meta_level.should eq(3)
        restored.cognitive_operation.should eq("learning")
        restored.atomspace.size.should be > 0

        storage.close
      ensure
        FileUtils.rm_rf(test_dir) if Dir.exists?(test_dir)
      end
    end

    it "returns false when loading from disconnected storage" do
      kernel = AtomSpace::CognitiveKernel.new([2], 0.5)
      storage = AtomSpace::HypergraphStateStorageNode.new("closed", "/tmp/does-not-matter", "file")

      kernel.load_hypergraph_state(storage).should be_false
    end
  end

  describe "AtomSpace convenience methods" do
    it "adds concepts, predicates, inheritance, and evaluation links" do
      kernel = AtomSpace::CognitiveKernel.new([2], 0.5)

      dog = kernel.add_concept_node("dog")
      animal = kernel.add_concept_node("animal")
      likes = kernel.add_predicate_node("likes")
      inheritance = kernel.add_inheritance_link(dog, animal)
      args = kernel.atomspace.add_list_link([dog, animal])
      evaluation = kernel.add_evaluation_link(likes, args)

      dog.type.should eq(AtomSpace::AtomType::CONCEPT_NODE)
      likes.type.should eq(AtomSpace::AtomType::PREDICATE_NODE)
      inheritance.type.should eq(AtomSpace::AtomType::INHERITANCE_LINK)
      evaluation.type.should eq(AtomSpace::AtomType::EVALUATION_LINK)
      kernel.atomspace.node_count.should eq(3)
      # inheritance + list + evaluation
      kernel.atomspace.link_count.should eq(3)
    end
  end

  describe "metrics and representation" do
    it "exposes performance metrics and cache stats" do
      kernel = AtomSpace::CognitiveKernel.new([3, 3], 0.5)
      kernel.tensor_field_encoding("prime")
      kernel.hypergraph_tensor_encoding

      metrics = kernel.performance_metrics
      metrics.has_key?("tensor_field_encoding").should be_true
      metrics["tensor_field_encoding"].call_count.should be >= 1
      metrics["tensor_field_encoding"].avg_time_ms.should be >= 0.0

      stats = kernel.cache_stats
      stats.has_key?("cache_hit_rate").should be_true
      stats.has_key?("cache_size").should be_true
      stats.has_key?("cache_utilization").should be_true
      stats.has_key?("pool_utilization").should be_true
      stats.has_key?("pool_hit_rate").should be_true
    end

    it "renders a readable string representation" do
      kernel = AtomSpace::CognitiveKernel.new([2, 2], 0.25, 1)
      kernel.add_concept_node("x")

      text = kernel.to_s
      text.should contain("CognitiveKernel")
      text.should contain("shape=[2, 2]")
      text.should contain("attention=0.25")
      text.should contain("meta_level=1")
      text.should contain("atomspace_size=1")
    end
  end

  describe "OperationMetrics" do
    it "tracks call counts, averages, and cache hit rate EMA" do
      metrics = AtomSpace::CognitiveKernel::OperationMetrics.new
      metrics.record_operation(10.0, true)
      metrics.record_operation(30.0, false)

      metrics.call_count.should eq(2)
      metrics.total_time_ms.should eq(40.0)
      metrics.avg_time_ms.should eq(20.0)
      # EMA: 0.1*1 + 0.9*0 = 0.1, then 0.1*0 + 0.9*0.1 = 0.09
      metrics.cache_hit_rate.should be_close(0.09, 0.0001)
    end
  end
end
