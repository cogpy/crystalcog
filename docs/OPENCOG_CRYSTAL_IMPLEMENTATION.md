# OpenCog Pure Crystal Language Implementation

## Overview

CrystalCog is a **complete, production-ready implementation of the OpenCog artificial intelligence framework in pure Crystal language**. This implementation provides all the core functionality of OpenCog with improved performance, memory safety, and modern language features.

## Implementation Status: ✅ COMPLETE

This repository contains a fully functional OpenCog implementation written entirely in Crystal, with no dependencies on the original C++ codebase.

## Core Components Implemented

### 1. CogUtil - Core Utilities ✅
**Location:** `src/cogutil/`

- **Logger** - Structured logging system with multiple severity levels
- **Config** - Configuration management system
- **RandGen** - Random number generation utilities
- **Performance Profiler** - Runtime performance monitoring
- **Memory Profiler** - Memory usage tracking and optimization
- **Performance Monitor** - Comprehensive performance metrics collection
- **Optimization Engine** - Automated performance optimization

**Files:**
- `cogutil.cr` - Main module
- `logger.cr` - Logging implementation
- `config.cr` - Configuration management
- `randgen.cr` - Random generation
- `performance_profiler.cr` - Profiling tools
- `memory_profiler.cr` - Memory analysis
- `performance_monitor.cr` - Monitoring system
- `optimization_engine.cr` - Optimization algorithms

### 2. AtomSpace - Knowledge Representation ✅
**Location:** `src/atomspace/`

The AtomSpace is the central knowledge store, implementing a hypergraph database for representing knowledge as atoms (nodes and links).

**Core Features:**
- Complete atom type system (Nodes and Links)
- Truth value system with probabilistic logic
- Efficient indexing and retrieval
- Thread-safe operations
- Event system for observers
- Distributed AtomSpace clustering
- Cognitive kernel support

**Storage Backends:**
- **File Storage** - Human-readable Scheme format
- **SQLite Storage** - Relational database with indexing
- **PostgreSQL Storage** - Enterprise-grade database
- **RocksDB Storage** - High-performance key-value store (0.9ms store, 0.5ms load)
- **Network Storage** - Distributed AtomSpace access via CogServer
- **Hypergraph State Persistence** - Complete cognitive kernel state management

**Files:**
- `atomspace.cr` - Main AtomSpace implementation
- `atom.cr` - Atom, Node, and Link classes
- `truthvalue.cr` - Truth value system
- `storage.cr` - Storage backend implementations
- `cognitive_kernel.cr` - Agent-Zero cognitive processing units
- `distributed_cluster.cr` - Multi-node clustering
- `distributed_storage.cr` - Distributed storage management

### 3. PLN - Probabilistic Logic Networks ✅
**Location:** `src/pln/`

Complete implementation of PLN reasoning system with multiple inference rules:

**Inference Rules:**
- Deduction Rule (A→B, B→C ⇒ A→C)
- Inversion Rule (A→B ⇒ B→A)
- Abduction Rule (A→B, C→B ⇒ A→C)
- Modus Ponens (A→B, A ⇒ B)
- Similarity (A→B, B→A ⇒ A↔B)

**Features:**
- Truth value calculations with PLN formulas
- Iterative reasoning with configurable depth
- Confidence decay for derived knowledge
- Rule chaining and composition

**Files:**
- `pln.cr` - Complete PLN implementation

### 4. URE - Unified Rule Engine ✅
**Location:** `src/ure/`

Advanced inference engine supporting both forward and backward chaining:

**Features:**
- Forward chaining (data-driven reasoning)
- Backward chaining (goal-driven reasoning)
- Configurable rule sets
- Rule fitness evaluation
- Inference control strategies
- Depth-limited search

**Rule Types:**
- Conjunction rule (A, B ⇒ A∧B)
- Disjunction rule (A ⇒ A∨B)
- Implication rule (A, A→B ⇒ B)
- Negation rule (¬A ⇒ A is false)

**Files:**
- `ure.cr` - Complete URE implementation

### 5. Pattern Matching ✅
**Location:** `src/pattern_matching/`

Sophisticated pattern matching and query system:

**Features:**
- Variable binding and substitution
- Recursive pattern composition
- Temporal pattern analysis
- Machine learning integration
- Statistical inference
- Type constraints
- Pattern mining for frequent subgraphs

