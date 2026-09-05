require "spec"
require "file_utils"
require "../../src/atomspace/atomspace"

describe AtomSpace::MemoryStorageNode do
  it "opens and closes, tracking connected state" do
    storage = AtomSpace::MemoryStorageNode.new("mem")
    storage.connected?.should be_false

    storage.open.should be_true
    storage.connected?.should be_true

    storage.close.should be_true
    storage.connected?.should be_false
  end

  it "rejects mutations while disconnected" do
    storage = AtomSpace::MemoryStorageNode.new("mem_disconnected")
    atom = AtomSpace::ConceptNode.new("dog")

    storage.store_atom(atom).should be_false
    storage.fetch_atom(atom.handle).should be_nil
    storage.remove_atom(atom).should be_false
    storage.store_atomspace(AtomSpace::AtomSpace.new).should be_false
    storage.load_atomspace(AtomSpace::AtomSpace.new).should be_false
  end

  it "stores, fetches, and removes individual atoms" do
    storage = AtomSpace::MemoryStorageNode.new("mem_crud")
    storage.open.should be_true

    dog = AtomSpace::ConceptNode.new("dog")
    cat = AtomSpace::ConceptNode.new("cat")

    storage.store_atom(dog).should be_true
    storage.store_atom(cat).should be_true

    storage.fetch_atom(dog.handle).should eq(dog)
    storage.fetch_atom(cat.handle).should eq(cat)
    storage.fetch_atom(999_999_u64).should be_nil

    storage.remove_atom(dog).should be_true
    storage.fetch_atom(dog.handle).should be_nil
    storage.fetch_atom(cat.handle).should eq(cat)

    storage.close
  end

  it "round-trips an AtomSpace through store and load" do
    storage = AtomSpace::MemoryStorageNode.new("mem_space")
    storage.open.should be_true

    source = AtomSpace::AtomSpace.new
    dog = source.add_concept_node("dog")
    animal = source.add_concept_node("animal")
    source.add_inheritance_link(dog, animal)

    storage.store_atomspace(source).should be_true
    storage.get_stats["atom_count"].should eq(source.size.to_i64)
    storage.all_atoms.size.should eq(source.size)

    target = AtomSpace::AtomSpace.new
    storage.load_atomspace(target).should be_true
    target.size.should eq(source.size)
    target.node_count.should eq(source.node_count)
    target.link_count.should eq(source.link_count)

    storage.clear
    storage.all_atoms.should be_empty
    storage.get_stats["atom_count"].should eq(0_i64)

    storage.close
  end

  it "implements StorageNode bulk helpers and resolve_atom" do
    storage = AtomSpace::MemoryStorageNode.new("mem_bulk")
    storage.open.should be_true

    a = AtomSpace::ConceptNode.new("a")
    b = AtomSpace::ConceptNode.new("b")
    link = AtomSpace::InheritanceLink.new(a, b)

    storage.store_atoms([a, b, link]).should be_true
    storage.store_atoms_batch([a, b]).should be_true

    fetched = storage.fetch_atoms_batch([a.handle, b.handle, 42_u64])
    fetched.size.should eq(2)
    fetched.should contain(a)
    fetched.should contain(b)

    storage.resolve_atom(a.handle).should eq(a)
    storage.resolve_atom(42_u64).should be_nil

    lazy = storage.fetch_link_lazy(link.handle)
    lazy.should_not be_nil
    lazy.not_nil!.type.should eq(AtomSpace::AtomType::INHERITANCE_LINK)

    storage.fetch_link_lazy(a.handle).should be_nil
    storage.fetch_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE).should be_empty

    stats = storage.get_stats
    stats["type"].should eq("MemoryStorage")
    stats["connected"].should eq("true")
    stats["atom_count"].should eq(3_i64)

    storage.close
  end
end

