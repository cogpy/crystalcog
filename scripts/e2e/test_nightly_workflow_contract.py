#!/usr/bin/env python3
"""Local workflow contract regression; requires the already available PyYAML."""
from pathlib import Path
import subprocess
import yaml

root = Path(__file__).resolve().parents[2]
workflow = yaml.safe_load((root / '.github/workflows/nightly-e2e.yml').read_text())
jobs = workflow['jobs']
for job, step_name, command, artifact in (
    ('atomspace-e2e', 'Run AtomSpace persistence tests',
     'bash scripts/e2e/run_logged.sh atomspace-persistence.log 300 \\\n  crystal run --error-trace scripts/e2e/atomspace_persistence_test.cr',
     'atomspace-e2e-results'),
    ('websocket-e2e', 'Run WebSocket monitoring test',
     'bash scripts/e2e/run_logged.sh websocket-monitoring.log 180 \\\n  crystal run --error-trace examples/tests/test_websocket_monitoring.cr',
     'websocket-e2e-results'),
    ('distributed-e2e', 'Run distributed cache tests',
     'bash scripts/e2e/run_logged.sh distributed-test-results.txt 600 \\\n  crystal run --release benchmarks/distributed_storage_benchmark.cr',
     'distributed-e2e-results'),
    ('cogserver-e2e', 'Build CogServer',
     'bash scripts/e2e/run_logged.sh cogserver-build.log 600 \\\n  crystal build --verbose --stats --error-trace src/bin/cogserver.cr -o cogserver_bin',
     'cogserver-e2e-results'),
):
    steps = jobs[job]['steps']
    step = next(s for s in steps if s.get('name') == step_name)
    assert step['run'].strip() == command, f'{job}: strict logged runner drift'
    upload = next(s for s in steps if s.get('with', {}).get('name') == artifact)
    assert upload['if'] == 'always()'
    assert '*.log' in upload['with']['path'].splitlines()
    print(f'PASS {job}: strict required step and always-uploaded log contract')

summary = next(s for s in jobs['e2e-summary']['steps'] if s.get('name') == 'Check for failures')['run']
names = ['atomspace-e2e', 'cogserver-e2e', 'distributed-e2e', 'performance-e2e', 'websocket-e2e']
cases = [(['success'] * 5, 0), (['skipped'] * 5, 0)]
for outcome in ('failure', 'cancelled'):
    for i in range(5):
        results = ['success'] * 5
        results[i] = outcome
        cases.append((results, 1))
for results, expected in cases:
    script = summary
    for name, result in zip(names, results):
        script = script.replace('${{ needs.' + name + '.result }}', result)
    result = subprocess.run(['bash', '-e', '-c', script], capture_output=True, text=True, timeout=5)
    assert result.returncode == expected, (results, result.stdout, result.stderr)
    print(f'PASS summary {" ".join(results)}: exit {expected}')
print('Nightly workflow contract checks passed')
