#!/usr/bin/env python3
"""Test Nightly bootstrap ordering and result contract without sudo/apt/network.

A local sudo shim verifies the exact bounded apt invocation and returns controlled
statuses. This tests wiring/observability, not apt mirrors or real package refresh.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import yaml

ROOT = Path(__file__).resolve().parents[2]
JOBS = ('atomspace-e2e', 'cogserver-e2e', 'distributed-e2e', 'performance-e2e', 'websocket-e2e')
COMMAND = ('bash scripts/e2e/run_logged.sh apt-index-refresh.log 200 \\\n'
           '  sudo timeout --kill-after=5s 180s apt-get -o Acquire::Retries=2 -o APT::Update::Error-Mode=any update')


def main():
    workflow = yaml.safe_load((ROOT / '.github/workflows/nightly-e2e.yml').read_text())
    commands = []
    for name in JOBS:
        steps = workflow['jobs'][name]['steps']
        names = [step.get('name') for step in steps]
        assert names.count('Refresh apt package indexes') == 1, name
        refresh = names.index('Refresh apt package indexes')
        installer = names.index('Install Crystal')
        assert names.index('Checkout repository') < refresh < installer, name
        step = steps[refresh]
        assert not step.get('continue-on-error', False) and 'if' not in step, name
        assert step['run'].strip() == COMMAND, (name, step['run'])
        upload = next(s for s in steps if s.get('uses', '').startswith('actions/upload-artifact@'))
        assert upload['if'] == 'always()' and '*.log' in upload['with']['path'].splitlines(), name
        commands.append((name, step['run']))
        print(f'PASS {name}: one bounded strict refresh before installer, always-uploaded log')

    with tempfile.TemporaryDirectory(prefix='nightly-bootstrap-') as directory:
        work = Path(directory)
        (work / 'scripts/e2e').mkdir(parents=True)
        (work / 'scripts/e2e/run_logged.sh').symlink_to(ROOT / 'scripts/e2e/run_logged.sh')
        bin_dir = work / 'bin'
        bin_dir.mkdir()
        sudo = bin_dir / 'sudo'
        sudo.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
expected = ['timeout', '--kill-after=5s', '180s', 'apt-get', '-o', 'Acquire::Retries=2', '-o', 'APT::Update::Error-Mode=any', 'update']
if sys.argv[1:] != expected:
    print('Wrong bootstrap invocation: ' + repr(sys.argv[1:]), file=sys.stderr)
    sys.exit(2)
Path(os.environ['APT_CALL_RECORD']).write_text(json.dumps(sys.argv[1:]))
print('apt stdout marker: reading package indexes')
print('apt stderr marker: package/mirror diagnostic', file=sys.stderr)
status = int(os.environ['APT_FIXTURE_STATUS'])
if status == 100:
    print('E: Failed to fetch libevent archive: HTTP 404 fixture', file=sys.stderr)
sys.exit(status)
''')
        sudo.chmod(0o700)
        record = work / 'apt-call.json'
        env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'],
                   APT_CALL_RECORD=str(record))
        for name, command in commands:
            for expected in (0, 100, 42, 124):
                record.unlink(missing_ok=True)
                env['APT_FIXTURE_STATUS'] = str(expected)
                result = subprocess.run(['bash', '-ex', '-c', command], cwd=work, env=env,
                                        capture_output=True, text=True, timeout=10)
                output = result.stdout + result.stderr
                assert result.returncode == expected, (name, expected, result.returncode, output)
                assert record.exists(), (name, 'bootstrap command was skipped')
                log = (work / 'apt-index-refresh.log').read_text()
                for marker in ('apt stdout marker', 'apt stderr marker', f'Command exit status: {expected}'):
                    assert marker in output and marker in log, (name, marker, output, log)
                if expected == 100:
                    assert 'HTTP 404 fixture' in output and 'HTTP 404 fixture' in log
                print(f'PASS {name}: bootstrap exit {expected}, both streams and status retained')
    print('Nightly bootstrap contract regressions passed')


if __name__ == '__main__':
    main()
