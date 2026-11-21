require "../../src/cogutil/performance_monitor"
require "http/client"
require "http/web_socket"
require "json"
require "socket"

module NightlyWebSocketMonitoring
  def self.await(label : String, wait : Time::Span, &condition : -> Bool)
    deadline = Time.instant + wait
    until condition.call
      raise "Timed out waiting for #{label}" if Time.instant >= deadline
      sleep 10.milliseconds
    end
  end

  # Loopback client, randomly assigned port: no fixed 8081 port or external service.
  # The short reservation-to-bind gap is guarded by readiness/outcome checks.
  def self.run(monitor = CogUtil::PerformanceMonitor.new, websocket_path = "/ws", wait = 5.seconds)
    reservation = TCPServer.new("127.0.0.1", 0)
    port = reservation.local_address.port
    reservation.close
    client = HTTP::Client.new("127.0.0.1", port)
    client.connect_timeout = 1.second
    client.read_timeout = 1.second
    ws : HTTP::WebSocket? = nil
    done : Channel(Exception?)? = nil

    puts "WebSocket Monitoring Integration Test (port #{port})"
    begin
      monitor.start_http_server(port: port)
      monitor.start_monitoring(interval: 0.1.seconds)
      await("HTTP server readiness", wait) do
        begin
          client.get("/summary").status_code == 200
        rescue IO::Error | Socket::Error
          false
        end
      end

      puts "Test 1: HTTP API Endpoints"
      ["/summary", "/metrics", "/alerts"].each do |path|
        response = client.get(path)
        raise "GET #{path} failed: #{response.status_code}" unless response.status_code == 200
        data = JSON.parse(response.body)
        if path == "/summary"
          raise "HTTP summary reports inactive monitoring" unless data["monitoring_active"].as_bool
        end
        puts "GET #{path}: #{response.status_code}"
      end

      puts "Test 2: WebSocket Connection"
      socket = HTTP::WebSocket.new(URI.parse("ws://127.0.0.1:#{port}#{websocket_path}"))
      ws = socket
      initial_state_received = false
      summary_received = false
      alerts_received = false
      metric_updates = 0
      alert_received = false
      messages_received = 0
      socket_errors = [] of String
      socket.on_message do |message|
        messages_received += 1
        data = JSON.parse(message)
        case data["type"].as_s
        when "initial_state"
          raise "Initial state reports inactive monitoring" unless data["data"]["monitoring_active"].as_bool
          initial_state_received = true
        when "summary"
          data["data"].as_h
          summary_received = true
        when "alerts"
          data["data"].as_a
          alerts_received = true
        when "metric_update"
          if data["data"]["metric"].as_s == "test_metric"
            data["data"]["value"].as_f
            metric_updates += 1
          end
        when "alert"
          alert_received = true if data["data"]["name"].as_s == "high_test_metric"
        when "error"
          socket_errors << data["message"].as_s
        end
      end

      completion = Channel(Exception?).new(1)
      done = completion
      spawn do
        error : Exception? = nil
        begin
          socket.run
        rescue ex
          error = ex
        ensure
          completion.send(error)
        end
      end
      await("WebSocket initial state", wait) { initial_state_received }
      puts "Received initial state; WebSocket connection established"

      puts "Test 3: WebSocket Commands"
      socket.send({"command" => "get_summary"}.to_json)
      socket.send({"command" => "get_alerts"}.to_json)
      await("summary and alerts command responses", wait) { summary_received && alerts_received }
      puts "Received summary and alerts responses"

      puts "Test 4: Real-time Metric Updates"
      10.times do |i|
        monitor.record_metric("test_metric", (i * 10).to_f64, {"iteration" => i.to_s})
      end
      await("10 test_metric updates", wait) { metric_updates == 10 }
      puts "Received 10 test_metric updates"

      puts "Test 5: Performance Statistics"
      stats = monitor.get_performance_summary["test_metric"]
      raise "Incorrect test_metric count" unless stats["count"].as_i == 10
      raise "Incorrect test_metric average" unless stats["avg"].as_f == 45.0
      raise "Incorrect test_metric range" unless stats["min"].as_f == 0.0 && stats["max"].as_f == 90.0
      puts "Verified test_metric count, average, and range"

      puts "Test 6: Alert System"
      monitor.add_alert_rule(
        name: "high_test_metric", metric_pattern: "test_metric", threshold: 50.0,
        comparison: "gt", duration: 1.second, severity: "warning"
      )
      monitor.record_metric("test_metric", 75.0, {"test" => "alert_trigger"})
      active_alerts = monitor.get_active_alerts
      raise "Expected high_test_metric alert was not triggered" unless active_alerts.any? do |alert|
                                                                         alert.rule.name == "high_test_metric" && alert.current_value == 75.0
                                                                       end
      await("high_test_metric WebSocket alert", wait) { alert_received }
      raise "WebSocket reported errors: #{socket_errors.join(", ")}" unless socket_errors.empty?
      puts "Verified high_test_metric active alert and WebSocket notification"

      socket.close
      select
      when error = completion.receive
        raise "WebSocket reader failed: #{error.message}" if error
      when timeout(wait)
        raise "Timed out waiting for WebSocket reader completion"
      end
      done = nil
      puts "WebSocket monitoring test passed! (#{messages_received} messages)"
    ensure
      # Closing the socket releases its reader; no unsupported Fiber#join and
      # no wait on unrelated server fibers. Cleanup also runs on assertion failure.
      begin
        begin
          ws.try(&.close)
        rescue ex
          STDERR.puts "WebSocket close failed during cleanup: #{ex.message}"
        end
        if cleanup_completion = done
          select
          when error = cleanup_completion.receive
            STDERR.puts "WebSocket reader failed during cleanup: #{error.message}" if error
          when timeout(wait)
            STDERR.puts "WebSocket reader cleanup timed out"
          end
        end
      ensure
        client.close
        monitor.stop_monitoring
        monitor.stop_dashboard
      end
    end
  end
end
