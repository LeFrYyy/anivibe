#!/usr/bin/env python3
"""Static project/configuration validation; not a Swift compiler or runtime test."""
import json
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def check(condition, message):
    if not condition:
        raise SystemExit('Project validation failed: ' + message)

required = ['Anivibe.xcodeproj/project.pbxproj', 'Anivibe.xcodeproj/xcshareddata/xcschemes/Anivibe.xcscheme',
            'Config/Info.plist', 'Config/Anivibe.xcconfig', 'Config/Supabase.xcconfig',
            'Packages/AnivibeCore/Package.swift', '.github/workflows/ios.yml']
for relative in required:
    check((ROOT / relative).is_file(), 'Missing file: ' + relative)
with (ROOT / 'Config/Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
check(info['AnivibeSupabaseURL'] == '$(ANIVIBE_SUPABASE_URL)', 'Supabase URL build setting not connected')
check(info['AnivibeSupabaseAnonKey'] == '$(ANIVIBE_SUPABASE_ANON_KEY)', 'API key build setting not connected')
check(any('anivibe' in entry.get('CFBundleURLSchemes', []) for entry in info.get('CFBundleURLTypes', [])), 'Missing native OAuth URL scheme')
for path in ROOT.glob('Anivibe/**/*.json'):
    json.loads(path.read_text())
base = (ROOT / 'Config/Anivibe.xcconfig').read_text()
check(base.index('#include "Supabase.xcconfig"') < base.index('#include? "Secrets.xcconfig"'), 'Incorrect config override order')
settings = (ROOT / 'Anivibe/App/AppSettings.swift').read_text().split('    init(', 1)[1]
check(settings.index('Theme.palette.hex = accentHex') > settings.index('anilibriaEnabled ='), 'Theme read before settings initialized')
background = (ROOT / 'Anivibe/Features/Settings/BackgroundSettings.swift').read_text()
check('catch { if !Task.isCancelled { self.error =' in background, 'Unqualified error assignment in catch')
auth = (ROOT / 'Packages/AnivibeCore/Sources/AnivibeCore/Sync/SupabaseAuthClient.swift').read_text()
check('bearer ?? config.anonKey' not in auth, 'API key must not be used as user Bearer')
check(len(list((ROOT / 'supabase/migrations').glob('*.sql'))) == 3, 'Expected all three migrations')
print('Static project checks passed. Swift compilation and device checks are separate.')
