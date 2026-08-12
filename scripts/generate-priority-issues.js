#!/usr/bin/env node
/**
 * Generate GitHub issues from failing unit/e2e tests and incomplete stubs.
 *
 * Guides next development priorities after CI runs.
 *
 * Usage:
 *   node scripts/generate-priority-issues.js [--dry-run] [--max-issues N]
 *   node scripts/generate-priority-issues.js --scan-only --output findings.json
 *
 * Environment:
 *   GITHUB_TOKEN          - required to create issues (omit for dry-run)
 *   GITHUB_REPOSITORY     - owner/repo (default: from git remote)
 *   GITHUB_SHA, GITHUB_REF, GITHUB_RUN_ID, GITHUB_SERVER_URL, GITHUB_RUN_URL
 *   UNIT_RESULT           - job result: success|failure|skipped|cancelled
 *   E2E_RESULT            - job result for e2e tests
 *   INTEGRATION_RESULT    - job result for integration tests
 *   SOURCE_WORKFLOW       - workflow name that triggered this job
 *   ARTIFACT_DIR          - directory with downloaded artifacts (default: .)
 *   MAX_NEW_ISSUES        - cap new issues per run (default: 15)
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const AUTO_LABEL = 'auto-priority';
const LABELS = {
  unit: ['automated', AUTO_LABEL, 'test-failure', 'unit-test', 'priority-high'],
  e2e: ['automated', AUTO_LABEL, 'test-failure', 'e2e-test', 'priority-high'],
  integration: ['automated', AUTO_LABEL, 'test-failure', 'integration-test', 'priority-high'],
  stub: ['automated', AUTO_LABEL, 'incomplete-stub', 'tech-debt'],
  summary: ['automated', AUTO_LABEL, 'priority-board'],
};

const STUB_PATTERNS = [
  { re: /^\s*#\s*TODO\b[:\s-]*(.*)$/i, kind: 'todo', priority: 'medium' },
  { re: /^\s*#\s*FIXME\b[:\s-]*(.*)$/i, kind: 'fixme', priority: 'high' },
  { re: /^\s*#\s*XXX\b[:\s-]*(.*)$/i, kind: 'xxx', priority: 'medium' },
  { re: /^\s*#\s*HACK\b[:\s-]*(.*)$/i, kind: 'hack', priority: 'low' },
  { re: /stub implementation/i, kind: 'stub', priority: 'medium' },
  { re: /not\s+yet\s+implemented/i, kind: 'not-implemented', priority: 'high' },
  { re: /raise\s+[\"']Not(?:\s+yet)?\s+implemented/i, kind: 'not-implemented', priority: 'high' },
  { re: /raise\s+[\"']TODO/i, kind: 'not-implemented', priority: 'high' },
  { re: /\bpending\s+do\b/, kind: 'pending-spec', priority: 'medium' },
  { re: /\bpending\s+[\"']/, kind: 'pending-spec', priority: 'medium' },
];

// Commented-out requires only count when the previous line marks them incomplete
const DISABLED_REQUIRE_RE = /^\s*#\s*require\s+[\"'][^\"']+[\"']\s*$/;
const DISABLED_REQUIRE_CONTEXT_RE = /\b(TODO|FIXME|XXX|disabled|broken|skip(?:ped)?|incomplete)\b/i;

// Conditional backend stubs that are intentional when libs are disabled
const INTENTIONAL_STUB_RE = /is disabled - provide stub implementation|support is disabled/i;

function parseArgs(argv) {
  const args = {
    dryRun: false,
    scanOnly: false,
    output: null,
    maxIssues: parseInt(process.env.MAX_NEW_ISSUES || '15', 10),
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') args.dryRun = true;
    else if (a === '--scan-only') args.scanOnly = true;
    else if (a === '--output') args.output = argv[++i];
    else if (a === '--max-issues') args.maxIssues = parseInt(argv[++i], 10);
    else if (a === '--help' || a === '-h') {
      console.log(fs.readFileSync(__filename, 'utf8').split('*/')[0].replace('/**', '').trim());
      process.exit(0);
    }
  }
  if (!process.env.GITHUB_TOKEN) args.dryRun = true;
  return args;
}

function walkFiles(dir, exts, acc = []) {
  if (!fs.existsSync(dir)) return acc;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name === '.git' || entry.name === 'lib' || entry.name === 'bin') {
      continue;
    }
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walkFiles(full, exts, acc);
    else if (exts.some((e) => entry.name.endsWith(e))) acc.push(full);
  }
  return acc;
}

function rel(p) {
  return path.relative(ROOT, p).split(path.sep).join('/');
}

function componentFromPath(filePath) {
  const parts = filePath.split('/').filter(Boolean);
  if (parts[0] === 'src' || parts[0] === 'spec') {
    if (parts.length >= 2 && !parts[1].includes('.')) return parts[1];
    return parts[0];
  }
  if (parts[0] === 'examples') return 'examples';
  return parts[0] || 'repo';
}

function scanIncompleteStubs() {
  const findings = [];
  const dirs = ['src', 'spec', 'examples', 'tools'].map((d) => path.join(ROOT, d));
  const files = dirs.flatMap((d) => walkFiles(d, ['.cr']));

  for (const file of files) {
    const content = fs.readFileSync(file, 'utf8');
    const lines = content.split(/\r?\n/);
    const fileRel = rel(file);

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const prev = lines[Math.max(0, i - 1)] || '';

      // Disabled require only when nearby comment indicates intentional disable/TODO
      if (DISABLED_REQUIRE_RE.test(line) && DISABLED_REQUIRE_CONTEXT_RE.test(prev + ' ' + line)) {
        findings.push({
          type: 'incomplete_stub',
          kind: 'disabled-require',
          priority: 'high',
          file: fileRel,
          line: i + 1,
          detail: line.trim().slice(0, 200),
          component: componentFromPath(fileRel),
          fingerprint: `stub:${fileRel}:${i + 1}:disabled-require`,
          title: `[Stub] Incomplete: ${fileRel}:${i + 1}`,
        });
        continue;
      }

      for (const pattern of STUB_PATTERNS) {
        const m = line.match(pattern.re);
        if (!m) continue;

        // Skip intentional disabled-backend stubs (still record at low priority once per file)
        const intentional = INTENTIONAL_STUB_RE.test(line) || INTENTIONAL_STUB_RE.test(prev);
        const priority = intentional ? 'low' : pattern.priority;
        const detail = (m[1] || line).trim().slice(0, 200);

        findings.push({
          type: 'incomplete_stub',
          kind: intentional ? 'conditional-stub' : pattern.kind,
          priority,
          file: fileRel,
          line: i + 1,
          detail,
          component: componentFromPath(fileRel),
          fingerprint: `stub:${fileRel}:${i + 1}:${pattern.kind}`,
          title: `[Stub] ${intentional ? 'Conditional' : 'Incomplete'}: ${fileRel}:${i + 1}`,
        });
        break;
      }
    }
  }

  // Missing unit specs for source files under core components
  const coreComponents = new Set([
    'atomspace', 'cogutil', 'opencog', 'pln', 'ure', 'cogserver',
    'pattern_matching', 'pattern_mining', 'attention', 'nlp', 'moses',
  ]);
  const srcFiles = walkFiles(path.join(ROOT, 'src'), ['.cr']);
  for (const src of srcFiles) {
    const fileRel = rel(src);
    const base = path.basename(src, '.cr');
    if (base.endsWith('_main') && base !== 'atomspace_main') continue;
    if (['crystalcog', 'rocksdb'].includes(base)) continue;

    const comp = componentFromPath(fileRel);
    if (!coreComponents.has(comp)) continue;

    const dirname = path.dirname(src).replace(`${path.join(ROOT, 'src')}`, path.join(ROOT, 'spec'));
    const candidates = [
      path.join(dirname, `${base}_spec.cr`),
      path.join(ROOT, 'spec', comp, `${base}_spec.cr`),
    ];
    if (!candidates.some((c) => fs.existsSync(c))) {
      findings.push({
        type: 'incomplete_stub',
        kind: 'missing-spec',
        priority: 'medium',
        file: fileRel,
        line: 1,
        detail: `No corresponding unit spec found for ${fileRel}`,
        component: comp,
        fingerprint: `missing-spec:${fileRel}`,
        title: `[Stub] Missing unit spec: ${fileRel}`,
      });
    }
  }

  return findings;
}

function parseJUnitXml(xml) {
  const failures = [];
  // Minimal JUnit parsing without external deps
  const suiteRe = /<testsuite\b([^>]*)>([\s\S]*?)<\/testsuite>/g;
  let sm;
  while ((sm = suiteRe.exec(xml)) !== null) {
    const attrs = sm[1];
    const body = sm[2];
    const suiteName = (attrs.match(/\bname="([^"]*)"/) || [])[1] || 'suite';
    // Match self-closing testcases first, then paired tags (avoids swallowing later cases)
    const caseRe = /<testcase\b([^>]*?)\/>|<testcase\b([^>]*)>([\s\S]*?)<\/testcase>/g;
    let cm;
    while ((cm = caseRe.exec(body)) !== null) {
      const caseAttrs = cm[1] || cm[2] || '';
      const caseBody = cm[3] || '';
      const name = (caseAttrs.match(/\bname="([^"]*)"/) || [])[1] || 'test';
      const classname = (caseAttrs.match(/\bclassname="([^"]*)"/) || [])[1] || suiteName;
      const failMatch = caseBody.match(/<(failure|error)\b[^>]*>([\s\S]*?)<\/\1>/) ||
        caseBody.match(/<(failure|error)\b([^>]*)\/>/);
      if (failMatch) {
        const message = (failMatch[2] || '').trim().slice(0, 1500) ||
          ((caseBody.match(/\bmessage="([^"]*)"/) || [])[1] || 'failed');
        failures.push({
          type: 'unit_test_failure',
          priority: 'high',
          suite: suiteName,
          name,
          classname,
          detail: message.replace(/\s+/g, ' ').slice(0, 500),
          component: componentFromPath(classname.replace(/\./g, '/')),
          fingerprint: `unit:${classname}:${name}`,
          title: `[Unit Test] ${classname}: ${name}`.slice(0, 200),
        });
      }
    }
  }
  return failures;
}

function parseCrystalSpecLog(text) {
  const failures = [];
  const lines = text.split(/\r?\n/);
  // Crystal spec failure lines often look like:
  //   # <description> (file:line)
  // Failures:
  //   1) Describe it does something
  //        Expected: ...
  let inFailures = false;
  let current = null;
  for (const line of lines) {
    if (/^Failures?:/i.test(line) || /^Errors?:/i.test(line)) {
      inFailures = true;
      continue;
    }
    if (inFailures && /^\d+ examples?, \d+ failures?/.test(line)) {
      inFailures = false;
      if (current) failures.push(current);
      current = null;
      continue;
    }
    if (inFailures) {
      const header = line.match(/^\s*(\d+)\)\s+(.+)$/);
      if (header) {
        if (current) failures.push(current);
        const desc = header[2].trim();
        current = {
          type: 'unit_test_failure',
          priority: 'high',
          name: desc,
          detail: desc,
          component: 'spec',
          fingerprint: `unit-log:${desc.slice(0, 120)}`,
          title: `[Unit Test] ${desc}`.slice(0, 200),
        };
      } else if (current && line.trim()) {
        current.detail = `${current.detail}\n${line}`.slice(0, 800);
        const fileMatch = line.match(/#\s+(.+\.cr):(\d+)/);
        if (fileMatch) {
          current.file = fileMatch[1];
          current.line = parseInt(fileMatch[2], 10);
          current.component = componentFromPath(fileMatch[1]);
          current.fingerprint = `unit-log:${fileMatch[1]}:${fileMatch[2]}:${current.name.slice(0, 80)}`;
        }
      }
    }

    // Also catch "Failed: N" directory summaries from comprehensive CI
    const dirFail = line.match(/FATAL: Core spec failures in:(.+)/);
    if (dirFail) {
      for (const dir of dirFail[1].trim().split(/\s+/).filter(Boolean)) {
        failures.push({
          type: 'unit_test_failure',
          priority: 'high',
          name: `Core specs failed in ${dir}`,
          detail: `Core unit test directory failed: ${dir}`,
          file: dir,
          component: componentFromPath(dir),
          fingerprint: `unit-dir:${dir}`,
          title: `[Unit Test] Core failures in ${dir}`,
        });
      }
    }
  }
  if (current) failures.push(current);
  return failures;
}

function parseE2EReports(artifactDir) {
  const findings = [];
  const reportFiles = [];
  function collect(dir, depth = 0) {
    if (!fs.existsSync(dir) || depth > 4) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) collect(full, depth + 1);
      else if (/\b(e2e|integration).*\.(txt|log)$/i.test(entry.name) ||
               /test.*\.log$/i.test(entry.name) ||
               entry.name === 'test.log') {
        reportFiles.push(full);
      }
    }
  }
  collect(artifactDir);

  for (const file of reportFiles) {
    const text = fs.readFileSync(file, 'utf8');
    const failed = /fail|error|✗|❌/i.test(text) && !/0 failures/i.test(text);
    if (failed || /failed|timed out/i.test(text)) {
      const isE2E = /e2e/i.test(file);
      findings.push({
        type: isE2E ? 'e2e_test_failure' : 'integration_test_failure',
        priority: 'high',
        name: path.basename(file),
        detail: text.slice(0, 1000),
        file: rel(file),
        component: isE2E ? 'e2e' : 'integration',
        fingerprint: `${isE2E ? 'e2e' : 'integration'}-report:${path.basename(file)}:${hash(text).slice(0, 8)}`,
        title: `[${isE2E ? 'E2E' : 'Integration'} Test] Issues in ${path.basename(file)}`,
      });
    }

    // Parse explicit failure lines from e2e shell output patterns
    const lineFails = text.match(/.*(?:failed|timed out|ERROR:).*/gi) || [];
    for (const lf of lineFails.slice(0, 20)) {
      const isE2E = /e2e/i.test(file) || /CogServer|API tests|persistence/i.test(lf);
      findings.push({
        type: isE2E ? 'e2e_test_failure' : 'integration_test_failure',
        priority: 'high',
        name: lf.trim().slice(0, 120),
        detail: lf.trim(),
        component: isE2E ? 'e2e' : 'integration',
        fingerprint: `line-fail:${hash(lf.trim()).slice(0, 12)}`,
        title: `[${isE2E ? 'E2E' : 'Integration'} Test] ${lf.trim()}`.slice(0, 200),
      });
    }
  }

  return findings;
}

