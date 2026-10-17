# CrystalCog Phase 6: Extended Integrations

## Overview

Phase 6 introduces extended integration capabilities for CrystalCog, enabling seamless connections with external systems, databases, and platforms. This phase focuses on expanding the ecosystem compatibility and providing modern tooling for developers.

**Version**: 0.3.0
**Release Date**: January 2026

## New Integrations

### 1. Neo4j Graph Database Integration

**File**: `src/integrations/neo4j_integration.cr`

A comprehensive Neo4j graph database integration that enables storing and querying AtomSpace data using Neo4j's powerful graph capabilities.

#### Features

- **Atom Storage**: Store atoms as labeled nodes with properties
- **Link Management**: Represent AtomSpace links as Neo4j relationships
- **Cypher Query Builder**: Fluent API for building Cypher queries
- **Graph Analytics**: PageRank, community detection, path finding
- **Semantic Similarity**: Jaccard similarity search for related atoms
- **Batch Operations**: Efficient bulk insert/update operations
- **Connection Pooling**: High-performance connection management

#### Usage

```crystal
require "crystalcog/integrations/neo4j_integration"

# Create client
client = CrystalCog::Integrations::Neo4jClient.new(
  host: "localhost",
  port: 7474,
  username: "neo4j",
  password: "password"
)

# Connect and initialize schema
client.connect
client.initialize_schema

# Store an atom
atom = CrystalCog::Integrations::Neo4jAtomNode.new(
  id: "concept-1",
  atom_type: "ConceptNode",
  name: "Dog",
  truth_value_strength: 0.9,
  truth_value_confidence: 0.8
)
client.store_atom(atom)

# Query atoms
dogs = client.search_atoms_by_name(".*Dog.*")

# Find paths between atoms
paths = client.find_path("concept-1", "concept-2")

# Get graph statistics
stats = client.get_statistics
```

#### Schema

```cypher
(:Atom:ConceptNode {
  id: String,
  atomType: String,
  name: String?,
  tvStrength: Float,
  tvConfidence: Float,
  avSti: Float,
  avLti: Float,
  createdAt: Integer,
  updatedAt: Integer,
  metadata: String
})

(:Atom)-[:InheritanceLink {
  id: String,
  tvStrength: Float,
  tvConfidence: Float,
  arity: Integer,
  outgoingSet: List<String>
}]->(:Atom)
```

---

### 2. IPFS Decentralized Storage Integration

**File**: `src/integrations/ipfs_integration.cr`

Content-addressed, decentralized storage for AtomSpace data using IPFS (InterPlanetary File System).

#### Features

- **Content-Addressed Storage**: Atoms stored by content hash (CID)
- **AtomSpace Snapshots**: Version-controlled knowledge base snapshots
- **DAG Operations**: IPLD-based structured data storage
- **IPNS Publishing**: Mutable names for AtomSpace versions
- **MFS Integration**: Familiar file system operations
- **Pubsub Sync**: Real-time distributed synchronization
- **DHT Discovery**: Peer-to-peer content discovery

#### Usage

```crystal
require "crystalcog/integrations/ipfs_integration"

# Create client
client = CrystalCog::Integrations::IPFSClient.new("localhost", 5001)
client.connect

# Store content
cid = client.add("Hello, CrystalCog!")

# Store JSON data
atom_data = JSON.parse({
  "type" => "ConceptNode",
  "name" => "Dog"
}.to_json)
cid = client.add_json(atom_data)

# Retrieve content
content = client.cat(cid)
json = client.get_json(cid)

# AtomSpace storage
storage = CrystalCog::Integrations::IPFSAtomSpaceStorage.new(client, "my-atomspace")
storage.initialize_storage

# Store atom
atom = CrystalCog::Integrations::IPFSAtom.new(
  id: "atom-1",
  atom_type: "ConceptNode",
  name: "Cat"
)
cid = storage.store_atom(atom)

# Create snapshot
atoms = [atom1, atom2, atom3]
links = [link1, link2]
snapshot_cid = storage.store_snapshot(atoms, links)

# Version history
versions = storage.get_versions
```

#### Content Addressing

```
AtomSpace Snapshot (CID: QmXyz...)
├── atoms/
│   ├── atom-1 (CID: QmAbc...)
│   ├── atom-2 (CID: QmDef...)
│   └── ...
├── links/
│   └── ...
├── index.json
└── manifest.json
```

---

### 3. MeTTa Hypergraph Rewriting Integration

