# Variant Sync

This tree unifies the five `crystalcog` variants. Each variant contributed
what it did best; where two variants implemented the same thing, the choice
and the reason are recorded here.

| Source | Contribution |
| --- | --- |
| o9nn | Build-reliability fixes (Crystal 1.14 pin, `Bytes`-backed memory pool), validated atomic `FileStorageNode` persistence, `src/bin/` executables, `scripts/ci-smoke.sh`, scheme storage parser |
| cogpy | Phase 6-7 modules: genetic programming, simulation, multi-agent communication/coordination, neural-symbolic, self-modification, advanced learning/NLP, robotics navigation/goal planning/ROS bridge, attention forgetting/normalization/query optimizer, production hardening, ~60 specs, e2e harness, priority-issue generator |
| 9cog | Integration framework in `src/integrations/` (CogPy, PyG, Pygmalion, Galatea, Paphos, Neo4j, IPFS, MeTTa, TypeScript SDK) and the `crystalcog integration` command |
| EchoCog | Organized layout for docs, demos and standalone tests: `docs/{api,features,guides,reports,agent-zero,guix}`, `examples/crystal/`, `spec/standalone/`, `scripts/{demos,testing}/`, `tools/`; the roadmap-to-issues generator (`generate-next-steps.yml`, `.github/scripts/roadmap-parser.js`) |
| rzonedevops | Agent persona definitions in `.github/agents/`; `examples/crystal/opencog_complete_demo.cr` (end-to-end demo) and `docs/OPENCOG_CRYSTAL_IMPLEMENTATION.md` |

## Overlap resolutions

- **Temporal**: o9nn's `Temporal` (Allen interval algebra, event processing,
  temporal networks) stays; cogpy's event calculus, sequence learner and
  temporal planner live in `TemporalReasoning` (`src/temporal/temporal_reasoning.cr`).
- **Explanation**: o9nn's `Explanation` (causal models, feature importance,
  traced inference) stays; cogpy's explanation traces and confidence
  calibration live in `ReasoningExplanation` (`src/explanation/explanation.cr`).
- **Sensory-motor**: o9nn's `Robotics` sensors/actuators/body schema stay in
  `sensory_motor.cr`; cogpy's reactive `Robotics::SensoryMotor` loop is in
  `sensory_motor_control.cr`.
- **CogShell**: `CrystalCog::Shell` (o9nn) is the entry point and delegates
  any command it does not define to cogpy's `CogShell::Shell`
  (`concept`, `inherit`, `eval`, `imply`, `ure`, `nlp`, `parse`, `tv`, ...).
- **Atom clone/equality/to_s**: o9nn's versions. Atoms are acyclic, and
  cogpy's process-wide visited sets would print a sub-link shared within one
  link (e.g. `(And L L)`) as `...`.
- **PLN abduction**: o9nn's formula plus cogpy's guard against `0/0`.
- **CI**: o9nn's pinned, lean `ci-e2e.yml`; cogpy's array-built issue body in
  `test-monitoring.yml`.
- **Issue generators**: cogpy's `generate-priority-issues.yml` keeps the weekly
  schedule; EchoCog's `generate-next-steps.yml` runs on demand only (two
  scheduled generators would open overlapping issues) and reads the roadmap
  from `docs/agent-zero/` or any file passed as `roadmap_file`.
- **Roadmap**: `docs/DEVELOPMENT-ROADMAP.md` (o9nn, current) is the one roadmap;
  EchoCog's older copy under `docs/roadmap/` is dropped.
- **CognitiveKernelManager**: commented out in every variant; restored so the
  hypergraph persistence demo and standalone test build and run.
- **Memory benchmarks**: `MemoryProfiler` reports per-atom cost from live GC
  heap growth after a collection rather than process RSS, which moved with
  page granularity and other fibers and made the comparison specs flaky.
- **PLN rule set**: o9nn's stock engine (deduction, inversion, modus ponens,
  abduction) stays the default because its inference context only constructs
  atoms it keeps. cogpy's revision, conditional, evaluation and higher-order
  rules are opt-in via `PLN.create_advanced_engine` or
  `PLNEngine#add_advanced_rules`; they rescan per premise and update existing
  truth values.

## Not carried over

- `gitpod (1).yml`, `oc (1).yml`, `oc (2).yml` (EchoCog, rzonedevops):
  duplicated uploads of a Gitpod config and a C++ OpenCog CI, not workflows
  for this repository.
- rzonedevops' root-level demos, tests and reports: the same files live in
  EchoCog's organized directories.
- C/C++/Rust scaffolding still present in EchoCog and rzonedevops
  (`CMakeLists.txt`, `Cargo.toml` files, `src/agent-zero/*.c`, C++ OpenCog
  and Rust CI workflows, `docker/archive/`, `rest-api-documentation/`): cogpy
  removed these in its "Clean up repository for pure Crystal implementation"
  change, and this tree follows that cleanup.

## Inventory

Every file on each variant's `main`, classified against this tree:

| Variant | Files | Same content | Updated in place | Moved | Not carried over |
| --- | --- | --- | --- | --- | --- |
| o9nn | 640 | 521 | 116 | 0 | 3 |
| cogpy | 895 | 859 | 34 | 1 | 1 |
| 9cog | 645 | 497 | 144 | 1 | 3 |
| EchoCog | 693 | 402 | 133 | 43 | 115 |
| rzonedevops | 715 | 371 | 113 | 113 | 116 |

"Updated in place" means a newer version from another variant replaced it;
"moved" means the same file lives at a new path (EchoCog's organized layout).
What is not carried over:

- o9nn, 9cog: `multi-platform-build.yml` (C++ pipeline, see above) and two
  `*.spec.cr.skip` stubs whose specs now run as `attention_spec.cr` and
  `error_handling_spec.cr`.
- cogpy: `multi-platform-build.yml`.
- EchoCog, rzonedevops: C/C++/Rust scaffolding (`CMakeLists.txt`,
  `Cargo.toml`, `src/agent-zero/*.c`, `requirements.txt`, `.idx/dev.nix`),
  C++ OpenCog and Rust CI workflows, Cargo/workflow generator scripts,
  `docker/archive/`, `rest-api-documentation/` (Swagger UI around an empty
  spec for a Python service on `localhost:5000`), a generated
  `coverage-report.txt`, and rzonedevops' Python/Rust `README` setup note.
