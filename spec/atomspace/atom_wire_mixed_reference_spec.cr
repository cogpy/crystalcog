require "spec"
require "json"
require "../../src/atomspace/atomspace"
require "../../src/atomspace/atom_wire"

describe "AtomWire mixed receiver references" do
  it "decodes detached nested content and interns it without replacing receiver references" do
    receiver = AtomSpace::AtomSpace.new
    first = receiver.add_concept_node("receiver-first", AtomSpace::SimpleTruthValue.new(0.8, 0.6))
    second = receiver.add_concept_node("receiver-second", AtomSpace::SimpleTruthValue.new(0.3, 0.4))
    existing_link = receiver.add_inheritance_link(first, second, AtomSpace::SimpleTruthValue.new(0.7, 0.5))
    before_size = receiver.size
    before_atoms = receiver.get_all_atoms
    before_truth_values = before_atoms.map { |atom| {atom.truth_value, atom.truth_value.to_a} }
    before_incoming = before_atoms.map { |atom| receiver.get_incoming(atom).map(&.handle).sort }

    data = JSON.parse(%({"type":"LIST_LINK","outgoing":[
      #{first.handle},
      {"type":"CONCEPT_NODE","name":"inline-outer"},
      {"type":"LIST_LINK","outgoing":[
        #{second.handle},
        {"type":"CONCEPT_NODE","name":"inline-inner"},
        #{first.handle}, #{second.handle}, #{existing_link.handle}
      ]},
      #{second.handle}, #{first.handle}, #{existing_link.handle}
    ]}))
    resolver_calls = [] of AtomSpace::Handle
    decoded = AtomSpace::AtomWire.read(data) do |handle|
      resolver_calls << handle
      receiver.get_atom(handle)
    end

    resolver_calls.should eq([
      first.handle, second.handle, first.handle, second.handle, existing_link.handle,
      second.handle, first.handle, existing_link.handle,
    ])
    decoded.type.should eq(AtomSpace::AtomType::LIST_LINK)
    decoded.arity.should eq(6)
    decoded.outgoing[0].should be(first)
    outer_inline = decoded.outgoing[1]
    outer_inline.type.should eq(AtomSpace::AtomType::CONCEPT_NODE)
    outer_inline.name.should eq("inline-outer")
    nested = decoded.outgoing[2]
    nested.type.should eq(AtomSpace::AtomType::LIST_LINK)
    nested.arity.should eq(5)
    nested.outgoing[0].should be(second)
    inner_inline = nested.outgoing[1]
    inner_inline.type.should eq(AtomSpace::AtomType::CONCEPT_NODE)
    inner_inline.name.should eq("inline-inner")
    nested.outgoing[2].should be(first)
    nested.outgoing[3].should be(second)
    nested.outgoing[4].should be(existing_link)
    decoded.outgoing[3].should be(second)
    decoded.outgoing[4].should be(first)
    decoded.outgoing[5].should be(existing_link)

    # Detached allocation is not a receiver mutation, including its incoming index.
    [decoded, nested, outer_inline, inner_inline].each do |atom|
      atom.atomspace.should be_nil
      receiver.get_atom(atom.handle).should be_nil
    end
    receiver.size.should eq(before_size)
    receiver.get_all_atoms.map(&.handle).sort.should eq(before_atoms.map(&.handle).sort)
    before_atoms.each_with_index do |atom, index|
      receiver.get_atom(atom.handle).should be(atom)
      atom.atomspace.should be(receiver)
      atom.truth_value.should be(before_truth_values[index][0])
      atom.truth_value.to_a.should eq(before_truth_values[index][1])
      receiver.get_incoming(atom).map(&.handle).sort.should eq(before_incoming[index])
    end

    interned = AtomSpace::AtomWire.intern(decoded, receiver)
    stored_outer = receiver.get_nodes_by_name("inline-outer").first
    stored_inner = receiver.get_nodes_by_name("inline-inner").first
    stored_nested = interned.outgoing[2]
    receiver.size.should eq(before_size + 4) # Two inline nodes and two links.
    interned.type.should eq(AtomSpace::AtomType::LIST_LINK)
    stored_nested.type.should eq(AtomSpace::AtomType::LIST_LINK)
    interned.arity.should eq(6)
    stored_nested.arity.should eq(5)
    interned.outgoing.zip([first, stored_outer, stored_nested, second, first, existing_link]) do |actual, expected|
      actual.should be(expected)
    end
    stored_nested.outgoing.zip([second, stored_inner, first, second, existing_link]) do |actual, expected|
      actual.should be(expected)
    end
    # Intern rebuilds inline atoms; receiver-owned references take the early return.
    [interned, stored_nested, stored_outer, stored_inner].zip([decoded, nested, outer_inline, inner_inline]) do |stored, detached|
      stored.should_not be(detached)
      receiver.get_atom(stored.handle).should be(stored)
      stored.atomspace.should be(receiver)
      detached.atomspace.should be_nil
    end
    before_atoms.each_with_index do |atom, index|
      receiver.get_atom(atom.handle).should be(atom)
      atom.truth_value.should be(before_truth_values[index][0])
      atom.truth_value.to_a.should eq(before_truth_values[index][1])
    end
  end

  it "rejects an unknown nested handle after valid resolution without mutating the receiver" do
    receiver = AtomSpace::AtomSpace.new
    first = receiver.add_concept_node("receiver-first", AtomSpace::SimpleTruthValue.new(0.8, 0.6))
    second = receiver.add_concept_node("receiver-second", AtomSpace::SimpleTruthValue.new(0.3, 0.4))
    receiver.add_inheritance_link(first, second, AtomSpace::SimpleTruthValue.new(0.7, 0.5))
    before_size = receiver.size
    before_atoms = receiver.get_all_atoms
    before_truth_values = before_atoms.map { |atom| {atom.truth_value, atom.truth_value.to_a} }
    before_incoming = before_atoms.map { |atom| receiver.get_incoming(atom).map(&.handle).sort }
    unknown = 9_876_543_210_u64
    receiver.get_atom(unknown).should be_nil
    data = JSON.parse(%({"type":"LIST_LINK","outgoing":[
      #{first.handle},
      {"type":"CONCEPT_NODE","name":"uncommitted-outer"},
      {"type":"LIST_LINK","outgoing":[
        #{second.handle},
        {"type":"CONCEPT_NODE","name":"uncommitted-inner"},
        #{first.handle}, #{unknown}, #{second.handle}
      ]}
    ]}))
    resolver_calls = [] of AtomSpace::Handle

    error = expect_raises(ArgumentError) do
      AtomSpace::AtomWire.read(data) do |handle|
        resolver_calls << handle
        receiver.get_atom(handle)
      end
    end
    error.message.should eq("Unknown outgoing handle: #{unknown}")
    resolver_calls.should eq([first.handle, second.handle, first.handle, unknown])

    # No partial graph is interned after a failed read.
    receiver.size.should eq(before_size)
    receiver.get_all_atoms.map(&.handle).sort.should eq(before_atoms.map(&.handle).sort)
    before_atoms.each_with_index do |atom, index|
      receiver.get_atom(atom.handle).should be(atom)
      atom.atomspace.should be(receiver)
      atom.truth_value.should be(before_truth_values[index][0])
      atom.truth_value.to_a.should eq(before_truth_values[index][1])
      receiver.get_incoming(atom).map(&.handle).sort.should eq(before_incoming[index])
    end
    receiver.get_nodes_by_name("uncommitted-outer").should be_empty
    receiver.get_nodes_by_name("uncommitted-inner").should be_empty
  end
end
