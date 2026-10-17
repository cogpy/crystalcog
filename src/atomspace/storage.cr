# Crystal implementation of AtomSpace persistence interfaces
# Based on atomspace/opencog/persist/api/StorageNode.h
#
# This provides the base interface for persistent storage of AtomSpace contents.
#
# Database dependencies can be disabled at compile time using environment variables:
#   DISABLE_SQLITE3=1  - Disable SQLite3 support
#   DISABLE_POSTGRES=1 - Disable PostgreSQL support
#   DISABLE_ROCKSDB=1  - Disable RocksDB support (see rocksdb.cr)
#
# When all database backends are disabled, use MemoryStorageNode or FileStorageNode.

require "./atom"
require "./truthvalue"
require "./scheme_storage_parser"
require "../cogutil/cogutil"
require "../rocksdb"

# Conditionally require database libraries based on environment variables
{% unless env("DISABLE_SQLITE3") == "1" %}
  require "sqlite3"
{% end %}

{% unless env("DISABLE_POSTGRES") == "1" %}
  require "pg"
{% end %}

# Always require db and json for common functionality
require "db"
require "json"
require "http/client"

module AtomSpace
  # Database connection pool for improved concurrency and throughput
  class ConnectionPool
    @pool : Array(DB::Database)
    @available : Channel(DB::Database)
    @size : Int32
    @connection_string : String
    @mutex : Mutex

    def initialize(@connection_string : String, @size : Int32 = 10)
      @pool = Array(DB::Database).new
      @available = Channel(DB::Database).new(@size)
      @mutex = Mutex.new

      # Initialize pool with connections
      @size.times do
        conn = DB.open(@connection_string)
        @pool << conn
        @available.send(conn)
      end
    end

    # Acquire a connection from the pool (blocks if none available)
    def acquire : DB::Database
      @available.receive
    end

    # Release a connection back to the pool
    def release(conn : DB::Database)
      @available.send(conn)
    end

    # Execute a block with a connection from the pool
    def with_connection(&block : DB::Database -> T) : T forall T
      conn = acquire
      begin
        yield conn
      ensure
        release(conn)
      end
    end

    # Close all connections in the pool
    def close
      @mutex.synchronize do
        @pool.each(&.close)
        @pool.clear
      end
    end

    # Get pool statistics
    def stats : Hash(String, Int32)
      {
        "size"      => @size,
        "available" => @available.size,
        "in_use"    => @size - @available.size,
      }
    end
  end

  # Base interface for persistent storage
  # Implements AtomResolver for lazy loading support
  abstract class StorageNode < Node
    include AtomResolver

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

    # AtomResolver interface implementation - used by lazy loading
    def resolve_atom(handle : Handle) : Atom?
      fetch_atom(handle)
    end

    # Fetch a link with lazy loading (defers loading of outgoing atoms)
    def fetch_link_lazy(handle : Handle) : LazyLink?
      # Default implementation - subclasses can override for optimized loading
      atom = fetch_atom(handle)
      return nil unless atom
      return nil unless atom.is_a?(Link)

      # Convert regular link to lazy link
      link = atom.as(Link)
      outgoing_handles = link.outgoing.map(&.handle)
      lazy_link = LazyLink.new(link.type, outgoing_handles, link.truth_value, self)
      lazy_link
    end

    # Bulk operations
    def store_atoms(atoms : Array(Atom)) : Bool
      success = true
      atoms.each do |atom|
        success = false unless store_atom(atom)
      end
      success
    end

    # Batch operations with transaction support (default implementation)
    # Subclasses should override with proper transaction handling
    def store_atoms_batch(atoms : Array(Atom)) : Bool
      store_atoms(atoms)
    end

    # Fetch multiple atoms by handles
    def fetch_atoms_batch(handles : Array(Handle)) : Array(Atom)
      handles.compact_map { |h| fetch_atom(h) }
    end

    # Fetch multiple links with lazy loading
    def fetch_links_lazy_batch(handles : Array(Handle)) : Array(LazyLink)
      handles.compact_map { |h| fetch_link_lazy(h) }
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

        # Validate the entire document before exposing a connected store. A bad
        # file must not leave a silently partial in-memory index behind.
        rebuild_index

        @connected = true
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
        # Appending a revision would leave conflicting copies on reopening.
        # Replace the logical atom in a complete, validated persistence image.
        topology_key = atom_topology_key(atom)
        atoms = @atom_index.values.reject { |stored| atom_topology_key(stored) == topology_key }
        atoms << atom
        validate_snapshot_consistency(atoms)
        write_atoms(atoms)

        # Update index
        @atom_index.reject! { |_, stored| atom_topology_key(stored) == topology_key }
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
        remaining = @atom_index.values.reject { |stored| stored.handle == atom.handle }
        write_atoms(remaining)
        @atom_index.delete(atom.handle)

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
        atoms = atomspace.get_all_atoms
        # Render before replacing the current file so unsupported metadata cannot
        # turn a failed store into a truncated persistence file.
        write_atoms(atoms)
        @atom_index.clear
        atoms.each { |atom| @atom_index[atom.handle] = atom }

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
        # Parsing is a complete, detached phase. Do not call AtomSpace#add_atom
        # until every expression has been validated, avoiding partial mutation on
        # malformed input.
        parsed_atoms = parse_file
        validate_snapshot_consistency(parsed_atoms)
        canonical_atoms = Hash(String, Atom).new
        loaded_atoms = parsed_atoms.map { |atom| canonicalize_atom(atom, atomspace, canonical_atoms) }

        # `fetch_atom` should return the canonical instances made visible by this
        # load, not the transient parser graph.
        @atom_index.clear
        canonical_atoms.each_value { |atom| @atom_index[atom.handle] = atom }

        log_info("Loaded #{loaded_atoms.size} root atoms from: #{@file_path}")
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

    # Serialize a complete recursive atom expression. Each top-level AtomSpace
    # atom is also written independently, so a reader can rebuild an index while
    # nested expressions retain graph topology for a standalone round trip.
    private def atom_to_scheme(atom : Atom, depth : Int32 = 1) : String
      if depth > SchemeStorageParser::MAX_NESTING
        raise ArgumentError.new("FileStorage atom nesting exceeds #{SchemeStorageParser::MAX_NESTING}")
      end

      if atom.is_a?(Node)
        if atom.type == AtomType::NUMBER_NODE
          number = atom.name.to_f64?
          unless number && number.finite?
            raise ArgumentError.new("FileStorage NumberNode must contain a finite number")
          end
        end
        "(#{atom.type} \"#{escape_scheme_string(atom.name)}\"#{atom_metadata_to_scheme(atom)})"
      elsif atom.link?
        outgoing = atom.outgoing.map { |child| atom_to_scheme(child, depth + 1) }.join(" ")
        body = outgoing.empty? ? atom.type.to_s : "#{atom.type} #{outgoing}"
        "(#{body}#{atom_metadata_to_scheme(atom)})"
      else
        raise ArgumentError.new("FileStorage cannot serialize unsupported atom #{atom}")
      end
    end

    private def atom_metadata_to_scheme(atom : Atom) : String
      metadata = [] of String
      truth_value = atom.truth_value
      metadata << truth_value_to_scheme(truth_value) unless default_simple_truth_value?(truth_value)

      if attention = atom.attention_value
        metadata << "(av #{attention.sti} #{attention.lti} #{attention.vlti})"
      end

      metadata.empty? ? "" : " #{metadata.join(" ")}"
    end

    # Do not rely on TruthValue#== here: some subclasses carry fields beyond
    # strength/confidence. Omitting their tag would silently erase that metadata.
    private def default_simple_truth_value?(truth_value : TruthValue) : Bool
      truth_value.is_a?(SimpleTruthValue) && !truth_value.is_a?(FuzzyTruthValue) &&
        truth_value.strength == 1.0 && truth_value.confidence == 0.0
    end

    private def truth_value_to_scheme(truth_value : TruthValue) : String
      if (truth_value.is_a?(CountTruthValue) && !truth_value.count.finite?) ||
         (truth_value.is_a?(FuzzyTruthValue) && !truth_value.uncertainty.finite?)
        raise ArgumentError.new("FileStorage truth metadata must contain finite numbers")
      end

      case truth_value
      when FuzzyTruthValue
        "(tv FuzzyTruthValue #{truth_value.strength} #{truth_value.confidence} #{truth_value.uncertainty})"
      when CountTruthValue
        "(tv CountTruthValue #{truth_value.strength} #{truth_value.confidence} #{truth_value.count})"
      when IndefiniteTruthValue
        "(tv IndefiniteTruthValue #{truth_value.lower} #{truth_value.upper} #{truth_value.confidence})"
      when SimpleTruthValue
        "(tv SimpleTruthValue #{truth_value.strength} #{truth_value.confidence})"
      else
        raise ArgumentError.new("FileStorage cannot serialize truth value #{truth_value.type_name}")
      end
    end

    private def escape_scheme_string(value : String) : String
      String.build do |io|
        value.each_char do |char|
          case char
          when '"'
            io << "\\\""
          when '\\'
            io << "\\\\"
          when '\n'
            io << "\\n"
          when '\r'
            io << "\\r"
          when '\t'
            io << "\\t"
          when '\b'
            io << "\\b"
          when '\f'
            io << "\\f"
          else
            if char.ord < 0x20
              io << "\\u" << char.ord.to_s(16).rjust(4, '0')
            else
              io << char
            end
          end
        end
      end
    end

    # Parse first and only then insert. The parser creates detached Atom objects;
    # this method recursively replaces every child with AtomSpace#add_atom's
    # canonical object, preserving sharing, outgoing order, and incoming indexes.
    # A snapshot writes both a top-level atom and nested copies of that atom, so
    # cache by topology to guarantee its persisted truth value is inserted once.
    private def canonicalize_atom(atom : Atom, atomspace : AtomSpace,
                                  canonical_atoms : Hash(String, Atom)) : Atom
      topology_key = atom_topology_key(atom)
      if cached = canonical_atoms[topology_key]?
        return cached
      end

      case atom
      when Node
        canonical = atomspace.add_atom(atom)
        canonical.attention_value = atom.attention_value if atom.attention_value
        canonical_atoms[topology_key] = canonical
        canonical
      when Link
        outgoing = atom.outgoing.map { |child| canonicalize_atom(child, atomspace, canonical_atoms) }
        candidate = Link.new(atom.type, outgoing, atom.truth_value)
        candidate.attention_value = atom.attention_value
        canonical = atomspace.add_atom(candidate)
        canonical.attention_value = atom.attention_value if atom.attention_value
        canonical_atoms[topology_key] = canonical
        canonical
      else
        raise ArgumentError.new("FileStorage cannot load unsupported atom #{atom}")
      end
    end

    # A well-formed AtomSpace snapshot may repeat a topology recursively, but it
    # must repeat its metadata exactly. Reject conflicts before insertion instead
    # of passing two values through AtomSpace's merge policy and changing either.
    private def validate_snapshot_consistency(atoms : Array(Atom))
      metadata_by_topology = Hash(String, String).new
      atoms.each { |atom| validate_atom_metadata(atom, metadata_by_topology) }
    end

    private def validate_atom_metadata(atom : Atom, metadata_by_topology : Hash(String, String))
      topology_key = atom_topology_key(atom)
      metadata = atom_metadata_to_scheme(atom)

      if existing_metadata = metadata_by_topology[topology_key]?
        unless existing_metadata == metadata
          raise SchemeStorageParseError.new("conflicting metadata for persisted #{atom.type}")
        end
      else
        metadata_by_topology[topology_key] = metadata
      end

      atom.outgoing.each { |child| validate_atom_metadata(child, metadata_by_topology) } if atom.link?
    end

    private def atom_topology_key(atom : Atom, depth : Int32 = 1) : String
      if depth > SchemeStorageParser::MAX_NESTING
        raise ArgumentError.new("FileStorage atom nesting exceeds #{SchemeStorageParser::MAX_NESTING}")
      end

      if atom.is_a?(Node)
        name = atom.name
        "node:#{atom.type}:#{name.bytesize}:#{name}"
      elsif atom.link?
        String.build do |io|
          io << "link:" << atom.type << ':'
          atom.outgoing.each do |child|
            key = atom_topology_key(child, depth + 1)
            io << key.bytesize << ':' << key
          end
        end
      else
        raise ArgumentError.new("FileStorage cannot key unsupported atom #{atom}")
      end
    end

    private def parse_file : Array(Atom)
      return [] of Atom unless File.exists?(@file_path)
      SchemeStorageParser.new(File.read(@file_path)).parse_document
    end

    # Render all expressions before swapping the file, so failed serialization
    # leaves the previous persistence image intact.
    private def write_atoms(atoms : Array(Atom))
      validate_snapshot_consistency(atoms)
      lines = atoms.map { |atom| atom_to_scheme(atom) }
      temporary_path = "#{@file_path}.tmp-#{Process.pid}"
      content = lines.join("\n")
      content += "\n" unless content.empty?

      begin
        File.write(temporary_path, content)
        File.rename(temporary_path, @file_path)
      ensure
        File.delete(temporary_path) if File.exists?(temporary_path)
      end
    end

    # Rebuild the storage-local index from a validated complete document. Handles
    # are process-local, so these entries are suitable for this open instance;
    # `load_atomspace` refreshes the index with target AtomSpace canonical atoms.
    private def rebuild_index
      atoms = parse_file
      validate_snapshot_consistency(atoms)
      transient_space = AtomSpace.new
      canonical_atoms = Hash(String, Atom).new
      atoms.each { |atom| canonicalize_atom(atom, transient_space, canonical_atoms) }
      @atom_index.clear
      canonical_atoms.each_value { |atom| @atom_index[atom.handle] = atom }
      log_debug("Rebuilt index with #{@atom_index.size} atoms")
    end
  end

  # In-memory storage implementation
  # This is a fallback storage backend that doesn't require any external libraries.
  # Useful for testing and platforms without database libraries.
  class MemoryStorageNode < StorageNode
    @atoms : Hash(Handle, Atom) = Hash(Handle, Atom).new
    @connected : Bool = false
    @mutex : Mutex = Mutex.new

    def initialize(name : String = "memory")
      super(name)
      log_info("MemoryStorageNode created")
    end

    def open : Bool
      @connected = true
      log_info("Opened in-memory storage")
      true
    end

    def close : Bool
      @connected = false
      @atoms.clear
      log_info("Closed in-memory storage")
      true
    end

    def connected? : Bool
      @connected
    end

    def store_atom(atom : Atom) : Bool
      return false unless @connected

      @mutex.synchronize do
        @atoms[atom.handle] = atom
      end

      log_debug("Stored atom in memory: #{atom}")
      true
    end

    def fetch_atom(handle : Handle) : Atom?
      return nil unless @connected

      @mutex.synchronize do
        @atoms[handle]?
      end
    end

    def remove_atom(atom : Atom) : Bool
      return false unless @connected

      @mutex.synchronize do
        @atoms.delete(atom.handle)
      end

      log_debug("Removed atom from memory: #{atom}")
      true
    end

    def store_atomspace(atomspace : AtomSpace) : Bool
      return false unless @connected

      @mutex.synchronize do
        @atoms.clear
        atomspace.get_all_atoms.each do |atom|
          @atoms[atom.handle] = atom
        end
      end

      log_info("Stored AtomSpace (#{atomspace.size} atoms) to memory")
      true
    end

    def load_atomspace(atomspace : AtomSpace) : Bool
      return false unless @connected

      count = 0
      @mutex.synchronize do
        @atoms.each_value do |atom|
          atomspace.add_atom(atom)
          count += 1
        end
      end

      log_info("Loaded #{count} atoms from memory")
      true
    end

    def get_stats : Hash(String, String | Int32 | Int64)
      stats = Hash(String, String | Int32 | Int64).new
      stats["type"] = "MemoryStorage"
      stats["connected"] = @connected ? "true" : "false"
      stats["atom_count"] = @atoms.size.to_i64
      stats
    end

    # Get all stored atoms (for debugging/testing)
    def all_atoms : Array(Atom)
      @mutex.synchronize do
        @atoms.values
      end
    end

    # Clear all stored atoms
    def clear
      @mutex.synchronize do
        @atoms.clear
      end
      log_debug("Cleared in-memory storage")
    end
  end

  # SQLite-based storage implementation with connection pooling
  # Only available when DISABLE_SQLITE3 is not set
  {% unless env("DISABLE_SQLITE3") == "1" %}
  class SQLiteStorageNode < StorageNode
    @db_path : String
    @db : DB::Database?
    @pool : ConnectionPool?
    @connected : Bool = false
    @use_pool : Bool
    @pool_size : Int32

    def initialize(name : String, @db_path : String, @use_pool : Bool = true, @pool_size : Int32 = 10)
      super(name)
      log_info("SQLiteStorageNode created for: #{@db_path} (pool: #{@use_pool})")
    end

    def open : Bool
      return true if @connected

      begin
        # Ensure directory exists
        dir = File.dirname(@db_path)
        Dir.mkdir_p(dir) unless Dir.exists?(dir)

        if @use_pool
          # Use connection pool for better concurrency
          @pool = ConnectionPool.new("sqlite3:#{@db_path}", @pool_size)
          # Keep one connection for compatibility
          @db = DB.open("sqlite3:#{@db_path}")
        else
          # Single connection mode
          @db = DB.open("sqlite3:#{@db_path}")
        end

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
      if @pool
        @pool.try(&.close)
        @pool = nil
      end
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

    # Batch store with transaction support for better performance
    def store_atoms_batch(atoms : Array(Atom)) : Bool
      return false unless @connected

      begin
        if @use_pool && @pool
          # Use connection from pool
          @pool.not_nil!.with_connection do |db|
            db.transaction do |tx|
              conn = tx.connection
              atoms.each do |atom|
                store_atom_in_connection(atom, conn)
              end
            end
          end
        else
          # Use single connection with transaction
          db = @db.not_nil!
          db.transaction do |tx|
            conn = tx.connection
            atoms.each do |atom|
              store_atom_in_connection(atom, conn)
            end
          end
        end

        log_info("Batch stored #{atoms.size} atoms to SQLite: #{@db_path}")
        true
      rescue ex
        log_error("Failed to batch store atoms to SQLite: #{ex.message}")
        false
      end
    end

    # Helper method to store atom using a specific connection
    private def store_atom_in_connection(atom : Atom, conn : DB::Connection) : Bool
      case atom
      when Node
        conn.exec(
          "INSERT OR REPLACE INTO atoms (handle, type, name, truth_strength, truth_confidence) VALUES (?, ?, ?, ?, ?)",
          atom.handle.to_s, atom.type.to_s, atom.name,
          atom.truth_value.strength, atom.truth_value.confidence
        )
      when Link
        # Store the link
        conn.exec(
          "INSERT OR REPLACE INTO atoms (handle, type, name, truth_strength, truth_confidence) VALUES (?, ?, ?, ?, ?)",
          atom.handle.to_s, atom.type.to_s, "",
          atom.truth_value.strength, atom.truth_value.confidence
        )

        # Store outgoing relationships
        conn.exec("DELETE FROM outgoing WHERE link_handle = ?", atom.handle.to_s)
        atom.outgoing.each_with_index do |target, position|
          conn.exec(
            "INSERT INTO outgoing (link_handle, target_handle, position) VALUES (?, ?, ?)",
            atom.handle.to_s, target.handle.to_s, position
          )
        end
      end
      true
    rescue ex
      log_error("Failed to store atom in connection: #{ex.message}")
      false
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
  {% else %}
  # SQLite3 is disabled - provide stub implementation
  class SQLiteStorageNode < StorageNode
    @db_path : String
    @connected : Bool = false

    def initialize(name : String, @db_path : String, use_pool : Bool = true, pool_size : Int32 = 10)
      super(name)
      CogUtil::Logger.warn("SQLiteStorageNode: SQLite3 support is disabled. Set DISABLE_SQLITE3=0 and rebuild.")
    end

    def open : Bool
      raise "SQLite3 support is disabled. Install libsqlite3-dev and rebuild without DISABLE_SQLITE3=1"
    end

    def close : Bool
      true
    end

    def connected? : Bool
      false
    end

    def store_atom(atom : Atom) : Bool
      raise "SQLite3 support is disabled"
    end

    def fetch_atom(handle : Handle) : Atom?
      raise "SQLite3 support is disabled"
    end

    def remove_atom(atom : Atom) : Bool
      raise "SQLite3 support is disabled"
    end

    def store_atomspace(atomspace : AtomSpace) : Bool
      raise "SQLite3 support is disabled"
    end

    def load_atomspace(atomspace : AtomSpace) : Bool
      raise "SQLite3 support is disabled"
    end

    def get_stats : Hash(String, String | Int32 | Int64)
      Hash(String, String | Int32 | Int64){"type" => "SQLiteStorage", "status" => "disabled"}
    end
  end
  {% end %}

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

  # PostgreSQL-based storage implementation with connection pooling
  # Only available when DISABLE_POSTGRES is not set
  {% unless env("DISABLE_POSTGRES") == "1" %}
  class PostgresStorageNode < StorageNode
    @connection_string : String
    @db : DB::Database?
    @pool : ConnectionPool?
    @connected : Bool = false
    @use_pool : Bool
    @pool_size : Int32

    def initialize(name : String, @connection_string : String, @use_pool : Bool = true, @pool_size : Int32 = 10)
      super(name)
      log_info("PostgresStorageNode created for: #{@connection_string} (pool: #{@use_pool})")
    end

    def open : Bool
      return true if @connected

      begin
        if @use_pool
          # Use connection pool for better concurrency
          @pool = ConnectionPool.new("postgres://#{@connection_string}", @pool_size)
          # Keep one connection for compatibility
          @db = DB.open("postgres://#{@connection_string}")
        else
          # Single connection mode
          @db = DB.open("postgres://#{@connection_string}")
        end

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
        if @pool
          @pool.try(&.close)
          @pool = nil
        end
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

    # Batch store with transaction support for better performance
    def store_atoms_batch(atoms : Array(Atom)) : Bool
      return false unless @connected

      begin
        if @use_pool && @pool
          # Use connection from pool
          @pool.not_nil!.with_connection do |db|
            db.transaction do |tx|
              conn = tx.connection
              atoms.each do |atom|
                store_atom_in_connection(atom, conn)
              end
            end
          end
        else
          # Use single connection with transaction
          db = @db.not_nil!
          db.transaction do |tx|
            conn = tx.connection
            atoms.each do |atom|
              store_atom_in_connection(atom, conn)
            end
          end
        end

        log_info("Batch stored #{atoms.size} atoms to PostgreSQL: #{@connection_string}")
        true
      rescue ex
        log_error("Failed to batch store atoms to PostgreSQL: #{ex.message}")
        false
      end
    end

    # Helper method to store atom using a specific connection
    private def store_atom_in_connection(atom : Atom, conn : DB::Connection) : Bool
      tv = atom.truth_value
      conn.exec(
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
        conn.exec("DELETE FROM outgoing WHERE link_handle = $1", atom.handle.to_s)

        # Add new outgoing relationships
        atom.outgoing.each_with_index do |target, index|
          conn.exec(
            "INSERT INTO outgoing (link_handle, target_handle, position) VALUES ($1, $2, $3)",
            atom.handle.to_s, target.handle.to_s, index
          )
        end
      end
      true
    rescue ex
      log_error("Failed to store atom in connection: #{ex.message}")
      false
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
  {% else %}
  # PostgreSQL is disabled - provide stub implementation
  class PostgresStorageNode < StorageNode
    @connection_string : String
    @connected : Bool = false

    def initialize(name : String, @connection_string : String, use_pool : Bool = true, pool_size : Int32 = 10)
      super(name)
      CogUtil::Logger.warn("PostgresStorageNode: PostgreSQL support is disabled. Set DISABLE_POSTGRES=0 and rebuild.")
    end

    def open : Bool
      raise "PostgreSQL support is disabled. Install libpq-dev and rebuild without DISABLE_POSTGRES=1"
    end

    def close : Bool
      true
    end

    def connected? : Bool
      false
    end

    def store_atom(atom : Atom) : Bool
      raise "PostgreSQL support is disabled"
    end

    def fetch_atom(handle : Handle) : Atom?
      raise "PostgreSQL support is disabled"
    end

    def remove_atom(atom : Atom) : Bool
      raise "PostgreSQL support is disabled"
    end

    def store_atomspace(atomspace : AtomSpace) : Bool
      raise "PostgreSQL support is disabled"
    end

    def load_atomspace(atomspace : AtomSpace) : Bool
      raise "PostgreSQL support is disabled"
    end

    def get_stats : Hash(String, String | Int32 | Int64)
      Hash(String, String | Int32 | Int64){"type" => "PostgreSQLStorage", "status" => "disabled"}
    end
  end
  {% end %}

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
          "handle"           => atom.handle.to_s,
          "type"             => atom.type.to_s,
          "name"             => atom.is_a?(Node) ? atom.name : "",
          "truth_strength"   => atom.truth_value.strength,
          "truth_confidence" => atom.truth_value.confidence,
          "outgoing"         => atom.is_a?(Link) ? atom.outgoing.map(&.handle.to_s) : [] of String,
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
            handle_str = key[5..] # Remove "atom:" prefix
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

        # Reconstruct hypergraph state from JSON metadata
        op_json = metadata["cognitive_operation"]?
        cognitive_operation = if op_json && !op_json.raw.nil?
                                op_json.as_s
                              else
                                nil
                              end

        state = HypergraphState.new(
          atomspace: target_atomspace,
          tensor_shape: metadata["tensor_shape"].as_a.map(&.as_i),
          attention: metadata["attention"].as_f,
          meta_level: metadata["meta_level"].as_i,
          cognitive_operation: cognitive_operation,
          timestamp: Time.unix(metadata["timestamp"].as_i64)
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
      data["tensor_shape"] = JSON::Any.new(state.tensor_shape.map { |n| JSON::Any.new(n.to_i64) })
      data["attention"] = JSON::Any.new(state.attention)
      data["meta_level"] = JSON::Any.new(state.meta_level.to_i64)
      data["cognitive_operation"] = if op = state.cognitive_operation
                                     JSON::Any.new(op)
                                   else
                                     JSON::Any.new(nil)
                                   end
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
