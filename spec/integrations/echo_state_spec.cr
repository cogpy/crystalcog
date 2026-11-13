require "spec"
require "../../src/integrations/pygmalion_agent"

private def small_reservoir(seed = 42)
  PygmalionAgent::EchoStateReservoir.new(120, 0.9, 0.1, 1.0, 0.3, seed)
end

describe PygmalionAgent::EchoStateReservoir do
  it "counts rooted trees (A000081) and factors sizes into primes" do
    PygmalionAgent::EchoStateReservoir.rooted_trees(10).should eq([1, 1, 2, 4, 9, 20, 48, 115, 286, 719])
    PygmalionAgent::EchoStateReservoir.rooted_trees(0).should be_empty
    PygmalionAgent::EchoStateReservoir.prime_factors(1000).should eq([2, 2, 2, 5, 5, 5])
    PygmalionAgent::EchoStateReservoir.prime_factors(97).should eq([97])
    PygmalionAgent::EchoStateReservoir.prime_factors(1).should be_empty
  end

  it "encodes words deterministically, with similar spellings close together" do
    encode = ->(w : String) { PygmalionAgent::EchoStateReservoir.encode(w) }
    similarity = ->(a : String, b : String) { PygmalionAgent::EchoStateReservoir.similarity(encode.call(a), encode.call(b)) }
    encode.call("reasoning").should eq(encode.call("reasoning"))
    Math.sqrt(encode.call("reasoning").sum { |v| v * v }).should be_close(1.0, 1e-9)
    similarity.call("reasoning", "reasoned").should be > similarity.call("reasoning", "umbrella")
    # FNV-1a of "a", a published test vector: the hash does not depend on the process.
    PygmalionAgent::EchoStateReservoir.fnv1a("a").should eq(0xaf63dc4c8601ec8c_u64)
    PygmalionAgent::EchoStateReservoir.words("Hello, wörld! It's 42.").should eq(["hello", "wörld", "it's", "42"])
  end

  it "is deterministic for a seed and bounded" do
    a = small_reservoir
    b = small_reservoir
    other = small_reservoir(7)
    text = "the cat sat on the mat and thought about graphs"
    a.feed(text).should eq(b.feed(text))
    other.feed(text).should_not eq(a.state)
    a.steps.should eq(10)
    a.state.all? { |v| v.abs < 1.0 }.should be_true
    a.state.any? { |v| v != 0.0 }.should be_true
    a.gestalt.size.should eq(6)
    a.reset
    a.state.all?(&.zero?).should be_true
  end

  it "has the echo state property: old inputs fade, recent ones dominate" do
    one = small_reservoir
    two = small_reservoir
    one.feed("quantum chromodynamics lattice gauge")
    two.feed("gardening tomatoes compost seedlings")
    before = PygmalionAgent::EchoStateReservoir.similarity(one.state, two.state)
    shared = Array.new(60) { |i| "word#{i % 7}" }.join(" ")
    one.feed(shared)
    two.feed(shared)
    after = PygmalionAgent::EchoStateReservoir.similarity(one.state, two.state)
    after.should be > 0.999
    after.should be > before

    # With no input the state decays: the spectral radius is below one.
    quiet = small_reservoir
    quiet.feed("something to remember")
    start = Math.sqrt(quiet.state.sum { |v| v * v })
    200.times { quiet.step(Array.new(PygmalionAgent::EchoStateReservoir::INPUT_DIM, 0.0)) }
    Math.sqrt(quiet.state.sum { |v| v * v }).should be < start * 0.01
  end
end

describe "PygmalionAgent tensor signatures" do
  it "reports the reservoir state after messages are processed" do
    config = PygmalionAgent::Config.new
    config.echo_state = PygmalionAgent::EchoStateConfig.new(reservoir_size: 60)
    agent = PygmalionAgent::Agent.new(config)

    idle = agent.compute_tensor_signatures
    idle["prime_factors"].should eq([2.0, 2.0, 3.0, 5.0])
    idle["rooted_trees"].should eq([1.0, 1.0, 2.0, 4.0])
    idle["reservoir_state"].size.should eq(60)
    idle["reservoir_state"].all?(&.zero?).should be_true

    agent.build_request("Tell me about hypergraphs and attention")
    active = agent.compute_tensor_signatures
    active["reservoir_state"].any? { |v| v != 0.0 }.should be_true
    active["gestalt_state"].size.should eq(6)
    active["gestalt_state"][2].should be > 0.0

    agent.echo_resonance("hypergraphs and attention").should be > agent.echo_resonance("marmalade sandwiches")

    config.echo_state.tensor_signatures = false
    agent.compute_tensor_signatures["reservoir_state"].should be_empty
  end

  it "leaves the reservoir alone when cognitive binding is off" do
    config = PygmalionAgent::Config.new
    config.echo_state = PygmalionAgent::EchoStateConfig.new(reservoir_size: 30, cognitive_binding: false)
    agent = PygmalionAgent::Agent.new(config)
    agent.build_request("hello there")
    agent.compute_tensor_signatures["reservoir_state"].all?(&.zero?).should be_true
  end
end
