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
check(len(list((ROOT / 'supabase/migrations').glob('*.sql'))) >= 4, 'Expected library and profile/friend migrations')

# --- Виджет: генератор, встраивание, App Group и deep link ---
for relative in ['AnivibeWidget/AnivibeWidgetBundle.swift', 'AnivibeWidget/ContinueWatchingWidget.swift',
                 'AnivibeWidget/ContinueWatchingProvider.swift', 'AnivibeWidget/WidgetTheme.swift',
                 'Config/AnivibeWidget-Info.plist', 'Config/AnivibeWidget.entitlements',
                 'Config/Anivibe.entitlements']:
    check((ROOT / relative).is_file(), 'Missing widget file: ' + relative)

with (ROOT / 'Config/AnivibeWidget-Info.plist').open('rb') as stream:
    widget_info = plistlib.load(stream)
check(widget_info.get('NSExtension', {}).get('NSExtensionPointIdentifier') == 'com.apple.widgetkit-extension',
      'Widget extension point must be com.apple.widgetkit-extension')

# Схема anivibe://anime/<id> из виджета обязана открываться приложением.
core_snapshot = (ROOT / 'Packages/AnivibeCore/Sources/AnivibeCore/Models/WidgetSnapshot.swift').read_text()
check('anivibe://anime/' in core_snapshot, 'WidgetSnapshot must build the anivibe://anime/<id> deep link')
app_delegate = (ROOT / 'Anivibe/App/AnivibeApp.swift').read_text()
check('onOpenURL' in app_delegate, 'App must handle deep links via onOpenURL')
router = (ROOT / 'Anivibe/Core/DeepLinkRouter.swift').read_text()
check('WidgetSnapshot.animeID(from: url)' in router, 'DeepLinkRouter must reuse WidgetSnapshot URL parsing')

# App Group должен совпадать в модели, обоих entitlements и xcconfig.
groups = set()
for relative in ['Config/Anivibe.entitlements', 'Config/AnivibeWidget.entitlements']:
    with (ROOT / relative).open('rb') as stream:
        groups.update(plistlib.load(stream).get('com.apple.security.application-groups', []))
config_text = (ROOT / 'Config/Anivibe.xcconfig').read_text()
for group in groups:
    check(f'ANIVIBE_APP_GROUP = {group}' in config_text, 'App Group not declared in Anivibe.xcconfig: ' + group)
    check(f'"{group}"' in core_snapshot, 'WidgetSnapshot appGroupIdentifier mismatch: ' + group)
check(len(groups) == 1, 'App and widget must share exactly one App Group')

# Сгенерированный проект обязан содержать и встраивать расширение.
pbxproj = (ROOT / 'Anivibe.xcodeproj/project.pbxproj').read_text()
check('AnivibeWidgetExtension.appex in Embed App Extensions' in pbxproj, 'Widget extension not embedded into the app')
check('com.apple.product-type.app-extension' in pbxproj, 'Widget target must be an app extension')
config_file = (ROOT / 'Config/Anivibe.xcconfig').read_text()
check('ANIVIBE_WIDGET_BUNDLE_ID = ' in config_file, 'Widget bundle id variable must be defined in Anivibe.xcconfig')
widget_bundle = config_file.split('ANIVIBE_WIDGET_BUNDLE_ID = ', 1)[1].splitlines()[0].strip()
app_bundle = config_file.split('\nPRODUCT_BUNDLE_IDENTIFIER = ', 1)[1].splitlines()[0].strip()
check(widget_bundle.startswith(app_bundle + '.'), 'Widget bundle id must extend the app bundle id')

print('Static project checks passed. Swift compilation and device checks are separate.')
