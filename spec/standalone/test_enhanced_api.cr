# Enhanced integration test for CogServer with persistence endpoints
# Tests the new storage-related HTTP API endpoints

require "../../src/cogserver/cogserver_main"
require "http/client"
require "json"
require "file_utils"

puts "Starting CogServer Enhanced API integration test..."

# Start the server on test ports
server = CogServer::Server.new("localhost", 17005, 18085)
server.start

# Give the server time to start
sleep 2

begin
  base_url = "http://localhost:18085"
  
  # Test basic functionality first
  puts "=== Basic API Tests ==="
  
  # Test ping
  response = HTTP::Client.get("#{base_url}/ping")
  if response.status_code == 200
    puts "✓ Ping endpoint working"
  else
    puts "✗ Ping endpoint failed: #{response.status_code}"
    exit(1)
  end
  
  # Test version
  response = HTTP::Client.get("#{base_url}/version")
  if response.status_code == 200
    version = JSON.parse(response.body)
    puts "✓ Version endpoint working: #{version["version"]}"
  else
    puts "✗ Version endpoint failed: #{response.status_code}"
    exit(1)
  end
  
  # Test atomspace status
  response = HTTP::Client.get("#{base_url}/atomspace")
  if response.status_code == 200
    atomspace = JSON.parse(response.body)
    puts "✓ AtomSpace endpoint working: #{atomspace["size"]} atoms"
  else
    puts "✗ AtomSpace endpoint failed: #{response.status_code}"
    exit(1)
  end
  
  puts
  puts "=== Storage API Tests ==="
  
  # Test storage listing (should be empty initially)
  puts "Testing storage listing..."
  response = HTTP::Client.get("#{base_url}/storage")
  
  if response.status_code == 200
    storage_data = JSON.parse(response.body)
    puts "✓ Storage endpoint working"
    puts "  Storage count: #{storage_data["storage_count"]}"
    initial_storage_count = storage_data["storage_count"].as_i
  else
    puts "✗ Storage endpoint failed: #{response.status_code}"
    exit(1)
  end
  
  # Test attaching file storage
  puts "\nTesting file storage attachment..."
  test_dir = "/tmp/crystalcog_test_api"
  Dir.mkdir_p(test_dir)
  
  attach_data = {
    "type" => "file",
    "name" => "test_file_storage",
    "path" => "#{test_dir}/api_test.scm"
  }
  
  headers = HTTP::Headers{"Content-Type" => "application/json"}
  response = HTTP::Client.post("#{base_url}/storage/attach", headers: headers, body: attach_data.to_json)
  
  if response.status_code == 201
    result = JSON.parse(response.body)
    puts "✓ File storage attached: #{result["storage"]["name"]}"
    puts "  Connected: #{result["storage"]["connected"]}"
  else
    puts "✗ Failed to attach file storage: #{response.status_code}"
    puts "  Response: #{response.body}"
    exit(1)
  end
  
  # Test attaching SQLite storage (may fail if SQLite not available)
  puts "\nTesting SQLite storage attachment..."
  attach_data = {
    "type" => "sqlite",
    "name" => "test_sqlite_storage", 
    "path" => "#{test_dir}/api_test.db"
  }
  
  response = HTTP::Client.post("#{base_url}/storage/attach", headers: headers, body: attach_data.to_json)
  
  sqlite_attached = false
  if response.status_code == 201
    result = JSON.parse(response.body)
    puts "✓ SQLite storage attached: #{result["storage"]["name"]}"
    sqlite_attached = true
  else
    puts "⚠ SQLite storage attachment failed (expected if SQLite not available): #{response.status_code}"
  end
  
  # Verify storage list updated
  puts "\nVerifying storage list updated..."
  response = HTTP::Client.get("#{base_url}/storage")
  
  if response.status_code == 200
    storage_data = JSON.parse(response.body)
    expected_count = initial_storage_count + 1 + (sqlite_attached ? 1 : 0)
    if storage_data["storage_count"].as_i == expected_count
      puts "✓ Storage count updated correctly: #{storage_data["storage_count"]}"
      storage_data["storages"].as_a.each do |storage|
        puts "  - #{storage["name"]} (#{storage["type"]}): #{storage["connected"]}"
      end
    else
      puts "✗ Storage count mismatch: expected #{expected_count}, got #{storage_data["storage_count"]}"
    end
  else
    puts "✗ Failed to get updated storage list: #{response.status_code}"
  end
  
  # Add some test atoms to save
  puts "\nAdding test atoms..."
  test_atoms = [
    {
      "type" => "CONCEPT_NODE",
      "name" => "test_concept_api"
    },
    {
      "type" => "PREDICATE_NODE", 
      "name" => "test_predicate_api"
    }
  ]
  
  test_atoms.each do |atom_data|
    response = HTTP::Client.post("#{base_url}/atoms", headers: headers, body: atom_data.to_json)
    if response.status_code == 201
      puts "✓ Added atom: #{atom_data["name"]}"
    else
      puts "⚠ Failed to add atom #{atom_data["name"]}: #{response.status_code}"
    end
  end
  
  # Test saving to all storages
  puts "\nTesting save to all storages..."
  response = HTTP::Client.post("#{base_url}/storage/save", headers: headers, body: "{}".to_json)
  
  if response.status_code == 200
    result = JSON.parse(response.body)
    puts "✓ Save to all storages: #{result["message"]}"
    puts "  Success: #{result["success"]}"
  else
    puts "✗ Failed to save to all storages: #{response.status_code}"
    puts "  Response: #{response.body}"
  end
  
  # Test saving to specific storage
  puts "\nTesting save to specific storage..."
  save_data = {"storage" => "test_file_storage"}
  response = HTTP::Client.post("#{base_url}/storage/save", headers: headers, body: save_data.to_json)
  
  if response.status_code == 200
    result = JSON.parse(response.body)
    puts "✓ Save to specific storage: #{result["message"]}"
  else
    puts "✗ Failed to save to specific storage: #{response.status_code}"
  end
  
  # Verify file was created
  test_file = "#{test_dir}/api_test.scm"
  if File.exists?(test_file) && File.size(test_file) > 0
    puts "✓ Storage file created: #{File.size(test_file)} bytes"
  else
    puts "⚠ Storage file not found or empty"
  end
  
  # Test loading from specific storage
  puts "\nTesting load from specific storage..."
  load_data = {"storage" => "test_file_storage"}
  response = HTTP::Client.post("#{base_url}/storage/load", headers: headers, body: load_data.to_json)
  
  if response.status_code == 200
    result = JSON.parse(response.body)
    puts "✓ Load from specific storage: #{result["message"]}"
    puts "  AtomSpace size after load: #{result["atomspace_size"]}"
  else
    puts "✗ Failed to load from specific storage: #{response.status_code}"
  end
  
  # Test loading from all storages
  puts "\nTesting load from all storages..."
  response = HTTP::Client.post("#{base_url}/storage/load", headers: headers, body: "{}".to_json)
  
  if response.status_code == 200
    result = JSON.parse(response.body)
    puts "✓ Load from all storages: #{result["message"]}"
    puts "  AtomSpace size after load: #{result["atomspace_size"]}"
  else
    puts "✗ Failed to load from all storages: #{response.status_code}"
  end
  
  # Test detaching storage
  puts "\nTesting storage detachment..."
  detach_data = {"name" => "test_file_storage"}
  response = HTTP::Client.post("#{base_url}/storage/detach", headers: headers, body: detach_data.to_json)
  
  if response.status_code == 200
    result = JSON.parse(response.body)
    puts "✓ Storage detached: #{result["message"]}"
  else
    puts "✗ Failed to detach storage: #{response.status_code}"
  end
  
  # Verify storage list updated after detachment
  response = HTTP::Client.get("#{base_url}/storage")
  if response.status_code == 200
    storage_data = JSON.parse(response.body)
    puts "✓ Storage count after detachment: #{storage_data["storage_count"]}"
  end
  
  # Test error handling - try to attach invalid storage
  puts "\nTesting error handling..."
  invalid_data = {
    "type" => "invalid_type",
    "name" => "invalid_storage"
  }
  
  response = HTTP::Client.post("#{base_url}/storage/attach", headers: headers, body: invalid_data.to_json)
  
  if response.status_code == 400
    puts "✓ Invalid storage type properly rejected"
  else
    puts "✗ Invalid storage type not rejected: #{response.status_code}"
  end
  
  # Test trying to save/load to non-existent storage
  nonexistent_data = {"storage" => "nonexistent_storage"}
  response = HTTP::Client.post("#{base_url}/storage/save", headers: headers, body: nonexistent_data.to_json)
  
  if response.status_code == 404
    puts "✓ Non-existent storage properly rejected for save"
  else
    puts "✗ Non-existent storage not rejected for save: #{response.status_code}"
  end
  
  puts
  puts "=== Network Storage Test ==="
  
  # Test CogStorageNode attachment (should fail since no external server)
  puts "Testing network storage attachment..."
  network_data = {
    "type" => "cog",
    "name" => "test_network_storage",
    "host" => "localhost",
    "port" => 99999  # Non-existent port
  }
  
  response = HTTP::Client.post("#{base_url}/storage/attach", headers: headers, body: network_data.to_json)
  
  if response.status_code == 201
    result = JSON.parse(response.body)
    if result["storage"]["connected"] == false
      puts "✓ Network storage attached but not connected (expected)"
    else
      puts "? Network storage connected unexpectedly"
    end
  else
    puts "⚠ Network storage attachment failed: #{response.status_code}"
  end
  
  puts
  puts "✓ Enhanced CogServer API integration test completed successfully!"
  
  # Cleanup
  FileUtils.rm_rf(test_dir) if Dir.exists?(test_dir)
  
rescue ex
  puts "✗ Integration test failed: #{ex.message}"
  puts ex.backtrace.join("\n")
  exit(1)
ensure
  # Clean up
  puts "\nStopping server..."
  server.stop
end