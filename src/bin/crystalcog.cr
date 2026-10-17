# Executable entry point. Keep src/crystalcog.cr safe to require as a library.
require "../crystalcog"

begin
  CrystalCog.main(ARGV)
rescue ex
  STDERR.puts "CrystalCog error: #{ex.message}"
  exit 1
end
