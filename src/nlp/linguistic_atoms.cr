# Linguistic atom types and operations specific to NLP
#
# Defines specialized atom types and operations for representing
# linguistic knowledge in the AtomSpace.

module NLP
  module LinguisticAtoms
    # Create a word atom with optional part-of-speech information
    def self.create_word_atom(atomspace : AtomSpace::AtomSpace, word : String, pos : String? = nil) : AtomSpace::Atom
      # Create the basic word atom
      word_atom = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "word:#{word}")

      # If part-of-speech is provided, create the relationship
      if pos
        pos_atom = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "pos:#{pos}")
        pos_link = atomspace.add_link(AtomSpace::AtomType::INHERITANCE_LINK, [word_atom, pos_atom])
        CogUtil::Logger.debug("Created word atom '#{word}' with POS '#{pos}'")
      else
        CogUtil::Logger.debug("Created word atom '#{word}'")
      end

      word_atom
    end

    # Create a sentence structure in the AtomSpace
    def self.create_sentence_structure(atomspace : AtomSpace::AtomSpace, tokens : Array(String)) : Array(AtomSpace::Atom)
      atoms = [] of AtomSpace::Atom

      # Create word atoms for each token
      word_atoms = tokens.map do |token|
        word_atom = create_word_atom(atomspace, token)
        atoms << word_atom
        word_atom
      end

      # Create sequential ordering links between adjacent words
      (0...word_atoms.size - 1).each do |i|
        sequence_link = atomspace.add_link(
          AtomSpace::AtomType::ORDERED_LINK,
          [word_atoms[i], word_atoms[i + 1]]
        )
        atoms << sequence_link
      end

      # Create a list representing the sentence
      if word_atoms.size > 0
        sentence_list = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, word_atoms)
        atoms << sentence_list

        # Create a sentence concept and link it to the word list
        sentence_concept = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "sentence")
        sentence_relation = atomspace.add_link(
          AtomSpace::AtomType::EVALUATION_LINK,
          [sentence_concept, sentence_list]
        )
        atoms << sentence_concept
        atoms << sentence_relation
      end

      CogUtil::Logger.debug("Created sentence structure with #{atoms.size} atoms")
      atoms
    end

    # Create semantic relationships between words
    def self.create_semantic_relation(
      atomspace : AtomSpace::AtomSpace,
      word1 : String,
      word2 : String,
      relation_type : String,
      confidence : Float64 = 0.8,
    ) : AtomSpace::Atom
      # Create or get word atoms
      word1_atom = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "word:#{word1}")
      word2_atom = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "word:#{word2}")

      # Create relation atom
      relation_atom = atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, relation_type)

      # Create the semantic relationship
      tv = AtomSpace::SimpleTruthValue.new(confidence, 0.9)
      relation_link = atomspace.add_link(
        AtomSpace::AtomType::EVALUATION_LINK,
        [relation_atom, atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [word1_atom, word2_atom])],
        tv
      )

      CogUtil::Logger.debug("Created semantic relation '#{relation_type}' between '#{word1}' and '#{word2}'")
      relation_link
    end

    # Create a parse tree structure in AtomSpace
    def self.create_parse_tree(atomspace : AtomSpace::AtomSpace, tokens : Array(String), structure : Array(Array(Int32))) : Array(AtomSpace::Atom)
      atoms = [] of AtomSpace::Atom

      # Create word atoms
      word_atoms = tokens.map { |token| create_word_atom(atomspace, token) }
      atoms.concat(word_atoms)

      # Create syntactic structure based on the provided structure
      structure.each do |group|
        if group.size > 1
          # Create a phrase from the group of token indices
          phrase_atoms = group.map { |index| word_atoms[index] }
          phrase_link = atomspace.add_link(AtomSpace::AtomType::LIST_LINK, phrase_atoms)
          atoms << phrase_link

          # Mark this as a syntactic phrase
          phrase_concept = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "phrase")
          phrase_relation = atomspace.add_link(
            AtomSpace::AtomType::EVALUATION_LINK,
            [phrase_concept, phrase_link]
          )
          atoms << phrase_concept
          atoms << phrase_relation
        end
      end

      CogUtil::Logger.debug("Created parse tree with #{atoms.size} atoms")
      atoms
    end

    # Create lexical semantic relationships (synonymy, antonymy, etc.)
    def self.create_lexical_relations(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
      atoms = [] of AtomSpace::Atom

      # Define some basic semantic relationships
      relations = [
        {"happy", "sad", "antonym"},
        {"happy", "joyful", "synonym"},
        {"big", "large", "synonym"},
        {"big", "small", "antonym"},
        {"dog", "animal", "hypernym"},
        {"cat", "animal", "hypernym"},
        {"red", "color", "hypernym"},
        {"blue", "color", "hypernym"},
      ]

      relations.each do |word1, word2, relation|
        relation_atom = create_semantic_relation(atomspace, word1, word2, relation, 0.9)
        atoms << relation_atom
      end

      CogUtil::Logger.info("Created #{relations.size} lexical relations")
      atoms
    end

    # Extract all word atoms from an atomspace
    def self.get_word_atoms(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
      # Get both legacy word: concept nodes and new WORD_NODE atoms
      concept_words = atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE)
        .select { |atom| atom.name.starts_with?("word:") }
      word_nodes = atomspace.get_atoms_by_type(AtomSpace::AtomType::WORD_NODE)

      concept_words + word_nodes
    end

    # Extract all sentence structures from an atomspace
    def self.get_sentence_atoms(atomspace : AtomSpace::AtomSpace) : Array(AtomSpace::Atom)
      # Find evaluation links where the predicate is "sentence"
      sentence_concept = atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE)
        .find { |atom| atom.name == "sentence" }

      return [] of AtomSpace::Atom unless sentence_concept

      atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
        .select do |atom|
          atom.is_a?(AtomSpace::Link) &&
            atom.as(AtomSpace::Link).outgoing.first? == sentence_concept
        end
    end

    # Get semantic relations of a specific type
    def self.get_semantic_relations(
      atomspace : AtomSpace::AtomSpace,
      relation_type : String,
    ) : Array(AtomSpace::Atom)
      relation_predicate = atomspace.get_atoms_by_type(AtomSpace::AtomType::PREDICATE_NODE)
        .find { |atom| atom.name == relation_type }

      return [] of AtomSpace::Atom unless relation_predicate

      atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK)
        .select do |atom|
          atom.is_a?(AtomSpace::Link) &&
            atom.as(AtomSpace::Link).outgoing.first? == relation_predicate
        end
    end

    # Calculate linguistic complexity metrics
    def self.get_linguistic_complexity(atomspace : AtomSpace::AtomSpace) : Hash(String, Int32)
      word_atoms = get_word_atoms(atomspace)
      sentence_atoms = get_sentence_atoms(atomspace)

      # Count different types of linguistic structures
      evaluation_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::EVALUATION_LINK).size
      list_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::LIST_LINK).size
      inheritance_links = atomspace.get_atoms_by_type(AtomSpace::AtomType::INHERITANCE_LINK).size

      {
        "word_count"             => word_atoms.size,
        "sentence_count"         => sentence_atoms.size,
        "evaluation_links"       => evaluation_links,
        "list_links"             => list_links,
        "inheritance_links"      => inheritance_links,
        "total_linguistic_atoms" => word_atoms.size + sentence_atoms.size,
      }
    end
  end
end
