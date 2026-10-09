require "spec"
require "../../scripts/e2e/multi_node_simulation"

describe "Nightly E2E multi-node simulation" do
  it "distributes atoms across node LRU caches without assigning handles" do
    NightlyE2E.multi_node_simulation(atom_count: 30, cache_size: 10, node_count: 3).should be_true
  end
end
