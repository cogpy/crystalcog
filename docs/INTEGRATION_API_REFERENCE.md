# CrystalCog Integration API Reference

## Overview

This document provides a complete API reference for the CrystalCog integration framework.

## Table of Contents

1. [CogPy Bridge](#cogpy-bridge)
2. [PyG Adapter](#pyg-adapter)
3. [Pygmalion Agent](#pygmalion-agent)
4. [Galatea Frontend](#galatea-frontend)
5. [Paphos Backend](#paphos-backend)
6. [Crystal Accelerator](#crystal-accelerator)
7. [Integration Manager](#integration-manager)

---

## CogPy Bridge

**Module:** `CogPyBridge`  
**File:** `src/integrations/cogpy_bridge.cr`

### Classes

#### `CogPyBridge::Config`

Configuration for the CogPy bridge.

**Properties:**
- `host : String` - Host address (default: "localhost")
- `port : Int32` - Port number (default: 5000)
- `timeout : Int32` - Connection timeout in seconds (default: 30)
- `auth_token : String?` - Optional authentication token

**Example:**
```crystal
config = CogPyBridge::Config.new(
  host: "localhost",
  port: 5000,
  timeout: 30
)
```

#### `CogPyBridge::Bridge`

Main bridge class for CogPy integration.

**Properties:**
- `config : Config` - Bridge configuration
- `atomspace : AtomSpace::AtomSpace?` - Attached AtomSpace

**Methods:**

##### `connect : Bool`
Connect to the CogPy framework.

**Returns:** `true` on success

##### `disconnect : Bool`
Disconnect from CogPy framework.

**Returns:** `true` on success

##### `attach_atomspace(atomspace : AtomSpace::AtomSpace)`
Attach an AtomSpace for cognitive operations.

##### `send_cognitive_data(data : Hash(String, String)) : Hash(String, String)`
Send cognitive data to CogPy framework.

**Parameters:**
- `data` - Hash containing cognitive data

**Returns:** Response hash with status

##### `receive_updates : Array(Hash(String, String))`
Receive cognitive updates from CogPy.

**Returns:** Array of update hashes

##### `execute_python_function(function_name : String, args : Hash(String, String)) : String`
Execute a Python cognitive function through CogPy.

**Parameters:**
- `function_name` - Name of Python function to execute
- `args` - Function arguments

**Returns:** Execution result as string

##### `status : Hash(String, String)`
Query CogPy framework status.

**Returns:** Hash with status information

---

## PyG Adapter

**Module:** `PygAdapter`  
**File:** `src/integrations/pyg_adapter.cr`

### Classes

#### `PygAdapter::Config`

Configuration for PyG integration.

**Properties:**
- `pyg_backend_url : String` - PyG backend URL (default: "http://localhost:8000")
- `batch_size : Int32` - Batch size for processing (default: 32)
- `embedding_dim : Int32` - Embedding dimension (default: 128)
- `use_gpu : Bool` - Enable GPU processing (default: false)

#### `PygAdapter::Adapter`

Main adapter for PyG framework.

**Properties:**
- `config : Config` - Adapter configuration
- `atomspace : AtomSpace::AtomSpace?` - Attached AtomSpace

**Methods:**

##### `initialize_backend : Bool`
Initialize PyG backend connection.

##### `attach_atomspace(atomspace : AtomSpace::AtomSpace)`
Attach AtomSpace for graph operations.

##### `export_atomspace_graph : Hash(String, Array(Array(Int32)))`
Convert AtomSpace graph to PyG format.

**Returns:** Hash with edge_index and node_features

##### `run_gnn_inference(graph_data : Hash(String, Array(Array(Int32)))) : Array(Float64)`
Run graph neural network inference.

**Parameters:**
- `graph_data` - Graph data in PyG format

**Returns:** Node embeddings

##### `train_gnn_model(epochs : Int32, learning_rate : Float64) : Hash(String, String)`
Train GNN model on cognitive graph.

**Parameters:**
- `epochs` - Number of training epochs
- `learning_rate` - Learning rate

**Returns:** Training results

##### `get_node_embeddings : Hash(String, Array(Float64))`
Get node embeddings from trained model.

---

## Pygmalion Agent

**Module:** `PygmalionAgent`  
**File:** `src/integrations/pygmalion_agent.cr`

### Classes

#### `PygmalionAgent::Config`

Configuration for Pygmalion integration.

**Properties:**
- `pygmalion_api_url : String` - API URL
- `model_name : String` - Model name (default: "pygmalion-13b")
- `max_context_length : Int32` - Maximum context length (default: 2048)
- `temperature : Float64` - Sampling temperature (default: 0.7)
- `echo_state_enabled : Bool` - Enable Echo State Networks (default: true)

#### `PygmalionAgent::EchoStateConfig`

Echo State Network configuration.

**Properties:**
- `reservoir_size : Int32` - Reservoir size (default: 1000)
- `spectral_radius : Float64` - Spectral radius (default: 0.95)
- `sparsity : Float64` - Sparsity level (default: 0.1)
- `tensor_signatures : Bool` - Enable tensor signatures (default: true)

#### `PygmalionAgent::Agent`

Main Pygmalion agent class.

**Properties:**
- `config : Config` - Agent configuration
- `echo_config : EchoStateConfig` - Echo state configuration
- `atomspace : AtomSpace::AtomSpace?` - Attached AtomSpace
- `conversation_history : Array(Hash(String, String))` - Conversation history

**Methods:**

##### `initialize_agent : Bool`
Initialize Pygmalion agent.

##### `attach_atomspace(atomspace : AtomSpace::AtomSpace)`
Attach AtomSpace for cognitive-conversational integration.

##### `chat(message : String, context : Hash(String, String)? = nil) : String`
Send message to Pygmalion and get response.

**Parameters:**
- `message` - User message
- `context` - Optional conversation context

**Returns:** Agent response

##### `compute_tensor_signatures : Hash(String, Array(Float64))`
Compute tensor signatures for cognitive state.

**Returns:** Hash with tensor signature arrays

##### `get_cognitive_context : Array(String)`
Get conversation context from AtomSpace.

##### `store_conversation_in_atomspace : Bool`
Store conversation history in AtomSpace.

##### `clear_history`
Clear conversation history.

---

## Galatea Frontend

**Module:** `GalateaFrontend`  
**File:** `src/integrations/galatea_frontend.cr`

### Classes

#### `GalateaFrontend::Config`

Configuration for Galatea frontend.

**Properties:**
- `host : String` - Host address (default: "0.0.0.0")
- `port : Int32` - HTTP port (default: 3000)
- `websocket_port : Int32` - WebSocket port (default: 3001)
- `cors_enabled : Bool` - Enable CORS (default: true)
- `max_connections : Int32` - Maximum connections (default: 100)

#### `GalateaFrontend::APIHandlers`

REST API endpoint handlers.

**Methods:**

##### `handle_health_check : Hash(String, String)`
Health check endpoint.

##### `handle_get_state : Hash(String, String)`
Get cognitive state.

##### `handle_atom_query(query : Hash(String, String)) : Array(Hash(String, String))`
Query atoms from frontend.

##### `handle_execute_action(action : Hash(String, String)) : Hash(String, String)`
Execute cognitive action.

##### `handle_get_visualization : Hash(String, Array(Hash(String, String)))`
Get visualization data.

#### `GalateaFrontend::WebSocketHandlers`

WebSocket handlers for real-time updates.

**Methods:**

##### `handle_connect(client_id : String)`
Handle new WebSocket connection.

##### `handle_disconnect(client_id : String)`
Handle WebSocket disconnection.

##### `handle_message(client_id : String, message : String) : String`
Handle incoming WebSocket message.

##### `broadcast_state_update(update : Hash(String, String))`
Broadcast state update to all connected clients.

##### `notify_atom_update(atom_handle : Int32, update_type : String)`
Send atom update notification.

#### `GalateaFrontend::Interface`

Main Galatea frontend interface.

**Methods:**

##### `initialize_interface : Bool`
Initialize the frontend interface.

##### `attach_atomspace(atomspace : AtomSpace::AtomSpace)`
Attach AtomSpace for cognitive operations.

##### `start : Bool`
Start the frontend server.

##### `stop : Bool`
Stop the frontend server.

---

## Paphos Backend

**Module:** `PaphosBackend`  
**File:** `src/integrations/paphos_connector.cr`

### Classes

#### `PaphosBackend::Config`

Configuration for Paphos backend.

**Properties:**
- `backend_url : String` - Backend URL (default: "http://localhost:4000")
- `api_key : String?` - API key for authentication
- `timeout : Int32` - Request timeout (default: 30)
- `retry_attempts : Int32` - Retry attempts (default: 3)
- `enable_caching : Bool` - Enable caching (default: true)

#### `PaphosBackend::AuthHandler`

Authentication and authorization handler.

**Methods:**

##### `authenticate : Bool`
Authenticate with Paphos backend.

##### `validate_token : Bool`
Validate authentication token.

##### `refresh_token : Bool`
Refresh authentication token.

#### `PaphosBackend::PersistenceLayer`

Data persistence layer.

**Methods:**

##### `store_atomspace_data : Bool`
Store AtomSpace data to Paphos backend.

##### `load_atomspace_data : Bool`
Load AtomSpace data from Paphos backend.

##### `store_snapshot(snapshot_id : String, data : Hash(String, String)) : Bool`
Store cognitive state snapshot.

##### `load_snapshot(snapshot_id : String) : Hash(String, String)?`
Load cognitive state snapshot.

##### `query_data(query : Hash(String, String)) : Array(Hash(String, String))`
Query stored data.

#### `PaphosBackend::Connector`

Main Paphos connector class.

**Methods:**

##### `initialize_connection : Bool`
Initialize connection to Paphos backend.

##### `attach_atomspace(atomspace : AtomSpace::AtomSpace)`
Attach AtomSpace for cognitive operations.

##### `send_command(command : String, params : Hash(String, String)) : Hash(String, String)`
Send cognitive command to backend.

##### `receive_events : Array(Hash(String, String))`
Receive events from backend.

##### `synchronize_state : Bool`
Synchronize cognitive state with backend.

##### `execute_service_function(function_name : String, args : Hash(String, String)) : String`
Execute backend service function.

##### `test_connection : Bool`
Test backend connection.

---

## Crystal Accelerator

**Module:** `CrystalAccelerator`  
**File:** `src/integrations/crystal_accelerator.cr`

### Classes

#### `CrystalAccelerator::Config`

Configuration for acceleration engine.

**Properties:**
- `enable_parallel_processing : Bool` - Enable parallel processing (default: true)
- `thread_pool_size : Int32` - Thread pool size (default: 4)
- `cache_size : Int32` - Cache size (default: 10000)
- `optimization_level : Int32` - Optimization level 0-3 (default: 2)
- `profile_performance : Bool` - Enable profiling (default: false)

#### `CrystalAccelerator::PerformanceProfiler`

Performance profiler for monitoring.

**Methods:**

##### `record_timing(operation : String, duration : Float64)`
Record operation timing.

##### `get_statistics : Hash(String, Hash(String, Float64))`
Get performance statistics.

##### `clear_metrics`
Clear all metrics.

#### `CrystalAccelerator::BatchProcessor`

Batch processing utilities.

**Methods:**

##### `process_atoms_batch(atom_handles : Array(Int32), &block : Int32 -> Nil)`
Process atoms in batches.

##### `optimized_batch_query(queries : Array(Hash(String, String))) : Array(Hash(String, String))`
Batch query optimization.

#### `CrystalAccelerator::CacheManager`

Cache manager for frequently accessed data.

**Methods:**

##### `get(key : String) : String?`
Get value from cache.

##### `set(key : String, value : String)`
Store value in cache.

##### `stats : Hash(String, String)`
Get cache statistics.

##### `clear`
Clear cache.

#### `CrystalAccelerator::Engine`

Main acceleration engine.

**Methods:**

##### `initialize_engine : Bool`
Initialize acceleration engine.

##### `attach_atomspace(atomspace : AtomSpace::AtomSpace)`
Attach AtomSpace for accelerated operations.

##### `execute_accelerated(operation_name : String, &block)`
Execute accelerated operation with timing.

##### `optimize_atomspace_access`
Optimize AtomSpace access patterns.

##### `performance_report : Hash(String, Hash(String, Float64))`
Get performance report.

---

## Integration Manager

**Module:** `CrystalCogIntegration`  
**File:** `src/integrations/integration.cr`

### Classes

#### `CrystalCogIntegration::Manager`

Main integration manager coordinating all integrations.

**Properties:**
- `cogpy_bridge : CogPyBridge::Bridge?`
- `pyg_adapter : PygAdapter::Adapter?`
- `pygmalion_agent : PygmalionAgent::Agent?`
- `galatea_frontend : GalateaFrontend::Interface?`
- `paphos_connector : PaphosBackend::Connector?`
- `crystal_accelerator : CrystalAccelerator::Engine?`
- `atomspace : AtomSpace::AtomSpace?`

**Methods:**

##### `initialize_all_integrations(atomspace : AtomSpace::AtomSpace)`
Initialize all integration components.

**Parameters:**
- `atomspace` - AtomSpace to attach to all integrations

##### `initialize_integration(integration_name : String, atomspace : AtomSpace::AtomSpace, config : Hash(String, String)? = nil)`
Initialize specific integration.

**Parameters:**
- `integration_name` - Name of integration: "cogpy", "pyg", "pygmalion", "galatea", "paphos", "accelerator"
- `atomspace` - AtomSpace to attach
- `config` - Optional configuration hash

##### `get_integration_status : Hash(String, Hash(String, String))`
Get status of all integrations.

**Returns:** Hash mapping integration names to status hashes

##### `execute_cognitive_pipeline(input : String) : Hash(String, String)`
Execute integrated cognitive pipeline.

**Parameters:**
- `input` - Input query or data

**Returns:** Hash with pipeline results

##### `shutdown_all`
Shutdown all integrations.

### Factory Methods

##### `CrystalCogIntegration.create_manager : Manager`
Create a new integration manager.

---

## Usage Examples

### Initialize All Integrations

```crystal
require "./src/integrations/integration"

atomspace = AtomSpace::AtomSpace.new
manager = CrystalCogIntegration.create_manager
manager.initialize_all_integrations(atomspace)
```

### Execute Cognitive Pipeline

```crystal
result = manager.execute_cognitive_pipeline("What is intelligence?")
puts result["pygmalion_response"]
puts result["status"]
```

### Use Individual Components

```crystal
# CogPy Bridge
bridge = manager.cogpy_bridge
data = {"query" => "analyze", "concept" => "reasoning"}
response = bridge.send_cognitive_data(data)

# Pygmalion Agent
agent = manager.pygmalion_agent
chat_response = agent.chat("Explain cognitive architectures")

# Crystal Accelerator
accelerator = manager.crystal_accelerator
result = accelerator.execute_accelerated("reasoning") do
  # Your cognitive processing code
end
```

### Check Integration Status

```crystal
status = manager.get_integration_status
status.each do |name, component_status|
  puts "#{name}: #{component_status["status"]}"
end
```

---

## Configuration

See `config/integration_config.yml` for configuration options.

## License

AGPL-3.0 - See LICENSE file for details
