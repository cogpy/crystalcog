require "spec"
require "http/server"
require "../../../src/integrations/platform/aphrodite_engine"

private def config(backend, **opts)
  AphroditeEngine::Config.new(backend: backend, model: opts[:model]? || "/models/pygmalion-2-7b.Q4_K_M.gguf",
    python: "/venv/bin/python", port: 2300)
end

describe AphroditeEngine::Engine do
  it "builds the launch command for each backend" do
    llama = AphroditeEngine::Engine.new(config(AphroditeEngine::Backend::LlamaCpp)).command
    llama[0..2].should eq(["/venv/bin/python", "-m", "llama_cpp.server"])
    llama.should contain("pygmalion-2-7b.Q4_K_M") # served name drops the .gguf suffix
    llama.should contain("2300")
    llama.join(" ").should contain("--chat_format pygmalion") # Metharme for Pygmalion models

    aphro = AphroditeEngine::Engine.new(config(AphroditeEngine::Backend::Aphrodite, model: "PygmalionAI/pygmalion-2-7b")).command
    aphro[0..2].should eq(["aphrodite", "run", "PygmalionAI/pygmalion-2-7b"])

    ENV["APHRODITE_JAX_SERVER"] = "/opt/crystalcog/bin/aphrodite_jax_server"
    begin
      jax = AphroditeEngine::Engine.new(config(AphroditeEngine::Backend::AphroditeJax, model: "Qwen/Qwen3-0.6B")).command
      jax[0..2].should eq(["/opt/crystalcog/bin/aphrodite_jax_server", "--model", "Qwen/Qwen3-0.6B"])
    ensure
      ENV.delete("APHRODITE_JAX_SERVER")
    end

    AphroditeEngine::Engine.new(config(AphroditeEngine::Backend::External)).command.should be_empty
  end

  it "defaults to the native Crystal engine" do
    AphroditeEngine::Config.new.backend.should eq(AphroditeEngine::Backend::AphroditeJax)
    AphroditeEngine::Config.from_env.backend.should eq(AphroditeEngine::Backend::AphroditeJax)
  end

  it "reads its configuration from the environment" do
    ENV["APHRODITE_URL"] = "http://127.0.0.1:9999/"
    begin
      cfg = AphroditeEngine::Config.from_env
      cfg.backend.should eq(AphroditeEngine::Backend::External)
      cfg.url.should eq("http://127.0.0.1:9999")
    ensure
      ENV.delete("APHRODITE_URL")
    end
  end

  it "attaches to an external server and binds agents to its model" do
    server = HTTP::Server.new do |ctx|
      ctx.response.content_type = "application/json"
      ctx.response.print %({"object":"list","data":[{"id":"pygmalion-2-7b"}]})
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    Fiber.yield
    begin
      cfg = AphroditeEngine::Config.new(backend: AphroditeEngine::Backend::External,
        external_url: "http://127.0.0.1:#{address.port}", startup_timeout: 5.seconds)
      engine = AphroditeEngine::Engine.new(cfg).start
      engine.models.should eq(["pygmalion-2-7b"])
      engine.agent.config.model_name.should eq("pygmalion-2-7b")
    ensure
      server.close
    end
  end

  it "fails fast when the backend process exits" do
    cfg = AphroditeEngine::Config.new(backend: AphroditeEngine::Backend::LlamaCpp, model: "/nonexistent.gguf",
      python: "false", port: 2399, startup_timeout: 30.seconds)
    # POSIX has `false` (exits 1); elsewhere it is missing and launch fails.
    expect_raises(AphroditeEngine::Error, /exited before becoming ready|failed to launch/) do
      AphroditeEngine::Engine.new(cfg).start
    end
  end
end
