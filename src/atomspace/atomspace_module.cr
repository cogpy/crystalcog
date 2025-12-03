# AtomSpace module - Core knowledge representation for Crystal OpenCog
# Converted from atomspace/opencog/*
#
# This module provides the fundamental knowledge representation system for OpenCog.

require "./truthvalue"
require "./atom"
require "./atomspace"
require "./distributed_cluster"
require "./distributed_storage"

module AtomSpace
  VERSION = "0.1.0"

  # Initialize the AtomSpace subsystem
  def self.initialize
    CogUtil::Logger.info("AtomSpace #{VERSION} initializing")
    CogUtil::Logger.info("AtomSpace #{VERSION} initialized")
  end

  # Create a new AtomSpace instance
  def self.create_atomspace : AtomSpace
    AtomSpace.new
  end

  # Create a distributed AtomSpace cluster
  def self.create_distributed_cluster(cluster_id : String, atomspace : AtomSpace? = nil,
                                      host : String = "localhost", port : Int32 = 0,
                                      sync_strategy : SyncStrategy = SyncStrategy::MergeUsingTruthValues) : DistributedAtomSpaceCluster
    target_atomspace = atomspace || create_atomspace
    DistributedAtomSpaceCluster.new(cluster_id, target_atomspace, host, port, sync_strategy)
  end

  # Create a distributed storage node
  def self.create_distributed_storage(name : String, cluster : DistributedAtomSpaceCluster,
                                      local_storage_backend : String = "file",
                                      storage_path : String = "./distributed_storage",
                                      partition_strategy : PartitionStrategy = PartitionStrategy::HashBased,
                                      replication_strategy : ReplicationStrategy = ReplicationStrategy::PrimaryBackup,
                                      replication_factor : Int32 = 2) : DistributedStorageNode
    DistributedStorageNode.new(name, cluster, local_storage_backend, storage_path,
                              partition_strategy, replication_strategy, replication_factor)
  end

  # Shutdown and cleanup
  def self.finalize
    CogUtil::Logger.info("AtomSpace shutting down")

    # Clear default atomspace if it exists
    AtomSpaceManager.default_atomspace.clear
  end

  # Exception classes specific to AtomSpace
  class AtomSpaceException < CogUtil::OpenCogException
  end

  class InvalidAtomException < AtomSpaceException
  end

  class DuplicateAtomException < AtomSpaceException
  end

  class AtomNotFoundException < AtomSpaceException
  end

  class InvalidTruthValueException < AtomSpaceException
  end

  # Factory methods for common operations
  module Factory
    # Create a simple concept taxonomy
    def self.create_taxonomy(atomspace : AtomSpace, concepts : Hash(String, Array(String)))
      concepts.each do |concept, parents|
        concept_node = atomspace.add_concept_node(concept)
        parents.each do |parent|
          parent_node = atomspace.add_concept_node(parent)
          atomspace.add_inheritance_link(concept_node, parent_node)
        end
      end
    end

    # Create a simple fact
    def self.create_fact(atomspace : AtomSpace, predicate : String, subject : String, object : String? = nil, tv : TruthValue = TruthValue::TRUE_TV)
      pred_node = atomspace.add_predicate_node(predicate)
      subj_node = atomspace.add_concept_node(subject)

      if object
        obj_node = atomspace.add_concept_node(object)
        args = atomspace.add_list_link([subj_node, obj_node])
      else
        args = atomspace.add_list_link([subj_node])
      end

      atomspace.add_evaluation_link(pred_node, args, tv)
    end

    # Create a numeric fact
    def self.create_numeric_fact(atomspace : AtomSpace, predicate : String, subject : String, value : Float64, tv : TruthValue = TruthValue::TRUE_TV)
      pred_node = atomspace.add_predicate_node(predicate)
      subj_node = atomspace.add_concept_node(subject)
      value_node = NumberNode.new(value)
      atomspace.add_atom(value_node)

      args = atomspace.add_list_link([subj_node, value_node])
      atomspace.add_evaluation_link(pred_node, args, tv)
    end
  end

  # Query and pattern matching utilities
  module Query
    # Simple query for atoms of a specific type and name
    def self.find_nodes(atomspace : AtomSpace, name : String, type : AtomType? = nil) : Array(Atom)
      atomspace.get_nodes_by_name(name, type)
    end

    # Find all inheritance relationships for a concept
    def self.find_inheritance(atomspace : AtomSpace, concept : String) : Array(Atom)
      concept_node = atomspace.get_nodes_by_name(concept, AtomType::CONCEPT_NODE).first?
      return [] of Atom unless concept_node

      atomspace.get_incoming(concept_node).select(&.inheritance_link?)
    end

    # Find all facts about a concept
    def self.find_facts(atomspace : AtomSpace, concept : String) : Array(Atom)
      concept_node = atomspace.get_nodes_by_name(concept, AtomType::CONCEPT_NODE).first?
      return [] of Atom unless concept_node

      facts = [] of Atom
      atomspace.get_incoming(concept_node).each do |link|
        if link.evaluation_link?
          facts << link
        elsif link.list_link?
          # Check if this list is part of an evaluation
          atomspace.get_incoming(link).each do |eval_link|
            facts << eval_link if eval_link.evaluation_link?
          end
        end
      end
      facts
    end

    # Simple pattern matching for [Predicate, Subject, Object] patterns
    def self.match_pattern(atomspace : AtomSpace, predicate : String?, subject : String?, object : String?) : Array(Atom)
      results = [] of Atom

      # Get all evaluation links
      eval_links = atomspace.get_atoms_by_type(AtomType::EVALUATION_LINK)

      eval_links.each do |link|
        next unless link.is_a?(Link) && link.arity == 2

        pred = link.outgoing[0]
        args = link.outgoing[1]

        # Check predicate match
        if predicate && pred.is_a?(Node)
          next unless pred.name == predicate
        end

        # Check argument matches if args is a ListLink
        if args.is_a?(Link) && args.list_link?
          case args.arity
          when 1
            arg1 = args.outgoing[0]
            if subject && arg1.is_a?(Node)
              next unless arg1.name == subject
            end
          when 2
            arg1, arg2 = args.outgoing[0], args.outgoing[1]
            if subject && arg1.is_a?(Node)
              next unless arg1.name == subject
            end
            if object && arg2.is_a?(Node)
              next unless arg2.name == object
            end
          end
        end

        results << link
      end

      results
    end
  end

  # Serialization utilities
  module Serialization
    # Export AtomSpace to simple text format
    def self.to_text(atomspace : AtomSpace) : String
      String.build do |str|
        atomspace.get_all_atoms.each do |atom|
          str << atom.to_s << " "
          str << atom.truth_value.to_s << "\n"
        end
      end
    end

    # Import atoms from simple text format (simplified parser)
    def self.from_text(atomspace : AtomSpace, text : String)
      text.each_line do |line|
        line = line.strip
        next if line.empty? || line.starts_with?('#')

        # Very basic parsing - would need more sophisticated parser for real use
        if match = line.match(/\((\w+)\s+"([^"]+)"\)\s+\(([^)]+)\)/)
          type_str = match[1]
          name = match[2]
          tv_str = match[3]

          # Parse truth value
          if tv_match = tv_str.match(/([\d.]+),\s*([\d.]+)/)
            strength = tv_match[1].to_f64
            confidence = tv_match[2].to_f64
            tv = SimpleTruthValue.new(strength, confidence)

            # Create atom based on type
            case type_str.upcase
            when "CONCEPTNODE"
              atomspace.add_concept_node(name, tv)
            when "PREDICATENODE"
              atomspace.add_predicate_node(name, tv)
            end
          end
        end
      end
    end
  end

  # Statistics and analysis utilities
  module Statistics
    # Get type distribution
    def self.type_distribution(atomspace : AtomSpace) : Hash(AtomType, Int32)
      distribution = Hash(AtomType, Int32).new(0)

      atomspace.get_all_atoms.each do |atom|
        distribution[atom.type] += 1
      end

      distribution
    end

    # Get truth value statistics
    def self.truth_value_stats(atomspace : AtomSpace) : NamedTuple(mean_strength: Float64, mean_confidence: Float64, total_atoms: Int32)
      atoms = atomspace.get_all_atoms
      return {mean_strength: 0.0, mean_confidence: 0.0, total_atoms: 0} if atoms.empty?

      total_strength = 0.0
      total_confidence = 0.0

      atoms.each do |atom|
        total_strength += atom.truth_value.strength
        total_confidence += atom.truth_value.confidence
      end

      count = atoms.size
      {
        mean_strength:   total_strength / count,
        mean_confidence: total_confidence / count,
        total_atoms:     count,
      }
    end

    # Find highly connected atoms
    def self.highly_connected_atoms(atomspace : AtomSpace, min_connections : Int32 = 5) : Array(Tuple(Atom, Int32))
      connection_counts = [] of Tuple(Atom, Int32)

      atomspace.get_all_atoms.each do |atom|
        connections = atomspace.get_incoming(atom).size
        if connections >= min_connections
          connection_counts << {atom, connections}
        end
      end

      connection_counts.sort { |a, b| b[1] <=> a[1] }
    end
  end
end
