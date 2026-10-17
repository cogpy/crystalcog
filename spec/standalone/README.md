# Standalone Test Files

This directory contains standalone test scripts that can be run independently of the main spec framework.

## Available Tests

| File | Description |
|------|-------------|
| `test_advanced_nlp.cr` | Advanced NLP functionality tests |
| `test_advanced_pattern_matching.cr` | Advanced pattern matching tests |
| `test_ai_integration.cr` | AI integration tests |
| `test_attention_simple.cr` | Simple attention allocation tests |
| `test_basic.cr` | Basic functionality tests |
| `test_cogserver_api.cr` | CogServer API tests |
| `test_cogserver_websocket.cr` | WebSocket functionality tests |
| `test_distributed_integration.cr` | Distributed system integration tests |
| `test_enhanced_api.cr` | Enhanced API tests |
| `test_enhanced_pattern_matching.cr` | Enhanced pattern matching tests |
| `test_hypergraph_persistence.cr` | Hypergraph persistence tests |
| `test_learning_features.cr` | Learning system tests |
| `test_ml_features.cr` | Machine learning feature tests |
| `test_new_storage_backends.cr` | New storage backend tests |
| `test_pattern_matching.cr` | Pattern matching tests |
| `test_persistence.cr` | Persistence layer tests |
| `test_pln.cr` | PLN reasoning tests |
| `test_profiling_tools.cr` | Profiling tools tests |
| `test_query_language.cr` | Query language tests |

## Running Tests

From the repository root:

```bash
# Run a specific standalone test
crystal run spec/standalone/test_basic.cr

# Run all standalone tests
for test in spec/standalone/test_*.cr; do crystal run "$test"; done
```
