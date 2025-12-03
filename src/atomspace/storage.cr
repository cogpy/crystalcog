# Crystal implementation of AtomSpace persistence interfaces
# Based on atomspace/opencog/persist/api/StorageNode.h
#
# This provides the base interface for persistent storage of AtomSpace contents.

require "./atom"
require "./truthvalue"
require "../cogutil/cogutil"
require "../rocksdb"
require "sqlite3"
require "pg"
require "db"
require "json"
require "http/client"

module AtomSpace
  # Base interface for persistent storage
  abstract class StorageNode < Node
    def initialize(name : String)
      super(AtomType::STORAGE_NODE, name)
    end

    # Open connection to storage backend
    abstract def open : Bool

    # Close connection to storage backend
    abstract def close : Bool

    # Check if connection is open
    abstract def connected? : Bool

    # Store a single atom
    abstract def store_atom(atom : Atom) : Bool

    # Fetch a single atom by handle
    abstract def fetch_atom(handle : Handle) : Atom?

    # Remove an atom from storage
    abstract def remove_atom(atom : Atom) : Bool

    # Store all atoms from AtomSpace
    abstract def store_atomspace(atomspace : AtomSpace) : Bool

    # Load all atoms into AtomSpace
    abstract def load_atomspace(atomspace : AtomSpace) : Bool

    # Get storage statistics
    abstract def get_stats : Hash(String, String | Int32 | Int64)

    # Bulk operations
    def store_atoms(atoms : Array(Atom)) : Bool
      success = true
      atoms.each do |atom|
        success = false unless store_atom(atom)
      end
      success
    end

    def fetch_atoms_by_type(type : AtomType) : Array(Atom)
      # Default implementation - subclasses should override for efficiency
      [] of Atom
    end

    # Utility methods
    protected def log_error(message : String)
      CogUtil::Logger.error("#{self.class.name}: #{message}")
    end

    protected def log_info(message : String)
      CogUtil::Logger.info("#{self.class.name}: #{message}")
    end

    protected def log_debug(message : String)
      CogUtil::Logger.debug("#{self.class.name}: #{message}")
    end
  end

  # File-based storage implementation
  class FileStorageNode < StorageNode
    @file_path : String
    @connected : Bool = false
    @atom_index : Hash(Handle, Atom) = Hash(Handle, Atom).new
    @index_dirty : Bool = false

    def initialize(name : String, @file_path : String)
      super(name)
      log_info("FileStorageNode created for: #{@file_path}")
    end

    def open : Bool
      return true if @connected

      begin
        # Ensure directory exists
        dir = File.dirname(@file_path)
        Dir.mkdir_p(dir) unless Dir.exists?(dir)

        # Test write access
        File.touch(@file_path) unless File.exists?(@file_path)

        @connected = true
        
        # Build index from existing file
        rebuild_index
        
        log_info("Opened file storage: #{@file_path}")
        true
      rescue ex
        log_error("Failed to open file storage: #{ex.message}")
        false
      end
    end

    def close : Bool
      @connected = false
      @atom_index.clear
      @index_dirty = false
      log_info("Closed file storage: #{@file_path}")
      true
    end

    def connected? : Bool
      @connected
    end

    def store_atom(atom : Atom) : Bool
      return false unless @connected

      begin
        File.open(@file_path, "a") do |file|
          file.puts(atom_to_scheme(atom))
        end
        
        # Update index
        @atom_index[atom.handle] = atom
        
        log_debug("Stored atom: #{atom}")
        true
      rescue ex
        log_error("Failed to store atom: #{ex.message}")
        false
      end
    end

    def fetch_atom(handle : Handle) : Atom?
      return nil unless @connected

      # Use index for O(1) lookup
      @atom_index[handle]?
    end

    def remove_atom(atom : Atom) : Bool
      return false unless @connected

      begin
        # Remove from index
        @atom_index.delete(atom.handle)
        
        # Rewrite file with remaining atoms
        File.open(@file_path, "w") do |file|
          @atom_index.each_value { |a| file.puts(atom_to_scheme(a)) }
        end

        log_debug("Removed atom: #{atom}")
        true
      rescue ex
        log_error("Failed to remove atom: #{ex.message}")
        false
      end
    end

    def store_atomspace(atomspace : AtomSpace) : Bool
      return false unless @connected

      begin
        # Clear and rebuild index
        @atom_index.clear
        
        File.open(@file_path, "w") do |file|
          atomspace.get_all_atoms.each do |atom|
            file.puts(atom_to_scheme(atom))
            @atom_index[atom.handle] = atom
          end
        end

        log_info("Stored AtomSpace (#{atomspace.size} atoms) to: #{@file_path}")
        true
      rescue ex
        log_error("Failed to store AtomSpace: #{ex.message}")
        false
      end
    end

    def load_atomspace(atomspace : AtomSpace) : Bool
      return false unless @connected

      begin
        return true unless File.exists?(@file_path)

        count = 0
        File.each_line(@file_path) do |line|
          line = line.strip
          next if line.empty? || line.starts_with?(';')

          atom = scheme_to_atom(line)
          if atom
            atomspace.add_atom(atom)
            count += 1
          end
        end

        log_info("Loaded #{count} atoms from: #{@file_path}")
        true
      rescue ex
        log_error("Failed to load AtomSpace: #{ex.message}")
        false
      end
    end

    def get_stats : Hash(String, String | Int32 | Int64)
      stats = Hash(String, String | Int32 | Int64).new
      stats["type"] = "FileStorage"
      stats["path"] = @file_path
      stats["connected"] = @connected ? "true" : "false"

      if File.exists?(@file_path)
        stats["file_size"] = File.size(@file_path)
        stats["file_exists"] = "true"
      else
        stats["file_exists"] = "false"
        stats["file_size"] = 0_i64
      end

      stats
    end

    # Convert atom to Scheme s-expression format
    private def atom_to_scheme(atom : Atom) : String
      case atom
      when Node
        tv_str = atom.truth_value == TruthValue::DEFAULT_TV ? "" : " #{atom.truth_value}"
        "(#{atom.type.to_s} \"#{atom.name}\"#{tv_str})"
      when Link
        outgoing_str = atom.outgoing.map { |a| atom_to_scheme(a) }.join(" ")
        tv_str = atom.truth_value == TruthValue::DEFAULT_TV ? "" : " #{atom.truth_value}"
        "(#{atom.type.to_s} #{outgoing_str}#{tv_str})"
      else
        atom.to_s
      end
    end

    # Convert Scheme s-expression to atom (simplified parser)
    private def scheme_to_atom(scheme : String) : Atom?
      # This is a simplified parser - in practice, we'd use a proper S-expression parser
      scheme = scheme.strip
      return nil unless scheme.starts_with?('(') && scheme.ends_with?(')')

      # Remove outer parentheses
      content = scheme[1..-2].strip

      # Split on first space to get type
      parts = content.split(' ', 2)
      return nil if parts.empty?

      begin
        type = AtomType.parse(parts[0])

        if type.node?
          # Parse node: (TYPE "name" [truth_value])
          if parts.size >= 2
            name_part = parts[1].strip
            # <<<<<<< copilot/fix-56
            if name_part.starts_with?('"') && name_part[1..].includes?('"')
              # =======
              #            if name_part.starts_with?('"') && name_part[1..].includes?("\"")
              # >>>>>>> main
              quote_end = name_part.index('"', 1)
              if quote_end
                name = name_part[1...quote_end]
                return Node.new(type, name)
              end
            end
          end
        else
          # Parse link: (TYPE atom1 atom2 ... [truth_value])
          # This would require recursive parsing - simplified for now
          return Link.new(type, [] of Atom)
        end
      rescue
        return nil
      end

      nil
    end

    # Load all atoms from file
    private def load_all_atoms : Array(Atom)
      atoms = [] of Atom
      return atoms unless File.exists?(@file_path)

      File.each_line(@file_path) do |line|
        line = line.strip
        next if line.empty? || line.starts_with?(';')

        atom = scheme_to_atom(line)
        atoms << atom if atom
      end

      atoms
    end
    
    # Rebuild the in-memory index from file
    private def rebuild_index
      @atom_index.clear
      return unless File.exists?(@file_path)
      
      File.each_line(@file_path) do |line|
        line = line.strip
        next if line.empty? || line.starts_with?(';')
        
        atom = scheme_to_atom(line)
        if atom
          @atom_index[atom.handle] = atom
        end
      end
      
      log_debug("Rebuilt index with #{@atom_index.size} atoms")
    end
  end

  # SQLite-based storage implementation
  class SQLiteStorageNode < StorageNode
    @db_path : String
    @db : DB::Database?
    @connected : Bool = false

    def initialize(name : String, @db_path : String)
      super(name)
      log_info("SQLiteStorageNode created for: #{@db_path}")
    end

    def open : Bool
      return true if @connected

      begin
        # Ensure directory exists
        dir = File.dirname(@db_path)
        Dir.mkdir_p(dir) unless Dir.exists?(dir)

        @db = DB.open("sqlite3:#{@db_path}")
        create_tables

        @connected = true
        log_info("Opened SQLite storage: #{@db_path}")
        true
      rescue ex
        log_error("Failed to open SQLite storage: #{ex.message}")
        false
      end
    end

    def close : Bool
      if @db
        @db.try(&.close)
        @db = nil
      end
      @connected = false
      log_info("Closed SQLite storage: #{@db_path}")
      true
    end

    def connected? : Bool
      @connected
    end

    def store_atom(atom : Atom) : Bool
      return false unless @connected || !@db

      begin
        db = @db.not_nil!

        case atom
        when Node
          db.exec(
            "INSERT OR REPLACE INTO atoms (handle, type, name, truth_strength, truth_confidence) VALUES (?, ?, ?, ?, ?)",
            atom.handle.to_s, atom.type.to_s, atom.name,
            atom.truth_value.strength, atom.truth_value.confidence
          )
        when Link
          # Store the link
          db.exec(
            "INSERT OR REPLACE INTO atoms (handle, type, name, truth_strength, truth_confidence) VALUES (?, ?, ?, ?, ?)",
            atom.handle.to_s, atom.type.to_s, "",
            atom.truth_value.strength, atom.truth_value.confidence
          )

          # Store outgoing relationships
          db.exec("DELETE FROM outgoing WHERE link_handle = ?", atom.handle.to_s)
          atom.outgoing.each_with_index do |target, position|
            db.exec(
              "INSERT INTO outgoing (link_handle, target_handle, position) VALUES (?, ?, ?)",
              atom.handle.to_s, target.handle.to_s, position
            )
          end
        end

        log_debug("Stored atom in SQLite: #{atom}")
        true
      rescue ex
        log_error("Failed to store atom in SQLite: #{ex.message}")
        false
      end
    end

    def fetch_atom(handle : Handle) : Atom?
      return nil unless @connected || !@db

      begin
        db = @db.not_nil!

        # Get atom data
        db.query("SELECT type, name, truth_strength, truth_confidence FROM atoms WHERE handle = ?", handle.to_s) do |rs|
          if rs.move_next
            type = AtomType.parse(rs.read(String))
            name = rs.read(String)
            strength = rs.read(Float64)
            confidence = rs.read(Float64)
            tv = SimpleTruthValue.new(strength, confidence)

            if type.node?
              return Node.new(type, name, tv)
            else
              # Get outgoing atoms for links
              outgoing = [] of Atom
              db.query("SELECT target_handle FROM outgoing WHERE link_handle = ? ORDER BY position", handle.to_s) do |out_rs|
                while out_rs.move_next
                  target_handle = Handle.new(out_rs.read(String))
                  target_atom = fetch_atom(target_handle)
                  outgoing << target_atom if target_atom
                end
              end
              return Link.new(type, outgoing, tv)
            end
          end
        end

        nil
      rescue ex
        log_error("Failed to fetch atom from SQLite: #{ex.message}")
        nil
      end
    end

    def remove_atom(atom : Atom) : Bool
      return false unless @connected || !@db

      begin
        db = @db.not_nil!

        # Remove outgoing relationships if it's a link
        db.exec("DELETE FROM outgoing WHERE link_handle = ?", atom.handle.to_s)

        # Remove the atom
        db.exec("DELETE FROM atoms WHERE handle = ?", atom.handle.to_s)

        log_debug("Removed atom from SQLite: #{atom}")
        true
      rescue ex
        log_error("Failed to remove atom from SQLite: #{ex.message}")
        false
      end
    end

    def store_atomspace(atomspace : AtomSpace) : Bool
      return false unless @connected

      begin
        db = @db.not_nil!

        # Clear existing data
        db.exec("DELETE FROM outgoing")
        db.exec("DELETE FROM atoms")

        # Store all atoms
        atomspace.get_all_atoms.each do |atom|
          store_atom(atom)
        end

        log_info("Stored AtomSpace (#{atomspace.size} atoms) to SQLite: #{@db_path}")
        true
      rescue ex
        log_error("Failed to store AtomSpace to SQLite: #{ex.message}")
        false
      end
    end

    def load_atomspace(atomspace : AtomSpace) : Bool
      return false unless @connected || !@db

      begin
        db = @db.not_nil!
        count = 0

        # Load all atoms (nodes first, then links)
        db.query("SELECT handle FROM atoms ORDER BY CASE WHEN name = '' THEN 1 ELSE 0 END") do |rs|
          while rs.move_next
            handle = Handle.new(rs.read(String))
            atom = fetch_atom(handle)
            if atom
              atomspace.add_atom(atom)
              count += 1
            end
          end
        end

        log_info("Loaded #{count} atoms from SQLite: #{@db_path}")
        true
      rescue ex
        log_error("Failed to load AtomSpace from SQLite: #{ex.message}")
        false
      end
    end

    def get_stats : Hash(String, String | Int32 | Int64)
      stats = Hash(String, String | Int32 | Int64).new
      stats["type"] = "SQLiteStorage"
      stats["path"] = @db_path
      stats["connected"] = @connected ? "true" : "false"

      if @connected && @db
        begin
          db = @db.not_nil!
          db.query("SELECT COUNT(*) FROM atoms") do |rs|
            stats["atom_count"] = rs.move_next ? rs.read(Int64) : 0_i64
          end
          db.query("SELECT COUNT(*) FROM outgoing") do |rs|
            stats["link_count"] = rs.move_next ? rs.read(Int64) : 0_i64
          end
        rescue ex
          log_error("Failed to get SQLite stats: #{ex.message}")
        end
      end

      if File.exists?(@db_path)
        stats["file_size"] = File.size(@db_path)
      end

      stats
    end

    private def create_tables
      return unless @db

      db = @db.not_nil!

      # Create atoms table
      db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS atoms (
          handle TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          name TEXT,
          truth_strength REAL DEFAULT 1.0,
          truth_confidence REAL DEFAULT 1.0,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      SQL

      # Create outgoing relationships table
      db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS outgoing (
          link_handle TEXT NOT NULL,
          target_handle TEXT NOT NULL,
          position INTEGER NOT NULL,
          PRIMARY KEY (link_handle, position),
          FOREIGN KEY (link_handle) REFERENCES atoms(handle),
          FOREIGN KEY (target_handle) REFERENCES atoms(handle)
        )
      SQL

      # Create indexes for performance
      db.exec "CREATE INDEX IF NOT EXISTS idx_atoms_type ON atoms(type)"
      db.exec "CREATE INDEX IF NOT EXISTS idx_atoms_name ON atoms(name)"
      db.exec "CREATE INDEX IF NOT EXISTS idx_outgoing_target ON outgoing(target_handle)"

      log_debug("Created SQLite tables and indexes")
    end
  end

  # Network storage implementation (for CogServer communication)
  class CogStorageNode < StorageNode
    @host : String
    @port : Int32
    @connected : Bool = false
    @base_url : String

    def initialize(name : String, @host : String, @port : Int32)
      super(name)
      @base_url = "http://#{@host}:#{@port}"
      log_info("CogStorageNode created for: #{@base_url}")
    end

    def open : Bool
      return true if @connected

      begin
        # Test connection with ping
        response = HTTP::Client.get("#{@base_url}/ping")

        if response.status_code == 200
          @connected = true
          log_info("Connected to CogServer: #{@base_url}")
          true
        else
          log_error("Failed to connect to CogServer: status #{response.status_code}")
          false
        end
      rescue ex
        log_error("Failed to connect to CogServer: #{ex.message}")
        false
      end
    end

    def close : Bool
      @connected = false
      log_info("Disconnected from CogServer: #{@base_url}")
      true
    end

    def connected? : Bool
      @connected
    end

    def store_atom(atom : Atom) : Bool
      return false unless @connected

      begin
        data = {
          "type"        => atom.type.to_s,
          "name"        => atom.responds_to?(:name) ? atom.name : nil,
          "outgoing"    => atom.responds_to?(:outgoing) ? atom.outgoing.map(&.handle.to_s) : nil,
          "truth_value" => {
            "strength"   => atom.truth_value.strength,
            "confidence" => atom.truth_value.confidence,
          },
        }

        headers = HTTP::Headers{"Content-Type" => "application/json"}
        response = HTTP::Client.post("#{@base_url}/atoms", headers: headers, body: data.to_json)

        if response.status_code == 201
          log_debug("Stored atom via network: #{atom}")
          true
        else
          log_error("Failed to store atom via network: status #{response.status_code}")
          false
        end
      rescue ex
        log_error("Failed to store atom via network: #{ex.message}")
        false
      end
    end

    def fetch_atom(handle : Handle) : Atom?
      return nil unless @connected

      begin
        response = HTTP::Client.get("#{@base_url}/atoms/#{handle}")

        if response.status_code == 200
          # Parse JSON response and recreate atom
          # This would require proper JSON parsing and atom reconstruction
          log_debug("Fetched atom via network: #{handle}")
          nil # Simplified - would return actual atom
        else
          nil
        end
      rescue ex
        log_error("Failed to fetch atom via network: #{ex.message}")
        nil
      end
    end

    def remove_atom(atom : Atom) : Bool
      return false unless @connected

      begin
        response = HTTP::Client.delete("#{@base_url}/atoms/#{atom.handle}")

        response.status_code == 200
      rescue ex
        log_error("Failed to remove atom via network: #{ex.message}")
        false
      end
    end

    def store_atomspace(atomspace : AtomSpace) : Bool
      # Store atoms one by one
      atomspace.get_all_atoms.all? { |atom| store_atom(atom) }
    end

    def load_atomspace(atomspace : AtomSpace) : Bool
      return false unless @connected

      begin
        response = HTTP::Client.get("#{@base_url}/atoms")

        if response.status_code == 200
          data = JSON.parse(response.body)
          count = 0

          # This would require proper JSON parsing and atom reconstruction
          log_info("Loaded #{count} atoms from CogServer: #{@base_url}")
          true
        else
          false
        end
      rescue ex
        log_error("Failed to load AtomSpace from network: #{ex.message}")
        false
      end
    end

    def get_stats : Hash(String, String | Int32 | Int64)
      stats = Hash(String, String | Int32 | Int64).new
      stats["type"] = "CogStorage"
      stats["host"] = @host
      stats["port"] = @port
      stats["connected"] = @connected ? "true" : "false"
      stats["base_url"] = @base_url

      if @connected
        begin
          response = HTTP::Client.get("#{@base_url}/status")
          if response.status_code == 200
            server_stats = JSON.parse(response.body)
            stats["remote_atomspace_size"] = server_stats["atomspace_size"]?.try(&.as_i64) || 0_i64
          end
        rescue ex
          log_error("Failed to get network stats: #{ex.message}")
        end
      end

      stats
    end
  end

  # PostgreSQL-based storage implementation
  class PostgresStorageNode < StorageNode
    @connection_string : String
    @db : DB::Database?
    @connected : Bool = false

    def initialize(name : String, @connection_string : String)
      super(name)
      log_info("PostgresStorageNode created for: #{@connection_string}")
    end

    def open : Bool
      return true if @connected

      begin
        @db = DB.open("postgres://#{@connection_string}")
        create_tables
        @connected = true
        log_info("Opened PostgreSQL storage: #{@connection_string}")
        true
      rescue ex
        log_error("Failed to open PostgreSQL connection: #{ex.message}")
        false
      end
    end

    def close : Bool
      return true unless @connected

      begin
        @db.try(&.close)
        @db = nil
        @connected = false
        log_info("Closed PostgreSQL storage")
        true
      rescue ex
        log_error("Failed to close PostgreSQL connection: #{ex.message}")
        false
      end
    end

    def connected? : Bool
      @connected
    end

    def store_atom(atom : Atom) : Bool
      return false unless @connected || !@db

      begin
        db = @db.not_nil!
        
        # Store the atom
        tv = atom.truth_value
        db.exec(
          "INSERT INTO atoms (handle, type, name, truth_strength, truth_confidence) 
           VALUES ($1, $2, $3, $4, $5) 
           ON CONFLICT (handle) DO UPDATE SET 
           type = EXCLUDED.type, name = EXCLUDED.name, 
           truth_strength = EXCLUDED.truth_strength, 
           truth_confidence = EXCLUDED.truth_confidence",
          atom.handle.to_s, atom.type.to_s, 
          atom.is_a?(Node) ? atom.name : "",
          tv.strength, tv.confidence
        )

        # Store outgoing relationships for links
        if atom.is_a?(Link)
          # Remove existing outgoing relationships
          db.exec("DELETE FROM outgoing WHERE link_handle = $1", atom.handle.to_s)
          
          # Add new outgoing relationships
          atom.outgoing.each_with_index do |target, index|
            db.exec(
              "INSERT INTO outgoing (link_handle, target_handle, position) VALUES ($1, $2, $3)",
              atom.handle.to_s, target.handle.to_s, index
            )
          end
        end

        log_debug("Stored atom in PostgreSQL: #{atom}")
        true
      rescue ex
        log_error("Failed to store atom in PostgreSQL: #{ex.message}")
        false
      end
    end

    def fetch_atom(handle : Handle) : Atom?
      return nil unless @connected || !@db

      begin
        db = @db.not_nil!
        
        # Fetch atom basic info
        db.query(
          "SELECT type, name, truth_strength, truth_confidence FROM atoms WHERE handle = $1",
          handle.to_s
        ) do |rs|
          if rs.move_next
            type = AtomType.parse(rs.read(String))
            name = rs.read(String)
            strength = rs.read(Float64)
            confidence = rs.read(Float64)
            tv = SimpleTruthValue.new(strength, confidence)

            if type.node?
              return Node.new(type, name, tv)
            else
              # Fetch outgoing atoms for links
              outgoing = [] of Atom
              db.query(
                "SELECT target_handle FROM outgoing WHERE link_handle = $1 ORDER BY position",
                handle.to_s
              ) do |out_rs|
                while out_rs.move_next
                  target_handle = Handle.new(out_rs.read(String))
                  target_atom = fetch_atom(target_handle)
                  outgoing << target_atom if target_atom
                end
              end
              return Link.new(type, outgoing, tv)
            end
          end
        end

        nil
      rescue ex
        log_error("Failed to fetch atom from PostgreSQL: #{ex.message}")
        nil
      end
    end

    def remove_atom(atom : Atom) : Bool
      return false unless @connected || !@db

      begin
        db = @db.not_nil!

        # Remove outgoing relationships if it's a link
        db.exec("DELETE FROM outgoing WHERE link_handle = $1", atom.handle.to_s)

        # Remove the atom
        db.exec("DELETE FROM atoms WHERE handle = $1", atom.handle.to_s)

        log_debug("Removed atom from PostgreSQL: #{atom}")
        true
      rescue ex
        log_error("Failed to remove atom from PostgreSQL: #{ex.message}")
        false
      end
    end

    def store_atomspace(atomspace : AtomSpace) : Bool
      return false unless @connected

      begin
        db = @db.not_nil!

        # Clear existing data
        db.exec("DELETE FROM outgoing")
        db.exec("DELETE FROM atoms")

        # Store all atoms
        atomspace.get_all_atoms.each do |atom|
          store_atom(atom)
        end

        log_info("Stored AtomSpace (#{atomspace.size} atoms) to PostgreSQL: #{@connection_string}")
        true
      rescue ex
        log_error("Failed to store AtomSpace to PostgreSQL: #{ex.message}")
        false
      end
    end

    def load_atomspace(atomspace : AtomSpace) : Bool
      return false unless @connected || !@db

      begin
        db = @db.not_nil!
        count = 0

        # Load all atoms (nodes first, then links)
        db.query("SELECT handle FROM atoms ORDER BY CASE WHEN name = '' THEN 1 ELSE 0 END") do |rs|
          while rs.move_next
            handle = Handle.new(rs.read(String))
            atom = fetch_atom(handle)
            if atom
              atomspace.add_atom(atom)
              count += 1
            end
          end
        end

        log_info("Loaded #{count} atoms from PostgreSQL: #{@connection_string}")
        true
      rescue ex
        log_error("Failed to load AtomSpace from PostgreSQL: #{ex.message}")
        false
      end
    end

    def get_stats : Hash(String, String | Int32 | Int64)
      stats = Hash(String, String | Int32 | Int64).new
      stats["type"] = "PostgreSQLStorage"
      stats["connection_string"] = @connection_string
      stats["connected"] = @connected ? "true" : "false"

      if @connected && @db
        begin
          db = @db.not_nil!
          db.query("SELECT COUNT(*) FROM atoms") do |rs|
            stats["atom_count"] = rs.move_next ? rs.read(Int64) : 0_i64
          end
          db.query("SELECT COUNT(*) FROM outgoing") do |rs|
            stats["outgoing_count"] = rs.move_next ? rs.read(Int64) : 0_i64
          end
        rescue ex
          log_error("Failed to get PostgreSQL stats: #{ex.message}")
        end
      end

      stats
    end

    private def create_tables
      db = @db.not_nil!

      # Create atoms table
      db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS atoms (
          handle TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          name TEXT,
          truth_strength REAL DEFAULT 1.0,
          truth_confidence REAL DEFAULT 1.0,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      SQL

      # Create outgoing relationships table
      db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS outgoing (
          link_handle TEXT NOT NULL,
          target_handle TEXT NOT NULL,
          position INTEGER NOT NULL,
          PRIMARY KEY (link_handle, position),
          FOREIGN KEY (link_handle) REFERENCES atoms(handle),
          FOREIGN KEY (target_handle) REFERENCES atoms(handle)
        )
      SQL

      # Create indexes for performance
      db.exec "CREATE INDEX IF NOT EXISTS idx_atoms_type ON atoms(type)"
      db.exec "CREATE INDEX IF NOT EXISTS idx_atoms_name ON atoms(name)"
      db.exec "CREATE INDEX IF NOT EXISTS idx_outgoing_target ON outgoing(target_handle)"

      log_debug("Created PostgreSQL tables and indexes")
    end
  end

  # RocksDB-based storage implementation
  class RocksDBStorageNode < StorageNode
    @db_path : String
    @db : RocksDB::Database?
    @connected : Bool = false

    def initialize(name : String, @db_path : String)
      super(name)
      log_info("RocksDBStorageNode created for: #{@db_path}")
    end

    def open : Bool
      return true if @connected

      begin
        # Ensure directory exists
        dir = File.dirname(@db_path)
        Dir.mkdir_p(dir) unless Dir.exists?(dir)

        @db = RocksDB::Database.new(@db_path)
        @connected = true
        log_info("Opened RocksDB storage: #{@db_path}")
        true
      rescue ex
        log_error("Failed to open RocksDB: #{ex.message}")
        false
      end
    end

    def close : Bool
      return true unless @connected

      begin
        @db.try(&.close)
        @db = nil
        @connected = false
        log_info("Closed RocksDB storage")
        true
      rescue ex
        log_error("Failed to close RocksDB: #{ex.message}")
        false
      end
    end

    def connected? : Bool
      @connected
    end

    def store_atom(atom : Atom) : Bool
      return false unless @connected || !@db

      begin
        db = @db.not_nil!
        
        # Serialize atom to JSON
        atom_data = {
          "handle" => atom.handle.to_s,
          "type" => atom.type.to_s,
          "name" => atom.is_a?(Node) ? atom.name : "",
          "truth_strength" => atom.truth_value.strength,
          "truth_confidence" => atom.truth_value.confidence,
          "outgoing" => atom.is_a?(Link) ? atom.outgoing.map(&.handle.to_s) : [] of String
        }
        
        # Store with handle as key
        db.put("atom:#{atom.handle}", atom_data.to_json)
        
        # Create type index
        db.put("type:#{atom.type}:#{atom.handle}", "1")
        
        # Create name index for nodes
        if atom.is_a?(Node) && !atom.name.empty?
          db.put("name:#{atom.name}:#{atom.handle}", "1")
        end

        log_debug("Stored atom in RocksDB: #{atom}")
        true
      rescue ex
        log_error("Failed to store atom in RocksDB: #{ex.message}")
        false
      end
    end

    def fetch_atom(handle : Handle) : Atom?
      return nil unless @connected || !@db

      begin
        db = @db.not_nil!
        
        # Fetch atom data
        json_data = db.get("atom:#{handle}")
        return nil unless json_data
        
        data = JSON.parse(json_data)
        type = AtomType.parse(data["type"].as_s)
        strength = data["truth_strength"].as_f
        confidence = data["truth_confidence"].as_f
        tv = SimpleTruthValue.new(strength, confidence)
        
        if type.node?
          name = data["name"].as_s
          return Node.new(type, name, tv)
        else
          # Reconstruct outgoing atoms for links
          outgoing_handles = data["outgoing"].as_a.map { |h| Handle.new(h.as_s) }
          outgoing = [] of Atom
          outgoing_handles.each do |h| 
            atom = fetch_atom(h)
            outgoing << atom if atom
          end
          return Link.new(type, outgoing, tv)
        end
      rescue ex
        log_error("Failed to fetch atom from RocksDB: #{ex.message}")
        nil
      end
    end

    def remove_atom(atom : Atom) : Bool
      return false unless @connected || !@db

      begin
        db = @db.not_nil!

        # Remove main atom entry
        db.delete("atom:#{atom.handle}")
        
        # Remove type index
        db.delete("type:#{atom.type}:#{atom.handle}")
        
        # Remove name index for nodes
        if atom.is_a?(Node) && !atom.name.empty?
          db.delete("name:#{atom.name}:#{atom.handle}")
        end

        log_debug("Removed atom from RocksDB: #{atom}")
        true
      rescue ex
        log_error("Failed to remove atom from RocksDB: #{ex.message}")
        false
      end
    end

    def store_atomspace(atomspace : AtomSpace) : Bool
      return false unless @connected

      begin
        # Clear existing data (we could implement a more efficient batch delete)
        db = @db.not_nil!
        db.each_key do |key|
          db.delete(key) if key.starts_with?("atom:") || key.starts_with?("type:") || key.starts_with?("name:")
        end

        # Store all atoms
        atomspace.get_all_atoms.each do |atom|
          store_atom(atom)
        end

        log_info("Stored AtomSpace (#{atomspace.size} atoms) to RocksDB: #{@db_path}")
        true
      rescue ex
        log_error("Failed to store AtomSpace to RocksDB: #{ex.message}")
        false
      end
    end

    def load_atomspace(atomspace : AtomSpace) : Bool
      return false unless @connected || !@db

      begin
        db = @db.not_nil!
        count = 0
        handle_mapping = {} of Handle => Atom

        # First pass: Load all nodes (no recursion risk)
        node_handles = [] of Handle
        link_data = {} of Handle => JSON::Any
        
        db.each_key do |key|
          if key.starts_with?("atom:")
            handle_str = key[5..]  # Remove "atom:" prefix
            handle = Handle.new(handle_str)
            
            json_data = db.get(key)
            next unless json_data
            
            data = JSON.parse(json_data)
            type = AtomType.parse(data["type"].as_s)
            
            if type.node?
              # Load nodes immediately and create handle mapping
              strength = data["truth_strength"].as_f
              confidence = data["truth_confidence"].as_f
              tv = SimpleTruthValue.new(strength, confidence)
              name = data["name"].as_s
              
              node = Node.new(type, name, tv)
              new_atom = atomspace.add_atom(node)
              handle_mapping[handle] = new_atom
              count += 1
            else
              # Store link data for second pass
              link_data[handle] = data
            end
          end
        end
        
        # Second pass: Load all links using handle mapping
        link_data.each do |original_handle, data|
          type = AtomType.parse(data["type"].as_s)
          strength = data["truth_strength"].as_f
          confidence = data["truth_confidence"].as_f
          tv = SimpleTruthValue.new(strength, confidence)
          
          # Build outgoing array using handle mapping
          outgoing_handles = data["outgoing"].as_a.map { |h| Handle.new(h.as_s) }
          outgoing = [] of Atom
          
          outgoing_handles.each do |old_handle|
            # Use handle mapping to find the new atom
            mapped_atom = handle_mapping[old_handle]?
            outgoing << mapped_atom if mapped_atom
          end
          
          link = Link.new(type, outgoing, tv)
          new_link = atomspace.add_atom(link)
          handle_mapping[original_handle] = new_link
          count += 1
        end

        log_info("Loaded #{count} atoms from RocksDB: #{@db_path}")
        true
      rescue ex
        log_error("Failed to load AtomSpace from RocksDB: #{ex.message}")
        false
      end
    end

    def get_stats : Hash(String, String | Int32 | Int64)
      stats = Hash(String, String | Int32 | Int64).new
      stats["type"] = "RocksDBStorage"
      stats["path"] = @db_path
      stats["connected"] = @connected ? "true" : "false"

      if @connected && @db
        begin
          # Count atoms by iterating through keys
          atom_count = 0_i64
          type_count = 0_i64
          name_count = 0_i64
          
          db = @db.not_nil!
          db.each_key do |key|
            if key.starts_with?("atom:")
              atom_count += 1
            elsif key.starts_with?("type:")
              type_count += 1  
            elsif key.starts_with?("name:")
              name_count += 1
            end
          end
          
          stats["atom_count"] = atom_count
          stats["type_index_count"] = type_count
          stats["name_index_count"] = name_count
        rescue ex
          log_error("Failed to get RocksDB stats: #{ex.message}")
        end
      end

      stats
    end

    def fetch_atoms_by_type(type : AtomType) : Array(Atom)
      atoms = [] of Atom
      return atoms unless @connected || !@db

      begin
        db = @db.not_nil!
        
        # Use type index to find atoms efficiently
        db.each_key do |key|
          if key.starts_with?("type:#{type}:")
            handle_str = key.split(":")[2]
            handle = Handle.new(handle_str)
            atom = fetch_atom(handle)
            atoms << atom if atom
          end
        end
      rescue ex
        log_error("Failed to fetch atoms by type from RocksDB: #{ex.message}")
      end

      atoms
    end
  end

  # Hypergraph state representation
  record HypergraphState, atomspace : AtomSpace, tensor_shape : Array(Int32),
    attention : Float64, meta_level : Int32,
    cognitive_operation : String?, timestamp : Time

  # Hypergraph state persistence implementation
  class HypergraphStateStorageNode < StorageNode
    @storage_path : String
    @connected : Bool = false
    @backend_storage : StorageNode?

    def initialize(name : String, @storage_path : String, backend_type : String = "file")
      super(name)
      @backend_storage = create_backend_storage(backend_type, @storage_path)
      log_info("HypergraphStateStorageNode created with #{backend_type} backend: #{@storage_path}")
    end

    private def create_backend_storage(backend_type : String, path : String) : StorageNode
      case backend_type.downcase
      when "file"
        FileStorageNode.new("#{name}_file", path)
      when "sqlite", "db"
        SQLiteStorageNode.new("#{name}_sqlite", path)
      else
        FileStorageNode.new("#{name}_file", path)
      end
    end

    def open : Bool
      return true if @connected

      backend = @backend_storage
      return false unless backend

      if backend.open
        @connected = true
        log_info("Opened hypergraph state storage: #{@storage_path}")
        true
      else
        log_error("Failed to open backend storage")
        false
      end
    end

    def close : Bool
      backend = @backend_storage
      backend.try(&.close)
      @connected = false
      log_info("Closed hypergraph state storage: #{@storage_path}")
      true
    end

    def connected? : Bool
      @connected
    end

    # Store complete hypergraph state
    def store_hypergraph_state(state : HypergraphState) : Bool
      return false unless @connected

      begin
        # Serialize hypergraph state to JSON-like format
        state_data = serialize_hypergraph_state(state)

        # Create a special atom to represent the hypergraph state
        state_atom = Node.new(AtomType::CONCEPT_NODE, "HYPERGRAPH_STATE_#{state.timestamp.to_unix}")
        state_atom.truth_value = SimpleTruthValue.new(1.0, 1.0)

        backend = @backend_storage
        return false unless backend

        # Store the atomspace content first
        unless backend.store_atomspace(state.atomspace)
          log_error("Failed to store atomspace content")
          return false
        end

        # Store the hypergraph state metadata
        if store_hypergraph_metadata(state_data)
          log_info("Stored hypergraph state: tensor_shape=#{state.tensor_shape}, attention=#{state.attention}")
          true
        else
          log_error("Failed to store hypergraph metadata")
          false
        end
      rescue ex
        log_error("Failed to store hypergraph state: #{ex.message}")
        false
      end
    end

    # Load complete hypergraph state
    def load_hypergraph_state(target_atomspace : AtomSpace) : HypergraphState?
      return nil unless @connected

      begin
        backend = @backend_storage
        return nil unless backend

        # Load atomspace content
        unless backend.load_atomspace(target_atomspace)
          log_error("Failed to load atomspace content")
          return nil
        end

        # Load hypergraph state metadata
        metadata = load_hypergraph_metadata
        return nil unless metadata

        # Reconstruct hypergraph state
        state = HypergraphState.new(
          atomspace: target_atomspace,
          tensor_shape: metadata["tensor_shape"].as(Array(Int32)),
          attention: metadata["attention"].as(Float64),
          meta_level: metadata["meta_level"].as(Int32),
          cognitive_operation: metadata["cognitive_operation"]?.as(String?),
          timestamp: Time.unix(metadata["timestamp"].as(Int64))
        )

        log_info("Loaded hypergraph state: tensor_shape=#{state.tensor_shape}, attention=#{state.attention}")
        state
      rescue ex
        log_error("Failed to load hypergraph state: #{ex.message}")
        nil
      end
    end

    # Standard StorageNode interface (delegated to backend)
    def store_atom(atom : Atom) : Bool
      backend = @backend_storage
      return false unless backend && @connected
      backend.store_atom(atom)
    end

    def fetch_atom(handle : Handle) : Atom?
      backend = @backend_storage
      return nil unless backend && @connected
      backend.fetch_atom(handle)
    end

    def remove_atom(atom : Atom) : Bool
      backend = @backend_storage
      return false unless backend && @connected
      backend.remove_atom(atom)
    end

    def store_atomspace(atomspace : AtomSpace) : Bool
      backend = @backend_storage
      return false unless backend && @connected
      backend.store_atomspace(atomspace)
    end

    def load_atomspace(atomspace : AtomSpace) : Bool
      backend = @backend_storage
      return false unless backend && @connected
      backend.load_atomspace(atomspace)
    end

    def get_stats : Hash(String, String | Int32 | Int64)
      stats = Hash(String, String | Int32 | Int64).new
      stats["type"] = "HypergraphStateStorage"
      stats["path"] = @storage_path
      stats["connected"] = @connected ? "true" : "false"

      backend = @backend_storage
      if backend
        backend_stats = backend.get_stats
        stats["backend_type"] = backend_stats["type"]
        stats["backend_connected"] = backend_stats["connected"]
      end

      stats
    end

    private def serialize_hypergraph_state(state : HypergraphState) : Hash(String, JSON::Any)
      data = Hash(String, JSON::Any).new
      data["tensor_shape"] = JSON::Any.new(state.tensor_shape.map(&.as(JSON::Any)))
      data["attention"] = JSON::Any.new(state.attention)
      data["meta_level"] = JSON::Any.new(state.meta_level)
      data["cognitive_operation"] = JSON::Any.new(state.cognitive_operation)
      data["timestamp"] = JSON::Any.new(state.timestamp.to_unix)
      data["atomspace_size"] = JSON::Any.new(state.atomspace.size.to_i64)
      data
    end

    private def store_hypergraph_metadata(data : Hash(String, JSON::Any)) : Bool
      metadata_path = get_metadata_path

      begin
        File.open(metadata_path, "w") do |file|
          file.puts(data.to_json)
        end
        true
      rescue ex
        log_error("Failed to store hypergraph metadata: #{ex.message}")
        false
      end
    end

    private def load_hypergraph_metadata : Hash(String, JSON::Any)?
      metadata_path = get_metadata_path

      return nil unless File.exists?(metadata_path)

      begin
        content = File.read(metadata_path)
        JSON.parse(content).as_h
      rescue ex
        log_error("Failed to load hypergraph metadata: #{ex.message}")
        nil
      end
    end

    private def get_metadata_path : String
      case @storage_path
      when .ends_with?(".scm")
        @storage_path.sub(".scm", "_metadata.json")
      when .ends_with?(".db")
        @storage_path.sub(".db", "_metadata.json")
      else
        "#{@storage_path}_metadata.json"
      end
    end
  end
end
