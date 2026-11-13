# Gives every CogServer the CogShell command set (AtomSpace, PLN, URE,
# NLP, vision) on its telnet and WebSocket interfaces.
#
# This lives apart from cogserver.cr because the AtomSpace core requires
# that file (through the cluster and agent code), and the shell in turn
# requires the reasoning and language modules built on the AtomSpace.

require "./cogserver"
require "../tools/cogshell"

CogServer::Server.shell_factory = ->(atomspace : AtomSpace::AtomSpace) do
  shell = CogShell::Shell.new(atomspace)
  ->(line : String) { shell.eval_line(line) }
end
