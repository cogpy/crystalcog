# CrystalCog post-merge release diagnosis

**Repository:** [o9nn/crystalcog](https://github.com/o9nn/crystalcog)
**Snapshot:** 14 October 2026, 03:16 UTC
**Merged baseline:** `fa5c8e9d9be8eeb4682eff4d0b9c377a99202e54`
**Follow-up branch:** `fix/release-packaging-portability`

## Verified current state

[PR #4](https://github.com/o9nn/crystalcog/pull/4) is **MERGED**, at 02:50:45 UTC. The merge includes both the compiler/PLN/persistence changes and a later four-line CogServer attribute adjustment. The local checkout was fast-forwarded to merged `main` before creating the scoped follow-up branch.

| Workflow / release | Observed result |
|---|---|
| [Release and Deploy #1](https://github.com/o9nn/crystalcog/actions/runs/38504059166) | **Completed successfully** |
| [Release All Binaries #1](https://github.com/o9nn/crystalcog/actions/runs/38504059141) | **Failed** on all four platform build jobs |
| [v1.0.0 release](https://github.com/o9nn/crystalcog/releases/tag/v1.0.0) | Published; two single-CLI tarballs, not the comprehensive binary set |
| Nightly E2E, Comprehensive CI/CD, Comprehensive E2E, Unit/Integration, E2E Pipeline | **Five manually dispatched runs still queued** |
| Test Monitoring and Reporting | Completed successfully; not proof that underlying builds/tests passed |
| Main Crystal Build and Test | Failed; test process ended with exit **143** |
| Main Crystal CI | Failed in its test stage; exit **1**, no successful full-suite summary |

The existing release assets are `crystalcog-linux-x86_64.tar.gz` (1,168,811 bytes) and `crystalcog-macos-x86_64.tar.gz` (1,427,840 bytes). The queued run job-list API returned no assigned jobs for sampled runs. This does not establish the queue's underlying cause; no user-triggered runs were canceled, restarted, or reconfigured.

## Causal release failures

| Platform | First causal error from logs | Implemented correction |
|---|---|---|
| Linux x86_64 | Linker cannot find `-lrocksdb` | Install RocksDB and PostgreSQL development packages; pin Ubuntu 24.04 |
| macOS x86_64 / ARM64 | `declare: -A: invalid option` | Remove Bash-4 associative arrays; use a Bash-3-compatible packager |
| Linux ARM64 | Crystal 1.14 Alpine image is `linux/amd64`, not the requested `linux/arm64` | Use a native `ubuntu-24.04-arm` runner and the official Crystal 1.22.0 ARM compiler |

The Linux script also used `((SUCCESS++))` / `((FAILED++))` under `bash -e`: incrementing from zero returns a failing shell status and prematurely ends the loop. The replacement avoids this defect and propagates actual build failures.

Official compiler release assets were checked through GitHub: Crystal 1.14.0 has no official Linux aarch64 tarball, while Crystal 1.22.0 has one. Other release platforms remain pinned to 1.14.0. The per-archive build manifest records the exact compiler and architecture.

## Scoped follow-up changes

The new `scripts/release/build-binaries.sh` treats **shard.yml's 21 targets** as the source of truth. It performs frozen optimized builds, clears stale target outputs, requires every declared executable, verifies architecture and invokes the CLI before packaging. No missing source or failed target is accepted as success. Archives contain `BUILD-MANIFEST.txt`.

Both release workflows now use frozen dependencies, explicit native-library setup, and correct platform labeling. Their artifact filenames no longer collide: the single-CLI workflow produces `crystalcog-main-*` archives, while the all-target workflow keeps its comprehensive archive names. New runs default to dynamic builds; an explicit Linux static option remains available and fails honestly if its native-library requirements cannot be satisfied.

The all-binaries container previously copied Ubuntu/glibc-linked executables into Alpine/musl. Its runtime definition now matches Ubuntu 24.04 and installs native runtime libraries. The single-CLI deployment previously built the repository's unrelated `opencog/opencog-dev` Dockerfile instead of its compiled CLI. It now uses the verified Linux artifact and a matching runtime definition, with a `/cli` image namespace to avoid racing the all-binaries workflow's full-suite image tags. These are **proposed future-workflow changes**, not changes to the already-published release or registry images.

A non-publishing PR workflow runs deterministic packaging contract tests. Release notes now distinguish real executable commands from library entry-point artifacts rather than promising interactive CLIs for every target.

## Validation

| Check | Result |
|---|---|
| Edited workflow `actionlint` | Passed |
| Workflow YAML parsing | Passed |
| Shell syntax | Passed |
| Five deterministic packaging cases | Passed: normal output, propagated build failure, missing/stale target rejection, architecture rejection, static-flag propagation |
| Staged whitespace, secret, and size guard | Passed |
| Real frozen optimized all-target packaging | **Stopped after 600 seconds**, exit 124; nine executable files produced before the `ml_bin` build |
| Built optimized CLI invocation | Exited successfully; reports the existing embedded version **0.1.0** and usage text |
| macOS/native ARM and Docker execution | Not run locally; requires hosted platform validation |

The bounded optimized build timeout is **not** reported as release success or as another compiler segmentation fault. The prior normal-flag all-target build passed; optimized release compilation is substantially slower and still needs an uninterrupted hosted run. The existing source version remains 0.1.0 despite the v1.0.0 tag; this follow-up does not invent a version bump.

## Boundaries and next steps

The follow-up is delivered as a separate reviewable PR. It is not automatically merged. The published `v1.0.0` tag/release, existing assets, registry images, and queued manual runs remain untouched.

After review and merge, validate the four platform builds and container smoke checks before publishing a new release or intentionally supplementing the current one. Rerunning an old failed run would use its old commit/workflow and would not pick up these corrections. Full-suite distributed lifecycle/test-stage failures remain separate work; green monitoring workflows do not close them.

GitHub operations use the previously user-authorized Beast credential fallback because the configured gitpat previously returned HTTP 401. No secrets are included in this report or patch.