**File**: `src/integrations/metta_integration.cr`

Integration with MeTTa (Meta Type Talk), the hypergraph rewriting language from OpenCog Hyperon.

#### Features

- **Hypergraph Pattern Matching**: First-class pattern matching on atom structures
- **Rewrite Rules**: Define and apply transformation rules
- **Type System**: Optional type annotations for variables
- **Non-determinism**: Superposition for exploring multiple possibilities
- **Meta-Level Operations**: Quote, unquote, and reflection
- **Built-in Operations**: Arithmetic, logic, comparison
- **REPL**: Interactive exploration environment

#### Usage

```crystal
require "crystalcog/integrations/metta_integration"

# Create interpreter
interpreter = CrystalCog::Integrations::MeTTaInterpreter.new
interpreter.load_stdlib

# Basic arithmetic
result = interpreter.eval("(+ 1 2 3)")  # => 6.0

# Pattern matching
interpreter.run("(add-atom &self (Person Alice))")
interpreter.run("(add-atom &self (Person Bob))")
results = interpreter.run("(match &self (Person $name) $name)")
# => [Alice, Bob]

# Define rewrite rules
interpreter.run("(= (double $x) (* 2 $x))")
result = interpreter.eval("(double 21)")  # => 42.0

# Complex rules
interpreter.run(<<-METTA
  (= (factorial 0) 1)
  (= (factorial $n) (* $n (factorial (- $n 1))))
METTA)
result = interpreter.eval("(factorial 5)")  # => 120.0

# REPL mode
interpreter.repl
```

#### MeTTa Syntax

```metta
; Symbols
foo bar +

; Variables
$x $name $any

; Numbers
42 3.14 -10

; Strings
"hello world"

; Expressions
(f x y)
(+ 1 2 3)
(Person Alice)

; Rules (rewriting)
(= (inc $x) (+ $x 1))
(= (double $x) (* 2 $x))

; Pattern matching
(match &space (Person $name) $name)

; Conditionals
(if True then-branch else-branch)
(case $x ((pattern1 result1) (pattern2 result2)))

; Non-determinism
(superpose (list a b c))
(collapse (superpose ...))
```

---

### 4. TypeScript SDK

**File**: `src/integrations/typescript_sdk.cr`

Complete TypeScript/JavaScript SDK for web applications interacting with CrystalCog.

#### Features

- **REST API**: Full CRUD operations for atoms
- **WebSocket**: Real-time subscriptions and updates
- **OpenAPI Spec**: Auto-generated API documentation
- **TypeScript Types**: Full type definitions
- **Client Library**: Ready-to-use npm package
- **CORS Support**: Cross-origin web requests
- **Authentication**: Optional API key auth

#### Server Usage

```crystal
require "crystalcog/integrations/typescript_sdk"

# Create and start server
config = CrystalCog::Integrations::TypeScriptSDKConfig.new(
  host: "0.0.0.0",
  port: 8080,
  enable_websocket: true,
  cors_origins: ["http://localhost:3000"]
)

server = CrystalCog::Integrations::TypeScriptSDKServer.new(config)
server.start
```

#### TypeScript Client Usage

```typescript
import { CrystalCogClient } from '@crystalcog/sdk';

// Create client
const client = new CrystalCogClient('http://localhost:8080');

// Create atom
const dog = await client.createAtom({
  type: 'ConceptNode',
  name: 'Dog',
  truthValue: { strength: 0.9, confidence: 0.8 }
});

// Query atoms
const results = await client.query({ pattern: 'Dog', limit: 10 });

// WebSocket subscriptions
await client.connect();
const unsubscribe = client.subscribe('atoms', (event) => {
  console.log('Atom changed:', event);
});

// Health check
const health = await client.health();
```

#### REST API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/atoms` | List all atoms |
| POST | `/api/v1/atoms` | Create new atom |
| GET | `/api/v1/atoms/:id` | Get atom by ID |
| PUT | `/api/v1/atoms/:id` | Update atom |
| DELETE | `/api/v1/atoms/:id` | Delete atom |
| POST | `/api/v1/query` | Query atoms |
| GET | `/api/v1/stats` | Get statistics |
| GET | `/api/v1/health` | Health check |
| GET | `/api/v1/openapi.json` | OpenAPI specification |

#### WebSocket Protocol

