# Natural Language Processing (NLP) Module

This module provides comprehensive natural language processing functionality for the CrystalCog OpenCog implementation. It includes text tokenization, processing, Link Grammar parsing, and integration with the AtomSpace for storing linguistic knowledge.

## Features

### Core Functionality

- **Text Tokenization**: Split text into words, sentences, and tokens with classification
- **Text Processing**: Normalization, stop word removal, stemming, and keyword extraction  
- **Link Grammar Parsing**: Advanced syntactic parsing with dependency structures
- **AtomSpace Integration**: Store linguistic knowledge as atoms and relationships
- **Semantic Relations**: Create and manage semantic relationships between words
- **Statistical Analysis**: Calculate text and linguistic complexity metrics

### Modules

#### `NLP::Tokenizer`
- Basic and advanced tokenization
- Token classification (words, numbers, punctuation)
- Sentence splitting
- N-gram extraction
- Token feature analysis

#### `NLP::TextProcessor`
- Text normalization and preprocessing
- Stop word removal (English)
- Simple stemming algorithm
- Term frequency calculation
- Keyword extraction
- Text statistics

#### `NLP::LinguisticAtoms`
- Word atom creation with part-of-speech tagging
- Sentence structure representation in AtomSpace
- Semantic relationship creation (synonyms, antonyms, hypernyms)
- Parse tree structures
- Linguistic complexity metrics

#### `NLP::LinkGrammar` ⭐ ADVANCED
- Syntactic parsing with Link Grammar
- Dependency structure extraction
- Parse result representation in AtomSpace
- Linkage analysis (links, disjuncts, connectors)
- Multiple language support (English by default)
- Dictionary lookup capabilities

#### `NLP::DependencyParser` ⭐ ADVANCED
- Universal Dependencies parsing
- Dependency tree construction
- Grammatical relation extraction
- AtomSpace representation of dependency structures
- Integration with Link Grammar parser

#### `NLP::LanguageGeneration` ⭐ ADVANCED
- Natural language text generation
- Template-based generation
- Sentence construction from semantic atoms
- Multi-tense support (present, past, future)
- Clause and phrase generation

#### `NLP::SemanticUnderstanding` ⭐ ADVANCED
- Semantic role labeling (agent, patient, theme, etc.)
- Frame-based semantic analysis
- Predicate-argument structure extraction
- Semantic frame representation in AtomSpace
- Entity relationship extraction

## Usage Examples

### Basic Text Processing

```crystal
require "./src/nlp/nlp"

# Initialize systems
CogUtil.initialize
AtomSpace.initialize
NLP.initialize

# Create an AtomSpace
atomspace = AtomSpace::AtomSpace.new

# Process text
text = "The quick brown fox jumps over the lazy dog."
atoms = NLP.process_text(text, atomspace)

puts "Created #{atoms.size} atoms from text processing"
```

### Tokenization

```crystal
# Basic tokenization
text = "Hello, world! This is a test."
tokens = NLP::Tokenizer.tokenize(text)
# => ["hello", "world", "this", "is", "a", "test"]

# Advanced tokenization with features
features = NLP::Tokenizer.tokenize_with_features(text)
features.each do |feature|
  puts "#{feature[:token]} (#{feature[:type]}) at position #{feature[:position]}"
end

# Sentence splitting
sentences = NLP::Tokenizer.split_sentences(text)
# => ["Hello, world", "This is a test"]
```

### Text Processing

```crystal
# Text normalization
normalized = NLP::TextProcessor.normalize_text("HELLO   World\t\n")
# => "hello world"

# Stop word removal
tokens = ["the", "quick", "brown", "fox"]
filtered = NLP::TextProcessor.remove_stop_words(tokens)
# => ["quick", "brown", "fox"]

# Keyword extraction
keywords = NLP::TextProcessor.extract_keywords(text, 5)
puts "Keywords: #{keywords.join(", ")}"

# Text statistics
stats = NLP::TextProcessor.get_text_stats(text)
puts "Words: #{stats["word_count"]}, Sentences: #{stats["sentence_count"]}"
```

### Linguistic Atoms

```crystal
# Create word atoms
word_atom = NLP::LinguisticAtoms.create_word_atom(atomspace, "cat", "noun")

# Create semantic relationships
relation = NLP::LinguisticAtoms.create_semantic_relation(
  atomspace, "dog", "animal", "isa", 0.9
)

# Create sentence structure
tokens = ["the", "cat", "sits"]
sentence_atoms = NLP::LinguisticAtoms.create_sentence_structure(atomspace, tokens)

# Get linguistic statistics
complexity = NLP::LinguisticAtoms.get_linguistic_complexity(atomspace)
puts "Linguistic complexity: #{complexity}"
```

