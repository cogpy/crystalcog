#!/usr/bin/env crystal
# Link Grammar Parser Integration Demo
#
# This demo showcases the Link Grammar parser integration in CrystalCog,
# demonstrating how sentences are parsed and represented in the AtomSpace.

require "../../src/nlp/nlp"

# Initialize all subsystems
CogUtil.initialize
AtomSpace.initialize
NLP.initialize

puts "="*70
puts "CrystalCog Link Grammar Parser Integration Demo"
puts "="*70

# Create an AtomSpace for storing linguistic knowledge
atomspace = AtomSpace::AtomSpace.new
puts "\nCreated AtomSpace for linguistic knowledge storage\n"

# Example sentences to parse
sentences = [
  "The cat sits on the mat.",
  "Dogs are loyal animals.",
  "Natural language processing enables understanding.",
  "The quick brown fox jumps over the lazy dog."
]

# Parse each sentence and display results
sentences.each_with_index do |sentence, idx|
  puts "\n#{"-"*70}"
  puts "Sentence #{idx + 1}: #{sentence}"
  puts "-"*70

  # Parse the sentence
  parser = NLP::LinkGrammar::Parser.new
  linkages = parser.parse(sentence)
  
  if linkages.empty?
    puts "No parse found!"
    next
  end

  linkage = linkages.first
  
  # Display parse information
  puts "\n📝 Parse Analysis:"
  puts "  Words: #{linkage.words.size}"
  puts "  Word list: #{linkage.words.join(", ")}"
  puts "  Links: #{linkage.links.size}"
  puts "  Disjuncts: #{linkage.disjuncts.size}"
  puts "  Parse cost: #{linkage.cost}"
  
  # Show links
  if linkage.links.size > 0
    puts "\n🔗 Links between words:"
    linkage.links.each do |link|
      left_word = linkage.words[link.left_word]
      right_word = linkage.words[link.right_word]
      puts "  #{left_word} -[#{link.label}]-> #{right_word}"
    end
  end
  
  # Show disjuncts
  if linkage.disjuncts.size > 0
    puts "\n🔧 Disjuncts (connector sets):"
    linkage.disjuncts.each do |disjunct|
      connectors_str = disjunct.connectors.map(&.to_s).join(" ")
      puts "  #{disjunct.word}: #{connectors_str}"
    end
  end
  
  # Store in AtomSpace
  atoms = linkage.to_atomspace(atomspace)
  puts "\n💾 AtomSpace Storage:"
  puts "  Created #{atoms.size} atoms for this sentence"
end

# Display overall AtomSpace statistics
puts "\n======================================================================"
puts "Overall AtomSpace Statistics"
puts "="*70
puts "Total atoms in AtomSpace: #{atomspace.size}"

# Count different atom types
word_nodes = atomspace.get_atoms_by_type(AtomSpace::AtomType::WORD_NODE)
word_instances = atomspace.get_atoms_by_type(AtomSpace::AtomType::WORD_INSTANCE_NODE)
parse_nodes = atomspace.get_atoms_by_type(AtomSpace::AtomType::PARSE_NODE)
link_nodes = atomspace.get_atoms_by_type(AtomSpace::AtomType::LG_LINK_NODE)
link_instances = atomspace.get_atoms_by_type(AtomSpace::AtomType::LG_LINK_INSTANCE_LINK)
sentence_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::SENTENCE_LINK)

puts "\nAtom Type Breakdown:"
puts "  WORD_NODE: #{word_nodes.size}"
puts "  WORD_INSTANCE_NODE: #{word_instances.size}"
puts "  PARSE_NODE: #{parse_nodes.size}"
puts "  LG_LINK_NODE: #{link_nodes.size}"
puts "  LG_LINK_INSTANCE_LINK: #{link_instances.size}"
puts "  SENTENCE_LINK: #{sentence_links.size}"

# Show unique words
puts "\n📚 Unique words in corpus:"
unique_words = word_nodes.map(&.name).sort
unique_words.each_slice(8) do |words|
  puts "  #{words.join(", ")}"
end

# Show link types used
puts "\n🏷️  Link types used:"
unique_links = link_nodes.map(&.name).uniq.sort
puts "  #{unique_links.join(", ")}"

# Integration with existing NLP modules
puts "\n======================================================================"
puts "Integration with Other NLP Modules"
puts "="*70

test_text = "The intelligent system processes natural language efficiently."

# Tokenization
tokens = NLP::Tokenizer.tokenize(test_text)
puts "\n🔤 Tokenization:"
puts "  Tokens: #{tokens.join(" | ")}"

# Keyword extraction
keywords = NLP::TextProcessor.extract_keywords(test_text, 5)
puts "\n🔑 Keywords:"
puts "  #{keywords.join(", ")}"

# Link Grammar parsing
lg_linkages = NLP::LinkGrammar.parse(test_text)
puts "\n🌳 Link Grammar Parse:"
puts "  Found #{lg_linkages.size} linkage(s)"
if lg_linkages.size > 0
  puts "  Words: #{lg_linkages.first.words.size}"
  puts "  Links: #{lg_linkages.first.links.size}"
end

# Text statistics
stats = NLP::TextProcessor.get_text_stats(test_text)
puts "\n📊 Text Statistics:"
puts "  Words: #{stats["word_count"]}"
puts "  Characters: #{stats["character_count"]}"
puts "  Sentences: #{stats["sentence_count"]}"
puts "  Unique words: #{stats["unique_words"]}"

# Linguistic atoms
lg_atoms = NLP::LinkGrammar.parse_to_atomspace(test_text, atomspace)
word_atoms = NLP::LinguisticAtoms.get_word_atoms(atomspace)
puts "\n🧠 Linguistic Knowledge:"
puts "  Link Grammar atoms created: #{lg_atoms.size}"
puts "  Total word atoms: #{word_atoms.size}"
puts "  Total AtomSpace size: #{atomspace.size}"

puts "\n======================================================================"
puts "Demo Complete!"
puts "="*70
puts "\nThe Link Grammar parser successfully:"
puts "  ✅ Parsed #{sentences.size} sentences"
puts "  ✅ Created detailed syntactic structures"
puts "  ✅ Stored parse results in AtomSpace"
puts "  ✅ Integrated with existing NLP modules"
puts "  ✅ Provided word-level and sentence-level analysis"
puts "\nThis integration enables advanced linguistic reasoning and"
puts "natural language understanding in the CrystalCog framework."
puts "\n"
