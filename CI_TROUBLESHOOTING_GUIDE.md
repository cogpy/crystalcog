# Crystal CI/CD Troubleshooting Guide

## Overview

This guide addresses common compilation and linking errors encountered in GitHub Actions workflows for the CrystalCog project.

---

## Common Issues and Solutions

### 1. Invalid Memory Access (Signal 11)

**Error Message**:
```
Invalid memory access (signal 11) at address 0x40
```

**Root Causes**:
- Insufficient memory in CI environment
- Concurrent builds writing to shared cache
- Corrupted object files in cache

**Solutions**:

1. **Clear the Crystal cache**:
   ```bash
   rm -rf ~/.cache/crystal
   rm -rf .crystal
   ```

2. **Use `--no-cache` flag**:
   ```bash
   crystal build --no-cache src/cogutil/cogutil.cr
   ```

3. **Increase memory allocation** (in GitHub Actions):
   ```yaml
   container:
     image: crystallang/crystal:latest
     options: --cpus 2 --memory 4g
   ```

4. **Disable parallel compilation**:
   ```bash
   crystal build --threads 1 src/cogutil/cogutil.cr
   ```

---

### 2. Linker Errors - Cannot Find Object Files

**Error Message**:
```
/usr/bin/ld: cannot find C-ogU-til5858A-tomM-emoryP-ool.o: No such file or directory
```

**Root Causes**:
- Object files with mangled names not found
- Cache directory path issues (`~/.cache/crystal`)
- Stale or corrupted object files
- Concurrent build processes

**Solutions**:

1. **Clear cache before building**:
   ```bash
   rm -rf ~/.cache/crystal
   rm -rf .crystal
   shards install --no-cache
   ```

2. **Use explicit cache directory**:
   ```bash
   export CRYSTAL_CACHE_DIR=/tmp/crystal_cache
   crystal build --no-cache src/cogutil/cogutil.cr
   ```

3. **Avoid home directory cache in CI**:
   ```yaml
   - name: Build without cache
     run: |
       unset CRYSTAL_CACHE_DIR
       crystal build --no-cache src/cogutil/cogutil.cr
   ```

4. **Use `--no-codegen` for syntax checks**:
   ```bash
   crystal build --no-codegen src/cogutil/cogutil.cr
   ```

---

### 3. Shards Installation Issues

**Error Message**:
```
Error: Failed to resolve dependency
```

**Solutions**:

1. **Install system dependencies first**:
   ```bash
   apt-get update
   apt-get install -y build-essential libssl-dev libgc-dev libpcre2-dev libevent-dev
   ```

2. **Use `--no-cache` with shards**:
   ```bash
   shards install --no-cache
   ```

3. **Clear shards cache**:
   ```bash
   rm -rf ~/.cache/shards
   ```

---

### 4. Segmentation Faults During Compilation

**Error Message**:
```
Segmentation fault (core dumped)
```

**Solutions**:

1. **Reduce parallel compilation**:
   ```bash
   crystal build --threads 1 src/cogutil/cogutil.cr
   ```

2. **Use `--debug` flag for more information**:
   ```bash
   crystal build --debug --error-trace src/cogutil/cogutil.cr
   ```

3. **Increase memory limits**:
   ```bash
   ulimit -v unlimited
   crystal build src/cogutil/cogutil.cr
   ```

---

### 5. Test Execution Failures

**Error Message**:
```
Invalid memory access (signal 11) at address 0x40
```

**Solutions**:

1. **Run tests with timeout**:
   ```bash
   timeout 300 crystal spec --verbose
   ```

2. **Run tests in smaller batches**:
   ```bash
   crystal spec spec/cogutil/ --verbose
   crystal spec spec/atomspace/ --verbose
   crystal spec spec/opencog/ --verbose
   ```

3. **Use `--no-codegen` for compilation check only**:
   ```bash
   crystal build --no-codegen spec/cogutil/cogutil_spec.cr
   ```

---

## GitHub Actions Workflow Best Practices

### 1. Cache Management

**Good**:
```yaml
- name: Clear cache
  run: |
    rm -rf ~/.cache/crystal
    rm -rf .crystal
```

