# CogTools — crystalcog components (AtomSpace, PLN, URE, NLP) as named
# tools with JSON-schema parameters. The same tools serve three callers:
#
#   - a language model, through OpenAI-style function calling;
#   - chat interfaces, as slash commands ("/inherit cat animal");
#   - the command line ("crystalcog cog inherit cat animal").
#
# Every tool runs a CogShell command against one AtomSpace, so a fact a
# model adds is visible to PLN, to the next slash command and to the shell.

require "json"
require "./cogshell"

module CrystalCog
  class CogTools
    record Param, name : String, type : String, description : String, required : Bool = true

    # A tool: its schema, plus the CogShell command line it runs.
    record Tool, name : String, description : String, params : Array(Param), command : Proc(JSON::Any, String) do
      def schema : JSON::Any
        props = params.to_h { |p| {p.name, JSON::Any.new({"type" => JSON::Any.new(p.type), "description" => JSON::Any.new(p.description)})} }
        required = params.select(&.required).map { |p| JSON::Any.new(p.name) }
        JSON::Any.new({
          "type"     => JSON::Any.new("function"),
          "function" => JSON::Any.new({
            "name"        => JSON::Any.new(name),
            "description" => JSON::Any.new(description),
            "parameters"  => JSON::Any.new({"type" => JSON::Any.new("object"), "properties" => JSON::Any.new(props),
                                           "required" => JSON::Any.new(required)}),
          }),
        })
      end
    end

    getter shell : CogShell::Shell
    getter tools : Array(Tool)
    @mutex = Mutex.new

    def initialize(atomspace : AtomSpace::AtomSpace = AtomSpace::AtomSpace.new)
      @shell = CogShell::Shell.new(atomspace)
      @tools = build_tools
    end

    def atomspace : AtomSpace::AtomSpace
      @shell.atomspace
    end

    def names : Array(String)
      @tools.map(&.name)
    end

    def schemas : Array(JSON::Any)
      @tools.map(&.schema)
    end

    def [](name : String) : Tool
      @tools.find { |t| t.name == name } || raise ArgumentError.new("unknown tool #{name.inspect} (have: #{names.join(", ")})")
    end

    # Run a tool by name with JSON arguments (an object, or a JSON string of
    # one) and return its text output.
    def call(name : String, arguments : JSON::Any | String = "{}") : String
      args = arguments.is_a?(String) ? parse_args(arguments) : arguments
      args = JSON::Any.new({} of String => JSON::Any) unless args.as_h?
      run(self[name].command.call(args))
    end

    # Run one CogShell command line ("inherit cat animal", "reason 3").
    def run(command_line : String) : String
      @mutex.synchronize { @shell.eval_line(command_line).rstrip }
    end

    # A one-line summary of each tool, for help text.
    def help : String
      String.build do |io|
        @tools.each do |t|
          io << "  " << t.name
          t.params.each { |p| io << ' ' << (p.required ? "<#{p.name}>" : "[#{p.name}]") }
          io << "\n      " << t.description << '\n'
        end
      end
    end

    private def parse_args(s : String) : JSON::Any
      s.strip.empty? ? JSON::Any.new({} of String => JSON::Any) : JSON.parse(s)
    rescue JSON::ParseException
      raise ArgumentError.new("tool arguments are not JSON: #{s}")
    end

    private def str(args : JSON::Any, key : String) : String
      value = args[key]?
      text = value.try { |v| v.as_s? || (v.raw.nil? ? nil : v.to_json) }
      raise ArgumentError.new("missing argument #{key.inspect}") if text.nil? || text.strip.empty?
      text.strip
    end

    private def opt(args : JSON::Any, key : String) : String?
      args[key]?.try { |v| v.as_s? || v.as_i64?.try(&.to_s) || v.as_f?.try(&.to_s) }.try(&.strip.presence)
    end

    # Quote an argument for CogShell's tokenizer (it splits on spaces and
    # groups "double quoted" words; quotes themselves cannot be escaped).
    private def q(s : String) : String
      t = s.delete('"')
      t.includes?(' ') ? %("#{t}") : t
    end

    private def build_tools : Array(Tool)
      [
        Tool.new("add_inheritance", "Record that one concept is a kind of another (InheritanceLink child -> parent), " \
                                    "e.g. child=cat parent=animal.",
          [Param.new("child", "string", "The more specific concept"),
           Param.new("parent", "string", "The more general concept"),
           Param.new("strength", "number", "Truth strength 0..1 (default 1)", false),
           Param.new("confidence", "number", "Truth confidence 0..1 (default 0.9 when strength is given)", false)],
          ->(a : JSON::Any) {
            tv = opt(a, "strength").try { |s| " #{s} #{opt(a, "confidence") || "0.9"}" } || ""
            "inherit #{q(str(a, "child"))} #{q(str(a, "parent"))}#{tv}"
          }),
        Tool.new("add_evaluation", "Record that a predicate holds for some concepts (EvaluationLink), " \
                                   "e.g. predicate=likes arguments=[\"alice\", \"tea\"].",
          [Param.new("predicate", "string", "Predicate name"),
           Param.new("arguments", "array", "Concept names the predicate applies to")],
          ->(a : JSON::Any) {
            items = a["arguments"]?.try(&.as_a?).try(&.compact_map(&.as_s?)) ||
                    str(a, "arguments").split(/[,\s]+/).reject(&.empty?)
            raise ArgumentError.new("arguments must name at least one concept") if items.empty?
            "eval #{q(str(a, "predicate"))} #{items.map { |i| q(i) }.join(' ')}"
          }),
        Tool.new("add_implication", "Record that one concept implies another (ImplicationLink).",
          [Param.new("antecedent", "string", "The condition"), Param.new("consequent", "string", "What follows")],
          ->(a : JSON::Any) { "imply #{q(str(a, "antecedent"))} #{q(str(a, "consequent"))}" }),
        Tool.new("query_atoms", "Look up what the knowledge base holds for a name.",
          [Param.new("name", "string", "Atom name, e.g. cat")],
          ->(a : JSON::Any) { "query #{q(str(a, "name"))}" }),
        Tool.new("list_atoms", "List atoms in the knowledge base, optionally of one type " \
                               "(concept, predicate, inheritance, evaluation, implication).",
          [Param.new("type", "string", "Atom type filter", false)],
          ->(a : JSON::Any) { "list #{opt(a, "type")}".strip }),
        Tool.new("pln_reason", "Run PLN (probabilistic logic) inference over the knowledge base to derive new facts, " \
                               "e.g. cat->mammal and mammal->animal gives cat->animal.",
          [Param.new("steps", "integer", "Inference iterations (default 5)", false)],
          ->(a : JSON::Any) { "reason #{opt(a, "steps").try(&.to_f.to_i) || 5}" }),
        Tool.new("ure_forward_chain", "Run the Unified Rule Engine's forward chainer over the knowledge base.",
          Array(Param).new,
          ->(a : JSON::Any) { "ure" }),
        Tool.new("nlp_process", "Tokenize and analyse English text, adding word and sentence atoms to the knowledge base.",
          [Param.new("text", "string", "Text to process")],
          ->(a : JSON::Any) { "nlp #{str(a, "text").delete('"')}" }),
        Tool.new("parse_sentence", "Parse an English sentence with Link Grammar and show its linkages.",
          [Param.new("text", "string", "Sentence to parse")],
          ->(a : JSON::Any) { "parse #{str(a, "text").delete('"')}" }),
        Tool.new("see_image", "Look at an image file (PNG or PPM): find the coloured shapes in it and how they are " \
                              "arranged, describe them, and add them to the knowledge base as a scene.",
          [Param.new("path", "string", "Path of the image file"),
           Param.new("scene", "string", "Name for the scene (default: the file name)", false)],
          ->(a : JSON::Any) { "see #{q(str(a, "path"))} #{opt(a, "scene").try { |name| q(name) }}".strip }),
        Tool.new("atomspace_stats", "Show how many atoms, nodes and links the knowledge base holds.",
          Array(Param).new,
          ->(a : JSON::Any) { "size" }),
      ]
    end
  end
end
