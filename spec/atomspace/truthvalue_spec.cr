require "spec"
require "../../src/atomspace/truthvalue"

describe AtomSpace::TruthValue do
  describe "SimpleTruthValue" do
    it "creates valid truth values" do
      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      tv.strength.should eq(0.8)
      tv.confidence.should eq(0.9)
      tv.valid?.should be_true
    end

    it "rejects invalid truth values" do
      expect_raises(ArgumentError) do
        AtomSpace::SimpleTruthValue.new(-0.1, 0.5)
      end

      expect_raises(ArgumentError) do
        AtomSpace::SimpleTruthValue.new(0.5, 1.1)
      end
    end

    it "converts confidence to count" do
      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.8)
      tv.count.should be_close(4.0, 0.001) # 0.8 / (1 - 0.8) = 4
    end

    it "checks for special values" do
      true_tv = AtomSpace::SimpleTruthValue.new(1.0, 1.0)
      false_tv = AtomSpace::SimpleTruthValue.new(0.0, 1.0)
      null_tv = AtomSpace::SimpleTruthValue.new(0.0, 0.0)

      true_tv.true?.should be_true
      false_tv.false?.should be_true
      null_tv.null?.should be_true
    end

    it "merges truth values correctly" do
      tv1 = AtomSpace::SimpleTruthValue.new(0.8, 0.6)
      tv2 = AtomSpace::SimpleTruthValue.new(0.7, 0.4)

      merged = tv1.merge(tv2)

      # Weighted average: (0.8*0.6 + 0.7*0.4) / (0.6 + 0.4) = 0.76
      merged.strength.should be_close(0.76, 0.01)
      merged.confidence.should eq(1.0) # Capped at 1.0
    end

    it "converts to and from string" do
      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      tv.to_s.should eq("(0.8, 0.9)")

      parsed = AtomSpace::TruthValue.from_string("(0.8, 0.9)")
      parsed.should be_a(AtomSpace::SimpleTruthValue)
      parsed.strength.should eq(0.8)
      parsed.confidence.should eq(0.9)
    end
  end

  describe "CountTruthValue" do
    it "creates valid count truth values" do
      tv = AtomSpace::CountTruthValue.new(0.8, 0.9, 10.0)
      tv.strength.should eq(0.8)
      tv.confidence.should eq(0.9)
      tv.count.should eq(10.0)
    end

    it "merges count truth values" do
      tv1 = AtomSpace::CountTruthValue.new(0.8, 0.6, 5.0)
      tv2 = AtomSpace::CountTruthValue.new(0.6, 0.4, 3.0)

      merged = tv1.merge(tv2)
      merged.should be_a(AtomSpace::CountTruthValue)

      # New count should be sum: 5 + 3 = 8
      merged.count.should eq(8.0)

      # New strength should be weighted average: (0.8*5 + 0.6*3) / 8 = 0.725
      merged.strength.should be_close(0.725, 0.01)
    end
  end

  describe "IndefiniteTruthValue" do
    it "creates valid indefinite truth values" do
      tv = AtomSpace::IndefiniteTruthValue.new(0.3, 0.8, 0.9)
      tv.lower.should eq(0.3)
      tv.upper.should eq(0.8)
      tv.confidence.should eq(0.9)
      tv.strength.should eq(0.55) # (0.3 + 0.8) / 2
    end

    it "rejects invalid bounds" do
      expect_raises(ArgumentError) do
        AtomSpace::IndefiniteTruthValue.new(0.8, 0.3) # lower > upper
      end
    end

    it "merges indefinite truth values" do
      tv1 = AtomSpace::IndefiniteTruthValue.new(0.2, 0.6, 0.5)
      tv2 = AtomSpace::IndefiniteTruthValue.new(0.4, 0.8, 0.5)

      merged = tv1.merge(tv2)
      merged.should be_a(AtomSpace::IndefiniteTruthValue)

      # Intersection should be [0.4, 0.6]
      merged.as(AtomSpace::IndefiniteTruthValue).lower.should eq(0.4)
      merged.as(AtomSpace::IndefiniteTruthValue).upper.should eq(0.6)
    end
  end

  describe "FuzzyTruthValue" do
    it "creates valid fuzzy truth values" do
      tv = AtomSpace::FuzzyTruthValue.new(0.8, 0.9, 0.1)
      tv.strength.should eq(0.8)
      tv.confidence.should eq(0.9)
      tv.uncertainty.should eq(0.1)
    end

    it "merges fuzzy truth values" do
      tv1 = AtomSpace::FuzzyTruthValue.new(0.8, 0.6, 0.1)
      tv2 = AtomSpace::FuzzyTruthValue.new(0.7, 0.4, 0.2)

      merged = tv1.merge(tv2)
      merged.should be_a(AtomSpace::FuzzyTruthValue)

      # Uncertainty should combine: sqrt(0.1^2 + 0.2^2) ≈ 0.224
      merged.as(AtomSpace::FuzzyTruthValue).uncertainty.should be_close(0.224, 0.01)
    end
  end

  describe "TruthValueUtil" do
    it "performs logical AND correctly" do
      tv1 = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      tv2 = AtomSpace::SimpleTruthValue.new(0.6, 0.7)

      result = AtomSpace::TruthValueUtil.and_tv(tv1, tv2)

      # AND: strength = 0.8 * 0.6 = 0.48, confidence = 0.9 * 0.7 = 0.63
      result.strength.should eq(0.48)
      result.confidence.should eq(0.63)
    end

    it "performs logical OR correctly" do
      tv1 = AtomSpace::SimpleTruthValue.new(0.6, 0.8)
      tv2 = AtomSpace::SimpleTruthValue.new(0.4, 0.7)

      result = AtomSpace::TruthValueUtil.or_tv(tv1, tv2)

      # OR: strength = 0.6 + 0.4 - 0.6*0.4 = 0.76
      result.strength.should eq(0.76)
      result.confidence.should be_close(0.56, 0.001) # 0.8 * 0.7
    end

    it "performs logical NOT correctly" do
      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)

      result = AtomSpace::TruthValueUtil.not_tv(tv)

      # NOT: strength = 1 - 0.8 = 0.2, confidence unchanged
      result.strength.should be_close(0.2, 0.001)
      result.confidence.should eq(0.9)
    end

    it "performs implication correctly" do
      tv1 = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      tv2 = AtomSpace::SimpleTruthValue.new(0.6, 0.7)

      result = AtomSpace::TruthValueUtil.implies_tv(tv1, tv2)

      # Implication is ¬A ∨ B
      # ¬A = (0.2, 0.9), B = (0.6, 0.7)
      # ¬A ∨ B = 0.2 + 0.6 - 0.2*0.6 = 0.68
      result.strength.should be_close(0.68, 0.001)
    end
  end

  describe "default truth values" do
    it "provides standard default values" do
      AtomSpace::TruthValue::DEFAULT_TV.strength.should eq(1.0)
      AtomSpace::TruthValue::DEFAULT_TV.confidence.should eq(0.0)

      AtomSpace::TruthValue::TRUE_TV.strength.should eq(1.0)
      AtomSpace::TruthValue::TRUE_TV.confidence.should eq(1.0)

      AtomSpace::TruthValue::FALSE_TV.strength.should eq(0.0)
      AtomSpace::TruthValue::FALSE_TV.confidence.should eq(1.0)

      AtomSpace::TruthValue::NULL_TV.strength.should eq(0.0)
      AtomSpace::TruthValue::NULL_TV.confidence.should eq(0.0)
    end
  end

  describe "SimpleTruthValue additional cases" do
    it "to_a returns [strength, confidence]" do
      tv = AtomSpace::SimpleTruthValue.new(0.7, 0.6)
      tv.to_a.should eq([0.7, 0.6])
    end

    it "valid? returns false for out-of-range values after creation would fail" do
      tv = AtomSpace::SimpleTruthValue.new(0.5, 0.5)
      tv.valid?.should be_true
    end

    it "hash is consistent for equal truth values" do
      tv1 = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      tv2 = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      tv1.hash.should eq(tv2.hash)
    end

    it "equality check works" do
      tv1 = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      tv2 = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      tv3 = AtomSpace::SimpleTruthValue.new(0.7, 0.9)

      (tv1 == tv2).should be_true
      (tv1 == tv3).should be_false
    end

    it "equality fails for different truth value types" do
      stv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      ctv = AtomSpace::CountTruthValue.new(0.8, 0.9, 10.0)
      (stv == ctv).should be_false
    end

    it "type_name returns SimpleTruthValue" do
      tv = AtomSpace::SimpleTruthValue.new(0.5, 0.5)
      tv.type_name.should eq("SimpleTruthValue")
    end

    it "count is 0 when confidence is 0" do
      tv = AtomSpace::SimpleTruthValue.new(0.5, 0.0)
      tv.count.should eq(0.0)
    end

    it "clone produces equal but distinct object" do
      tv = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      cloned = tv.clone
      (tv == cloned).should be_true
    end

    it "merges with zero-confidence second TV returns clone of first" do
      tv1 = AtomSpace::SimpleTruthValue.new(0.8, 0.6)
      tv2 = AtomSpace::SimpleTruthValue.new(0.0, 0.0)
      merged = tv1.merge(tv2)
      (merged == tv1).should be_true
    end

    it "from_string parses space-separated format" do
      parsed = AtomSpace::TruthValue.from_string("0.7 0.5")
      parsed.should be_a(AtomSpace::SimpleTruthValue)
      parsed.strength.should eq(0.7)
      parsed.confidence.should eq(0.5)
    end

    it "from_string raises ArgumentError for invalid format" do
      expect_raises(ArgumentError) do
        AtomSpace::TruthValue.from_string("invalid_format")
      end
    end
  end

  describe "CountTruthValue additional cases" do
    it "type_name returns CountTruthValue" do
      tv = AtomSpace::CountTruthValue.new(0.5, 0.5, 5.0)
      tv.type_name.should eq("CountTruthValue")
    end

    it "to_s includes count" do
      tv = AtomSpace::CountTruthValue.new(0.5, 0.5, 5.0)
      tv.to_s.should contain("5.0")
    end

    it "clone produces equal object" do
      tv = AtomSpace::CountTruthValue.new(0.5, 0.5, 5.0)
      cloned = tv.clone
      cloned.should be_a(AtomSpace::CountTruthValue)
      cloned.count.should eq(5.0)
    end

    it "rejects negative count" do
      expect_raises(ArgumentError) do
        AtomSpace::CountTruthValue.new(0.5, 0.5, -1.0)
      end
    end

    it "merges with SimpleTruthValue by converting it" do
      ctv = AtomSpace::CountTruthValue.new(0.8, 0.6, 5.0)
      stv = AtomSpace::SimpleTruthValue.new(0.6, 0.5)
      merged = ctv.merge(stv)
      # Should return a CountTruthValue
      merged.should be_a(AtomSpace::CountTruthValue)
    end

    it "to_a returns [strength, confidence]" do
      tv = AtomSpace::CountTruthValue.new(0.7, 0.6, 3.0)
      tv.to_a.should eq([0.7, 0.6])
    end
  end

  describe "IndefiniteTruthValue additional cases" do
    it "type_name returns IndefiniteTruthValue" do
      tv = AtomSpace::IndefiniteTruthValue.new(0.2, 0.8)
      tv.type_name.should eq("IndefiniteTruthValue")
    end

    it "clone produces equal object" do
      tv = AtomSpace::IndefiniteTruthValue.new(0.3, 0.7, 0.8)
      cloned = tv.clone
      cloned.should be_a(AtomSpace::IndefiniteTruthValue)
      cloned.as(AtomSpace::IndefiniteTruthValue).lower.should eq(0.3)
      cloned.as(AtomSpace::IndefiniteTruthValue).upper.should eq(0.7)
    end

    it "rejects confidence > 1" do
      expect_raises(ArgumentError) do
        AtomSpace::IndefiniteTruthValue.new(0.2, 0.8, 1.5)
      end
    end

    it "allows equal lower and upper bounds" do
      tv = AtomSpace::IndefiniteTruthValue.new(0.5, 0.5)
      tv.strength.should eq(0.5)
    end

    it "merges with SimpleTruthValue" do
      itv = AtomSpace::IndefiniteTruthValue.new(0.3, 0.7, 0.5)
      stv = AtomSpace::SimpleTruthValue.new(0.5, 0.5)
      merged = itv.merge(stv)
      merged.should be_a(AtomSpace::IndefiniteTruthValue)
    end

    it "merges non-overlapping intervals using weighted average" do
      tv1 = AtomSpace::IndefiniteTruthValue.new(0.1, 0.2, 0.5)
      tv2 = AtomSpace::IndefiniteTruthValue.new(0.8, 0.9, 0.5)
      merged = tv1.merge(tv2)
      merged.should be_a(AtomSpace::IndefiniteTruthValue)
      # Non-overlapping: should compute weighted average of bounds
      itv = merged.as(AtomSpace::IndefiniteTruthValue)
      itv.lower.should be < itv.upper
    end

    it "count is computed correctly" do
      tv = AtomSpace::IndefiniteTruthValue.new(0.3, 0.7, 0.5)
      tv.count.should be_close(1.0, 0.001) # 0.5 / (1 - 0.5) = 1.0
    end
  end

  describe "FuzzyTruthValue additional cases" do
    it "type_name returns FuzzyTruthValue" do
      tv = AtomSpace::FuzzyTruthValue.new(0.5, 0.5, 0.1)
      tv.type_name.should eq("FuzzyTruthValue")
    end

    it "rejects negative uncertainty" do
      expect_raises(ArgumentError) do
        AtomSpace::FuzzyTruthValue.new(0.5, 0.5, -0.1)
      end
    end

    it "rejects uncertainty > 1" do
      expect_raises(ArgumentError) do
        AtomSpace::FuzzyTruthValue.new(0.5, 0.5, 1.5)
      end
    end

    it "merges with SimpleTruthValue preserves original uncertainty" do
      ftv = AtomSpace::FuzzyTruthValue.new(0.8, 0.6, 0.2)
      stv = AtomSpace::SimpleTruthValue.new(0.7, 0.4)
      merged = ftv.merge(stv)
      merged.should be_a(AtomSpace::FuzzyTruthValue)
      merged.as(AtomSpace::FuzzyTruthValue).uncertainty.should eq(0.2)
    end

    it "clone produces equal object" do
      tv = AtomSpace::FuzzyTruthValue.new(0.7, 0.8, 0.15)
      cloned = tv.clone
      cloned.should be_a(AtomSpace::FuzzyTruthValue)
      cloned.as(AtomSpace::FuzzyTruthValue).uncertainty.should eq(0.15)
    end
  end

  describe "TruthValueUtil additional cases" do
    it "implies_tv with FALSE antecedent is always TRUE" do
      false_tv = AtomSpace::SimpleTruthValue.new(0.0, 1.0)
      any_tv = AtomSpace::SimpleTruthValue.new(0.5, 0.5)
      result = AtomSpace::TruthValueUtil.implies_tv(false_tv, any_tv)
      # ¬false = (1.0, 1.0); OR with any = (1.0, ...)
      result.strength.should be > 0.9
    end

    it "and_tv with zero-strength returns near-zero strength" do
      tv1 = AtomSpace::SimpleTruthValue.new(0.0, 0.9)
      tv2 = AtomSpace::SimpleTruthValue.new(0.8, 0.9)
      result = AtomSpace::TruthValueUtil.and_tv(tv1, tv2)
      result.strength.should eq(0.0)
    end

    it "or_tv with full-strength tv1 is always high" do
      tv1 = AtomSpace::SimpleTruthValue.new(1.0, 0.9)
      tv2 = AtomSpace::SimpleTruthValue.new(0.3, 0.7)
      result = AtomSpace::TruthValueUtil.or_tv(tv1, tv2)
      result.strength.should eq(1.0)
    end

    it "not_tv of TRUE_TV gives near-zero strength" do
      result = AtomSpace::TruthValueUtil.not_tv(AtomSpace::TruthValue::TRUE_TV)
      result.strength.should be_close(0.0, 0.001)
    end
  end
end
