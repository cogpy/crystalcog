'use strict';

const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const GENERATOR = path.join(__dirname, 'generate-priority-issues.js');

function scan(t, files = {}, overrides = {}) {
  // Isolate ROOT as well as artifacts: repository logs/stub findings cannot leak
  // into fixtures, and --scan-only cannot write to GitHub even with ambient auth.
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'crystalcog-priority-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const scripts = path.join(root, 'scripts');
  const artifacts = path.join(root, 'artifacts');
  fs.mkdirSync(scripts);
  fs.mkdirSync(artifacts);
  const generator = path.join(scripts, 'generate-priority-issues.js');
  fs.copyFileSync(GENERATOR, generator);
  for (const [filename, content] of Object.entries(files)) {
    fs.writeFileSync(path.join(artifacts, filename), content);
  }
  const outputPath = path.join(artifacts, 'findings.json');
  execFileSync(process.execPath, [generator, '--scan-only', '--output', outputPath], {
    cwd: root,
    env: {
      ...process.env,
      GITHUB_TOKEN: '',
      GITHUB_REPOSITORY: 'cogpy/crystalcog',
      GITHUB_RUN_ID: '101',
      SOURCE_WORKFLOW: 'Fixture pipeline',
      UNIT_RESULT: '',
      INTEGRATION_RESULT: '',
      E2E_RESULT: '',
      ARTIFACT_DIR: artifacts,
      GITHUB_STEP_SUMMARY: path.join(artifacts, 'summary.md'),
      ...overrides,
    },
    stdio: 'ignore',
  });
  return JSON.parse(fs.readFileSync(outputPath, 'utf8')).findings;
}

function lineFailures(findings) {
  return findings.filter((finding) => finding.fingerprint.startsWith('line-fail:'));
}

function fingerprints(findings) {
  return findings.map((finding) => finding.fingerprint).sort();
}

test('only reports explicit integration failure lines', (t) => {
  const findings = scan(t, { 'integration-test.log': [
    'creates failed response2026-10-25 17:14:25.599 [WARN] No configuration file found. Using defaults.',
    'Integration test failed: expected status 200, got 500',
  ].join('\n') });
  assert.deepEqual(lineFailures(findings).map((finding) => finding.name), [
    'Integration test failed: expected status 200, got 500',
  ]);
});

test('passing negative-path logs and test descriptions produce no failure issues', (t) => {
  const findings = scan(t, { 'unit-test.log': [
    '2026-11-21 02:07:06.370 [ERROR] Failed to send message to node ghost-1: Connection refused',
    '2026-11-21 02:07:06.371 [ERROR] AtomSpace::FileStorageNode: Failed to load AtomSpace: malformed input',
    '2026-11-21 02:07:06.372 [ERROR] Generation failed: 500 - {"error":"boom"}',
    'creates failed response',
    'Error Handling and Edge Cases',
    'error handling',
    'Error condition tests passed',
    '- Sync::Error::Deadlock (S-ync.o0.bc)',
    '- Spec::AssertionFailed (S-pec.o0.bc)',
    '2673 examples, 0 failures, 0 errors, 2 pending',
    '=== Summary: 23 passed, 0 failed ===',
  ].join('\n') }, { UNIT_RESULT: 'success', INTEGRATION_RESULT: 'success' });
  assert.deepEqual(findings, []);
});

test('failed jobs remain actionable even when logs contain only application diagnostics', (t) => {
  const findings = scan(t, { 'integration-test.log':
    '2026-11-21 02:07:06.370 [ERROR] Failed to connect to peer localhost:20001: Connection refused' },
  { UNIT_RESULT: 'failure', INTEGRATION_RESULT: 'failure', E2E_RESULT: 'failure' });
  assert.deepEqual(findings.map((finding) => finding.type).sort(), [
    'e2e_test_failure', 'integration_test_failure', 'unit_test_failure',
  ]);
  assert.equal(lineFailures(findings).length, 0);
});

test('JUnit failures are retained despite a successful job status', (t) => {
  const findings = scan(t, { 'test-results.xml':
    '<testsuite name="suite"><testcase name="rejects bad data" classname="atomspace"><failure>Expected true, got false</failure></testcase></testsuite>' },
  { UNIT_RESULT: 'success' });
  assert.equal(findings.length, 1);
  assert.equal(findings[0].type, 'unit_test_failure');
  assert.equal(findings[0].name, 'rejects bad data');
});

test('explicit linker and runtime errors are not hidden by a later passing summary', (t) => {
  const findings = scan(t, { 'unit-test.log': [
    '\u001b[31m/usr/bin/ld: cannot find -lrocksdb: No such file or directory\u001b[0m',
    'Error: execution of command failed with exit status 1',
    'Unhandled exception: database startup failed (RuntimeError)',
    '2673 examples, 0 failures, 0 errors, 2 pending',
  ].join('\n') }, { UNIT_RESULT: 'success' });
  assert.equal(lineFailures(findings).length, 3);
  assert.ok(findings.every((finding) => finding.type === 'unit_test_failure'));
});

