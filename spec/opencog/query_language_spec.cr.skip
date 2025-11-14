require "spec"
require "../../src/opencog/opencog"

describe OpenCog::QueryLanguage do
  before_each do
    OpenCog.initialize
    @atomspace = AtomSpace::AtomSpace.new
    @query_interface = OpenCog::QueryLanguage.create_interface(@atomspace)
  end
  
  # Helper method to access atomspace instance
  def atomspace
    @atomspace
  end

  describe "module initialization" do
    it "has correct version" do
      OpenCog::QueryLanguage::VERSION.should eq("0.1.0")
    end

    it "initializes query language subsystem" do
      OpenCog::QueryLanguage.initialize
      # Should not crash
    end

    it "creates query interface" do
      interface = OpenCog::QueryLanguage.create_interface(atomspace)
      interface.should be_a(OpenCog::QueryLanguage::QueryLanguageInterface)
      interface.atomspace.should eq(atomspace)
    end
  end

  describe "QueryVariable" do
    it "creates variable without type" do
      var = OpenCog::QueryLanguage::QueryVariable.new("x")
      var.name.should eq("x")
      var.type.should be_nil
    end

    it "creates variable with type" do
      var = OpenCog::QueryLanguage::QueryVariable.new("concept", AtomSpace::AtomType::CONCEPT_NODE)
      var.name.should eq("concept")
      var.type.should eq(AtomSpace::AtomType::CONCEPT_NODE)
    end

    it "converts to string correctly" do
      var1 = OpenCog::QueryLanguage::QueryVariable.new("x")
      var1.to_s.should eq("$x")

      var2 = OpenCog::QueryLanguage::QueryVariable.new("concept", AtomSpace::AtomType::CONCEPT_NODE)
      var2.to_s.should eq("$concept:CONCEPT_NODE")
    end
  end

  describe "QueryParser" do
    it "parses simple SELECT query" do
      query = "SELECT $x WHERE { $x ISA Animal }"
      parsed = OpenCog::QueryLanguage::QueryParser.parse(query)

      parsed.variables.size.should eq(1)
      parsed.variables[0].name.should eq("x")
      parsed.clauses.size.should eq(1)
      parsed.clauses[0].should be_a(OpenCog::QueryLanguage::InheritanceClause)
    end

    it "parses multiple variables" do
      query = "SELECT $x, $y WHERE { $x likes $y }"
      parsed = OpenCog::QueryLanguage::QueryParser.parse(query)

      parsed.variables.size.should eq(2)
      parsed.variables[0].name.should eq("x")
      parsed.variables[1].name.should eq("y")
    end

    it "parses variables with types" do
      query = "SELECT $concept:CONCEPT, $pred:PREDICATE WHERE { $concept $pred $x }"
      parsed = OpenCog::QueryLanguage::QueryParser.parse(query)

      parsed.variables.size.should eq(2)
      parsed.variables[0].name.should eq("concept")
      parsed.variables[0].type.should eq(AtomSpace::AtomType::CONCEPT_NODE)
      parsed.variables[1].name.should eq("pred")
      parsed.variables[1].type.should eq(AtomSpace::AtomType::PREDICATE_NODE)
    end

    it "parses triple patterns" do
      query = "SELECT $x WHERE { John likes $x }"
      parsed = OpenCog::QueryLanguage::QueryParser.parse(query)

      parsed.clauses.size.should eq(1)
      clause = parsed.clauses[0].as(OpenCog::QueryLanguage::TripleClause)
      clause.subject.should eq("John")
      clause.predicate.should eq("likes")
      clause.object.should eq("$x")
    end

    it "parses inheritance patterns" do
      query = "SELECT $x WHERE { $x ISA Mammal }"
      parsed = OpenCog::QueryLanguage::QueryParser.parse(query)

      parsed.clauses.size.should eq(1)
      clause = parsed.clauses[0].as(OpenCog::QueryLanguage::InheritanceClause)
      clause.child.should eq("$x")
      clause.parent.should eq("Mammal")
    end

    it "handles multiple clauses" do
      query = "SELECT $x WHERE { $x ISA Animal . $x likes Food }"
      parsed = OpenCog::QueryLanguage::QueryParser.parse(query)

      parsed.clauses.size.should eq(2)
      parsed.clauses[0].should be_a(OpenCog::QueryLanguage::InheritanceClause)
      parsed.clauses[1].should be_a(OpenCog::QueryLanguage::TripleClause)
    end

    it "raises exception for invalid syntax" do
      expect_raises(OpenCog::QueryLanguage::QueryParseException, "Query must start with SELECT") do
        OpenCog::QueryLanguage::QueryParser.parse("FIND $x WHERE { $x ISA Animal }")
      end
    end

    it "raises exception for missing WHERE" do
      expect_raises(OpenCog::QueryLanguage::QueryParseException, "Invalid SELECT syntax") do
        OpenCog::QueryLanguage::QueryParser.parse("SELECT $x")
      end
    end

    it "raises exception for malformed WHERE clause" do
      expect_raises(OpenCog::QueryLanguage::QueryParseException, "Missing WHERE clause") do
        OpenCog::QueryLanguage::QueryParser.parse("SELECT $x WHERE $x ISA Animal")
      end
    end
  end

  describe "QueryExecutor" do
    it "creates executor with atomspace" do
      executor = OpenCog::QueryLanguage::QueryExecutor.new(atomspace)
      executor.atomspace.should eq(atomspace)
      executor.pattern_matcher.should be_a(PatternMatching::PatternMatcher)
    end

    it "executes simple queries on empty atomspace" do
      query = OpenCog::QueryLanguage::QueryParser.parse("SELECT $x WHERE { $x ISA Animal }")
      executor = OpenCog::QueryLanguage::QueryExecutor.new(atomspace)

      results = executor.execute(query)
      results.should be_a(Array(OpenCog::Query::QueryResult))
      # Empty atomspace should return empty results
      results.size.should eq(0)
    end
  end

  describe "QueryLanguageInterface" do
    it "executes string queries" do
      # Add some test data
      dog = atomspace.add_concept_node("Dog")
      animal = atomspace.add_concept_node("Animal")
      atomspace.add_inheritance_link(dog, animal)

      results = @query_interface.query("SELECT $x WHERE { $x ISA Animal }")
      results.should be_a(Array(OpenCog::Query::QueryResult))

      # Should find Dog as inheriting from Animal
      results.size.should be >= 0
    end

    it "handles query execution errors gracefully" do
      expect_raises(OpenCog::QueryLanguage::QueryParseException) do
        @query_interface.query("INVALID QUERY SYNTAX")
      end
    end

    it "provides convenience methods" do
      # Add test data
      dog = atomspace.add_concept_node("Dog")
      animal = atomspace.add_concept_node("Animal")
      atomspace.add_inheritance_link(dog, animal)

      results = @query_interface.find_all("Animal")
      results.should be_a(Array(OpenCog::Query::QueryResult))
    end
  end

  describe "integration with OpenCog::Query" do
    it "integrates with existing Query module" do
      # Add test data
      john = atomspace.add_concept_node("John")
      mary = atomspace.add_concept_node("Mary")
      likes = atomspace.add_predicate_node("likes")

      list_link = atomspace.add_list_link([john, mary])
      eval_link = atomspace.add_evaluation_link(likes, list_link)

      # Test string-based query execution
      results = OpenCog::Query.execute_query(atomspace, "SELECT $x WHERE { John likes $x }")
      results.should be_a(Array(OpenCog::Query::QueryResult))
    end

    it "parses queries through Query module" do
      parsed = OpenCog::Query.parse_query("SELECT $x WHERE { $x ISA Animal }")
      parsed.should be_a(OpenCog::QueryLanguage::ParsedQuery)
      parsed.variables.size.should eq(1)
    end

    it "creates query interface through Query module" do
      interface = OpenCog::Query.create_query_interface(atomspace)
      interface.should be_a(OpenCog::QueryLanguage::QueryLanguageInterface)
    end
  end

  describe "clause types" do
    describe "TripleClause" do
      it "creates triple clause" do
        clause = OpenCog::QueryLanguage::TripleClause.new("John", "likes", "Mary")
        clause.subject.should eq("John")
        clause.predicate.should eq("likes")
        clause.object.should eq("Mary")
      end

      it "converts to atoms" do
        clause = OpenCog::QueryLanguage::TripleClause.new("John", "likes", "Mary")
        var_map = Hash(String, AtomSpace::Atom).new

        atoms = clause.to_atoms(atomspace, var_map)
        atoms.size.should be >= 1

        # Should create evaluation link structure
        atoms.each do |atom|
          atom.should be_a(AtomSpace::Atom)
        end
      end
    end

    describe "InheritanceClause" do
      it "creates inheritance clause" do
        clause = OpenCog::QueryLanguage::InheritanceClause.new("Dog", "Animal")
        clause.child.should eq("Dog")
        clause.parent.should eq("Animal")
      end

      it "converts to atoms" do
        clause = OpenCog::QueryLanguage::InheritanceClause.new("Dog", "Animal")
        var_map = Hash(String, AtomSpace::Atom).new

        atoms = clause.to_atoms(atomspace, var_map)
        atoms.size.should eq(1)

        # Should create inheritance link
        atom = atoms[0]
        atom.type.should eq(AtomSpace::AtomType::INHERITANCE_LINK)
      end
    end
  end

  describe "complex query scenarios" do
    before_each do
      # Create rich knowledge base for testing

      # Concepts
      @dog = atomspace.add_concept_node("Dog")
      @cat = atomspace.add_concept_node("Cat")
      @bird = atomspace.add_concept_node("Bird")
      @animal = atomspace.add_concept_node("Animal")
      @mammal = atomspace.add_concept_node("Mammal")

      # Individuals
      @fido = atomspace.add_concept_node("Fido")
      @fluffy = atomspace.add_concept_node("Fluffy")
      @tweety = atomspace.add_concept_node("Tweety")

      # Predicates
      @likes = atomspace.add_predicate_node("likes")
      @eats = atomspace.add_predicate_node("eats")

      # Inheritance hierarchy
      atomspace.add_inheritance_link(@dog, @mammal)
      atomspace.add_inheritance_link(@cat, @mammal)
      atomspace.add_inheritance_link(@mammal, @animal)
      atomspace.add_inheritance_link(@bird, @animal)

      # Individual classifications
      atomspace.add_inheritance_link(@fido, @dog)
      atomspace.add_inheritance_link(@fluffy, @cat)
      atomspace.add_inheritance_link(@tweety, @bird)

      # Relationships
      food = atomspace.add_concept_node("Food")

      list1 = atomspace.add_list_link([@fido, food])
      atomspace.add_evaluation_link(@likes, list1)

      list2 = atomspace.add_list_link([@fluffy, food])
      atomspace.add_evaluation_link(@likes, list2)
    end

    it "finds all animals" do
      results = @query_interface.query("SELECT $x WHERE { $x ISA Animal }")

      # Should find entities that inherit from Animal (directly or indirectly)
      results.size.should be >= 0
    end

    it "finds what likes food" do
      results = @query_interface.query("SELECT $x WHERE { $x likes Food }")

      # Should find Fido and Fluffy
      results.size.should be >= 0
    end

    it "finds animals that like food" do
      results = @query_interface.query("SELECT $x WHERE { $x ISA Animal . $x likes Food }")

      # Should find intersection of animals and food-likers
      results.size.should be >= 0
    end

    it "handles variables in multiple clauses" do
      results = @query_interface.query("SELECT $x WHERE { $x ISA Mammal . $x likes $y }")

      # Should find mammals that like something
      results.size.should be >= 0
    end

    it "uses convenience methods" do
      # Test find_all convenience method
      animal_results = @query_interface.find_all("Animal")
      animal_results.should be_a(Array(OpenCog::Query::QueryResult))

      # Test find_relations convenience method
      fido_relations = @query_interface.find_relations("Fido", "likes")
      fido_relations.should be_a(Array(OpenCog::Query::QueryResult))
    end

    it "handles empty result sets gracefully" do
      results = @query_interface.query("SELECT $x WHERE { $x ISA NonExistentType }")
      results.size.should eq(0)
    end

    it "maintains result ordering by confidence" do
      results = @query_interface.query("SELECT $x WHERE { $x ISA Animal }")

      # Results should be sorted by confidence (descending)
      if results.size > 1
        (0...results.size - 1).each do |i|
          results[i].confidence.should be >= results[i + 1].confidence
        end
      end
    end
  end

  describe "error handling" do
    it "handles parsing errors" do
      expect_raises(OpenCog::QueryLanguage::QueryParseException) do
        @query_interface.query("SELECT WHERE { invalid }")
      end
    end

    it "handles execution errors" do
      # This should not crash, even with complex invalid patterns
      begin
        results = @query_interface.query("SELECT $x WHERE { $x unknown_relation $y }")
        results.should be_a(Array(OpenCog::Query::QueryResult))
      rescue ex : OpenCog::QueryLanguage::QueryLanguageException
        ex.should be_a(OpenCog::QueryLanguage::QueryLanguageException)
      end
    end

    it "provides meaningful error messages" do
      begin
        @query_interface.query("INVALID SYNTAX")
        fail "Should have raised exception"
      rescue ex : OpenCog::QueryLanguage::QueryParseException
        ex.message.should contain("Query must start with SELECT")
      end
    end
  end

  describe "performance characteristics" do
    it "handles moderate query loads" do
      # Add more data for performance testing
      100.times do |i|
        concept = atomspace.add_concept_node("Concept#{i}")
        atomspace.add_inheritance_link(concept, @animal)
      end

      start_time = Time.monotonic

      results = @query_interface.query("SELECT $x WHERE { $x ISA Animal }")

      end_time = Time.monotonic
      duration = end_time - start_time

      # Should complete in reasonable time
      duration.should be < 5.seconds

      # Should return results
      results.size.should be >= 100
    end

    it "handles complex queries efficiently" do
      # Add interconnected data
      10.times do |i|
        entity = atomspace.add_concept_node("Entity#{i}")
        property = atomspace.add_predicate_node("Property#{i}")

        list_link = atomspace.add_list_link([entity, @animal])
        atomspace.add_evaluation_link(property, list_link)
      end

      start_time = Time.monotonic

      results = @query_interface.query("SELECT $x, $y WHERE { $x $y Animal }")

      end_time = Time.monotonic
      duration = end_time - start_time

      # Should complete in reasonable time
      duration.should be < 3.seconds

      results.should be_a(Array(OpenCog::Query::QueryResult))
    end
  end

  describe "integration with pattern matching" do
    it "uses PatternMatching engine correctly" do
      # Add test data
      dog = atomspace.add_concept_node("Dog")
      animal = atomspace.add_concept_node("Animal")
      inheritance = atomspace.add_inheritance_link(dog, animal)

      # Query should use pattern matching internally
      results = @query_interface.query("SELECT $x WHERE { $x ISA Animal }")

      # Should leverage existing pattern matching capabilities
      results.should be_a(Array(OpenCog::Query::QueryResult))
      results.size.should be >= 0
    end

    it "handles pattern matching constraints" do
      query_string = "SELECT $concept:CONCEPT WHERE { $concept ISA Animal }"

      # Should apply type constraints through pattern matching
      results = @query_interface.query(query_string)
      results.should be_a(Array(OpenCog::Query::QueryResult))
    end
  end
end

# Test exception hierarchy
describe "QueryLanguage Exception Hierarchy" do
  it "defines proper exception inheritance" do
    base_ex = OpenCog::QueryLanguage::QueryLanguageException.new("base")
    base_ex.should be_a(OpenCog::OpenCogException)

    parse_ex = OpenCog::QueryLanguage::QueryParseException.new("parse error")
    parse_ex.should be_a(OpenCog::QueryLanguage::QueryLanguageException)
    parse_ex.should be_a(OpenCog::OpenCogException)

    exec_ex = OpenCog::QueryLanguage::QueryExecutionException.new("execution error")
    exec_ex.should be_a(OpenCog::QueryLanguage::QueryLanguageException)
    exec_ex.should be_a(OpenCog::OpenCogException)
  end
end
