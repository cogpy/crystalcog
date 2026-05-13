require "spec"
require "../../src/nlp/nlp"

describe NLP::TextProcessor do
  describe "text normalization" do
    it "normalizes basic text" do
      text = "HELLO   World\t\nTest"
      normalized = NLP::TextProcessor.normalize_text(text)

      normalized.should eq("hello world test")
    end

    it "removes extra whitespace" do
      text = "word1   word2\t\tword3\n\nword4"
      normalized = NLP::TextProcessor.normalize_text(text)

      normalized.should eq("word1 word2 word3 word4")
    end

    it "handles unicode characters" do
      text = "\"Hello\" and 'world' with – dash"
      normalized = NLP::TextProcessor.normalize_text(text)

      # Should normalize unicode quotes and dashes
      normalized.should contain("\"")
      normalized.should contain("-")
    end

    it "raises exception for empty text" do
      expect_raises(NLP::TextProcessingException) do
        NLP::TextProcessor.normalize_text("")
      end
    end
  end

  describe "stop word removal" do
    it "removes common stop words" do
      tokens = ["the", "quick", "brown", "fox", "is", "running"]
      filtered = NLP::TextProcessor.remove_stop_words(tokens)

      filtered.should_not contain("the")
      filtered.should_not contain("is")
      filtered.should contain("quick")
      filtered.should contain("brown")
      filtered.should contain("fox")
      filtered.should contain("running")
    end

    it "preserves content words" do
      tokens = ["cat", "dog", "house", "blue"]
      filtered = NLP::TextProcessor.remove_stop_words(tokens)

      filtered.should eq(tokens) # No stop words to remove
    end

    it "handles empty token array" do
      tokens = [] of String
      filtered = NLP::TextProcessor.remove_stop_words(tokens)

      filtered.should eq([] of String)
    end
  end

  describe "n-gram extraction" do
    it "extracts bigrams correctly" do
      tokens = ["the", "quick", "brown", "fox"]
      bigrams = NLP::TextProcessor.extract_ngrams(tokens, 2)

      bigrams.size.should eq(3)
      bigrams[0].should eq(["the", "quick"])
      bigrams[1].should eq(["quick", "brown"])
      bigrams[2].should eq(["brown", "fox"])
    end

    it "extracts trigrams correctly" do
      tokens = ["the", "quick", "brown", "fox", "jumps"]
      trigrams = NLP::TextProcessor.extract_ngrams(tokens, 3)

      trigrams.size.should eq(3)
      trigrams[0].should eq(["the", "quick", "brown"])
      trigrams[1].should eq(["quick", "brown", "fox"])
      trigrams[2].should eq(["brown", "fox", "jumps"])
    end

    it "handles edge cases for n-grams" do
      tokens = ["single"]

      expect_raises(NLP::TextProcessingException) do
        NLP::TextProcessor.extract_ngrams(tokens, 2)
      end

      expect_raises(NLP::TextProcessingException) do
        NLP::TextProcessor.extract_ngrams(tokens, 0)
      end
    end
  end

  describe "text statistics" do
    it "calculates comprehensive statistics" do
      text = "Hello world! This is a test."
      stats = NLP::TextProcessor.get_text_stats(text)

      stats["character_count"].should be > 0
      stats["token_count"].should be > 0
      stats["word_count"].should be > 0
      stats["sentence_count"].should be > 0
      stats["average_word_length"].should be > 0.0
      stats["average_sentence_length"].should be > 0.0
    end

    it "handles text with numbers and punctuation" do
      text = "There are 123 items. Cost is $45.67."
      stats = NLP::TextProcessor.get_text_stats(text)

      stats["digit_count"].should be > 0
      stats["alphabetic_count"].should be > 0
      stats["character_count"].should be > 0
    end

    it "calculates unique word count" do
      text = "the cat and the dog and the bird"
      stats = NLP::TextProcessor.get_text_stats(text)

      stats["word_count"].should eq(7)   # Total words
      stats["unique_words"].should eq(5) # cat, dog, bird, and, the
    end
  end

  describe "stemming" do
    it "handles plural forms" do
      NLP::TextProcessor.simple_stem("cats").should eq("cat")
      NLP::TextProcessor.simple_stem("dogs").should eq("dog")
      NLP::TextProcessor.simple_stem("boxes").should eq("boxe") # Basic rule
    end

    it "handles past tense" do
      NLP::TextProcessor.simple_stem("walked").should eq("walk")
      NLP::TextProcessor.simple_stem("jumped").should eq("jump")
    end

    it "handles gerunds" do
      NLP::TextProcessor.simple_stem("walking").should eq("walk")
      NLP::TextProcessor.simple_stem("running").should eq("runn")
    end

    it "handles comparative forms" do
      NLP::TextProcessor.simple_stem("bigger").should eq("big")
      NLP::TextProcessor.simple_stem("fastest").should eq("fast")
    end

    it "preserves short words" do
      NLP::TextProcessor.simple_stem("cat").should eq("cat")
      NLP::TextProcessor.simple_stem("is").should eq("is")
    end

    it "stems token arrays" do
      tokens = ["cats", "running", "jumped", "bigger"]
      stemmed = NLP::TextProcessor.stem_tokens(tokens)

      stemmed.should contain("cat")
      stemmed.should contain("runn")
      stemmed.should contain("jump")
      stemmed.should contain("big")
    end
  end

  describe "term frequency" do
    it "calculates correct frequencies" do
      tokens = ["cat", "dog", "cat", "bird"]
      tf = NLP::TextProcessor.calculate_term_frequency(tokens)

      tf["cat"].should eq(0.5)   # 2 out of 4
      tf["dog"].should eq(0.25)  # 1 out of 4
      tf["bird"].should eq(0.25) # 1 out of 4
    end

    it "handles single token" do
      tokens = ["single"]
      tf = NLP::TextProcessor.calculate_term_frequency(tokens)

      tf["single"].should eq(1.0)
    end
  end

  describe "keyword extraction" do
    it "extracts keywords from text" do
      text = "The cat sat on the mat. The dog ran in the park. Cats are animals."
      keywords = NLP::TextProcessor.extract_keywords(text, 5)

      keywords.size.should be <= 5
      keywords.should be_a(Array(String))

      # Should prefer content words over stop words
      keywords.should_not contain("the")
      keywords.should_not contain("on")
    end

    it "handles short text" do
      text = "Short text"
      keywords = NLP::TextProcessor.extract_keywords(text, 10)

      keywords.size.should be <= 2
      keywords.should contain("short")
      keywords.should contain("text")
    end

    it "respects maximum keyword limit" do
      text = "word1 word2 word3 word4 word5 word6 word7 word8"
      keywords = NLP::TextProcessor.extract_keywords(text, 3)

      keywords.size.should eq(3)
    end
  end

  describe "stop words" do
    it "provides a comprehensive stop word list" do
      stop_words = NLP::TextProcessor.get_stop_words

      stop_words.should contain("the")
      stop_words.should contain("and")
      stop_words.should contain("is")
      stop_words.should contain("of")
      stop_words.should_not contain("cat")
      stop_words.should_not contain("house")
    end
  end

  describe "error handling" do
    it "handles empty input gracefully" do
      expect_raises(NLP::TextProcessingException) do
        NLP::TextProcessor.normalize_text("")
      end
    end

    it "handles invalid n-gram parameters" do
      tokens = ["a", "b"]

      expect_raises(NLP::TextProcessingException) do
        NLP::TextProcessor.extract_ngrams(tokens, 0)
      end

      expect_raises(NLP::TextProcessingException) do
        NLP::TextProcessor.extract_ngrams(tokens, 3) # More than available tokens
      end
    end
  end
end