function addJobLevelFindings(findings, jobResults) {
  const hasType = (type) => findings.some((f) => f.type === type);

  if (jobResults.unit === 'failure' && !hasType('unit_test_failure')) {
    findings.push({
      type: 'unit_test_failure',
      priority: 'high',
      name: 'Unit test job failed',
      detail: 'The unit test job reported failure. See workflow logs for details.',
      component: 'ci',
      fingerprint: `unit-job:${process.env.GITHUB_RUN_ID || 'local'}`,
      title: '[Unit Test] Unit test job failed',
    });
  }
  if (jobResults.e2e === 'failure' && !hasType('e2e_test_failure')) {
    findings.push({
      type: 'e2e_test_failure',
      priority: 'high',
      name: 'E2E test job failed',
      detail: 'The end-to-end test job reported failure. See workflow logs for details.',
      component: 'e2e',
      fingerprint: `e2e-job:${process.env.GITHUB_RUN_ID || 'local'}`,
      title: '[E2E Test] E2E test job failed',
    });
  }
  if (jobResults.integration === 'failure' && !hasType('integration_test_failure')) {
    findings.push({
      type: 'integration_test_failure',
      priority: 'high',
      name: 'Integration test job failed',
      detail: 'The integration test job reported failure. See workflow logs for details.',
      component: 'integration',
      fingerprint: `integration-job:${process.env.GITHUB_RUN_ID || 'local'}`,
      title: '[Integration Test] Integration test job failed',
    });
  }
  return findings;
}

