# CogShell — interactive AtomSpace / reasoning shell for CrystalCog
#
# Usage:
#   crystal run src/tools/cogshell.cr
#   crystalcog shell
#
# Commands:
#   help                         Show help
#   concept <name>               Create/get a ConceptNode
#   predicate <name>             Create/get a PredicateNode
#   inherit <child> <parent>     Add InheritanceLink
#   eval <pred> <a> [b ...]      Add EvaluationLink
#   imply <a> <b>                Add ImplicationLink between concepts
#   reason [steps]               Run PLN reasoning
#   ure [steps]                  Run URE forward chaining
#   query <name>                 Look up atoms by name
#   list [type]                  List atoms (optional type filter)
#   size                         Show AtomSpace size
#   clear                        Clear AtomSpace
#   nlp <text>                   Process text with NLP
#   parse <text>                 Link-grammar parse
#   tv <name> <strength> <conf>  Set truth value on named concept
#   quit / exit                  Leave the shell

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "../pln/pln"
require "../ure/ure"
require "../nlp/nlp"
require "../nlp/link_grammar"

module CogShell
  VERSION = "0.1.0"

  class Shell
    getter atomspace : AtomSpace::AtomSpace
    getter running : Bool

    def initialize(@atomspace : AtomSpace::AtomSpace = AtomSpace::AtomSpace.new)
      @running = false
      @pln = PLN.create_engine(@atomspace)
      @ure = URE.create_engine(@atomspace)
    end

    def run(input : IO = STDIN, output : IO = STDOUT)
      @running = true
      output.puts "CogShell #{VERSION} — CrystalCog interactive shell"
      output.puts "Type 'help' for commands, 'quit' to exit."

      while @running
        output.print "cog> "
        output.flush
        line = input.gets
        break unless line
        line = line.strip
        next if line.empty?
        begin
          handle(line, output)
        rescue ex
          output.puts "Error: #{ex.message}"
        end
      end

      output.puts "Goodbye."
    end

    # Process a single command line (also useful for tests / scripting)
    def eval_line(line : String) : String
      io = IO::Memory.new
      handle(line.strip, io)
      io.to_s
    end

    private def handle(line : String, output : IO)
      parts = tokenize(line)
      return if parts.empty?
      cmd = parts[0].downcase
      args = parts[1..]

      case cmd
      when "help", "?"
        print_help(output)
      when "quit", "exit", "q"
        @running = false
      when "concept", "c"
        name = args[0]? || raise "usage: concept <name>"
        node = @atomspace.add_concept_node(name)
        output.puts "=> #{node}"
      when "predicate", "pred", "p"
        name = args[0]? || raise "usage: predicate <name>"
        node = @atomspace.add_predicate_node(name)
        output.puts "=> #{node}"
      when "inherit", "inh"
        raise "usage: inherit <child> <parent>" unless args.size >= 2
        child = @atomspace.add_concept_node(args[0])
        parent = @atomspace.add_concept_node(args[1])
        tv = parse_tv(args[2]?, args[3]?)
        link = @atomspace.add_inheritance_link(child, parent, tv)
        output.puts "=> #{link}"
      when "eval", "evaluation"
        raise "usage: eval <pred> <arg1> [arg2 ...]" unless args.size >= 2
        pred = @atomspace.add_predicate_node(args[0])
        arg_nodes = args[1..].map { |n| @atomspace.add_concept_node(n).as(AtomSpace::Atom) }
        list = @atomspace.add_list_link(arg_nodes)
        link = @atomspace.add_evaluation_link(pred, list)
        output.puts "=> #{link}"
      when "imply", "implication"
        raise "usage: imply <antecedent> <consequent>" unless args.size >= 2
        a = @atomspace.add_concept_node(args[0])
        b = @atomspace.add_concept_node(args[1])
        tv = parse_tv(args[2]?, args[3]?)
        link = @atomspace.add_implication_link(a, b, tv)
        output.puts "=> #{link}"
      when "reason", "pln"
        steps = (args[0]? || "5").to_i
        @pln = PLN.create_engine(@atomspace)
        results = @pln.reason(steps)
        output.puts "PLN generated #{results.size} atom(s) in up to #{steps} iteration(s)"
        results.first(20).each { |a| output.puts "  #{a}" }
        output.puts "  ... (#{results.size - 20} more)" if results.size > 20
      when "ure", "forward"
        @ure = URE.create_engine(@atomspace)
        results = @ure.forward_chain
        output.puts "URE generated #{results.size} atom(s)"
        results.first(20).each { |a| output.puts "  #{a}" }
      when "query", "get", "find"
        name = args[0]? || raise "usage: query <name>"
        atoms = @atomspace.get_nodes_by_name(name)
        if atoms.empty?
          output.puts "(no atoms named #{name.inspect})"
        else
          atoms.each { |a| output.puts "  #{a}" }
        end
      when "list", "ls"
        atoms = if type_name = args[0]?
                  type = parse_type(type_name)
                  @atomspace.get_atoms_by_type(type)
                else
                  @atomspace.get_all_atoms
                end
        output.puts "#{atoms.size} atom(s):"
        atoms.first(50).each { |a| output.puts "  #{a}" }
        output.puts "  ... (#{atoms.size - 50} more)" if atoms.size > 50
      when "size"
        output.puts "AtomSpace size=#{@atomspace.size} nodes=#{@atomspace.node_count} links=#{@atomspace.link_count}"
      when "clear"
        @atomspace.clear
        @pln = PLN.create_engine(@atomspace)
        @ure = URE.create_engine(@atomspace)
        output.puts "AtomSpace cleared."
      when "nlp"
        text = args.join(" ")
        raise "usage: nlp <text>" if text.empty?
        atoms = NLP.process_text(text, @atomspace)
        output.puts "NLP created #{atoms.size} atom(s)"
        atoms.first(20).each { |a| output.puts "  #{a}" }
      when "parse", "lg"
        text = args.join(" ")
        raise "usage: parse <text>" if text.empty?
        linkages = NLP::LinkGrammar.parse(text)
        linkages.each_with_index do |linkage, i|
          output.puts "Linkage ##{i + 1} (cost=#{linkage.cost}): #{linkage.words.join(" ")}"
          linkage.links.each { |link| output.puts "  #{link}" }
        end
      when "tv"
        raise "usage: tv <name> <strength> <confidence>" unless args.size >= 3
        atoms = @atomspace.get_nodes_by_name(args[0])
        raise "no atom named #{args[0]}" if atoms.empty?
        tv = AtomSpace::SimpleTruthValue.new(args[1].to_f, args[2].to_f)
        atoms.each do |atom|
          atom.truth_value = tv
          output.puts "=> #{atom}"
        end
      else
        output.puts "Unknown command: #{cmd.inspect}. Type 'help' for commands."
      end
    end

    private def print_help(output : IO)
      output.puts <<-HELP
      CogShell commands:
        concept <name>                 Create ConceptNode
        predicate <name>               Create PredicateNode
        inherit <child> <parent> [s c] InheritanceLink (optional strength/confidence)
        eval <pred> <a> [b ...]        EvaluationLink
        imply <a> <b> [s c]            ImplicationLink
        reason [steps]                 Run PLN (default 5)
        ure                            Run URE forward chaining
        query <name>                   Lookup by name
        list [type]                    List atoms
        size                           AtomSpace statistics
        clear                          Clear AtomSpace
        nlp <text>                     NLP process text
        parse <text>                   Link Grammar parse
        tv <name> <s> <c>              Set truth value
        help                           This help
        quit                           Exit
      HELP
    end

    private def tokenize(line : String) : Array(String)
      tokens = [] of String
      current = String::Builder.new
      in_quotes = false

      line.each_char do |ch|
        if ch == '"'
          in_quotes = !in_quotes
        elsif ch.ascii_whitespace? && !in_quotes
          unless current.empty?
            tokens << current.to_s
            current = String::Builder.new
          end
        else
          current << ch
        end
      end
      tokens << current.to_s unless current.empty?
      tokens
    end

    private def parse_tv(s : String?, c : String?) : AtomSpace::TruthValue
      if s && c
        AtomSpace::SimpleTruthValue.new(s.to_f, c.to_f)
      else
        AtomSpace::SimpleTruthValue.new(1.0, 0.0)
      end
    end

    private def parse_type(name : String) : AtomSpace::AtomType
      key = name.upcase.gsub("-", "_")
      aliases = {
        "CONCEPT"     => AtomSpace::AtomType::CONCEPT_NODE,
        "PREDICATE"   => AtomSpace::AtomType::PREDICATE_NODE,
        "INHERITANCE" => AtomSpace::AtomType::INHERITANCE_LINK,
        "EVALUATION"  => AtomSpace::AtomType::EVALUATION_LINK,
        "IMPLICATION" => AtomSpace::AtomType::IMPLICATION_LINK,
        "LIST"        => AtomSpace::AtomType::LIST_LINK,
        "AND"         => AtomSpace::AtomType::AND_LINK,
        "OR"          => AtomSpace::AtomType::OR_LINK,
      }
      aliases[key]? || aliases[name.upcase]? || AtomSpace::AtomType::CONCEPT_NODE
    end
  end

  def self.start(args : Array(String) = [] of String)
    CogUtil.initialize
    AtomSpace.initialize
    PLN.initialize
    URE.initialize
    NLP.initialize

    shell = Shell.new

    if args.size > 0 && args[0] != "-i"
      puts shell.eval_line(args.join(" "))
      return
    end

    shell.run
  end

  def self.main(args = ARGV)
    start(args)
  end
end

# Allow `crystal run src/tools/cogshell.cr`
CogShell.main if PROGRAM_NAME.includes?("cogshell")
