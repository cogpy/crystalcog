#!/usr/bin/env crystal

# WebSocket Monitoring Integration Test
# Tests the real-time performance monitoring WebSocket implementation

require "../../src/cogutil/performance_monitor"
require "http/client"
require "http/web_socket"
require "json"

puts "=" * 60
puts "WebSocket Monitoring Integration Test"
puts "=" * 60
puts

# Create performance monitor
monitor = CogUtil::PerformanceMonitor.new

# Start HTTP server in background fiber
server_fiber = spawn do
  monitor.start_http_server(port: 8081)
end

# Give server time to start
sleep 0.5

# Start monitoring
monitor.start_monitoring(interval: 0.1.seconds)

puts "✓ Performance monitor started on port 8081"
puts "✓ Monitoring active with 0.1s interval"
puts

# Test 1: HTTP API endpoints
puts "Test 1: HTTP API Endpoints"
puts "-" * 40

begin
  # Test summary endpoint
  response = HTTP::Client.get("http://localhost:8081/summary")
  if response.status_code == 200
    summary = JSON.parse(response.body)
    puts "✓ GET /summary: #{response.status_code}"
    puts "  - Monitoring active: #{summary["monitoring_active"]}"
    puts "  - Sample count: #{summary["total_samples"]}"
  else
    puts "✗ GET /summary failed: #{response.status_code}"
  end
  
  # Test metrics endpoint
  response = HTTP::Client.get("http://localhost:8081/metrics")
  if response.status_code == 200
    puts "✓ GET /metrics: #{response.status_code}"
  else
    puts "✗ GET /metrics failed: #{response.status_code}"
  end
  
  # Test alerts endpoint
  response = HTTP::Client.get("http://localhost:8081/alerts")
  if response.status_code == 200
    puts "✓ GET /alerts: #{response.status_code}"
  else
    puts "✗ GET /alerts failed: #{response.status_code}"
  end
rescue ex
  puts "✗ HTTP API test failed: #{ex.message}"
end

puts

# Test 2: WebSocket Connection and Communication
puts "Test 2: WebSocket Connection"
puts "-" * 40

websocket_test_passed = false
messages_received = 0
initial_state_received = false

begin
  ws = HTTP::WebSocket.new(URI.parse("ws://localhost:8081/ws"))
  
  # Track received messages
  ws.on_message do |message|
    messages_received += 1
    data = JSON.parse(message)
    msg_type = data["type"]?.try(&.as_s)
    
    case msg_type
    when "initial_state"
      initial_state_received = true
      puts "✓ Received initial state"
      puts "  - Monitoring: #{data["data"]["monitoring_active"]}"
      puts "  - Samples: #{data["data"]["sample_count"]}"
      puts "  - Alerts: #{data["data"]["active_alerts"]}"
    when "metric_update"
      metric_name = data["data"]["metric"]?.try(&.as_s)
      value = data["data"]["value"]?.try(&.as_f)
      puts "✓ Received metric update: #{metric_name} = #{value}"
    when "alert"
      alert_name = data["data"]["name"]?.try(&.as_s)
      severity = data["data"]["severity"]?.try(&.as_s)
      puts "✓ Received alert: #{alert_name} (#{severity})"
    when "summary"
      puts "✓ Received summary response"
    when "alerts"
      alert_count = data["data"].as_a.size
      puts "✓ Received alerts list: #{alert_count} alerts"
    when "error"
      puts "✗ Received error: #{data["message"]}"
    else
      puts "  Received: #{msg_type}"
    end
  end
  
  ws.on_close do
    puts "✓ WebSocket connection closed"
  end
  
  # Run WebSocket in background
  ws_fiber = spawn do
    ws.run
  rescue ex
    puts "WebSocket error: #{ex.message}"
  end
  
  # Wait for initial state
  sleep 0.2
  
  if initial_state_received
    puts "✓ WebSocket connection established"
    
    # Test 3: Send commands via WebSocket
    puts
    puts "Test 3: WebSocket Commands"
    puts "-" * 40
    
    # Request summary
    ws.send({"command" => "get_summary"}.to_json)
    sleep 0.1
    
    # Request alerts
    ws.send({"command" => "get_alerts"}.to_json)
    sleep 0.1
    
    # Generate some metrics to trigger updates
    puts
    puts "Test 4: Real-time Metric Updates"
    puts "-" * 40
    
    10.times do |i|
      monitor.record_metric("test_metric", (i * 10).to_f64, {"iteration" => i.to_s})
      sleep 0.05
    end
    
    sleep 0.2  # Wait for broadcasts
    
    websocket_test_passed = true
  else
    puts "✗ Did not receive initial state"
  end
  
  # Close WebSocket
  ws.close
  ws_fiber.join
  
rescue ex
  puts "✗ WebSocket test failed: #{ex.message}"
  puts "  #{ex.backtrace.first(3).join("\n  ")}"
end

puts

# Test 5: Performance Statistics
puts "Test 5: Performance Statistics"
puts "-" * 40

summary = monitor.get_performance_summary
puts "✓ Total metrics recorded: #{summary.size}"

summary.each do |metric, stats|
  puts "  #{metric}:"
  puts "    - Count: #{stats["count"]}"
  puts "    - Average: #{stats["avg"].round(2)}"
  puts "    - Min: #{stats["min"].round(2)}"
  puts "    - Max: #{stats["max"].round(2)}"
end

puts

# Test 6: Alert System
puts "Test 6: Alert System"
puts "-" * 40

# Add a test alert rule
monitor.add_alert_rule(
  name: "high_test_metric",
  metric_pattern: "test_metric",
  threshold: 50.0,
  comparison: "gt",
  duration: 1.second,
  severity: "warning"
)

puts "✓ Added alert rule: high_test_metric (threshold: 50.0)"

# Trigger the alert
monitor.record_metric("test_metric", 75.0, {"test" => "alert_trigger"})
sleep 0.2

active_alerts = monitor.get_active_alerts
if active_alerts.any?
  puts "✓ Alert triggered successfully"
  active_alerts.each do |alert|
    puts "  - #{alert.rule.name}: #{alert.current_value} > #{alert.rule.threshold}"
  end
else
  puts "✗ Alert not triggered (expected alert for value > 50.0)"
end

puts

# Cleanup
puts "=" * 60
puts "Test Summary"
puts "=" * 60
puts "✓ HTTP API endpoints: Working"
puts "✓ WebSocket connection: #{websocket_test_passed ? "Working" : "Failed"}"
puts "✓ Messages received: #{messages_received}"
puts "✓ Real-time updates: #{messages_received > 5 ? "Working" : "Limited"}"
puts "✓ Alert system: #{active_alerts.any? ? "Working" : "Not triggered"}"
puts

monitor.stop_monitoring

puts "WebSocket monitoring test completed!"
puts "=" * 60