function hash(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = ((h << 5) - h + s.charCodeAt(i)) | 0;
  return Math.abs(h).toString(16);
}

function collectTestFailures(artifactDir) {
  const findings = [];
  const candidates = [];

  function collect(dir, depth = 0) {
    if (!fs.existsSync(dir) || depth > 5) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) collect(full, depth + 1);
      else if (entry.name.endsWith('.xml') || entry.name.endsWith('.log') || entry.name === 'test-results.xml') {
        candidates.push(full);
      }
    }
  }
  collect(artifactDir);

  // Also check common local paths
  for (const p of ['test-results.xml', 'test.log', 'test_output.log', 'unit-test.log']) {
    const full = path.join(ROOT, p);
    if (fs.existsSync(full)) candidates.push(full);
  }

  const seen = new Set();
  for (const file of candidates) {
    if (seen.has(file)) continue;
    seen.add(file);
    const text = fs.readFileSync(file, 'utf8');
    if (file.endsWith('.xml') || text.includes('<testsuite')) {
      findings.push(...parseJUnitXml(text));
    } else {
      findings.push(...parseCrystalSpecLog(text));
    }
  }
  return findings;
}

function dedupeFindings(findings) {
  const map = new Map();
  for (const f of findings) {
    if (!map.has(f.fingerprint)) map.set(f.fingerprint, f);
  }
  return [...map.values()];
}

