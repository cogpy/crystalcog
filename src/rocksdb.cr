# Simple Crystal binding for RocksDB
# This provides basic functionality for AtomSpace persistence
# RocksDB can be disabled by setting DISABLE_ROCKSDB=1 environment variable

{% unless env("DISABLE_ROCKSDB") == "1" %}
  @[Link("rocksdb")]
{% end %}
lib LibRocksDB
  type DB = Void*
  type Options = Void*
  type ReadOptions = Void*
  type WriteOptions = Void*
  type Iterator = Void*
  
  # Database operations
  fun rocksdb_open = rocksdb_open(options : Options, name : UInt8*, errptr : UInt8**) : DB
  fun rocksdb_close = rocksdb_close(db : DB)
  
  # Options
  fun rocksdb_options_create = rocksdb_options_create() : Options
  fun rocksdb_options_destroy = rocksdb_options_destroy(options : Options)
  fun rocksdb_options_set_create_if_missing = rocksdb_options_set_create_if_missing(options : Options, value : Bool)
  
  # Read/Write options
  fun rocksdb_readoptions_create = rocksdb_readoptions_create() : ReadOptions
  fun rocksdb_readoptions_destroy = rocksdb_readoptions_destroy(options : ReadOptions)
  fun rocksdb_writeoptions_create = rocksdb_writeoptions_create() : WriteOptions
  fun rocksdb_writeoptions_destroy = rocksdb_writeoptions_destroy(options : WriteOptions)
  
  # Basic operations
  fun rocksdb_put = rocksdb_put(db : DB, write_options : WriteOptions, key : UInt8*, keylen : LibC::SizeT, value : UInt8*, valuelen : LibC::SizeT, errptr : UInt8**)
  fun rocksdb_get = rocksdb_get(db : DB, read_options : ReadOptions, key : UInt8*, keylen : LibC::SizeT, valuelen : LibC::SizeT*, errptr : UInt8**) : UInt8*
  fun rocksdb_delete = rocksdb_delete(db : DB, write_options : WriteOptions, key : UInt8*, keylen : LibC::SizeT, errptr : UInt8**)
  
  # Iterator operations  
  fun rocksdb_create_iterator = rocksdb_create_iterator(db : DB, read_options : ReadOptions) : Iterator
  fun rocksdb_iter_destroy = rocksdb_iter_destroy(iter : Iterator)
  fun rocksdb_iter_seek_to_first = rocksdb_iter_seek_to_first(iter : Iterator)
  fun rocksdb_iter_valid = rocksdb_iter_valid(iter : Iterator) : Bool
  fun rocksdb_iter_next = rocksdb_iter_next(iter : Iterator)
  fun rocksdb_iter_key = rocksdb_iter_key(iter : Iterator, keylen : LibC::SizeT*) : UInt8*
  fun rocksdb_iter_value = rocksdb_iter_value(iter : Iterator, valuelen : LibC::SizeT*) : UInt8*
  
  # Memory management
  fun rocksdb_free = rocksdb_free(ptr : Void*)
end

