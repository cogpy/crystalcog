# Attention value normalization for ECAN
# Keeps STI/LTI distributions stable and comparable across atoms

require "./attention"
require "./attention_bank"

module Attention
  # Normalizes attention values across the atomspace so that
  # total STI/LTI match target funds and values stay in range.
  class AttentionNormalizer
    getter bank : AttentionBank
    getter target_sti_total : Int16
    getter target_lti_total : Int16

    def initialize(@bank : AttentionBank,
                   @target_sti_total : Int16 = ECANParams::TARGET_STI_FUNDS,
                   @target_lti_total : Int16 = ECANParams::TARGET_LTI_FUNDS)
    end

    # Compute current STI/LTI totals across all atoms
    def current_totals : NamedTuple(sti: Int64, lti: Int64, count: Int32)
      sti_sum = 0_i64
      lti_sum = 0_i64
      count = 0

      @bank.atomspace.get_all_atoms.each do |atom|
        av = @bank.get_attention_value(atom.handle)
        next unless av
        sti_sum += av.sti
        lti_sum += av.lti
        count += 1
      end

      {sti: sti_sum, lti: lti_sum, count: count}
    end

    # Scale all STI values so their sum equals target_sti_total.
    # Preserves relative proportions. Returns number of atoms updated.
    def normalize_sti : Int32
      totals = current_totals
      return 0 if totals[:count] == 0 || totals[:sti] == 0

      scale = @target_sti_total.to_f64 / totals[:sti].to_f64
      updated = 0

      @bank.atomspace.get_all_atoms.each do |atom|
        av = @bank.get_attention_value(atom.handle)
        next unless av

        new_sti = (av.sti.to_f64 * scale).round.to_i16
        new_sti = new_sti.clamp(ECANParams::MIN_STI, ECANParams::MAX_STI)
        next if new_sti == av.sti

        new_av = AtomSpace::AttentionValue.new(new_sti, av.lti, av.vlti)
        updated += 1 if @bank.set_attention_value(atom.handle, new_av)
      end

      CogUtil::Logger.info("AttentionNormalizer", "Normalized STI for #{updated} atoms (scale=#{scale.round(4)})")
      updated
    end

    # Scale all LTI values so their sum equals target_lti_total.
    def normalize_lti : Int32
      totals = current_totals
      return 0 if totals[:count] == 0 || totals[:lti] == 0

      scale = @target_lti_total.to_f64 / totals[:lti].to_f64
      updated = 0

      @bank.atomspace.get_all_atoms.each do |atom|
        av = @bank.get_attention_value(atom.handle)
        next unless av

        new_lti = (av.lti.to_f64 * scale).round.to_i16
        new_lti = new_lti.clamp(ECANParams::MIN_STI, ECANParams::MAX_STI)
        next if new_lti == av.lti

        new_av = AtomSpace::AttentionValue.new(av.sti, new_lti, av.vlti)
        updated += 1 if @bank.set_attention_value(atom.handle, new_av)
      end

      CogUtil::Logger.info("AttentionNormalizer", "Normalized LTI for #{updated} atoms (scale=#{scale.round(4)})")
      updated
    end

    # Normalize both STI and LTI
    def normalize_all : Hash(String, Int32)
      {
        "sti_updated" => normalize_sti,
        "lti_updated" => normalize_lti,
      }
    end

    # Min-max normalize STI into [0, max_sti] range while preserving order
    def min_max_normalize_sti(max_sti : Int16 = 1000_i16) : Int32
      values = [] of Tuple(AtomSpace::Handle, Int16, AtomSpace::AttentionValue)

      @bank.atomspace.get_all_atoms.each do |atom|
        av = @bank.get_attention_value(atom.handle)
        next unless av
        values << {atom.handle, av.sti, av}
      end

      return 0 if values.empty?

      min_val = values.min_of { |_, sti, _| sti }
      max_val = values.max_of { |_, sti, _| sti }
      range = max_val - min_val
      return 0 if range == 0

      updated = 0
      values.each do |handle, sti, av|
        normalized = ((sti - min_val).to_f64 / range.to_f64 * max_sti.to_f64).round.to_i16
        new_av = AtomSpace::AttentionValue.new(normalized, av.lti, av.vlti)
        updated += 1 if @bank.set_attention_value(handle, new_av)
      end

      updated
    end

    # Z-score style centering: shift STI so mean is near target_mean
    def center_sti(target_mean : Int16 = 100_i16) : Int32
      totals = current_totals
      return 0 if totals[:count] == 0

      mean = totals[:sti].to_f64 / totals[:count].to_f64
      shift = (target_mean.to_f64 - mean).round.to_i16
      return 0 if shift == 0

      updated = 0
      @bank.atomspace.get_all_atoms.each do |atom|
        av = @bank.get_attention_value(atom.handle)
        next unless av

        new_sti = (av.sti + shift).clamp(ECANParams::MIN_STI, ECANParams::MAX_STI)
        next if new_sti == av.sti

        new_av = AtomSpace::AttentionValue.new(new_sti, av.lti, av.vlti)
        updated += 1 if @bank.set_attention_value(atom.handle, new_av)
      end

      updated
    end
  end
end