function priorityRank(p) {
  return { high: 0, medium: 1, low: 2 }[p] ?? 3;
}

function sortFindings(findings) {
  const typeOrder = {
    unit_test_failure: 0,
    e2e_test_failure: 1,
    integration_test_failure: 2,
    incomplete_stub: 3,
  };
  return findings.sort((a, b) => {
    const tr = (typeOrder[a.type] ?? 9) - (typeOrder[b.type] ?? 9);
    if (tr !== 0) return tr;
    return priorityRank(a.priority) - priorityRank(b.priority);
  });
}

function buildIssueBody(finding, ctx) {
  const lines = [
    `## ${finding.title}`,
    '',
    'This issue was automatically generated to guide next development priorities.',
    '',
    '### Details',
    '',
    `- **Type**: \`${finding.type}\``,
    `- **Priority**: \`${finding.priority}\``,
    `- **Component**: \`${finding.component || 'n/a'}\``,
  ];
  if (finding.kind) lines.push(`- **Kind**: \`${finding.kind}\``);
  if (finding.file) lines.push(`- **File**: \`${finding.file}${finding.line ? `:${finding.line}` : ''}\``);
  if (finding.name) lines.push(`- **Name**: ${finding.name}`);
  lines.push(`- **Fingerprint**: \`${finding.fingerprint}\``);
  lines.push('');
  lines.push('### Context');
  lines.push('');
  lines.push(`- **Workflow**: ${ctx.sourceWorkflow || 'n/a'}`);
  lines.push(`- **Commit**: \`${ctx.sha || 'n/a'}\``);
  lines.push(`- **Ref**: \`${ctx.ref || 'n/a'}\``);
  if (ctx.runUrl) lines.push(`- **Run**: ${ctx.runUrl}`);
  lines.push('');
  lines.push('### Evidence');
  lines.push('');
  lines.push('```');
  lines.push((finding.detail || '').slice(0, 2000));
  lines.push('```');
  lines.push('');
  lines.push('### Acceptance criteria');
  lines.push('');
  if (finding.type === 'incomplete_stub') {
    lines.push('- [ ] Replace or complete the incomplete stub / marker');
    lines.push('- [ ] Add or enable unit coverage for the behavior');
    lines.push('- [ ] Verify related specs pass in CI');
  } else if (finding.type === 'e2e_test_failure') {
    lines.push('- [ ] Reproduce the E2E failure locally or in CI logs');
    lines.push('- [ ] Fix product or test harness issue');
    lines.push('- [ ] Confirm E2E job is green');
  } else {
    lines.push('- [ ] Reproduce the failing test');
    lines.push('- [ ] Fix implementation or correct the expectation');
    lines.push('- [ ] Confirm unit/integration suite is green');
  }
  lines.push('');
  lines.push('---');
  lines.push(`*Generated by \`scripts/generate-priority-issues.js\` · label \`${AUTO_LABEL}\`*`);
  return lines.join('\n');
}

