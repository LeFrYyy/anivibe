#!/usr/bin/env python3
"""Write GitHub Actions overrides without logging configuration values."""
import os
import base64
import json
from pathlib import Path
from urllib.parse import urlsplit

root = Path(__file__).resolve().parents[1]
keys = ['ANIVIBE_SUPABASE_URL', 'ANIVIBE_SUPABASE_ANON_KEY', 'ANIVIBE_KODIK_TOKEN', 'ANIVIBE_MANIFEST_URL']
lines = []
for key in keys:
    value = os.environ.get(key, '').strip()
    if not value:
        continue
    if any(char in value for char in ['\n', '\r', '\x00']):
        raise SystemExit('Invalid multiline configuration: ' + key)
    if key.endswith('_URL'):
        parsed = urlsplit(value)
        if parsed.scheme != 'https' or not parsed.hostname:
            raise SystemExit('Expected an HTTPS URL: ' + key)
        if key == 'ANIVIBE_SUPABASE_URL' and (parsed.path not in ('', '/') or parsed.query or parsed.fragment):
            raise SystemExit('Supabase URL must be the project base URL, without /rest/v1 or other paths')
    if key == 'ANIVIBE_SUPABASE_ANON_KEY' and value.startswith('sb_secret_'):
        raise SystemExit('Refusing a server secret in client configuration')
    if key == 'ANIVIBE_SUPABASE_ANON_KEY' and value.count('.') == 2:
        payload = value.split('.')[1]
        try:
            role = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4))).get('role')
        except (ValueError, TypeError, AttributeError):
            role = None
        if role == 'service_role':
            raise SystemExit('Refusing a service_role key in client configuration')
    lines.append(key + ' = ' + value.replace('//', '/$()/'))
(root / 'Config/Secrets.xcconfig').write_text('\n'.join(lines) + '\n')
print('CI overrides prepared; project defaults apply to unset values. Values not logged.')
