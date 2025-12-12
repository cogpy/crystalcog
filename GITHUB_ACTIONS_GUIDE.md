# GitHub Actions CI/CD Guide for CrystalCog

## Overview

This document describes the comprehensive CI/CD pipeline implemented for CrystalCog using GitHub Actions. The pipeline includes automated testing, benchmarking, security scanning, and deployment workflows.

## Workflow Architecture

### 1. **CI/CD Pipeline** (`ci-e2e.yml`)

**Purpose**: Main continuous integration and delivery pipeline

**Triggers**:
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop`
- Daily at 2 AM UTC
- Manual dispatch with options

**Jobs**:

#### Quick Check (5-10 minutes)
- Fast validation to fail early
- Format checking
- Syntax validation
- No dependencies installed

#### Build and Test (15-30 minutes)
- Full dependency installation
- Build main executable and components
- Run unit tests with JUnit output
- Upload test results and build artifacts

#### Integration Tests (10-20 minutes)
- Run integration test suite
- Test basic functionality, PLN, pattern matching
- Test CogServer API
- Test WebSocket monitoring

#### E2E Tests (20-30 minutes)
- Start CogServer
- Test REST API endpoints
- Test atom operations
- Test persistence layer
- Full system integration validation

#### Performance Benchmarks (10-20 minutes)
- Run distributed storage benchmarks
- Measure cache performance
- Track performance metrics over time
- Upload benchmark results

#### Security Scan (10-15 minutes)
- Trivy vulnerability scanning
- Dependency audit
- SARIF report upload to GitHub Security

#### CI Status Summary
- Aggregate all job results
- Generate summary report
- Fail if core tests fail

**Status**: ✅ Production Ready

---

### 2. **Comprehensive CI** (`crystal-comprehensive-ci.yml`)

**Purpose**: Extended testing with multiple configurations

**Updates Applied**:
- ✅ Fixed Crystal version to 1.14.0 (removed problematic 1.9.2 and 1.10.1)
- ✅ Removed version matrix that caused linker errors
- ✅ Simplified to single stable version

**Triggers**:
- Push to `main`, `develop`, `cryscog`
- Pull requests
- Daily at 2 AM UTC
- Manual dispatch

**Jobs**:
- Test matrix (single version now)
- Performance benchmarks
- Code coverage analysis
- Security scanning
- CI status summary

**Status**: ✅ Fixed and Ready

---

### 3. **Crystal Build** (`crystal-build.yml`)

**Purpose**: Fast build and test workflow

**Updates Applied**:
- ✅ Updated Crystal version to 1.14.0

**Triggers**:
- Push to `main`
- Pull requests to `main`
- Manual dispatch

**Jobs**:
- Install Crystal and dependencies
- Build main executable
- Run basic tests
- Create GitHub issues on failure

**Status**: ✅ Fixed and Ready

---

### 4. **Release and Deploy** (`release.yml`)

**Purpose**: Automated release and deployment

**Triggers**:
- Push tags matching `v*.*.*`
- Manual dispatch with version input

**Jobs**:

#### Build Release (30-45 minutes)
- Build for Linux and macOS
- Create static binaries
- Generate tarballs
- Upload artifacts

#### Create Release (5-10 minutes)
- Download all artifacts
- Generate release notes
- Create GitHub release
- Attach binaries

#### Docker Build (15-30 minutes)
- Build Docker image
- Push to GitHub Container Registry
- Tag as version and latest

#### Publish Packages (5-10 minutes)
- Placeholder for package registry publishing
- Documentation for manual installation

#### Deployment Notification
- Generate deployment summary
- Create status report

**Status**: ✅ Production Ready

---

### 5. **Nightly E2E Tests** (`nightly-e2e.yml`)

**Purpose**: Comprehensive overnight testing

**Triggers**:
- Daily at 3 AM UTC
- Manual dispatch with test suite selection

**Test Suites**:

#### AtomSpace E2E (30-45 minutes)
- Stress tests (10,000 atoms, 5,000 links)
- Query performance tests
- Pattern matching tests
- Persistence tests

#### CogServer E2E (20-30 minutes)
- Build and start CogServer
- Load testing (100 concurrent requests)
- API endpoint validation
- Performance monitoring

#### Distributed System E2E (30-45 minutes)
- Distributed cache tests
- Multi-node simulation
- Cache statistics validation
- Network I/O reduction tests

#### Performance Regression E2E (45-60 minutes)
- Comprehensive benchmarks
- Performance threshold validation
- Regression detection
- Historical comparison

#### WebSocket E2E (15-20 minutes)
- WebSocket connection tests
- Real-time monitoring validation
- Command handling tests
- Broadcasting tests

#### E2E Summary
- Aggregate results
- Generate report
- Fail on regressions

**Status**: ✅ Production Ready

---

## Workflow Fixes Applied

### Issues Identified

1. **Crystal Version Compatibility**
   - Crystal 1.9.2 and 1.10.1 causing linker errors
   - Missing object files during compilation
   - Cache corruption issues

2. **Test Timeouts**
   - Some tests running indefinitely
   - No timeout protection

3. **Missing E2E Coverage**
   - No comprehensive end-to-end testing
   - Limited integration test coverage

### Solutions Implemented

1. **Version Standardization**
   - Updated all workflows to Crystal 1.14.0
   - Removed problematic version matrix
   - Single stable version for consistency

2. **Timeout Protection**
   - Added timeouts to all jobs
   - Added timeouts to individual test steps
   - Prevents hanging builds

3. **Comprehensive E2E Testing**
   - Created dedicated E2E workflow
   - Added nightly comprehensive tests
   - Stress testing and load testing

4. **Better Error Handling**
   - Continue-on-error for non-critical steps
   - Better failure reporting
   - Artifact upload on failure

---

## Workflow Usage

### Running CI/CD Pipeline

**Automatic**: Triggered on push/PR to main or develop

**Manual**:
```bash
# Via GitHub CLI
gh workflow run ci-e2e.yml

