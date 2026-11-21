require "./sqlite_persistence_scenario"

file = File.tempfile("nightly-atomspace", ".db")
file.close
status = 0
begin
  storage = AtomSpace::SQLiteStorageNode.new("nightly-persistence", file.path, use_pool: false)
  NightlySQLitePersistence.run(storage)
rescue ex
  STDERR.puts "Persistence test failed: #{ex.message}"
  status = 1
ensure
  # Only remove files owned by this run, after closing the database.
  [file.path, "#{file.path}-wal", "#{file.path}-shm", "#{file.path}-journal"].each do |path|
    File.delete(path) if File.exists?(path)
  end
end
exit status
