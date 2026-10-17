require "spec"
require "../../src/atomspace/atomspace"

describe AtomSpace::AtomSpace do
  describe "reverse adjacency index" do
    it "deduplicates repeated outgoing targets and duplicate links" do
      space = AtomSpace::AtomSpace.new
      node = space.add_concept_node("target")
      link = space.add_list_link([node, node])
      duplicate = space.add_list_link([node, node])
      duplicate.handle.should eq(link.handle)
      space.get_incoming(node).map(&.handle).should eq([link.handle])
    end

    it "maintains the index when links are removed and the space is cleared" do
      space = AtomSpace::AtomSpace.new
      child = space.add_concept_node("child")
      parent = space.add_concept_node("parent")
      first = space.add_inheritance_link(child, parent)
      second = space.add_list_link([child, parent])
      space.remove_atom(first).should be_true
      space.get_incoming(child).map(&.handle).should eq([second.handle])
      space.remove_atom(child).should be_false
      space.remove_atom(second).should be_true
      space.get_incoming(child).should be_empty
      space.remove_atom(child).should be_true
      space.clear
      space.get_incoming(parent).should be_empty
      space.link_count.should eq(0)
    end

    it "indexes unresolved lazy links without materializing outgoing atoms" do
      space = AtomSpace::AtomSpace.new
      node = space.add_concept_node("lazy-target")
      lazy = AtomSpace::LazyLink.new(AtomSpace::AtomType::LIST_LINK, [node.handle])
      space.add_atom(lazy)
      lazy.loaded?.should be_false
      space.get_incoming(node).map(&.handle).should eq([lazy.handle])
      space.remove_atom(node).should be_false
      eager = space.add_list_link([node])
      eager.handle.should eq(lazy.handle)
      space.size.should eq(2)
      space.remove_atom(lazy).should be_true
      space.get_incoming(node).should be_empty
      space.remove_atom(node).should be_true
      lazy.loaded?.should be_false
    end

    it "protects links referenced by other links" do
      space = AtomSpace::AtomSpace.new
      node = space.add_concept_node("nested")
      inner = space.add_list_link([node])
      outer = space.add_list_link([inner])
      space.remove_atom(inner).should be_false
      space.remove_atom(outer).should be_true
      space.remove_atom(inner).should be_true
      space.get_incoming(node).should be_empty
    end
  end

  describe "re-entrant observers" do
    it "allows callbacks to query and mutate the same AtomSpace" do
      space = AtomSpace::AtomSpace.new
      observed = [] of AtomSpace::Handle
      observer = ->(event : AtomSpace::AtomSpaceEvent, atom : AtomSpace::Atom) {
        if event == AtomSpace::AtomSpaceEvent::ATOM_ADDED
          space.get_atom(atom.handle).should_not be_nil
          observed << atom.handle
          space.add_concept_node("derived") if atom.name == "source"
        end
      }
      space.add_observer(observer)
      space.add_concept_node("source")
      space.size.should eq(2)
      observed.size.should eq(2)
    end

    it "uses a registration snapshot while callbacks unsubscribe" do
      space = AtomSpace::AtomSpace.new
      calls = [] of String
      second = ->(event : AtomSpace::AtomSpaceEvent, atom : AtomSpace::Atom) {
        calls << "second"
      }
      first = ->(event : AtomSpace::AtomSpaceEvent, atom : AtomSpace::Atom) {
        calls << "first"
        space.remove_observer(second)
        nil
      }
      space.add_observer(first)
      space.add_observer(second)
      space.add_concept_node("one")
      space.add_concept_node("two")
      calls.should eq(["first", "second", "first"])
    end

    it "publishes removals after updating all indexes" do
      space = AtomSpace::AtomSpace.new
      node = space.add_concept_node("removed")
      removed = false
      observer = ->(event : AtomSpace::AtomSpaceEvent, atom : AtomSpace::Atom) {
        if event == AtomSpace::AtomSpaceEvent::ATOM_REMOVED
          space.contains?(atom).should be_false
          space.get_nodes_by_name(atom.name).should be_empty
          removed = true
        end
      }
      space.add_observer(observer)
      space.remove_atom(node).should be_true
      removed.should be_true
    end
  end
end

describe "AtomSpace topology ownership and notification ordering" do
  it "owns eager and lazy topology independently of constructor and getter arrays" do
    space = AtomSpace::AtomSpace.new
    node = space.add_concept_node("owned-target")
    handles = [node.handle]
    lazy = AtomSpace::LazyLink.new(AtomSpace::AtomType::LIST_LINK, handles)
    space.add_atom(lazy)
    handles.clear
    lazy.outgoing_handles.clear
    lazy.outgoing_handles.should eq([node.handle])
    space.remove_atom(lazy).should be_true
    space.remove_atom(node).should be_true

    node = space.add_concept_node("eager-target")
    outgoing = [node]
    link = AtomSpace::ListLink.new(outgoing)
    space.add_atom(link)
    outgoing.clear
    link.outgoing.clear
    link.outgoing.map(&.handle).should eq([node.handle])
    space.remove_atom(link).should be_true
    space.get_incoming(node).should be_empty
    space.remove_atom(node).should be_true
  end

  it "delivers additions to every observer before nested removals" do
    space = AtomSpace::AtomSpace.new
    notifications = [] of String
    first = ->(event : AtomSpace::AtomSpaceEvent, atom : AtomSpace::Atom) {
      notifications << "first:#{event}"
      space.remove_atom(atom) if event == AtomSpace::AtomSpaceEvent::ATOM_ADDED
      nil
    }
    second = ->(event : AtomSpace::AtomSpaceEvent, atom : AtomSpace::Atom) {
      notifications << "second:#{event}"
    }
    space.add_observer(first)
    space.add_observer(second)
    space.add_concept_node("transient")
    notifications.should eq([
      "first:ATOM_ADDED", "second:ATOM_ADDED",
      "first:ATOM_REMOVED", "second:ATOM_REMOVED",
    ])
    space.size.should eq(0)
  end
end
