# CrystalCog CI/CD Pipeline Documentation

This document describes the comprehensive CI/CD pipeline setup for automated testing in the CrystalCog project.

## Overview

The CI/CD pipeline provides multiple layers of automated testing to ensure code quality, performance, and reliability:

1. **Basic Build & Test** - Fast feedback for every commit
2. **Comprehensive Testing** - Multi-platform, multi-version testing
3. **Performance Monitoring** - Benchmark tracking and regression detection
4. **Test Monitoring** - Automated test result analysis and reporting

## Workflow Files

### 1. `crystal-build.yml` - Primary Build and Test
**Trigger**: Push to main, pull requests
**Purpose**: Quick validation of changes
**Features**:
- Crystal compilation
- Unit test execution
- Integration test runs
- Error handling with automatic issue creation
- Build artifact uploads

### 2. `crystal-comprehensive-ci.yml` - Comprehensive Testing
**Trigger**: Manual, scheduled (nightly)
**Purpose**: Thorough testing across environments
**Features**:
- Test matrix (multiple Crystal versions and OS)
- Performance benchmarking
- Code coverage analysis
- Security scanning
- Multi-platform compatibility

### 3. `test-monitoring.yml` - Test Result Monitoring
**Trigger**: After other workflows, weekly schedule
**Purpose**: Track test health and generate reports
**Features**:
- Success rate monitoring
- Automatic issue creation for test instability
- Test trend analysis
- Weekly test reports

## Test Organization

### Directory Structure
```
spec/                    # Unit tests (Crystal spec framework)
├── cogutil/            # cogutil component tests
├── atomspace/          # atomspace component tests
├── cogserver/          # cogserver component tests
└── pattern_matching/   # pattern matching tests

test_*.cr               # Integration tests (root level)
├── test_basic.cr       # Basic functionality tests
├── test_pln.cr         # PLN reasoning tests
├── test_pattern_matching.cr # Pattern matching tests
└── test_cogserver_api.cr    # CogServer API tests

benchmarks/             # Performance benchmarks
scripts/test-runner.sh  # Comprehensive test runner script
.github/testing-config.yml # Test configuration
```

### Test Types

1. **Unit Tests** - Individual component testing
2. **Integration Tests** - Cross-component functionality
3. **Performance Tests** - Benchmark and regression testing
4. **Security Tests** - Vulnerability scanning
5. **Compatibility Tests** - Multi-platform and version testing

## Configuration

### Test Matrix Configuration
The comprehensive CI runs tests across:
- **Operating Systems**: Ubuntu (latest, 20.04), macOS (latest)
- **Crystal Versions**: 1.10.1, 1.9.2, nightly
- **Build Types**: Debug, release
- **Test Types**: Unit, integration, performance

### Quality Gates
Tests must pass the following quality gates:
- Build success: Required
- Unit tests: Required (100% pass)
- Integration tests: Required (100% pass)
- Code formatting: Warning level
- Security scan: Warning level
- Performance regression: Warning level

## Running Tests

### Local Development

Use the test runner script for comprehensive local testing:

```bash
# Install and make executable (first time)
chmod +x scripts/test-runner.sh

# Run all tests
./scripts/test-runner.sh --all

# Run specific test types
./scripts/test-runner.sh --unit --verbose
./scripts/test-runner.sh --integration
./scripts/test-runner.sh --benchmarks --coverage

# Test specific component
./scripts/test-runner.sh --component atomspace

# Run with linting and build
./scripts/test-runner.sh --lint --build --integration
```

**Validation Status**: The test runner script has been fully validated. See the [Test Runner Validation Report](TEST_RUNNER_VALIDATION_REPORT.md) for detailed validation results and known issues.

### CI/CD Pipeline

Tests run automatically on:
- **Every commit** to main branch (basic tests)
- **Every pull request** (basic tests + coverage analysis)
- **Nightly schedule** (comprehensive tests)
- **Manual trigger** (comprehensive tests with options)

### Manual Workflow Triggers

You can manually trigger comprehensive testing:

1. Go to Actions tab in GitHub
2. Select "Comprehensive Crystal CI/CD" workflow
3. Click "Run workflow"
4. Choose options:
   - Run benchmarks: true/false
   - Generate coverage: true/false

## Test Monitoring and Reporting

### Automatic Monitoring
The pipeline automatically:
- Tracks success/failure rates
- Detects test instability patterns
- Creates GitHub issues for recurring failures
- Generates weekly test reports

### Success Rate Thresholds
- **>95%**: Excellent - tests are very stable
- **80-95%**: Good - minor instability, monitor closely  
- **<80%**: Poor - automatic issue creation triggered

### Issue Creation
Automatic issues are created when:
- Multiple recent test failures (≥2 failures)
- Success rate drops below 80%
- Consistent failure patterns detected

## Artifacts and Reports

### Build Artifacts
- Compiled Crystal executables
- Test result files (JUnit XML)
- Build logs
- Coverage reports

### Performance Data
- Benchmark results
- Performance trend analysis
- Memory usage reports
- Execution time metrics

### Test Reports
- Weekly comprehensive test reports
- Success/failure trend analysis
- Component-specific test status
- Recommendations for improvements

## Integration with Development Workflow

### Pull Request Workflow
1. Developer creates PR
2. Basic build and test runs automatically
3. Coverage analysis generated for PR
4. Test results commented on PR
5. Merge allowed only if tests pass

### Main Branch Workflow
1. Code merged to main
2. Full test suite runs
3. Artifacts built and stored
4. Test monitoring updates statistics
5. Issues created if instability detected

### Nightly Testing
1. Comprehensive test matrix runs
2. Performance benchmarks executed
3. Security scans performed
4. Reports generated and stored
5. Trends analyzed and documented

## Troubleshooting

### Common Issues

**Dependency Installation Fails**
- Check `shard.yml` for correct versions
- Verify system dependencies are available
- Review Crystal version compatibility

**Tests Flaky or Unstable**
- Check for race conditions
- Ensure proper test isolation
- Verify test data cleanup
- Consider adding retry mechanisms

**Performance Regressions**
- Review recent code changes
- Check algorithm complexity changes
- Verify optimization flags
- Compare benchmark results

**Security Scan Failures**
- Update vulnerable dependencies
- Review security advisories
- Check for exposed secrets
- Validate input sanitization

### Getting Help

1. Check the latest test report in `docs/testing/latest-report.md`
2. Review workflow run logs in GitHub Actions
3. Check for open issues with `testing` or `ci-cd` labels
4. Use the test runner script locally to reproduce issues

## Best Practices

### Writing Tests
- Write deterministic, repeatable tests
- Use descriptive test names and documentation
- Avoid external dependencies where possible
- Clean up resources after tests
- Test edge cases and error conditions

### Maintaining Tests
- Review and update tests with code changes
- Remove obsolete tests when refactoring
- Keep test execution time reasonable
- Monitor test coverage and fill gaps
- Update benchmarks when performance changes

### CI/CD Optimization
- Use caching for faster builds
- Parallelize test execution where possible
- Fail fast for critical issues
- Provide clear failure messages
- Monitor resource usage and costs

## Roadmap Integration

This CI/CD pipeline directly addresses the development roadmap item:
- ✅ **Setup CI/CD pipeline for automated testing**

The implementation provides comprehensive automated testing infrastructure that supports the project's development goals and ensures high code quality throughout the OpenCog to Crystal conversion process.