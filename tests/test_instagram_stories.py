"""Run Stories extraction against mocked responses inside the bundled Python runtime."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
for case in ('api', 'graphql', 'relay', 'photo', 'profile-bound', 'missing', 'highlight', 'legacy-user', 'missing-token', 'rate-limit'):
    result = subprocess.run([
        str(root / 'Vendor/Helpers/yt-dlp.bundle/yt-dlp'),
        '--ignore-config', '--no-update', '--no-colors', '--simulate', '--no-playlist',
        '--no-plugin-dirs', '--plugin-dirs', str(root / 'Grabb/Resources/Diagnostics'),
        '--plugin-dirs', str(root / 'tests/fixtures'),
        '--use-extractors', 'grabb:story-fixture',
        '--proxy', 'http://127.0.0.1:1', '--socket-timeout', '1',
        'grabb-fixture:' + case,
    ], capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and f'PASS fixture={case}' in output, output
    assert 'FIXTURE_SECRET' not in output, output
    print('PASS', case)
