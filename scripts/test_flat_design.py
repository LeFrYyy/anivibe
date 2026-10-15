#!/usr/bin/env python3
"""Flat-design source and color contracts; NOT a Swift compiler or iOS UI test."""
import json
from pathlib import Path
import re
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


def luminance(hex_value):
    channels = [(hex_value >> shift & 255) / 255 for shift in (16, 8, 0)]
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in channels]
    return sum(a * b for a, b in zip(linear, (0.2126, 0.7152, 0.0722)))


def contrast(a, b):
    lighter, darker = sorted((luminance(a), luminance(b)), reverse=True)
    return (lighter + 0.05) / (darker + 0.05)


class FlatDesignSourceTests(unittest.TestCase):
    def test_no_gradient_api_or_gradient_shape_style_in_app_sources(self):
        pattern = r"\b(?:LinearGradient|RadialGradient|AngularGradient|EllipticalGradient|MeshGradient|Gradient)\s*\(|\.gradient\b"
        for path in (ROOT / "Anivibe").rglob("*.swift"):
            self.assertIsNone(re.search(pattern, path.read_text()), str(path.relative_to(ROOT)))

    def test_no_frosted_material_or_decorative_shadow_in_app_sources(self):
        for path in (ROOT / "Anivibe").rglob("*.swift"):
            body = path.read_text()
            self.assertNotRegex(body, r"\b(?:ultraThinMaterial|thinMaterial|regularMaterial|thickMaterial)\b")
            self.assertNotIn(".shadow(", body, str(path.relative_to(ROOT)))

    def test_folder_card_uses_name_count_and_one_flat_surface(self):
        folders = source("Anivibe/Features/Home/FolderViews.swift")
        tile = folders.split("struct FolderTile:", 1)[1].split("struct FolderBackground:", 1)[0]
        self.assertIn('Image(systemName: "folder")', tile)
        self.assertIn("Text(collection.name)", tile)
        self.assertIn("countLabel(collection.items.count)", tile)
        self.assertIn(".lineLimit(2, reservesSpace: true)", tile)
        self.assertNotIn("0..<9", tile)
        self.assertNotIn("LazyVGrid", tile)
        self.assertNotIn("PosterImage", tile)

    def test_folder_surface_has_border_but_no_glass_glow_or_tinted_overlay(self):
        folders = source("Anivibe/Features/Home/FolderViews.swift")
        background = folders.split("struct FolderBackground:", 1)[1].split("struct NewFolderTile:", 1)[0]
        self.assertIn(".fill(Theme.surface)", background)
        self.assertIn(".strokeBorder(Theme.separator, lineWidth: 1)", background)
        for effect in ("Material", ".blur(", ".shadow(", "Theme.accent", "usesMaterial"):
            self.assertNotIn(effect, background)
        self.assertNotIn("GlassCapsuleStyle", folders)

    def test_folder_panel_uses_system_theme_and_does_not_tilt_or_scale(self):
        folders = source("Anivibe/Features/Home/FolderViews.swift")
        self.assertNotIn(".environment(\\.colorScheme, .dark)", folders)
        self.assertNotIn(".rotationEffect(", folders)
        self.assertNotIn(".scaleEffect(", folders)
        self.assertNotIn("design: .rounded", folders)
        self.assertNotIn(".offset(", folders)

    def test_folder_panel_is_responsive_and_handles_dynamic_type(self):
        folders = source("Anivibe/Features/Home/FolderViews.swift")
        self.assertIn("GeometryReader { geometry in", folders)
        self.assertIn("min(640, geometry.size.width - 32)", folders)
        self.assertIn("geometry.size.height - 32", folders)
        self.assertIn(".adaptive(minimum:", folders)
        self.assertIn("dynamicTypeSize.isAccessibilitySize", folders)
        self.assertIn("ScrollView {", folders)

    def test_folder_has_accessible_close_and_44_point_actions(self):
        folders = source("Anivibe/Features/Home/FolderViews.swift")
        self.assertIn('.accessibilityLabel("Закрыть папку")', folders)
        self.assertIn(".accessibilityAction(.escape, close)", folders)
        self.assertIn(".accessibilityAddTraits(.isModal)", folders)
        self.assertGreaterEqual(folders.count("frame(width: 44, height: 44)"), 3)
        self.assertIn(".frame(minHeight: 44)", folders)
        self.assertIn('.accessibilityLabel("Создать папку")', folders)

    def test_folder_edit_search_reorder_and_account_guards_are_preserved(self):
        folders = source("Anivibe/Features/Home/FolderViews.swift")
        home = source("Anivibe/Features/Home/HomeView.swift")
        for marker in ("env.collections.rename", "env.collections.remove", "env.collections.delete",
                       "env.collections.reorderItem", "AddToFolderSheet(collectionID:",
                       "env.collections.activeAccountID == presentedAccountID"):
            self.assertIn(marker, folders)
        self.assertIn("env.collections.reorder(source, to: target)", home)
        self.assertIn(".onChange(of: env.collections.activeAccountID)", home)
        self.assertIn("path.append(anime)", home)
        self.assertIn(".onDrag {", folders)
        self.assertIn(".onDrop(", folders)

    def test_empty_folder_has_clear_copy_and_add_action(self):
        folders = source("Anivibe/Features/Home/FolderViews.swift")
        self.assertIn("collection.items.isEmpty", folders)
        self.assertIn('Text("В папке пока пусто")', folders)
        self.assertIn('Label("Добавить", systemImage: "plus")', folders)
        self.assertNotIn("dash:", folders)

    def test_player_uses_local_flat_panels_and_narrow_width_fallback(self):
        player = source("Anivibe/Features/Player/PlayerControlsView.swift")
        self.assertEqual(player.count(".background(Color.black.opacity(0.76)"), 5)
        self.assertIn("ViewThatFits(in: .horizontal)", player)
        self.assertIn(".labelStyle(.iconOnly)", player)
        self.assertIn(".fill(Color.white)", player)
        self.assertIn(".frame(minWidth: 44, minHeight: 44)", player)

    def test_details_text_is_below_artwork_not_over_an_unreadable_banner(self):
        details = source("Anivibe/Features/AnimeDetails/AnimeDetailsView.swift")
        header = details.split("private var header:", 1)[1].split("// MARK: Actions", 1)[0]
        self.assertIn("VStack(alignment: .leading", header)
        self.assertIn("if let bannerURL = anime.bannerURL", header)
        self.assertIn(".background(Theme.surface)", header)
        self.assertNotIn(".offset(", header)
        self.assertNotIn("ZStack(", header)

    def test_default_palette_text_and_action_contrast_meets_aa(self):
        theme = source("Anivibe/DesignSystem/Theme.swift")
        values = {name: (int(light, 16), int(dark, 16)) for name, light, dark in re.findall(
            r"static let (\w+) = Color\(light: 0x([A-Fa-f0-9]+), dark: 0x([A-Fa-f0-9]+)\)", theme)}
        accent_block = theme.split("static var accent:", 1)[1].split("static var onAccent:", 1)[0]
        light, dark = re.search(r"return Color\(light: 0x([A-Fa-f0-9]+), dark: 0x([A-Fa-f0-9]+)\)", accent_block).groups()
        accents = (int(light, 16), int(dark, 16))
        for mode in (0, 1):
            for background in ("background", "surface", "surfaceElevated"):
                for foreground in ("textPrimary", "textSecondary", "success", "danger"):
                    self.assertGreaterEqual(contrast(values[foreground][mode], values[background][mode]), 4.5,
                                            (mode, foreground, background))
            self.assertGreaterEqual(contrast((0xFFFFFF, 0x000000)[mode], accents[mode]), 4.5)
            self.assertGreaterEqual(contrast(accents[mode], values["surface"][mode]), 4.5)
        self.assertIn("static var secondaryAccent: Color { accent }", theme)
        self.assertIn("if let hex = palette.hex", theme)

    def test_native_assets_and_settings_share_the_flat_palette(self):
        colors = json.loads(source("Anivibe/Resources/Assets.xcassets/AccentColor.colorset/Contents.json"))
        for row, expected in zip(colors["colors"], (("0x27", "0x5D", "0x8C"), ("0x9C", "0xBA", "0xDD"))):
            actual = row["color"]["components"]
            self.assertEqual(tuple(actual[key] for key in ("red", "green", "blue")), expected)
        splash = source("Anivibe/App/SplashView.swift")
        self.assertNotIn(".shadow(", splash)
        self.assertNotIn("design: .rounded", splash)
        self.assertIn("Вернуть стандартный цвет", source("Anivibe/Features/Settings/SettingsView.swift"))
        for relative, expected in (
            ("AppLogo.imageset/AppLogo.png", (600, 600)),
            ("AppIcon.appiconset/AppIcon-1024.png", (1024, 1024)),
        ):
            data = (ROOT / "Anivibe/Resources/Assets.xcassets" / relative).read_bytes()
            self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(struct.unpack(">II", data[16:24]), expected)


if __name__ == "__main__":
    unittest.main(verbosity=2)