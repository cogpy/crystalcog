# Maintenance issue evidence

The priority generator (`scripts/generate-priority-issues.js`) distinguishes test failures from application diagnostics. A passing negative-path test can legitimately log a refused connection, malformed storage input, or unavailable backend; a logger's `ERROR`/`WARN` record alone is not a failed assertion.

## Failure evidence

The generator still reports JUnit `<failure>`/`<error>` records, Crystal assertion descriptions, positive failure/error totals, failed directory totals, explicit shell-harness failures, linker/compiler errors and unhandled exceptions. These remain actionable even if a calling job mistakenly reports success. A failing job with no detailed test evidence produces a job-level finding with its workflow link; successful/skipped job statuses do not invent failures.

Plain test descriptions such as `creates failed response`, `Error Handling`, passing `0 failed` totals, LLVM exception symbols, and timestamped application logger records are not standalone failure evidence. The parser does not turn all output from a successful job into trusted success: explicit failed assertions/builds still win over a green badge.

Report evidence contains the detected failure lines, not the first thousand characters of unrelated compilation statistics. Unit-named logs remain unit findings rather than being relabelled as integration failures.

## Stable issue identities

Line/report fingerprints use failure evidence, excluding unrelated report noise. Only recognized logger timestamps and the complete ephemeral `#<TCPSocket:0x...>` identity are normalized. Ports, node/peer identifiers, source paths, line numbers, thresholds and other diagnostic fields stay distinct. Repeated job-level failures use the source workflow identity rather than the run number.

Existing issues with older run-specific fingerprints are not silently closed or rewritten. Reconcile them with linked evidence before consolidation. Historical failure reports can contain different real causes even when their titles match; age or a current green badge is not sufficient reason to close them.

## Local validation

```sh
node --check scripts/generate-priority-issues.js
node --test scripts/generate-priority-issues.test.js
```

The CLI fixtures isolate both the repository root and artifacts, use `--scan-only`, and cover passing error-path logs, genuine failures and repeat identities. The existing Validate Scripts workflow runs this gate on relevant pull requests.

To inspect actual artifacts without writing to GitHub:

```sh
ARTIFACT_DIR=/path/to/artifacts \
  node scripts/generate-priority-issues.js --scan-only --output /tmp/priority-findings.json
```

Set `UNIT_RESULT`, `INTEGRATION_RESULT` and `E2E_RESULT` to the actual calling-job results when available. `--scan-only` writes findings (and an optional step summary) but returns before issue upserts. Stub/coverage-gap scanning is independent of test-failure scanning, so a clean test log may still legitimately report incomplete work.

Issue [#284](https://github.com/cogpy/crystalcog/issues/284) records the false-positive backlog diagnosis and prior evidence-based cleanup. This parser repair addresses future detection and deduplication; it is not a guarantee of complete production test coverage or a replacement for fail-closed CI commands.
