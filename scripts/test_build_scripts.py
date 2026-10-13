import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).resolve().with_name('write_ci_config.py')
class BuildConfigTests(unittest.TestCase):
    def run_config(self, **values):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'scripts').mkdir()
            (root / 'Config').mkdir()
            script = root / 'scripts/write_ci_config.py'
            shutil.copyfile(SOURCE, script)
            env = {k: v for k, v in os.environ.items() if not k.startswith('ANIVIBE_')}
            env.update(values)
            result = subprocess.run([sys.executable, str(script)], env=env, capture_output=True, text=True)
            file = root / 'Config/Secrets.xcconfig'
            return result, file.read_text() if file.exists() else None
    def test_empty_environment_preserves_defaults(self):
        result, contents = self.run_config()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(contents, '\n')
    def test_url_escaping_and_no_key_logging(self):
        key = 'sb_publishable_example'
        result, contents = self.run_config(ANIVIBE_SUPABASE_URL='https://example.supabase.co', ANIVIBE_SUPABASE_ANON_KEY=key)
        self.assertEqual(result.returncode, 0)
        self.assertIn('https:/$()/example.supabase.co', contents)
        self.assertIn(key, contents)
        self.assertNotIn(key, result.stdout + result.stderr)
    def test_rejects_rest_endpoint(self):
        result, contents = self.run_config(ANIVIBE_SUPABASE_URL='https://example.supabase.co/rest/v1/')
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(contents)
    def test_rejects_http(self):
        result, _ = self.run_config(ANIVIBE_SUPABASE_URL='http://example.supabase.co')
        self.assertNotEqual(result.returncode, 0)
    def test_rejects_newline(self):
        result, _ = self.run_config(ANIVIBE_SUPABASE_ANON_KEY='example\ninjected = setting')
        self.assertNotEqual(result.returncode, 0)
    def test_rejects_secret_key(self):
        result, _ = self.run_config(ANIVIBE_SUPABASE_ANON_KEY='sb_secret_example')
        self.assertNotEqual(result.returncode, 0)
    def test_rejects_service_role(self):
        payload = base64.urlsafe_b64encode(json.dumps({'role': 'service_role'}).encode()).decode().rstrip('=')
        result, _ = self.run_config(ANIVIBE_SUPABASE_ANON_KEY='header.' + payload + '.signature')
        self.assertNotEqual(result.returncode, 0)
    def test_accepts_legacy_anon(self):
        payload = base64.urlsafe_b64encode(json.dumps({'role': 'anon'}).encode()).decode().rstrip('=')
        result, contents = self.run_config(ANIVIBE_SUPABASE_ANON_KEY='header.' + payload + '.signature')
        self.assertEqual(result.returncode, 0)
        self.assertIn('ANIVIBE_SUPABASE_ANON_KEY', contents)
if __name__ == '__main__':
    unittest.main()
