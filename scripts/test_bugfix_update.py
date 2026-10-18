#!/usr/bin/env python3
"""Source-level regressions only: these do not compile/run Swift, SwiftUI or SQL."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


class BugfixUpdateSourceTests(unittest.TestCase):
    def test_profile_library_routes_are_value_based_and_owned_by_root(self):
        profile = source("Anivibe/Features/Profile/ProfileView.swift")
        self.assertIn("NavigationStack(path: $path)", profile)
        self.assertIn(".navigationDestination(for: LibrarySection.self)", profile)
        for route in ("favorites", "history", "list(status)"):
            self.assertIn("NavigationLink(value: LibrarySection." + route, profile)
        self.assertEqual(profile.count("LibraryView("), 1)
        self.assertIn(".id(section)", profile)

    def test_embedded_library_does_not_register_duplicate_destinations(self):
        library = source("Anivibe/Features/Library/LibraryView.swift")
        body = library.split("var body: some View {", 1)[1].split("private var libraryContent:", 1)[0]
        self.assertIn("if embedded { libraryContent }", body)
        self.assertEqual(body.count(".navigationDestination("), 2)
        self.assertNotIn(".navigationDestination(", library.split("private var libraryContent:", 1)[1])

    def test_progress_keeps_event_time_end_to_end(self):
        player = source("Anivibe/Features/Player/PlayerViewModel.swift")
        store = source("Anivibe/Core/LibraryStore.swift")
        repository = source("Packages/AnivibeCore/Sources/AnivibeCore/Library/LibraryRepository.swift")
        self.assertIn("recordedAt: now", player)
        self.assertIn("recordedAt: recordedAt", store)
        self.assertIn("let t = recordedAt ?? now()", repository)
        self.assertIn("existing.updatedAt > t", repository)
        self.assertIn("let newerSampleExists =", repository)
        self.assertIn("activeAccountID == accountID", repository)

    def test_close_waits_for_final_save_before_dismissing(self):
        screen = source("Anivibe/Features/Player/PlayerScreen.swift")
        close = screen.split("private func close()", 1)[1].split("private struct PlayerContent:", 1)[0]
        self.assertLess(close.index("await model?.finishPlayback()"), close.index("dismiss()"))
        self.assertIn("guard !isClosing", close)
        player = source("Anivibe/Features/Player/PlayerViewModel.swift")
        finish = player.split("func finishPlayback()", 1)[1].split("var kodikWebURL", 1)[0]
        self.assertLess(finish.index("teardown()"), finish.index("await progressSaveTask?.value"))

    def test_final_sample_reads_live_position_and_allows_zero(self):
        player = source("Anivibe/Features/Player/PlayerViewModel.swift")
        save = player.split("private func saveProgress(force:", 1)[1].split("// MARK: - Helpers", 1)[0]
        self.assertIn("player.currentTime().seconds", save)
        self.assertIn("position >= 0", save)
        self.assertNotIn("currentTime > 0", save)
        self.assertIn("hasActuallyPlayed", save)
        self.assertIn("source?.isTestContent != true", save)
        observer = player.split("player.observe(\\.timeControlStatus", 1)[1].split("private func observe(item:", 1)[0]
        self.assertIn("self.hasActuallyPlayed = true", observer)
        self.assertIn("self.saveProgress(force: true)", observer)

    def test_date_precision_has_legacy_read_fallback(self):
        persistence = source("Packages/AnivibeCore/Sources/AnivibeCore/Library/LibraryPersistence.swift")
        self.assertEqual(persistence.count(".withFractionalSeconds"), 2)
        self.assertIn("fractional.date(from: value) ?? legacy.date(from: value)", persistence)

    def test_finished_source_keeps_anchor_and_next_is_resolved_from_real_list(self):
        repository = source("Packages/AnivibeCore/Sources/AnivibeCore/Library/LibraryRepository.swift")
        self.assertNotIn("guard !latest.isFinished else { return nil }", repository)
        details = source("Anivibe/Features/AnimeDetails/AnimeDetailsView.swift")
        self.assertIn("KodikProvider.resumeEpisode(for: saved, in: list)", details)
        provider = source("Packages/AnivibeCore/Sources/AnivibeCore/Providers/KodikProvider.swift")
        resolver = provider.split("public static func resumeEpisode(", 1)[1].split("/// Озвучки", 1)[0]
        self.assertIn("$0.sourceKey == key", resolver)
        self.assertIn("nextSource.titleID == currentSource.titleID", resolver)
        self.assertNotIn("resume.episode + 1", resolver)

    def test_voice_restore_is_exact_and_does_not_override_explicit_choice(self):
        online = source("Anivibe/Features/Online/OnlineSourcesSection.swift")
        self.assertIn("guard !hasExplicitVoiceSelection, let sourceKey", online)
        self.assertIn("$0.sourceKey == sourceKey", online)
        self.assertIn("hasExplicitVoiceSelection = true", online)
        self.assertIn("resumeSourceKey: library.resumePoint(for: anime)?.sourceKey", online)
        player = source("Anivibe/Features/Player/PlayerViewModel.swift")
        self.assertIn("KodikProvider.progressEpisode(for: $0)", player)
        self.assertIn("episode: identity.number, sourceKey: identity.id", player)

    def test_feature_flags_hide_entry_points_without_deleting_implementation(self):
        flags = source("Anivibe/App/AppFeatures.swift")
        self.assertIn("sharedWatchingEnabled = false", flags)
        self.assertIn("friendshipShopEnabled = false", flags)
        self.assertIn("session.user != nil && AppFeatures.communityEnabled",
                      source("Anivibe/Features/Profile/ProfileView.swift"))
        self.assertIn("env.session.user != nil && AppFeatures.sharedWatchingEnabled",
                      source("Anivibe/Features/AnimeDetails/AnimeDetailsView.swift"))
        friends = source("Anivibe/Features/Profile/FriendsView.swift")
        self.assertIn('if AppFeatures.sharedWatchingEnabled, relationships.edge', friends)
        community = source("Anivibe/Features/Community/CommunityViews.swift")
        self.assertIn("case .shop, .inventory: return AppFeatures.friendshipShopEnabled", community)
        self.assertTrue((ROOT / "Anivibe/Features/Community/WatchRoomViews.swift").is_file())
        self.assertIn("func purchase(", source("Anivibe/Core/CommunityStore.swift"))

    def test_hidden_community_does_not_poll_in_background(self):
        root = source("Anivibe/App/RootView.swift")
        guard = root.index("guard AppFeatures.communityEnabled, scenePhase")
        self.assertLess(guard, root.index("await env.community.refresh"))
        self.assertLess(guard, root.index("service.invalidations"))

    def test_dropped_is_wired_into_ui_core_and_server(self):
        model = source("Packages/AnivibeCore/Sources/AnivibeCore/Models/Library.swift")
        self.assertIn('case .dropped: return "Брошено"', model)
        self.assertIn(".list(.dropped)", source("Anivibe/Features/Library/LibraryView.swift"))
        self.assertIn("case .dropped: return Theme.danger", source("Anivibe/Features/Profile/ProfileView.swift"))
        migration = source("supabase/migrations/20261015000000_bugfix_library_status.sql")
        self.assertIn("'onHold', 'dropped'", migration)
        self.assertIn("'dropped',count(*) filter(where status='dropped')", migration)
        self.assertIn("public.anivibe_can_view_profile(p_target)", migration)
        self.assertIn("public.anivibe_can_view_shared", migration)
        self.assertNotRegex(migration.lower(), r"\b(?:delete from|truncate|drop table)\b")

    def test_source_history_and_library_rows_use_source_aware_progress(self):
        library = source("Anivibe/Features/Library/LibraryView.swift")
        self.assertIn("sourceKey: item.sourceKey", library)
        self.assertIn("latestProgress(animeId: entry.id, episode: last)", library)
        repository = source("Packages/AnivibeCore/Sources/AnivibeCore/Library/LibraryRepository.swift")
        self.assertIn("entry.status != .dropped", repository)

    def test_swipe_removes_membership_not_the_whole_library_entry(self):
        library = source("Anivibe/Features/Library/LibraryView.swift")
        swipe = library.split(".swipeActions {", 1)[1].split(".contextMenu {", 1)[0]
        self.assertIn("library.setFavorite(false, for: entry.anime)", swipe)
        self.assertIn("library.setStatus(nil, for: entry.anime)", swipe)
        self.assertNotIn("library.remove(", swipe)
        self.assertIn('Button("Удалить из библиотеки", role: .destructive)', library)

    def test_behavior_tests_and_ci_cover_the_update(self):
        tests = source("Packages/AnivibeCore/Tests/AnivibeCoreTests/Bugfix20261015Tests.swift")
        self.assertEqual(len(re.findall(r"func test\w+\(", tests)), 20)
        self.assertIn("python3 scripts/test_bugfix_update.py", source(".github/workflows/ios.yml"))

    def test_hold_to_speedup_fast_forward_gesture(self):
        model = source("Anivibe/Features/Player/PlayerViewModel.swift")
        self.assertIn("private(set) var isFastForwarding = false", model)
        self.assertIn("var fastForwardSpeed: Float", model)
        self.assertIn("func startFastForward()", model)
        self.assertIn("func stopFastForward()", model)
        self.assertIn("player.rate = fastForwardSpeed", model)
        self.assertIn("player.rate = playbackSpeed", model)

        layer = source("Anivibe/Features/Player/PlayerLayerView.swift")
        self.assertIn("var onHoldBegan: (() -> Void)?", layer)
        self.assertIn("var onHoldEnded: (() -> Void)?", layer)
        self.assertIn("UILongPressGestureRecognizer", layer)
        self.assertIn("tap.require(toFail: longPress)", layer)

        screen = source("Anivibe/Features/Player/PlayerScreen.swift")
        self.assertIn("PlayerHaptic.playHoldFeedback()", screen)
        self.assertIn("model.startFastForward()", screen)
        self.assertIn("model.stopFastForward()", screen)
        self.assertIn("fastForwardBadge", screen)
        self.assertIn("controls.hide()", screen)


if __name__ == "__main__":
    unittest.main(verbosity=2)