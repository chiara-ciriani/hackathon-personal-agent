"""Run the Swift/Python/MCP loop with synthetic data on an isolated local server."""
import os
import sys
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.request
from cryptography.fernet import Fernet

os.chdir(Path(__file__).resolve().parents[1])

with tempfile.TemporaryDirectory(prefix='qc-roundtrip-') as folder:
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    env = {**os.environ, 'QC_API_TOKEN': 'synthetic-integration-token',
           'QC_DB_PATH': str(Path(folder) / 'test.db'), 'QC_ENCRYPTION_KEY': Fernet.generate_key().decode()}
    env.pop('QC_ACTIVE_SESSION_ID', None)
    with open(str(Path(folder) / 'server.log'), 'w') as log:
        server = subprocess.Popen([sys.executable, '-m', 'uvicorn',
            'quiet_compass.app:create_app', '--factory', '--host', '127.0.0.1', '--port', str(port), '--no-access-log'],
            env=env, stdout=log, stderr=log)
        try:
            for _ in range(50):
                try:
                    urllib.request.urlopen(f'http://127.0.0.1:{port}/healthz', timeout=1).close()
                    break
                except OSError:
                    time.sleep(.1)
            else:
                raise RuntimeError('Local test server failed to start')
            result = subprocess.run(['swift', 'test', '--package-path', 'ios/Packages/QuietCore',
                '--scratch-path', 'ios/Packages/QuietCore/.build', '--filter', 'LiveServerTests'],
                env={**os.environ, 'QC_TEST_SERVER_URL': f'http://127.0.0.1:{port}'})
        finally:
            server.terminate()
            server.wait(timeout=10)
    raise SystemExit(result.returncode)
