# Natural Language Processing module for CrystalCog
#
# This module provides basic NLP functionality including tokenization,
# text processing, and integration with the OpenCog AtomSpace for
# storing linguistic knowledge.

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module NLP
  VERSION = "0.1.0"

  # Exception classes for NLP operations
  class NLPException < Exception
  end

  class TokenizationException < NLPException
  end

  class TextProcessingException < NLPException
  end

  # Initialize the NLP subsystem
  def self.initialize
    CogUtil::Logger.info("Initializing NLP subsystem...")

    # Register NLP-specific atom types if needed
    register_linguistic_atom_types

    CogUtil::Logger.info("NLP subsystem initialized successfully")
  end

  # Register NLP-specific atom types with the AtomSpace
  private def self.register_linguistic_atom_types
    # This will be extended as we add more linguistic atom types
    CogUtil::Logger.debug("Registering linguistic atom types...")
  end

  # Main NLP processing pipeline
  def self.process_text(text : String, atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
    CogUtil::Logger.debug("Processing text: #{text[0..50]}...")

    # Tokenize the text
    tokens = Tokenizer.tokenize(text)

    # Process tokens and create atoms
    atoms = [] of AtomSpace::Atom

    tokens.each do |token|
      # Create word nodes for each token
      word_atom = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "word:#{token}")
      atoms << word_atom
    end

    # Create sentence structure if we have multiple tokens
    if tokens.size > 1
      # Create a list link representing the sentence structure
      sentence_atom = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, atoms)
      atoms << sentence_atom

      # Create a sentence node
      sentence_node = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "sentence")
      atoms << sentence_node

      # Link the sentence structure to the sentence concept
      sentence_link = atomspace.add_link(AtomSpace::AtomType::EVALUATION_LINK, [sentence_node, sentence_atom])
      atoms << sentence_link
    end

    CogUtil::Logger.debug("Created #{atoms.size} atoms from text processing")
    atoms
  end

  # Create a basic linguistic knowledge base
  def self.create_linguistic_kb(atomspace : AtomSpace::AtomSpace) : AtomSpace::AtomSpace
    CogUtil::Logger.info("Creating basic linguistic knowledge base...")

    # Add basic linguistic concepts
    word = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "word")
    sentence = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "sentence")
    noun = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "noun")
    verb = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "verb")
    adjective = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "adjective")

    # Create basic inheritance relationships
    high_confidence = AtomSpace::SimpleTruthValue.new(0.9, 0.9)

    atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [noun, word], high_confidence)
    atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [verb, word], high_confidence)
    atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [adjective, word], high_confidence)

    CogUtil::Logger.info("Linguistic knowledge base created")
    atomspace
  end

  # Utility method to get linguistic statistics from an atomspace
  def self.get_linguistic_stats(atomspace : AtomSpace::AtomSpace) : Hash(String, Int32)
    word_count = atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE)
      .count { |atom| atom.name.starts_with?("word:") }

    sentence_count = atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE)
      .count { |atom| atom.name == "sentence" }

    {
      "word_atoms"     => word_count,
      "sentence_atoms" => sentence_count,
      "total_atoms"    => atomspace.size.to_i32,
    }
  end
end

# Load sub-modules
require "./tokenizer"
require "./text_processor"
require "./linguistic_atoms"
require "./link_grammar"
require "./dependency_parser"
require "./advanced_nlp"
require "./language_generation"
require "./semantic_understanding"
