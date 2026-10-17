# CrystalCog Integration Guide

## Overview

This guide covers the integration of CrystalCog with external systems and frameworks:

- **CogPy/PyG Framework** - Python cognitive processing framework
- **Pygmalion System** - Advanced conversational AI with deep cognitive architecture
- **Galatea Frontend** - Web-based frontend interface
- **Paphos Backend** - Backend service for data persistence and coordination
- **Crystal Acceleration Engine** - Performance optimization layer

## Quick Start

### 1. Basic Integration Setup

```crystal
require "./src/integrations/integration"
require "./src/atomspace/atomspace"

# Create an AtomSpace
atomspace = AtomSpace::AtomSpace.new

# Create integration manager
manager = CrystalCogIntegration.create_manager

# Initialize all integrations
manager.initialize_all_integrations(atomspace)

# Check integration status
status = manager.get_integration_status
puts status
```

### 2. Individual Integration Setup

You can also initialize integrations individually:

```crystal
# Initialize only specific integrations
manager = CrystalCogIntegration.create_manager

# Initialize only CogPy bridge
manager.initialize_integration("cogpy", atomspace)

# Initialize only Pygmalion agent
manager.initialize_integration("pygmalion", atomspace)

# Initialize only Galatea frontend
manager.initialize_integration("galatea", atomspace)
```

## Integration Components

### CogPy Bridge

The CogPy bridge provides seamless integration with Python cognitive processing:

```crystal
require "./src/integrations/cogpy_bridge"

# Create and configure bridge
config = CogPyBridge::Config.new(
  host: "localhost",
  port: 5000,
  timeout: 30
)

bridge = CogPyBridge::Bridge.new(config)
bridge.attach_atomspace(atomspace)
bridge.connect

# Send cognitive data
data = {"concept" => "intelligence", "operation" => "analyze"}
response = bridge.send_cognitive_data(data)

# Execute Python function
result = bridge.execute_python_function("process_cognitive_state", data)

# Check status
puts bridge.status
```

### PyG Adapter

Integration with PyTorch Geometric for graph neural networks:

```crystal
require "./src/integrations/pyg_adapter"

# Create adapter
adapter = PygAdapter.create_default_adapter
adapter.attach_atomspace(atomspace)
adapter.initialize_backend

# Export AtomSpace graph
graph_data = adapter.export_atomspace_graph

# Run GNN inference
embeddings = adapter.run_gnn_inference(graph_data)

# Train GNN model
training_result = adapter.train_gnn_model(epochs: 100, learning_rate: 0.001)

# Get node embeddings
node_embeddings = adapter.get_node_embeddings
```

### Pygmalion Agent

Advanced conversational AI with Echo State Networks:

```crystal
require "./src/integrations/pygmalion_agent"

# Create agent
agent = PygmalionAgent.create_default_agent
agent.attach_atomspace(atomspace)
agent.initialize_agent

# Chat with agent
response = agent.chat("Tell me about artificial intelligence")
puts response

# Get cognitive context
context = agent.get_cognitive_context

# Compute tensor signatures
signatures = agent.compute_tensor_signatures

# Store conversation in AtomSpace
agent.store_conversation_in_atomspace
```

### Galatea Frontend

Web-based frontend interface with REST API and WebSocket support:

```crystal
require "./src/integrations/galatea_frontend"

# Create frontend interface
frontend = GalateaFrontend.create_default_interface
frontend.attach_atomspace(atomspace)
frontend.initialize_interface

# Start the server
frontend.start

# API endpoints will be available at:
# - http://localhost:3000/health
# - http://localhost:3000/state
# - http://localhost:3000/atoms/query
# - http://localhost:3000/execute
# - http://localhost:3000/visualization

# WebSocket available at:
# - ws://localhost:3001
```

### Paphos Backend

Backend service for data persistence and coordination:

```crystal
require "./src/integrations/paphos_connector"

# Create connector
connector = PaphosBackend.create_authenticated_connector(
  backend_url: "http://localhost:4000",
  api_key: "your-api-key"
)

connector.attach_atomspace(atomspace)
connector.initialize_connection

# Send command
result = connector.send_command("analyze_cognitive_state", {"depth" => "3"})

# Synchronize state
connector.synchronize_state

# Store snapshot
connector.persistence.store_snapshot("snapshot_1", {"state" => "active"})

# Load snapshot
snapshot = connector.persistence.load_snapshot("snapshot_1")
```

### Crystal Acceleration Engine

Performance optimization layer:

```crystal
require "./src/integrations/crystal_accelerator"

# Create high-performance engine
accelerator = CrystalAccelerator.create_high_performance_engine
accelerator.attach_atomspace(atomspace)
accelerator.initialize_engine

# Execute accelerated operation
result = accelerator.execute_accelerated("complex_reasoning") do
  # Your cognitive processing code here
  "reasoning complete"
end

# Get performance report
report = accelerator.performance_report
puts report

# Get engine status
status = accelerator.status
puts "Cache hit rate: #{status["cache_hit_rate"]}"
```

## Integrated Cognitive Pipeline

Execute a complete cognitive pipeline using all integrations:

```crystal
manager = CrystalCogIntegration.create_manager
manager.initialize_all_integrations(atomspace)

# Execute pipeline
result = manager.execute_cognitive_pipeline("What is consciousness?")

puts "Pipeline result:"
puts "  Pygmalion response: #{result["pygmalion_response"]}"
puts "  CogPy processing: #{result["cogpy_processing"]}"
puts "  Paphos sync: #{result["paphos_sync"]}"
puts "  Galatea update: #{result["galatea_update"]}"
puts "  Status: #{result["status"]}"
```

## Configuration

Edit `config/integration_config.yml` to customize integration settings:

```yaml
cogpy:
  host: "localhost"
  port: 5000

pygmalion:
  model_name: "pygmalion-13b"
  temperature: 0.7

galatea:
  port: 3000
  websocket_port: 3001

paphos:
  backend_url: "http://localhost:4000"

accelerator:
  thread_pool_size: 8
  optimization_level: 3
```

## Environment Variables

You can also configure integrations using environment variables:

```bash
export COGPY_HOST="localhost"
export COGPY_PORT="5000"
export PYGMALION_API_URL="https://api.pygmalion.chat"
export GALATEA_PORT="3000"
export PAPHOS_BACKEND_URL="http://localhost:4000"
export PAPHOS_API_KEY="your-api-key"
```

## Testing Integrations

Run integration tests:

```bash
# Test all integrations
crystal spec spec/integrations/

# Test specific integration
crystal spec spec/integrations/cogpy_bridge_spec.cr
crystal spec spec/integrations/pygmalion_agent_spec.cr
crystal spec spec/integrations/galatea_frontend_spec.cr
```

## Troubleshooting

### Connection Issues

If integrations fail to connect:

1. Check that all services are running
2. Verify configuration in `config/integration_config.yml`
3. Check firewall settings
4. Review logs for error messages

### Performance Issues

If performance is degraded:

1. Enable the Crystal Acceleration Engine
2. Increase thread pool size
3. Enable caching in Paphos connector
4. Profile performance with `profile_performance: true`

### Authentication Errors

If authentication fails:

1. Verify API keys are correct
2. Check token expiration
3. Ensure proper permissions

## API Reference

See `docs/INTEGRATION_API_REFERENCE.md` for detailed API documentation.

## Examples

See `examples/integration_examples/` for complete working examples.

## License

AGPL-3.0 License - See LICENSE file for details.
