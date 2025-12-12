require "json"
require "http/server"
require "http/web_socket"
require "socket"
require "./performance_profiler"

# Real-time performance monitoring and dashboard system
# Provides live metrics, alerts, and performance visualization
module CogUtil
  class PerformanceMonitor
    # Real-time metric sample
    struct MetricSample
      property timestamp : Time
      property metric_name : String
      property value : Float64
      property tags : Hash(String, String)
      
      def initialize(@timestamp : Time, @metric_name : String, @value : Float64, @tags : Hash(String, String) = Hash(String, String).new)
      end
      
      def to_json(json : JSON::Builder)
        json.object do
          json.field "timestamp", @timestamp.to_rfc3339
          json.field "metric", @metric_name
          json.field "value", @value
          json.field "tags", @tags
        end
      end
    end
    
    # Performance alert configuration
    struct AlertRule
      property name : String
      property metric_pattern : String
      property threshold : Float64
      property comparison : String  # "gt", "lt", "eq"
      property duration : Time::Span
      property severity : String   # "critical", "warning", "info"
      property enabled : Bool
      
      def initialize(@name : String, @metric_pattern : String, @threshold : Float64,
                     @comparison : String, @duration : Time::Span, @severity : String, @enabled : Bool = true)
      end
      
      def triggered?(value : Float64) : Bool
        return false unless @enabled
        
        case @comparison
        when "gt"
          value > @threshold
        when "lt"
          value < @threshold
        when "eq"
          (value - @threshold).abs < 0.001
        else
          false
        end
      end
    end
    
    # Active alert instance
    struct ActiveAlert
      property rule : AlertRule
      property triggered_at : Time
      property current_value : Float64
      property acknowledged : Bool
      
      def initialize(@rule : AlertRule, @triggered_at : Time, @current_value : Float64, @acknowledged : Bool = false)
      end
      
      def duration : Time::Span
        Time.utc - @triggered_at
      end
      
      def critical? : Bool
        @rule.severity == "critical"
      end
    end
    
    @samples : Array(MetricSample)
    @alert_rules : Array(AlertRule)
    @active_alerts : Array(ActiveAlert)
    @monitoring_active : Bool
    @sample_buffer_size : Int32
    @http_server : HTTP::Server?
    @websocket_clients : Array(HTTP::WebSocket)
    @monitoring_fiber : Fiber?
    @websocket_mutex : Mutex
    
    def initialize(@sample_buffer_size : Int32 = 10000)
      @samples = Array(MetricSample).new
      @alert_rules = Array(AlertRule).new
      @active_alerts = Array(ActiveAlert).new
      @monitoring_active = false
      @websocket_clients = Array(HTTP::WebSocket).new
      @websocket_mutex = Mutex.new
      
      setup_default_alert_rules
    end
    
    # Start real-time monitoring
    def start_monitoring(interval : Time::Span = 1.second)
      return if @monitoring_active
      
      @monitoring_active = true
      @monitoring_fiber = spawn do
        monitor_loop(interval)
      end
      
      puts "Performance monitoring started (interval: #{interval})"
    end
    
    # Stop monitoring
    def stop_monitoring
      @monitoring_active = false
      @monitoring_fiber = nil
      
      puts "Performance monitoring stopped"
    end
    
    # Record a performance metric
    def record_metric(name : String, value : Float64, tags : Hash(String, String) = Hash(String, String).new)
      sample = MetricSample.new(Time.utc, name, value, tags)
      @samples << sample
      
      # Keep buffer size under control
      if @samples.size > @sample_buffer_size
        @samples.shift(@samples.size - @sample_buffer_size)
      end
      
      # Check alert rules
      check_alerts(sample)
      
      # Broadcast to websocket clients
      broadcast_metric_update(sample)
    end
    
    # Start HTTP dashboard server
    def start_dashboard(port : Int32 = 8080)
      @http_server = HTTP::Server.new([
        HTTP::ErrorHandler.new,
        HTTP::LogHandler.new,
        HTTP::StaticFileHandler.new("./dashboard", false)
      ]) do |context|
        handle_request(context)
      end
      
      spawn do
        puts "Performance dashboard starting on http://localhost:#{port}"
        @http_server.try(&.bind_tcp("0.0.0.0", port))
        @http_server.try(&.listen)
      end
    end
    
    # Stop dashboard server
    def stop_dashboard
      @http_server.try(&.close)
      @http_server = nil
      puts "Performance dashboard stopped"
    end
    
    # Add custom alert rule
    def add_alert_rule(rule : AlertRule)
      @alert_rules << rule
      puts "Added alert rule: #{rule.name}"
    end
    
    # Get current performance summary
    def get_performance_summary : Hash(String, JSON::Any)
      now = Time.utc
      last_minute = now - 1.minute
      last_hour = now - 1.hour
      
      recent_samples = @samples.select { |s| s.timestamp > last_minute }
      hourly_samples = @samples.select { |s| s.timestamp > last_hour }
      
      summary = Hash(String, JSON::Any).new
      
      # Calculate metrics by name
      metric_names = @samples.map(&.metric_name).uniq
      
      metric_names.each do |name|
        recent_values = recent_samples.select { |s| s.metric_name == name }.map(&.value)
        hourly_values = hourly_samples.select { |s| s.metric_name == name }.map(&.value)
        
        next if recent_values.empty?
        
        metric_summary = {
          "current" => recent_values.last,
          "recent_avg" => recent_values.sum / recent_values.size,
          "recent_min" => recent_values.min,
          "recent_max" => recent_values.max,
          "hourly_avg" => hourly_values.empty? ? 0.0 : hourly_values.sum / hourly_values.size,
          "trend" => calculate_trend(recent_values),
          "sample_count" => recent_values.size
        }
        
        summary[name] = JSON.parse(metric_summary.to_json)
      end
      
      summary["_meta"] = JSON.parse({
        "last_update" => now.to_rfc3339,
        "active_alerts" => @active_alerts.size,
        "total_samples" => @samples.size,
        "monitoring_active" => @monitoring_active
      }.to_json)
      
      summary
    end
    
    # Get recent metrics for a specific name
    def get_metric_history(name : String, duration : Time::Span = 1.hour) : Array(MetricSample)
      cutoff = Time.utc - duration
      @samples.select { |s| s.metric_name == name && s.timestamp > cutoff }
    end
    
    # Get active alerts
    def get_active_alerts : Array(ActiveAlert)
      @active_alerts.dup
    end
    
    # Acknowledge an alert
    def acknowledge_alert(rule_name : String)
      @active_alerts.each do |alert|
        if alert.rule.name == rule_name
          alert.acknowledged = true
          puts "Alert acknowledged: #{rule_name}"
        end
      end
    end
    
    # Export monitoring data
    def export_monitoring_data(format : String = "json") : String
      case format
      when "json"
        JSON.build do |json|
          json.object do
            json.field "export_timestamp", Time.utc.to_rfc3339
            json.field "sample_count", @samples.size
            json.field "active_alerts", @active_alerts.size
            
            json.field "samples" do
              json.array do
                @samples.each { |sample| sample.to_json(json) }
              end
            end
            
            json.field "alert_rules" do
              json.array do
                @alert_rules.each do |rule|
                  json.object do
                    json.field "name", rule.name
                    json.field "metric_pattern", rule.metric_pattern
                    json.field "threshold", rule.threshold
                    json.field "comparison", rule.comparison
                    json.field "severity", rule.severity
                    json.field "enabled", rule.enabled
                  end
                end
              end
            end
          end
        end
      when "csv"
        export_csv
      else
        raise ArgumentError.new("Unsupported format: #{format}")
      end
    end
    
    # Generate performance monitoring report
    def generate_monitoring_report : String
      now = Time.utc
      String.build do |str|
        str << "Performance Monitoring Report\n"
        str << "=" * 35 << "\n"
        str << "Generated: #{now}\n"
        str << "Monitoring Status: #{@monitoring_active ? "Active" : "Inactive"}\n"
        str << "Sample Count: #{@samples.size}\n"
        str << "Alert Rules: #{@alert_rules.size}\n"
        str << "Active Alerts: #{@active_alerts.size}\n\n"
        
        # Alert status
        if @active_alerts.any?
          str << "🚨 ACTIVE ALERTS:\n"
          str << "-" * 16 << "\n"
          
          @active_alerts.each do |alert|
            status = alert.acknowledged ? "ACKNOWLEDGED" : "ACTIVE"
            str << "#{alert.rule.severity.upcase}: #{alert.rule.name} [#{status}]\n"
            str << "  Triggered: #{alert.triggered_at}\n"
            str << "  Duration: #{format_duration(alert.duration)}\n"
            str << "  Current Value: #{alert.current_value}\n"
            str << "  Threshold: #{alert.rule.threshold} (#{alert.rule.comparison})\n\n"
          end
        else
          str << "✅ No active alerts\n\n"
        end
        
        # Performance summary
        summary = get_performance_summary
        if summary.any?
          str << "📊 PERFORMANCE METRICS:\n"
          str << "-" * 24 << "\n"
          
          summary.each do |name, data|
            next if name == "_meta"
            
            current = data["current"].as_f
            avg = data["recent_avg"].as_f
            min_val = data["recent_min"].as_f
            max_val = data["recent_max"].as_f
            trend = data["trend"].as_f
            
            trend_icon = trend > 0.1 ? "📈" : trend < -0.1 ? "📉" : "➡️"
            
            str << "#{trend_icon} #{name}:\n"
            str << "  Current: #{current.round(4)}\n"
            str << "  Average: #{avg.round(4)}\n"
            str << "  Range: #{min_val.round(4)} - #{max_val.round(4)}\n"
            str << "  Trend: #{trend > 0 ? "+" : ""}#{trend.round(4)}\n\n"
          end
        end
        
        # System health indicators
        str << "🔋 SYSTEM HEALTH:\n"
        str << "-" * 16 << "\n"
        
        # Calculate health metrics
        error_rate = calculate_error_rate
        response_time = calculate_avg_response_time
        memory_usage = calculate_memory_trend
        
        health_score = calculate_health_score(error_rate, response_time, memory_usage)
        
        str << "Overall Health Score: #{health_score}/100\n"
        str << "Error Rate: #{error_rate.round(2)}%\n"
        str << "Avg Response Time: #{response_time.round(4)}s\n"
        str << "Memory Trend: #{memory_usage > 0 ? "↗️" : "↘️"} #{memory_usage.round(2)}%\n\n"
        
        str << "Recommendations:\n"
        if health_score < 70
          str << "⚠️ System health below optimal threshold\n"
          str << "• Review active alerts and address critical issues\n"
          str << "• Check for performance regressions\n"
          str << "• Consider scaling or optimization\n"
        elsif health_score < 85
          str << "💡 Good performance with room for improvement\n"
          str << "• Monitor trends for potential issues\n"
          str << "• Consider proactive optimizations\n"
        else
          str << "✅ Excellent system performance\n"
          str << "• Continue current monitoring\n"
          str << "• Maintain optimization practices\n"
        end
      end
    end
    
    private def setup_default_alert_rules
      # High response time alert
      @alert_rules << AlertRule.new(
        name: "high_response_time",
        metric_pattern: "response_time",
        threshold: 1.0,
        comparison: "gt",
        duration: 30.seconds,
        severity: "warning"
      )
      
      # Memory usage alert
      @alert_rules << AlertRule.new(
        name: "high_memory_usage",
        metric_pattern: "memory_usage",
        threshold: 500_000_000.0,  # 500MB
        comparison: "gt",
        duration: 1.minute,
        severity: "critical"
      )
      
      # Error rate alert
      @alert_rules << AlertRule.new(
        name: "high_error_rate",
        metric_pattern: "error_rate",
        threshold: 5.0,  # 5%
        comparison: "gt",
        duration: 2.minutes,
        severity: "critical"
      )
      
      # CPU usage alert
      @alert_rules << AlertRule.new(
        name: "high_cpu_usage",
        metric_pattern: "cpu_usage",
        threshold: 80.0,  # 80%
        comparison: "gt",
        duration: 5.minutes,
        severity: "warning"
      )
    end
    
    private def monitor_loop(interval : Time::Span)
      while @monitoring_active
        begin
          # Collect system metrics
          collect_system_metrics
          
          # Update performance metrics from active profiler session
          update_profiler_metrics
          
          # Check for stale alerts
          cleanup_stale_alerts
          
          sleep interval
        rescue ex
          puts "Monitoring error: #{ex.message}"
          break unless @monitoring_active
        end
      end
    end
    
    private def collect_system_metrics
      # Collect basic system metrics
      gc_stats = GC.stats
      
      record_metric("memory_usage", gc_stats.total_bytes.to_f64)
      # record_metric("gc_collections", gc_stats.collections.to_f64)  # Not available in Crystal's GC::Stats
      
      # Record timestamp for heartbeat
      record_metric("system_heartbeat", Time.utc.to_unix_f)
    end
    
    private def update_profiler_metrics
      # If there's an active profiler session, extract current metrics
      if session = PerformanceProfiler.current_session
        session.all_metrics.each do |name, metrics|
          record_metric("function_time_#{name}", metrics.wall_time)
          record_metric("function_calls_#{name}", metrics.call_count.to_f64)
          record_metric("function_errors_#{name}", metrics.errors.to_f64)
        end
      end
    end
    
    private def check_alerts(sample : MetricSample)
      @alert_rules.each do |rule|
        next unless rule.enabled
        next unless sample.metric_name.matches?(Regex.new(rule.metric_pattern))
        
        if rule.triggered?(sample.value)
          # Check if alert already exists
          existing_alert = @active_alerts.find { |a| a.rule.name == rule.name }
          
          if existing_alert
            existing_alert.current_value = sample.value
          else
            # Create new alert
            alert = ActiveAlert.new(rule, sample.timestamp, sample.value)
            @active_alerts << alert
            
            puts "🚨 ALERT TRIGGERED: #{rule.name} (#{rule.severity})"
            puts "   Value: #{sample.value}, Threshold: #{rule.threshold}"
            
            # Broadcast alert to websocket clients
            broadcast_alert(alert)
          end
        else
          # Remove resolved alerts
          @active_alerts.reject! { |a| a.rule.name == rule.name }
        end
      end
    end
    
    private def cleanup_stale_alerts
      # Remove acknowledged alerts older than 1 hour
      cutoff = Time.utc - 1.hour
      @active_alerts.reject! { |a| a.acknowledged && a.triggered_at < cutoff }
    end
    
    private def handle_request(context : HTTP::Server::Context)
      case context.request.path
      when "/"
        serve_dashboard_html(context)
      when "/api/metrics"
        serve_metrics_api(context)
      when "/api/alerts"
        serve_alerts_api(context)
      when "/api/summary"
        serve_summary_api(context)
      when "/ws"
        handle_websocket(context)
      else
        context.response.status_code = 404
        context.response.print "Not found"
      end
    end
    
    private def serve_dashboard_html(context : HTTP::Server::Context)
      html = generate_dashboard_html
      context.response.content_type = "text/html"
      context.response.print html
    end
    
    private def serve_metrics_api(context : HTTP::Server::Context)
      context.response.content_type = "application/json"
      context.response.print get_performance_summary.to_json
    end
    
    private def serve_alerts_api(context : HTTP::Server::Context)
      context.response.content_type = "application/json"
      alerts_json = @active_alerts.map do |alert|
        {
          "name" => alert.rule.name,
          "severity" => alert.rule.severity,
          "triggered_at" => alert.triggered_at.to_rfc3339,
          "current_value" => alert.current_value,
          "threshold" => alert.rule.threshold,
          "acknowledged" => alert.acknowledged
        }
      end
      context.response.print alerts_json.to_json
    end
    
    private def serve_summary_api(context : HTTP::Server::Context)
      context.response.content_type = "application/json"
      summary = {
        "monitoring_active" => @monitoring_active,
        "sample_count" => @samples.size,
        "alert_count" => @active_alerts.size,
        "last_update" => Time.utc.to_rfc3339
      }
      context.response.print summary.to_json
    end
    
    private def handle_websocket(context : HTTP::Server::Context)
      # Upgrade HTTP connection to WebSocket using response.upgrade
      context.response.upgrade do |io|
        # Create WebSocket protocol handler
        ws_protocol = HTTP::WebSocket::Protocol.new(io, masked: false)
        ws = HTTP::WebSocket.new(ws_protocol)
        
        # Add client to active connections
        @websocket_mutex.synchronize do
          @websocket_clients << ws
        end
        
        puts "WebSocket client connected (total: #{@websocket_clients.size})"
        
        # Send initial state
        initial_state = {
          "type" => "initial_state",
          "data" => {
            "monitoring_active" => @monitoring_active,
            "sample_count" => @samples.size,
            "active_alerts" => @active_alerts.size,
            "alert_rules" => @alert_rules.size
          }
        }
        
        begin
          ws.send(initial_state.to_json)
          
          # Handle incoming messages
          ws.on_message do |message|
            handle_websocket_message(ws, message)
          end
          
          # Handle client disconnect
          ws.on_close do
            @websocket_mutex.synchronize do
              @websocket_clients.delete(ws)
            end
            puts "WebSocket client disconnected (remaining: #{@websocket_clients.size})"
          end
          
          # Run the WebSocket
          ws.run
        rescue ex
          puts "WebSocket error: #{ex.message}"
          @websocket_mutex.synchronize do
            @websocket_clients.delete(ws)
          end
        end
      end
    end
    
    private def handle_websocket_message(ws : HTTP::WebSocket, message : String)
      begin
        data = JSON.parse(message)
        command = data["command"]?.try(&.as_s)
        
        case command
        when "get_summary"
          summary = get_performance_summary
          ws.send({"type" => "summary", "data" => summary}.to_json)
        when "get_alerts"
          alerts = @active_alerts.map do |alert|
            {
              "name" => alert.rule.name,
              "severity" => alert.rule.severity,
              "value" => alert.current_value,
              "threshold" => alert.rule.threshold,
              "triggered_at" => alert.triggered_at.to_rfc3339,
              "acknowledged" => alert.acknowledged
            }
          end
          ws.send({"type" => "alerts", "data" => alerts}.to_json)
        when "acknowledge_alert"
          if rule_name = data["rule_name"]?.try(&.as_s)
            acknowledge_alert(rule_name)
            ws.send({"type" => "ack_success", "data" => {"rule_name" => rule_name}}.to_json)
          end
        else
          ws.send({"type" => "error", "message" => "Unknown command: #{command}"}.to_json)
        end
      rescue ex
        ws.send({"type" => "error", "message" => ex.message}.to_json)
      end
    end
    
    private def broadcast_metric_update(sample : MetricSample)
      message = {
        "type" => "metric_update",
        "data" => {
          "timestamp" => sample.timestamp.to_rfc3339,
          "metric" => sample.metric_name,
          "value" => sample.value,
          "tags" => sample.tags
        }
      }
      
      broadcast_to_websockets(message.to_json)
    end
    
    private def broadcast_alert(alert : ActiveAlert)
      message = {
        "type" => "alert",
        "data" => {
          "name" => alert.rule.name,
          "severity" => alert.rule.severity,
          "value" => alert.current_value,
          "threshold" => alert.rule.threshold,
          "triggered_at" => alert.triggered_at.to_rfc3339
        }
      }
      
      broadcast_to_websockets(message.to_json)
    end
    
    private def broadcast_to_websockets(message : String)
      # Broadcast message to all connected WebSocket clients
      @websocket_mutex.synchronize do
        disconnected = [] of HTTP::WebSocket
        
        @websocket_clients.each do |client|
          begin
            client.send(message)
          rescue ex
            # Mark disconnected clients for removal
            disconnected << client
            puts "Failed to send to WebSocket client: #{ex.message}"
          end
        end
        
        # Remove disconnected clients
        disconnected.each do |client|
          @websocket_clients.delete(client)
        end
      end
    end
    
    private def calculate_trend(values : Array(Float64)) : Float64
      return 0.0 if values.size < 2
      
      # Simple linear trend calculation
      n = values.size
      x_sum = (0...n).sum.to_f64
      y_sum = values.sum
      xy_sum = (0...n).zip(values).sum { |x, y| x * y }
      x2_sum = (0...n).sum { |x| x * x }.to_f64
      
      denominator = n * x2_sum - x_sum * x_sum
      return 0.0 if denominator == 0.0
      
      (n * xy_sum - x_sum * y_sum) / denominator
    end
    
    private def calculate_error_rate : Float64
      error_samples = @samples.select { |s| s.metric_name.includes?("error") }
      return 0.0 if error_samples.empty?
      
      recent_errors = error_samples.select { |s| s.timestamp > Time.utc - 1.hour }
      return 0.0 if recent_errors.empty?
      
      recent_errors.sum(&.value) / recent_errors.size
    end
    
    private def calculate_avg_response_time : Float64
      response_samples = @samples.select { |s| s.metric_name.includes?("response_time") || s.metric_name.includes?("function_time") }
      return 0.0 if response_samples.empty?
      
      recent_times = response_samples.select { |s| s.timestamp > Time.utc - 1.hour }
      return 0.0 if recent_times.empty?
      
      recent_times.sum(&.value) / recent_times.size
    end
    
    private def calculate_memory_trend : Float64
      memory_samples = @samples.select { |s| s.metric_name.includes?("memory") }
      return 0.0 if memory_samples.empty?
      
      recent_memory = memory_samples.select { |s| s.timestamp > Time.utc - 1.hour }
      return 0.0 if recent_memory.size < 2
      
      values = recent_memory.map(&.value)
      calculate_trend(values)
    end
    
    private def calculate_health_score(error_rate : Float64, response_time : Float64, memory_trend : Float64) : Int32
      score = 100
      
      # Deduct for high error rate
      score -= (error_rate * 2).to_i
      
      # Deduct for high response time
      if response_time > 1.0
        score -= ((response_time - 1.0) * 20).to_i
      end
      
      # Deduct for increasing memory trend
      if memory_trend > 0.1
        score -= (memory_trend * 100).to_i
      end
      
      # Deduct for active critical alerts
      critical_alerts = @active_alerts.count(&.critical?)
      score -= critical_alerts * 10
      
      [score, 0].max
    end
    
    private def format_duration(duration : Time::Span) : String
      if duration.total_days >= 1
        "#{duration.total_days.to_i}d #{duration.hours}h #{duration.minutes}m"
      elsif duration.total_hours >= 1
        "#{duration.hours}h #{duration.minutes}m"
      elsif duration.total_minutes >= 1
        "#{duration.minutes}m #{duration.seconds}s"
      else
        "#{duration.seconds}s"
      end
    end
    
    private def export_csv : String
      String.build do |str|
        str << "timestamp,metric_name,value,tags\n"
        @samples.each do |sample|
          tags_str = sample.tags.map { |k, v| "#{k}=#{v}" }.join(";")
          str << "#{sample.timestamp.to_rfc3339},#{sample.metric_name},#{sample.value},\"#{tags_str}\"\n"
        end
      end
    end
    
    private def generate_dashboard_html : String
      <<-HTML
      <!DOCTYPE html>
      <html>
      <head>
          <title>CrystalCog Performance Dashboard</title>
          <style>
              body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
              .container { max-width: 1200px; margin: 0 auto; }
              .header { background: #2c3e50; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
              .metrics-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
              .metric-card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
              .metric-value { font-size: 2em; font-weight: bold; color: #3498db; }
              .metric-label { color: #7f8c8d; margin-bottom: 10px; }
              .alert { padding: 15px; margin: 10px 0; border-radius: 4px; }
              .alert-critical { background: #e74c3c; color: white; }
              .alert-warning { background: #f39c12; color: white; }
              .alert-info { background: #3498db; color: white; }
              .status-indicator { display: inline-block; width: 12px; height: 12px; border-radius: 50%; margin-right: 8px; }
              .status-active { background: #2ecc71; }
              .status-inactive { background: #e74c3c; }
          </style>
      </head>
      <body>
          <div class="container">
              <div class="header">
                  <h1>🚀 CrystalCog Performance Dashboard</h1>
                  <p>Real-time performance monitoring and alerting</p>
                  <span class="status-indicator status-active"></span>
                  <span>Monitoring Active</span>
              </div>
              
              <div id="alerts-section">
                  <h2>🚨 Active Alerts</h2>
                  <div id="alerts-container">
                      <!-- Alerts will be loaded here -->
                  </div>
              </div>
              
              <div id="metrics-section">
                  <h2>📊 Performance Metrics</h2>
                  <div class="metrics-grid" id="metrics-container">
                      <!-- Metrics will be loaded here -->
                  </div>
              </div>
          </div>
          
          <script>
              // WebSocket connection for real-time updates
              const ws = new WebSocket('ws://localhost:8080/ws');
              
              ws.onmessage = function(event) {
                  const message = JSON.parse(event.data);
                  if (message.type === 'metric_update') {
                      updateMetric(message.data);
                  } else if (message.type === 'alert') {
                      addAlert(message.data);
                  }
              };
              
              // Load initial data
              loadMetrics();
              loadAlerts();
              
              function loadMetrics() {
                  fetch('/api/metrics')
                      .then(response => response.json())
                      .then(data => renderMetrics(data));
              }
              
              function loadAlerts() {
                  fetch('/api/alerts')
                      .then(response => response.json())
                      .then(data => renderAlerts(data));
              }
              
              function renderMetrics(metrics) {
                  const container = document.getElementById('metrics-container');
                  container.innerHTML = '';
                  
                  Object.keys(metrics).forEach(name => {
                      if (name === '_meta') return;
                      
                      const metric = metrics[name];
                      const card = document.createElement('div');
                      card.className = 'metric-card';
                      card.innerHTML = `
                          <div class="metric-label">${name}</div>
                          <div class="metric-value">${metric.current.toFixed(4)}</div>
                          <div>Average: ${metric.recent_avg.toFixed(4)}</div>
                          <div>Range: ${metric.recent_min.toFixed(4)} - ${metric.recent_max.toFixed(4)}</div>
                          <div>Trend: ${metric.trend > 0 ? '↗️' : '↘️'} ${metric.trend.toFixed(4)}</div>
                      `;
                      container.appendChild(card);
                  });
              }
              
              function renderAlerts(alerts) {
                  const container = document.getElementById('alerts-container');
                  container.innerHTML = '';
                  
                  if (alerts.length === 0) {
                      container.innerHTML = '<div class="alert alert-info">✅ No active alerts</div>';
                      return;
                  }
                  
                  alerts.forEach(alert => {
                      const alertDiv = document.createElement('div');
                      alertDiv.className = `alert alert-${alert.severity}`;
                      alertDiv.innerHTML = `
                          <strong>${alert.name}</strong> - ${alert.severity.toUpperCase()}
                          <br>Value: ${alert.current_value.toFixed(4)}, Threshold: ${alert.threshold}
                          <br>Triggered: ${new Date(alert.triggered_at).toLocaleString()}
                          ${alert.acknowledged ? '<br><em>Acknowledged</em>' : ''}
                      `;
                      container.appendChild(alertDiv);
                  });
              }
              
              function updateMetric(data) {
                  // Real-time metric updates would be implemented here
                  console.log('Metric update:', data);
              }
              
              function addAlert(data) {
                  // Real-time alert updates would be implemented here
                  console.log('New alert:', data);
                  loadAlerts(); // Reload alerts for now
              }
              
              // Refresh data every 5 seconds
              setInterval(() => {
                  loadMetrics();
                  loadAlerts();
              }, 5000);
          </script>
      </body>
      </html>
      HTML
    end
  end
end