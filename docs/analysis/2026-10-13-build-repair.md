# CrystalCog state analysis and repair report

**Repository:** https://github.com/o9nn/crystalcog
**Analysis date:** 13 October 2026
**Baseline:** `8af77fb6a3ad65415470988944edd150bb566056` (`main`, last repository push 2 January 2026)
**Repair branch:** `fix/build-reliability-core-optimizations`

## Executive result

The repository contained real compilation defects, missing executable entry points, graph/API correctness problems, and test infrastructure that could report success despite failures. This repair restores the affected source paths, implements a working CogShell, adds indexed incoming-link lookup and re-entrant FIFO observer dispatch, and makes CI fail honestly.

**The final broad non-distributed suite passes: 312 examples, 0 failures, 0 errors.** Twenty of 21 declared targets compile, and compiled CLI/shell/live HTTP smoke checks pass. **The complete repository is not build-green:** the distributed demo and complete `crystal spec` invocation reproduce an LLVM instruction-selection segmentation fault. It persists on both tested compiler releases and is recorded rather than bypassed or relabeled as success.

## 1. Current-state assessment

- 81 Crystal source files under `src/`, 64 spec files, and 21 declared Shards targets.
- Core subsystems include AtomSpace, PLN, URE, attention, pattern matching/mining, NLP, agent networking, robotics, temporal/spatial reasoning, behavior trees, and a simulated AI bridge.
- Recent visible GitHub runs were predominantly CodeQL, not fresh evidence that the full Crystal build and tests were healthy.
- The prior E2E workflow was large but suppressed important failures. The local test runner also accepted failure when more spec files passed than failed.
- Several component executable targets still compile library modules without application behavior. Their successful compilation should not be confused with feature completeness.

## 2. Completed repairs and implementations

### Build and runtime compatibility

- Fixed invalid ROS generic topic factory syntax by inferring the generic message type from `T.class`.
- Replaced unsupported `Set#reject!` usage and accepted arrays of behavior-node subclasses in Sequence/Selector constructors without Crystal array-invariance failures.
- Repaired the explanation trace's conflict with Crystal's zero-argument GC `finalize` hook, and safely handled missing last-trace IDs.
- Accepted ROS `Float32` range samples while preserving `Float64` internal sensor representation.
- Corrected distributed cache-statistics casts to the actual `Int32` size values.
- Implemented inclusive temporal duration comparisons used by consistency checks and added boundary regression coverage.

### Executable entry points and CogShell

- Separated the reusable CrystalCog library from executable wrappers in `src/bin/`.
- Corrected Shards, documentation, CI, release, and validation build paths.
- Implemented the missing CogShell with injectable I/O, concept creation, statistics, bounded reasoning, help, and graceful quit/EOF behavior.
- Restored standalone CogServer dispatch and validated malformed, missing, colliding, and out-of-range port arguments before startup.
- Fixed source/test ignore rules so executable wrappers and regression tests are not silently excluded from Git.

### AtomSpace correctness and optimization

- Added a handle-keyed reverse adjacency index; incoming lookup scales with the queried atom's incoming degree instead of scanning all links.
- Maintained eager and lazy-link adjacency during insert, removal, and clear operations, including nested-link deletion protection.
- Defensively owned constructor arrays and returned detached outgoing views so caller mutation cannot corrupt link topology or index cleanup.
- Moved notifications outside the mutation mutex and introduced FIFO post-commit dispatch, preventing observer deadlocks and nested remove-before-add event delivery.
- Kept internal eager-Link access efficient by avoiding detached-view allocation in arity, indexing, clone, and serialization operations.

### HTTP graph API

- Listed actual stored atoms instead of querying the unpopulated abstract `ATOM` type.
- Returned stable handles and names on atom creation and handles in listings.
- Resolved all submitted outgoing handles before adding a relationship; preserved outgoing order and rejected invalid or missing targets without partial insertion. The previous path silently constructed empty links.
- Added node/link HTTP round-trip and reverse-index regressions.

