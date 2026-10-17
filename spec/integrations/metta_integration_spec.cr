require "../spec_helper"
require "../../src/integrations/metta_integration"

describe CrystalCog::Integrations do
  describe CrystalCog::Integrations::MeTTaSymbol do
    it "creates symbol" do
      sym = CrystalCog::Integrations::MeTTaSymbol.new("foo")
      sym.name.should eq "foo"
      sym.atom_type.should eq CrystalCog::Integrations::MeTTaType::Symbol
      sym.to_metta.should eq "foo"
    end

    it "compares symbols" do
      sym1 = CrystalCog::Integrations::MeTTaSymbol.new("foo")
      sym2 = CrystalCog::Integrations::MeTTaSymbol.new("foo")
      sym3 = CrystalCog::Integrations::MeTTaSymbol.new("bar")

      (sym1 == sym2).should be_true
      (sym1 == sym3).should be_false
    end

    it "matches patterns" do
      sym = CrystalCog::Integrations::MeTTaSymbol.new("foo")
      var = CrystalCog::Integrations::MeTTaVariable.new("x")

      sym.matches?(var).should be_true
      sym.matches?(sym).should be_true
    end

    it "is not a variable" do
      sym = CrystalCog::Integrations::MeTTaSymbol.new("foo")
      sym.variable?.should be_false
      sym.symbol?.should be_true
    end
  end

  describe CrystalCog::Integrations::MeTTaVariable do
    it "creates variable" do
      var = CrystalCog::Integrations::MeTTaVariable.new("x")
      var.name.should eq "x"
      var.atom_type.should eq CrystalCog::Integrations::MeTTaType::Variable
      var.to_metta.should eq "$x"
    end

    it "matches anything" do
      var = CrystalCog::Integrations::MeTTaVariable.new("x")
      sym = CrystalCog::Integrations::MeTTaSymbol.new("foo")
      num = CrystalCog::Integrations::MeTTaGrounded.new(42)

      var.matches?(sym).should be_true
      var.matches?(num).should be_true
    end

    it "is a variable" do
      var = CrystalCog::Integrations::MeTTaVariable.new("x")
      var.variable?.should be_true
    end
  end

  describe CrystalCog::Integrations::MeTTaGrounded do
    it "creates grounded integer" do
      num = CrystalCog::Integrations::MeTTaGrounded.new(42)
      num.value_type.should eq "Number"
      num.as_int.should eq 42
      num.to_metta.should eq "42"
    end

    it "creates grounded float" do
      num = CrystalCog::Integrations::MeTTaGrounded.new(3.14)
      num.value_type.should eq "Float"
      num.as_float.should eq 3.14
    end

    it "creates grounded string" do
      str = CrystalCog::Integrations::MeTTaGrounded.new("hello")
      str.value_type.should eq "String"
      str.as_string.should eq "hello"
      str.to_metta.should eq "\"hello\""
    end

    it "creates grounded boolean" do
      bool = CrystalCog::Integrations::MeTTaGrounded.new(true)
      bool.value_type.should eq "Bool"
      bool.as_bool.should eq true
    end

    it "is grounded" do
      num = CrystalCog::Integrations::MeTTaGrounded.new(42)
      num.grounded?.should be_true
    end
  end

  describe CrystalCog::Integrations::MeTTaExpression do
    it "creates expression" do
      sym = CrystalCog::Integrations::MeTTaSymbol.new("foo")
      num = CrystalCog::Integrations::MeTTaGrounded.new(42)
      expr = CrystalCog::Integrations::MeTTaExpression.new([sym, num] of CrystalCog::Integrations::MeTTaAtom)

      expr.size.should eq 2
      expr.head.should eq sym
      expr.tail.should eq [num]
      expr.to_metta.should eq "(foo 42)"
    end

    it "creates nested expression" do
      inner = CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("a"),
        CrystalCog::Integrations::MeTTaSymbol.new("b"),
      ] of CrystalCog::Integrations::MeTTaAtom)
      outer = CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("f"),
        inner,
      ] of CrystalCog::Integrations::MeTTaAtom)

      outer.to_metta.should eq "(f (a b))"
    end

    it "compares expressions" do
      e1 = CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("a"),
      ] of CrystalCog::Integrations::MeTTaAtom)
      e2 = CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("a"),
      ] of CrystalCog::Integrations::MeTTaAtom)

      (e1 == e2).should be_true
    end

    it "is an expression" do
      expr = CrystalCog::Integrations::MeTTaExpression.new
      expr.expression?.should be_true
      expr.empty?.should be_true
    end
  end

  describe CrystalCog::Integrations::MeTTaEmpty do
    it "creates empty value" do
      empty = CrystalCog::Integrations::MeTTaEmpty.new
      empty.atom_type.should eq CrystalCog::Integrations::MeTTaType::Empty
      empty.to_metta.should eq "()"
    end
  end

  describe CrystalCog::Integrations::MeTTaError do
    it "creates error" do
      err = CrystalCog::Integrations::MeTTaError.new("Something went wrong")
      err.message.should eq "Something went wrong"
      err.to_metta.should contain "Error"
    end
  end

  describe CrystalCog::Integrations::MeTTaBindings do
    it "creates empty bindings" do
      bindings = CrystalCog::Integrations::MeTTaBindings.new
      bindings.empty?.should be_true
      bindings.size.should eq 0
    end

    it "binds values" do
      bindings = CrystalCog::Integrations::MeTTaBindings.new
      sym = CrystalCog::Integrations::MeTTaSymbol.new("foo")

      bindings.bind("x", sym).should be_true
      bindings.get("x").should eq sym
      bindings.has?("x").should be_true
      bindings.size.should eq 1
    end

    it "fails on conflicting bindings" do
      bindings = CrystalCog::Integrations::MeTTaBindings.new
      sym1 = CrystalCog::Integrations::MeTTaSymbol.new("foo")
      sym2 = CrystalCog::Integrations::MeTTaSymbol.new("bar")

      bindings.bind("x", sym1).should be_true
      bindings.bind("x", sym2).should be_false
    end

    it "allows same binding" do
      bindings = CrystalCog::Integrations::MeTTaBindings.new
      sym = CrystalCog::Integrations::MeTTaSymbol.new("foo")

      bindings.bind("x", sym).should be_true
      bindings.bind("x", sym).should be_true
    end

    it "applies bindings" do
      bindings = CrystalCog::Integrations::MeTTaBindings.new
      sym = CrystalCog::Integrations::MeTTaSymbol.new("foo")
      bindings.bind("x", sym)

      var = CrystalCog::Integrations::MeTTaVariable.new("x")
      result = bindings.apply(var)
      result.should eq sym
    end

    it "merges bindings" do
      b1 = CrystalCog::Integrations::MeTTaBindings.new
      b2 = CrystalCog::Integrations::MeTTaBindings.new

      b1.bind("x", CrystalCog::Integrations::MeTTaSymbol.new("a"))
      b2.bind("y", CrystalCog::Integrations::MeTTaSymbol.new("b"))

      merged = b1.merge(b2)
      merged.should_not be_nil
      merged.not_nil!.has?("x").should be_true
      merged.not_nil!.has?("y").should be_true
    end

    it "fails merge on conflict" do
      b1 = CrystalCog::Integrations::MeTTaBindings.new
      b2 = CrystalCog::Integrations::MeTTaBindings.new

      b1.bind("x", CrystalCog::Integrations::MeTTaSymbol.new("a"))
      b2.bind("x", CrystalCog::Integrations::MeTTaSymbol.new("b"))

      b1.merge(b2).should be_nil
    end
  end

  describe CrystalCog::Integrations::MeTTaPatternMatcher do
    matcher = CrystalCog::Integrations::MeTTaPatternMatcher.new

    it "matches symbol to symbol" do
      sym1 = CrystalCog::Integrations::MeTTaSymbol.new("foo")
      sym2 = CrystalCog::Integrations::MeTTaSymbol.new("foo")

      bindings = matcher.match(sym1, sym2)
      bindings.should_not be_nil
    end

    it "matches atom to variable" do
      sym = CrystalCog::Integrations::MeTTaSymbol.new("foo")
      var = CrystalCog::Integrations::MeTTaVariable.new("x")

      bindings = matcher.match(sym, var)
      bindings.should_not be_nil
      bindings.not_nil!.get("x").should eq sym
    end

    it "matches expression pattern" do
      atom = CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("Person"),
        CrystalCog::Integrations::MeTTaSymbol.new("Alice"),
      ] of CrystalCog::Integrations::MeTTaAtom)

      pattern = CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("Person"),
        CrystalCog::Integrations::MeTTaVariable.new("name"),
      ] of CrystalCog::Integrations::MeTTaAtom)

      bindings = matcher.match(atom, pattern)
      bindings.should_not be_nil
      bindings.not_nil!.get("name").not_nil!.to_metta.should eq "Alice"
    end

    it "fails on different structure" do
      atom = CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("a"),
        CrystalCog::Integrations::MeTTaSymbol.new("b"),
      ] of CrystalCog::Integrations::MeTTaAtom)

      pattern = CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("a"),
      ] of CrystalCog::Integrations::MeTTaAtom)

      matcher.match(atom, pattern).should be_nil
    end

    it "matches all atoms in array" do
      atoms = [
        CrystalCog::Integrations::MeTTaExpression.new([
          CrystalCog::Integrations::MeTTaSymbol.new("Person"),
          CrystalCog::Integrations::MeTTaSymbol.new("Alice"),
        ] of CrystalCog::Integrations::MeTTaAtom),
        CrystalCog::Integrations::MeTTaExpression.new([
          CrystalCog::Integrations::MeTTaSymbol.new("Person"),
          CrystalCog::Integrations::MeTTaSymbol.new("Bob"),
        ] of CrystalCog::Integrations::MeTTaAtom),
        CrystalCog::Integrations::MeTTaExpression.new([
          CrystalCog::Integrations::MeTTaSymbol.new("Animal"),
          CrystalCog::Integrations::MeTTaSymbol.new("Cat"),
        ] of CrystalCog::Integrations::MeTTaAtom),
      ] of CrystalCog::Integrations::MeTTaAtom

      pattern = CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("Person"),
        CrystalCog::Integrations::MeTTaVariable.new("name"),
      ] of CrystalCog::Integrations::MeTTaAtom)

      results = matcher.match_all(atoms, pattern)
      results.size.should eq 2
    end

    it "unifies atoms" do
      var_x = CrystalCog::Integrations::MeTTaVariable.new("x")
      var_y = CrystalCog::Integrations::MeTTaVariable.new("y")
      sym = CrystalCog::Integrations::MeTTaSymbol.new("foo")

      bindings = matcher.unify(var_x, sym)
      bindings.should_not be_nil
      bindings.not_nil!.get("x").should eq sym
    end
  end

  describe CrystalCog::Integrations::MeTTaRule do
    it "creates rule" do
      pattern = CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("inc"),
        CrystalCog::Integrations::MeTTaVariable.new("x"),
      ] of CrystalCog::Integrations::MeTTaAtom)

      template = CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("+"),
        CrystalCog::Integrations::MeTTaVariable.new("x"),
        CrystalCog::Integrations::MeTTaGrounded.new(1),
      ] of CrystalCog::Integrations::MeTTaAtom)

      rule = CrystalCog::Integrations::MeTTaRule.new("increment", pattern, template)
      rule.name.should eq "increment"
      rule.to_metta.should contain "="
    end

    it "applies rule" do
      pattern = CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("double"),
        CrystalCog::Integrations::MeTTaVariable.new("x"),
      ] of CrystalCog::Integrations::MeTTaAtom)

      template = CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("+"),
        CrystalCog::Integrations::MeTTaVariable.new("x"),
        CrystalCog::Integrations::MeTTaVariable.new("x"),
      ] of CrystalCog::Integrations::MeTTaAtom)

      rule = CrystalCog::Integrations::MeTTaRule.new("double", pattern, template)

      atom = CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("double"),
        CrystalCog::Integrations::MeTTaGrounded.new(5),
      ] of CrystalCog::Integrations::MeTTaAtom)

      matcher = CrystalCog::Integrations::MeTTaPatternMatcher.new
      result = rule.apply(atom, matcher)

      result.should_not be_nil
      result.not_nil!.to_metta.should eq "(+ 5 5)"
    end
  end

  describe CrystalCog::Integrations::MeTTaSpace do
    it "creates empty space" do
      space = CrystalCog::Integrations::MeTTaSpace.new
      space.size.should eq 0
    end

    it "adds atoms" do
      space = CrystalCog::Integrations::MeTTaSpace.new
      sym = CrystalCog::Integrations::MeTTaSymbol.new("foo")

      space.add(sym).should be_true
      space.size.should eq 1
      space.contains?(sym).should be_true
    end

    it "removes atoms" do
      space = CrystalCog::Integrations::MeTTaSpace.new
      sym = CrystalCog::Integrations::MeTTaSymbol.new("foo")

      space.add(sym)
      space.remove(sym).should be_true
      space.size.should eq 0
    end

    it "queries atoms" do
      space = CrystalCog::Integrations::MeTTaSpace.new
      space.add(CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("Person"),
        CrystalCog::Integrations::MeTTaSymbol.new("Alice"),
      ] of CrystalCog::Integrations::MeTTaAtom))

      pattern = CrystalCog::Integrations::MeTTaExpression.new([
        CrystalCog::Integrations::MeTTaSymbol.new("Person"),
        CrystalCog::Integrations::MeTTaVariable.new("name"),
      ] of CrystalCog::Integrations::MeTTaAtom)

      results = space.query(pattern)
      results.size.should eq 1
      results.first.get("name").not_nil!.to_metta.should eq "Alice"
    end

    it "exports to MeTTa format" do
      space = CrystalCog::Integrations::MeTTaSpace.new
      space.add(CrystalCog::Integrations::MeTTaSymbol.new("foo"))
      space.add(CrystalCog::Integrations::MeTTaGrounded.new(42))

      metta = space.to_metta
      metta.should contain "foo"
      metta.should contain "42"
    end
  end

  describe CrystalCog::Integrations::MeTTaParser do
    it "parses symbol" do
      parser = CrystalCog::Integrations::MeTTaParser.new("foo")
      atoms = parser.parse
      atoms.size.should eq 1
      atoms.first.to_metta.should eq "foo"
    end

    it "parses variable" do
      parser = CrystalCog::Integrations::MeTTaParser.new("$x")
      atoms = parser.parse
      atoms.first.to_metta.should eq "$x"
      atoms.first.variable?.should be_true
    end

    it "parses number" do
      parser = CrystalCog::Integrations::MeTTaParser.new("42")
      atoms = parser.parse
      atoms.first.as(CrystalCog::Integrations::MeTTaGrounded).as_int.should eq 42
    end

    it "parses float" do
      parser = CrystalCog::Integrations::MeTTaParser.new("3.14")
      atoms = parser.parse
      atoms.first.as(CrystalCog::Integrations::MeTTaGrounded).as_float.should eq 3.14
    end

    it "parses string" do
      parser = CrystalCog::Integrations::MeTTaParser.new("\"hello world\"")
      atoms = parser.parse
      atoms.first.as(CrystalCog::Integrations::MeTTaGrounded).as_string.should eq "hello world"
    end

    it "parses expression" do
      parser = CrystalCog::Integrations::MeTTaParser.new("(foo bar)")
      atoms = parser.parse
      atoms.first.to_metta.should eq "(foo bar)"
    end

    it "parses nested expression" do
      parser = CrystalCog::Integrations::MeTTaParser.new("(f (g x))")
      atoms = parser.parse
      atoms.first.to_metta.should eq "(f (g x))"
    end

    it "parses multiple atoms" do
      parser = CrystalCog::Integrations::MeTTaParser.new("foo bar 42")
      atoms = parser.parse
      atoms.size.should eq 3
    end

    it "handles comments" do
      parser = CrystalCog::Integrations::MeTTaParser.new("; this is a comment\nfoo")
      atoms = parser.parse
      atoms.size.should eq 1
      atoms.first.to_metta.should eq "foo"
    end
  end

  describe CrystalCog::Integrations::MeTTaInterpreter do
    it "evaluates arithmetic" do
      interp = CrystalCog::Integrations::MeTTaInterpreter.new
      result = interp.eval("(+ 1 2 3)")
      result.should_not be_nil
      result.not_nil!.as(CrystalCog::Integrations::MeTTaGrounded).as_float.should eq 6.0
    end

    it "evaluates multiplication" do
      interp = CrystalCog::Integrations::MeTTaInterpreter.new
      result = interp.eval("(* 2 3 4)")
      result.not_nil!.as(CrystalCog::Integrations::MeTTaGrounded).as_float.should eq 24.0
    end

    it "evaluates comparison" do
      interp = CrystalCog::Integrations::MeTTaInterpreter.new

      result = interp.eval("(< 1 2)")
      result.not_nil!.to_metta.should eq "True"

      result = interp.eval("(> 1 2)")
      result.not_nil!.to_metta.should eq "False"
    end

    it "evaluates if" do
      interp = CrystalCog::Integrations::MeTTaInterpreter.new
      result = interp.eval("(if True yes no)")
      result.not_nil!.to_metta.should eq "yes"
    end

    it "defines and applies rules" do
      interp = CrystalCog::Integrations::MeTTaInterpreter.new
      interp.run("(= (double $x) (* 2 $x))")

      result = interp.eval("(double 21)")
      result.not_nil!.as(CrystalCog::Integrations::MeTTaGrounded).as_float.should eq 42.0
    end
  end
end