# With options
gh workflow run ci-e2e.yml \
  -f run_benchmarks=true \
  -f run_e2e_tests=true
```

### Creating a Release

**Via Git Tag**:
```bash
git tag v1.0.0
git push origin v1.0.0
```

**Manual**:
```bash
gh workflow run release.yml -f version=v1.0.0
```

### Running Nightly Tests

**Automatic**: Runs daily at 3 AM UTC

**Manual**:
```bash
# Run all tests
gh workflow run nightly-e2e.yml

# Run specific suite
gh workflow run nightly-e2e.yml -f test_suite=performance
```

### Checking Workflow Status

```bash
# List recent runs
gh run list --limit 10

# View specific run
gh run view <run-id>

# View failed logs
gh run view <run-id> --log-failed

# Watch live run
gh run watch
```

---

## Artifacts and Reports

### Test Results
- **Location**: Uploaded as artifacts
- **Retention**: 7 days
- **Format**: JUnit XML, text logs

### Benchmark Results
- **Location**: Uploaded as artifacts
- **Retention**: 30 days
- **Format**: Text reports with metrics

### Security Reports
- **Location**: GitHub Security tab
- **Format**: SARIF
- **Integration**: CodeQL

### Build Artifacts
- **Location**: Uploaded as artifacts
- **Retention**: 7 days
- **Contents**: Binaries, libraries

### Release Artifacts
- **Location**: GitHub Releases
- **Format**: tar.gz archives
- **Platforms**: Linux, macOS

---

## Performance Metrics

### CI/CD Pipeline Timing

| Job | Duration | Frequency |
|-----|----------|-----------|
| Quick Check | 5-10 min | Every push/PR |
| Build & Test | 15-30 min | Every push/PR |
| Integration Tests | 10-20 min | Every push/PR |
| E2E Tests | 20-30 min | Push to main, manual |
| Benchmarks | 10-20 min | Manual, nightly |
| Security Scan | 10-15 min | Every push/PR |
| **Total Pipeline** | **45-90 min** | Every push/PR |

### Nightly E2E Timing

| Test Suite | Duration |
|------------|----------|
| AtomSpace E2E | 30-45 min |
| CogServer E2E | 20-30 min |
| Distributed E2E | 30-45 min |
| Performance E2E | 45-60 min |
| WebSocket E2E | 15-20 min |
| **Total Nightly** | **2-3 hours** |

---

## Best Practices

### For Developers

1. **Before Pushing**
   - Run `crystal tool format` locally
   - Run `crystal spec` to ensure tests pass
   - Check `crystal build --no-codegen` for syntax errors

2. **Pull Requests**
   - Wait for CI to pass before requesting review
   - Address any CI failures promptly
   - Check benchmark results for performance regressions

3. **Releases**
   - Use semantic versioning (v1.2.3)
   - Update CHANGELOG.md before tagging
   - Test release process in fork first

### For Maintainers

1. **Monitoring**
   - Check nightly test results daily
   - Review security scan reports weekly
   - Monitor performance trends monthly

2. **Maintenance**
   - Update Crystal version quarterly
   - Review and update dependencies monthly
   - Clean up old workflow runs periodically

3. **Optimization**
   - Cache dependencies aggressively
   - Parallelize independent jobs
   - Use fail-fast for quick feedback

---

## Troubleshooting

### Common Issues

#### 1. Linker Errors
**Symptom**: `ld: cannot find *.o: No such file or directory`

**Solution**:
- Use Crystal 1.14.0 or later
- Clear Crystal cache: `rm -rf ~/.cache/crystal`
- Ensure all system dependencies installed

#### 2. Test Timeouts
**Symptom**: Tests hang indefinitely

**Solution**:
- Add timeout to test steps
- Use `timeout` command: `timeout 60 crystal spec`
- Check for infinite loops in tests

#### 3. Dependency Installation Failures
**Symptom**: `shards install` fails

**Solution**:
- Check shard.yml syntax
- Verify dependency versions
- Check network connectivity
- Clear shard cache: `rm -rf lib/ shard.lock`

#### 4. Workflow Not Triggering
**Symptom**: Push doesn't trigger workflow

**Solution**:
- Check branch name matches trigger
- Verify file paths match trigger patterns
- Check if workflow is disabled
- Review GitHub Actions permissions

---

## Workflow Files Summary

| File | Purpose | Status |
|------|---------|--------|
| `ci-e2e.yml` | Main CI/CD pipeline | ✅ New |
| `release.yml` | Release automation | ✅ New |
| `nightly-e2e.yml` | Nightly E2E tests | ✅ New |
| `crystal-comprehensive-ci.yml` | Extended CI | ✅ Fixed |
| `crystal-build.yml` | Fast build/test | ✅ Fixed |
| `crystal.yml` | Legacy | ⚠️ Keep for compatibility |

---

## Migration Notes

### From Old Workflows

The new workflows replace/improve:
- Multiple version testing (now single stable version)
- Manual test execution (now automated E2E)
- Ad-hoc benchmarking (now scheduled)
- Manual releases (now automated)

### Backward Compatibility

- Old workflows still present but not triggered
- Can be safely removed after validation
- New workflows cover all previous functionality

---

## Future Enhancements

### Planned Improvements

1. **Matrix Testing**
   - Add macOS and Windows once stable
   - Test multiple Crystal versions when compatible

2. **Advanced Benchmarking**
   - Historical performance tracking
   - Regression detection with alerts
   - Performance comparison graphs

3. **Deployment Automation**
   - Automatic deployment to staging
   - Canary deployments
   - Rollback automation

4. **Enhanced Reporting**
   - Test coverage trends
   - Flaky test detection
   - Dependency vulnerability tracking

---

## Support and Contact

For issues with CI/CD workflows:
1. Check this documentation first
2. Review workflow run logs
3. Open GitHub issue with workflow run link
4. Tag with `ci/cd` label

---

**Last Updated**: December 12, 2025  
**Crystal Version**: 1.14.0  
**Status**: ✅ All workflows validated and production-ready