### NLP and AI response correctness

- Anchored complete-token classification regexes, preventing `hello123` and `12abc` substring misclassification.
- Corrected doubled consonants in comparative stemming (`bigger` → `big`) while retaining established simple-stem behavior.
- Preserved long text-statistics names and added the concise aliases consumed by linguistic analysis.
- Corrected an objectively erroneous fixture: `the cat and the dog and the bird` contains eight words, not seven.
- Replaced `tap` mutation of value-type `InferenceResponse` structs with explicit variable assignment/return. Error messages and successful inference metadata now survive construction.

### Honest validation infrastructure

- Replaced the previous E2E workflow with frozen dependency installation, all-target builds, full tests, pipe-failure propagation, compiled smoke checks, and optional index benchmarking.
- Preserved the established Crystal 1.14 CI pin: testing Crystal 1.22 did not fix the LLVM crash, so a toolchain upgrade alone was not published as a repair.
- Changed the local test runner to fail on **any** failing spec, removed misleading skip messages, and added a deterministic shell regression proving failure and success exit behavior.
- Fixed invalid release-job dependency expressions, retired runner/action references, monitoring YAML indentation, a missing `bc` dependency, and division by zero when no recent runs exist.
- Relocated the placeholder reusable workflow to a `.yml.example` template; it is not an executable workflow.
- All remaining workflow YAML passes `actionlint`. Some untouched repository Crystal files retain pre-existing formatter differences; whole-tree reformatting was deliberately avoided.

## 3. Validation evidence

Tests were run on the final repaired files unless stated otherwise. Counts overlap; they must not be summed into a unique total.

| Gate | Result | Evidence file in analysis workspace |
|---|---|---|
| Locked shard install/check | Pass | `all-targets-build-1.22.log` and original install output |
| Broad non-distributed suite (`spec/spec_helper.cr`, Crystal 1.22) | **312 examples, 0 failures/errors** | `broad-final.log` |
| Full AtomSpace directory | **123 examples, 0 failures/errors** | `atomspace-all-final.log` |
| Atom/core/shell/HTTP regression selection | **65 examples, 0 failures/errors** | `regressions-final.log` |
| Tokenizer and text processor | **46 examples, 0 failures/errors** | `nlp-final-passing.log` |
| AI bridge and metadata response tests | **39 examples, 0 failures/errors** | `ai-final-passing.log` |
| Large-operation canonicalization fixture | **1 example, 0 failures/errors** | `large-consistency-final.log` |
| Signed memory-load fixture | **1 example, 0 failures/errors** | `memory-fixture-final.log` |
| Distributed cluster focused tests, Crystal 1.14 | **30 examples, 0 failures/errors** | `suite-agent-2/distributed-cluster-after-cache-stats.log` |
| Sensory-motor focused tests, Crystal 1.14 | **35 examples, 0 failures/errors** | worker terminal result |
| Declared binaries | **20 of 21 compile** | `all-targets-build-1.22.log`, `remaining-targets-build.log`, `ai-final-passing.log` |
| Compiled main CLI, CogShell, live CogServer HTTP | Pass | `smoke-final.log` |
| NLP structural validation | Pass | `nlp-structure.log` |
| Test-runner failure propagation | Pass | deterministic `scripts/validation/test_test_runner_exit.sh` |
| Workflow lint, shell syntax, diff/secret/large-file scan | Pass | `actionlint-all.log`, `staged-guard.json` and final terminal checks |
| Full repository spec execution | **Blocked by compiler SIGSEGV** | `suite-agent-2/full-suite-direct-1.22-02.log` |
| Full-suite release/no-debug probe | **Stopped at 10-minute bound, exit 143** | `suite-agent-2/full-suite-direct-1.22-release-no-debug-01.log` |
| Separate full semantic/no-codegen probe | **Timed out at 90-second diagnostic bound** | `full-suite-typecheck.log` |

### Reproduction commands

