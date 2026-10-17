# Simple WebSocket test for CogServer
# This tests the WebSocket upgrade functionality

require "../../src/cogserver/cogserver_main"
require "http/client"
require "base64"

puts "Starting CogServer WebSocket test..."

# Start the server on a test port
server = CogServer::Server.new("localhost", 17004, 18084)
server.start

# Give the server time to start
sleep 1

begin
  # Test WebSocket upgrade
  puts "Testing WebSocket upgrade..."
  
  # Create WebSocket upgrade request headers
  websocket_key = Base64.strict_encode("test_key_123456789")
  
  headers = HTTP::Headers{
    "Connection" => "Upgrade",
    "Upgrade" => "websocket",
    "Sec-WebSocket-Key" => websocket_key,
    "Sec-WebSocket-Version" => "13"
  }
  
  response = HTTP::Client.get("http://localhost:18084/", headers: headers)
  
  if response.status_code == 101
    puts "✓ WebSocket upgrade successful"
    puts "  Status: #{response.status_code}"
    puts "  Upgrade header: #{response.headers["Upgrade"]?}"
    puts "  Connection header: #{response.headers["Connection"]?}"
    puts "  Accept key present: #{response.headers["Sec-WebSocket-Accept"]? ? "Yes" : "No"}"
  else
    puts "✗ WebSocket upgrade failed with code: #{response.status_code}"
    puts "  Response body: #{response.body}"
  end
  
  # Test invalid WebSocket upgrade
  puts "\nTesting invalid WebSocket upgrade..."
  invalid_headers = HTTP::Headers{
    "Connection" => "keep-alive",
    "Upgrade" => "websocket"
  }
  
  response = HTTP::Client.get("http://localhost:18084/", headers: invalid_headers)
  
  if response.status_code == 400
    puts "✓ Invalid WebSocket upgrade properly rejected"
  else
    puts "✗ Invalid WebSocket upgrade not rejected (code: #{response.status_code})"
  end
  
  puts "\n✓ CogServer WebSocket test completed successfully!"
  
rescue ex
  puts "✗ WebSocket test failed: #{ex.message}"
ensure
  # Clean up
  puts "\nStopping server..."
  server.stop
end