**Files:**
- `pattern_matching.cr` - Core pattern matching
- `pattern_matching_main.cr` - Advanced capabilities
- `advanced_pattern_matching.cr` - ML and temporal analysis

**Pattern Mining Location:** `src/pattern_mining/`
- `pattern_mining.cr` - Frequent pattern discovery
- `pattern_mining_main.cr` - Mining algorithms

### 6. CogServer - Network Server ✅
**Location:** `src/cogserver/`

Complete network server for distributed OpenCog processing:

**Features:**
- **HTTP REST API** - Complete CRUD operations for atoms
- **WebSocket Support** - Real-time bidirectional communication
- **Telnet Interface** - Command-line access
- **Session Management** - Client connection tracking
- **Storage Management API** - Attach/detach storage backends via REST

**Endpoints:**
- `GET /atoms` - List all atoms
- `POST /atoms` - Create new atom
- `GET /atoms/:handle` - Get specific atom
- `PUT /atoms/:handle` - Update atom
- `DELETE /atoms/:handle` - Delete atom
- `GET /stats` - AtomSpace statistics
- `POST /storage/save` - Persist AtomSpace
- `POST /query` - Pattern matching queries

**Files:**
- `cogserver.cr` - Server implementation
- `cogserver_main.cr` - Entry point

### 7. NLP - Natural Language Processing ✅
**Location:** `src/nlp/`

Comprehensive natural language processing system:

**Features:**
- Text tokenization and parsing
- Linguistic atom representation
- Semantic relationship creation
- Text statistics and analysis
- Keyword extraction
- Link Grammar integration
- Dependency parsing
- Language generation
- Semantic understanding

**Files:**
- `nlp.cr` - Main NLP module
- `nlp_main.cr` - Entry point
- `tokenizer.cr` - Text tokenization
- `text_processor.cr` - Text analysis
- `linguistic_atoms.cr` - Linguistic representations
- `link_grammar.cr` - Grammar parsing
- `dependency_parser.cr` - Dependency analysis
- `language_generation.cr` - Text generation
- `semantic_understanding.cr` - Semantic analysis

### 8. MOSES - Evolutionary Program Learning ✅
**Location:** `src/moses/`

Meta-Optimizing Semantic Evolutionary Search for program learning:

**Features:**
- Program representation as combo trees
- Evolutionary optimization
- Fitness scoring
- Deme-based population management
- Metapopulation evolution
- Tournament selection
- Crossover and mutation operators

**Files:**
- `moses.cr` - Main module
- `moses_main.cr` - Entry point
- `moses_framework.cr` - Framework implementation
- `representation.cr` - Program representation
- `scoring.cr` - Fitness evaluation
- `optimization.cr` - Optimization algorithms
- `deme.cr` - Local populations
- `metapopulation.cr` - Global populations
- `types.cr` - Type definitions

### 9. Machine Learning Integration ✅
**Location:** `src/ml/`

Integration of machine learning capabilities:

**Features:**
- Neural network implementation
- ML-AtomSpace integration
- Training and inference

**Files:**
- `ml_main.cr` - Entry point
- `ml_integration.cr` - Integration layer
- `neural_network.cr` - Neural network implementation

### 10. Learning Systems ✅
**Location:** `src/learning/`

Concept learning and generalization:

**Features:**
- Concept formation from examples
- Pattern generalization
- Inductive learning

**Files:**
- `learning_main.cr` - Entry point
- `concept_learning.cr` - Concept formation
- `generalization.cr` - Pattern generalization

### 11. Attention Allocation ✅
**Location:** `src/attention/`

Economic Attention Networks (ECAN):

**Features:**
- Importance and attention values
- Attentional focus management
- Importance diffusion
- Rent collection (forgetting)
- Multi-goal optimization

**Files:**
- `attention.cr` - Core types
- `attention_main.cr` - Entry point
- `attention_bank.cr` - Attention value management
- `allocation_engine.cr` - Attention allocation
- `diffusion.cr` - Importance spreading
- `rent_collector.cr` - Forgetting mechanism

### 12. Agent-Zero Cognitive System ✅
**Location:** `src/agent-zero/`

Distributed cognitive agent networks:

**Features:**
- Cognitive tensor field encoding
- Distributed agent communication
- Network services
- OpenCog-GGML bridge

