#!/usr/bin/env python3
"""Static contracts for the Continue Watching widget and its deep link.

Source-level checks only; Swift compilation and on-device widget rendering are
verified by the iOS workflow (see .github/workflows/ios.yml).
"""
import plistlib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


class WidgetSourceTests(unittest.TestCase):
    def test_widget_sources_and_configuration_exist(self):
        for relative in (
            "AnivibeWidget/AnivibeWidgetBundle.swift",
            "AnivibeWidget/ContinueWatchingProvider.swift",
            "AnivibeWidget/ContinueWatchingWidget.swift",
            "AnivibeWidget/WidgetTheme.swift",
            "Config/AnivibeWidget-Info.plist",
            "Config/AnivibeWidget.entitlements",
            "Config/Anivibe.entitlements",
            "Anivibe/Core/WidgetBridge.swift",
            "Packages/AnivibeCore/Sources/AnivibeCore/Models/WidgetSnapshot.swift",
        ):
            self.assertTrue((ROOT / relative).is_file(), "Missing: " + relative)

    def test_bundle_declares_continue_watching_widget_and_provider(self):
        bundle = source("AnivibeWidget/AnivibeWidgetBundle.swift")
        self.assertIn("@main", bundle)
        self.assertIn("WidgetBundle", bundle)
        self.assertIn("ContinueWatchingWidget()", bundle)

        widget = source("AnivibeWidget/ContinueWatchingWidget.swift")
        self.assertIn("struct ContinueWatchingWidget", widget)
        self.assertIn("StaticConfiguration(kind:", widget)
        self.assertIn("ContinueWatchingProvider()", widget)
        for family in ("systemSmall", "systemMedium", "systemLarge"):
            self.assertIn(family, widget, "Missing widget family: " + family)

    def test_timeline_provider_refreshes_and_never_blocks_forever(self):
        provider = source("AnivibeWidget/ContinueWatchingProvider.swift")
        self.assertIn("TimelineProvider", provider)
        self.assertIn("WidgetSnapshotStore.read()", provider)
        self.assertIn("Timeline(entries:", provider)
        self.assertIn(".after(", provider)
        self.assertIn("func placeholder(in context: Context)", provider)
        self.assertIn("func getSnapshot(in context: Context", provider)
        self.assertIn("func getTimeline(in context: Context", provider)

    def test_widget_renders_progress_and_opens_anivibe_scheme(self):
        widget = source("AnivibeWidget/ContinueWatchingWidget.swift")
        # Виджет не должен ходить в сеть сам: только локальный снимок из App Group.
        self.assertNotIn("URLSession", widget)
        self.assertNotIn("AniListCatalogService", widget)
        # Каждый элемент открывается deep link'ом на детали тайтла.
        self.assertIn("Link(destination:", widget)
        self.assertIn("WidgetSnapshot.deepLink(for:", widget)

    def test_app_publishes_snapshot_after_library_refresh(self):
        store = source("Anivibe/Core/LibraryStore.swift")
        self.assertIn("WidgetBridge.publish(", store)
        bridge = source("Anivibe/Core/WidgetBridge.swift")
        self.assertIn("WidgetSnapshotStore.write(", bridge)
        self.assertIn("WidgetCenter.shared.reloadAllTimelines()", bridge)

    def test_snapshot_store_uses_shared_app_group_and_stays_offline(self):
        snapshot = source("Packages/AnivibeCore/Sources/AnivibeCore/Models/WidgetSnapshot.swift")
        self.assertIn("containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)", snapshot)
        self.assertIn("anivibe://anime/", snapshot)
        self.assertIn("dateEncodingStrategy = .iso8601", snapshot)
        self.assertIn("dateDecodingStrategy = .iso8601", snapshot)
        # Снимок ограничен, чтобы не раздувать файл в App Group.
        self.assertIn("prefix(", snapshot)

    def test_deep_link_route_parses_only_our_scheme(self):
        snapshot = source("Packages/AnivibeCore/Sources/AnivibeCore/Models/WidgetSnapshot.swift")
        router = source("Anivibe/Core/DeepLinkRouter.swift")
        self.assertIn("static func animeID(from url: URL)", snapshot)
        self.assertIn("WidgetSnapshot.animeID(from: url)", router)

    def test_app_group_matches_across_entitlements_and_configuration(self):
        groups = set()
        for relative in ("Config/Anivibe.entitlements", "Config/AnivibeWidget.entitlements"):
            with (ROOT / relative).open("rb") as stream:
                groups.update(plistlib.load(stream).get("com.apple.security.application-groups", []))
        self.assertEqual(len(groups), 1, "App and widget must share exactly one App Group")
        group = groups.pop()
        self.assertIn(f"ANIVIBE_APP_GROUP = {group}", source("Config/Anivibe.xcconfig"))
        self.assertIn(f'"{group}"', source("Packages/AnivibeCore/Sources/AnivibeCore/Models/WidgetSnapshot.swift"))

    def test_widget_extension_is_embedded_by_the_generated_project(self):
        pbxproj = source("Anivibe.xcodeproj/project.pbxproj")
        self.assertIn("AnivibeWidgetExtension", pbxproj)
        self.assertIn("AnivibeWidgetExtension.appex in Embed App Extensions", pbxproj)
        self.assertIn("com.apple.product-type.app-extension", pbxproj)
        with (ROOT / "Config/AnivibeWidget-Info.plist").open("rb") as stream:
            widget_info = plistlib.load(stream)
        self.assertEqual(
            widget_info["NSExtension"]["NSExtensionPointIdentifier"],
            "com.apple.widgetkit-extension",
        )

    def test_widget_bundle_id_extends_the_app_bundle_id(self):
        config = source("Config/Anivibe.xcconfig")
        app_id = config.split("\nPRODUCT_BUNDLE_IDENTIFIER = ", 1)[1].splitlines()[0].strip()
        widget_id = config.split("ANIVIBE_WIDGET_BUNDLE_ID = ", 1)[1].splitlines()[0].strip()
        self.assertTrue(widget_id.startswith(app_id + "."), f"{widget_id} must start with {app_id}.")

    def test_generator_emits_the_widget_target_and_is_idempotent(self):
        generator = source("scripts/generate_xcodeproj.py")
        for marker in ("widgetTarget", "widgetSync", "embedAppExtensions", "widgetCoreProductDep"):
            self.assertIn(marker, generator, "Generator is missing the widget target piece: " + marker)
        self.assertIn("path = AnivibeWidget", generator, "Generator must add the AnivibeWidget synchronized folder")

        # Повторный запуск генератора не должен менять сгенерированный проект:
        # иначе CI увидит вечный diff и проверки станут бесполезны.
        import subprocess
        import sys
        pbxproj = ROOT / "Anivibe.xcodeproj/project.pbxproj"
        before = pbxproj.read_text(encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/generate_xcodeproj.py")],
            cwd=ROOT, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, pbxproj.read_text(encoding="utf-8"), "Generator output is not deterministic")


if __name__ == "__main__":
    unittest.main(verbosity=2)
