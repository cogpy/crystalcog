# Text processing utilities for natural language processing
#
# Provides text preprocessing, normalization, and analysis functions.

module NLP
  module TextProcessor
    # Text normalization and preprocessing

    # Normalize text for processing
    def self.normalize_text(text : String) : String
      raise TextProcessingException.new("Cannot process nil or empty text") if text.empty?

      CogUtil::Logger.debug("Normalizing text: '#{text[0..50]}...'")

      # Convert to lowercase
      normalized = text.downcase

      # Remove extra whitespace
      normalized = normalized.gsub(/\s+/, " ").strip

      # Handle common unicode issues
      normalized = normalized.gsub(/[""'']/, "\"")
      normalized = normalized.gsub(/[–—]/, "-")

      # Remove control characters
      normalized = normalized.gsub(/[\x00-\x1f\x7f]/, "")

      CogUtil::Logger.debug("Text normalized")
      normalized
    end

    # Remove common stop words
    def self.remove_stop_words(tokens : Array(String)) : Array(String)
      stop_words = get_stop_words
      filtered = tokens.reject { |token| stop_words.includes?(token) }

      CogUtil::Logger.debug("Removed #{tokens.size - filtered.size} stop words")
      filtered
    end

    # Get common English stop words
    def self.get_stop_words : Set(String)
      Set{
        "a", "an", "and", "are", "as", "at", "be", "been", "by", "for",
        "from", "has", "he", "in", "is", "it", "its", "of", "on", "that",
        "the", "to", "was", "will", "with", "would", "i", "you", "we",
        "they", "them", "this", "these", "those", "there", "their", "his",
        "her", "my", "our", "your", "me", "him", "us", "can", "could",
        "should", "have", "had", "do", "does", "did", "not", "no", "yes",
      }
    end

    # Extract n-grams from tokens
    def self.extract_ngrams(tokens : Array(String), n : Int32) : Array(Array(String))
      raise TextProcessingException.new("N-gram size must be positive") if n <= 0
      raise TextProcessingException.new("Not enough tokens for n-grams") if tokens.size < n

      ngrams = [] of Array(String)

      (0..tokens.size - n).each do |i|
        ngram = tokens[i, n]
        ngrams << ngram
      end

      CogUtil::Logger.debug("Extracted #{ngrams.size} #{n}-grams")
      ngrams
    end

    # Calculate basic text statistics
    def self.get_text_stats(text : String) : Hash(String, Int32 | Float64)
      tokens = Tokenizer.tokenize(text)
      sentences = Tokenizer.split_sentences(text)

      # Character counts
      char_count = text.size
      alpha_count = text.count { |c| c.letter? }
      digit_count = text.count { |c| c.number? }
      space_count = text.count { |c| c.whitespace? }

      # Word statistics
      word_tokens = tokens.select { |t| Tokenizer.is_word?(t) }
      avg_word_length = word_tokens.empty? ? 0.0 : word_tokens.sum(&.size).to_f / word_tokens.size

      # Sentence statistics
      avg_sentence_length = sentences.empty? ? 0.0 : tokens.size.to_f / sentences.size

      {
        "character_count"         => char_count,
        "alphabetic_count"        => alpha_count,
        "digit_count"             => digit_count,
        "whitespace_count"        => space_count,
        "token_count"             => tokens.size,
        "word_count"              => word_tokens.size,
        "sentence_count"          => sentences.size,
        "average_word_length"     => avg_word_length,
        "average_sentence_length" => avg_sentence_length,
        "unique_words"            => word_tokens.uniq.size,
      }
    end

    # Simple stemming (remove common suffixes)
    def self.simple_stem(word : String) : String
      return word if word.size <= 3

      # Remove common English suffixes
      stemmed = word

      # Plural forms
      if word.ends_with?("ies") && word.size > 4
        stemmed = word[0..-4] + "y"
      elsif word.ends_with?("ves") && word.size > 4
        stemmed = word[0..-4] + "f"
      elsif word.ends_with?("s") && !word.ends_with?("ss") && word.size > 2
        stemmed = word[0..-2]
      end

      # Past tense
      if stemmed.ends_with?("ed") && stemmed.size > 3
        stemmed = stemmed[0..-3]
      end

      # Present participle
      if stemmed.ends_with?("ing") && stemmed.size > 4
        stemmed = stemmed[0..-4]
      end

      # Comparative/superlative
      if stemmed.ends_with?("er") && stemmed.size > 3
        stemmed = stemmed[0..-3]
      elsif stemmed.ends_with?("est") && stemmed.size > 4
        stemmed = stemmed[0..-4]
      end

      # Reduce doubled final consonant (e.g. "bigg" -> "big", "runn" -> "run")
      if stemmed.size >= 3 && stemmed[-1] == stemmed[-2] && !stemmed[-1].in?('e', 'o', 'l', 's')
        stemmed = stemmed[0..-2]
      end

      stemmed
    end

    # Apply stemming to all tokens
    def self.stem_tokens(tokens : Array(String)) : Array(String)
      stemmed = tokens.map { |token| Tokenizer.is_word?(token) ? simple_stem(token) : token }

      CogUtil::Logger.debug("Applied stemming to #{tokens.size} tokens")
      stemmed
    end

    # Calculate term frequency
    def self.calculate_term_frequency(tokens : Array(String)) : Hash(String, Float64)
      total_tokens = tokens.size.to_f
      frequency_counts = Hash(String, Int32).new(0)

      tokens.each { |token| frequency_counts[token] += 1 }

      term_frequencies = Hash(String, Float64).new
      frequency_counts.each do |term, count|
        term_frequencies[term] = count.to_f / total_tokens
      end

      term_frequencies
    end

    # Extract keywords using simple frequency analysis
    def self.extract_keywords(text : String, max_keywords : Int32 = 10) : Array(String)
      # Normalize and tokenize
      normalized = normalize_text(text)
      tokens = Tokenizer.tokenize(normalized)

      # Remove stop words and apply stemming
      content_tokens = remove_stop_words(tokens)
      stemmed_tokens = stem_tokens(content_tokens)

      # Calculate frequencies
      tf = calculate_term_frequency(stemmed_tokens)

      # Sort by frequency and take top keywords
      keywords = tf.to_a
        .sort_by { |_, freq| -freq }
        .first(max_keywords)
        .map { |term, _| term }

      CogUtil::Logger.debug("Extracted #{keywords.size} keywords: #{keywords[0..2]}")
      keywords
    end
  end
end
