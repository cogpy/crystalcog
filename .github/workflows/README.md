# GitHub Actions Workflows Documentation

This directory contains GitHub Actions workflows for building, testing, and deploying the OpenCog project components.

## Workflow Overview

### Main Workflows

1. **build.yml** - Simple build workflow for the main project
   - Builds, tests, and packages the project
   - Uses artifacts to share build outputs between jobs
   - Runs on push to main and pull requests

2. **ci.yml** - Full CI pipeline with all OpenCog components
   - Builds components in dependency order: cogutil → atomspace → (ure, asmoses, cogserver, attention) → opencog
   - Each component is built in isolation with proper dependency management
   - Includes packaging step for main branch builds

3. **ci-improved.yml** - Improved CI using reusable workflows
   - Cleaner implementation using the reusable build component
   - Better parallelization of independent components
   - Includes integration testing phase

4. **multi-platform-build.yml** - Cross-platform build matrix
   - Tests on Ubuntu 20.04 and 22.04
   - Builds in both Release and Debug modes
   - Includes sanitizer builds (AddressSanitizer, ThreadSanitizer, UBSan)
   - Code quality checks with clang-format and cppcheck

### Reusable Workflows

- **reusable/build-component.yml** - Reusable workflow for building OpenCog components
  - Standardizes the build process across all components
  - Handles dependency downloads and artifact uploads
  - Configurable for different repositories and build options

## Build Sequence

The OpenCog project has the following dependency hierarchy:

```
cogutil
   └── atomspace
          ├── ure
          │    ├── miner
          │    └── unify
          ├── asmoses
          ├── cogserver
          │    └── opencog
          └── attention
                └── opencog
```

## Workflow Features

### Artifact Management
- Build artifacts are shared between jobs using GitHub Actions artifacts
- Artifacts include libraries and headers needed by dependent components
- Artifacts are retained for 1 day by default (7 days for releases)

### Caching
- Multi-platform builds use caching for faster builds
- ccache is used to cache compilation results
- pip cache is preserved for Python dependencies

### Testing
- Each component runs its test suite independently
- Test failures don't block the pipeline (continue-on-error)
- Test results are uploaded as artifacts for debugging
- Integration tests run after all components are built

### Container Usage
- All workflows use the `opencog/opencog-deps` Docker image
- This ensures consistent build environment across all runners
- Different tags are used for different Ubuntu versions

## Running Workflows Locally