**Files:**
- `distributed_agents.cr` - Agent implementation
- `agent_network.cr` - Network coordination
- `network_services.cr` - Network protocols
- `distributed_network_demo.cr` - Demo application

### 13. OpenCog Query Language ✅
**Location:** `src/opencog/`

High-level query and manipulation interface:

**Features:**
- Declarative query syntax
- Pattern-based queries
- Query optimization
- Result filtering

**Files:**
- `opencog.cr` - Main interface
- `query_language.cr` - Query DSL

### 14. AI Integration Bridge ✅
**Location:** `src/ai_integration/`

Bridge to external AI systems:

**Features:**
- Integration with external AI frameworks
- Data format conversion
- API bridging

**Files:**
- `ai_bridge.cr` - Integration implementation

## Build and Test System

### Building

```bash
# Install dependencies
shards install

# Build main executable
crystal build src/crystalcog.cr -o bin/crystalcog

# Build specific components
crystal build src/cogserver/cogserver_main.cr -o cogserver_bin
crystal build src/pattern_matching/pattern_matching_main.cr
```

### Testing

The project includes comprehensive test coverage:

**Test Structure:**
- `spec/cogutil/` - CogUtil tests (8 specs)
- `spec/atomspace/` - AtomSpace tests (6 specs)
- `spec/pln/` - PLN tests
- `spec/ure/` - URE tests (2 specs)
- `spec/pattern_matching/` - Pattern matching tests (2 specs)
- `spec/pattern_mining/` - Pattern mining tests (2 specs)
- `spec/nlp/` - NLP tests (7 specs)
- `spec/moses/` - MOSES tests (7 specs)
- `spec/attention/` - Attention tests (7 specs)
- `spec/cogserver/` - CogServer tests (2 specs)
- `spec/opencog/` - OpenCog integration tests (3 specs)
- `spec/integration/` - Integration tests
- `spec/error_handling/` - Error handling and edge cases

**Running Tests:**
```bash
# Run all tests
crystal spec

# Run specific component tests
crystal spec spec/cogutil/
crystal spec spec/atomspace/
crystal spec spec/pln/
crystal spec spec/ure/

# Run integration tests
crystal spec spec/integration/
```

## Demonstrations

The repository includes multiple demonstration files:

1. **demo.cr** - Basic AtomSpace operations and reasoning
2. **demo_attention.cr** - Attention allocation mechanisms
3. **demo_advanced_reasoning.cr** - PLN and URE reasoning
4. **demo_advanced_pattern_matching.cr** - Advanced pattern matching
5. **demo_hypergraph_persistence.cr** - Storage backend demonstrations
6. **demo_storage_backends.cr** - Multiple storage engines
7. **demo_link_grammar.cr** - NLP and linguistic parsing
8. **demo_cogserver.cr** - Network server functionality
9. **demo_ai_integration.cr** - AI system integration

**Running Demos:**
```bash
crystal run demo.cr
crystal run demo_attention.cr
crystal run demo_advanced_reasoning.cr
```

## Performance Characteristics

Based on benchmarks in the repository:

- **AtomSpace Operations:** Sub-millisecond atom creation and retrieval
- **RocksDB Storage:** 0.9ms store, 0.5ms load times
- **Pattern Matching:** Efficient indexing and search
- **Memory Management:** Automatic garbage collection via Crystal runtime
- **Thread Safety:** Mutex-based synchronization for concurrent access

## Dependencies

**External Libraries:**
- `crystal-sqlite3` - SQLite database support
- `crystal-pg` - PostgreSQL database support

**System Libraries:**
- libevent - Event-driven networking
- librocksdb - RocksDB storage backend
- libyaml - YAML configuration
- libssl - Secure communications
- libsqlite3 - SQLite storage

## Crystal Language Features Utilized

The implementation leverages Crystal's modern features:

- **Type Safety:** Static typing with type inference
- **Performance:** Compiled to native code via LLVM
- **Memory Safety:** Automatic memory management
- **Concurrency:** Fiber-based concurrency model
- **Macros:** Compile-time code generation
- **Generics:** Type-safe generic programming
- **Modules:** Namespace organization

## Project Structure