describe AtomSpace::FileStorageNode do
  it "persists atoms to a file and serves them from the in-memory index" do
    dir = File.join(Dir.tempdir, "crystalcog_file_storage_#{Random::Secure.hex(6)}")
    path = File.join(dir, "atoms.scm")
    FileUtils.mkdir_p(dir)

    begin
      storage = AtomSpace::FileStorageNode.new("file", path)
      storage.connected?.should be_false
      storage.open.should be_true
      storage.connected?.should be_true
      File.exists?(path).should be_true

      dog = AtomSpace::ConceptNode.new("dog")
      animal = AtomSpace::ConceptNode.new("animal")
      link = AtomSpace::InheritanceLink.new(dog, animal)

      storage.store_atom(dog).should be_true
      storage.store_atom(animal).should be_true
      storage.store_atom(link).should be_true

      storage.fetch_atom(dog.handle).should eq(dog)
      storage.fetch_atom(animal.handle).should eq(animal)
      storage.fetch_atom(link.handle).should eq(link)

      content = File.read(path)
      content.should contain("CONCEPT_NODE")
      content.should contain("\"dog\"")
      content.should contain("INHERITANCE_LINK")

      storage.remove_atom(link).should be_true
      storage.fetch_atom(link.handle).should be_nil
      File.read(path).should_not contain("INHERITANCE_LINK")

      stats = storage.get_stats
      stats["type"].should eq("FileStorage")
      stats["path"].should eq(path)
      stats["connected"].should eq("true")
      stats["file_exists"].should eq("true")
      stats["file_size"].as(Int64).should be > 0

      storage.close.should be_true
      storage.connected?.should be_false
      storage.fetch_atom(dog.handle).should be_nil
    ensure
      FileUtils.rm_rf(dir) if Dir.exists?(dir)
    end
  end

  it "stores and loads an AtomSpace via scheme serialization" do
    dir = File.join(Dir.tempdir, "crystalcog_file_space_#{Random::Secure.hex(6)}")
    path = File.join(dir, "space.scm")
    FileUtils.mkdir_p(dir)

    begin
      storage = AtomSpace::FileStorageNode.new("file_space", path)
      storage.open.should be_true

      source = AtomSpace::AtomSpace.new
      source.add_concept_node("alpha")
      source.add_concept_node("beta")
      source.add_predicate_node("likes")

      storage.store_atomspace(source).should be_true
      File.read(path).should contain("\"alpha\"")
      File.read(path).should contain("\"beta\"")
      File.read(path).should contain("\"likes\"")

      target = AtomSpace::AtomSpace.new
      storage.load_atomspace(target).should be_true
      # File parser reconstructs nodes; count should match stored nodes
      target.node_count.should eq(source.node_count)

      storage.close
    ensure
      FileUtils.rm_rf(dir) if Dir.exists?(dir)
    end
  end

  it "rejects operations while disconnected" do
    dir = File.join(Dir.tempdir, "crystalcog_file_disc_#{Random::Secure.hex(6)}")
    path = File.join(dir, "disc.scm")
    FileUtils.mkdir_p(dir)

    begin
      storage = AtomSpace::FileStorageNode.new("file_disc", path)
      atom = AtomSpace::ConceptNode.new("lonely")

      storage.store_atom(atom).should be_false
      storage.fetch_atom(atom.handle).should be_nil
      storage.remove_atom(atom).should be_false
      storage.store_atomspace(AtomSpace::AtomSpace.new).should be_false
      storage.load_atomspace(AtomSpace::AtomSpace.new).should be_false
    ensure
      FileUtils.rm_rf(dir) if Dir.exists?(dir)
    end
  end
end

describe AtomSpace::HypergraphStateStorageNode do
  it "delegates StorageNode operations through a file backend" do
    dir = File.join(Dir.tempdir, "crystalcog_hyper_#{Random::Secure.hex(6)}")
    path = File.join(dir, "hyper.scm")
    FileUtils.mkdir_p(dir)

    begin
      storage = AtomSpace::HypergraphStateStorageNode.new("hyper", path, "file")
      storage.open.should be_true
      storage.connected?.should be_true

      node = AtomSpace::ConceptNode.new("hyper_node")
      storage.store_atom(node).should be_true
      storage.fetch_atom(node.handle).should eq(node)

      stats = storage.get_stats
      stats["type"].should eq("HypergraphStateStorage")
      stats["path"].should eq(path)
      stats["connected"].should eq("true")
      stats["backend_type"].should eq("FileStorage")

      storage.close.should be_true
      storage.connected?.should be_false
    ensure
      FileUtils.rm_rf(dir) if Dir.exists?(dir)
    end
  end
end

{% unless env("DISABLE_SQLITE3") == "1" %}
describe AtomSpace::SQLiteStorageNode do
  it "stores and loads atoms with SQLite" do
    dir = File.join(Dir.tempdir, "crystalcog_sqlite_#{Random::Secure.hex(6)}")
    path = File.join(dir, "atoms.db")
    FileUtils.mkdir_p(dir)

    begin
      storage = AtomSpace::SQLiteStorageNode.new("sqlite", path, use_pool: false)
      storage.open.should be_true

      dog = AtomSpace::ConceptNode.new("dog")
      storage.store_atom(dog).should be_true

      fetched = storage.fetch_atom(dog.handle)
      fetched.should_not be_nil
      fetched.not_nil!.is_a?(AtomSpace::Node).should be_true
      fetched.not_nil!.as(AtomSpace::Node).name.should eq("dog")

      source = AtomSpace::AtomSpace.new
      source.add_concept_node("one")
      source.add_concept_node("two")
      storage.store_atomspace(source).should be_true

      target = AtomSpace::AtomSpace.new
      storage.load_atomspace(target).should be_true
      target.size.should be >= 2

      stats = storage.get_stats
      stats["type"].should eq("SQLiteStorage")
      stats["connected"].should eq("true")

      storage.close.should be_true
    ensure
      FileUtils.rm_rf(dir) if Dir.exists?(dir)
    end
  end
end
{% end %}
