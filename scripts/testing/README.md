# Testing Scripts

This directory contains test runner scripts for the CrystalCog project.

## Available Scripts

| Script | Description |
|--------|-------------|
| `test_cogserver_integration.sh` | CogServer integration testing |
| `test_integration.sh` | General integration tests |
| `test_nlp_structure.sh` | NLP structure validation tests |

## Usage

From the repository root:

```bash
# Run CogServer integration tests
./scripts/testing/test_cogserver_integration.sh

# Run general integration tests
./scripts/testing/test_integration.sh

# Run NLP structure tests
./scripts/testing/test_nlp_structure.sh
```

## See Also

- Main test runner: `scripts/test-runner.sh`
- Spec tests: `spec/`
- Standalone tests: `spec/standalone/`