You can test these workflows locally using [act](https://github.com/nektos/act):

```bash
# Run the build workflow
act -W .github/workflows/build.yml

# Run a specific job
act -j build-and-test -W .github/workflows/build.yml

# Run with specific event
act pull_request -W .github/workflows/ci.yml
```

## Customization

### Adding a New Component

To add a new component to the build sequence:

1. Add a job in `ci-improved.yml`:
```yaml
  my-component:
    needs: atomspace  # or other dependencies
    uses: ./.github/workflows/reusable/build-component.yml
    with:
      component-name: my-component
      repository: opencog/my-component
      dependencies: cogutil-artifacts,atomspace-artifacts
```

2. Update dependent jobs to include the new component if needed

### Modifying Build Options

You can pass additional CMake arguments through the reusable workflow:

```yaml
  my-component:
    uses: ./.github/workflows/reusable/build-component.yml
    with:
      component-name: my-component
      repository: opencog/my-component
      cmake-args: "-DENABLE_FEATURE=ON -DBUILD_SHARED_LIBS=OFF"
```

## Troubleshooting

### Common Issues

1. **Build failures due to missing dependencies**
   - Check that all required artifacts are downloaded
   - Verify the dependency order is correct

2. **Test failures**
   - Tests are set to continue on error to prevent blocking
   - Check test artifacts for detailed logs

3. **Artifact upload failures**
   - Ensure paths exist before uploading
   - Use `if-no-files-found: ignore` for optional artifacts

### Debugging Tips

- Use `actions/upload-artifact` to save build logs
- Add `set -x` to shell scripts for verbose output
- Check container logs if builds fail mysteriously
- Use matrix builds to isolate platform-specific issues

## Best Practices

1. **Keep workflows DRY** - Use reusable workflows for common patterns
2. **Fail fast** - Use `fail-fast: false` in matrices only when needed
3. **Cache wisely** - Cache dependencies but not build outputs
4. **Test in parallel** - Run independent tests concurrently
5. **Document changes** - Update this README when modifying workflows

## Crystal-Specific Workflows

### Crystal Build and Test (`crystal-build.yml`)

**Purpose**: Automates the Crystal build process with comprehensive error capture and diagnostic reporting.

**Triggers**:
- Push to main branch (when Crystal source files change)
- Pull requests to main branch (when Crystal source files change)
- Manual workflow dispatch

**Features**:
- **Environment Setup**: Installs Crystal 1.20.1 and required dependencies
- **Dependency Management**: Runs `shards install` with error capture
- **Multi-target Build**: Compiles crystalcog, cogutil, atomspace, and opencog components
- **Test Execution**: Runs Crystal specs and basic functionality tests
- **Error Diagnostics**: Automatically creates GitHub issues for build failures with:
  - Detailed error analysis and common causes
  - Diagnostic explanations for typical Crystal errors
  - Suggested remediation steps
  - Build context and environment information

**Error Issue Labels**: `bug`, `crystal-build`, `dependencies`/`compilation-error`/`test-failure`, `automated`

### Development Roadmap Issues (`roadmap-issues.yml`)

**Purpose**: Automatically generates GitHub issues from actionable tasks in the DEVELOPMENT-ROADMAP.md file.

**Triggers**:
- Weekly schedule (Mondays at 10 AM UTC)
- Manual workflow dispatch
- Push to main when DEVELOPMENT-ROADMAP.md changes

**Features**:
- **Roadmap Verification**: Checks roadmap structure and freshness
- **Task Parsing**: Extracts incomplete tasks from "Next Steps" sections
- **Issue Generation**: Creates GitHub issues for uncompleted roadmap tasks
- **Smart Labeling**: Applies component-specific labels (cogutil, atomspace, PLN, etc.)
- **Priority Management**: Labels issues based on roadmap section priority
- **Duplicate Prevention**: Avoids creating duplicate issues
- **Progress Tracking**: Maintains a summary issue with generation statistics

**Issue Labels**: 
- `roadmap` - All roadmap-generated issues
- `crystal-conversion` - Part of Crystal conversion project
- `priority-{high,medium,low}` - Based on roadmap section
- Component labels: `cogutil`, `atomspace`, `opencog`, `pln`, `ure`, `testing`, `ci-cd`, `documentation`
- Section labels: `immediate-actions`, `phase-2-implementation`, etc.

**Manual Options**:
- `force_recreate`: Close existing roadmap issues and recreate all
- `roadmap_section`: Process only specific roadmap section

## Crystal Development Workflow

### When Build Fails

1. **Automatic Issue Creation**: The workflow automatically creates an issue with diagnostic information
2. **Review the Issue**: Check the generated issue for error analysis and suggested fixes
3. **Fix the Problem**: Address the underlying issue in the code
4. **Verify Fix**: Push changes to trigger another build
5. **Close Issue**: Close the automated issue once the build succeeds

### When Working on Roadmap Tasks

1. **Find Tasks**: Check issues labeled with `roadmap` for available tasks
2. **Assign Yourself**: Assign roadmap issues you plan to work on
3. **Complete Task**: Implement the roadmap task
4. **Update Roadmap**: Mark the task as complete in DEVELOPMENT-ROADMAP.md using `- [x]`
5. **Close Issue**: The issue can be closed when the roadmap is updated

## Configuration

### Crystal Build Workflow

The Crystal version is configured in the workflow file:
```yaml
env:
  CRYSTAL_VERSION: 1.20.1
```

### Roadmap Issues Workflow

The roadmap file path and schedule are configured:
```yaml
env:
  ROADMAP_FILE: 'DEVELOPMENT-ROADMAP.md'
  
# Weekly schedule (Mondays at 10 AM UTC)
schedule:
  - cron: '0 10 * * 1'
```