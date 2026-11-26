# Lightweight AtomSpace entry point.
#
# Persistence and cluster adapters are intentionally excluded. Consumers that
# only need the in-memory graph should require this file; full applications can
# continue to require atomspace_main.

require "./truthvalue"
require "./atom"
require "./atomspace"
