# Tokenizer module for basic text tokenization
#
# Provides functionality to split text into tokens (words, punctuation, etc.)
# following basic NLP tokenization rules.

module NLP
  module Tokenizer
    # Basic tokenization patterns
    WORD_PATTERN        = /[a-zA-Z]+/
    NUMBER_PATTERN      = /\d+(\.\d+)?/
    PUNCTUATION_PATTERN = /[.!?,:;]/
    WHITESPACE_PATTERN  = /\s+/

    # Tokenize text into an array of tokens
    def self.tokenize(text : String) : Array(String)
      raise TokenizationException.new("Cannot tokenize nil or empty text") if text.empty?

      CogUtil::Logger.debug("Tokenizing text: '#{text}'")

      tokens = [] of String

      # Simple whitespace-based tokenization with basic cleanup
      raw_tokens = text.downcase.split(WHITESPACE_PATTERN)

      raw_tokens.each do |token|
        # Skip empty tokens
        next if token.empty?

        # Handle punctuation attached to words
        cleaned_token = clean_token(token)
        tokens << cleaned_token unless cleaned_token.empty?
      end

      CogUtil::Logger.debug("Tokenized into #{tokens.size} tokens: #{tokens[0..5]}")
      tokens
    end

    # Advanced tokenization that preserves sentence structure
    def self.tokenize_sentences(text : String) : Array(Array(String))
      sentences = split_sentences(text)
      sentences.map { |sentence| tokenize(sentence) }
    end

    # Split text into sentences based on punctuation
    def self.split_sentences(text : String) : Array(String)
      # Simple sentence splitting on period, exclamation, question mark
      sentences = text.split(/[.!?]+/)
        .map(&.strip)
        .reject(&.empty?)

      CogUtil::Logger.debug("Split into #{sentences.size} sentences")
      sentences
    end

    # Check if a token is a word (contains only letters)
    def self.is_word?(token : String) : Bool
      !!(token.match(/^[a-zA-Z]+$/))
    end

    # Check if a token is a number
    def self.is_number?(token : String) : Bool
      !!(token.match(/^\d+(\.\d+)?$/))
    end

    # Check if a token is punctuation
    def self.is_punctuation?(token : String) : Bool
      !!token.match(PUNCTUATION_PATTERN)
    end

    # Get token type classification
    def self.get_token_type(token : String) : String
      return "word" if is_word?(token)
      return "number" if is_number?(token)
      return "punctuation" if is_punctuation?(token)
      "other"
    end

    # Clean a token by removing attached punctuation and normalizing
    private def self.clean_token(token : String) : String
      # Remove leading/trailing punctuation but preserve it as separate tokens
      cleaned = token.gsub(/^[^\w]+|[^\w]+$/, "")

      # Handle special cases
      cleaned = cleaned.strip

      # Normalize common contractions and special cases
      case cleaned
      when "won't"
        "will not"
      when "can't"
        "cannot"
      when "n't"
        "not"
      else
        cleaned
      end
    end

    # Advanced tokenization with linguistic features
    def self.tokenize_with_features(text : String) : Array(NamedTuple(token: String, type: String, position: Int32))
      tokens = tokenize(text)

      tokens.map_with_index do |token, index|
        {
          token:    token,
          type:     get_token_type(token),
          position: index,
        }
      end
    end

    # Get token statistics
    def self.get_token_stats(tokens : Array(String)) : Hash(String, Int32)
      types = tokens.map { |token| get_token_type(token) }

      {
        "total_tokens"  => tokens.size,
        "unique_tokens" => tokens.uniq.size,
        "words"         => types.count("word"),
        "numbers"       => types.count("number"),
        "punctuation"   => types.count("punctuation"),
        "other"         => types.count("other"),
      }
    end
  end
end