```bash
shards install --frozen
shards check
shards build --error-trace
crystal spec --error-trace --no-color
crystal spec spec/spec_helper.cr --error-trace --no-color
crystal spec spec/atomspace/ --error-trace --no-color
bash scripts/ci-smoke.sh
bash scripts/validation/test_test_runner_exit.sh
crystal run --release benchmarks/incoming_index_benchmark.cr
```

Native packages used include SQLite, PostgreSQL, RocksDB, libevent, SSL, YAML, and PCRE development libraries. Validation used Crystal 1.14.0 and 1.22.0 with locked shards; final broad/focused successes reported above use 1.22 except where noted.

## 4. Measured optimization

The deterministic benchmark creates 10,000 inheritance links, queries a target with incoming degree 10, and verifies exact indexed/scan result equality before timing 1,000 queries.

| Method | Elapsed |
|---|---:|
| Reverse adjacency index | 0.380 ms |
| Linear adjacency scan | 40.258 ms |
| Observed speedup | **106.0×** |

The scan uses precomputed adjacency arrays to avoid inflating its cost with defensive-copy getters. This is a workload-specific microbenchmark, not a claimed 106× whole-application improvement. The index adds memory proportional to link adjacency and insertion/removal bookkeeping.

## 5. Unresolved highest-priority work

### P0 — Isolate and fix LLVM distributed-network code generation

`src/agent-zero/distributed_network_demo.cr` and the complete repository suite trigger `SIGSEGV` during code generation. Symbolizing Crystal 1.22 crash addresses identifies `llvm::SelectionDAG::ReplaceAllUsesWith`, `DAGCombiner::visit/combine`, and instruction-selection passes.

Reproduced with Crystal 1.14 and 1.22, one/two-worker modes, generic CPU selection, a single LLVM module, and `-O1`. The release demo did not produce a binary and ended with exit 137 at approximately ten minutes; no diagnosis of OOM is asserted. The whole release suite was explicitly terminated at its ten-minute bound. A version switch is therefore not an evidenced fix.

Next: reduce the distributed-network source to a minimal compiler reproduction, capture the failing LLVM module, test a narrowly isolated source transformation or supported LLVM build, and require the complete suite plus all 21 targets to pass. Strict CI retains this failure instead of excluding the target.

### P1 — Bound PLN intermediate allocation and benchmark work

The isolated memory-load fixture passed but showed nearly one million temporary Atom handles generated from a roughly 3,000-atom workload, while only a small number of new canonical results were reported. Investigate duplicate inference construction, early canonical lookup, and iteration/frontier limits. A prior loaded broad run also exceeded the URE backward-chain wall-time budget (3.465 seconds versus 3 seconds); the final 312-case run passed, so this is a load-sensitive performance risk, not a currently reproducible deterministic failure.

### P1 — Implement faithful recursive file-storage round trips

`FileStorageNode#scheme_to_atom` still has a simplified parser that returns empty outgoing arrays for links. It needs a recursive S-expression parser, escaped-name handling, truth-value restoration, malformed-input validation, and round-trip graph integrity tests. This larger persistence feature was not bundled into the reverse-index/API repair.

### P2 — Replace simulated AI/distributed reasoning with actual integrations

The AI bridge still simulates model loading/inference and emits demo responses; distributed agent reasoning also explicitly uses simplified behavior. Define backend capabilities and failure contracts before wiring real C++ or external inference. No model/API credentials were added to source or consumed for these repairs.

## 6. Repository synchronization and scope

The user-requested `gitpat` credential was retried and still returns **HTTP 401**. The user explicitly authorized `GH_PAT_BEAST` or `DEVORG` as fallbacks; `GH_PAT_BEAST` passed repository-write and workflow-scope preflight and is the publication credential for this branch.

Changes are delivered as a reviewable pull request, not an automatic merge to `main`. The patch includes source/test changes, CI/build paths, this report, and regression/benchmark sources. It excludes native binaries, installed shards, compiler caches, raw database fixtures, diagnostic logs, and credentials. Remote CI must not be described as green without its actual completed result.
