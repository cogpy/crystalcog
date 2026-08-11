require "spec"
require "../../src/nlp/nlp"

describe NLP::Advanced::NamedEntityRecognizer do
  it "recognizes gazetteer entities" do
    ner = NLP::Advanced::NamedEntityRecognizer.new
    ents = ner.recognize("Alice met Bob in London on Monday")
    types = ents.map(&.entity_type)
    types.should contain(NLP::Advanced::EntityType::PERSON)
    types.should contain(NLP::Advanced::EntityType::LOCATION)
    types.should contain(NLP::Advanced::EntityType::DATE)
  end

  it "recognizes money and dates via patterns" do
    ner = NLP::Advanced::NamedEntityRecognizer.new
    ents = ner.recognize("Paid $42.50 in 2024")
    ents.map(&.entity_type).should contain(NLP::Advanced::EntityType::MONEY)
    ents.map(&.entity_type).should contain(NLP::Advanced::EntityType::DATE)
  end

  it "exports entities to atomspace" do
    atomspace = AtomSpace::AtomSpace.new
    ner = NLP::Advanced::NamedEntityRecognizer.new
    atoms = ner.to_atomspace("Google hired Mary", atomspace)
    atoms.should_not be_empty
  end
end

describe NLP::Advanced::CoreferenceResolver do
  it "links pronouns to prior noun mentions" do
    resolver = NLP::Advanced::CoreferenceResolver.new
    mentions = resolver.resolve("John arrived. He sat down.")
    pronoun = mentions.find { |m| m.is_pronoun }
    pronoun.should_not be_nil
    pronoun.not_nil!.referent.should eq("John")
  end

  it "rewrites pronouns with antecedents" do
    resolver = NLP::Advanced::CoreferenceResolver.new
    rewritten = resolver.rewrite("Mary left. She smiled.")
    rewritten.should contain("Mary")
  end

  it "builds coreference clusters" do
    clusters = NLP::Advanced::CoreferenceResolver.new.clusters("Bob ran. He won.")
    clusters.keys.should contain("Bob")
  end
end

describe NLP::Advanced::WordSenseDisambiguator do
  it "disambiguates bank in financial context" do
    wsd = NLP::Advanced::WordSenseDisambiguator.new
    sense = wsd.disambiguate("bank", "I deposited money in my account at the bank")
    sense.should_not be_nil
    sense.not_nil!.id.should eq("bank.n.01")
  end

  it "disambiguates bank in river context" do
    wsd = NLP::Advanced::WordSenseDisambiguator.new
    sense = wsd.disambiguate("bank", "We walked along the river shore and sat on the bank")
    sense.should_not be_nil
    sense.not_nil!.id.should eq("bank.n.02")
  end

  it "returns multiple senses for ambiguous words" do
    wsd = NLP::Advanced::WordSenseDisambiguator.new
    wsd.senses_for("crane").size.should eq(2)
  end
end

describe NLP::Advanced::MultilingualSupport do
  it "tokenizes and strips English stopwords" do
    ml = NLP::Advanced::MultilingualSupport.new
    tokens = ml.tokenize("the quick brown fox", "en")
    filtered = ml.remove_stopwords(tokens, "en")
    filtered.should_not contain("the")
    filtered.should contain("quick")
  end

  it "detects language from stopwords" do
    ml = NLP::Advanced::MultilingualSupport.new
    ml.detect_language("el gato es grande y la casa").should eq("es")
  end

  it "lists supported languages" do
    ml = NLP::Advanced::MultilingualSupport.new
    ml.supported_languages.should contain("en")
    ml.supported_languages.should contain("fr")
  end

  it "registers a custom language" do
    ml = NLP::Advanced::MultilingualSupport.new
    ml.register_language("it", ["il", "lo", "la", "di", "e"])
    ml.supported_languages.should contain("it")
  end
end

describe NLP::Advanced::DiscoursePlanner do
  it "plans discourse with connectives" do
    planner = NLP::Advanced::DiscoursePlanner.new
    units = [
      NLP::Advanced::DiscourseUnit.new("The system started."),
      NLP::Advanced::DiscourseUnit.new("It loaded modules.", NLP::Advanced::DiscourseRelation::SEQUENCE),
      NLP::Advanced::DiscourseUnit.new("Errors were rare.", NLP::Advanced::DiscourseRelation::CONTRAST),
    ]
    text = planner.plan(units)
    text.should contain("The system started")
    text.downcase.should contain("however")
  end

  it "prioritizes by importance" do
    planner = NLP::Advanced::DiscoursePlanner.new
    units = [
      NLP::Advanced::DiscourseUnit.new("low", nil, 0.1),
      NLP::Advanced::DiscourseUnit.new("high", nil, 0.9),
    ]
    planner.prioritize(units).first.content.should eq("high")
  end
end

describe NLP::Advanced::StylisticAdapter do
  it "adapts to formal style" do
    adapter = NLP::Advanced::StylisticAdapter.new
    adapter.adapt("I can't go", NLP::Advanced::Style::FORMAL).should contain("cannot")
  end

  it "adapts to casual style" do
    adapter = NLP::Advanced::StylisticAdapter.new
    adapter.adapt("I cannot go", NLP::Advanced::Style::CASUAL).should contain("can't")
  end

  it "adapts to simple style" do
    adapter = NLP::Advanced::StylisticAdapter.new
    adapter.adapt("Please utilize the tool", NLP::Advanced::Style::SIMPLE).should contain("use")
  end
end

describe "LanguageGeneration style and discourse hooks" do
  it "generates discourse and adapts style" do
    gen = NLP::LanguageGeneration::Generator.new
    units = [
      NLP::Advanced::DiscourseUnit.new("Cats are mammals."),
      NLP::Advanced::DiscourseUnit.new("Dogs are mammals.", NLP::Advanced::DiscourseRelation::ELABORATION),
    ]
    text = gen.generate_discourse(units)
    text.should_not be_empty
    formal = gen.adapt_style("I don't know", NLP::Advanced::Style::FORMAL)
    formal.should contain("do not")
  end
end
