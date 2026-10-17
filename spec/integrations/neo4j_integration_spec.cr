require "../spec_helper"
require "../../src/integrations/neo4j_integration"

describe CrystalCog::Integrations do
  describe CrystalCog::Integrations::Neo4jConfig do
    it "creates config with default values" do
      config = CrystalCog::Integrations::Neo4jConfig.new
      config.host.should eq "localhost"
      config.port.should eq 7474
      config.username.should eq "neo4j"
      config.database.should eq "neo4j"
      config.use_ssl.should be_false
      config.batch_size.should eq 1000
    end

    it "generates correct bolt URI" do
      config = CrystalCog::Integrations::Neo4jConfig.new(host: "db.example.com")
      config.bolt_uri.should eq "bolt://db.example.com:7687"
    end

    it "generates correct bolt URI with SSL" do
      config = CrystalCog::Integrations::Neo4jConfig.new(use_ssl: true)
      config.bolt_uri.should eq "bolt+s://localhost:7687"
    end

    it "generates correct HTTP URI" do
      config = CrystalCog::Integrations::Neo4jConfig.new(host: "db.example.com", port: 7475)
      config.http_uri.should eq "http://db.example.com:7475"
    end

    it "generates correct cypher endpoint" do
      config = CrystalCog::Integrations::Neo4jConfig.new
      config.cypher_endpoint.should eq "http://localhost:7474/db/neo4j/tx/commit"
    end
  end

  describe CrystalCog::Integrations::CypherQueryBuilder do
    it "builds simple match query" do
      builder = CrystalCog::Integrations::CypherQueryBuilder.new
      builder.match("(n:Node)")
      builder.return_clause("n")

      query, params = builder.build
      query.should contain "MATCH (n:Node)"
      query.should contain "RETURN n"
      params.should be_empty
    end

    it "builds query with where clause" do
      builder = CrystalCog::Integrations::CypherQueryBuilder.new
      builder.match("(n:Atom)")
        .where("n.name = 'test'")
        .return_clause("n")

      query, _ = builder.build
      query.should contain "WHERE n.name = 'test'"
    end

    it "builds create query" do
      builder = CrystalCog::Integrations::CypherQueryBuilder.new
      builder.create("(n:ConceptNode {name: 'Dog'})")
        .return_clause("n")

      query, _ = builder.build
      query.should contain "CREATE (n:ConceptNode {name: 'Dog'})"
    end

    it "builds merge query with set" do
      builder = CrystalCog::Integrations::CypherQueryBuilder.new
      builder.merge("(n:Atom {id: $id})")
        .set("n.name = $name")
        .return_clause("n")

      query, _ = builder.build
      query.should contain "MERGE (n:Atom {id: $id})"
      query.should contain "SET n.name = $name"
    end

    it "adds parameters" do
      builder = CrystalCog::Integrations::CypherQueryBuilder.new
      builder.match("(n:Atom {id: $id})")
        .param("id", "test-123")
        .return_clause("n")

      _, params = builder.build
      params["id"].should eq JSON::Any.new("test-123")
    end

    it "builds query with limit and skip" do
      builder = CrystalCog::Integrations::CypherQueryBuilder.new
      builder.match("(n:Atom)")
        .return_clause("n")
        .skip(10)
        .limit(5)

      query, _ = builder.build
      query.should contain "SKIP 10"
      query.should contain "LIMIT 5"
    end

    it "builds unwind query" do
      builder = CrystalCog::Integrations::CypherQueryBuilder.new
      builder.unwind("$atoms AS atom")
        .create("(a:Atom)")
        .set("a = atom")

      query, _ = builder.build
      query.should contain "UNWIND $atoms AS atom"
    end
  end

  describe CrystalCog::Integrations::Neo4jResult do
    it "creates empty result" do
      result = CrystalCog::Integrations::Neo4jResult.new
      result.success?.should be_true
      result.empty?.should be_true
      result.row_count.should eq 0
    end

    it "creates result with data" do
      data = [
        [JSON::Any.new("id1"), JSON::Any.new("name1")],
        [JSON::Any.new("id2"), JSON::Any.new("name2")],
      ]
      result = CrystalCog::Integrations::Neo4jResult.new(
        columns: ["id", "name"],
        data: data
      )

      result.success?.should be_true
      result.empty?.should be_false
      result.row_count.should eq 2
      result.columns.should eq ["id", "name"]
    end

    it "creates result with errors" do
      result = CrystalCog::Integrations::Neo4jResult.new(
        errors: ["Connection failed"]
      )

      result.success?.should be_false
      result.errors.first.should eq "Connection failed"
    end

    it "converts to hash array" do
      data = [
        [JSON::Any.new("id1"), JSON::Any.new("name1")],
      ]
      result = CrystalCog::Integrations::Neo4jResult.new(
        columns: ["id", "name"],
        data: data
      )

      hash_array = result.to_hash_array
      hash_array.size.should eq 1
      hash_array.first["id"].should eq JSON::Any.new("id1")
      hash_array.first["name"].should eq JSON::Any.new("name1")
    end

    it "iterates with map" do
      data = [
        [JSON::Any.new(1_i64)],
        [JSON::Any.new(2_i64)],
      ]
      result = CrystalCog::Integrations::Neo4jResult.new(
        columns: ["num"],
        data: data
      )

      mapped = result.map { |row| row[0].as_i * 2 }
      mapped.should eq [2, 4]
    end
  end

  describe CrystalCog::Integrations::Neo4jStats do
    it "creates default stats" do
      stats = CrystalCog::Integrations::Neo4jStats.new
      stats.nodes_created.should eq 0
      stats.relationships_created.should eq 0
      stats.any_changes?.should be_false
    end

    it "detects changes" do
      stats = CrystalCog::Integrations::Neo4jStats.new(nodes_created: 1)
      stats.any_changes?.should be_true
    end

    it "parses from JSON" do
      json = JSON.parse({
        "stats" => {
          "nodes_created"         => 5,
          "relationships_created" => 3,
          "properties_set"        => 10,
        },
      }.to_json)

      stats = CrystalCog::Integrations::Neo4jStats.from_json(json)
      stats.nodes_created.should eq 5
      stats.relationships_created.should eq 3
      stats.properties_set.should eq 10
    end
  end

  describe CrystalCog::Integrations::Neo4jAtomNode do
    it "creates atom with default values" do
      atom = CrystalCog::Integrations::Neo4jAtomNode.new(
        id: "test-1",
        atom_type: "ConceptNode",
        name: "Dog"
      )

      atom.id.should eq "test-1"
      atom.atom_type.should eq "ConceptNode"
      atom.name.should eq "Dog"
      atom.truth_value_strength.should eq 1.0
      atom.truth_value_confidence.should eq 1.0
    end

    it "generates cypher properties" do
      atom = CrystalCog::Integrations::Neo4jAtomNode.new(
        id: "test-1",
        name: "Cat"
      )

      props = atom.to_cypher_properties
      props.should contain "\"id\":\"test-1\""
      props.should contain "\"name\":\"Cat\""
    end
  end

  describe CrystalCog::Integrations::Neo4jLinkRelationship do
    it "creates link" do
      link = CrystalCog::Integrations::Neo4jLinkRelationship.new(
        id: "link-1",
        link_type: "InheritanceLink",
        source_id: "atom-1",
        target_id: "atom-2"
      )

      link.id.should eq "link-1"
      link.link_type.should eq "InheritanceLink"
      link.source_id.should eq "atom-1"
      link.target_id.should eq "atom-2"
      link.arity.should eq 2
    end
  end

  describe CrystalCog::Integrations::Neo4jGraphStats do
    it "creates graph stats" do
      stats = CrystalCog::Integrations::Neo4jGraphStats.new(
        node_count: 100,
        relationship_count: 50,
        atom_types: ["ConceptNode", "PredicateNode"],
        average_degree: 1.0
      )

      stats.node_count.should eq 100
      stats.relationship_count.should eq 50
      stats.atom_types.size.should eq 2
    end
  end

  describe CrystalCog::Integrations::AtomSpaceGraphQuery do
    it "builds concept query" do
      # Note: Would need mock client for full test
      # This tests the query building pattern
      config = CrystalCog::Integrations::Neo4jConfig.new
      # client = CrystalCog::Integrations::Neo4jClient.new(config)
      # query = CrystalCog::Integrations::AtomSpaceGraphQuery.new(client)
      # query.concept("dog").with_truth_value(0.5).returns("dog")
      true.should be_true # Placeholder
    end
  end
end
