# Self-Modification Infrastructure for CrystalCog
#
# Safe primitives for meta-learning, rule learning from experience,
# architecture search, and cognitive plasticity — with guardrails.

require "../cogutil/cogutil"
require "../atomspace/atomspace_main"

module SelfModification
  VERSION = "0.1.0"

  class SelfModException < Exception
  end

  # Capability / permission for a modification
  enum Permission
    READ_ONLY
    ADD_KNOWLEDGE
    REVISE_TRUTH
    ADD_RULE
    REMOVE_RULE
    RESTRUCTURE
  end

  # A proposed change to the cognitive system
  class ModificationProposal
    getter id : String
    getter description : String
    getter permission : Permission
    getter target : String
    getter payload : Hash(String, String)
    getter risk_score : Float64 # 0.0 safe .. 1.0 dangerous
    property status : Status

    enum Status
      PENDING
      APPROVED
      REJECTED
      APPLIED
      ROLLED_BACK
    end

    def initialize(@description : String, @permission : Permission,
                   @target : String, @payload : Hash(String, String) = {} of String => String,
                   @risk_score : Float64 = 0.1)
      @id = Random::Secure.hex(8)
      @status = Status::PENDING
    end
  end

  # Snapshot for rollback
  class Checkpoint
    getter id : String
    getter label : String
    getter created_at : Time
    getter atom_count : Int32
    getter metadata : Hash(String, String)
    getter atom_keys : Array(String)

    def initialize(@label : String, @atom_count : Int32, @atom_keys : Array(String),
                   @metadata : Hash(String, String) = {} of String => String)
      @id = Random::Secure.hex(8)
      @created_at = Time.utc
    end
  end

  # Safety policy for self-modification
  class SafetyPolicy
    getter max_risk : Float64
    getter allowed : Set(Permission)
    getter require_checkpoint : Bool
    getter max_changes_per_cycle : Int32

    def initialize(@max_risk : Float64 = 0.5,
                   @allowed : Set(Permission) = Set{
                     Permission::READ_ONLY,
                     Permission::ADD_KNOWLEDGE,
                     Permission::REVISE_TRUTH,
                     Permission::ADD_RULE,
                   },
                   @require_checkpoint : Bool = true,
                   @max_changes_per_cycle : Int32 = 10)
    end

    def allows?(proposal : ModificationProposal) : Bool
      return false unless @allowed.includes?(proposal.permission)
      return false if proposal.risk_score > @max_risk
      true
    end
  end

  # Guarded executor of self-modifications against an AtomSpace
  class SafeModifier
    getter atomspace : AtomSpace::AtomSpace
    getter policy : SafetyPolicy
    getter history : Array(ModificationProposal)
    getter checkpoints : Array(Checkpoint)
    @changes_this_cycle : Int32

    def initialize(@atomspace : AtomSpace::AtomSpace, @policy : SafetyPolicy = SafetyPolicy.new)
      @history = [] of ModificationProposal
      @checkpoints = [] of Checkpoint
      @changes_this_cycle = 0
    end

    def reset_cycle
      @changes_this_cycle = 0
    end

    def checkpoint(label : String = "auto") : Checkpoint
      keys = @atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE).map(&.name).first(500)
      cp = Checkpoint.new(label, @atomspace.size.to_i32, keys)
      @checkpoints << cp
      CogUtil::Logger.info("SelfModification", "Checkpoint #{cp.id} (#{label})")
      cp
    end

    def propose(description : String, permission : Permission, target : String,
                payload : Hash(String, String) = {} of String => String,
                risk : Float64 = 0.1) : ModificationProposal
      ModificationProposal.new(description, permission, target, payload, risk)
    end

    def apply(proposal : ModificationProposal) : Bool
      unless @policy.allows?(proposal)
        proposal.status = ModificationProposal::Status::REJECTED
        @history << proposal
        return false
      end

      if @changes_this_cycle >= @policy.max_changes_per_cycle
        proposal.status = ModificationProposal::Status::REJECTED
        @history << proposal
        return false
      end

      checkpoint("pre_#{proposal.id}") if @policy.require_checkpoint

      success = case proposal.permission
                when .add_knowledge?
                  apply_add_knowledge(proposal)
                when .revise_truth?
                  apply_revise_truth(proposal)
                when .add_rule?
                  apply_add_rule(proposal)
                when .remove_rule?
                  apply_remove_rule(proposal)
                when .restructure?
                  apply_restructure(proposal)
                else
                  false
                end

      proposal.status = success ? ModificationProposal::Status::APPLIED : ModificationProposal::Status::REJECTED
      @changes_this_cycle += 1 if success
      @history << proposal
      success
    end

    def approved_count : Int32
      @history.count { |p| p.status == ModificationProposal::Status::APPLIED }
    end

    def rejected_count : Int32
      @history.count { |p| p.status == ModificationProposal::Status::REJECTED }
    end

    private def apply_add_knowledge(p : ModificationProposal) : Bool
      name = p.payload["name"]? || p.target
      strength = (p.payload["strength"]? || "0.8").to_f
      confidence = (p.payload["confidence"]? || "0.9").to_f
      @atomspace.add_node(
        AtomSpace::AtomType::CONCEPT_NODE,
        name,
        AtomSpace::SimpleTruthValue.new(strength, confidence)
      )
      true
    end

    private def apply_revise_truth(p : ModificationProposal) : Bool
      atoms = @atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE)
      atom = atoms.find { |a| a.name == p.target }
      return false unless atom
      strength = (p.payload["strength"]? || atom.truth_value.strength.to_s).to_f
      confidence = (p.payload["confidence"]? || atom.truth_value.confidence.to_s).to_f
      revised = @atomspace.add_node(
        AtomSpace::AtomType::CONCEPT_NODE,
        "#{p.target}_revised",
        AtomSpace::SimpleTruthValue.new(strength, confidence)
      )
      @atomspace.add_link(
        AtomSpace::AtomType::EQUIVALENCE_LINK,
        [atom, revised],
        AtomSpace::SimpleTruthValue.new(strength, confidence)
      )
      true
    rescue
      false
    end

    private def apply_add_rule(p : ModificationProposal) : Bool
      ant = p.payload["antecedent"]?
      cons = p.payload["consequent"]?
      return false unless ant && cons
      a = @atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, ant)
      c = @atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, cons)
      strength = (p.payload["strength"]? || "0.7").to_f
      @atomspace.add_link(
        AtomSpace::AtomType::IMPLICATION_LINK,
        [a, c],
        AtomSpace::SimpleTruthValue.new(strength, 0.8)
      )
      true
    end

    private def apply_remove_rule(p : ModificationProposal) : Bool
      links = @atomspace.get_atoms_by_type(AtomSpace::AtomType::IMPLICATION_LINK)
      target = links.find { |l| l.to_s.includes?(p.target) }
      return false unless target
      @atomspace.add_link(
        AtomSpace::AtomType::EVALUATION_LINK,
        [
          @atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "deprecated"),
          target,
        ],
        AtomSpace::SimpleTruthValue.new(0.0, 0.99)
      )
      true
    end

    private def apply_restructure(p : ModificationProposal) : Bool
      members = (p.payload["members"]? || "").split(",").map(&.strip).reject(&.empty?)
      return false if members.empty?
      schema = @atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, "schema:#{p.target}")
      member_atoms = members.map { |m| @atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, m).as(AtomSpace::Atom) }
      @atomspace.add_link(AtomSpace::AtomType::LIST_LINK, [schema.as(AtomSpace::Atom)] + member_atoms)
      true
    end
  end

  # Meta-learner: adjusts hyperparameters from performance feedback
  class MetaLearner
    getter params : Hash(String, Float64)
    getter history : Array(Tuple(Hash(String, Float64), Float64))

    def initialize(initial : Hash(String, Float64) = {"learning_rate" => 0.1, "exploration" => 0.2})
      @params = initial.dup
      @history = [] of Tuple(Hash(String, Float64), Float64)
    end

    def feedback(score : Float64)
      @history << {@params.dup, score}
      return if @history.size < 2

      prev_params, prev_score = @history[-2]
      if score > prev_score
        @params.each_key do |k|
          delta = @params[k] - (prev_params[k]? || @params[k])
          @params[k] = (@params[k] + delta * 0.1).clamp(0.001, 1.0)
        end
      else
        @params.each_key do |k|
          prev = prev_params[k]? || @params[k]
          @params[k] = (@params[k] * 0.7 + prev * 0.3).clamp(0.001, 1.0)
        end
      end
    end

    def best_params : Hash(String, Float64)
      return @params if @history.empty?
      @history.max_by { |_, s| s }[0]
    end
  end

  # Learn ImplicationLinks from observed (premise, conclusion, success) triples
  class RuleLearner
    getter rules : Hash(Tuple(String, String), Tuple(Int32, Int32))

    def initialize
      @rules = Hash(Tuple(String, String), Tuple(Int32, Int32)).new({0, 0})
    end

    def observe(antecedent : String, consequent : String, success : Bool)
      key = {antecedent, consequent}
      s, t = @rules[key]
      @rules[key] = {s + (success ? 1 : 0), t + 1}
    end

    def confidence(antecedent : String, consequent : String) : Float64
      s, t = @rules[{antecedent, consequent}]
      return 0.0 if t == 0
      s.to_f / t.to_f
    end

    def commit(atomspace : AtomSpace::AtomSpace, min_confidence : Float64 = 0.7,
               min_support : Int32 = 3) : Int32
      count = 0
      @rules.each do |(ant, cons), (s, t)|
        next if t < min_support
        conf = s.to_f / t.to_f
        next if conf < min_confidence
        a = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, ant)
        c = atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, cons)
        atomspace.add_link(
          AtomSpace::AtomType::IMPLICATION_LINK,
          [a, c],
          AtomSpace::SimpleTruthValue.new(conf, Math.min(0.99, t.to_f / 10.0))
        )
        count += 1
      end
      count
    end
  end

  # Simple architecture search over discrete component choices
  class ArchitectureSearch
    getter candidates : Array(Hash(String, String))
    getter scores : Hash(Int32, Float64)

    def initialize
      @candidates = [] of Hash(String, String)
      @scores = {} of Int32 => Float64
    end

    def add_candidate(config : Hash(String, String))
      @candidates << config
    end

    def evaluate(index : Int32, score : Float64)
      raise SelfModException.new("invalid candidate index") if index < 0 || index >= @candidates.size
      @scores[index] = score
    end

    def best : Hash(String, String)?
      return nil if @scores.empty?
      idx = @scores.max_by { |_, s| s }[0]
      @candidates[idx]
    end

    def sample_random(space : Hash(String, Array(String)), n : Int32 = 5) : Array(Hash(String, String))
      results = [] of Hash(String, String)
      n.times do
        cfg = {} of String => String
        space.each { |k, opts| cfg[k] = opts.sample }
        results << cfg
        add_candidate(cfg)
      end
      results
    end
  end

  # Cognitive plasticity: strengthen/weaken links based on usage
  class CognitivePlasticity
    getter usage : Hash(String, Int32)
    getter atomspace : AtomSpace::AtomSpace

    def initialize(@atomspace : AtomSpace::AtomSpace)
      @usage = Hash(String, Int32).new(0)
    end

    def touch(atom_name : String)
      @usage[atom_name] += 1
    end

    def hebbian_update(a : String, b : String, amount : Float64 = 0.05)
      touch(a)
      touch(b)
      na = @atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, a)
      nb = @atomspace.add_node(AtomSpace::AtomType::CONCEPT_NODE, b)
      strength = Math.min(0.99, 0.5 + amount * Math.min(@usage[a], @usage[b]))
      @atomspace.add_link(
        AtomSpace::AtomType::EQUIVALENCE_LINK,
        [na, nb],
        AtomSpace::SimpleTruthValue.new(strength, 0.7)
      )
    end

    def decay_unused(threshold : Int32 = 1) : Int32
      count = 0
      @atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE).each do |atom|
        next if @usage[atom.name] >= threshold
        @atomspace.add_link(
          AtomSpace::AtomType::EVALUATION_LINK,
          [
            @atomspace.add_node(AtomSpace::AtomType::PREDICATE_NODE, "unused"),
            atom,
          ],
          AtomSpace::SimpleTruthValue.new(0.1, 0.5)
        )
        count += 1
      end
      count
    end
  end

  def self.initialize
    CogUtil::Logger.info("Initializing SelfModification subsystem...")
    CogUtil::Logger.info("SelfModification subsystem initialized successfully")
  end
end