```javascript
// Subscribe to channel
{ "type": "subscribe", "channel": "atoms" }

// Query
{ "type": "query", "payload": { "pattern": "Dog" } }

// Mutation
{ "type": "mutation", "payload": { "action": "add", "atom": {...} } }

// Events (received)
{ "type": "event", "channel": "atoms", "payload": { "action": "add", "atom": {...} } }
```

---

## Installation & Configuration

### Neo4j

```yaml
# docker-compose.yml
services:
  neo4j:
    image: neo4j:5.15
    ports:
      - "7474:7474"
      - "7687:7687"
    environment:
      NEO4J_AUTH: neo4j/password
```

### IPFS

```yaml
# docker-compose.yml
services:
  ipfs:
    image: ipfs/kubo:latest
    ports:
      - "5001:5001"
      - "8080:8080"
```

### TypeScript SDK Server

```crystal
# config/integrations.cr
SDK_CONFIG = {
  host: ENV["SDK_HOST"]? || "0.0.0.0",
  port: (ENV["SDK_PORT"]? || "8080").to_i,
  auth_enabled: ENV["SDK_AUTH"]? == "true",
  api_key: ENV["SDK_API_KEY"]?
}
```

---

## Testing

Run the integration tests:

```bash
# All Phase 6 tests
crystal spec spec/integrations/neo4j_integration_spec.cr
crystal spec spec/integrations/ipfs_integration_spec.cr
crystal spec spec/integrations/metta_integration_spec.cr
crystal spec spec/integrations/typescript_sdk_spec.cr

# All integration tests
crystal spec spec/integrations/
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    CrystalCog Core                          │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │  AtomSpace  │  │  Reasoning   │  │  Pattern Match   │   │
│  └──────┬──────┘  └──────────────┘  └──────────────────┘   │
│         │                                                   │
├─────────┴───────────────────────────────────────────────────┤
│                Phase 6 Integration Layer                    │
│  ┌──────────┐  ┌────────┐  ┌─────────┐  ┌──────────────┐   │
│  │  Neo4j   │  │  IPFS  │  │  MeTTa  │  │ TypeScript   │   │
│  │ Storage  │  │Storage │  │ Engine  │  │    SDK       │   │
│  └────┬─────┘  └───┬────┘  └────┬────┘  └──────┬───────┘   │
│       │            │            │               │           │
└───────┼────────────┼────────────┼───────────────┼───────────┘
        │            │            │               │
        ▼            ▼            ▼               ▼
   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────┐
   │  Neo4j  │  │  IPFS   │  │ Hyperon │  │  Web Apps   │
   │   DB    │  │ Network │  │  MeTTa  │  │ TypeScript  │
   └─────────┘  └─────────┘  └─────────┘  └─────────────┘
```

---

## Migration from Phase 5

Phase 6 is fully backward compatible with Phase 5. Existing integrations continue to work. To use new integrations:

```crystal
require "crystalcog/integrations/integration"

manager = CrystalCogIntegration.create_manager

# Phase 5 integrations (existing)
manager.initialize_all_integrations(atomspace)

# Phase 6 integrations (new)
neo4j = CrystalCog::Integrations::Neo4jClient.new("localhost")
ipfs = CrystalCog::Integrations::IPFSClient.new("localhost")
metta = CrystalCog::Integrations::MeTTaInterpreter.new
sdk_server = CrystalCog::Integrations::TypeScriptSDKServer.new
```

---

## Performance Considerations

### Neo4j
- Use batch operations for bulk inserts (1000+ atoms)
- Create indexes on frequently queried properties
- Consider relationship direction for query performance

### IPFS
- Pin important content to prevent garbage collection
- Use DAG operations for structured data
- Implement caching for frequently accessed CIDs

### MeTTa
- Limit recursion depth for complex rules
- Use specific patterns over wildcard variables
- Pre-compile frequently used rules

### TypeScript SDK
- Enable connection pooling for high-traffic scenarios
- Use WebSocket for real-time updates
- Implement client-side caching

---

## Future Roadmap

### Phase 7: Applications & Tools
- AtomSpace Explorer GUI
- Unity3D Game Integration
- Minecraft Integration

### Phase 8: Advanced AI
- Neural-MeTTa Integration
- Distributed Reasoning
- Self-Modifying Systems

---

## License

AGPL-3.0 - See LICENSE file for details.

## Contributing

Contributions welcome! Please read CONTRIBUTING.md before submitting PRs.

## Support

- GitHub Issues: https://github.com/cogpy/crystalcog/issues
- Documentation: https://crystalcog.org/docs
- Community: https://discord.gg/opencog