### Link Grammar Parsing

```crystal
# Create a parser
parser = NLP::LinkGrammar::Parser.new

# Parse a sentence
linkages = parser.parse("The cat sits on the mat")
linkage = linkages.first

puts "Words: #{linkage.words}"
puts "Links: #{linkage.links.size}"
puts "Disjuncts: #{linkage.disjuncts.size}"

# Parse and store in AtomSpace
atoms = parser.parse_to_atomspace("The dog runs", atomspace)

# Query parse results
word_nodes = atomspace.get_atoms_by_type(AtomSpace::AtomType::WORD_NODE)
parse_nodes = atomspace.get_atoms_by_type(AtomSpace::AtomType::PARSE_NODE)
link_instances = atomspace.get_atoms_by_type(AtomSpace::AtomType::LG_LINK_INSTANCE_LINK)

# Use module-level convenience methods
linkages = NLP::LinkGrammar.parse("Hello world")
atoms = NLP::LinkGrammar.parse_to_atomspace("The cat runs", atomspace)

# Dictionary lookup
disjuncts = parser.dictionary_lookup("cat")
```

### Dependency Parsing

```crystal
# Parse sentence and extract dependencies
parse_result = NLP::DependencyParser.parse("The cat sits on the mat")

puts "Dependencies found: #{parse_result.dependencies.size}"
parse_result.dependencies.each do |dep|
  puts "#{dep.governor} --[#{dep.relation}]--> #{dep.dependent}"
end

# Parse and store in AtomSpace
atoms = NLP::DependencyParser.parse_to_atomspace("The dog runs", atomspace)

# Query dependency structures
dep_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::DEPENDENCY_LINK)
```

### Language Generation

```crystal
# Generate simple sentence
sentence = NLP::LanguageGeneration.generate_sentence(
  "cat", "sits", "mat",
  tense: NLP::LanguageGeneration::Sentence::Tense::Present
)
puts sentence # => "The cat sits on the mat."

# Use templates
template = NLP::LanguageGeneration::Template.new(
  "{subject} {verb} {object}",
  ["subject", "verb", "object"]
)
text = template.fill({
  "subject" => "The dog",
  "verb" => "chases",
  "object" => "the ball"
})
puts text # => "The dog chases the ball"
```

### Semantic Understanding

```crystal
# Analyze semantic roles
analysis = NLP::SemanticUnderstanding.analyze("John gave Mary a book")

puts "Frames: #{analysis.frames.size}"
analysis.frames.each do |frame|
  puts "Frame: #{frame.name}"
  frame.frame_elements.each do |role, filler|
    puts "  #{role}: #{filler}"
  end
end

# Store semantic analysis in AtomSpace
atoms = NLP::SemanticUnderstanding.analyze_to_atomspace(
  "The cat caught the mouse",
  atomspace
)
```

## Command Line Interface

The NLP module includes a command-line interface for testing and demonstration:

```bash
# Run comprehensive demonstration
crystal run src/nlp/nlp_main.cr -- demo

# Tokenize text
crystal run src/nlp/nlp_main.cr -- tokenize "Hello, world!"

# Process text into AtomSpace
crystal run src/nlp/nlp_main.cr -- process "The cat sits on the mat."

# Analyze text statistics
crystal run src/nlp/nlp_main.cr -- stats "Natural language processing is fascinating."
```

## Integration with CrystalCog

The NLP module integrates seamlessly with other CrystalCog components:

- **AtomSpace**: Stores linguistic knowledge alongside other knowledge representations
- **PLN**: Can reason about linguistic relationships and semantic knowledge
- **URE**: Can apply rules to linguistic structures
- **CogUtil**: Uses logging and configuration systems

## Testing

Comprehensive test suite covers all functionality:

```bash
# Run all NLP tests
crystal spec spec/nlp/

# Run specific test files
crystal spec spec/nlp/tokenizer_spec.cr
crystal spec spec/nlp/text_processor_spec.cr
crystal spec spec/nlp/linguistic_atoms_spec.cr
crystal spec spec/nlp/link_grammar_spec.cr

# Validate NLP module structure and dependencies
./scripts/validation/test_nlp_structure.sh
```

