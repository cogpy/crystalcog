#!/usr/bin/env crystal
# WebSocket Monitoring Integration Test: every required outcome is an assertion.
require "./websocket_monitoring_scenario"

begin
  NightlyWebSocketMonitoring.run
rescue ex
  STDERR.puts "WebSocket monitoring test failed: #{ex.message}"
  STDERR.puts ex.backtrace.first(3).join("\n")
  exit 1
end
