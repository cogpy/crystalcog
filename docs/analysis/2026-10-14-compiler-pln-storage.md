# CrystalCog: compiler trigger, PLN allocation reduction, and recursive persistence

**Repository:** [o9nn/crystalcog](https://github.com/o9nn/crystalcog)
**Date:** 14 October 2026
**Baseline:** `7704560` on `fix/build-reliability-core-optimizations`
**Delivery:** [repair PR #4](https://github.com/o9nn/crystalcog/pull/4), targeting `main`.

## Executive result

All three requested workstreams were implemented. The distributed-demo compiler failure is avoided by replacing an oversized inline memory-pool aggregate with owned heap-backed bytes. **All 21 declared executable targets now build on Crystal 1.14.0 with frozen dependencies and normal compiler flags.** The distributed target also compiled on Crystal 1.22.0.

The final targeted AtomSpace, persistence, PLN, and allocator suite passed **175 examples, 0 failures, 0 errors, 0 pending**. On a fixed 12-node/two-iteration PLN workload, inference results remained unchanged while GC-accounted allocated bytes fell **30.9%**, and discarded temporary Atom constructions were eliminated.

**The repository is not yet fully green:** the direct full suite now passes compilation but stalls during distributed peer bootstrap. It was stopped at a three-minute limit. The standalone demo likewise starts real cognitive kernels but stalls during peer setup. These are separate runtime problems, not the original LLVM build failure.

## 1. Isolated LLVM compiler trigger

### Root cause and reproduction

`src/cogutil/performance_optimization.cr` originally declared:

```crystal
@blocks : StaticArray(UInt8, 1_280_000)
# In initialize:
@blocks = StaticArray(UInt8, 1_280_000).new(0_u8)
```

`AtomMemoryPool` is instantiated by `CognitiveKernel`, which is reachable from the distributed demo. Crystal lowers the large value-type initialization into enormous aggregate returns, loads, and stores. The isolated LLVM unit contains operations such as:

```llvm
%LargeInlinePool = type { i32, [1280000 x i8] }
%1 = call [1280000 x i8] @"*StaticArray(... )::new..."(...)
store [1280000 x i8] %1, ptr %0
```

A standalone 15-line class with no shards, networking, AtomSpace, or agent dependencies emitted the same **signal 11 / “BUG: a codegen process failed”** failure under Crystal 1.14.0 / LLVM 18.1.6. The compiler driver also failed to terminate cleanly and was subsequently cleaned up. Its emitted bitcode disassembled successfully and passed LLVM 18's verifier: this was not a malformed-IR verification failure.

A direct `llc-18` probe of the reduced unit exceeded its 90-second diagnostic limit; it did **not** provide an additional independently completed segmentation-fault result. The evidence establishes the oversized by-value aggregate as the repository-level trigger; it does not claim an upstream LLVM patch or a fully minimized LLVM-internal defect.

The matching `Bytes` control retained the same 1,280,000-byte capacity, compiled in 2.453 seconds, and printed `0`.

Reproducer and control are committed under `docs/analysis/compiler/`:

```bash
# Expected to reproduce a compiler failure; force cleanup if the driver stalls.
timeout --kill-after=5s 90s crystal build \
  docs/analysis/compiler/static_array_repro.cr -o /tmp/pool-repro

# Same-capacity, heap-backed control.
crystal build docs/analysis/compiler/static_array_fixed.cr -o /tmp/pool-fixed
/tmp/pool-fixed
```

### Implemented repair

The pool now owns a fixed-size `Bytes` buffer. This retains contiguous, zero-initialized storage and its GC-managed lifetime without giant inline stack/SSA aggregates. No CPU-specific flags, release-only workaround, single-module workaround, or compiler upgrade is needed for the repair.

Allocator regressions exercise all 10,000 blocks, address uniqueness and spacing, GC lifetime, zeroed reuse, duplicate frees, and rejection of interior/external pointers. Exercising deallocation also uncovered and repaired an existing `Int64`-to-`Int32` block-index compilation error.

## 2. PLN intermediate-allocation investigation and optimization

### Sources of avoidable allocation

1. Built-in rules repeatedly copied `Link#outgoing` arrays and requested complete AtomSpace/type snapshots.
2. Deduction and abduction repeatedly scanned unrelated inheritance links.
3. Duplicate link proposals constructed a fresh `Link`, outgoing copy, and Atom handle before canonicalization rejected or merged the candidate.

### Implemented changes

- Built-in rules use immutable `Link#arity`/`[]` access rather than detached outgoing copies.
- A PLN-local inference context indexes inheritance candidates by subject and object. It refreshes after accepted inheritance insertions, preserving candidate order and visibility of links inferred earlier in the same iteration.
- Custom/caller-added rules retain the historical direct `apply` route.
- Detached/noncanonical endpoints retain structural-equality candidate matching. Contextual Modus Ponens falls back to the live public API for these graphs, preserving facts created earlier in the same iteration.
- `AtomSpace#add_link` now reuses an existing canonical relationship before constructing a candidate Atom. Lookup and truth-value merge occur under the mutation lock; observer dispatch occurs after unlocking. A lookup miss still uses the normal race-safe `add_atom` path.

Duplicate proposals are **not silently skipped**: their legitimate truth-value merges and observer events remain intact.

### Measured results

The committed benchmark, `benchmarks/pln_allocation_benchmark.cr`, uses a fixed 12-node chain and two reasoning iterations. It separates canonical graph growth from total Atom construction and measures Boehm GC cumulative allocation deltas after graph construction and collection.

| Metric | Baseline | Final |
|---|---:|---:|
| Results / canonical Atom growth | 51 / 51 | 51 / 51 |
| Atom constructions during reasoning | 127 | 51 |
| Discarded/merged candidate constructions | 76 | 0 |
| GC-accounted allocated bytes | 497,504 | 343,840 |
| Allocated bytes saved | — | 153,664 / **30.9%** |
| Atom construction reduction | — | **59.8%** |

The final allocation and construction counts were identical across three repetitions. Final elapsed times were 1.033, 0.997, and 0.861 ms; the baseline was one 1.033 ms sample. These small timings are **not evidence for a general throughput improvement**. Allocation reductions are the stronger result.

The previously discussed near-million-atom/handle figure is not attributed to PLN alone. URE forward-chaining closure must be benchmarked separately before conclusions about it are drawn.

```bash
crystal build benchmarks/pln_allocation_benchmark.cr --release -o /tmp/pln-alloc
/tmp/pln-alloc
```

### Options evaluated

| Option | Decision |
|---|---|
| Remove outgoing copies and repeated full scans | Implemented |
| Reuse canonical link candidates while preserving merges/events | Implemented in AtomSpace |
| Skip duplicate proposals entirely | Rejected: can suppress evidence updates and observer events |
| Incrementally maintain context indexes instead of rebuilding after insertions | Deferred pending larger-graph profiling and ordering-equivalence tests |
| Bound dense URE closure / compact graph result sets | Separate follow-up; no unsupported PLN attribution |

## 3. Faithful recursive AtomSpace file round trips

### Implemented behavior

`FileStorageNode` now uses a real bounded recursive Scheme-style parser instead of splitting link expressions into empty links. The implementation preserves:

- ordered outgoing relationships, empty links, shared descendants, and incoming indexes;
- node names, Unicode, quotes, backslashes, and escaped control characters;
- `SimpleTruthValue`, `CountTruthValue`, `IndefiniteTruthValue`, and `FuzzyTruthValue`, including their extra fields;
- attention metadata: short-term importance, long-term importance, and very-long-term importance;
- specialized `ConceptNode`, `PredicateNode`, `VariableNode`, and `NumberNode` behavior;
- exact numeric labels: integer `"42"`, floating `"42.0"`, and `"42.250"` remain distinct while restoring numeric values;
- storage-local resolution of recursively loaded descendants, including lazy-link resolution.

Repeated nested copies are canonicalized once by topology, preventing repeated CountTruthValue evidence merges. Conflicting persisted metadata for the same topology is rejected before target mutation. Malformed input, unknown syntax, trailing garbage, and excessive nesting are likewise rejected before insertion.

Complete writes render and validate before an atomic file replacement. Single-atom revisions now use topology upsert rather than appending conflicting historical copies. Unreadable numeric nodes and nonfinite extra truth metadata are rejected without replacing the previous valid image. The parser and writer share a maximum nesting depth of 256.

### Compatibility and scope

- Legacy bare **simple** `(strength, confidence)` metadata is accepted. Untagged three-field legacy values are ambiguous between Count and Fuzzy and are not guessed.
- File handles are process-local and regenerated; topology, sharing, labels, and metadata are restored, not durable cross-process handle IDs.
- Loading into an existing AtomSpace uses its established merge policy. Exact snapshot fidelity is verified against a fresh target.
- Conflicting detached graph metadata is rejected rather than silently reconciled; coordinated graph metadata revisions can be saved as a complete AtomSpace snapshot.
- This work covers **FileStorage**. It does not claim equivalent repairs to SQLite, PostgreSQL, RocksDB, or network storage.
- The recursive format expands repeated structures. Compact reference-based persistence and concurrent-writer coordination remain separate design work.

## 4. Validation matrix

| Gate | Observed result |
|---|---|
| Frozen `shards build` on Crystal 1.14.0 | **21 targets built successfully** |
| Distributed demo build on Crystal 1.14.0 | Passed with normal flags |
| Distributed demo build on Crystal 1.22.0 | Passed; deprecation warnings remain |
| Final AtomSpace + PLN + allocator specs | **175 examples, 0 failures, 0 errors, 0 pending** |
| Canonical reuse / observer regressions | Passed within final targeted suite |
| Recursive storage fidelity / malformed-input regressions | Passed within final targeted suite |
| Three final PLN benchmark repetitions | Identical allocation and Atom-construction counts |
| Changed Crystal formatting and staged whitespace checks | Passed |
| Staged secret scan | Passed |
| Direct full suite, fail-fast | Reached runtime; stopped after 180 s in distributed peer bootstrap |
| Standalone distributed demo runtime | Kernels started; stopped after 60 s in peer setup |

Representative commands:

```bash
CRYSTAL_WORKERS=1 shards build --frozen --error-trace
CRYSTAL_WORKERS=1 crystal spec spec/atomspace spec/pln \
  spec/cogutil/atom_memory_pool_spec.cr --error-trace --no-color
```

## 5. Remaining highest-priority work

1. **Distributed peer bootstrap and lifecycle:** diagnose listener readiness, registration/handshake ordering, peer retry behavior, and shutdown. The observed full-suite/demo stalls repeatedly attempt to reach the third agent before its listener is ready. This is an observed symptom, not a completed root-cause proof.
2. **Separate URE scaling measurement:** identify actual closure growth versus temporary construction and result-array allocation, then implement explicit inference budgets or graph-aware caching with semantic-equivalence tests.
3. **Persistence scaling and other backends:** consider compact references and durable identifiers; apply equivalent fidelity tests independently to database/network implementations.

## Repository synchronization

Changes are delivered on the existing repair branch and [PR #4](https://github.com/o9nn/crystalcog/pull/4); `main` is not merged by this task. The configured `gitpat` still returns HTTP 401. Synchronization therefore uses the **previously user-authorized Beast credential fallback**, without exposing credentials or changing account permissions.
