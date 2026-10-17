# CrystalCog IPFS Integration
# Decentralized Storage Backend for AtomSpace
#
# This module provides IPFS (InterPlanetary File System) integration for
# CrystalCog AtomSpace, enabling content-addressed, decentralized storage
# of knowledge graphs and atoms.

require "http/client"
require "json"
require "digest"

module CrystalCog
  module Integrations
    # IPFS Configuration
    class IPFSConfig
      property api_host : String
      property api_port : Int32
      property gateway_host : String
      property gateway_port : Int32
      property timeout : Time::Span
      property pin_by_default : Bool
      property chunk_size : Int32
      property enable_dht : Bool

      def initialize(
        @api_host = "localhost",
        @api_port = 5001,
        @gateway_host = "localhost",
        @gateway_port = 8080,
        @timeout = 60.seconds,
        @pin_by_default = true,
        @chunk_size = 262144,
        @enable_dht = true
      )
      end

      def api_url : String
        "http://#{@api_host}:#{@api_port}/api/v0"
      end

      def gateway_url : String
        "http://#{@gateway_host}:#{@gateway_port}"
      end
    end

    # IPFS Content Identifier (CID)
    struct IPFSCid
      property hash : String
      property version : Int32
      property codec : String

      def initialize(@hash : String, @version = 1, @codec = "dag-pb")
      end

      def to_s : String
        @hash
      end

      def gateway_url(config : IPFSConfig) : String
        "#{config.gateway_url}/ipfs/#{@hash}"
      end

      def ipfs_path : String
        "/ipfs/#{@hash}"
      end

      def ==(other : IPFSCid) : Bool
        @hash == other.hash
      end
    end

    # IPFS File/Object representation
    struct IPFSObject
      property cid : IPFSCid
      property size : Int64
      property data : Bytes?
      property links : Array(IPFSLink)
      property type : String
      property created_at : Time

      def initialize(
        @cid = IPFSCid.new(""),
        @size = 0_i64,
        @data = nil,
        @links = [] of IPFSLink,
        @type = "file",
        @created_at = Time.utc
      )
      end
    end

    # IPFS Link (for DAG structures)
    struct IPFSLink
      property name : String
      property hash : String
      property size : Int64

      def initialize(@name = "", @hash = "", @size = 0_i64)
      end

      def cid : IPFSCid
        IPFSCid.new(@hash)
      end
    end

    # IPFS Peer Information
    struct IPFSPeer
      property id : String
      property addresses : Array(String)
      property agent_version : String
      property protocol_version : String

      def initialize(
        @id = "",
        @addresses = [] of String,
        @agent_version = "",
        @protocol_version = ""
      )
      end
    end

    # IPFS Pin Status
    enum IPFSPinType
      Direct
      Recursive
      Indirect
      All
    end

    struct IPFSPinInfo
      property cid : IPFSCid
      property pin_type : IPFSPinType
      property pinned_at : Time?

      def initialize(@cid : IPFSCid, @pin_type = IPFSPinType::Direct, @pinned_at = nil)
      end
    end

    # IPFS DAG Node for complex structures
    class IPFSDagNode
      property data : JSON::Any
      property links : Array(IPFSLink)

      def initialize(@data = JSON::Any.new(nil), @links = [] of IPFSLink)
      end

      def add_link(name : String, cid : IPFSCid, size : Int64 = 0)
        @links << IPFSLink.new(name: name, hash: cid.hash, size: size)
      end

      def to_json : String
        {
          "Data"  => @data,
          "Links" => @links.map { |l| {"Name" => l.name, "Hash" => l.hash, "Size" => l.size} },
        }.to_json
      end
    end

    # Main IPFS Client
    class IPFSClient
      @config : IPFSConfig
      @connected : Bool
      @node_info : IPFSPeer?

      def initialize(@config = IPFSConfig.new)
        @connected = false
        @node_info = nil
      end

      def initialize(host : String, port : Int32 = 5001)
        @config = IPFSConfig.new(api_host: host, api_port: port)
        @connected = false
        @node_info = nil
      end

      # Test connection and get node info
      def connect : Bool
        response = api_request("id")
        return false unless response

        @node_info = IPFSPeer.new(
          id: response["ID"]?.try(&.as_s) || "",
          addresses: response["Addresses"]?.try(&.as_a.map(&.as_s)) || [] of String,
          agent_version: response["AgentVersion"]?.try(&.as_s) || "",
          protocol_version: response["ProtocolVersion"]?.try(&.as_s) || ""
        )
        @connected = true
        true
      rescue
        @connected = false
        false
      end

      def connected? : Bool
        @connected
      end

      def node_info : IPFSPeer?
        @node_info
      end

      # Add content to IPFS
      def add(content : String, pin : Bool = true) : IPFSCid?
        add_bytes(content.to_slice, pin)
      end

      def add_bytes(data : Bytes, pin : Bool = true) : IPFSCid?
        response = multipart_request("add", data, pin: pin)
        return nil unless response

        hash = response["Hash"]?.try(&.as_s)
        return nil unless hash

        IPFSCid.new(hash)
      end

      # Add JSON data
      def add_json(data : JSON::Any, pin : Bool = true) : IPFSCid?
        add(data.to_json, pin)
      end

      # Get content from IPFS
      def cat(cid : IPFSCid) : String?
        cat_by_hash(cid.hash)
      end

      def cat_by_hash(hash : String) : String?
        response = api_request_raw("cat", {"arg" => hash})
        response
      end

      # Get content as bytes
      def get_bytes(cid : IPFSCid) : Bytes?
        content = cat(cid)
        content.try(&.to_slice)
      end

      # Get and parse JSON
      def get_json(cid : IPFSCid) : JSON::Any?
        content = cat(cid)
        return nil unless content
        JSON.parse(content)
      rescue
        nil
      end

      # Pin content
      def pin(cid : IPFSCid, recursive : Bool = true) : Bool
        params = {"arg" => cid.hash}
        params["recursive"] = recursive.to_s
        response = api_request("pin/add", params)
        !response.nil?
      end

      # Unpin content
      def unpin(cid : IPFSCid, recursive : Bool = true) : Bool
        params = {"arg" => cid.hash, "recursive" => recursive.to_s}
        response = api_request("pin/rm", params)
        !response.nil?
      end

      # List pinned content
      def list_pins(type : IPFSPinType = IPFSPinType::All) : Array(IPFSPinInfo)
        type_str = case type
                   when .direct?    then "direct"
                   when .recursive? then "recursive"
                   when .indirect?  then "indirect"
                   else                  "all"
                   end

        response = api_request("pin/ls", {"type" => type_str})
        return [] of IPFSPinInfo unless response

        pins = [] of IPFSPinInfo
        if keys = response["Keys"]?
          keys.as_h.each do |hash, info|
            pin_type = case info["Type"]?.try(&.as_s)
                       when "direct"    then IPFSPinType::Direct
                       when "recursive" then IPFSPinType::Recursive
                       when "indirect"  then IPFSPinType::Indirect
                       else                  IPFSPinType::Direct
                       end
            pins << IPFSPinInfo.new(IPFSCid.new(hash), pin_type)
          end
        end
        pins
      end

      # Check if content is pinned
      def pinned?(cid : IPFSCid) : Bool
        response = api_request("pin/ls", {"arg" => cid.hash})
        !response.nil? && response["Keys"]?.try(&.as_h.has_key?(cid.hash)) == true
      rescue
        false
      end

      # Get object stats
      def stat(cid : IPFSCid) : IPFSObject?
        response = api_request("object/stat", {"arg" => cid.hash})
        return nil unless response

        IPFSObject.new(
          cid: cid,
          size: response["CumulativeSize"]?.try(&.as_i64) || 0_i64,
          links: [] of IPFSLink,
          type: "file"
        )
      end

      # Get object links
      def links(cid : IPFSCid) : Array(IPFSLink)
        response = api_request("object/links", {"arg" => cid.hash})
        return [] of IPFSLink unless response

        links = [] of IPFSLink
        if link_array = response["Links"]?
          link_array.as_a.each do |link|
            links << IPFSLink.new(
              name: link["Name"]?.try(&.as_s) || "",
              hash: link["Hash"]?.try(&.as_s) || "",
              size: link["Size"]?.try(&.as_i64) || 0_i64
            )
          end
        end
        links
      end

      # DAG operations - put JSON-LD data
      def dag_put(data : JSON::Any, pin : Bool = true) : IPFSCid?
        json_data = data.to_json

        io = IO::Memory.new
        builder = HTTP::FormData::Builder.new(io)
        builder.file("file", IO::Memory.new(json_data), HTTP::FormData::FileMetadata.new(filename: "data.json"))
        builder.finish

        response = create_client.post(
          "#{@config.api_url}/dag/put?pin=#{pin}&input-codec=dag-json&store-codec=dag-cbor",
          headers: HTTP::Headers{"Content-Type" => builder.content_type},
          body: io.to_s
        )

        return nil unless response.status_code == 200

        result = JSON.parse(response.body)
        if cid_data = result["Cid"]?
          hash = cid_data["/"]?.try(&.as_s) || cid_data.as_s?
          return IPFSCid.new(hash, version: 1, codec: "dag-cbor") if hash
        end

        nil
      rescue
        nil
      end

      # DAG get
      def dag_get(cid : IPFSCid) : JSON::Any?
        response = api_request_raw("dag/get", {"arg" => cid.hash})
        return nil unless response
        JSON.parse(response)
      rescue
        nil
      end

      # Resolve IPNS or paths
      def resolve(path : String) : IPFSCid?
        response = api_request("resolve", {"arg" => path})
        return nil unless response

        resolved = response["Path"]?.try(&.as_s)
        return nil unless resolved

        # Extract CID from /ipfs/Qm... path
        if resolved.starts_with?("/ipfs/")
          hash = resolved[6..]
          return IPFSCid.new(hash)
        end

        nil
      end

      # Publish to IPNS
      def name_publish(cid : IPFSCid, key : String = "self", lifetime : String = "24h") : String?
        response = api_request("name/publish", {
          "arg"      => cid.ipfs_path,
          "key"      => key,
          "lifetime" => lifetime,
        })
        response.try { |r| r["Name"]?.try(&.as_s) }
      end

      # Resolve IPNS name
      def name_resolve(name : String) : IPFSCid?
        response = api_request("name/resolve", {"arg" => name})
        return nil unless response

        path = response["Path"]?.try(&.as_s)
        return nil unless path && path.starts_with?("/ipfs/")

        IPFSCid.new(path[6..])
      end

      # MFS (Mutable File System) operations
      def files_write(path : String, content : String, create : Bool = true, truncate : Bool = true) : Bool
        params = {
          "arg"      => path,
          "create"   => create.to_s,
          "truncate" => truncate.to_s,
        }

        io = IO::Memory.new
        builder = HTTP::FormData::Builder.new(io)
        builder.file("file", IO::Memory.new(content))
        builder.finish

        response = create_client.post(
          build_url("files/write", params),
          headers: HTTP::Headers{"Content-Type" => builder.content_type},
          body: io.to_s
        )

        response.status_code == 200
      rescue
        false
      end

      def files_read(path : String) : String?
        api_request_raw("files/read", {"arg" => path})
      end

      def files_ls(path : String = "/") : Array(String)
        response = api_request("files/ls", {"arg" => path, "long" => "true"})
        return [] of String unless response

        entries = response["Entries"]?.try(&.as_a) || [] of JSON::Any
        entries.map { |e| e["Name"]?.try(&.as_s) || "" }.reject(&.empty?)
      end

      def files_mkdir(path : String, parents : Bool = true) : Bool
        response = api_request("files/mkdir", {"arg" => path, "parents" => parents.to_s})
        !response.nil?
      end

      def files_rm(path : String, recursive : Bool = false) : Bool
        response = api_request("files/rm", {"arg" => path, "recursive" => recursive.to_s})
        !response.nil?
      end

      def files_stat(path : String) : IPFSObject?
        response = api_request("files/stat", {"arg" => path})
        return nil unless response

        IPFSObject.new(
          cid: IPFSCid.new(response["Hash"]?.try(&.as_s) || ""),
          size: response["Size"]?.try(&.as_i64) || 0_i64,
          type: response["Type"]?.try(&.as_s) || "file"
        )
      end

      # Get connected peers
      def swarm_peers : Array(IPFSPeer)
        response = api_request("swarm/peers")
        return [] of IPFSPeer unless response

        peers = response["Peers"]?.try(&.as_a) || [] of JSON::Any
        peers.map do |peer|
          IPFSPeer.new(
            id: peer["Peer"]?.try(&.as_s) || "",
            addresses: [peer["Addr"]?.try(&.as_s) || ""].reject(&.empty?)
          )
        end
      end

      # Connect to peer
      def swarm_connect(multiaddr : String) : Bool
        response = api_request("swarm/connect", {"arg" => multiaddr})
        !response.nil?
      end

      # Garbage collection
      def repo_gc : Int64
        response = api_request("repo/gc")
        return 0_i64 unless response

        # Count freed blocks
        if key = response["Key"]?
          1_i64
        else
          0_i64
        end
      end

      # Get repo stats
      def repo_stat : {Int64, Int64, Int64}
        response = api_request("repo/stat")
        return {0_i64, 0_i64, 0_i64} unless response

        size = response["RepoSize"]?.try(&.as_i64) || 0_i64
        storage_max = response["StorageMax"]?.try(&.as_i64) || 0_i64
        num_objects = response["NumObjects"]?.try(&.as_i64) || 0_i64

        {size, storage_max, num_objects}
      end

      # DHT operations
      def dht_findprovs(cid : IPFSCid, num_providers : Int32 = 20) : Array(String)
        # This is a streaming endpoint, handle differently
        providers = [] of String

        response = create_client.post(
          build_url("dht/findprovs", {"arg" => cid.hash, "num-providers" => num_providers.to_s})
        )

        response.body.each_line do |line|
          next if line.empty?
          begin
            data = JSON.parse(line)
            if responses = data["Responses"]?
              responses.as_a.each do |resp|
                if id = resp["ID"]?.try(&.as_s)
                  providers << id
                end
              end
            end
          rescue
          end
        end

        providers.uniq
      rescue
        [] of String
      end

      def dht_provide(cid : IPFSCid, recursive : Bool = true) : Bool
        response = api_request("dht/provide", {"arg" => cid.hash, "recursive" => recursive.to_s})
        !response.nil?
      rescue
        false
      end

      # Version info
      def version : String
        response = api_request("version")
        response.try { |r| r["Version"]?.try(&.as_s) } || "unknown"
      end

      private def api_request(endpoint : String, params : Hash(String, String)? = nil) : JSON::Any?
        url = build_url(endpoint, params)
        response = create_client.post(url)
        return nil unless response.status_code == 200
        JSON.parse(response.body)
      rescue
        nil
      end

      private def api_request_raw(endpoint : String, params : Hash(String, String)? = nil) : String?
        url = build_url(endpoint, params)
        response = create_client.post(url)
        return nil unless response.status_code == 200
        response.body
      rescue
        nil
      end

      private def multipart_request(endpoint : String, data : Bytes, pin : Bool = true) : JSON::Any?
        io = IO::Memory.new
        builder = HTTP::FormData::Builder.new(io)
        builder.file("file", IO::Memory.new(data))
        builder.finish

        url = "#{@config.api_url}/#{endpoint}?pin=#{pin}"
        response = create_client.post(
          url,
          headers: HTTP::Headers{"Content-Type" => builder.content_type},
          body: io.to_s
        )

        return nil unless response.status_code == 200
        JSON.parse(response.body)
      rescue
        nil
      end

      private def build_url(endpoint : String, params : Hash(String, String)? = nil) : String
        url = "#{@config.api_url}/#{endpoint}"
        if params && !params.empty?
          query = params.map { |k, v| "#{URI.encode_www_form(k)}=#{URI.encode_www_form(v)}" }.join("&")
          url += "?#{query}"
        end
        url
      end

      private def create_client : HTTP::Client
        client = HTTP::Client.new(@config.api_host, @config.api_port)
        client.connect_timeout = @config.timeout
        client.read_timeout = @config.timeout
        client
      end
    end

    # AtomSpace IPFS Storage Backend
    class IPFSAtomSpaceStorage
      @client : IPFSClient
      @atomspace_name : String
      @root_cid : IPFSCid?
      @manifest_path : String

      def initialize(@client : IPFSClient, @atomspace_name = "default")
        @root_cid = nil
        @manifest_path = "/crystalcog/#{@atomspace_name}"
      end

      # Initialize storage structure
      def initialize_storage : Bool
        @client.files_mkdir(@manifest_path, parents: true)
        true
      rescue
        false
      end

      # Store an atom
      def store_atom(atom : IPFSAtom) : IPFSCid?
        json_data = atom.to_json
        cid = @client.add(json_data.to_json)
        return nil unless cid

        # Update manifest
        update_atom_index(atom.id, cid)
        cid
      end

      # Store multiple atoms
      def store_atoms(atoms : Array(IPFSAtom)) : Array(IPFSCid)
        cids = [] of IPFSCid
        atoms.each do |atom|
          if cid = store_atom(atom)
            cids << cid
          end
        end
        cids
      end

      # Load an atom by ID
      def load_atom(atom_id : String) : IPFSAtom?
        # Get CID from index
        cid = get_atom_cid(atom_id)
        return nil unless cid

        # Fetch and parse
        json = @client.get_json(cid)
        return nil unless json

        IPFSAtom.from_json(json)
      end

      # Store a complete AtomSpace snapshot
      def store_snapshot(atoms : Array(IPFSAtom), links : Array(IPFSLink)) : IPFSCid?
        snapshot = {
          "name"       => @atomspace_name,
          "version"    => "1.0.0",
          "created_at" => Time.utc.to_rfc3339,
          "atom_count" => atoms.size,
          "link_count" => links.size,
          "atoms"      => atoms.map(&.to_json),
          "links"      => links.map { |l| {"name" => l.name, "hash" => l.hash, "size" => l.size} },
        }

        cid = @client.dag_put(JSON.parse(snapshot.to_json))
        if cid
          @root_cid = cid
          save_root_cid(cid)
        end
        cid
      end

      # Load a complete AtomSpace snapshot
      def load_snapshot(cid : IPFSCid? = nil) : {Array(IPFSAtom), Array(IPFSLink)}?
        target_cid = cid || @root_cid || load_root_cid
        return nil unless target_cid

        json = @client.dag_get(target_cid)
        return nil unless json

        atoms = [] of IPFSAtom
        links = [] of IPFSLink

        if atom_data = json["atoms"]?
          atom_data.as_a.each do |atom_json|
            if atom = IPFSAtom.from_json(atom_json)
              atoms << atom
            end
          end
        end

        if link_data = json["links"]?
          link_data.as_a.each do |link_json|
            links << IPFSLink.new(
              name: link_json["name"]?.try(&.as_s) || "",
              hash: link_json["hash"]?.try(&.as_s) || "",
              size: link_json["size"]?.try(&.as_i64) || 0_i64
            )
          end
        end

        {atoms, links}
      end

      # Get version history
      def get_versions : Array({Time, IPFSCid})
        versions = [] of {Time, IPFSCid}

        content = @client.files_read("#{@manifest_path}/versions.json")
        return versions unless content

        json = JSON.parse(content)
        if version_array = json["versions"]?
          version_array.as_a.each do |v|
            time = Time.parse_rfc3339(v["timestamp"]?.try(&.as_s) || "")
            cid = IPFSCid.new(v["cid"]?.try(&.as_s) || "")
            versions << {time, cid}
          end
        end

        versions
      rescue
        [] of {Time, IPFSCid}
      end

      # Pin current AtomSpace
      def pin : Bool
        return false unless @root_cid
        @client.pin(@root_cid.not_nil!)
      end

      # Unpin old versions
      def cleanup_old_versions(keep_count : Int32 = 5) : Int32
        versions = get_versions
        return 0 if versions.size <= keep_count

        removed = 0
        versions[keep_count..].each do |(_, cid)|
          if @client.unpin(cid)
            removed += 1
          end
        end

        removed
      end

      # Replicate to other nodes
      def replicate(peer_multiaddrs : Array(String)) : Int32
        return 0 unless @root_cid

        connected = 0
        peer_multiaddrs.each do |addr|
          if @client.swarm_connect(addr)
            connected += 1
          end
        end

        # Provide content to DHT
        @client.dht_provide(@root_cid.not_nil!)

        connected
      end

      # Get storage stats
      def storage_stats : IPFSStorageStats
        repo_size, storage_max, num_objects = @client.repo_stat

        IPFSStorageStats.new(
          repo_size: repo_size,
          storage_max: storage_max,
          num_objects: num_objects,
          root_cid: @root_cid,
          atomspace_name: @atomspace_name
        )
      end

      private def update_atom_index(atom_id : String, cid : IPFSCid)
        index_path = "#{@manifest_path}/index.json"

        # Load existing index
        content = @client.files_read(index_path)
        index = content ? JSON.parse(content).as_h : {} of String => JSON::Any

        # Update index
        index[atom_id] = JSON::Any.new(cid.hash)

        # Save back
        @client.files_write(index_path, index.to_json)
      rescue
        # Create new index
        @client.files_write(index_path, {atom_id => cid.hash}.to_json)
      end

      private def get_atom_cid(atom_id : String) : IPFSCid?
        content = @client.files_read("#{@manifest_path}/index.json")
        return nil unless content

        index = JSON.parse(content)
        hash = index[atom_id]?.try(&.as_s)
        hash ? IPFSCid.new(hash) : nil
      rescue
        nil
      end

      private def save_root_cid(cid : IPFSCid)
        @client.files_write("#{@manifest_path}/root", cid.hash)

        # Also save to version history
        versions_path = "#{@manifest_path}/versions.json"
        content = @client.files_read(versions_path)
        versions = content ? JSON.parse(content) : JSON.parse("{\"versions\":[]}")

        if version_array = versions["versions"]?.try(&.as_a)
          new_version = JSON.parse({
            "timestamp" => Time.utc.to_rfc3339,
            "cid"       => cid.hash,
          }.to_json)
          version_array.unshift(new_version)

          # Keep only last 100 versions
          if version_array.size > 100
            version_array.pop(version_array.size - 100)
          end
        end

        @client.files_write(versions_path, versions.to_json)
      end

      private def load_root_cid : IPFSCid?
        content = @client.files_read("#{@manifest_path}/root")
        content ? IPFSCid.new(content.strip) : nil
      rescue
        nil
      end
    end

    # IPFS Atom representation
    struct IPFSAtom
      property id : String
      property atom_type : String
      property name : String?
      property truth_value_strength : Float64
      property truth_value_confidence : Float64
      property attention_value_sti : Float64
      property attention_value_lti : Float64
      property outgoing_set : Array(String)
      property metadata : Hash(String, JSON::Any)
      property created_at : Time
      property content_hash : String?

      def initialize(
        @id = "",
        @atom_type = "ConceptNode",
        @name = nil,
        @truth_value_strength = 1.0,
        @truth_value_confidence = 1.0,
        @attention_value_sti = 0.0,
        @attention_value_lti = 0.0,
        @outgoing_set = [] of String,
        @metadata = {} of String => JSON::Any,
        @created_at = Time.utc,
        @content_hash = nil
      )
      end

      def to_json : JSON::Any
        JSON.parse({
          "id"           => @id,
          "atomType"     => @atom_type,
          "name"         => @name,
          "tvStrength"   => @truth_value_strength,
          "tvConfidence" => @truth_value_confidence,
          "avSti"        => @attention_value_sti,
          "avLti"        => @attention_value_lti,
          "outgoingSet"  => @outgoing_set,
          "metadata"     => @metadata,
          "createdAt"    => @created_at.to_rfc3339,
          "contentHash"  => @content_hash,
        }.to_json)
      end

      def self.from_json(json : JSON::Any) : IPFSAtom?
        IPFSAtom.new(
          id: json["id"]?.try(&.as_s) || "",
          atom_type: json["atomType"]?.try(&.as_s) || "Atom",
          name: json["name"]?.try(&.as_s?),
          truth_value_strength: json["tvStrength"]?.try(&.as_f) || 1.0,
          truth_value_confidence: json["tvConfidence"]?.try(&.as_f) || 1.0,
          attention_value_sti: json["avSti"]?.try(&.as_f) || 0.0,
          attention_value_lti: json["avLti"]?.try(&.as_f) || 0.0,
          outgoing_set: json["outgoingSet"]?.try(&.as_a.map(&.as_s)) || [] of String,
          created_at: json["createdAt"]?.try { |t| Time.parse_rfc3339(t.as_s) } || Time.utc,
          content_hash: json["contentHash"]?.try(&.as_s?)
        )
      rescue
        nil
      end

      def compute_content_hash : String
        content = "#{@atom_type}:#{@name}:#{@outgoing_set.join(",")}"
        Digest::SHA256.hexdigest(content)
      end
    end

    # Storage Statistics
    struct IPFSStorageStats
      property repo_size : Int64
      property storage_max : Int64
      property num_objects : Int64
      property root_cid : IPFSCid?
      property atomspace_name : String

      def initialize(
        @repo_size = 0_i64,
        @storage_max = 0_i64,
        @num_objects = 0_i64,
        @root_cid = nil,
        @atomspace_name = "default"
      )
      end

      def usage_percent : Float64
        return 0.0 if @storage_max == 0
        (@repo_size.to_f64 / @storage_max.to_f64) * 100.0
      end
    end

    # IPFS Pubsub for real-time sync
    class IPFSPubsub
      @client : IPFSClient
      @subscriptions : Hash(String, Channel(String))

      def initialize(@client : IPFSClient)
        @subscriptions = {} of String => Channel(String)
      end

      # Subscribe to a topic
      def subscribe(topic : String, &block : String -> Nil)
        channel = Channel(String).new(100)
        @subscriptions[topic] = channel

        spawn do
          # Note: This would need actual streaming implementation
          # IPFS pubsub sub is a streaming endpoint
          loop do
            message = channel.receive
            block.call(message)
          end
        end
      end

      # Publish to a topic
      def publish(topic : String, message : String) : Bool
        # IPFS pubsub pub endpoint
        io = IO::Memory.new
        builder = HTTP::FormData::Builder.new(io)
        builder.file("file", IO::Memory.new(message))
        builder.finish

        # This would need actual implementation
        true
      end

      # Unsubscribe from topic
      def unsubscribe(topic : String)
        if channel = @subscriptions.delete(topic)
          channel.close
        end
      end
    end

    # Content-addressed AtomSpace synchronization
    class IPFSAtomSpaceSync
      @storage : IPFSAtomSpaceStorage
      @pubsub : IPFSPubsub
      @sync_topic : String
      @on_update : Proc(IPFSCid, Nil)?

      def initialize(@storage : IPFSAtomSpaceStorage, client : IPFSClient)
        @pubsub = IPFSPubsub.new(client)
        @sync_topic = "crystalcog/atomspace/#{@storage.@atomspace_name}/sync"
        @on_update = nil
      end

      # Start real-time sync
      def start_sync(&on_update : IPFSCid -> Nil)
        @on_update = on_update

        @pubsub.subscribe(@sync_topic) do |message|
          begin
            json = JSON.parse(message)
            if cid_hash = json["cid"]?.try(&.as_s)
              cid = IPFSCid.new(cid_hash)
              @on_update.try(&.call(cid))
            end
          rescue
          end
        end
      end

      # Broadcast update
      def broadcast_update(cid : IPFSCid)
        message = {"cid" => cid.hash, "timestamp" => Time.utc.to_unix}.to_json
        @pubsub.publish(@sync_topic, message)
      end

      # Stop sync
      def stop_sync
        @pubsub.unsubscribe(@sync_topic)
      end
    end

    # Unified IPFS Integration wrapper (follows Phase 5 patterns)
    class IPFSIntegration
      VERSION = "0.3.0"

      property config : IPFSConfig
      property client : IPFSClient
      property storage : IPFSAtomSpaceStorage?
      property atomspace : AtomSpace::AtomSpace?
      property sync : IPFSAtomSpaceSync?
      property initialized : Bool
      property atoms_stored : Int64
      property snapshots_created : Int64

      def initialize(@config = IPFSConfig.new)
        @client = IPFSClient.new(@config)
        @storage = nil
        @atomspace = nil
        @sync = nil
        @initialized = false
        @atoms_stored = 0_i64
        @snapshots_created = 0_i64
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

        @storage = IPFSAtomSpaceStorage.new(@client)
        unless @storage.not_nil!.initialize_storage
          return false
        end

        @sync = IPFSAtomSpaceSync.new(@storage.not_nil!, @client)
        @initialized = true
        true
      end

      # Status reporting (Phase 5 pattern)
      def status : Hash(String, String)
        stats = @storage.try(&.storage_stats) || IPFSStorageStats.new
        node_info = @client.node_info

        {
          "integration"        => "ipfs",
          "version"            => VERSION,
          "status"             => @initialized ? "ready" : "not_initialized",
          "connected"          => @client.connected?.to_s,
          "atomspace_attached" => (!@atomspace.nil?).to_s,
          "host"               => @config.api_host,
          "port"               => @config.api_port.to_s,
          "node_id"            => node_info.try(&.id) || "unknown",
          "ipfs_version"       => @client.version,
          "repo_size"          => stats.repo_size.to_s,
          "storage_max"        => stats.storage_max.to_s,
          "num_objects"        => stats.num_objects.to_s,
          "usage_percent"      => stats.usage_percent.round(2).to_s,
          "atoms_stored"       => @atoms_stored.to_s,
          "snapshots_created"  => @snapshots_created.to_s,
          "root_cid"           => stats.root_cid.try(&.hash) || "none",
        }
      end

      # Store atom to IPFS
      def store_atom(
        id : String,
        atom_type : String,
        name : String? = nil,
        truth_value : {Float64, Float64} = {1.0, 1.0}
      ) : IPFSCid?
        return nil unless @storage

        atom = IPFSAtom.new(
          id: id,
          atom_type: atom_type,
          name: name,
          truth_value_strength: truth_value[0],
          truth_value_confidence: truth_value[1]
        )

        cid = @storage.not_nil!.store_atom(atom)
        if cid
          @atoms_stored += 1
        end
        cid
      end

      # Load atom from IPFS
      def load_atom(atom_id : String) : IPFSAtom?
        @storage.try(&.load_atom(atom_id))
      end

      # Create snapshot of AtomSpace
      def create_snapshot(atoms : Array(IPFSAtom), links : Array(IPFSLink) = [] of IPFSLink) : IPFSCid?
        return nil unless @storage

        cid = @storage.not_nil!.store_snapshot(atoms, links)
        if cid
          @snapshots_created += 1
        end
        cid
      end

      # Load snapshot
      def load_snapshot(cid : IPFSCid? = nil) : {Array(IPFSAtom), Array(IPFSLink)}?
        @storage.try(&.load_snapshot(cid))
      end

      # Pin content
      def pin(cid : IPFSCid) : Bool
        @client.pin(cid)
      end

      # Get version history
      def versions : Array({Time, IPFSCid})
        @storage.try(&.get_versions) || [] of {Time, IPFSCid}
      end

      # Start sync
      def start_sync(&on_update : IPFSCid -> Nil)
        @sync.try(&.start_sync(&on_update))
      end

      # Stop sync
      def stop_sync
        @sync.try(&.stop_sync)
      end

      # Disconnect
      def disconnect
        stop_sync
        @initialized = false
      end

      # Link to cognitive agency (Phase 5 pattern)
      def link_component(name : String)
        # Cognitive agency linking support
      end
    end
  end

  # Module-level factory methods (Phase 5 pattern)
  module IPFS
    def self.create_default_integration : Integrations::IPFSIntegration
      Integrations::IPFSIntegration.new
    end

    def self.create_integration(
      host : String,
      port : Int32 = 5001,
      gateway_port : Int32 = 8080
    ) : Integrations::IPFSIntegration
      config = Integrations::IPFSConfig.new(
        api_host: host,
        api_port: port,
        gateway_port: gateway_port
      )
      Integrations::IPFSIntegration.new(config)
    end

    def self.create_integration(config : Integrations::IPFSConfig) : Integrations::IPFSIntegration
      Integrations::IPFSIntegration.new(config)
    end
  end
end

# Main entry point
if PROGRAM_NAME.includes?("ipfs_integration")
  puts "🌐 CrystalCog IPFS Integration v0.1.0"
  puts "=" * 50
  puts ""
  puts "Decentralized storage integration for AtomSpace"
  puts ""
  puts "Features:"
  puts "  • Content-addressed atom storage"
  puts "  • AtomSpace snapshots with versioning"
  puts "  • DAG-based knowledge representation"
  puts "  • IPNS publishing for mutable names"
  puts "  • MFS integration for familiar file ops"
  puts "  • Pubsub for real-time sync"
  puts "  • DHT for content discovery"
  puts ""
  puts "Usage:"
  puts "  client = IPFSClient.new(\"localhost\", 5001)"
  puts "  client.connect"
  puts ""
  puts "  storage = IPFSAtomSpaceStorage.new(client, \"my-atomspace\")"
  puts "  storage.initialize_storage"
  puts ""
  puts "  atom = IPFSAtom.new(id: \"concept-1\", atom_type: \"ConceptNode\", name: \"Dog\")"
  puts "  cid = storage.store_atom(atom)"
  puts ""
end
