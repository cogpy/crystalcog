'use strict';

const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const ROOT = path.resolve(__dirname, '..');
const GENERATOR = path.join(__dirname, 'generate-priority-issues.js');

test('only reports explicit integration failure lines', (t) => {
  const artifactDir = fs.mkdtempSync(path.join(os.tmpdir(), 'crystalcog-priority-'));
  t.after(() => fs.rmSync(artifactDir, { recursive: true, force: true }));

  fs.writeFileSync(
    path.join(artifactDir, 'integration-test.log'),
    [
      'creates failed response2026-10-25 17:14:25.599 [WARN] No configuration file found. Using defaults.',
      'Integration test failed: expected status 200, got 500',
    ].join('\n'),
  );
  const outputPath = path.join(artifactDir, 'findings.json');

  execFileSync(process.execPath, [GENERATOR, '--scan-only', '--output', outputPath], {
    cwd: ROOT,
    env: {
      ...process.env,
      ARTIFACT_DIR: artifactDir,
      GITHUB_STEP_SUMMARY: path.join(artifactDir, 'summary.md'),
    },
    stdio: 'ignore',
  });

  const findings = JSON.parse(fs.readFileSync(outputPath, 'utf8')).findings;
  const lineFailures = findings.filter((finding) => finding.fingerprint.startsWith('line-fail:'));

  assert.deepEqual(lineFailures.map((finding) => finding.name), [
    'Integration test failed: expected status 200, got 500',
  ]);
});
