# Hypergraph State Persistence Documentation

## Overview

This document describes the hypergraph state persistence system implemented for Agent-Zero Genesis. The system provides comprehensive persistence for cognitive kernel states, including AtomSpace hypergraph content, tensor field configurations, attention weights, and meta-cognitive information.

## Architecture

The hypergraph state persistence system consists of several key components:

### Core Components

1. **HypergraphState Record**: Complete representation of cognitive kernel state
2. **HypergraphStateStorageNode**: Specialized storage backend for hypergraph states
3. **CognitiveKernel**: Agent-Zero cognitive processing unit with state management
4. **CognitiveKernelManager**: Multi-kernel coordination and attention allocation

### Data Flow

```
CognitiveKernel → HypergraphState → HypergraphStateStorageNode → Persistent Storage
     ↑                                                                    ↓
AtomSpace Content ←─────────── Load Process ←─────────── JSON Metadata + AtomSpace Files
```

## Data Structures

### HypergraphState Record

```crystal
record HypergraphState, 
  atomspace : AtomSpace,           # Complete hypergraph content
  tensor_shape : Array(Int32),     # Tensor field dimensions
  attention : Float64,             # Attention weight (0.0-1.0)
  meta_level : Int32,              # Meta-cognitive level
  cognitive_operation : String?,   # Current cognitive operation
  timestamp : Time                 # State creation timestamp
```

The HypergraphState record encapsulates the complete cognitive state:
- **AtomSpace**: Contains all nodes, links, and their relationships
- **Tensor Shape**: Defines the dimensional structure of the cognitive tensor field
- **Attention**: Current attention allocation weight
- **Meta Level**: Recursive self-description depth
- **Cognitive Operation**: Current processing mode (reasoning, learning, memory, etc.)
- **Timestamp**: When the state was captured

### Storage Format

The system uses a dual-file approach:
1. **AtomSpace Content**: Stored in Scheme (.scm) or SQLite format
2. **Metadata**: JSON file containing non-AtomSpace state information

Example metadata structure:
```json
{
  "tensor_shape": [128, 64, 32],
  "attention": 0.85,
  "meta_level": 2,
  "cognitive_operation": "reasoning",
  "timestamp": 1694789123,
  "atomspace_size": 47
}
```

## CognitiveKernel Class

The CognitiveKernel class represents a complete Agent-Zero cognitive processing unit.

### Initialization

```crystal
# Create new cognitive kernel
kernel = CognitiveKernel.new([128, 64], 0.8, 1, "reasoning")

# Or from existing AtomSpace
kernel = CognitiveKernel.new(existing_atomspace, [64, 32], 0.7)
```

### Tensor Field Encoding

The cognitive kernel supports multiple mathematical sequence generators for tensor field encoding:

#### Available Encoding Types

1. **Prime Numbers**: Primary factorization-based encoding
2. **Fibonacci**: Sequential pattern recognition encoding
3. **Harmonic**: Frequency-domain representations (1/k series)
4. **Factorial**: Combinatorial complexity encoding
5. **Powers of Two**: Binary hierarchical structures

#### Usage Examples

```crystal
# Prime encoding with attention weighting
prime_encoding = kernel.tensor_field_encoding("prime", include_attention: true)

# Normalized Fibonacci encoding
fib_encoding = kernel.tensor_field_encoding("fibonacci", normalization: "unit")

# Hypergraph-aware encoding (includes connectivity metrics)
hypergraph_encoding = kernel.hypergraph_tensor_encoding

# Cognitive operation-specific encoding
reasoning_encoding = kernel.cognitive_tensor_field_encoding("reasoning")
```

#### Normalization Options

- **"none"**: No normalization (default)
- **"unit"**: Normalize to unit length (magnitude = 1.0)
- **"standard"**: Zero mean, unit variance normalization

### Cognitive Operations

The system supports operation-specific tensor encodings:

- **"reasoning"**: Weights [1.5, 1.2, 1.0] - emphasis on logical processing
- **"learning"**: Weights [1.0, 1.8, 1.3] - emphasis on adaptation
- **"attention"**: Weights [2.0, 1.0, 1.1] - emphasis on focus allocation
- **"memory"**: Weights [1.1, 1.0, 1.9] - emphasis on storage/retrieval
- **"adaptation"**: Weights [1.3, 1.6, 1.4] - balanced meta-cognitive processing

