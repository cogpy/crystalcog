# Simple integration test for CogServer HTTP API
# This tests the basic REST API functionality

require "../../src/cogserver/cogserver_main"
require "http/client"
require "json"

puts "Starting CogServer integration test..."

# Start the server on a test port
server = CogServer::Server.new("localhost", 17003, 18083)
server.start

# Give the server time to start
sleep 1

begin
  # Test the status endpoint
  puts "Testing status endpoint..."
  response = HTTP::Client.get("http://localhost:18083/status")
  
  if response.status_code == 200
    status = JSON.parse(response.body)
    puts "✓ Status endpoint working: #{status["running"]}"
    puts "  Server running: #{status["running"]}"
    puts "  Host: #{status["host"]}"
    puts "  Port: #{status["port"]}"
    puts "  AtomSpace size: #{status["atomspace_size"]}"
  else
    puts "✗ Status endpoint failed with code: #{response.status_code}"
  end
  
  # Test the atomspace endpoint
  puts "\nTesting atomspace endpoint..."
  response = HTTP::Client.get("http://localhost:18083/atomspace")
  
  if response.status_code == 200
    atomspace = JSON.parse(response.body)
    puts "✓ AtomSpace endpoint working"
    puts "  Size: #{atomspace["size"]}"
    puts "  Nodes: #{atomspace["nodes"]}"
    puts "  Links: #{atomspace["links"]}"
  else
    puts "✗ AtomSpace endpoint failed with code: #{response.status_code}"
  end
  
  # Test the atoms endpoint
  puts "\nTesting atoms endpoint..."
  response = HTTP::Client.get("http://localhost:18083/atoms")
  
  if response.status_code == 200
    atoms = JSON.parse(response.body)
    puts "✓ Atoms endpoint working"
    puts "  Atom count: #{atoms["count"]}"
  else
    puts "✗ Atoms endpoint failed with code: #{response.status_code}"
  end
  
  # Test the new endpoints
  puts "\nTesting sessions endpoint..."
  response = HTTP::Client.get("http://localhost:18083/sessions")
  
  if response.status_code == 200
    sessions = JSON.parse(response.body)
    puts "✓ Sessions endpoint working"
    puts "  Active sessions: #{sessions["active_sessions"]}"
  else
    puts "✗ Sessions endpoint failed with code: #{response.status_code}"
  end
  
  puts "\nTesting ping endpoint..."
  response = HTTP::Client.get("http://localhost:18083/ping")
  
  if response.status_code == 200
    ping = JSON.parse(response.body)
    puts "✓ Ping endpoint working: #{ping["status"]}"
  else
    puts "✗ Ping endpoint failed with code: #{response.status_code}"
  end
  
  puts "\nTesting version endpoint..."
  response = HTTP::Client.get("http://localhost:18083/version")
  
  if response.status_code == 200
    version = JSON.parse(response.body)
    puts "✓ Version endpoint working"
    puts "  Version: #{version["version"]}"
    puts "  API Version: #{version["api_version"]}"
  else
    puts "✗ Version endpoint failed with code: #{response.status_code}"
  end
  
  # Test telnet with command
  puts "\nTesting telnet with command..."
  response = HTTP::Client.get("http://localhost:17003?cmd=help")
  
  if response.status_code == 200 && response.body.includes?("Available commands")
    puts "✓ Telnet command processing working"
  else
    puts "✗ Telnet command failed with code: #{response.status_code}"
  end
  
  puts "\n✓ CogServer HTTP API integration test completed successfully!"
  
rescue ex
  puts "✗ Integration test failed: #{ex.message}"
ensure
  # Clean up
  puts "\nStopping server..."
  server.stop
end