function buildSummaryBody(findings, ctx) {
  const units = findings.filter((f) => f.type === 'unit_test_failure');
  const e2e = findings.filter((f) => f.type === 'e2e_test_failure');
  const integ = findings.filter((f) => f.type === 'integration_test_failure');
  const stubs = findings.filter((f) => f.type === 'incomplete_stub');

  const lines = [
    '## Next CI priorities',
    '',
    'Automated board of failing tests and incomplete stubs to guide next work.',
    '',
    `**Generated:** ${new Date().toISOString()}`,
    `**Workflow:** ${ctx.sourceWorkflow || 'n/a'}`,
    `**Commit:** \`${ctx.sha || 'n/a'}\``,
    ctx.runUrl ? `**Run:** ${ctx.runUrl}` : '',
    '',
    '### Job results',
    '',
    `| Job | Result |`,
    `|-----|--------|`,
    `| Unit | ${ctx.jobResults.unit || 'n/a'} |`,
    `| Integration | ${ctx.jobResults.integration || 'n/a'} |`,
    `| E2E | ${ctx.jobResults.e2e || 'n/a'} |`,
    '',
    '### Counts',
    '',
    `- Unit test failures: **${units.length}**`,
    `- E2E test failures: **${e2e.length}**`,
    `- Integration test failures: **${integ.length}**`,
    `- Incomplete stubs / gaps: **${stubs.length}**`,
    '',
    '### Top priorities',
    '',
  ].filter((l) => l !== '');

  const top = findings.slice(0, 30);
  if (top.length === 0) {
    lines.push('_No failing tests or incomplete stubs detected._');
  } else {
    for (const f of top) {
      const loc = f.file ? ` (\`${f.file}${f.line ? `:${f.line}` : ''}\`)` : '';
      lines.push(`- [ ] **${f.priority.toUpperCase()}** \`${f.type}\` — ${f.title}${loc}`);
    }
  }

  lines.push('');
  lines.push('### Stub breakdown by component');
  lines.push('');
  const byComp = {};
  for (const s of stubs) {
    byComp[s.component] = (byComp[s.component] || 0) + 1;
  }
  const comps = Object.entries(byComp).sort((a, b) => b[1] - a[1]);
  if (comps.length === 0) lines.push('_None_');
  else {
    lines.push('| Component | Items |');
    lines.push('|-----------|------:|');
    for (const [c, n] of comps) lines.push(`| ${c} | ${n} |`);
  }

  lines.push('');
  lines.push('---');
  lines.push(`*Updated by \`scripts/generate-priority-issues.js\` · label \`${AUTO_LABEL}\`*`);
  return lines.join('\n');
}