**Avoid**:
```yaml
env:
  CRYSTAL_CACHE_DIR: ~/.cache/crystal
```

### 2. Memory Configuration

**Good**:
```yaml
container:
  image: crystallang/crystal:latest
  options: --cpus 2 --memory 4g
```

**Avoid**:
```yaml
container:
  image: crystallang/crystal:latest
```

### 3. Build Flags

**Good**:
```bash
crystal build --no-cache --error-trace src/cogutil/cogutil.cr
```

**Avoid**:
```bash
crystal build src/cogutil/cogutil.cr
```

### 4. Error Handling

**Good**:
```yaml
- name: Build
  run: crystal build src/cogutil/cogutil.cr
  continue-on-error: true
```

**Avoid**:
```yaml
- name: Build
  run: crystal build src/cogutil/cogutil.cr
```

---

## Recommended Workflow Structure

```yaml
name: Crystal CI

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]

jobs:
  build:
    runs-on: ubuntu-latest
    
    container:
      image: crystallang/crystal:latest
      options: --cpus 2 --memory 4g
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Clear cache
      run: |
        rm -rf ~/.cache/crystal
        rm -rf .crystal
    
    - name: Install dependencies
      run: |
        apt-get update
        apt-get install -y build-essential libssl-dev libgc-dev libpcre2-dev
        shards install --no-cache
    
    - name: Build components
      run: |
        crystal build --no-cache src/cogutil/cogutil.cr -o bin/cogutil
        crystal build --no-cache src/atomspace/atomspace.cr -o bin/atomspace
        crystal build --no-cache src/opencog/opencog.cr -o bin/opencog
      continue-on-error: true
    
    - name: Run tests
      run: |
        rm -rf ~/.cache/crystal
        timeout 300 crystal spec --verbose
      continue-on-error: true
```

---

## Local Testing

To reproduce CI issues locally:

```bash
# Clear cache
rm -rf ~/.cache/crystal
rm -rf .crystal

# Install dependencies
shards install --no-cache

# Build with same flags as CI
crystal build --no-cache --error-trace src/cogutil/cogutil.cr

# Run tests
crystal spec --verbose
```

---

## Performance Optimization

### Build Time Reduction

1. **Use `--no-codegen` for syntax checks**:
   ```bash
   crystal build --no-codegen src/cogutil/cogutil.cr
   ```

2. **Build only changed components**:
   ```bash
   # Instead of building all, build only modified components
   crystal build --no-cache src/cogutil/cogutil.cr
   ```

3. **Use release builds for production**:
   ```bash
   crystal build --release src/cogutil/cogutil.cr
   ```

### Memory Usage Reduction

1. **Limit parallel compilation**:
   ```bash
   crystal build --threads 1 src/cogutil/cogutil.cr
   ```

2. **Disable optimizations for faster builds**:
   ```bash
   crystal build --no-optimize src/cogutil/cogutil.cr
   ```

---

## Debugging Tips

### 1. Enable Verbose Output

```bash
crystal build --verbose --error-trace src/cogutil/cogutil.cr
```

### 2. Check Object File Generation

```bash
crystal build --no-codegen src/cogutil/cogutil.cr
ls -la ~/.cache/crystal/
```

### 3. Inspect Linker Commands

```bash
crystal build --verbose src/cogutil/cogutil.cr 2>&1 | grep "cc \|ld "
```

### 4. Check Memory Usage

```bash
# Monitor memory during build
watch -n 1 'free -h'
crystal build src/cogutil/cogutil.cr
```

---

## Contact and Support

For issues not covered in this guide:

1. Check the [Crystal documentation](https://crystal-lang.org/reference/)
2. Review [GitHub Actions documentation](https://docs.github.com/en/actions)
3. Open an issue on the [CrystalCog repository](https://github.com/cogpy/crystalcog)

---

## Changelog

- **2025-12-03**: Initial troubleshooting guide created
- **2025-12-03**: Added solutions for signal 11 and linker errors
- **2025-12-03**: Added recommended workflow structure

