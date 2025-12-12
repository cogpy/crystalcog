# Repository Cleanup Plan - CrystalCog
## December 12, 2025

---

## Audit Summary

### Repository Statistics

| Category | Count | Status |
|----------|-------|--------|
| **Total Files** | 600+ | Needs cleanup |
| **Crystal Files** | 163 | ✅ Keep |
| **Markdown Files** | 176 | Review |
| **Shell Scripts** | 120 | Excessive |
| **Workflow Files** | 67 | Too many |
| **JavaScript Files** | 17 | Non-Crystal |
| **C Source Files** | 3 | Non-Crystal |

---

## Issues Identified

### 1. Non-Crystal Source Code

**C Source Files** (3 files):
```
src/agent-zero/cognitive-tensors.c
src/agent-zero/opencog-ggml-bridge.c  
src/agent-zero/test-cognitive.c
```

**Status**: ❌ Should be removed or rewritten in Crystal

**Reason**: Repository should contain only pure Crystal implementations

---

### 2. JavaScript Files

**REST API Documentation** (15 files):
```
rest-api-documentation/lib/*.js
rest-api-documentation/swagger-ui.js
rest-api-documentation/swagger-ui.min.js
```

**Status**: ⚠️ Consider removal or archival

**Reason**: Swagger UI files - may be useful for API docs but not Crystal code

**Script Files** (2 files):
```
.github/scripts/generate_build_workflow.js
.github/scripts/generate_cargo_toml.js
scripts/validate-roadmap.js
```

**Status**: ❌ Should be removed

**Reason**: Cargo/Rust related, not relevant to Crystal project

---

### 3. Rust/Cargo Files

**Files**:
```
.github/Cargo.toml
```

**Status**: ❌ Should be removed

**Reason**: Rust configuration in a Crystal project

---

### 4. Excessive Workflow Files

**Total**: 67 workflow files

**Duplicate/Versioned Workflows**:
```
ci-org.yml
ci-org-v2.yml
ci-org-v3.yml
ci-org-v7.yml
ci-org-v8.yml
ci-org-gen-4.yml
```

**Status**: ❌ Remove old versions

**Recommendation**: Keep only latest, active workflows

---

### 5. Excessive Shell Scripts

**Total**: 120 shell scripts

**Categories**:
- Docker archive scripts (50+)
- Installation scripts (10+)
- Build scripts (20+)
- Configuration scripts (40+)

**Status**: ⚠️ Review and consolidate

**Recommendation**: Keep only essential scripts, archive rest

---

### 6. Large Documentation Directories

**Agent Documentation** (50+ files):
```
.github/agents/*.md
```

**Status**: ⚠️ Consider consolidation

**Recommendation**: Consolidate into fewer, more organized docs

---

## Cleanup Strategy

### Phase 1: Remove Non-Crystal Code

#### Action Items:
1. **Remove C source files**
   - Archive or rewrite in Crystal
   - Remove from src/agent-zero/

2. **Remove Rust/Cargo files**
   - Delete .github/Cargo.toml
   - Remove Rust-related scripts

