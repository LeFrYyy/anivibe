#!/usr/bin/env python3
"""Source wiring checks only; UIKit interaction/FPS and iOS typechecking need Xcode/device."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
def source(path):
    return (ROOT / path).read_text(encoding='utf-8')

class UpdateSourceTests(unittest.TestCase):
    def test_hold_uses_native_surface_not_control_overlay(self):
        layer = source('Anivibe/Features/Player/PlayerLayerView.swift')
        self.assertIn('hold.minimumPressDuration = PlaybackSpeedBoost.activationDelay', layer)
        self.assertIn('hold.allowableMovement = CGFloat(PlaybackSpeedBoost.allowableMovement)', layer)
        self.assertIn('tap.require(toFail: hold)', layer)
        self.assertIn('case .ended, .cancelled, .failed: endHold()', layer)
        self.assertIn('coordinator.endHold()', layer)
        hold = layer.split('@objc func hold(', 1)[1]
        self.assertNotIn('seek(', hold)
        self.assertNotIn('skip(', hold)

    def test_boost_restores_setting_and_never_resumes_a_pause(self):
        player = source('Anivibe/Features/Player/PlayerViewModel.swift')
        boost = player.split('func beginSpeedBoost(', 1)[1].split('// MARK: - Transport', 1)[0]
        self.assertIn('player.rate > 0', boost)
        self.assertIn('speedBoost.end(restoring: playbackSpeed)', boost)
        self.assertNotIn('UserDefaults', boost)
        self.assertNotIn('player.play()', boost)
        self.assertIn('if player.rate > 0, !isSpeedBoosted', player)
        self.assertIn('isSharedWatch: sharedWatch != nil', boost)
        self.assertIn('isBlockedByUI: blockedByUI || nextEpisodeCountdown != nil', boost)
        self.assertIn('Self.speeds.contains(speed)', player)

    def test_hud_is_top_noninteractive_and_accessible(self):
        screen = source('Anivibe/Features/Player/PlayerScreen.swift')
        hud = source('Anivibe/Features/Player/SpeedBoostIndicator.swift')
        self.assertIn('alignment: .top)', screen)
        self.assertIn('AppMotion.hudTransition(reduceMotion: reduceMotion)', screen)
        self.assertIn('.onDisappear { hideTask?.cancel(); model.endSpeedBoost() }', screen)
        self.assertIn('if phase != .active { model.endSpeedBoost() }', screen)
        self.assertIn('controls.hide()', screen)
        self.assertIn('if reduceMotion', hud)
        self.assertIn('if reduceTransparency', hud)
        self.assertIn('PhaseAnimator([false, true])', hud)
        self.assertNotIn('Timer', hud)

    def test_folder_surfaces_are_flat_in_both_themes(self):
        home = source('Anivibe/Features/Home/HomeView.swift')
        folders = home.split('struct FolderTile:', 1)[1].split('struct AddToFolderSheet:', 1)[0]
        for banned in ('Gradient', 'Material', '.shadow(', '.fill(.white)', '.foregroundStyle(.white)', '.colorScheme, .dark'):
            self.assertNotIn(banned, folders)
        self.assertIn('Theme.Folder.placeholder', folders)
        self.assertIn('Theme.Folder.panelMaxHeight', folders)
        self.assertIn('Theme.Folder.panelMaxWidth', folders)
        self.assertIn('if trimmed.isEmpty { name = collection.name }', folders)
        self.assertIn('env.collections.activeAccountID == presentedAccountID', folders)
        selection = source('Anivibe/Features/Library/FolderSelectionSheet.swift')
        self.assertNotIn('Gradient', selection)
        self.assertNotIn('Material', selection)

    def test_dead_players_and_duplicate_root_sources_are_removed(self):
        all_swift = '\n'.join(p.read_text() for p in (ROOT / 'Anivibe').rglob('*.swift'))
        self.assertNotIn('KodikPlayerScreen', all_swift)
        self.assertNotIn('NativeVideoPlayer', all_swift)
        self.assertNotIn('GlassCapsuleStyle', all_swift)
        self.assertIn('struct WebPlayerView:', all_swift)
        self.assertFalse((ROOT / 'Features').exists())

    def test_search_stream_and_retries_are_wired(self):
        player = source('Anivibe/Features/Player/PlayerViewModel.swift')
        self.assertIn('registry.candidateUpdates(for: anime, season:', player)
        self.assertIn('if !startedPlayback, let first = update.decisive', player)
        self.assertIn('self.pendingSourceCount = update.pendingProviderIDs.count', player)
        self.assertIn('RetryingTransport(base: URLSessionTransport.standard())', source('Anivibe/App/AppEnvironment.swift'))
        self.assertIn('model.pendingSourceCount', source('Anivibe/Features/Player/PlayerControlsView.swift'))

    def test_source_refresh_retires_old_item_before_searching(self):
        player = source('Anivibe/Features/Player/PlayerViewModel.swift')
        search = player.split('func findSources() {', 1)[1].split('func select(candidate:', 1)[0]
        self.assertLess(search.index('clearItemObservers()'), search.index('phase = .searchingSources'))
        self.assertLess(search.index('player.replaceCurrentItem(with: nil)'), search.index('registry.candidateUpdates'))
        boost = player.split('func beginSpeedBoost(', 1)[1].split('func endSpeedBoost()', 1)[0]
        self.assertIn('player.timeControlStatus == .playing', boost)
        self.assertIn('!item.isPlaybackBufferEmpty', boost)

    def test_replay_and_identity_lookup_are_safe(self):
        self.assertIn('if duration > 0, currentTime >= duration - 0.5 { performSeek(to: 0) }', source('Anivibe/Features/Player/PlayerViewModel.swift'))
        self.assertIn('items.firstIndex(where: { $0.id == anime.id })', source('Anivibe/Features/Catalog/CatalogViewModel.swift'))
        library = source('Anivibe/Features/Library/LibraryView.swift')
        counts = library.split('private var sectionCounts:', 1)[1].split('@ViewBuilder private var content:', 1)[0]
        self.assertEqual(counts.count('for entry in library.snapshot.entries'), 1)
        self.assertNotIn('.filter', counts)

if __name__ == '__main__':
    unittest.main(verbosity=2)