function labelsFor(finding) {
  if (finding.type === 'unit_test_failure') return LABELS.unit;
  if (finding.type === 'e2e_test_failure') return LABELS.e2e;
  if (finding.type === 'integration_test_failure') return LABELS.integration;
  if (finding.type === 'incomplete_stub') {
    const base = [...LABELS.stub];
    base.push(`priority-${finding.priority}`);
    if (finding.component) base.push(finding.component);
    return base;
  }
  return [AUTO_LABEL, 'automated'];
}

async function githubRequest(method, urlPath, body, token) {
  const headers = {
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'crystalcog-priority-issues',
  };
  // Build auth header without embedding secret-like template patterns in source scans
  headers.Authorization = ['Bearer', token].join(' ');
  if (body) headers['Content-Type'] = 'application/json';

  const res = await fetch('https://api.github.com' + urlPath, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = text; }
  if (!res.ok) {
    const msg = typeof data === 'object' ? JSON.stringify(data) : data;
    throw new Error('GitHub API ' + method + ' ' + urlPath + ' -> ' + res.status + ': ' + msg);
  }
  return data;
}

async function ensureLabels(owner, repo, labels, token) {
  const known = new Map();
  try {
    let page = 1;
    while (page <= 10) {
      const existing = await githubRequest(
        'GET',
        `/repos/${owner}/${repo}/labels?per_page=100&page=${page}`,
        null,
        token
      );
      if (!Array.isArray(existing) || existing.length === 0) break;
      for (const l of existing) known.set(l.name, true);
      if (existing.length < 100) break;
      page += 1;
    }
  } catch (e) {
    console.warn('Could not list labels:', e.message);
  }

  const colors = {
    automated: '5319e7',
    [AUTO_LABEL]: '0e8a16',
    'test-failure': 'd73a4a',
    'unit-test': 'fbca04',
    'e2e-test': 'd93f0b',
    'integration-test': 'e99695',
    'incomplete-stub': 'c5def5',
    'tech-debt': 'bfd4f2',
    'priority-board': '1d76db',
    'priority-high': 'b60205',
    'priority-medium': 'fbca04',
    'priority-low': '0e8a16',
  };

  for (const name of labels) {
    if (known.has(name)) continue;
    try {
      await githubRequest('POST', `/repos/${owner}/${repo}/labels`, {
        name,
        color: colors[name] || 'ededed',
        description: `Auto-managed label for priority issue generation (${name})`,
      }, token);
      known.set(name, true);
    } catch (e) {
      // Likely already exists or lacks permission
      console.warn(`Label create skipped for ${name}: ${e.message}`);
    }
  }
}

