# Deliberately fail required outcomes. Each invocation must exit nonzero.
require "../sqlite_persistence_scenario"
require "../../../examples/tests/websocket_monitoring_scenario"

class FailingNightlyStorage
  getter closes = 0
  @opens = 0

  def initialize(@failure : String)
  end

  def open : Bool
    @opens += 1
    @failure != "open" && !(@failure == "reopen" && @opens == 2)
  end

  def close : Bool
    @closes += 1
    true
  end

  def store_atom(atom : AtomSpace::Atom) : Bool
    @failure != "store"
  end

  def fetch_atom(handle : AtomSpace::Handle) : AtomSpace::Atom?
    return nil if @failure == "fetch"
    AtomSpace::Node.new(AtomSpace::AtomType::CONCEPT_NODE, "wrong_content")
  end
end

class MissingNightlyAlert < CogUtil::PerformanceMonitor
  def get_active_alerts : Array(ActiveAlert)
    [] of ActiveAlert
  end
end

class MissingNightlyUpdates < CogUtil::PerformanceMonitor
  def record_metric(name : String, value : Float64, tags : Hash(String, String) = Hash(String, String).new)
    super unless name == "test_metric"
  end
end

class InactiveNightlyMonitor < CogUtil::PerformanceMonitor
  def start_monitoring(interval : Time::Span = 1.second)
  end
end

class MissingNightlyCommands < CogUtil::PerformanceMonitor
  private def handle_websocket_message(ws : HTTP::WebSocket, message : String)
  end
end

status = 0
begin
  case mode = ARGV[0]? || ""
  when "sqlite-open"
    blocker = File.tempfile("nightly-blocker")
    blocker.close
    begin
      storage = AtomSpace::SQLiteStorageNode.new("negative-open", "#{blocker.path}/impossible.db", use_pool: false)
      NightlySQLitePersistence.run(storage)
    ensure
      File.delete(blocker.path)
      puts "Fixture verified real SQLite cleanup"
    end
  when "open", "store", "reopen", "fetch", "mismatch"
    storage = FailingNightlyStorage.new(mode)
    begin
      NightlySQLitePersistence.run(storage)
    ensure
      raise "Storage cleanup was not called" unless storage.closes > 0
      puts "Fixture verified storage cleanup"
    end
  when "connection"
    NightlyWebSocketMonitoring.run(websocket_path: "/not-a-websocket", wait: 0.2.seconds)
  when "http"
    NightlyWebSocketMonitoring.run(InactiveNightlyMonitor.new, wait: 0.2.seconds)
  when "commands"
    NightlyWebSocketMonitoring.run(MissingNightlyCommands.new, wait: 0.2.seconds)
  when "alert"
    NightlyWebSocketMonitoring.run(MissingNightlyAlert.new, wait: 0.2.seconds)
  when "updates"
    NightlyWebSocketMonitoring.run(MissingNightlyUpdates.new, wait: 0.2.seconds)
  else
    raise "Unknown negative fixture: #{mode}"
  end
rescue ex
  STDERR.puts "Expected negative fixture failure: #{ex.message}"
  status = 1
end
exit status
