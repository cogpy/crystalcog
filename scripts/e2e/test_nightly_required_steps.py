#!/usr/bin/env python3
"""Required Nightly gates; local HTTP fixtures and stub compiler, no installs/dispatch.

Stub compiler checks shell result/diagnostic propagation, not Crystal correctness.
Actual compiler/runtime/timeout checks live in test_nightly_result_integrity.sh.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import yaml

ROOT = Path(__file__).resolve().parents[2]


def serve(mode, pid_file):
    Path(pid_file).write_text(str(os.getpid()))
    names = set()
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def send(self, code, value):
            body = value if isinstance(value, bytes) else json.dumps(value).encode()
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == '/ping':
                self.send(503 if mode == 'not-ready' else 200, {'status': 'ok'})
            else:
                if mode == 'summary-http':
                    self.send(500, {'error': 'deliberate summary rejection'})
                elif mode == 'summary-malformed':
                    self.send(200, b'not json')
                elif mode == 'summary-no-body':
                    self.send(200, b'')
                elif mode == 'summary-multiple':
                    value = json.dumps({'running': True, 'atomspace': {'nodes': 3}})
                    self.send(200, (value + '\n' + value).encode())
                else:
                    with lock:
                        count = len(names)
                    self.send(200, {'running': mode != 'summary-inactive',
                                    'atomspace': {'nodes': 0 if mode == 'summary-empty' else count}})

        def do_POST(self):
            data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            name = data['name']
            if mode in ('http-400', 'http-500'):
                self.send(int(mode.split('-')[1]), {'error': 'deliberate rejection'})
            elif mode == 'atom-malformed':
                self.send(201, b'not json')
            elif mode == 'atom-no-body':
                self.send(201, b'')
            elif mode == 'atom-multiple':
                value = json.dumps({'success': True, 'atom': {'name': name, 'handle': 1}})
                self.send(201, (value + '\n' + value).encode())
            else:
                with lock:
                    names.add(name)
                self.send(201, {'success': mode != 'atom-unsuccessful', 'atom': {
                    'name': 'wrong' if mode == 'atom-wrong-name' else name,
                    'handle': 0 if mode == 'atom-invalid-handle' else 1}})

        def log_message(self, *args):
            pass

    ThreadingHTTPServer(('127.0.0.1', 18080), Handler).serve_forever()


def run(command, cwd, env, seconds=15):
    process = subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, start_new_session=True)
    try:
        output, _ = process.communicate(timeout=seconds)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        raise AssertionError('Required gate timed out:\n' + output)
    return process.returncode, output


def test_required_workflow_commands(work):
    workflow = yaml.safe_load((ROOT / '.github/workflows/nightly-e2e.yml').read_text())
    (work / 'scripts/e2e').mkdir(parents=True)
    (work / 'scripts/e2e/run_logged.sh').symlink_to(ROOT / 'scripts/e2e/run_logged.sh')
    bin_dir = work / 'bin'
    bin_dir.mkdir()
    compiler = bin_dir / 'crystal'
    compiler.write_text('#!/usr/bin/env bash\necho "compiler stdout marker"\n'
                        'echo "compiler stderr marker" >&2\nexit "$TEST_COMPILER_STATUS"\n')
    compiler.chmod(0o700)
    env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'])
    for job, name, artifact in (
        ('distributed-e2e', 'Run distributed cache tests', 'distributed-test-results.txt'),
        ('cogserver-e2e', 'Build CogServer', 'cogserver-build.log'),
    ):
        script = next(s['run'] for s in workflow['jobs'][job]['steps'] if s.get('name') == name)
        for expected in (0, 1, 42):
            env['TEST_COMPILER_STATUS'] = str(expected)
            status, output = run(['bash', '-ex', '-c', script], work, env)
            assert status == expected, (name, expected, status, output)
            log = (work / artifact).read_text()
            for marker in ('compiler stdout marker', 'compiler stderr marker',
                           f'Command exit status: {expected}'):
                assert marker in output and marker in log, (name, marker, output, log)
            print(f'PASS {name}: original exit {expected}, both streams in console/artifact')


def test_cogserver(work):
    # Never connect to or kill an unrelated listener: fail before starting fixtures.
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 18080))
    harness = ROOT / 'scripts/e2e/cogserver_load_test.sh'
    wrapper = work / 'server'
    pid_file = work / 'server.pid'
    wrapper.write_text('#!/usr/bin/env bash\nexec python3 "$TEST_FIXTURE_SCRIPT" '
                       '--serve "$TEST_MODE" "$TEST_PID_FILE"\n')
    wrapper.chmod(0o700)
    env = dict(os.environ, TEST_FIXTURE_SCRIPT=str(Path(__file__).resolve()),
               TEST_PID_FILE=str(pid_file), COGSERVER_LOAD_REQUESTS='3',
               COGSERVER_READY_TIMEOUT='2')
    cases = [('success', 0), ('http-400', 1), ('http-500', 1), ('atom-malformed', 1),
             ('atom-unsuccessful', 1), ('atom-wrong-name', 1), ('atom-invalid-handle', 1),
             ('atom-no-body', 1), ('atom-multiple', 1),
             ('summary-http', 1), ('summary-malformed', 1), ('summary-inactive', 1),
             ('summary-no-body', 1), ('summary-multiple', 1),
             ('summary-empty', 1), ('not-ready', 1)]
    for mode, expected in cases:
        env['TEST_MODE'] = mode
        pid_file.unlink(missing_ok=True)
        status, output = run(['bash', str(harness), str(wrapper)], ROOT, env)
        assert status == expected, (mode, status, output)
        assert ('CogServer load test completed' in output) == (expected == 0), (mode, output)
        assert pid_file.exists(), (mode, output)
        pid = int(pid_file.read_text())
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            pass
        else:
            raise AssertionError(f'{mode}: owned server {pid} survived cleanup')
        print(f'PASS CogServer {mode}: exit {expected}, owned server reaped')
    nonexecutable = work / 'nonexecutable'
    nonexecutable.write_text('not a server\n')
    for args in ([], [str(work / 'missing')], [str(nonexecutable)]):
        status, output = run(['bash', str(harness), *args], ROOT, env)
        assert status == 1 and 'Required CogServer binary' in output, (args, status, output)
        print(f'PASS required binary {args}: nonzero, no successful skip')
    for name, value in (('COGSERVER_LOAD_REQUESTS', '0'), ('COGSERVER_LOAD_REQUESTS', 'bad'),
                        ('COGSERVER_READY_TIMEOUT', '0')):
        status, output = run(['bash', str(harness), str(wrapper)], ROOT, dict(env, **{name: value}))
        assert status == 2, (name, value, status, output)
        print(f'PASS invalid {name}={value}: exit 2')


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--serve':
        serve(sys.argv[2], sys.argv[3])
    else:
        with tempfile.TemporaryDirectory(prefix='nightly-required-') as directory:
            work = Path(directory)
            test_required_workflow_commands(work)
            test_cogserver(work)
        print('Required Nightly gate regressions passed')