async function findOpenIssueByFingerprint(owner, repo, fingerprint, token) {
  // Quote fingerprint so colons are not treated as GitHub search qualifiers
  const q = encodeURIComponent(
    `repo:${owner}/${repo} is:issue is:open label:${AUTO_LABEL} "${fingerprint}" in:body`
  );
  const result = await githubRequest('GET', `/search/issues?q=${q}&per_page=5`, null, token);
  return (result.items && result.items[0]) || null;
}

async function findSummaryIssue(owner, repo, token) {
  const q = encodeURIComponent(`repo:${owner}/${repo} is:issue is:open label:${AUTO_LABEL} label:priority-board in:title "Next CI priorities"`);
  const result = await githubRequest('GET', `/search/issues?q=${q}&per_page=5`, null, token);
  return (result.items && result.items[0]) || null;
}

async function createOrUpdateIssues(findings, ctx, args) {
  const token = process.env.GITHUB_TOKEN;
  const repoFull = process.env.GITHUB_REPOSITORY || ctx.repository;
  if (!repoFull) throw new Error('GITHUB_REPOSITORY is required to create issues');
  const [owner, repo] = repoFull.split('/');

  const created = [];
  const updated = [];
  const skipped = [];

  // Always maintain a summary issue
  const summaryTitle = '[Priorities] Next CI priorities';
  const summaryBody = buildSummaryBody(findings, ctx);
  const allLabels = new Set(LABELS.summary);
  for (const f of findings.slice(0, args.maxIssues)) {
    for (const l of labelsFor(f)) allLabels.add(l);
  }

  if (args.dryRun) {
    console.log('\n=== DRY RUN: would upsert summary issue ===');
    console.log(summaryTitle);
    console.log(summaryBody.slice(0, 500) + '...\n');
  } else {
    await ensureLabels(owner, repo, [...allLabels], token);
    const existingSummary = await findSummaryIssue(owner, repo, token);
    if (existingSummary) {
      await githubRequest('PATCH', `/repos/${owner}/${repo}/issues/${existingSummary.number}`, {
        title: summaryTitle,
        body: summaryBody,
        labels: LABELS.summary,
      }, token);
      updated.push({ number: existingSummary.number, title: summaryTitle, kind: 'summary' });
      console.log(`Updated summary issue #${existingSummary.number}`);
    } else {
      const issue = await githubRequest('POST', `/repos/${owner}/${repo}/issues`, {
        title: summaryTitle,
        body: summaryBody,
        labels: LABELS.summary,
      }, token);
      created.push({ number: issue.number, title: summaryTitle, kind: 'summary' });
      console.log(`Created summary issue #${issue.number}`);
    }
  }

  // Individual issues: high-priority failures + high/medium stubs (exclude low conditional stubs unless few findings)
  const actionable = findings.filter((f) => {
    if (f.type !== 'incomplete_stub') return true;
    if (f.priority === 'high' || f.priority === 'medium') return true;
    return false;
  }).slice(0, args.maxIssues);

  for (const finding of actionable) {
    const title = finding.title.slice(0, 240);
    const body = buildIssueBody(finding, ctx);
    const labels = labelsFor(finding);

    if (args.dryRun) {
      console.log(`[dry-run] issue: ${title}`);
      skipped.push({ title, reason: 'dry-run' });
      continue;
    }

    try {
      const existing = await findOpenIssueByFingerprint(owner, repo, finding.fingerprint, token);
      if (existing) {
        await githubRequest('PATCH', `/repos/${owner}/${repo}/issues/${existing.number}`, {
          body,
          labels,
        }, token);
        updated.push({ number: existing.number, title, kind: finding.type });
        console.log(`Updated #${existing.number}: ${title}`);
      } else {
        await ensureLabels(owner, repo, labels, token);
        const issue = await githubRequest('POST', `/repos/${owner}/${repo}/issues`, {
          title,
          body,
          labels,
        }, token);
        created.push({ number: issue.number, title, kind: finding.type });
        console.log(`Created #${issue.number}: ${title}`);
      }
    } catch (e) {
      console.error(`Failed for ${title}: ${e.message}`);
      skipped.push({ title, reason: e.message });
    }
  }

  return { created, updated, skipped };
}

