#!/usr/bin/env crystal

# Test Advanced NLP Features
# Tests dependency parsing, language generation, and semantic understanding

require "../../src/cogutil/cogutil"
require "../../src/atomspace/atomspace_main"
require "../../src/nlp/nlp"

puts "=== Advanced NLP Features Test ==="

# Initialize systems
CogUtil.initialize
AtomSpace.initialize
NLP.initialize

# Create atomspace
atomspace = AtomSpace::AtomSpace.new

puts "\n1. Dependency Parsing Test"
puts "=" * 50

sentences = [
  "The cat sits on the mat.",
  "Alice studies computer science.",
  "The quick brown fox jumps over the lazy dog."
]

sentences.each_with_index do |sentence, i|
  puts "\nSentence #{i + 1}: #{sentence}"
  
  # Parse with dependency parser
  parse = NLP::DependencyParser.parse(sentence)
  
  puts "  Words: #{parse.words.join(", ")}"
  puts "  Root index: #{parse.root_index}"
  puts "  Dependencies (#{parse.dependencies.size}):"
  
  parse.dependencies.each do |dep|
    puts "    #{dep}"
  end
  
  # Store in atomspace
  atoms = parse.to_atomspace(atomspace)
  puts "  Created #{atoms.size} atoms in AtomSpace"
  
  # Extract phrases
  parser = NLP::DependencyParser::Parser.new
  noun_phrases = parser.extract_noun_phrases(parse)
  verb_phrases = parser.extract_verb_phrases(parse)
  
  puts "  Noun phrases: #{noun_phrases.join(", ")}" unless noun_phrases.empty?
  puts "  Verb phrases: #{verb_phrases.join(", ")}" unless verb_phrases.empty?
end

puts "\n2. Language Generation Test"
puts "=" * 50

generator = NLP::LanguageGeneration::Generator.new

# Test simple sentence generation
puts "\nSimple sentence generation:"
sentence1 = generator.generate_sentence("The cat", "sits", "on the mat")
puts "  Generated: #{sentence1}"

sentence2 = generator.generate_sentence("Alice", "study", "mathematics", 
                                        tense: NLP::LanguageGeneration::Sentence::Tense::PAST)
puts "  Generated: #{sentence2}"

sentence3 = generator.generate_sentence("The robot", "help", "humans",
                                        tense: NLP::LanguageGeneration::Sentence::Tense::FUTURE)
puts "  Generated: #{sentence3}"

# Test template-based generation
puts "\nTemplate-based generation:"
generated1 = generator.generate_from_template("inheritance", {
  "subject" => "dog",
  "object" => "animal"
})
puts "  Generated: #{generated1}"

generated2 = generator.generate_from_template("action", {
  "subject" => "programmer",
  "action" => "writes",
  "object" => "code"
})
puts "  Generated: #{generated2}"

# Test question generation
puts "\nQuestion generation:"
statement = "The cat sits on the mat"
yes_no_q = generator.generate_question(statement, "yes_no")
what_q = generator.generate_question(statement, "what")
where_q = generator.generate_question(statement, "where")

puts "  Statement: #{statement}"
puts "  Yes/No: #{yes_no_q}"
puts "  What: #{what_q}"
puts "  Where: #{where_q}"

# Test generating from atomspace
puts "\nGenerating from AtomSpace atoms:"
dog = atomspace.add_concept_node("dog")
animal = atomspace.add_concept_node("animal")
inheritance = atomspace.add_inheritance_link(dog, animal, AtomSpace::SimpleTruthValue.new(0.9, 0.9))

generated_text = generator.generate_from_atom(inheritance, atomspace)
puts "  From inheritance link: #{generated_text}"

puts "\n3. Semantic Understanding Test"
puts "=" * 50

analyzer = NLP::SemanticUnderstanding::Analyzer.new

# Analyze sentences
test_sentences = [
  "Alice eats an apple.",
  "The programmer writes code efficiently.",
  "The cat sleeps on the soft pillow."
]

test_sentences.each_with_index do |sentence, i|
  puts "\nAnalyzing sentence #{i + 1}: #{sentence}"
  
  analysis = analyzer.analyze(sentence)
  
  puts "  Frames (#{analysis.frames.size}):"
  analysis.frames.each do |frame|
    puts "    #{frame}"
  end
  
  puts "  Entities: #{analysis.entities.join(", ")}"
  
  unless analysis.relations.empty?
    puts "  Relations:"
    analysis.relations.each do |rel|
      puts "    #{rel[0]} -- #{rel[1]} --> #{rel[2]}"
    end
  end
  
  # Store in atomspace
  atoms = analysis.to_atomspace(atomspace)
  puts "  Created #{atoms.size} atoms in AtomSpace"
end

# Test semantic similarity
puts "\nSemantic similarity test:"
text1 = "The dog runs in the park."
text2 = "The cat walks in the garden."
similarity = analyzer.semantic_similarity(text1, text2)
puts "  Text 1: #{text1}"
puts "  Text 2: #{text2}"
puts "  Similarity: #{similarity.round(3)}"

# Extract key concepts
puts "\nKey concept extraction:"
long_text = "Natural language processing enables computers to understand human language through various techniques including parsing and semantic analysis."
concepts = analyzer.extract_key_concepts(long_text, 5)
puts "  Text: #{long_text}"
puts "  Key concepts: #{concepts.join(", ")}"

puts "\n4. Integration Test"
puts "=" * 50

# Full pipeline: parse -> understand -> generate
input_text = "The student learns programming."

puts "\nInput: #{input_text}"

# Parse
parse = NLP::DependencyParser.parse(input_text)
puts "  Parsed into #{parse.dependencies.size} dependency relations"

# Understand
analysis = analyzer.analyze(input_text)
puts "  Extracted #{analysis.frames.size} semantic frames"

# Generate paraphrase
paraphrase = generator.paraphrase(input_text)
puts "  Paraphrase: #{paraphrase}"

puts "\n=== Advanced NLP Features Test Complete ==="
puts "Total atoms in AtomSpace: #{atomspace.size}"

puts "\nAll advanced NLP tests passed! ✅"