{% unless env("DISABLE_ROCKSDB") == "1" %}
module RocksDB
  class Database
    @db : LibRocksDB::DB
    @read_options : LibRocksDB::ReadOptions
    @write_options : LibRocksDB::WriteOptions
    @path : String
    
    def initialize(@path : String)
      options = LibRocksDB.rocksdb_options_create
      LibRocksDB.rocksdb_options_set_create_if_missing(options, true)
      
      error = Pointer(UInt8).null
      @db = LibRocksDB.rocksdb_open(options, @path.to_unsafe, pointerof(error))
      
      LibRocksDB.rocksdb_options_destroy(options)
      
      if error
        error_msg = String.new(error)
        LibRocksDB.rocksdb_free(error.as(Void*))
        raise "Failed to open RocksDB: #{error_msg}"
      end
      
      @read_options = LibRocksDB.rocksdb_readoptions_create
      @write_options = LibRocksDB.rocksdb_writeoptions_create
    end
    
    def close
      LibRocksDB.rocksdb_readoptions_destroy(@read_options)
      LibRocksDB.rocksdb_writeoptions_destroy(@write_options)
      LibRocksDB.rocksdb_close(@db)
    end
    
    def put(key : String, value : String)
      error = Pointer(UInt8).null
      LibRocksDB.rocksdb_put(
        @db, @write_options,
        key.to_unsafe, key.bytesize.to_u64,
        value.to_unsafe, value.bytesize.to_u64,
        pointerof(error)
      )
      
      if error
        error_msg = String.new(error)
        LibRocksDB.rocksdb_free(error.as(Void*))
        raise "Failed to put: #{error_msg}"
      end
    end
    
    def get(key : String) : String?
      error = Pointer(UInt8).null
      value_len = 0_u64
      
      value_ptr = LibRocksDB.rocksdb_get(
        @db, @read_options,
        key.to_unsafe, key.bytesize.to_u64,
        pointerof(value_len), pointerof(error)
      )
      
      if error
        error_msg = String.new(error)
        LibRocksDB.rocksdb_free(error.as(Void*))
        raise "Failed to get: #{error_msg}"
      end
      
      if value_ptr
        value = String.new(value_ptr, value_len.to_i32)
        LibRocksDB.rocksdb_free(value_ptr.as(Void*))
        value
      else
        nil
      end
    end
    
    def delete(key : String)
      error = Pointer(UInt8).null
      LibRocksDB.rocksdb_delete(
        @db, @write_options,
        key.to_unsafe, key.bytesize.to_u64,
        pointerof(error)
      )
      
      if error
        error_msg = String.new(error)
        LibRocksDB.rocksdb_free(error.as(Void*))
        raise "Failed to delete: #{error_msg}"
      end
    end
    
    def each_key(&block : String ->)
      iter = LibRocksDB.rocksdb_create_iterator(@db, @read_options)
      LibRocksDB.rocksdb_iter_seek_to_first(iter)
      
      while LibRocksDB.rocksdb_iter_valid(iter)
        key_len = 0_u64
        key_ptr = LibRocksDB.rocksdb_iter_key(iter, pointerof(key_len))
        key = String.new(key_ptr, key_len.to_i32)
        
        yield key
        
        LibRocksDB.rocksdb_iter_next(iter)
      end
      
      LibRocksDB.rocksdb_iter_destroy(iter)
    end
    
    def each(&block : String, String ->)
      iter = LibRocksDB.rocksdb_create_iterator(@db, @read_options)
      LibRocksDB.rocksdb_iter_seek_to_first(iter)
      
      while LibRocksDB.rocksdb_iter_valid(iter)
        key_len = 0_u64
        value_len = 0_u64
        
        key_ptr = LibRocksDB.rocksdb_iter_key(iter, pointerof(key_len))
        value_ptr = LibRocksDB.rocksdb_iter_value(iter, pointerof(value_len))
        
        key = String.new(key_ptr, key_len.to_i32)
        value = String.new(value_ptr, value_len.to_i32)
        
        yield key, value
        
        LibRocksDB.rocksdb_iter_next(iter)
      end
      
      LibRocksDB.rocksdb_iter_destroy(iter)
    end
  end
end
{% else %}
# RocksDB is disabled - provide stub implementation
module RocksDB
  class Database
    def initialize(@path : String)
      raise "RocksDB support is disabled. Install librocksdb-dev and rebuild without DISABLE_ROCKSDB=1"
    end
    
    def close
      # No-op
    end
    
    def put(key : String, value : String)
      raise "RocksDB support is disabled"
    end
    
    def get(key : String) : String?
      raise "RocksDB support is disabled"
    end
    
    def delete(key : String)
      raise "RocksDB support is disabled"
    end
    
    def each_key(&block : String ->)
      raise "RocksDB support is disabled"
    end
    
    def each(&block : String, String ->)
      raise "RocksDB support is disabled"
    end
  end
end
{% end %}