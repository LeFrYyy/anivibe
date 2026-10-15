#!/usr/bin/env python3
"""Source/configuration regressions, NOT Swift compilation or runtime/FPS tests."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


class MotionPerformanceSourceTests(unittest.TestCase):
    def test_no_routine_navigation_haptics(self):
        swift = "\n".join(path.read_text() for path in (ROOT / "Anivibe").rglob("*.swift"))
        for call in ("UIImpactFeedbackGenerator(", "UISelectionFeedbackGenerator(",
                     "UINotificationFeedbackGenerator(", ".sensoryFeedback("):
            self.assertNotIn(call, swift)

    def test_no_endless_edit_mode_animation(self):
        swift = "\n".join(path.read_text() for path in (ROOT / "Anivibe").rglob("*.swift"))
        self.assertNotIn(".repeatForever(", swift)
        self.assertNotIn("wiggle = true", swift)

    def test_every_explicit_ui_animation_uses_motion_policy(self):
        for path in (ROOT / "Anivibe").rglob("*.swift"):
            for line in path.read_text().splitlines():
                if "withAnimation(" in line or ".animation(" in line:
                    self.assertIn("AppMotion.", line, str(path.relative_to(ROOT)) + ": " + line)

    def test_motion_policy_respects_reduce_motion(self):
        motion = source("Anivibe/DesignSystem/AppMotion.swift")
        self.assertEqual(motion.count("reduceMotion ? nil"), 4)
        self.assertIn("guard !reduceMotion else { return .opacity }", motion)

    def test_folder_backdrop_is_separate_from_moving_panel(self):
        home = source("Anivibe/Features/Home/HomeView.swift")
        overlay = home.split("        .overlay {", 1)[1].split(".confirmationDialog(", 1)[0]
        self.assertIn("FolderBackdrop(close: closeFolder)", overlay)
        self.assertIn("AppMotion.panelTransition(reduceMotion: reduceMotion)", overlay)
        self.assertNotIn(".scale(scale: 0.86)", overlay)
        self.assertIn(".accessibilityHidden(openedFolder != nil)", home)
        folders = source("Anivibe/Features/Home/FolderViews.swift")
        self.assertIn("env.collections.activeAccountID == presentedAccountID", folders)

    def test_scrolling_folder_tiles_do_not_each_blur_and_double_shadow(self):
        folders = source("Anivibe/Features/Home/FolderViews.swift")
        background = folders.split("struct FolderBackground:", 1)[1].split("struct NewFolderTile:", 1)[0]
        self.assertIn(".fill(Theme.surface)", background)
        self.assertIn(".strokeBorder(Theme.separator, lineWidth: 1)", background)
        self.assertNotIn("Material", background)
        self.assertNotIn(".shadow(", background)
        self.assertIn("FolderBackground(cornerRadius: 16)", folders)

    def test_posters_request_bucketed_actual_display_size(self):
        poster = source("Anivibe/DesignSystem/Components/PosterImage.swift")
        self.assertIn("GeometryReader { geometry in", poster)
        self.assertIn("ImageDownsampling.targetSize(", poster)
        self.assertIn("scale: Double(displayScale)", poster)
        self.assertIn(".task(id: request)", poster)
        self.assertIn("self.url == request.url", poster)

    def test_image_decode_and_size_key_are_off_main_and_bounded(self):
        pipeline = source("Anivibe/Core/ImagePipeline.swift")
        self.assertIn("Task.detached(priority: .userInitiated)", pipeline)
        self.assertIn("size.width", pipeline)
        self.assertIn("size.height", pipeline)
        self.assertIn("ImageDownsampling.thumbnailPixelSize(", pipeline)
        self.assertIn("kCGImageSourceThumbnailMaxPixelSize: pixelSize", pipeline)
        self.assertIn("memory.totalCostLimit = 64 * 1024 * 1024", pipeline)
        self.assertIn("config.httpMaximumConnectionsPerHost = 4", pipeline)
        self.assertIn("config.timeoutIntervalForResource = 40", pipeline)
        self.assertIn("didReceiveMemoryWarningNotification", pipeline)
        self.assertIn("if (5...8).contains(orientation)", pipeline)

    def test_offscreen_image_cancel_keeps_other_consumers_and_rejects_old_flight(self):
        pipeline = source("Anivibe/Core/ImagePipeline.swift")
        self.assertIn("existing.subscribers.insert(subscriber)", pipeline)
        self.assertIn("withTaskCancellationHandler", pipeline)
        release = pipeline.split("private func release(", 1)[1]
        self.assertIn("flight.id == flightID", release)
        self.assertIn("flight.subscribers.remove(subscriber) != nil", release)
        self.assertIn("if flight.subscribers.isEmpty", release)
        self.assertLess(release.index("return nil"), release.index("abandoned?.cancel()"))

    def test_different_decode_sizes_share_one_url_download(self):
        pipeline = source("Anivibe/Core/ImagePipeline.swift")
        self.assertIn("private var downloads: [URL: Download]", pipeline)
        self.assertIn("let data = try await self.data(for: url)", pipeline)
        self.assertIn("if var existing = downloads[url]", pipeline)
        self.assertEqual(pipeline.count("session.data(from: url)"), 1)
        self.assertIn("download.id == downloadID", pipeline)
        self.assertIn("download.subscribers.remove(subscriber) != nil", pipeline)

    def test_catalog_cancels_invisible_work_and_restarts_pending_query(self):
        view = source("Anivibe/Features/Catalog/CatalogView.swift")
        model = source("Anivibe/Features/Catalog/CatalogViewModel.swift")
        self.assertIn(".onDisappear { model.cancelRequests() }", view)
        self.assertIn("model.phase == .idle || model.needsReload", view)
        cancel = model.split("func cancelRequests()", 1)[1].split("func loadGenres(", 1)[0]
        self.assertIn("runner.cancel()", cancel)
        self.assertIn("loadMoreTask?.cancel()", cancel)

    def test_pagination_cleanup_is_owned_by_current_request(self):
        model = source("Anivibe/Features/Catalog/CatalogViewModel.swift")
        pagination = model.split("func loadMoreIfNeeded(", 1)[1].split("func cancelRequests()", 1)[0]
        self.assertIn("!isReloading", pagination)
        self.assertIn("self.loadMoreRequestID == requestID", pagination)
        self.assertIn("defer {", pagination)
        self.assertIn("known.insert($0.id).inserted", pagination)
        self.assertNotIn("self?.isLoadingMore = false", pagination)

    def test_cached_catalog_index_decodes_off_main(self):
        model = source("Anivibe/Features/Catalog/CatalogViewModel.swift")
        cached = model.split("func loadCachedAnime(", 1)[1].split("func resetFilters()", 1)[0]
        self.assertLess(cached.index("Task.detached(priority: .utility)"), cached.index("JSONDecoder().decode"))
        self.assertIn("guard !Task.isCancelled, let cached", cached)
        self.assertIn("self.suggestions = Array(matches.prefix(10))", model)

    def test_home_details_and_folder_search_reject_stale_results(self):
        home = source("Anivibe/Features/Home/HomeViewModel.swift")
        details = source("Anivibe/Features/AnimeDetails/AnimeDetailsViewModel.swift")
        folder = source("Anivibe/Features/Home/HomeView.swift").split("struct AddToFolderSheet:", 1)[1]
        self.assertIn("!Task.isCancelled, feedRequestID == requestID", home)
        self.assertIn("!Task.isCancelled, recentRequestID == requestID", home)
        self.assertIn("!Task.isCancelled, loadRequestID == requestID", details)
        self.assertIn("defer { if searchRequestID == requestID { isLoading = false } }", folder)
        self.assertIn(".refreshable { await search(debounce: false) }", folder)

    def test_library_ui_reads_one_consistent_snapshot_and_skips_no_op_updates(self):
        repository = source("Packages/AnivibeCore/Sources/AnivibeCore/Library/LibraryRepository.swift")
        atomic_read = repository.split("public func viewState(", 1)[1].split("    /// Separate", 1)[0]
        self.assertNotIn("await ", atomic_read)
        store = source("Anivibe/Core/LibraryStore.swift")
        self.assertIn("let view = await repository.viewState()", store)
        self.assertIn("if snapshot != view.snapshot", store)
        self.assertIn("if continueWatching != view.continueWatching", store)
        self.assertIn("request == refreshGeneration", store)

    def test_continue_row_does_not_rescan_all_progress_for_every_anime(self):
        repository = source("Packages/AnivibeCore/Sources/AnivibeCore/Library/LibraryRepository.swift")
        continuing = repository.split("static func continueWatching(in state:", 1)[1].split("// MARK: - History", 1)[0]
        self.assertIn("guard limit > 0", continuing)
        self.assertIn("uniquingKeysWith: { first, _ in first }", continuing)
        self.assertIn("resumePoint(in: list,", continuing)
        self.assertNotIn("state.entries.first(", continuing)
        self.assertNotIn("resumePoint(in: state,", continuing)

    def test_unchanged_folder_mutations_skip_disk_and_cloud_work(self):
        store = source("Anivibe/App/AppEnvironment.swift")
        self.assertIn("guard next != state || errorMessage != nil else { return }", store)
        self.assertIn("if next != state { state = next }", store)

    def test_seek_is_latest_only_and_old_item_events_are_guarded(self):
        player = source("Anivibe/Features/Player/PlayerViewModel.swift")
        seek = player.split("func seek(to seconds:", 1)[1].split("// MARK: - Episodes", 1)[0]
        self.assertIn("seconds.isFinite", seek)
        self.assertIn("item.cancelPendingSeeks()", seek)
        self.assertIn("self.seekGeneration == requestID", seek)
        self.assertIn("self.player.currentItem === item", seek)
        self.assertIn("if !finished", seek)
        observers = player.split("private func observe(item:", 1)[1].split("private func observeApp()", 1)[0]
        self.assertGreaterEqual(observers.count("self.player.currentItem === item"), 7)

    def test_drag_does_not_restart_hide_timer_for_every_pixel(self):
        controls = source("Anivibe/Features/Player/PlayerControlsView.swift")
        changed = controls.split(".onChanged { gesture in", 1)[1].split(".onEnded { gesture in", 1)[0]
        self.assertIn("guard width.isFinite, width > 0", changed)
        self.assertEqual(changed.count("interacted()"), 1)
        self.assertIn("if dragPosition == nil", changed)

    def test_initial_video_preparation_has_cancellable_current_item_timeout(self):
        player = source("Anivibe/Features/Player/PlayerViewModel.swift")
        loading = player.split("private func load(_ source:", 1)[1].split("// MARK: - Observers", 1)[0]
        self.assertIn("30_000_000_000", loading)
        self.assertIn("self.player.currentItem === item, self.phase == .preparing", loading)
        self.assertIn("self.player.replaceCurrentItem(with: nil)", loading)
        self.assertIn("self.phase = .failed(", loading)
        cleanup = player.split("private func clearItemObservers()", 1)[1].split("private func updateLoadedTimeRanges", 1)[0]
        self.assertIn("preparationTask?.cancel()", cleanup)
        self.assertIn("player.currentItem?.asset.cancelLoading()", cleanup)
        self.assertIn("player.currentItem?.cancelPendingSeeks()", cleanup)

    def test_progress_writes_are_ordered_and_duplicate_final_save_is_skipped(self):
        player = source("Anivibe/Features/Player/PlayerViewModel.swift")
        progress = player.split("private func saveProgress(force:", 1)[1].split("// MARK: - Helpers", 1)[0]
        self.assertIn("sample != lastSavedProgress || library.errorMessage != nil", progress)
        self.assertLess(progress.index("await previousSave?.value"), progress.index("await library.recordProgress"))
        screen = source("Anivibe/Features/Player/PlayerScreen.swift")
        self.assertIn("scenePhase != .active", screen)

    def test_new_files_are_in_automatic_xcode_and_package_source_groups(self):
        project = source("Anivibe.xcodeproj/project.pbxproj")
        self.assertIn("PBXFileSystemSynchronizedRootGroup", project)
        self.assertTrue((ROOT / "Anivibe/DesignSystem/AppMotion.swift").is_file())
        self.assertTrue((ROOT / "Packages/AnivibeCore/Sources/AnivibeCore/Support/ImageDownsampling.swift").is_file())
        self.assertEqual(len(re.findall(r"func test\w+\(", source(
            "Packages/AnivibeCore/Tests/AnivibeCoreTests/MotionPerformanceTests.swift"))), 14)


if __name__ == "__main__":
    unittest.main(verbosity=2)
