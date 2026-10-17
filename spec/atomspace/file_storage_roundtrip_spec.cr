require "spec"
require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"

private def file_storage_roundtrip_path : String
  "/tmp/crystalcog-file-storage-#{Process.pid}-#{Random.rand(1_000_000)}.scm"
end

private def delete_file_storage_roundtrip_path(path : String)
  File.delete(path) if File.exists?(path)
  temporary_path = "#{path}.tmp-#{Process.pid}"
  File.delete(temporary_path) if File.exists?(temporary_path)
end

describe AtomSpace::FileStorageNode do
  it "keeps integer and float numeric labels distinct while restoring NumberNode values" do
    path = file_storage_roundtrip_path
    begin
      source = AtomSpace::AtomSpace.new
      source.add_atom(AtomSpace::NumberNode.new(42))
      source.add_atom(AtomSpace::NumberNode.new(42.0))
      source.add_atom(AtomSpace::Node.new(AtomSpace::AtomType::NUMBER_NODE, "42.250"))
      storage = AtomSpace::FileStorageNode.new("numeric-labels", path)
      storage.open.should be_true
      storage.store_atomspace(source).should be_true
      target = AtomSpace::AtomSpace.new
      storage.load_atomspace(target).should be_true
      target.size.should eq(3)
      ["42", "42.0", "42.250"].each do |name|
        loaded = target.get_nodes_by_name(name).first
        loaded.should be_a(AtomSpace::NumberNode)
        loaded.name.should eq(name)
        loaded.as(AtomSpace::NumberNode).value.should eq(name.to_f64)
      end
    ensure
      delete_file_storage_roundtrip_path(path)
    end
  end

  it "preserves the previous image when a numeric node cannot be faithfully restored" do
    path = file_storage_roundtrip_path
    begin
      source = AtomSpace::AtomSpace.new
      source.add_concept_node("preserved")
      storage = AtomSpace::FileStorageNode.new("failed-write", path)
      storage.open.should be_true
      storage.store_atomspace(source).should be_true
      previous = File.read(path)
      source.add_atom(AtomSpace::Node.new(AtomSpace::AtomType::NUMBER_NODE, "not-a-number"))
      storage.store_atomspace(source).should be_false
      File.read(path).should eq(previous)
    ensure
      delete_file_storage_roundtrip_path(path)
    end
  end

  it "atomically replaces single-atom revisions rather than appending conflicting metadata" do
    path = file_storage_roundtrip_path
    begin
      storage = AtomSpace::FileStorageNode.new("single-update", path)
      storage.open.should be_true
      atom = AtomSpace::ConceptNode.new("updated", AtomSpace::CountTruthValue.new(0.3, 0.4, 2.0))
      storage.store_atom(atom).should be_true
      atom.truth_value = AtomSpace::CountTruthValue.new(0.8, 0.6, 5.0)
      storage.store_atom(atom).should be_true
      storage.close.should be_true
      reopened = AtomSpace::FileStorageNode.new("single-update-reopened", path)
      reopened.open.should be_true
      target = AtomSpace::AtomSpace.new
      reopened.load_atomspace(target).should be_true
      target.size.should eq(1)
      loaded = target.get_nodes_by_name("updated").first
      loaded.truth_value.strength.should eq(0.8)
      loaded.truth_value.count.should eq(5.0)
    ensure
      delete_file_storage_roundtrip_path(path)
    end
  end

  it "indexes shared descendants of a standalone recursive root after reopening and loading" do
    path = file_storage_roundtrip_path
    begin
      storage = AtomSpace::FileStorageNode.new("standalone-root", path)
      storage.open.should be_true
      child = AtomSpace::ConceptNode.new("nested-only")
      root = AtomSpace::ListLink.new([child, child] of AtomSpace::Atom)
      storage.store_atom(root).should be_true
      storage.close.should be_true
      reopened = AtomSpace::FileStorageNode.new("standalone-root-reopened", path)
      reopened.open.should be_true
      target = AtomSpace::AtomSpace.new
      reopened.load_atomspace(target).should be_true
      loaded = target.get_atoms_by_type(AtomSpace::AtomType::LIST_LINK).first.as(AtomSpace::Link)
      loaded[0].same?(loaded[1]).should be_true
      reopened.fetch_atom(loaded[0].handle).not_nil!.same?(loaded[0]).should be_true
      reopened.fetch_link_lazy(loaded.handle).not_nil!.outgoing.size.should eq(2)
      target.size.should eq(2)
    ensure
      delete_file_storage_roundtrip_path(path)
    end
  end

  it "round-trips recursive graphs into canonical AtomSpace identities with typed values" do
    path = file_storage_roundtrip_path

    begin
      source = AtomSpace::AtomSpace.new
      shared_name = "shared \"node\" \\ newline\nλ"
      shared = source.add_node(
        AtomSpace::AtomType::CONCEPT_NODE,
        shared_name,
        AtomSpace::SimpleTruthValue.new(0.91, 0.72)
      )
      shared.attention_value = AtomSpace::AttentionValue.new(12, -5, true)

      counted = source.add_node(
        AtomSpace::AtomType::PREDICATE_NODE,
        "counted",
        AtomSpace::CountTruthValue.new(0.63, 0.41, 9.0)
      )
      bounded = source.add_node(
        AtomSpace::AtomType::SCHEMA_NODE,
        "bounded",
        AtomSpace::IndefiniteTruthValue.new(0.2, 0.8, 0.55)
      )
      fuzzy = source.add_node(
        AtomSpace::AtomType::WORD_NODE,
        "fuzzy",
        AtomSpace::FuzzyTruthValue.new(0.33, 0.66, 0.12)
      )
      variable = source.add_atom(AtomSpace::VariableNode.new("$X", AtomSpace::SimpleTruthValue.new(0.1, 0.2)))
      number = source.add_atom(AtomSpace::NumberNode.new(42.25, AtomSpace::SimpleTruthValue.new(0.3, 0.4)))
      empty = source.add_link(
        AtomSpace::AtomType::LIST_LINK,
        [] of AtomSpace::Atom,
        AtomSpace::FuzzyTruthValue.new(0.2, 0.3, 0.4)
      )
      nested = source.add_link(
        AtomSpace::AtomType::ORDERED_LINK,
        [shared, counted, bounded, fuzzy, variable, number],
        AtomSpace::CountTruthValue.new(0.7, 0.5, 4.0)
      )
      nested.attention_value = AtomSpace::AttentionValue.new(-3, 8, false)
      root = source.add_link(
        AtomSpace::AtomType::EVALUATION_LINK,
        [nested, empty, shared],
        AtomSpace::IndefiniteTruthValue.new(0.4, 0.9, 0.8)
      )
      root.attention_value = AtomSpace::AttentionValue.new(7, 11, true)

      storage = AtomSpace::FileStorageNode.new("roundtrip", path)
      storage.open.should be_true
      storage.store_atomspace(source).should be_true
      storage.close.should be_true

      reloaded_storage = AtomSpace::FileStorageNode.new("roundtrip-reopened", path)
      reloaded_storage.open.should be_true

      target = AtomSpace::AtomSpace.new
      reloaded_storage.load_atomspace(target).should be_true
      target.size.should eq(source.size)

      reloaded_shared = target.get_nodes_by_name(shared_name, AtomSpace::AtomType::CONCEPT_NODE).first
      reloaded_counted = target.get_nodes_by_name("counted", AtomSpace::AtomType::PREDICATE_NODE).first
      reloaded_bounded = target.get_nodes_by_name("bounded", AtomSpace::AtomType::SCHEMA_NODE).first
      reloaded_fuzzy = target.get_nodes_by_name("fuzzy", AtomSpace::AtomType::WORD_NODE).first
      reloaded_variable = target.get_nodes_by_name("$X", AtomSpace::AtomType::VARIABLE_NODE).first
      reloaded_number = target.get_nodes_by_name("42.25", AtomSpace::AtomType::NUMBER_NODE).first
      reloaded_root = target.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK).first.as(AtomSpace::Link)
      reloaded_nested = reloaded_root.outgoing[0].as(AtomSpace::Link)
      reloaded_empty = reloaded_root.outgoing[1].as(AtomSpace::Link)

      reloaded_root.outgoing.map(&.type).should eq([
        AtomSpace::AtomType::ORDERED_LINK,
        AtomSpace::AtomType::LIST_LINK,
        AtomSpace::AtomType::CONCEPT_NODE,
      ])
      reloaded_nested.outgoing.map(&.handle).should eq([
        reloaded_shared.handle,
        reloaded_counted.handle,
        reloaded_bounded.handle,
        reloaded_fuzzy.handle,
        reloaded_variable.handle,
        reloaded_number.handle,
      ])
      reloaded_root.outgoing[2].same?(reloaded_shared).should be_true
      reloaded_nested.outgoing[0].same?(reloaded_shared).should be_true
      reloaded_empty.arity.should eq(0)

      reloaded_shared.truth_value.should be_a(AtomSpace::SimpleTruthValue)
      reloaded_shared.truth_value.strength.should eq(0.91)
      reloaded_shared.attention_value.should eq(AtomSpace::AttentionValue.new(12, -5, true))
      reloaded_counted.truth_value.should be_a(AtomSpace::CountTruthValue)
      reloaded_counted.truth_value.as(AtomSpace::CountTruthValue).count.should eq(9.0)
      reloaded_nested.truth_value.should be_a(AtomSpace::CountTruthValue)
      reloaded_nested.truth_value.as(AtomSpace::CountTruthValue).count.should eq(4.0)
      reloaded_bounded.truth_value.should be_a(AtomSpace::IndefiniteTruthValue)
      reloaded_bounded.truth_value.as(AtomSpace::IndefiniteTruthValue).lower.should eq(0.2)
      reloaded_fuzzy.truth_value.should be_a(AtomSpace::FuzzyTruthValue)
      reloaded_fuzzy.truth_value.as(AtomSpace::FuzzyTruthValue).uncertainty.should eq(0.12)
      reloaded_variable.should be_a(AtomSpace::VariableNode)
      reloaded_number.should be_a(AtomSpace::NumberNode)
      reloaded_number.as(AtomSpace::NumberNode).value.should eq(42.25)
      reloaded_empty.truth_value.should be_a(AtomSpace::FuzzyTruthValue)
      reloaded_empty.truth_value.as(AtomSpace::FuzzyTruthValue).uncertainty.should eq(0.4)
      reloaded_root.truth_value.should be_a(AtomSpace::IndefiniteTruthValue)
      reloaded_root.truth_value.as(AtomSpace::IndefiniteTruthValue).lower.should eq(0.4)
      reloaded_root.truth_value.as(AtomSpace::IndefiniteTruthValue).upper.should eq(0.9)
      reloaded_root.attention_value.should eq(AtomSpace::AttentionValue.new(7, 11, true))

      reloaded_storage.fetch_atom(reloaded_root.handle).not_nil!.same?(reloaded_root).should be_true
      target.get_incoming(reloaded_shared).any? { |incoming| incoming.same?(reloaded_root) }.should be_true
      target.get_incoming(reloaded_shared).any? { |incoming| incoming.same?(reloaded_nested) }.should be_true
    ensure
      delete_file_storage_roundtrip_path(path)
    end
  end

  it "accepts the original bare simple-truth-value line syntax" do
    path = file_storage_roundtrip_path

    begin
      storage = AtomSpace::FileStorageNode.new("legacy", path)
      storage.open.should be_true
      File.write(path, <<-SCM)
        ; legacy FileStorage data may contain comments and line breaks
        (LISTLINK
          (CONCEPTNODE "legacy\\nname" (0.25, 0.75))
        )
      SCM

      target = AtomSpace::AtomSpace.new
      storage.load_atomspace(target).should be_true

      legacy = target.get_nodes_by_name("legacy\nname", AtomSpace::AtomType::CONCEPT_NODE).first
      legacy.truth_value.strength.should eq(0.25)
      legacy.truth_value.confidence.should eq(0.75)
      list = target.get_atoms_by_type(AtomSpace::AtomType::LIST_LINK).first.as(AtomSpace::Link)
      list.outgoing[0].same?(legacy).should be_true
    ensure
      delete_file_storage_roundtrip_path(path)
    end
  end

  it "decodes Unicode and string escapes from persisted Scheme" do
    path = file_storage_roundtrip_path

    begin
      storage = AtomSpace::FileStorageNode.new("unicode", path)
      storage.open.should be_true
      escaped_name = "\\u03bb\\n\\t\\\"\\\\"
      File.write(path, "(CONCEPTNODE \"#{escaped_name}\" (tv SimpleTruthValue 0.4 0.6))\n")

      target = AtomSpace::AtomSpace.new
      storage.load_atomspace(target).should be_true
      node = target.get_nodes_by_name("λ\n\t\"\\", AtomSpace::AtomType::CONCEPT_NODE).first
      node.truth_value.strength.should eq(0.4)
      node.truth_value.confidence.should eq(0.6)
    ensure
      delete_file_storage_roundtrip_path(path)
    end
  end

  it "rejects malformed trailing input without partially mutating the target AtomSpace" do
    path = file_storage_roundtrip_path

    begin
      storage = AtomSpace::FileStorageNode.new("malformed", path)
      storage.open.should be_true
      File.write(path, "(CONCEPTNODE \"valid-but-not-loaded\") trailing-garbage\n")

      target = AtomSpace::AtomSpace.new
      sentinel = target.add_concept_node("sentinel")
      storage.load_atomspace(target).should be_false
      target.size.should eq(1)
      target.get_nodes_by_name("sentinel", AtomSpace::AtomType::CONCEPT_NODE).first.same?(sentinel).should be_true
      target.get_nodes_by_name("valid-but-not-loaded", AtomSpace::AtomType::CONCEPT_NODE).should be_empty
    ensure
      delete_file_storage_roundtrip_path(path)
    end
  end

  it "rejects expressions that exceed the recursive nesting bound without mutation" do
    path = file_storage_roundtrip_path

    begin
      storage = AtomSpace::FileStorageNode.new("depth", path)
      storage.open.should be_true
      depth = AtomSpace::SchemeStorageParser::MAX_NESTING + 1
      nested = "(LISTLINK " * depth + "(CONCEPTNODE \"bottom\")" + ")" * depth
      File.write(path, nested)

      target = AtomSpace::AtomSpace.new
      sentinel = target.add_concept_node("sentinel")
      storage.load_atomspace(target).should be_false
      target.size.should eq(1)
      target.get_nodes_by_name("sentinel", AtomSpace::AtomType::CONCEPT_NODE).first.same?(sentinel).should be_true
    ensure
      delete_file_storage_roundtrip_path(path)
    end
  end

  it "rejects conflicting recursive snapshot metadata before AtomSpace merge can mutate the target" do
    path = file_storage_roundtrip_path

    begin
      storage = AtomSpace::FileStorageNode.new("conflict", path)
      storage.open.should be_true
      File.write(path, <<-SCM)
        (CONCEPTNODE "same-atom" (tv CountTruthValue 0.2 0.4 2.0))
        (LISTLINK (CONCEPTNODE "same-atom" (tv CountTruthValue 0.8 0.4 8.0)))
      SCM

      target = AtomSpace::AtomSpace.new
      sentinel = target.add_concept_node("sentinel")
      storage.load_atomspace(target).should be_false
      target.size.should eq(1)
      target.get_nodes_by_name("sentinel", AtomSpace::AtomType::CONCEPT_NODE).first.same?(sentinel).should be_true
      target.get_nodes_by_name("same-atom", AtomSpace::AtomType::CONCEPT_NODE).should be_empty
    ensure
      delete_file_storage_roundtrip_path(path)
    end
  end

  it "refuses to write graphs deeper than the parser can load" do
    path = file_storage_roundtrip_path

    begin
      source = AtomSpace::AtomSpace.new
      atom = AtomSpace::ConceptNode.new("bottom").as(AtomSpace::Atom)
      AtomSpace::SchemeStorageParser::MAX_NESTING.times do
        atom = AtomSpace::Link.new(AtomSpace::AtomType::LIST_LINK, [atom])
      end
      source.add_atom(atom)

      storage = AtomSpace::FileStorageNode.new("writer-depth", path)
      storage.open.should be_true
      storage.store_atomspace(source).should be_false
      File.read(path).should eq("")
    ensure
      delete_file_storage_roundtrip_path(path)
    end
  end
end
