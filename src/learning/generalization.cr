# Generalization Algorithms for CrystalCog
#
# This module implements various generalization algorithms for learning
# from specific examples and forming general rules.

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"
require "./concept_learning"

module Learning
  module Generalization
    VERSION = "0.1.0"

    # Exception classes
    class GeneralizationException < Exception
    end

    # Represents a generalized rule
    class Rule
      getter antecedent : Array(String)
      getter consequent : String
      getter support : Int32
      getter confidence : Float64

      def initialize(@antecedent : Array(String), @consequent : String,
                     @support : Int32 = 0, @confidence : Float64 = 0.0)
      end

      def to_s(io : IO)
        io << antecedent.join(" AND ") << " => " << consequent
        io << " (support: #{support}, confidence: #{confidence.round(3)})"
      end

      # Convert to AtomSpace representation
      def to_atomspace(atomspace : AtomSpace::AtomSpace) : AtomSpace::Atom
        # Create nodes for antecedent conditions
        antecedent_nodes = @antecedent.map do |cond|
          atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, cond)
        end

        # Create node for consequent
        consequent_node = atomspace.add_node(
          AtomSpace::AtomType::PREDICATE_NODE,
          @consequent
        )

        # Create AND link for antecedent
        and_link = atomspace.add_link(
          AtomSpace::AtomType::AND_LINK,
          antecedent_nodes
        )

        # Create implication link
        atomspace.add_link(
          AtomSpace::AtomType::IMPLICATION_LINK,
          [and_link, consequent_node],
          AtomSpace::SimpleTruthValue.new(@confidence, 0.9)
        )
      end
    end

    # Implements anti-unification (finding least general generalization)
    class AntiUnification
      def self.generalize(examples : Array(String)) : String
        return examples.first if examples.size == 1

        # Find common pattern
        result = examples.first

        examples[1..-1].each do |example|
          result = find_common_pattern(result, example)
        end

        result
      end

      private def self.find_common_pattern(s1 : String, s2 : String) : String
        words1 = s1.split
        words2 = s2.split

        common = [] of String

        [words1.size, words2.size].min.times do |i|
          if words1[i] == words2[i]
            common << words1[i]
          else
            common << "?"
          end
        end

        common.join(" ")
      end
    end

    # Association rule mining
    class AssociationRuleMiner
      getter min_support : Float64
      getter min_confidence : Float64

      def initialize(@min_support : Float64 = 0.3, @min_confidence : Float64 = 0.7)
      end

      def mine_rules(transactions : Array(Array(String))) : Array(Rule)
        # Find frequent itemsets
        frequent_itemsets = find_frequent_itemsets(transactions)

        # Generate association rules
        rules = [] of Rule

        frequent_itemsets.each do |itemset, support|
          next if itemset.size < 2

          # Generate all non-empty proper subsets
          subsets = generate_subsets(itemset)

          subsets.each do |antecedent|
            consequent_items = itemset - antecedent
            next if consequent_items.empty?

            # Calculate confidence
            antecedent_support = count_support(transactions, antecedent)
            confidence = support.to_f / antecedent_support

            if confidence >= @min_confidence
              rules << Rule.new(
                antecedent,
                consequent_items.join(" AND "),
                support,
                confidence
              )
            end
          end
        end

        rules
      end

      private def find_frequent_itemsets(transactions : Array(Array(String))) : Hash(Array(String), Int32)
        itemsets = {} of Array(String) => Int32

        # Count single items
        transactions.each do |transaction|
          transaction.each do |item|
            key = [item]
            itemsets[key] = itemsets.fetch(key, 0) + 1
          end
        end

        # Filter by minimum support
        min_support_count = (transactions.size * @min_support).to_i
        frequent = itemsets.select { |_, count| count >= min_support_count }

        # Generate larger itemsets
        k = 2
        while true
          candidates = generate_candidates(frequent.keys.to_a, k)
          break if candidates.empty?

          candidate_counts = {} of Array(String) => Int32

          transactions.each do |transaction|
            candidates.each do |candidate|
              if candidate.all? { |item| transaction.includes?(item) }
                candidate_counts[candidate] = candidate_counts.fetch(candidate, 0) + 1
              end
            end
          end

          new_frequent = candidate_counts.select { |_, count| count >= min_support_count }
          break if new_frequent.empty?

          frequent.merge!(new_frequent)
          k += 1
        end

        frequent
      end

      private def generate_candidates(itemsets : Array(Array(String)), k : Int32) : Array(Array(String))
        candidates = [] of Array(String)

        itemsets.each_with_index do |set1, i|
          itemsets[(i + 1)..-1].each do |set2|
            # Join itemsets if they share k-2 items
            union = (set1 | set2).sort
            if union.size == k
              candidates << union
            end
          end
        end

        candidates.uniq
      end

      private def generate_subsets(items : Array(String)) : Array(Array(String))
        subsets = [] of Array(String)

        (1...items.size).each do |size|
          items.combinations(size).each do |combo|
            subsets << combo
          end
        end

        subsets
      end

      private def count_support(transactions : Array(Array(String)),
                                items : Array(String)) : Int32
        transactions.count { |t| items.all? { |item| t.includes?(item) } }
      end
    end

    # Inductive Logic Programming (simplified)
    class InductiveLearner
      getter background_knowledge : Array(Rule)

      def initialize
        @background_knowledge = [] of Rule
      end

      def add_background(rule : Rule)
        @background_knowledge << rule
      end

      # Learn rules from positive and negative examples
      def learn(positive_examples : Array(Hash(String, String)),
                negative_examples : Array(Hash(String, String))) : Array(Rule)
        rules = [] of Rule

        # Extract features from positive examples
        features = extract_features(positive_examples)

        # Generate candidate rules
        features.each do |feature|
          # Count coverage
          positive_coverage = count_coverage(positive_examples, feature)
          negative_coverage = count_coverage(negative_examples, feature)

          # Calculate precision
          total_coverage = positive_coverage + negative_coverage
          if total_coverage > 0
            precision = positive_coverage.to_f / total_coverage
            # Adjust confidence by coverage proportion
            coverage_ratio = positive_coverage.to_f / positive_examples.size
            confidence = precision * coverage_ratio

            if precision > 0.7 # Threshold
              rules << Rule.new(
                [feature],
                "target_class",
                positive_coverage,
                confidence
              )
            end
          end
        end

        rules.sort_by { |r| -r.confidence }
      end

      private def extract_features(examples : Array(Hash(String, String))) : Array(String)
        features = Set(String).new

        examples.each do |example|
          example.each do |key, value|
            features.add("#{key}=#{value}")
          end
        end

        features.to_a
      end

      private def count_coverage(examples : Array(Hash(String, String)),
                                 feature : String) : Int32
        parts = feature.split("=")
        return 0 if parts.size != 2

        key, value = parts
        examples.count { |ex| ex[key]? == value }
      end
    end

    # Analogical reasoning for generalization
    class AnalogyMaker
      # Find analogies between two domains
      def find_analogy(source_domain : Hash(String, String),
                       target_domain : Hash(String, String)) : Hash(String, String)
        mapping = {} of String => String

        # Simple structural mapping based on roles
        source_domain.each do |role, entity|
          # Find corresponding role in target
          if target_entity = target_domain[role]?
            mapping[entity] = target_entity
          end
        end

        mapping
      end

      # Transfer knowledge via analogy
      def transfer_knowledge(source_knowledge : Array(Rule),
                             analogy_mapping : Hash(String, String)) : Array(Rule)
        transferred = [] of Rule

        source_knowledge.each do |rule|
          # Map antecedent and consequent
          mapped_antecedent = rule.antecedent.map do |cond|
            analogy_mapping.fetch(cond, cond)
          end

          mapped_consequent = analogy_mapping.fetch(rule.consequent, rule.consequent)

          transferred << Rule.new(
            mapped_antecedent,
            mapped_consequent,
            rule.support,
            rule.confidence * 0.8 # Lower confidence for transferred knowledge
          )
        end

        transferred
      end
    end

    # Cluster-based generalization
    class ClusterGeneralizer
      def generalize_clusters(clusters : Array(Array(Hash(String, String | Float64 | Bool)))) : Array(ConceptLearning::Concept)
        concepts = [] of ConceptLearning::Concept

        clusters.each_with_index do |cluster, idx|
          concept = ConceptLearning::Concept.new("cluster_#{idx}")

          # Find common features
          if cluster.size > 0
            common_features = cluster.first.keys.to_set

            cluster.each do |example|
              common_features &= example.keys.to_set
            end

            # Add common feature values
            common_features.each do |key|
              values = cluster.map { |ex| ex[key] }.compact.uniq
              if values.size == 1
                concept.features[key] = values[0]
              end
            end
          end

          # Add examples
          cluster.each do |example|
            concept.add_positive_example(example)
          end

          concepts << concept
        end

        concepts
      end
    end

    # Module-level convenience methods
    def self.mine_association_rules(transactions : Array(Array(String)),
                                    min_support : Float64 = 0.3,
                                    min_confidence : Float64 = 0.7) : Array(Rule)
      miner = AssociationRuleMiner.new(min_support, min_confidence)
      miner.mine_rules(transactions)
    end

    def self.generalize_examples(examples : Array(String)) : String
      AntiUnification.generalize(examples)
    end
  end
end