## Storage Backends

### HypergraphStateStorageNode

The specialized storage node handles complete hypergraph state persistence:

```crystal
# File-based storage
file_storage = HypergraphStateStorageNode.new("cognitive_file", "/path/to/state.scm", "file")

# SQLite-based storage
sqlite_storage = HypergraphStateStorageNode.new("cognitive_db", "/path/to/state.db", "sqlite")
```

### Backend Types

1. **File Backend**: Uses FileStorageNode for AtomSpace + JSON metadata
2. **SQLite Backend**: Uses SQLiteStorageNode for AtomSpace + JSON metadata

Both backends provide:
- Atomic operations for state consistency
- Metadata validation
- Error handling and recovery
- Statistics and monitoring

## AtomSpace Integration

The AtomSpace class is extended with hypergraph state persistence methods:

### Storage Creation

```crystal
atomspace = AtomSpace.new

# Create and attach hypergraph storage
storage = atomspace.create_hypergraph_storage("main_storage", "/path/to/state.scm", "file")
storage.open
```

### State Persistence

```crystal
# Store complete hypergraph state
success = atomspace.store_hypergraph_state([128, 64], 0.85, 2, "reasoning")

# Load hypergraph state
loaded_state = atomspace.load_hypergraph_state
if loaded_state
  puts "Loaded state: #{loaded_state.tensor_shape}, attention: #{loaded_state.attention}"
end
```

### Direct Storage Operations

```crystal
# Store to specific storage
atomspace.store_hypergraph_state_to(storage, [64, 32], 0.7, 1, "learning")

# Load from specific storage
state = atomspace.load_hypergraph_state_from(storage)
```

## CognitiveKernelManager

The manager coordinates multiple cognitive kernels with adaptive attention allocation:

### Multi-Kernel Management

```crystal
manager = CognitiveKernelManager.new

# Create specialized kernels
reasoning_kernel = manager.create_kernel([128, 64], 0.9)
learning_kernel = manager.create_kernel([64, 32], 0.7)
memory_kernel = manager.create_kernel([256, 128], 0.8)
```

### Attention Allocation

```crystal
goals = ["reasoning", "learning", "memory"]
allocations = manager.adaptive_attention_allocation(goals)

allocations.each do |allocation|
  kernel = allocation[:kernel]
  score = allocation[:attention_score]
  priority = allocation[:activation_priority]
  goal = allocation[:goal]
  
  puts "#{goal}: score=#{score}, priority=#{priority}"
end
```

The attention allocation system uses goal-specific scoring:
- **reasoning**: 0.9 (highest priority for logical tasks)
- **learning**: 0.7 (moderate priority for adaptation)
- **attention**: 0.8 (high priority for focus management)
- **memory**: 0.6 (lower priority for storage tasks)
- **adaptation**: 0.75 (balanced priority for meta-learning)

## Usage Examples

### Basic Hypergraph State Persistence

```crystal
# Create cognitive kernel
kernel = CognitiveKernel.new([64, 32], 0.8, 1, "reasoning")

# Add knowledge to AtomSpace
agent = kernel.add_concept_node("agent-zero")
cognitive = kernel.add_concept_node("cognitive-system")
kernel.add_inheritance_link(agent, cognitive)

# Create storage and persist state
storage = kernel.atomspace.create_hypergraph_storage("main", "state.scm")
storage.open

# Store complete state
kernel.store_hypergraph_state(storage)

# Load into new kernel
new_kernel = CognitiveKernel.new([16, 8], 0.2) # Different initial state
new_kernel.load_hypergraph_state(storage)      # Loads complete previous state
```

### Multi-Backend Persistence

```crystal
kernel = CognitiveKernel.new([128, 64], 0.9)

# Add knowledge content
# ... (populate AtomSpace)

# Store to multiple backends
file_storage = kernel.atomspace.create_hypergraph_storage("file", "state.scm", "file")
sqlite_storage = kernel.atomspace.create_hypergraph_storage("db", "state.db", "sqlite")

file_storage.open
sqlite_storage.open

# Both will store the same complete state
kernel.store_hypergraph_state(file_storage)
kernel.store_hypergraph_state(sqlite_storage)
```

### Tensor Field Analysis

