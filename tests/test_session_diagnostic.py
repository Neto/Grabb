"""Exercise the bundled yt-dlp with synthetic cookies only, never browser cookies."""
from pathlib import Path
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / 'Vendor/Helpers/yt-dlp.bundle/yt-dlp'
PLUGINS = ROOT / 'Grabb/Resources/Diagnostics'


def check(rows, expected):
    with tempfile.TemporaryDirectory() as folder:
        cookies = Path(folder) / 'synthetic-cookies.txt'
        cookies.write_text('# Netscape HTTP Cookie File\n' + '\n'.join(rows) + '\n')
        result = subprocess.run([
            str(BINARY), '--ignore-config', '--no-update', '--no-colors',
            '--no-plugin-dirs', '--plugin-dirs', str(PLUGINS),
            '--use-extractors', 'grabb:session', '--simulate',
            '--proxy', 'http://127.0.0.1:1', '--socket-timeout', '1',
            '--cookies', str(cookies), 'grabb:instagram-session',
        ], capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        assert result.returncode == 0, output
        assert 'SYNTHETIC_SECRET' not in output, output
        assert 'offline=complete' in output, output
        for fragment in expected:
            assert fragment in output, output


def row(domain, expires, name='sessionid'):
    return f'{domain}\tTRUE\t/\tTRUE\t{expires}\t{name}\tSYNTHETIC_SECRET'


check([], ['present=no count=0'])
check([row('.instagram.com', int(time.time()) + 86400)],
      ['present=yes count=1', 'domain=.instagram.com', 'expired=no', 'has_value=yes'])
check([row('.instagram.com', int(time.time()) - 86400)],
      ['present=yes count=1', 'expired=yes'])
check([row('.instagram.com', 0)], ['expires=session', 'expired=no'])
check([row('.instagram.com', 13454000000000000)],
      ['present=yes count=1', 'expires=out-of-range(raw=13454000000000000)', 'expired=unknown'])
check([row('.evilinstagram.com', 0), row('.instagram.com', 0, 'csrftoken')],
      ['present=no count=0'])
print('Session diagnostics: absent, present, expired, session-only, domain filtering and secret omission passed')