```
crystalcog/
├── src/                        # Source code
│   ├── cogutil/               # Core utilities
│   ├── atomspace/             # Knowledge representation
│   ├── pln/                   # Probabilistic Logic Networks
│   ├── ure/                   # Unified Rule Engine
│   ├── pattern_matching/      # Pattern matching
│   ├── pattern_mining/        # Pattern discovery
│   ├── cogserver/             # Network server
│   ├── nlp/                   # Natural language processing
│   ├── moses/                 # Evolutionary program learning
│   ├── attention/             # Attention allocation
│   ├── ml/                    # Machine learning
│   ├── learning/              # Concept learning
│   ├── opencog/               # High-level interface
│   ├── agent-zero/            # Distributed agents
│   ├── ai_integration/        # AI bridges
│   └── crystalcog.cr         # Main entry point
├── spec/                      # Test specifications
│   ├── cogutil/
│   ├── atomspace/
│   ├── pln/
│   ├── ure/
│   ├── pattern_matching/
│   ├── nlp/
│   ├── moses/
│   ├── attention/
│   ├── cogserver/
│   ├── opencog/
│   ├── integration/
│   └── error_handling/
├── examples/                  # Example applications
├── benchmarks/               # Performance benchmarks
├── scripts/                  # Build and deployment scripts
├── docs/                     # Documentation
├── demo*.cr                  # Demonstration programs
├── test*.cr                  # Test programs
└── shard.yml                # Crystal package definition
```

## API Documentation

### AtomSpace API

```crystal
# Create AtomSpace
atomspace = AtomSpace::AtomSpace.new

# Add nodes
dog = atomspace.add_concept_node("dog")
animal = atomspace.add_concept_node("animal")

# Add links
inheritance = atomspace.add_inheritance_link(dog, animal)

# Query atoms
all_atoms = atomspace.get_all_atoms
concept_nodes = atomspace.get_atoms_by_type(AtomSpace::AtomType::CONCEPT_NODE)

# Truth values
tv = AtomSpace::SimpleTruthValue.new(0.9, 0.8)
dog_with_tv = atomspace.add_concept_node("dog", tv)
```

### Storage API

```crystal
# File storage
file_storage = atomspace.create_file_storage("main", "knowledge.scm")
file_storage.open
file_storage.store_atomspace(atomspace)
file_storage.close

# RocksDB storage
rocksdb_storage = atomspace.create_rocksdb_storage("main", "knowledge.rocks")
rocksdb_storage.open
rocksdb_storage.store_atomspace(atomspace)

# PostgreSQL storage
postgres_storage = atomspace.create_postgres_storage("prod", "user:pass@localhost/opencog")
postgres_storage.open
postgres_storage.store_atomspace(atomspace)
```

### PLN API

```crystal
# Create PLN engine
pln_engine = PLN.create_engine(atomspace)

# Run reasoning
new_atoms = pln_engine.reason(10)  # 10 iterations
```

### URE API

```crystal
# Create URE engine
ure_engine = URE.create_engine(atomspace)

# Forward chaining
new_atoms = ure_engine.forward_chain(5)

# Backward chaining
goal = atomspace.add_concept_node("target")
result = ure_engine.backward_chain(goal)
```

### CogServer API

```crystal
# Start server
server = CogServer::CogServer.new(atomspace, port: 18080)
server.start
```

### NLP API

```crystal
# Process text
text = "The cat sits on the mat."
atoms = NLP.process_text(text, atomspace)

# Tokenize
tokens = NLP::Tokenizer.tokenize(text)

# Extract keywords
keywords = NLP::TextProcessor.extract_keywords(text, 3)

# Create semantic relations
NLP::LinguisticAtoms.create_semantic_relation(atomspace, "dog", "animal", "isa", 0.9)
```

## Conclusion

This is a **complete, production-ready implementation of OpenCog in pure Crystal language**. All core components are implemented and functional:

✅ CogUtil - Core utilities and system management  
✅ AtomSpace - Hypergraph knowledge representation  
✅ PLN - Probabilistic Logic Networks reasoning  
✅ URE - Unified Rule Engine inference  
✅ Pattern Matching - Advanced query and search  
✅ CogServer - Network server with REST API  
✅ NLP - Natural language processing  
✅ MOSES - Evolutionary program learning  
✅ Attention - Economic attention allocation  
✅ Learning - Concept learning and generalization  
✅ ML Integration - Machine learning capabilities  
✅ Agent-Zero - Distributed cognitive agents  
✅ Storage - Multiple persistence backends  
✅ Query Language - High-level manipulation interface  

The implementation is well-tested, documented, and includes demonstrations of all major features.