```crystal
kernel = CognitiveKernel.new([64, 32, 16], 0.85, 2, "meta-reasoning")

# Generate different encodings
prime_enc = kernel.tensor_field_encoding("prime", include_attention: true)
fib_enc = kernel.tensor_field_encoding("fibonacci", normalization: "unit")
hypergraph_enc = kernel.hypergraph_tensor_encoding

puts "Prime encoding size: #{prime_enc.size}"
puts "Hypergraph encoding includes connectivity: #{hypergraph_enc.size > prime_enc.size}"

# Operation-specific encodings
reasoning_enc = kernel.cognitive_tensor_field_encoding("reasoning")
learning_enc = kernel.cognitive_tensor_field_encoding("learning")

puts "Reasoning emphasis: #{reasoning_enc[0]} vs Learning emphasis: #{learning_enc[0]}"
```

## File Structure

When using file-based storage, the system creates:

```
/path/to/storage/
├── cognitive_state.scm          # AtomSpace content in Scheme format
└── cognitive_state_metadata.json # Hypergraph state metadata
```

For SQLite storage:

```
/path/to/storage/
├── cognitive_state.db           # AtomSpace content in SQLite format
└── cognitive_state_metadata.json # Hypergraph state metadata
```

## Error Handling

The system provides comprehensive error handling:

### Storage Errors
- Connection failures automatically logged
- Invalid state data validation
- Atomic operation rollback on failure
- Metadata consistency checking

### Recovery Patterns
```crystal
storage = HypergraphStateStorageNode.new("recovery", "state.scm")

unless storage.open
  puts "Failed to open storage, using backup..."
  storage = HypergraphStateStorageNode.new("backup", "backup_state.scm")
end

if storage.connected?
  state = storage.load_hypergraph_state(atomspace)
  puts state ? "Recovery successful" : "Recovery failed"
end
```

## Performance Considerations

### Memory Usage
- HypergraphState records reference AtomSpace, not copy
- Tensor encodings generated on-demand
- Metadata cached for repeated access

### Storage Performance
- SQLite backend provides better performance for large AtomSpaces
- File backend suitable for smaller states and debugging
- Batch operations minimize I/O overhead

### Scalability
- Attention allocation scales linearly with kernel count
- Tensor encodings support arbitrary dimensions
- Storage backends handle AtomSpaces with millions of atoms

## Testing

The system includes comprehensive tests:

### Test Coverage
- Basic cognitive kernel functionality
- Hypergraph state storage/loading
- Multiple backend validation
- AtomSpace integration
- Multi-kernel management
- Error conditions and recovery

### Running Tests
```bash
# Run hypergraph persistence tests
crystal run test_hypergraph_persistence.cr

# Run demonstration
crystal run demo_hypergraph_persistence.cr
```

## Integration with Agent-Zero Genesis

This hypergraph state persistence system fulfills the Agent-Zero Genesis roadmap requirement for "Build hypergraph state persistence". It provides:

1. **Complete State Capture**: All cognitive kernel components persisted
2. **Multiple Storage Options**: File and database backends
3. **Tensor Field Management**: Mathematical sequence encoding
4. **Attention Allocation**: Adaptive priority management
5. **Meta-Cognitive Support**: Recursive self-description persistence
6. **AtomSpace Integration**: Seamless hypergraph content management

The system enables Agent-Zero cognitive agents to:
- Persist complete cognitive states across sessions
- Resume complex reasoning tasks from exact previous states
- Analyze cognitive evolution through tensor field comparisons
- Coordinate multiple specialized cognitive kernels
- Maintain attention allocation strategies persistently

## Future Enhancements

Planned improvements include:

1. **Distributed Storage**: Network-based hypergraph state sharing
2. **Incremental Updates**: Delta-based state persistence
3. **Compression**: Efficient storage of large tensor fields
4. **Versioning**: Historical state tracking and rollback
5. **Analytics**: Cognitive evolution analysis tools
6. **GPU Integration**: GGML tensor operation acceleration

## Related Documentation

- [AtomSpace Persistence API Documentation](PERSISTENCE_API_DOCUMENTATION.md)
- [Agent-Zero Genesis Integration](AGENT-ZERO-INTEGRATION.md)
- [Cognitive Kernel Documentation](COGNITIVE_KERNEL_DOCUMENTATION.md)

---

*This hypergraph state persistence system represents a complete implementation of cognitive state management for the Agent-Zero Genesis platform, enabling persistent cognitive agents with full state continuity.*