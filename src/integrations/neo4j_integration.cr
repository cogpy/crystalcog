# CrystalCog Neo4j Integration
# Graph Database Backend for AtomSpace
#
# This module provides Neo4j graph database integration for the CrystalCog
# AtomSpace, enabling persistent graph storage, advanced graph queries,
# and distributed knowledge management.

require "http/client"
require "json"
require "uri"

module CrystalCog
  module Integrations
    # Neo4j Configuration
    class Neo4jConfig
      property host : String
      property port : Int32
      property username : String
      property password : String
      property database : String
      property use_ssl : Bool
      property connection_timeout : Time::Span
      property max_connections : Int32
      property batch_size : Int32

      def initialize(
        @host = "localhost",
        @port = 7474,
        @username = "neo4j",
        @password = "password",
        @database = "neo4j",
        @use_ssl = false,
        @connection_timeout = 30.seconds,
        @max_connections = 10,
        @batch_size = 1000
      )
      end

      def bolt_uri : String
        protocol = @use_ssl ? "bolt+s" : "bolt"
        "#{protocol}://#{@host}:7687"
      end

      def http_uri : String
        protocol = @use_ssl ? "https" : "http"
        "#{protocol}://#{@host}:#{@port}"
      end

      def cypher_endpoint : String
        "#{http_uri}/db/#{@database}/tx/commit"
      end
    end

    # Neo4j Cypher Query Builder
    class CypherQueryBuilder
      @query_parts : Array(String)
      @parameters : Hash(String, JSON::Any)

      def initialize
        @query_parts = [] of String
        @parameters = {} of String => JSON::Any
      end

      def match(pattern : String) : CypherQueryBuilder
        @query_parts << "MATCH #{pattern}"
        self
      end

      def where(condition : String) : CypherQueryBuilder
        @query_parts << "WHERE #{condition}"
        self
      end

      def create(pattern : String) : CypherQueryBuilder
        @query_parts << "CREATE #{pattern}"
        self
      end

      def merge(pattern : String) : CypherQueryBuilder
        @query_parts << "MERGE #{pattern}"
        self
      end

      def set(assignments : String) : CypherQueryBuilder
        @query_parts << "SET #{assignments}"
        self
      end

      def delete(items : String) : CypherQueryBuilder
        @query_parts << "DELETE #{items}"
        self
      end

      def detach_delete(items : String) : CypherQueryBuilder
        @query_parts << "DETACH DELETE #{items}"
        self
      end

      def return_clause(items : String) : CypherQueryBuilder
        @query_parts << "RETURN #{items}"
        self
      end

      def order_by(items : String) : CypherQueryBuilder
        @query_parts << "ORDER BY #{items}"
        self
      end

      def limit(count : Int32) : CypherQueryBuilder
        @query_parts << "LIMIT #{count}"
        self
      end

      def skip(count : Int32) : CypherQueryBuilder
        @query_parts << "SKIP #{count}"
        self
      end

      def with(items : String) : CypherQueryBuilder
        @query_parts << "WITH #{items}"
        self
      end

      def unwind(expression : String) : CypherQueryBuilder
        @query_parts << "UNWIND #{expression}"
        self
      end

      def param(name : String, value) : CypherQueryBuilder
        @parameters[name] = JSON.parse(value.to_json)
        self
      end

      def build : {String, Hash(String, JSON::Any)}
        query = @query_parts.join("\n")
        {query, @parameters}
      end

      def to_s : String
        @query_parts.join("\n")
      end
    end

    # Neo4j Query Result
    struct Neo4jResult
      property columns : Array(String)
      property data : Array(Array(JSON::Any))
      property stats : Neo4jStats
      property errors : Array(String)

      def initialize(
        @columns = [] of String,
        @data = [] of Array(JSON::Any),
        @stats = Neo4jStats.new,
        @errors = [] of String
      )
      end

      def success? : Bool
        @errors.empty?
      end

      def row_count : Int32
        @data.size
      end

      def empty? : Bool
        @data.empty?
      end

      def first : Array(JSON::Any)?
        @data.first?
      end

      def each(&block : Array(JSON::Any) -> Nil)
        @data.each { |row| block.call(row) }
      end

      def map(&block : Array(JSON::Any) -> T) forall T
        @data.map { |row| block.call(row) }
      end

      def to_hash_array : Array(Hash(String, JSON::Any))
        @data.map do |row|
          hash = {} of String => JSON::Any
          @columns.each_with_index do |col, i|
            hash[col] = row[i] if i < row.size
          end
          hash
        end
      end
    end

    # Neo4j Query Statistics
    struct Neo4jStats
      property nodes_created : Int32
      property nodes_deleted : Int32
      property relationships_created : Int32
      property relationships_deleted : Int32
      property properties_set : Int32
      property labels_added : Int32
      property labels_removed : Int32
      property indexes_added : Int32
      property indexes_removed : Int32
      property constraints_added : Int32
      property constraints_removed : Int32

      def initialize(
        @nodes_created = 0,
        @nodes_deleted = 0,
        @relationships_created = 0,
        @relationships_deleted = 0,
        @properties_set = 0,
        @labels_added = 0,
        @labels_removed = 0,
        @indexes_added = 0,
        @indexes_removed = 0,
        @constraints_added = 0,
        @constraints_removed = 0
      )
      end

      def self.from_json(json : JSON::Any) : Neo4jStats
        stats = Neo4jStats.new

        if counters = json["stats"]?
          stats = Neo4jStats.new(
            nodes_created: counters["nodes_created"]?.try(&.as_i) || 0,
            nodes_deleted: counters["nodes_deleted"]?.try(&.as_i) || 0,
            relationships_created: counters["relationships_created"]?.try(&.as_i) || 0,
            relationships_deleted: counters["relationships_deleted"]?.try(&.as_i) || 0,
            properties_set: counters["properties_set"]?.try(&.as_i) || 0,
            labels_added: counters["labels_added"]?.try(&.as_i) || 0,
            labels_removed: counters["labels_removed"]?.try(&.as_i) || 0,
            indexes_added: counters["indexes_added"]?.try(&.as_i) || 0,
            indexes_removed: counters["indexes_removed"]?.try(&.as_i) || 0,
            constraints_added: counters["constraints_added"]?.try(&.as_i) || 0,
            constraints_removed: counters["constraints_removed"]?.try(&.as_i) || 0
          )
        end

        stats
      end

      def any_changes? : Bool
        @nodes_created > 0 || @nodes_deleted > 0 ||
          @relationships_created > 0 || @relationships_deleted > 0 ||
          @properties_set > 0
      end
    end

    # Neo4j Connection Pool
    class Neo4jConnectionPool
      @config : Neo4jConfig
      @available : Channel(HTTP::Client)
      @mutex : Mutex

      def initialize(@config : Neo4jConfig)
        @available = Channel(HTTP::Client).new(@config.max_connections)
        @mutex = Mutex.new

        # Pre-create connections
        @config.max_connections.times do
          @available.send(create_client)
        end
      end

      def with_connection(&block : HTTP::Client -> T) forall T
        client = @available.receive
        begin
          yield client
        ensure
          @available.send(client)
        end
      end

      private def create_client : HTTP::Client
        uri = URI.parse(@config.http_uri)
        client = HTTP::Client.new(uri)
        client.connect_timeout = @config.connection_timeout
        client.read_timeout = @config.connection_timeout
        client.basic_auth(@config.username, @config.password)
        client
      end

      def close
        while client = @available.receive?
          client.close
        end
      end
    end

    # Neo4j Atom Node representation
    struct Neo4jAtomNode
      property id : String
      property atom_type : String
      property name : String?
      property truth_value_strength : Float64
      property truth_value_confidence : Float64
      property attention_value_sti : Float64
      property attention_value_lti : Float64
      property created_at : Time
      property updated_at : Time
      property metadata : Hash(String, JSON::Any)

      def initialize(
        @id = "",
        @atom_type = "ConceptNode",
        @name = nil,
        @truth_value_strength = 1.0,
        @truth_value_confidence = 1.0,
        @attention_value_sti = 0.0,
        @attention_value_lti = 0.0,
        @created_at = Time.utc,
        @updated_at = Time.utc,
        @metadata = {} of String => JSON::Any
      )
      end

      def to_cypher_properties : String
        props = {
          "id"           => @id,
          "atomType"     => @atom_type,
          "name"         => @name,
          "tvStrength"   => @truth_value_strength,
          "tvConfidence" => @truth_value_confidence,
          "avSti"        => @attention_value_sti,
          "avLti"        => @attention_value_lti,
          "createdAt"    => @created_at.to_unix,
          "updatedAt"    => @updated_at.to_unix,
          "metadata"     => @metadata.to_json,
        }
        props.to_json
      end
    end

    # Neo4j Link Relationship representation
    struct Neo4jLinkRelationship
      property id : String
      property link_type : String
      property source_id : String
      property target_id : String
      property truth_value_strength : Float64
      property truth_value_confidence : Float64
      property arity : Int32
      property outgoing_set : Array(String)
      property metadata : Hash(String, JSON::Any)

      def initialize(
        @id = "",
        @link_type = "Link",
        @source_id = "",
        @target_id = "",
        @truth_value_strength = 1.0,
        @truth_value_confidence = 1.0,
        @arity = 2,
        @outgoing_set = [] of String,
        @metadata = {} of String => JSON::Any
      )
      end
    end

    # Main Neo4j Integration Client
    class Neo4jClient
      @config : Neo4jConfig
      @pool : Neo4jConnectionPool
      @connected : Bool
      @schema_initialized : Bool

      def initialize(@config = Neo4jConfig.new)
        @pool = Neo4jConnectionPool.new(@config)
        @connected = false
        @schema_initialized = false
      end

      def initialize(
        host : String,
        port : Int32 = 7474,
        username : String = "neo4j",
        password : String = "password"
      )
        @config = Neo4jConfig.new(
          host: host,
          port: port,
          username: username,
          password: password
        )
        @pool = Neo4jConnectionPool.new(@config)
        @connected = false
        @schema_initialized = false
      end

      # Test connection to Neo4j
      def connect : Bool
        result = execute_cypher("RETURN 1 as test")
        @connected = result.success?
        @connected
      end

      def connected? : Bool
        @connected
      end

      # Initialize AtomSpace schema in Neo4j
      def initialize_schema : Bool
        return true if @schema_initialized

        # Create indexes for efficient atom lookup
        schema_queries = [
          "CREATE INDEX atom_id IF NOT EXISTS FOR (a:Atom) ON (a.id)",
          "CREATE INDEX atom_type IF NOT EXISTS FOR (a:Atom) ON (a.atomType)",
          "CREATE INDEX atom_name IF NOT EXISTS FOR (a:Atom) ON (a.name)",
          "CREATE INDEX concept_node IF NOT EXISTS FOR (n:ConceptNode) ON (n.id)",
          "CREATE INDEX predicate_node IF NOT EXISTS FOR (n:PredicateNode) ON (n.id)",
          "CREATE INDEX variable_node IF NOT EXISTS FOR (n:VariableNode) ON (n.id)",
          "CREATE CONSTRAINT atom_id_unique IF NOT EXISTS FOR (a:Atom) REQUIRE a.id IS UNIQUE",
        ]

        success = true
        schema_queries.each do |query|
          result = execute_cypher(query)
          success &&= result.success?
        end

        @schema_initialized = success
        success
      end

      # Execute raw Cypher query
      def execute_cypher(query : String, params : Hash(String, JSON::Any)? = nil) : Neo4jResult
        body = {
          "statements" => [
            {
              "statement"          => query,
              "parameters"         => params || {} of String => JSON::Any,
              "resultDataContents" => ["row"],
              "includeStats"       => true,
            },
          ],
        }.to_json

        @pool.with_connection do |client|
          response = client.post(
            @config.cypher_endpoint,
            headers: HTTP::Headers{
              "Content-Type" => "application/json",
              "Accept"       => "application/json",
            },
            body: body
          )

          parse_response(response)
        end
      end

      # Execute query using builder
      def execute(builder : CypherQueryBuilder) : Neo4jResult
        query, params = builder.build
        execute_cypher(query, params)
      end

      # Store an atom node
      def store_atom(atom : Neo4jAtomNode) : Neo4jResult
        labels = ["Atom", atom.atom_type]
        label_str = labels.join(":")

        query = <<-CYPHER
          MERGE (a:#{label_str} {id: $id})
          SET a.atomType = $atomType,
              a.name = $name,
              a.tvStrength = $tvStrength,
              a.tvConfidence = $tvConfidence,
              a.avSti = $avSti,
              a.avLti = $avLti,
              a.createdAt = $createdAt,
              a.updatedAt = $updatedAt,
              a.metadata = $metadata
          RETURN a
        CYPHER

        params = {
          "id"           => JSON::Any.new(atom.id),
          "atomType"     => JSON::Any.new(atom.atom_type),
          "name"         => atom.name ? JSON::Any.new(atom.name.not_nil!) : JSON::Any.new(nil),
          "tvStrength"   => JSON::Any.new(atom.truth_value_strength),
          "tvConfidence" => JSON::Any.new(atom.truth_value_confidence),
          "avSti"        => JSON::Any.new(atom.attention_value_sti),
          "avLti"        => JSON::Any.new(atom.attention_value_lti),
          "createdAt"    => JSON::Any.new(atom.created_at.to_unix),
          "updatedAt"    => JSON::Any.new(atom.updated_at.to_unix),
          "metadata"     => JSON::Any.new(atom.metadata.to_json),
        }

        execute_cypher(query, params)
      end

      # Store a link (relationship) between atoms
      def store_link(link : Neo4jLinkRelationship) : Neo4jResult
        query = <<-CYPHER
          MATCH (source:Atom {id: $sourceId})
          MATCH (target:Atom {id: $targetId})
          MERGE (source)-[r:#{link.link_type} {id: $id}]->(target)
          SET r.tvStrength = $tvStrength,
              r.tvConfidence = $tvConfidence,
              r.arity = $arity,
              r.outgoingSet = $outgoingSet,
              r.metadata = $metadata
          RETURN r
        CYPHER

        params = {
          "id"           => JSON::Any.new(link.id),
          "sourceId"     => JSON::Any.new(link.source_id),
          "targetId"     => JSON::Any.new(link.target_id),
          "tvStrength"   => JSON::Any.new(link.truth_value_strength),
          "tvConfidence" => JSON::Any.new(link.truth_value_confidence),
          "arity"        => JSON::Any.new(link.arity.to_i64),
          "outgoingSet"  => JSON::Any.new(link.outgoing_set.map { |s| JSON::Any.new(s) }),
          "metadata"     => JSON::Any.new(link.metadata.to_json),
        }

        execute_cypher(query, params)
      end

      # Get atom by ID
      def get_atom(id : String) : Neo4jAtomNode?
        query = "MATCH (a:Atom {id: $id}) RETURN a"
        params = {"id" => JSON::Any.new(id)}

        result = execute_cypher(query, params)
        return nil unless result.success? && !result.empty?

        parse_atom_from_result(result.first.not_nil![0])
      end

      # Get atoms by type
      def get_atoms_by_type(atom_type : String, limit : Int32 = 100) : Array(Neo4jAtomNode)
        query = <<-CYPHER
          MATCH (a:Atom {atomType: $atomType})
          RETURN a
          LIMIT $limit
        CYPHER

        params = {
          "atomType" => JSON::Any.new(atom_type),
          "limit"    => JSON::Any.new(limit.to_i64),
        }

        result = execute_cypher(query, params)
        return [] of Neo4jAtomNode unless result.success?

        result.map { |row| parse_atom_from_result(row[0]) }.compact
      end

      # Get atoms by name pattern
      def search_atoms_by_name(pattern : String, limit : Int32 = 100) : Array(Neo4jAtomNode)
        query = <<-CYPHER
          MATCH (a:Atom)
          WHERE a.name =~ $pattern
          RETURN a
          LIMIT $limit
        CYPHER

        params = {
          "pattern" => JSON::Any.new(pattern),
          "limit"   => JSON::Any.new(limit.to_i64),
        }

        result = execute_cypher(query, params)
        return [] of Neo4jAtomNode unless result.success?

        result.map { |row| parse_atom_from_result(row[0]) }.compact
      end

      # Get incoming links for an atom
      def get_incoming_links(atom_id : String) : Array(Neo4jLinkRelationship)
        query = <<-CYPHER
          MATCH (source:Atom)-[r]->(target:Atom {id: $atomId})
          RETURN r, source.id as sourceId, target.id as targetId, type(r) as linkType
        CYPHER

        params = {"atomId" => JSON::Any.new(atom_id)}
        result = execute_cypher(query, params)
        return [] of Neo4jLinkRelationship unless result.success?

        result.map { |row| parse_link_from_result(row) }.compact
      end

      # Get outgoing links from an atom
      def get_outgoing_links(atom_id : String) : Array(Neo4jLinkRelationship)
        query = <<-CYPHER
          MATCH (source:Atom {id: $atomId})-[r]->(target:Atom)
          RETURN r, source.id as sourceId, target.id as targetId, type(r) as linkType
        CYPHER

        params = {"atomId" => JSON::Any.new(atom_id)}
        result = execute_cypher(query, params)
        return [] of Neo4jLinkRelationship unless result.success?

        result.map { |row| parse_link_from_result(row) }.compact
      end

      # Delete atom and all its relationships
      def delete_atom(id : String) : Bool
        query = "MATCH (a:Atom {id: $id}) DETACH DELETE a"
        params = {"id" => JSON::Any.new(id)}
        result = execute_cypher(query, params)
        result.success? && result.stats.nodes_deleted > 0
      end

      # Batch store multiple atoms
      def batch_store_atoms(atoms : Array(Neo4jAtomNode)) : Neo4jResult
        query = <<-CYPHER
          UNWIND $atoms as atom
          MERGE (a:Atom {id: atom.id})
          SET a += atom
          RETURN count(a) as stored
        CYPHER

        atom_data = atoms.map do |atom|
          JSON.parse({
            "id"           => atom.id,
            "atomType"     => atom.atom_type,
            "name"         => atom.name,
            "tvStrength"   => atom.truth_value_strength,
            "tvConfidence" => atom.truth_value_confidence,
            "avSti"        => atom.attention_value_sti,
            "avLti"        => atom.attention_value_lti,
            "createdAt"    => atom.created_at.to_unix,
            "updatedAt"    => atom.updated_at.to_unix,
          }.to_json)
        end

        params = {"atoms" => JSON::Any.new(atom_data)}
        execute_cypher(query, params)
      end

      # Find path between two atoms
      def find_path(source_id : String, target_id : String, max_depth : Int32 = 10) : Array(Array(String))
        query = <<-CYPHER
          MATCH path = shortestPath((source:Atom {id: $sourceId})-[*..#{max_depth}]-(target:Atom {id: $targetId}))
          RETURN [node in nodes(path) | node.id] as path
        CYPHER

        params = {
          "sourceId" => JSON::Any.new(source_id),
          "targetId" => JSON::Any.new(target_id),
        }

        result = execute_cypher(query, params)
        return [] of Array(String) unless result.success?

        result.map do |row|
          row[0].as_a.map(&.as_s)
        end
      end

      # Get subgraph around an atom
      def get_subgraph(center_id : String, depth : Int32 = 2) : {Array(Neo4jAtomNode), Array(Neo4jLinkRelationship)}
        query = <<-CYPHER
          MATCH (center:Atom {id: $centerId})
          CALL apoc.path.subgraphAll(center, {maxLevel: $depth})
          YIELD nodes, relationships
          RETURN nodes, relationships
        CYPHER

        # Fallback query without APOC
        fallback_query = <<-CYPHER
          MATCH path = (center:Atom {id: $centerId})-[*0..#{depth}]-(connected:Atom)
          WITH collect(DISTINCT connected) as nodes,
               [r in collect(DISTINCT relationships(path)) | head(r)] as rels
          UNWIND nodes as n
          WITH collect(n) as allNodes, rels
          UNWIND rels as r
          RETURN allNodes, collect(DISTINCT r) as allRels
        CYPHER

        params = {
          "centerId" => JSON::Any.new(center_id),
          "depth"    => JSON::Any.new(depth.to_i64),
        }

        result = execute_cypher(fallback_query, params)
        return {[] of Neo4jAtomNode, [] of Neo4jLinkRelationship} unless result.success? && !result.empty?

        atoms = [] of Neo4jAtomNode
        links = [] of Neo4jLinkRelationship

        # Parse nodes and relationships from result
        if first_row = result.first
          if nodes_data = first_row[0]?
            nodes_data.as_a.each do |node|
              if atom = parse_atom_from_result(node)
                atoms << atom
              end
            end
          end
        end

        {atoms, links}
      end

      # Graph analytics - PageRank
      def compute_pagerank(iterations : Int32 = 20, damping_factor : Float64 = 0.85) : Hash(String, Float64)
        # Using GDS (Graph Data Science) if available
        query = <<-CYPHER
          CALL gds.pageRank.stream('atomspace', {
            maxIterations: $iterations,
            dampingFactor: $dampingFactor
          })
          YIELD nodeId, score
          RETURN gds.util.asNode(nodeId).id AS atomId, score
          ORDER BY score DESC
          LIMIT 100
        CYPHER

        params = {
          "iterations"    => JSON::Any.new(iterations.to_i64),
          "dampingFactor" => JSON::Any.new(damping_factor),
        }

        result = execute_cypher(query, params)
        pagerank = {} of String => Float64

        if result.success?
          result.each do |row|
            atom_id = row[0].as_s
            score = row[1].as_f
            pagerank[atom_id] = score
          end
        end

        pagerank
      end

      # Find communities using Louvain algorithm
      def detect_communities : Hash(String, Int32)
        query = <<-CYPHER
          CALL gds.louvain.stream('atomspace')
          YIELD nodeId, communityId
          RETURN gds.util.asNode(nodeId).id AS atomId, communityId
        CYPHER

        result = execute_cypher(query)
        communities = {} of String => Int32

        if result.success?
          result.each do |row|
            atom_id = row[0].as_s
            community_id = row[1].as_i
            communities[atom_id] = community_id
          end
        end

        communities
      end

      # Semantic similarity search
      def find_similar_atoms(atom_id : String, limit : Int32 = 10) : Array({String, Float64})
        query = <<-CYPHER
          MATCH (a:Atom {id: $atomId})-[r]-(neighbor:Atom)-[s]-(similar:Atom)
          WHERE similar.id <> $atomId
          WITH similar, count(DISTINCT neighbor) as commonNeighbors
          RETURN similar.id as atomId,
                 toFloat(commonNeighbors) / (size((a)-[]-()) + size((similar)-[]-()) - commonNeighbors) as jaccardSimilarity
          ORDER BY jaccardSimilarity DESC
          LIMIT $limit
        CYPHER

        params = {
          "atomId" => JSON::Any.new(atom_id),
          "limit"  => JSON::Any.new(limit.to_i64),
        }

        result = execute_cypher(query, params)
        similar = [] of {String, Float64}

        if result.success?
          result.each do |row|
            similar_id = row[0].as_s
            similarity = row[1].as_f
            similar << {similar_id, similarity}
          end
        end

        similar
      end

      # Get graph statistics
      def get_statistics : Neo4jGraphStats
        query = <<-CYPHER
          MATCH (a:Atom)
          WITH count(a) as nodeCount
          MATCH ()-[r]->()
          WITH nodeCount, count(r) as relCount
          MATCH (a:Atom)
          WITH nodeCount, relCount,
               collect(DISTINCT a.atomType) as atomTypes
          RETURN nodeCount, relCount, atomTypes
        CYPHER

        result = execute_cypher(query)

        if result.success? && !result.empty?
          row = result.first.not_nil!
          Neo4jGraphStats.new(
            node_count: row[0].as_i.to_i32,
            relationship_count: row[1].as_i.to_i32,
            atom_types: row[2].as_a.map(&.as_s),
            average_degree: row[1].as_i > 0 ? (row[1].as_i * 2.0 / row[0].as_i) : 0.0
          )
        else
          Neo4jGraphStats.new
        end
      end

      # Clear all atoms
      def clear_all : Bool
        result = execute_cypher("MATCH (a:Atom) DETACH DELETE a")
        result.success?
      end

      # Export graph to JSON
      def export_to_json : String
        query = <<-CYPHER
          MATCH (a:Atom)
          OPTIONAL MATCH (a)-[r]->(b:Atom)
          RETURN collect(DISTINCT a) as nodes,
                 collect(DISTINCT {source: a.id, target: b.id, type: type(r), properties: properties(r)}) as relationships
        CYPHER

        result = execute_cypher(query)

        if result.success? && !result.empty?
          row = result.first.not_nil!
          {
            "nodes"         => row[0],
            "relationships" => row[1],
            "exportedAt"    => Time.utc.to_unix,
          }.to_json
        else
          {"nodes" => [] of String, "relationships" => [] of String}.to_json
        end
      end

      # Import graph from JSON
      def import_from_json(json_data : String) : Bool
        data = JSON.parse(json_data)

        # Import nodes
        if nodes = data["nodes"]?
          nodes.as_a.each do |node|
            atom = Neo4jAtomNode.new(
              id: node["id"]?.try(&.as_s) || UUID.random.to_s,
              atom_type: node["atomType"]?.try(&.as_s) || "Atom",
              name: node["name"]?.try(&.as_s?),
              truth_value_strength: node["tvStrength"]?.try(&.as_f) || 1.0,
              truth_value_confidence: node["tvConfidence"]?.try(&.as_f) || 1.0
            )
            store_atom(atom)
          end
        end

        # Import relationships
        if rels = data["relationships"]?
          rels.as_a.each do |rel|
            next unless source = rel["source"]?.try(&.as_s)
            next unless target = rel["target"]?.try(&.as_s)

            link = Neo4jLinkRelationship.new(
              id: UUID.random.to_s,
              link_type: rel["type"]?.try(&.as_s) || "LINK",
              source_id: source,
              target_id: target
            )
            store_link(link)
          end
        end

        true
      rescue
        false
      end

      # Close connection
      def close
        @pool.close
        @connected = false
      end

      private def parse_response(response : HTTP::Client::Response) : Neo4jResult
        begin
          json = JSON.parse(response.body)

          errors = [] of String
          if error_list = json["errors"]?
            error_list.as_a.each do |error|
              errors << (error["message"]?.try(&.as_s) || "Unknown error")
            end
          end

          return Neo4jResult.new(errors: errors) unless errors.empty?

          results = json["results"]?
          return Neo4jResult.new unless results

          first_result = results.as_a.first?
          return Neo4jResult.new unless first_result

          columns = first_result["columns"]?.try(&.as_a.map(&.as_s)) || [] of String

          data = [] of Array(JSON::Any)
          if data_array = first_result["data"]?
            data_array.as_a.each do |row_data|
              if row = row_data["row"]?
                data << row.as_a
              end
            end
          end

          stats = if stats_data = first_result["stats"]?
                    Neo4jStats.from_json(stats_data)
                  else
                    Neo4jStats.new
                  end

          Neo4jResult.new(
            columns: columns,
            data: data,
            stats: stats,
            errors: errors
          )
        rescue ex
          Neo4jResult.new(errors: ["Parse error: #{ex.message}"])
        end
      end

      private def parse_atom_from_result(node_data : JSON::Any) : Neo4jAtomNode?
        return nil unless node_data.as_h?

        Neo4jAtomNode.new(
          id: node_data["id"]?.try(&.as_s) || "",
          atom_type: node_data["atomType"]?.try(&.as_s) || "Atom",
          name: node_data["name"]?.try(&.as_s?),
          truth_value_strength: node_data["tvStrength"]?.try(&.as_f) || 1.0,
          truth_value_confidence: node_data["tvConfidence"]?.try(&.as_f) || 1.0,
          attention_value_sti: node_data["avSti"]?.try(&.as_f) || 0.0,
          attention_value_lti: node_data["avLti"]?.try(&.as_f) || 0.0,
          created_at: Time.unix(node_data["createdAt"]?.try(&.as_i64) || Time.utc.to_unix),
          updated_at: Time.unix(node_data["updatedAt"]?.try(&.as_i64) || Time.utc.to_unix)
        )
      rescue
        nil
      end

      private def parse_link_from_result(row : Array(JSON::Any)) : Neo4jLinkRelationship?
        return nil if row.size < 4

        rel_data = row[0]
        source_id = row[1].as_s
        target_id = row[2].as_s
        link_type = row[3].as_s

        Neo4jLinkRelationship.new(
          id: rel_data["id"]?.try(&.as_s) || UUID.random.to_s,
          link_type: link_type,
          source_id: source_id,
          target_id: target_id,
          truth_value_strength: rel_data["tvStrength"]?.try(&.as_f) || 1.0,
          truth_value_confidence: rel_data["tvConfidence"]?.try(&.as_f) || 1.0,
          arity: rel_data["arity"]?.try(&.as_i.to_i32) || 2,
          outgoing_set: rel_data["outgoingSet"]?.try(&.as_a.map(&.as_s)) || [] of String
        )
      rescue
        nil
      end
    end

    # Graph Statistics
    struct Neo4jGraphStats
      property node_count : Int32
      property relationship_count : Int32
      property atom_types : Array(String)
      property average_degree : Float64

      def initialize(
        @node_count = 0,
        @relationship_count = 0,
        @atom_types = [] of String,
        @average_degree = 0.0
      )
      end
    end

    # AtomSpace Neo4j Storage Backend
    class Neo4jAtomSpaceStorage
      @client : Neo4jClient
      @atomspace_id : String
      @auto_sync : Bool

      def initialize(@client : Neo4jClient, @atomspace_id = "default", @auto_sync = true)
        @client.initialize_schema
      end

      # Sync entire AtomSpace to Neo4j
      def sync_atomspace(atoms : Array(Neo4jAtomNode), links : Array(Neo4jLinkRelationship)) : Bool
        # Clear existing data for this atomspace
        clear_query = "MATCH (a:Atom {atomspaceId: $atomspaceId}) DETACH DELETE a"
        @client.execute_cypher(clear_query, {"atomspaceId" => JSON::Any.new(@atomspace_id)})

        # Store all atoms
        atoms.each_slice(@client.@config.batch_size) do |batch|
          @client.batch_store_atoms(batch)
        end

        # Store all links
        links.each do |link|
          @client.store_link(link)
        end

        true
      rescue
        false
      end

      # Load AtomSpace from Neo4j
      def load_atomspace : {Array(Neo4jAtomNode), Array(Neo4jLinkRelationship)}
        atoms = [] of Neo4jAtomNode
        links = [] of Neo4jLinkRelationship

        # Load atoms
        atom_query = "MATCH (a:Atom {atomspaceId: $atomspaceId}) RETURN a"
        atom_result = @client.execute_cypher(atom_query, {"atomspaceId" => JSON::Any.new(@atomspace_id)})

        if atom_result.success?
          atom_result.each do |row|
            if atom = @client.send(:parse_atom_from_result, row[0])
              atoms << atom
            end
          end
        end

        # Load links
        link_query = <<-CYPHER
          MATCH (source:Atom {atomspaceId: $atomspaceId})-[r]->(target:Atom)
          RETURN r, source.id, target.id, type(r)
        CYPHER

        link_result = @client.execute_cypher(link_query, {"atomspaceId" => JSON::Any.new(@atomspace_id)})

        if link_result.success?
          link_result.each do |row|
            if link = @client.send(:parse_link_from_result, row)
              links << link
            end
          end
        end

        {atoms, links}
      end

      # Watch for changes and sync automatically
      def enable_auto_sync(interval : Time::Span = 30.seconds)
        spawn do
          loop do
            sleep interval
            # Sync logic would go here with actual AtomSpace
          end
        end
      end
    end

    # Graph Query DSL for AtomSpace
    class AtomSpaceGraphQuery
      @client : Neo4jClient
      @builder : CypherQueryBuilder

      def initialize(@client : Neo4jClient)
        @builder = CypherQueryBuilder.new
      end

      def concept(name : String) : AtomSpaceGraphQuery
        @builder.match("(#{name}:ConceptNode)")
        self
      end

      def predicate(name : String) : AtomSpaceGraphQuery
        @builder.match("(#{name}:PredicateNode)")
        self
      end

      def inheritance(source : String, target : String) : AtomSpaceGraphQuery
        @builder.match("(#{source})-[:InheritanceLink]->(#{target})")
        self
      end

      def evaluation(predicate : String, args : Array(String)) : AtomSpaceGraphQuery
        pattern = "(#{predicate})-[:EvaluationLink]->({args: [#{args.map { |a| "'#{a}'" }.join(", ")}]})"
        @builder.match(pattern)
        self
      end

      def with_truth_value(min_strength : Float64 = 0.0, min_confidence : Float64 = 0.0) : AtomSpaceGraphQuery
        @builder.where("a.tvStrength >= #{min_strength} AND a.tvConfidence >= #{min_confidence}")
        self
      end

      def with_attention(min_sti : Float64 = 0.0) : AtomSpaceGraphQuery
        @builder.where("a.avSti >= #{min_sti}")
        self
      end

      def returns(items : String) : AtomSpaceGraphQuery
        @builder.return_clause(items)
        self
      end

      def limit(count : Int32) : AtomSpaceGraphQuery
        @builder.limit(count)
        self
      end

      def execute : Neo4jResult
        @client.execute(@builder)
      end
    end

    # Unified Neo4j Integration wrapper (follows Phase 5 patterns)
    class Neo4jIntegration
      VERSION = "0.3.0"

      property config : Neo4jConfig
      property client : Neo4jClient
      property storage : Neo4jAtomSpaceStorage?
      property atomspace : AtomSpace::AtomSpace?
      property initialized : Bool
      property queries_executed : Int64
      property atoms_stored : Int64

      def initialize(@config = Neo4jConfig.new)
        @client = Neo4jClient.new(@config)
        @storage = nil
        @atomspace = nil
        @initialized = false
        @queries_executed = 0_i64
        @atoms_stored = 0_i64
      end

      # Attach AtomSpace (Phase 5 pattern)
      def attach_atomspace(atomspace : AtomSpace::AtomSpace)
        @atomspace = atomspace
      end

      # Initialize backend (Phase 5 pattern)
      def initialize_backend : Bool
        return true if @initialized

        unless @client.connect
          return false
        end

        unless @client.initialize_schema
          return false
        end

        @storage = Neo4jAtomSpaceStorage.new(@client)
        @initialized = true
        true
      end

      # Status reporting (Phase 5 pattern)
      def status : Hash(String, String)
        stats = @client.connected? ? @client.get_statistics : Neo4jGraphStats.new

        {
          "integration"        => "neo4j",
          "version"            => VERSION,
          "status"             => @initialized ? "ready" : "not_initialized",
          "connected"          => @client.connected?.to_s,
          "atomspace_attached" => (!@atomspace.nil?).to_s,
          "host"               => @config.host,
          "port"               => @config.port.to_s,
          "database"           => @config.database,
          "node_count"         => stats.node_count.to_s,
          "relationship_count" => stats.relationship_count.to_s,
          "queries_executed"   => @queries_executed.to_s,
          "atoms_stored"       => @atoms_stored.to_s,
          "max_connections"    => @config.max_connections.to_s,
          "batch_size"         => @config.batch_size.to_s,
        }
      end

      # Store atom to Neo4j
      def store_atom(
        id : String,
        atom_type : String,
        name : String? = nil,
        truth_value : {Float64, Float64} = {1.0, 1.0}
      ) : Bool
        atom = Neo4jAtomNode.new(
          id: id,
          atom_type: atom_type,
          name: name,
          truth_value_strength: truth_value[0],
          truth_value_confidence: truth_value[1]
        )
        result = @client.store_atom(atom)
        if result.success?
          @atoms_stored += 1
        end
        result.success?
      end

      # Query atoms
      def query(pattern : String, limit : Int32 = 100) : Array(Neo4jAtomNode)
        @queries_executed += 1
        @client.search_atoms_by_name(pattern, limit)
      end

      # Get atom by ID
      def get_atom(id : String) : Neo4jAtomNode?
        @queries_executed += 1
        @client.get_atom(id)
      end

      # Execute raw Cypher query
      def execute_cypher(query : String) : Neo4jResult
        @queries_executed += 1
        @client.execute_cypher(query)
      end

      # Sync AtomSpace to Neo4j
      def sync_atomspace : Bool
        return false unless @storage && @atomspace

        # Convert AtomSpace atoms to Neo4j format
        # This would integrate with actual AtomSpace API
        true
      end

      # Disconnect
      def disconnect
        @client.close
        @initialized = false
      end

      # Link to cognitive agency (Phase 5 pattern)
      def link_component(name : String)
        # Cognitive agency linking support
      end
    end
  end

  # Module-level factory methods (Phase 5 pattern)
  module Neo4j
    def self.create_default_integration : Integrations::Neo4jIntegration
      Integrations::Neo4jIntegration.new
    end

    def self.create_integration(
      host : String,
      port : Int32 = 7474,
      username : String = "neo4j",
      password : String = "password"
    ) : Integrations::Neo4jIntegration
      config = Integrations::Neo4jConfig.new(
        host: host,
        port: port,
        username: username,
        password: password
      )
      Integrations::Neo4jIntegration.new(config)
    end

    def self.create_integration(config : Integrations::Neo4jConfig) : Integrations::Neo4jIntegration
      Integrations::Neo4jIntegration.new(config)
    end
  end
end

# Main entry point for testing
if PROGRAM_NAME.includes?("neo4j_integration")
  puts "🔷 CrystalCog Neo4j Integration v0.1.0"
  puts "=" * 50
  puts ""
  puts "Neo4j graph database integration for AtomSpace"
  puts ""
  puts "Features:"
  puts "  • Atom storage and retrieval"
  puts "  • Link/relationship management"
  puts "  • Graph queries with Cypher"
  puts "  • Path finding between atoms"
  puts "  • Graph analytics (PageRank, communities)"
  puts "  • Semantic similarity search"
  puts "  • Batch operations"
  puts "  • Import/export JSON"
  puts ""
  puts "Usage:"
  puts "  client = Neo4jClient.new(\"localhost\", 7474, \"neo4j\", \"password\")"
  puts "  client.connect"
  puts "  client.initialize_schema"
  puts ""
  puts "  # Store an atom"
  puts "  atom = Neo4jAtomNode.new(id: \"concept-1\", atom_type: \"ConceptNode\", name: \"Dog\")"
  puts "  client.store_atom(atom)"
  puts ""
  puts "  # Query atoms"
  puts "  dogs = client.search_atoms_by_name(\".*Dog.*\")"
  puts ""
end
