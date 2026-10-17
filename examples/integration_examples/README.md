# CrystalCog Integration Examples

This directory contains example programs demonstrating the integration framework for CrystalCog.

## Integration Components

The integration framework provides bridges to the following systems:

1. **CogPy/PyG Framework** - Python cognitive processing and graph neural networks
2. **Pygmalion System** - Advanced conversational AI with Echo State Networks
3. **Galatea Frontend** - Web-based frontend interface with REST API and WebSocket
4. **Paphos Backend** - Backend service for data persistence and coordination
5. **Crystal Acceleration Engine** - Performance optimization and caching layer

## Examples

### Complete Integration Demo

**File:** `complete_integration_demo.cr`

Demonstrates the full integration framework with all components:

```bash
# Run the complete integration demo
crystal run examples/integration_examples/complete_integration_demo.cr

# Or build and run
crystal build examples/integration_examples/complete_integration_demo.cr -o integration_demo
./integration_demo
```

This example shows:
- Initializing all integration components
- Checking integration status
- Executing integrated cognitive pipeline
- Using individual components
- Proper shutdown procedures

## Running from Main Executable

You can also run the integration demo from the main CrystalCog executable:

```bash
# Build the main executable
crystal build src/crystalcog.cr

# Run integration demo
./crystalcog integration
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

## Documentation

For detailed documentation, see:

- [Integration Guide](../../docs/INTEGRATION_GUIDE.md) - Complete integration documentation
- [API Documentation](../../docs/API_DOCUMENTATION.md) - API reference

## Integration Tests

Run integration tests:

```bash
# Test all integrations
crystal spec spec/integrations/

# Test specific integration
crystal spec spec/integrations/integration_spec.cr
```

## Building Integration Components

Build the integration demo as a standalone binary:

```bash
# Build integration demo
shards build integration_demo

# Run built binary
./bin/integration_demo
```

## Requirements

Most integrations work out of the box with CrystalCog. For full functionality:

- **CogPy**: Install Python and the cogpy package
- **PyG**: Install PyTorch Geometric (optional, for GNN features)
- **Pygmalion**: API key for Pygmalion service (optional)
- **Galatea**: No additional requirements
- **Paphos**: Backend service running (optional)
- **Accelerator**: No additional requirements

## Architecture

The integration framework uses a manager pattern to coordinate all integrations:

```
CrystalCogIntegration::Manager
├── CogPyBridge::Bridge          (Python integration)
├── PygAdapter::Adapter          (Graph neural networks)
├── PygmalionAgent::Agent        (Conversational AI)
├── GalateaFrontend::Interface   (Web interface)
├── PaphosBackend::Connector     (Backend service)
└── CrystalAccelerator::Engine   (Performance optimization)
```

Each component can be used independently or as part of the integrated pipeline.

## Example Output

When running the integration demo, you should see output similar to:

```
============================================================
CrystalCog Integration Example
============================================================

1. Creating AtomSpace...
   Added concepts: dog, cat, animal

2. Creating Integration Manager...
   Manager created

3. Initializing Individual Integrations...
   - Initializing CogPy bridge...
   - Initializing PyG adapter...
   - Initializing Pygmalion agent...
   - Initializing Galatea frontend...
   - Initializing Paphos connector...
   - Initializing Crystal accelerator...
   All integrations initialized!

4. Checking Integration Status...
   COGPY:
     - bridge_status: connected
     - cogpy_version: 0.1.0
     - atomspace_attached: true
   
   [... more status output ...]

5. Executing Integrated Cognitive Pipeline...
   Input: What is the relationship between dogs and animals?
   
   Pipeline Results:
     - pygmalion_response: [AI response]
     - cogpy_processing: success
     - paphos_sync: completed
     - galatea_update: broadcasted
     - status: completed

[... rest of demo output ...]
```

## Contributing

To add new integration examples:

1. Create a new `.cr` file in this directory
2. Require the integration framework: `require "../../src/integrations/integration"`
3. Add documentation to this README
4. Add tests to `spec/integrations/`

## License

AGPL-3.0 - See LICENSE file for details
