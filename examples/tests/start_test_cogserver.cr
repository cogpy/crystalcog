# Start a CogServer for testing the bash integration script
require "../../src/cogserver/cogserver"
# This script should be run from the repository root or via crystal run from any location
# The relative path is resolved from this file's location (examples/tests/)
require "../../src/cogserver/cogserver_main"

puts "Starting CogServer for bash integration test..."

# Start the server on the ports expected by the bash script
server = CogServer::Server.new("localhost", 17001, 18080)

# Handle shutdown gracefully
Signal::INT.trap do
  puts "\nShutting down CogServer..."
  server.stop
  exit(0)
end

Signal::TERM.trap do
  puts "\nShutting down CogServer..."
  server.stop
  exit(0)
end

server.start

puts "CogServer is running for integration test."
puts "Telnet interface: telnet localhost 17001"
puts "HTTP API: http://localhost:18080"
puts "Status: http://localhost:18080/status"
puts "Press Ctrl+C to stop."

# Keep the main thread alive
while server.running?
  sleep 1
end