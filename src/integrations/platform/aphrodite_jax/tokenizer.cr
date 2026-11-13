# Byte-level BPE tokenizer loaded from a Hugging Face tokenizer.json
# (GPT-2/Qwen style): NFC normalisation, added tokens split out first,
# regex pre-tokenisation, bytes mapped to printable code points, then BPE
# merges by rank.

require "json"

module AphroditeJax
  class Tokenizer
    # Qwen2/Qwen3 pre-tokenizer pattern (used when tokenizer.json has none).
    DEFAULT_PATTERN = %q((?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+)

    getter vocab : Hash(String, Int32)
    getter added : Hash(String, Int32)
    getter special_ids : Set(Int32)
    @id_to_token : Hash(Int32, String)
    @merge_ranks : Hash({String, String}, Int32)
    @byte_to_char : Array(Char)
    @char_to_byte : Hash(Char, UInt8)
    @pattern : Regex
    @added_pattern : Regex?
    @nfc : Bool
    @cache = {} of String => Array(Int32)

    def self.from_file(path : String) : Tokenizer
      new(JSON.parse(File.read(path)))
    end

    def initialize(json : JSON::Any)
      model = json["model"]
      raise ArgumentError.new("only BPE tokenizers are supported") unless model["type"]?.try(&.as_s?) == "BPE"

      @vocab = model["vocab"].as_h.transform_values(&.as_i)
      @merge_ranks = {} of {String, String} => Int32
      model["merges"].as_a.each_with_index do |m, rank|
        pair = m.as_s? ? m.as_s.split(' ', 2) : m.as_a.map(&.as_s)
        @merge_ranks[{pair[0], pair[1]}] = rank
      end

      @added = {} of String => Int32
      @special_ids = Set(Int32).new
      json["added_tokens"]?.try(&.as_a?).try &.each do |t|
        id = t["id"].as_i
        @added[t["content"].as_s] = id
        @special_ids << id if t["special"]?.try(&.as_bool?)
      end

      @id_to_token = {} of Int32 => String
      @vocab.each { |tok, id| @id_to_token[id] = tok }
      @added.each { |tok, id| @id_to_token[id] = tok }

      @byte_to_char = Tokenizer.bytes_to_unicode
      @char_to_byte = {} of Char => UInt8
      @byte_to_char.each_with_index { |c, b| @char_to_byte[c] = b.to_u8 }

      @pattern = Regex.new(find_split_pattern(json) || DEFAULT_PATTERN)
      unless @added.empty?
        alternatives = @added.keys.sort_by { |k| -k.size }.map { |k| Regex.escape(k) }
        @added_pattern = Regex.new(alternatives.join("|"))
      end
      @nfc = json["normalizer"]?.try { |n| n.to_json.includes?("NFC") } || false
    end

    def vocab_size : Int32
      (@id_to_token.keys.max? || -1) + 1
    end

    def token_id(token : String) : Int32?
      @added[token]? || @vocab[token]?
    end

    def encode(text : String) : Array(Int32)
      text = text.unicode_normalize(:nfc) if @nfc
      ids = [] of Int32
      pos = 0
      if pattern = @added_pattern
        text.scan(pattern) do |m|
          start = m.begin(0).not_nil!
          encode_ordinary(text[pos...start], ids) if start > pos
          ids << @added[m[0]]
          pos = m.end(0).not_nil!
        end
      end
      encode_ordinary(text[pos..], ids) if pos < text.size
      ids
    end

    def decode(ids : Enumerable(Int32), skip_special : Bool = false) : String
      bytes = IO::Memory.new
      ids.each do |id|
        token = @id_to_token[id]? || next
        if @added.has_key?(token)
          next if skip_special && @special_ids.includes?(id)
          bytes << token
        else
          token.each_char { |c| bytes.write_byte(@char_to_byte[c]? || '?'.ord.to_u8) }
        end
      end
      String.new(bytes.to_slice)
    end

    private def encode_ordinary(text : String, ids : Array(Int32))
      text.scan(@pattern) do |m|
        piece = m[0]
        if cached = @cache[piece]?
          ids.concat(cached)
          next
        end
        mapped = String.build { |io| piece.each_byte { |b| io << @byte_to_char[b] } }
        piece_ids = bpe(mapped).map { |sym| @vocab[sym]? || raise KeyError.new("token #{sym.inspect} not in vocab") }
        @cache[piece] = piece_ids if @cache.size < 100_000
        ids.concat(piece_ids)
      end
    end

    # Merge the lowest-ranked adjacent pair until no ranked pair remains.
    private def bpe(word : String) : Array(String)
      symbols = word.chars.map(&.to_s)
      return symbols if symbols.size < 2
      loop do
        best_rank = Int32::MAX
        best = -1
        (0...symbols.size - 1).each do |i|
          if (rank = @merge_ranks[{symbols[i], symbols[i + 1]}]?) && rank < best_rank
            best_rank = rank
            best = i
          end
        end
        break if best < 0
        left, right = symbols[best], symbols[best + 1]
        merged = [] of String
        i = 0
        while i < symbols.size
          if i < symbols.size - 1 && symbols[i] == left && symbols[i + 1] == right
            merged << left + right
            i += 2
          else
            merged << symbols[i]
            i += 1
          end
        end
        symbols = merged
        break if symbols.size == 1
      end
      symbols
    end

    private def find_split_pattern(json) : String?
      pre = json["pre_tokenizer"]?
      return nil unless pre
      list = pre["pretokenizers"]?.try(&.as_a?) || [pre]
      list.each do |p|
        if p["type"]?.try(&.as_s?) == "Split"
          return p.dig?("pattern", "Regex").try(&.as_s?)
        end
      end
      nil
    end

    # GPT-2's reversible byte -> printable code point table.
    def self.bytes_to_unicode : Array(Char)
      keep = ('!'.ord..'~'.ord).to_a + ('¡'.ord..'¬'.ord).to_a + ('®'.ord..'ÿ'.ord).to_a
      table = Array(Char).new(256, ' ')
      extra = 0
      256.times do |b|
        if keep.includes?(b)
          table[b] = b.chr
        else
          table[b] = (256 + extra).chr
          extra += 1
        end
      end
      table
    end
  end
end
