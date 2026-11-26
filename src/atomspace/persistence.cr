# AtomSpace persistence extension.
#
# Kept separate from atomspace.cr so in-memory consumers do not link database
# drivers or distributed storage support.

require "./atomspace"
require "./storage"

module AtomSpace
  class AtomSpace
    @attached_storages : Array(StorageNode)?

    def create_file_storage(name : String, path : String, attach : Bool = true) : FileStorageNode
      storage = FileStorageNode.new(name, path)
      attach_storage(storage) if attach
      storage
    end

    def create_sqlite_storage(name : String, path : String, attach : Bool = true) : SQLiteStorageNode
      storage = SQLiteStorageNode.new(name, path)
      attach_storage(storage) if attach
      storage
    end

    def create_postgres_storage(name : String, connection_string : String, attach : Bool = false) : PostgresStorageNode
      storage = PostgresStorageNode.new(name, connection_string)
      attach_storage(storage) if attach
      storage
    end

    def create_rocksdb_storage(name : String, path : String, attach : Bool = false) : RocksDBStorageNode
      storage = RocksDBStorageNode.new(name, path)
      attach_storage(storage) if attach
      storage
    end

    def create_cog_storage(name : String, host : String, port : Int32, attach : Bool = true) : CogStorageNode
      storage = CogStorageNode.new(name, host, port)
      attach_storage(storage) if attach
      storage
    end

    def attach_storage(storage : StorageNode)
      @attached_storages ||= [] of StorageNode
      @attached_storages.not_nil! << storage
      CogUtil::Logger.info("Attached storage: #{storage.name}")
    end

    def detach_storage(storage : StorageNode)
      @attached_storages.try(&.delete(storage))
      CogUtil::Logger.info("Detached storage: #{storage.name}")
    end

    def get_attached_storages : Array(StorageNode)
      @attached_storages || [] of StorageNode
    end

    def store_all : Bool
      success = true
      get_attached_storages.each do |storage|
        success = false unless storage.store_atomspace(self)
      end
      success
    end

    def load_all : Bool
      success = true
      get_attached_storages.each do |storage|
        success = false unless storage.load_atomspace(self)
      end
      success
    end

    def store_to(storage : StorageNode) : Bool
      storage.store_atomspace(self)
    end

    def load_from(storage : StorageNode) : Bool
      storage.load_atomspace(self)
    end

    def create_hypergraph_storage(name : String, storage_path : String,
                                  backend_type : String = "file", attach : Bool = true) : HypergraphStateStorageNode
      storage = HypergraphStateStorageNode.new(name, storage_path, backend_type)
      attach_storage(storage) if attach
      storage
    end

    def extract_hypergraph_state(tensor_shape : Array(Int32), attention : Float64,
                                 meta_level : Int32 = 0, cognitive_operation : String? = nil) : HypergraphState
      HypergraphState.new(
        atomspace: self,
        tensor_shape: tensor_shape,
        attention: attention,
        meta_level: meta_level,
        cognitive_operation: cognitive_operation,
        timestamp: Time.utc
      )
    end

    def store_hypergraph_state(tensor_shape : Array(Int32), attention : Float64,
                               meta_level : Int32 = 0, cognitive_operation : String? = nil) : Bool
      state = extract_hypergraph_state(tensor_shape, attention, meta_level, cognitive_operation)
      success = true
      get_attached_storages.each do |storage|
        if storage.is_a?(HypergraphStateStorageNode)
          success = false unless storage.store_hypergraph_state(state)
        end
      end
      success
    end

    def load_hypergraph_state : HypergraphState?
      get_attached_storages.each do |storage|
        next unless storage.is_a?(HypergraphStateStorageNode)
        state = storage.load_hypergraph_state(self)
        return state if state
      end
      nil
    end

    def store_hypergraph_state_to(storage : HypergraphStateStorageNode, tensor_shape : Array(Int32),
                                  attention : Float64, meta_level : Int32 = 0,
                                  cognitive_operation : String? = nil) : Bool
      storage.store_hypergraph_state(
        extract_hypergraph_state(tensor_shape, attention, meta_level, cognitive_operation)
      )
    end

    def load_hypergraph_state_from(storage : HypergraphStateStorageNode) : HypergraphState?
      storage.load_hypergraph_state(self)
    end
  end
end
