require "spec"
require "../../src/nlp/language_generation"

describe NLP::LanguageGeneration do
  describe "Template" do
    it "fills in slot values" do
      template = NLP::LanguageGeneration::Template.new("{subject} is {property}", ["subject", "property"])
      template.fill({"subject" => "Socrates", "property" => "mortal"}).should eq("Socrates is mortal")
    end

    it "leaves unfilled slots untouched" do
      template = NLP::LanguageGeneration::Template.new("{a} and {b}", ["a", "b"])
      template.fill({"a" => "x"}).should eq("x and {b}")
    end
  end

  describe "Sentence" do
    it "builds a capitalized, punctuated sentence" do
      sentence = NLP::LanguageGeneration::Sentence.new("cat", "sit", "mat")
      sentence.to_s.should eq("Cat sit mat.")
    end

    it "conjugates past tense" do
      sentence = NLP::LanguageGeneration::Sentence.new("dog", "bark", tense: NLP::LanguageGeneration::Sentence::Tense::PAST)
      sentence.to_s.should eq("Dog barked.")
    end

    it "conjugates future tense" do
      sentence = NLP::LanguageGeneration::Sentence.new("bird", "fly", tense: NLP::LanguageGeneration::Sentence::Tense::FUTURE)
      sentence.to_s.should eq("Bird will fly.")
    end
  end

  describe "Generator" do
    it "generates a simple sentence" do
      generator = NLP::LanguageGeneration::Generator.new
      generator.generate_sentence("cat", "sit", "mat").should eq("Cat sit mat.")
    end

    it "generates from a custom template" do
      generator = NLP::LanguageGeneration::Generator.new
      generator.add_template("greeting", "Hello, {name}!", ["name"])
      generator.generate_from_template("greeting", {"name" => "World"}).should eq("Hello, World!")
    end

    it "raises for an unknown template" do
      generator = NLP::LanguageGeneration::Generator.new
      expect_raises(NLP::LanguageGeneration::GenerationException) do
        generator.generate_from_template("missing", {} of String => String)
      end
    end

    it "paraphrases using simple synonyms" do
      generator = NLP::LanguageGeneration::Generator.new
      generator.paraphrase("the big dog is fast").should eq("the large dog is quick")
    end

    it "summarizes by taking the first sentences" do
      generator = NLP::LanguageGeneration::Generator.new
      summary = generator.summarize(["One.", "Two.", "Three.", "Four."], max_sentences: 2)
      summary.should eq("One. Two.")
    end

    it "generates a yes/no question from a statement" do
      generator = NLP::LanguageGeneration::Generator.new
      question = generator.generate_question("cats are animals", "yes_no")
      question.should end_with("?")
    end
  end
end
