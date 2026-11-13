# Native Crystal small-model engine with an OpenAI-compatible API.
# Build: crystal build --release -Dpreview_mt src/bin/aphrodite_jax_server.cr
require "option_parser"
require "../integrations/platform/aphrodite_jax_server"

AphroditeJax.main
