require "spec"
require "http/server"
require "socket"
require "../../../src/integrations/platform/stack"

describe PygmalionPlatform::Stack do
  it "stops components started before a later startup failure" do
    engine_server = HTTP::Server.new do |ctx|
      ctx.response.content_type = "application/json"
      ctx.response.print(%({"data":[{"id":"test"}]}))
    end
    engine_address = engine_server.bind_tcp("127.0.0.1", 0)
    spawn { engine_server.listen }
    occupied = TCPServer.new("127.0.0.1", 0)
    Fiber.yield

    config = AphroditeEngine::Config.new(
      backend: AphroditeEngine::Backend::External,
      external_url: "http://127.0.0.1:#{engine_address.port}"
    )
    stack = PygmalionPlatform::Stack.new(
      engine_config: config,
      paphos_port: 0,
      galatea_port: occupied.local_address.as(Socket::IPAddress).port
    )

    expect_raises(Socket::BindError) { stack.start }
    expect_raises(IO::Error | Socket::Error) do
      HTTP::Client.get(stack.paphos.url).body
    end
  ensure
    occupied.try(&.close)
    engine_server.try(&.close)
  end
end
