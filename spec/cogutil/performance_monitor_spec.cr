require "spec"
require "json"
require "../../src/cogutil/performance_monitor"

describe CogUtil::PerformanceMonitor do
  describe "MetricSample" do
    it "stores timestamp, name, value, and tags" do
      tags = {"host" => "local", "env" => "test"}
      sample = CogUtil::PerformanceMonitor::MetricSample.new(
        Time.utc(2024, 1, 2, 3, 4, 5),
        "response_time",
        1.25,
        tags
      )

      sample.metric_name.should eq("response_time")
      sample.value.should eq(1.25)
      sample.tags.should eq(tags)
      sample.timestamp.should eq(Time.utc(2024, 1, 2, 3, 4, 5))
    end

    it "serializes to JSON with expected fields" do
      sample = CogUtil::PerformanceMonitor::MetricSample.new(
        Time.utc(2024, 6, 15, 12, 0, 0),
        "cpu_usage",
        42.0,
        {"unit" => "percent"}
      )

      parsed = JSON.parse(sample.to_json)
      parsed["metric"].as_s.should eq("cpu_usage")
      parsed["value"].as_f.should eq(42.0)
      parsed["tags"]["unit"].as_s.should eq("percent")
      parsed["timestamp"].as_s.should contain("2024-06-15")
    end

    it "defaults tags to an empty hash" do
      sample = CogUtil::PerformanceMonitor::MetricSample.new(Time.utc, "heartbeat", 1.0)
      sample.tags.should be_empty
    end
  end

  describe "AlertRule" do
    it "evaluates greater-than comparisons" do
      rule = CogUtil::PerformanceMonitor::AlertRule.new(
        "high_latency", "response_time", 1.0, "gt", 30.seconds, "warning"
      )

      rule.triggered?(1.1).should be_true
      rule.triggered?(1.0).should be_false
      rule.triggered?(0.9).should be_false
    end

    it "evaluates less-than and equality comparisons" do
      lt_rule = CogUtil::PerformanceMonitor::AlertRule.new(
        "low_throughput", "ops", 10.0, "lt", 1.minute, "info"
      )
      eq_rule = CogUtil::PerformanceMonitor::AlertRule.new(
        "exact_match", "ratio", 0.5, "eq", 1.minute, "info"
      )

      lt_rule.triggered?(9.0).should be_true
      lt_rule.triggered?(10.0).should be_false
      eq_rule.triggered?(0.5004).should be_true
      eq_rule.triggered?(0.51).should be_false
    end

    it "ignores disabled rules and unknown comparisons" do
      disabled = CogUtil::PerformanceMonitor::AlertRule.new(
        "disabled", "cpu", 50.0, "gt", 1.minute, "warning", false
      )
      unknown = CogUtil::PerformanceMonitor::AlertRule.new(
        "unknown", "cpu", 50.0, "neq", 1.minute, "warning"
      )

      disabled.triggered?(99.0).should be_false
      unknown.triggered?(99.0).should be_false
    end
  end

  describe "ActiveAlert" do
    it "reports duration and critical severity" do
      rule = CogUtil::PerformanceMonitor::AlertRule.new(
        "critical_mem", "memory_usage", 100.0, "gt", 1.minute, "critical"
      )
      alert = CogUtil::PerformanceMonitor::ActiveAlert.new(rule, Time.utc - 2.seconds, 250.0)

      alert.critical?.should be_true
      alert.acknowledged.should be_false
      alert.duration.should be > 1.second
      alert.duration.should be < 10.seconds
    end

    it "is not critical for warning severity" do
      rule = CogUtil::PerformanceMonitor::AlertRule.new(
        "warn_cpu", "cpu_usage", 80.0, "gt", 1.minute, "warning"
      )
      alert = CogUtil::PerformanceMonitor::ActiveAlert.new(rule, Time.utc, 90.0)

      alert.critical?.should be_false
    end
  end

  describe "initialization" do
    it "creates a monitor with the requested buffer size" do
      monitor = CogUtil::PerformanceMonitor.new(1000)
      monitor.should_not be_nil
    end

    it "loads default alert rules into exported data" do
      monitor = CogUtil::PerformanceMonitor.new
      export = JSON.parse(monitor.export_monitoring_data("json"))
      rules = export["alert_rules"].as_a.map { |r| r["name"].as_s }

      rules.should contain("high_response_time")
      rules.should contain("high_memory_usage")
      rules.should contain("high_error_rate")
      rules.should contain("high_cpu_usage")
    end
  end

  describe "metric recording" do
    it "records metrics and builds a performance summary" do
      monitor = CogUtil::PerformanceMonitor.new

      monitor.record_metric("test_metric", 42.5)
      monitor.record_metric("test_metric", 45.0, {"source" => "unit"})

      summary = monitor.get_performance_summary
      summary.has_key?("test_metric").should be_true

      metric_data = summary["test_metric"]
      metric_data["current"].as_f.should eq(45.0)
      metric_data["min"].as_f.should eq(42.5)
      metric_data["max"].as_f.should eq(45.0)
      metric_data["count"].as_i.should eq(2)
      metric_data["avg"].as_f.should eq(43.75)
    end

    it "enforces the sample buffer size" do
      monitor = CogUtil::PerformanceMonitor.new(3)

      5.times do |i|
        monitor.record_metric("buffered", i.to_f64)
      end

      history = monitor.get_metric_history("buffered", 1.hour)
      history.size.should eq(3)
      history.map(&.value).should eq([2.0, 3.0, 4.0])
    end

    it "tracks metric history for a named metric" do
      monitor = CogUtil::PerformanceMonitor.new

      5.times do |i|
        monitor.record_metric("history_test", i.to_f64)
      end

      history = monitor.get_metric_history("history_test", 1.hour)
      history.size.should eq(5)
      history.first.value.should eq(0.0)
      history.last.value.should eq(4.0)

      empty = monitor.get_metric_history("missing_metric", 1.hour)
      empty.should be_empty
    end
  end

  describe "alert management" do
    it "triggers alerts for matching metric patterns" do
      monitor = CogUtil::PerformanceMonitor.new

      monitor.add_alert_rule(
        CogUtil::PerformanceMonitor::AlertRule.new(
          "test_alert",
          "test_metric",
          50.0,
          "gt",
          1.second,
          "warning"
        )
      )

      monitor.record_metric("test_metric", 55.0)

      alerts = monitor.get_active_alerts
      alerts.size.should eq(1)
      alerts.first.rule.name.should eq("test_alert")
      alerts.first.current_value.should eq(55.0)
      alerts.first.critical?.should be_false
    end

    it "supports the named-parameter add_alert_rule overload" do
      monitor = CogUtil::PerformanceMonitor.new

      monitor.add_alert_rule(
        name: "named_rule",
        metric_pattern: "custom_metric",
        threshold: 10.0,
        comparison: "gt",
        duration: 5.seconds,
        severity: "critical"
      )

      monitor.record_metric("custom_metric", 12.0)

      alerts = monitor.get_active_alerts
      named = alerts.find { |a| a.rule.name == "named_rule" }
      named.should_not be_nil
      named.try(&.critical?).should be_true
    end

    it "updates existing alerts and resolves them when values recover" do
      monitor = CogUtil::PerformanceMonitor.new
      monitor.add_alert_rule(
        name: "recoverable",
        metric_pattern: "latency",
        threshold: 1.0,
        comparison: "gt",
        duration: 1.second,
        severity: "warning"
      )

      monitor.record_metric("latency", 2.0)
      monitor.get_active_alerts.size.should eq(1)
      monitor.get_active_alerts.first.current_value.should eq(2.0)

      monitor.record_metric("latency", 3.0)
      monitor.get_active_alerts.size.should eq(1)
      monitor.get_active_alerts.first.current_value.should eq(3.0)

      monitor.record_metric("latency", 0.5)
      monitor.get_active_alerts.should be_empty
    end

    it "acknowledges active alerts by rule name" do
      monitor = CogUtil::PerformanceMonitor.new
      monitor.add_alert_rule(
        name: "ack_me",
        metric_pattern: "errors",
        threshold: 0.0,
        comparison: "gt",
        duration: 1.second,
        severity: "critical"
      )

      monitor.record_metric("errors", 5.0)
      monitor.acknowledge_alert("ack_me")

      alert = monitor.get_active_alerts.find { |a| a.rule.name == "ack_me" }
      alert.should_not be_nil
      alert.try(&.acknowledged).should be_true
    end

    it "does not trigger disabled alert rules" do
      monitor = CogUtil::PerformanceMonitor.new
      monitor.add_alert_rule(
        name: "disabled_rule",
        metric_pattern: "quiet_metric",
        threshold: 1.0,
        comparison: "gt",
        duration: 1.second,
        severity: "warning",
        enabled: false
      )

      monitor.record_metric("quiet_metric", 100.0)
      monitor.get_active_alerts.any? { |a| a.rule.name == "disabled_rule" }.should be_false
    end
  end

  describe "monitoring lifecycle" do
    it "starts and stops the monitoring loop" do
      monitor = CogUtil::PerformanceMonitor.new

      monitor.start_monitoring(50.milliseconds)
      sleep 120.milliseconds
      monitor.stop_monitoring

      # System metrics should have been collected at least once
      heartbeats = monitor.get_metric_history("system_heartbeat", 1.hour)
      heartbeats.size.should be >= 1

      memory = monitor.get_metric_history("memory_usage", 1.hour)
      memory.size.should be >= 1
    end

    it "is idempotent when start_monitoring is called twice" do
      monitor = CogUtil::PerformanceMonitor.new
      monitor.start_monitoring(100.milliseconds)
      monitor.start_monitoring(100.milliseconds)
      monitor.stop_monitoring
    end
  end

  describe "exports and reports" do
    it "generates a monitoring report with health sections" do
      monitor = CogUtil::PerformanceMonitor.new
      monitor.record_metric("response_time", 0.5)
      monitor.record_metric("memory_usage", 100_000_000.0)

      report = monitor.generate_monitoring_report
      report.should contain("Performance Monitoring Report")
      report.should contain("SYSTEM HEALTH")
      report.should contain("Sample Count: 2")
      report.should contain("No active alerts")
    end

    it "includes active alerts in the monitoring report" do
      monitor = CogUtil::PerformanceMonitor.new
      monitor.add_alert_rule(
        name: "report_alert",
        metric_pattern: "response_time",
        threshold: 0.1,
        comparison: "gt",
        duration: 1.second,
        severity: "critical"
      )
      monitor.record_metric("response_time", 2.0)

      report = monitor.generate_monitoring_report
      report.should contain("ACTIVE ALERTS")
      report.should contain("report_alert")
      report.should contain("CRITICAL")
    end

    it "exports monitoring data as JSON and CSV" do
      monitor = CogUtil::PerformanceMonitor.new
      monitor.record_metric("export_test", 123.0, {"env" => "spec"})

      json_export = monitor.export_monitoring_data("json")
      json_export.should contain("export_timestamp")
      json_export.should contain("samples")
      json_export.should contain("export_test")

      parsed = JSON.parse(json_export)
      parsed["sample_count"].as_i.should eq(1)

      csv_export = monitor.export_monitoring_data("csv")
      csv_export.should contain("timestamp,metric_name,value")
      csv_export.should contain("export_test")
      csv_export.should contain("env=spec")
    end

    it "raises for unsupported export formats" do
      monitor = CogUtil::PerformanceMonitor.new
      expect_raises(ArgumentError, /Unsupported format/) do
        monitor.export_monitoring_data("xml")
      end
    end
  end

  describe "dashboard lifecycle" do
    it "starts and stops the HTTP dashboard without raising" do
      monitor = CogUtil::PerformanceMonitor.new
      port = 18080 + Random.rand(1000)

      monitor.start_dashboard(port)
      sleep 50.milliseconds
      monitor.stop_dashboard
    end
  end
end