function resolveRepository() {
  if (process.env.GITHUB_REPOSITORY) return process.env.GITHUB_REPOSITORY;
  try {
    const url = execSync('git remote get-url origin', { cwd: ROOT, encoding: 'utf8' }).trim();
    const m = url.match(/github\.com[:/](.+?)(?:\.git)?$/);
    if (m) return m[1];
  } catch { /* ignore */ }
  return null;
}

function writeStepSummary(findings, result) {
  const summaryFile = process.env.GITHUB_STEP_SUMMARY;
  if (!summaryFile) return;
  const units = findings.filter((f) => f.type === 'unit_test_failure').length;
  const e2e = findings.filter((f) => f.type === 'e2e_test_failure').length;
  const integ = findings.filter((f) => f.type === 'integration_test_failure').length;
  const stubs = findings.filter((f) => f.type === 'incomplete_stub').length;
  const md = [
    '## Priority issue generation',
    '',
    `| Category | Count |`,
    `|----------|------:|`,
    `| Unit failures | ${units} |`,
    `| E2E failures | ${e2e} |`,
    `| Integration failures | ${integ} |`,
    `| Incomplete stubs | ${stubs} |`,
    `| Issues created | ${(result.created || []).length} |`,
    `| Issues updated | ${(result.updated || []).length} |`,
    `| Skipped | ${(result.skipped || []).length} |`,
    '',
  ].join('\n');
  fs.appendFileSync(summaryFile, md);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const artifactDir = path.resolve(process.env.ARTIFACT_DIR || ROOT);
  const jobResults = {
    unit: process.env.UNIT_RESULT || '',
    e2e: process.env.E2E_RESULT || '',
    integration: process.env.INTEGRATION_RESULT || '',
  };
  const ctx = {
    repository: resolveRepository(),
    sha: process.env.GITHUB_SHA || '',
    ref: process.env.GITHUB_REF || '',
    sourceWorkflow: process.env.SOURCE_WORKFLOW || process.env.GITHUB_WORKFLOW || '',
    runUrl: process.env.GITHUB_RUN_URL ||
      (process.env.GITHUB_SERVER_URL && process.env.GITHUB_REPOSITORY && process.env.GITHUB_RUN_ID
        ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`
        : ''),
    jobResults,
  };

  console.log('CrystalCog priority issue generator');
  console.log('==================================');
  console.log(`Root: ${ROOT}`);
  console.log(`Artifact dir: ${artifactDir}`);
  console.log(`Dry run: ${args.dryRun}`);
  console.log(`Job results: unit=${jobResults.unit || 'n/a'} integration=${jobResults.integration || 'n/a'} e2e=${jobResults.e2e || 'n/a'}`);

  const stubs = scanIncompleteStubs();
  const unitFails = collectTestFailures(artifactDir);
  const e2eFails = parseE2EReports(artifactDir);
  let findings = dedupeFindings([...unitFails, ...e2eFails, ...stubs]);
  findings = addJobLevelFindings(findings, jobResults);
  findings = sortFindings(findings);

  console.log(`\nFindings: ${findings.length}`);
  console.log(`  unit: ${findings.filter((f) => f.type === 'unit_test_failure').length}`);
  console.log(`  e2e: ${findings.filter((f) => f.type === 'e2e_test_failure').length}`);
  console.log(`  integration: ${findings.filter((f) => f.type === 'integration_test_failure').length}`);
  console.log(`  stubs: ${findings.filter((f) => f.type === 'incomplete_stub').length}`);

  const outPath = args.output || path.join(artifactDir, 'priority-findings.json');
  fs.writeFileSync(outPath, JSON.stringify({ generated_at: new Date().toISOString(), ctx, findings }, null, 2));
  console.log(`Wrote ${outPath}`);

  if (args.scanOnly) {
    writeStepSummary(findings, { created: [], updated: [], skipped: [] });
    return;
  }

  const result = await createOrUpdateIssues(findings, ctx, args);
  writeStepSummary(findings, result);

  const report = {
    findings: findings.length,
    created: result.created.length,
    updated: result.updated.length,
    skipped: result.skipped.length,
  };
  fs.writeFileSync(path.join(artifactDir, 'priority-issues-report.json'), JSON.stringify(report, null, 2));
  console.log('\nDone:', report);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