### Validation Script

The `scripts/validation/test_nlp_structure.sh` script provides comprehensive validation of:

- **File Structure**: Verifies all 9 NLP module files exist (including advanced modules)
- **Module Definitions**: Checks proper module and class definitions for all modules
- **Method Signatures**: Validates key methods in each module:
  - NLP core: initialize, process_text, create_linguistic_kb
  - LinkGrammar: parse, parse_to_atomspace
  - DependencyParser: parse, parse_to_atomspace  
  - LanguageGeneration: generate, generate_sentence
  - SemanticUnderstanding: analyze, analyze_to_atomspace
- **Dependency Compatibility**: Validates CogUtil and AtomSpace dependencies
- **Cross-Module Dependencies**: Verifies LinkGrammar → DependencyParser → SemanticUnderstanding chain
- **Integration Points**: Confirms proper integration with main system
- **Guix Environment**: Checks Guix package configuration compatibility
- **Reasoning Systems**: Validates PLN and URE integration potential
- **Test Coverage**: Ensures all 7 test files are in place and properly structured

```bash
# Run comprehensive NLP validation (must be run from repo root)
cd /path/to/crystalcog
bash scripts/validation/test_nlp_structure.sh
# Run comprehensive NLP validation
./scripts/validation/test_nlp_structure.sh
```

This validation script is particularly useful for:
- Continuous integration checks
- Development environment setup verification
- Dependency troubleshooting
- Package distribution validation
- Verifying all advanced NLP features are properly integrated

## Architecture

The NLP module follows the established CrystalCog patterns:

- **Modular Design**: Separate modules for different functionality
- **Exception Handling**: Custom exception classes for error handling
- **AtomSpace Integration**: Native integration with knowledge representation
- **Crystal Idioms**: Uses Crystal language features and patterns
- **Comprehensive Testing**: Full test coverage with realistic examples

## Supported Features

### Text Processing
- ✅ Tokenization with classification
- ✅ Text normalization and preprocessing
- ✅ Stop word removal (English)
- ✅ Basic stemming
- ✅ N-gram extraction
- ✅ Keyword extraction
- ✅ Term frequency analysis

### Linguistic Representation
- ✅ Word atoms with part-of-speech
- ✅ Sentence structure representation
- ✅ Semantic relationships (synonyms, antonyms, hypernyms)
- ✅ Sequential word ordering
- ✅ Parse tree structures
- ✅ Linguistic complexity metrics
- ✅ Link Grammar parses with dependency links
- ✅ Word instance nodes and linkages
- ✅ Connector and disjunct representation

### Advanced Features
- ✅ Link Grammar parsing with typed links
- ✅ Universal Dependencies parsing
- ✅ Dependency tree construction
- ✅ Natural language generation with templates
- ✅ Semantic role labeling (agent, patient, theme, etc.)
- ✅ Frame-based semantic analysis
- ✅ Multi-tense sentence generation (present, past, future)

### Integration Features
- ✅ AtomSpace native integration
- ✅ Compatible with PLN reasoning
- ✅ Compatible with URE rule engine
- ✅ CogUtil logging integration
- ✅ Error handling and validation

## Future Enhancements

Potential extensions for the NLP module:

- **Full Link Grammar Integration**: Complete FFI bindings to Link Grammar C library
- **Advanced Parsing**: Multiple parse rankings, cost-based selection
- **Parser Integration**: Interface with external parsers (RelEx, spaCy)
- **Advanced Stemming**: Porter stemmer or lemmatization
- **Named Entity Recognition**: Identify and classify named entities
- **Semantic Role Labeling**: Predicate-argument structures
- **Multi-language Support**: Russian, Thai, Arabic parsing
- **Machine Learning Integration**: Neural language models
- **Discourse Processing**: Anaphora resolution and discourse structure

## Performance Notes

The NLP module is designed for:

- **Memory Efficiency**: Minimal memory footprint for text processing
- **Speed**: Fast tokenization and text processing
- **Scalability**: Handles varying text sizes efficiently
- **Thread Safety**: Compatible with concurrent AtomSpace operations

## Dependencies

- **CogUtil**: Logging and configuration
- **AtomSpace**: Knowledge representation and storage
- **Crystal Standard Library**: String processing and collections

This implementation provides a solid foundation for natural language processing in CrystalCog while maintaining compatibility with the existing OpenCog architecture.