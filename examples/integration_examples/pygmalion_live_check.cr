# Pygmalion live check - exercises the Pygmalion integration against a real
# OpenAI-compatible backend (Aphrodite, vLLM, llama.cpp server, ...).
#
#   PYGMALION_API_URL=http://localhost:2242 PYGMALION_MODEL=pygmalion-2-7b \
#     crystal run examples/integration_examples/pygmalion_live_check.cr
#
# Optional: PYGMALION_API_KEY. Exits non-zero if any required check fails;
# endpoints a backend may not implement (health, tokenize) are reported only.

require "../../src/integrations/integration"
require "../../src/atomspace/atomspace"

CogUtil::Logger.set_level(CogUtil::LogLevel::WARN)

failures = 0
check = ->(name : String, required : Bool, block : -> String) do
  begin
    detail = block.call
    puts "PASS  #{name}: #{detail}"
  rescue ex
    if required
      failures += 1
      puts "FAIL  #{name}: #{ex.class}: #{ex.message}"
    else
      puts "SKIP  #{name}: #{ex.message}"
    end
  end
end

abort "Set PYGMALION_API_URL" unless ENV["PYGMALION_API_URL"]?

agent = PygmalionAgent.create_default_agent
agent.config.default_max_tokens = (ENV["PYGMALION_MAX_TOKENS"]? || "48").to_i
agent.config.api.timeout = 600.seconds
agent.config.api.max_retries = 1
space = AtomSpace::AtomSpace.new
agent.attach_atomspace(space)

puts "Backend: #{agent.config.api.base_url}  model: #{agent.config.model_name}"

check.call("models", true, -> {
  raise "initialize_agent returned false" unless agent.initialize_agent
  agent.models.join(", ")
})

check.call("health", false, -> {
  h = agent.health
  raise "status=#{h.status}" unless h.healthy?
  h.status
})

check.call("chat", true, -> {
  reply = agent.chat("Hello! Who are you, in one sentence?")
  raise "empty reply" if reply.strip.empty?
  reply.strip.inspect
})

check.call("chat_stream", true, -> {
  pieces = 0
  text = agent.chat_stream("Name three colours.") { |_| pieces += 1 }
  raise "no streamed text" if text.strip.empty?
  "#{pieces} chunks: #{text.strip.inspect}"
})

check.call("complete", true, -> {
  text = agent.complete("The capital of France is", 8)
  raise "empty completion" if text.strip.empty?
  text.strip.inspect
})

check.call("atomspace", true, -> {
  raise "no atoms stored" if space.size == 0
  "#{space.size} atoms; context=#{agent.get_cognitive_context.first(5)}"
})

check.call("tokenize", false, -> { "#{agent.tokenize("hello world").count} tokens" })

check.call("roleplay", true, -> {
  character = PygmalionAgent::CharacterConfig.new(name: "Galatea", personality: "warm, curious sculpture come to life")
  rp = PygmalionAgent.create_roleplay_agent(agent.config.api.base_url, character)
  rp.config.model_name = agent.config.model_name
  rp.config.api.api_key = agent.config.api.api_key
  rp.config.api.timeout = 600.seconds
  rp.config.default_max_tokens = agent.config.default_max_tokens
  # Sampled replies can legitimately be empty when the model opens with a
  # stop sequence ("\nUser:"), so allow a few attempts.
  reply = ""
  attempts = 0
  while reply.strip.empty? && attempts < 3
    attempts += 1
    rp.clear_history
    reply = rp.chat("Hi Galatea, how do you feel today?")
  end
  raise "empty reply after #{attempts} attempts" if reply.strip.empty?
  "#{reply.strip.inspect} (attempt #{attempts})"
})

check.call("cognitive pipeline", true, -> {
  manager = CrystalCogIntegration::Manager.new
  manager.initialize_all_integrations(AtomSpace::AtomSpace.new)
  manager.pygmalion_agent = agent
  result = manager.execute_cognitive_pipeline("What links reasoning and intelligence?")
  response = result["pygmalion_response"]? || raise "no pygmalion_response (status=#{result["pygmalion_status"]?})"
  response.strip.inspect
})

puts failures == 0 ? "\nAll required checks passed." : "\n#{failures} required check(s) failed."
exit(failures == 0 ? 0 : 1)