3. **Remove JavaScript build scripts**
   - Delete .github/scripts/*.js
   - Keep only Crystal-related scripts

#### Commands:
```bash
# Remove C files
rm -rf src/agent-zero/*.c
rm -rf src/agent-zero/test-cognitive

# Remove Cargo files
rm -f .github/Cargo.toml

# Remove JS build scripts
rm -f .github/scripts/generate_cargo_toml.js
rm -f .github/scripts/generate_build_workflow.js
```

---

### Phase 2: Clean Up Workflows

#### Action Items:
1. **Remove duplicate/versioned workflows**
   - Keep only latest versions
   - Remove ci-org-v*.yml files

2. **Archive unused workflows**
   - Move to .github/workflows/archive/
   - Keep only active workflows

3. **Consolidate similar workflows**
   - Merge redundant CI workflows
   - Simplify workflow structure

#### Target: Reduce from 67 to ~15 active workflows

**Keep**:
- crystal.yml (Crystal CI)
- crystal-build.yml (Build)
- crystal-comprehensive-ci.yml (Comprehensive CI)
- ci-e2e.yml (E2E tests)
- release.yml (Releases)
- nightly-e2e.yml (Nightly tests)
- crci.yml (Matrix CI)

**Remove/Archive**:
- ci-org*.yml (all versions)
- Old CI workflows
- Duplicate workflows
- Unused workflows

---

### Phase 3: Consolidate Shell Scripts

#### Action Items:
1. **Archive docker scripts**
   - Already in docker/archive/
   - Can be removed entirely

2. **Keep essential scripts**
   - build_all_components.sh
   - Installation scripts
   - Setup scripts

3. **Remove redundant scripts**
   - Old build scripts
   - Duplicate scripts

#### Target: Reduce from 120 to ~20 essential scripts

---

### Phase 4: Optimize Directory Structure

#### Current Structure Issues:
- Too many top-level directories
- Mixed concerns
- Unclear organization

#### Proposed Structure:
```
crystalcog/
├── src/                    # Crystal source code
│   ├── atomspace/         # Core components
│   ├── cogutil/
│   ├── opencog/
│   ├── pln/
│   ├── ure/
│   ├── cogserver/
│   ├── attention/
│   ├── pattern_matching/
│   ├── pattern_mining/
│   ├── nlp/
│   ├── moses/
│   ├── learning/
│   └── ml/
│
├── spec/                   # Tests
│   └── (mirrors src/)
│
├── examples/               # Example code
│   ├── basic/
│   ├── advanced/
│   └── tests/
│
├── benchmarks/             # Performance benchmarks
│
├── docs/                   # Documentation
│   ├── api/
│   ├── guides/
│   └── architecture/
│
├── scripts/                # Essential scripts only
│   ├── build.sh
│   ├── install.sh
│   └── setup.sh
│
├── .github/
│   ├── workflows/         # Active workflows only
│   └── workflows/archive/ # Old workflows
│
├── bin/                    # Built binaries (gitignored)
│
└── (root files)
    ├── shard.yml
    ├── README.md
    ├── LICENSE
    └── CHANGELOG.md
```

---

### Phase 5: Documentation Cleanup

#### Action Items:
1. **Consolidate agent docs**
   - Merge .github/agents/*.md into docs/agents/
   - Create index document

2. **Organize documentation**
   - API docs
   - User guides
   - Developer guides
   - Architecture docs

3. **Remove duplicate docs**
   - Multiple README files
   - Duplicate guides

---

## Detailed Removal Plan

### Files to Remove

#### Non-Crystal Source Code:
```
src/agent-zero/cognitive-tensors.c
src/agent-zero/opencog-ggml-bridge.c
src/agent-zero/test-cognitive.c
src/agent-zero/test-cognitive (binary)
```

#### Rust/Cargo Files:
```
.github/Cargo.toml
.github/scripts/generate_cargo_toml.js
.github/scripts/generate_build_workflow.js
```

#### Duplicate Workflows:
```
.github/workflows/ci-org.yml
.github/workflows/ci-org-v2.yml
.github/workflows/ci-org-v3.yml
.github/workflows/ci-org-v7.yml
.github/workflows/ci-org-v8.yml
.github/workflows/ci-org-gen-4.yml
```

#### Old/Unused Workflows (to archive):
```
.github/workflows/asmoses.yml
.github/workflows/atomspace.yml
.github/workflows/attention.yml
.github/workflows/build.yml
.github/workflows/ci-atomspace.yml
.github/workflows/ci-improved.yml
.github/workflows/ci.yml
.github/workflows/cici.yml
.github/workflows/clean.yml
.github/workflows/cmake-multi-platform.yml
.github/workflows/cogci.yml
.github/workflows/cogserver.yml
.github/workflows/cogutil.yml
.github/workflows/consolidate-atomspace.yml
.github/workflows/docker-image.yml
.github/workflows/docker-publish.yml
.github/workflows/efficient-build.yml
.github/workflows/fetch.yml
.github/workflows/generate-build-workflow.yml
.github/workflows/generate-cargo-commit.yml
.github/workflows/generate-cargo-toml.yml
.github/workflows/generate-next-steps.yml
.github/workflows/generator-generic-ossf-slsa3-publish.yml
.github/workflows/gitpod (1).yml
.github/workflows/guix.yml
.github/workflows/integrate-modules.yml
.github/workflows/main.yml
.github/workflows/miner.yml
.github/workflows/monorepo-build.yml
.github/workflows/msvc.yml
```

#### Docker Archive (entire directory):
```
docker/archive/
```

#### REST API Documentation (consider removal):
```
rest-api-documentation/
```

---

## Directories to Archive

### Create Archive Structure:
```
archive/
├── c-implementations/     # C source files
├── workflows/             # Old workflow files
├── docker/                # Docker archive
├── scripts/               # Old scripts
└── docs/                  # Old documentation
```

---

## Expected Results

### Before Cleanup:
- **Total Files**: 600+
- **Crystal Files**: 163 (27%)
- **Non-Crystal**: 440+ (73%)
- **Workflows**: 67
- **Scripts**: 120

### After Cleanup:
- **Total Files**: ~300
- **Crystal Files**: 163 (54%)
- **Essential Support**: 137 (46%)
- **Workflows**: ~15
- **Scripts**: ~20

### Benefits:
- ✅ Pure Crystal implementation
- ✅ Clear directory structure
- ✅ Reduced complexity
- ✅ Easier maintenance
- ✅ Faster CI/CD
- ✅ Better developer experience

---

## Implementation Steps

### Step 1: Create Archive Directory
```bash
mkdir -p archive/{c-implementations,workflows,docker,scripts,docs}
```

### Step 2: Move Non-Crystal Code
```bash
# Move C files
mv src/agent-zero/*.c archive/c-implementations/
mv src/agent-zero/test-cognitive archive/c-implementations/

# Move Rust files
mv .github/Cargo.toml archive/c-implementations/
```

### Step 3: Archive Old Workflows
```bash
# Create workflow archive
mkdir -p .github/workflows/archive

# Move old workflows
mv .github/workflows/ci-org*.yml .github/workflows/archive/
mv .github/workflows/{asmoses,atomspace,attention,build}.yml .github/workflows/archive/
# ... (continue for all old workflows)
```

### Step 4: Clean Up Scripts
```bash
# Move docker archive
mv docker/archive archive/docker/

# Review and move unnecessary scripts
# (manual review needed)
```

### Step 5: Consolidate Documentation
```bash
# Create docs structure
mkdir -p docs/{api,guides,architecture,agents}

# Move agent docs
mv .github/agents/*.md docs/agents/
```

### Step 6: Update .gitignore
```
# Add to .gitignore
archive/
bin/
*.o
*.so
*.dylib
test-cognitive
```

### Step 7: Commit Changes
```bash
git add -A
git commit -m "refactor: Clean up repository for pure Crystal implementation"
git push origin main
```

---

## Validation Checklist

- [ ] All Crystal files remain intact
- [ ] No non-Crystal source code in src/
- [ ] Workflows reduced to essential set
- [ ] Scripts consolidated
- [ ] Documentation organized
- [ ] Archive directory created
- [ ] .gitignore updated
- [ ] All tests still pass
- [ ] CI/CD still works
- [ ] README updated

---

## Rollback Plan

If issues arise:
1. Restore from archive/ directory
2. Git revert cleanup commits
3. Review what broke
4. Adjust cleanup strategy

---

## Next Steps

1. Review and approve cleanup plan
2. Create archive directory
3. Execute cleanup in phases
4. Test after each phase
5. Update documentation
6. Push changes

---

**Status**: ✅ Plan ready for execution  
**Estimated Time**: 2-3 hours  
**Risk Level**: Low (everything archived)  
**Reversibility**: High (can restore from archive)
