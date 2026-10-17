# Variant Sync

This tree unifies the five `crystalcog` variants. Each variant contributed
what it did best; where two variants implemented the same thing, the choice
and the reason are recorded here.

| Source | Contribution |
| --- | --- |
| o9nn | Build-reliability fixes (Crystal 1.14 pin, `Bytes`-backed memory pool), validated atomic `FileStorageNode` persistence, `src/bin/` executables, `scripts/ci-smoke.sh`, scheme storage parser |
| cogpy | Phase 6-7 modules: genetic programming, simulation, multi-agent communication/coordination, neural-symbolic, self-modification, advanced learning/NLP, robotics navigation/goal planning/ROS bridge, attention forgetting/normalization/query optimizer, production hardening, ~60 specs, e2e harness, priority-issue generator |
| 9cog | Integration framework in `src/integrations/` (CogPy, PyG, Pygmalion, Galatea, Paphos, Neo4j, IPFS, MeTTa, TypeScript SDK) and the `crystalcog integration` command |
| EchoCog | Organized layout for docs, demos and standalone tests: `docs/{api,features,guides,reports,roadmap,agent-zero,guix}`, `examples/crystal/`, `spec/standalone/`, `scripts/{demos,testing}/`, `tools/` |
| rzonedevops | Agent persona definitions in `.github/agents/` |

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
- **PLN rule set**: o9nn's stock engine (deduction, inversion, modus ponens,
  abduction) stays the default because its inference context only constructs
  atoms it keeps. cogpy's revision, conditional, evaluation and higher-order
  rules are opt-in via `PLN.create_advanced_engine` or
  `PLNEngine#add_advanced_rules`; they rescan per premise and update existing
  truth values.

## Not carried over

- EchoCog's `generate-next-steps.yml` and `.github/scripts/roadmap-parser.js`:
  superseded by cogpy's `generate-priority-issues.yml`, and pointed at a root
  `AGENT-ZERO-GENESIS.md` that no longer exists.
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