test('positive Crystal failure/error and directory totals are explicit failure evidence', (t) => {
  for (const summary of ['3 examples, 1 failure, 0 errors', '3 examples, 0 failures, 1 error',
    '=== Summary: 22 passed, 1 failed ===']) {
    const findings = scan(t, { 'unit-test.log': summary }, { UNIT_RESULT: 'success' });
    assert.equal(lineFailures(findings).length, 1, summary);
  }
});

test('Crystal assertion records retain test identity', (t) => {
  const findings = scan(t, { 'unit-test.log': [
    'Failures:', '  1) AtomSpace keeps all atoms',
    '       Expected: 3', '            got: 2',
    '       # spec/atomspace/atomspace_spec.cr:12',
    '1 example, 1 failure, 0 errors',
  ].join('\n') });
  assert.ok(findings.some((finding) => finding.name === 'AtomSpace keeps all atoms' &&
    finding.file === 'spec/atomspace/atomspace_spec.cr'));
});

test('timestamps/socket identities and unrelated report noise do not change failure fingerprints', (t) => {
  const first = scan(t, { 'integration-test.log': [
    'Parse: 10ms',
    'Integration test failed: 2026-11-21 02:07:06.370 [ERROR] peer-1 write (#<TCPSocket:0xabc>): Broken pipe',
  ].join('\n') });
  const second = scan(t, { 'integration-test.log': [
    'Parse: 100ms; different compiler stats',
    'Integration test failed: 2026-11-22 04:08:09.999 [ERROR] peer-1 write (#<TCPSocket:0xdef>): Broken pipe',
  ].join('\n') });
  assert.equal(first.length, 2);
  assert.deepEqual(fingerprints(first), fingerprints(second));
  assert.ok(first[0].detail.startsWith('Integration test failed:'));
  assert.ok(!first[0].detail.includes('Parse:'));
});

test('different ports and node identities remain distinct failures', (t) => {
  const first = scan(t, { 'integration-test.log': 'Integration test failed: peer-1 localhost:20001 refused' });
  const port = scan(t, { 'integration-test.log': 'Integration test failed: peer-1 localhost:20002 refused' });
  const peer = scan(t, { 'integration-test.log': 'Integration test failed: peer-2 localhost:20001 refused' });
  assert.notDeepEqual(fingerprints(first), fingerprints(port));
  assert.notDeepEqual(fingerprints(first), fingerprints(peer));
});

test('repeated job failures update one identity per source workflow, not per run', (t) => {
  const first = scan(t, {}, { E2E_RESULT: 'failure', GITHUB_RUN_ID: '101' });
  const second = scan(t, {}, { E2E_RESULT: 'failure', GITHUB_RUN_ID: '202' });
  const otherWorkflow = scan(t, {}, { E2E_RESULT: 'failure', SOURCE_WORKFLOW: 'Other pipeline' });
  assert.equal(first.length, 1);
  assert.deepEqual(fingerprints(first), fingerprints(second));
  assert.notDeepEqual(fingerprints(first), fingerprints(otherWorkflow));
});

test('explicit FAIL/FATAL shell output is retained without job metadata', (t) => {
  const findings = scan(t, { 'e2e-report.log': [
    'FAIL: persistence round trip',
    'FATAL: server exited unexpectedly',
  ].join('\n') });
  assert.equal(lineFailures(findings).length, 2);
  assert.ok(findings.every((finding) => finding.type === 'e2e_test_failure'));
});

test('explicit failure records win over embedded application logger diagnostics', (t) => {
  const findings = scan(t, { 'unit-test.log': [
    'FAIL: expected quiet stderr, got 2026-11-21 02:07:06.370 [ERROR] peer refused',
    'Unhandled exception: 2026-11-21 02:07:06.370 [ERROR] peer refused (RuntimeError)',
    '/usr/bin/ld: cannot find -lrocksdb: 2026-11-21 02:07:06.370 [ERROR] missing dependency',
    '2026-11-21 02:07:06.370 [ERROR] expected unavailable backend: cannot find -loptional',
  ].join('\n') }, { UNIT_RESULT: 'success' });
  assert.equal(lineFailures(findings).length, 3);
  assert.ok(!lineFailures(findings).some((finding) => finding.detail.includes('unavailable backend')));
});

test('standalone FAIL and FAILED markers remain failures', (t) => {
  for (const marker of ['FAIL', 'FAILED']) {
    const findings = scan(t, { 'e2e-test.log': marker }, { E2E_RESULT: 'success' });
    assert.equal(lineFailures(findings).length, 1, marker);
  }
});
