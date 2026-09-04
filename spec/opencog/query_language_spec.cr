require "spec"
require "../../src/opencog/query_language"

describe OpenCog::QueryLanguage do
  describe "QueryParser" do
    it "parses a simple SELECT query with a variable" do
      query = OpenCog::QueryLanguage::QueryParser.parse("SELECT $x WHERE { $x ISA Animal }")
      query.variables.size.should eq(1)
      query.variables.first.name.should eq("x")
      query.clauses.should_not be_empty
    end

    it "parses variables with type annotations" do
      query = OpenCog::QueryLanguage::QueryParser.parse("SELECT $c:Concept WHERE { $c ISA Animal }")
      query.variables.first.type.should eq(AtomSpace::AtomType::CONCEPT_NODE)
    end

    it "raises when the query does not start with SELECT" do
      expect_raises(OpenCog::QueryLanguage::QueryParseException) do
        OpenCog::QueryLanguage::QueryParser.parse("GET $x WHERE { $x }")
      end
    end

    it "raises when the WHERE clause is missing" do
      expect_raises(OpenCog::QueryLanguage::QueryParseException) do
        OpenCog::QueryLanguage::QueryParser.parse("SELECT $x")
      end
    end
  end

  describe "QueryLanguageInterface" do
    it "executes a query against an atomspace" do
      atomspace = AtomSpace::AtomSpace.new
      animal = atomspace.add_concept_node("Animal")
      dog = atomspace.add_concept_node("Dog")
      atomspace.add_inheritance_link(dog, animal)

      interface = OpenCog::QueryLanguage.create_interface(atomspace)
      results = interface.query("SELECT $x WHERE { $x ISA Animal }")
      results.should be_a(Array(OpenCog::Query::QueryResult))
    end
  end

  describe "module helpers" do
    it "parses via the module-level helper" do
      parsed = OpenCog::QueryLanguage.parse_query("SELECT $x WHERE { $x ISA Animal }")
      parsed.variables.first.name.should eq("x")
    end
  end
end
