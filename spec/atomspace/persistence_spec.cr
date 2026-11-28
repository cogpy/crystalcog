require "spec"
require "file_utils"
require "../../src/atomspace/persistence"

# Direct coverage for src/atomspace/persistence.cr: storage attachment,
# store/load fan-out across attached storages, factory attach defaults and
# hypergraph state persistence.

private def populated_space
  space = AtomSpace::AtomSpace.new
  dog = space.add_concept_node("dog")
  animal = space.add_concept_node("animal")
  space.add_inheritance_link(dog, animal, AtomSpace::SimpleTruthValue.new(0.9, 0.8))
  space
end

private def open_memory(name)
  storage = AtomSpace::MemoryStorageNode.new(name)
  storage.open.should be_true
  storage
end

private def with_tmpdir(&)
  dir = File.join(Dir.tempdir, "crystalcog_persistence_spec_#{Process.pid}_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(dir)
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

describe "AtomSpace persistence extension (persistence.cr)" do
  describe "storage attachment" do
    it "starts empty and attaches and detaches storages in order" do
      space = AtomSpace::AtomSpace.new
      space.get_attached_storages.should be_empty
      first = AtomSpace::MemoryStorageNode.new("first")
      second = AtomSpace::MemoryStorageNode.new("second")
      space.attach_storage(first)
      space.attach_storage(second)
      space.get_attached_storages.should eq([first, second])
      space.detach_storage(first)
      space.get_attached_storages.should eq([second])
    end

    it "detaching from a space with no storages is a no-op" do
      space = AtomSpace::AtomSpace.new
      space.detach_storage(AtomSpace::MemoryStorageNode.new("never_attached"))
      space.get_attached_storages.should be_empty
    end
  end

  describe "store_all and load_all" do
    it "returns true with no attached storages" do
      space = AtomSpace::AtomSpace.new
      space.store_all.should be_true
      space.load_all.should be_true
    end

    it "stores into every attached storage and loads back" do
      space = populated_space
      first = open_memory("store_first")
      second = open_memory("store_second")
      space.attach_storage(first)
      space.attach_storage(second)
      space.store_all.should be_true

      [first, second].each do |storage|
        restored = AtomSpace::AtomSpace.new
        restored.load_from(storage).should be_true
        restored.size.should eq(space.size)
        restored.get_nodes_by_name("dog").size.should eq(1)
      end

      restored = AtomSpace::AtomSpace.new
      restored.attach_storage(first)
      restored.load_all.should be_true
      restored.size.should eq(3)
    end

    it "reports failure when any storage fails but still stores the others" do
      space = populated_space
      disconnected = AtomSpace::MemoryStorageNode.new("store_disconnected")
      healthy = open_memory("store_healthy")
      space.attach_storage(disconnected)
      space.attach_storage(healthy)
      space.store_all.should be_false

      restored = AtomSpace::AtomSpace.new
      restored.load_from(healthy).should be_true
      restored.size.should eq(3)

      loader = AtomSpace::AtomSpace.new
      loader.attach_storage(disconnected)
      loader.attach_storage(healthy)
      loader.load_all.should be_false
      loader.size.should eq(3)
    end

    it "store_to and load_from work without attaching" do
      space = populated_space
      storage = open_memory("unattached")
      space.store_to(storage).should be_true
      space.get_attached_storages.should be_empty
      restored = AtomSpace::AtomSpace.new
      restored.load_from(storage).should be_true
      restored.size.should eq(3)
    end
  end

  describe "storage factories" do
    it "attaches file and sqlite storages by default and honours attach: false" do
      with_tmpdir do |dir|
        space = AtomSpace::AtomSpace.new
        file = space.create_file_storage("file", File.join(dir, "atoms.scm"))
        file.should be_a(AtomSpace::FileStorageNode)
        sqlite = space.create_sqlite_storage("sqlite", File.join(dir, "atoms.db"))
        sqlite.should be_a(AtomSpace::SQLiteStorageNode)
        space.get_attached_storages.should eq([file, sqlite] of AtomSpace::StorageNode)

        detached = space.create_file_storage("detached", File.join(dir, "other.scm"), attach: false)
        space.get_attached_storages.includes?(detached).should be_false
        space.get_attached_storages.size.should eq(2)
      end
    end

    it "round-trips through an attached file storage" do
      with_tmpdir do |dir|
        path = File.join(dir, "roundtrip.scm")
        space = populated_space
        space.create_file_storage("writer", path).open.should be_true
        space.store_all.should be_true

        restored = AtomSpace::AtomSpace.new
        restored.create_file_storage("reader", path).open.should be_true
        restored.load_all.should be_true
        restored.size.should eq(3)
        restored.get_nodes_by_name("animal").size.should eq(1)
      end
    end
  end

  describe "hypergraph state" do
    it "extracts a state snapshot of the current space" do
      space = populated_space
      before = Time.utc
      state = space.extract_hypergraph_state([2, 3], 0.75, 1, "reasoning")
      state.atomspace.should be(space)
      state.tensor_shape.should eq([2, 3])
      state.attention.should eq(0.75)
      state.meta_level.should eq(1)
      state.cognitive_operation.should eq("reasoning")
      state.timestamp.should be >= before - 1.second
      space.extract_hypergraph_state([1], 0.1).cognitive_operation.should be_nil
    end

    it "creates attached hypergraph storage and round-trips state and atoms" do
      with_tmpdir do |dir|
        path = File.join(dir, "state.scm")
        space = populated_space
        storage = space.create_hypergraph_storage("hg", path)
        space.get_attached_storages.should eq([storage] of AtomSpace::StorageNode)
        storage.open.should be_true
        space.store_hypergraph_state([4, 8], 0.5, 2, "attention").should be_true
        File.exists?(File.join(dir, "state_metadata.json")).should be_true

        restored = AtomSpace::AtomSpace.new
        restored.create_hypergraph_storage("hg_reader", path).open.should be_true
        state = restored.load_hypergraph_state.not_nil!
        state.atomspace.should be(restored)
        state.tensor_shape.should eq([4, 8])
        state.attention.should eq(0.5)
        state.meta_level.should eq(2)
        state.cognitive_operation.should eq("attention")
        restored.size.should eq(3)
      end
    end

    it "ignores non-hypergraph storages and fails when hypergraph storage is closed" do
      with_tmpdir do |dir|
        space = populated_space
        space.attach_storage(AtomSpace::MemoryStorageNode.new("plain_disconnected"))
        space.store_hypergraph_state([1], 0.2).should be_true
        space.load_hypergraph_state.should be_nil

        closed = space.create_hypergraph_storage("closed", File.join(dir, "closed.scm"))
        space.store_hypergraph_state([1], 0.2).should be_false
        space.load_hypergraph_state.should be_nil
        closed.connected?.should be_false
      end
    end

    it "store_hypergraph_state_to and load_hypergraph_state_from skip attachment" do
      with_tmpdir do |dir|
        path = File.join(dir, "direct.scm")
        space = populated_space
        storage = AtomSpace::HypergraphStateStorageNode.new("direct", path)
        storage.open.should be_true
        space.store_hypergraph_state_to(storage, [3], 0.9, cognitive_operation: nil).should be_true
        space.get_attached_storages.should be_empty

        restored = AtomSpace::AtomSpace.new
        state = restored.load_hypergraph_state_from(storage).not_nil!
        state.tensor_shape.should eq([3])
        state.meta_level.should eq(0)
        state.cognitive_operation.should be_nil
        restored.size.should eq(3)
      end
    end
  end
end
