# Qwen3's chat format with function calling, written out by hand instead
# of running the model's Jinja template:
#
#   - tools go into the system turn as JSON lines in <tools>...</tools>;
#   - the model answers a call with <tool_call>{"name": .., "arguments": {..}}</tool_call>;
#   - results come back in a user turn as <tool_response>...</tool_response>
#     blocks, one per result.
#
# Messages are OpenAI chat messages (role, content, tool_calls, tool_call_id).

require "json"

module AphroditeJax
  module ChatFormat
    TOOL_CALL_OPEN  = "<tool_call>"
    TOOL_CALL_CLOSE = "</tool_call>"

    record ToolCall, name : String, arguments : JSON::Any do
      def arguments_json : String
        arguments.to_json
      end
    end

    TOOLS_PREAMBLE = "# Tools\n\nYou may call one or more functions to assist with the user query.\n\n" \
                     "You are provided with function signatures within <tools></tools> XML tags:\n<tools>"
    TOOLS_POSTAMBLE = "\n</tools>\n\nFor each function call, return a json object with function name and arguments " \
                      "within <tool_call></tool_call> XML tags:\n<tool_call>\n{\"name\": <function-name>, " \
                      "\"arguments\": <args-json-object>}\n</tool_call>"

    # Text of a message's content: a string, or an array of {type: text} parts.
    def self.text_of(content : JSON::Any?) : String
      return "" unless content
      content.as_s? || content.as_a?.try(&.compact_map { |p| p["text"]?.try(&.as_s?) }.join) || ""
    end

    # The prompt for `messages`, ending with an open assistant turn. Unless
    # `thinking`, Qwen3's reasoning mode is turned off with an empty think
    # block.
    def self.prompt(messages : Array(JSON::Any), tools : Array(JSON::Any)? = nil, thinking : Bool = false) : String
      String.build do |io|
        rest = messages
        if tools && !tools.empty?
          io << "<|im_start|>system\n"
          if (first = messages.first?) && first["role"]?.try(&.as_s?) == "system"
            io << text_of(first["content"]?) << "\n\n"
            rest = messages[1..]
          end
          io << TOOLS_PREAMBLE
          tools.each { |t| io << '\n' << dumps(t) }
          io << TOOLS_POSTAMBLE << "<|im_end|>\n"
        end

        in_responses = false
        rest.each do |m|
          role = m["role"]?.try(&.as_s?) || "user"
          if role == "tool"
            io << "<|im_start|>user" unless in_responses
            io << "\n<tool_response>\n" << text_of(m["content"]?) << "\n</tool_response>"
            in_responses = true
            next
          end
          if in_responses
            io << "<|im_end|>\n"
            in_responses = false
          end
          content = text_of(m["content"]?)
          content = strip_reasoning(content) if role == "assistant"
          io << "<|im_start|>" << role << '\n' << content
          if role == "assistant" && (calls = m["tool_calls"]?.try(&.as_a?))
            calls.each_with_index do |call, i|
              fn = call["function"]? || call
              io << '\n' if i > 0 || !content.empty?
              io << TOOL_CALL_OPEN << "\n{\"name\": \"" << fn["name"]?.try(&.as_s?) << "\", \"arguments\": " << dumps(arguments(fn["arguments"]?)) << '}'
              io << '\n' << TOOL_CALL_CLOSE
            end
          end
          io << "<|im_end|>\n"
        end
        io << "<|im_end|>\n" if in_responses
        io << (thinking ? "<|im_start|>assistant\n" : "<|im_start|>assistant\n<think>\n\n</think>\n\n")
      end
    end

    # The text after Qwen3's <think>...</think> reasoning block, if any.
    def self.strip_reasoning(text : String) : String
      if close = text.index("</think>")
        text[close + "</think>".size..].lstrip
      else
        text
      end
    end

    # Split generated text into its plain content and the tool calls it
    # makes. A block that is not valid JSON with a "name" stays in the text.
    # Small models sometimes write a call as an XML element instead
    # (<query_atoms name="cat"/>); given the tool names, those count too.
    def self.parse(text : String, tool_names : Enumerable(String)? = nil) : {String, Array(ToolCall)}
      text = strip_reasoning(text)
      if tool_names && !text.includes?(TOOL_CALL_OPEN)
        xml = xml_calls(text, tool_names)
        return xml unless xml[1].empty?
      end
      calls = [] of ToolCall
      content = String.build do |io|
        pos = 0
        while open = text.index(TOOL_CALL_OPEN, pos)
          close = text.index(TOOL_CALL_CLOSE, open)
          body_end = close || text.size
          if call = parse_call(text[open + TOOL_CALL_OPEN.size...body_end])
            io << text[pos...open]
            calls << call
          else
            io << text[pos...body_end]
          end
          pos = close ? close + TOOL_CALL_CLOSE.size : text.size
        end
        io << text[pos..] if pos < text.size
      end
      {content.strip, calls}
    end

    private def self.parse_call(body : String) : ToolCall?
      json = JSON.parse(body.strip)
      name = json["name"]?.try(&.as_s?) || return nil
      ToolCall.new(name, arguments(json["arguments"]? || json["parameters"]?))
    rescue JSON::ParseException
      nil
    end

    XML_CALL = /<([A-Za-z_][\w.-]*)((?:\s+[\w-]+\s*=\s*"[^"]*")*)\s*\/?>(?:\s*<\/\1>)?/

    private def self.xml_calls(text : String, tool_names : Enumerable(String)) : {String, Array(ToolCall)}
      calls = [] of ToolCall
      content = text.scrub.gsub(XML_CALL) do |whole, m|
        next whole unless tool_names.includes?(m[1])
        args = {} of String => JSON::Any
        m[2].scan(/([\w-]+)\s*=\s*"([^"]*)"/) { |a| args[a[1]] = JSON::Any.new(a[2]) }
        calls << ToolCall.new(m[1], JSON::Any.new(args))
        ""
      end
      {content.strip, calls}
    end

    # JSON the way the template's `tojson` writes it (Python's json.dumps:
    # ", " and ": " separators, non-ASCII kept).
    def self.dumps(value : JSON::Any) : String
      String.build { |io| dump(io, value) }
    end

    private def self.dump(io : IO, value : JSON::Any)
      if h = value.as_h?
        io << '{'
        h.each_with_index do |(k, v), i|
          io << ", " if i > 0
          k.to_json(io)
          io << ": "
          dump(io, v)
        end
        io << '}'
      elsif a = value.as_a?
        io << '['
        a.each_with_index do |v, i|
          io << ", " if i > 0
          dump(io, v)
        end
        io << ']'
      else
        value.to_json(io)
      end
    end

    # Arguments as a JSON object; OpenAI sends them as a JSON-encoded string.
    def self.arguments(args : JSON::Any?) : JSON::Any
      return JSON::Any.new({} of String => JSON::Any) unless args
      if s = args.as_s?
        begin
          return JSON.parse(s)
        rescue JSON::ParseException
          return JSON::Any.new(s)
        end
      end
      args
    end
  end
end
