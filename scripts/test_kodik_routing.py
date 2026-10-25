"""Static wiring regression checks; NOT Swift compilation or live Kodik tests."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class KodikWiringTests(unittest.TestCase):
    def test_default_player_does_not_exclude_kodik(self):
        source = (ROOT/'Anivibe/Features/Player/PlayerViewModel.swift').read_text()
        self.assertNotIn('excluding: [KodikProvider.providerID]',source)
        self.assertIn('registry.candidateUpdates(for: anime, season:',source)
    def test_watch_waits_for_voice_lookup_before_routing(self):
        source = (ROOT/'Anivibe/Features/AnimeDetails/AnimeDetailsView.swift').read_text()
        flow = source.split('private func startPreferredPlayback() async {',1)[1]
        self.assertLess(flow.index('await kodikModel.load'),flow.index('if let voice = kodikModel.selectedVoice'))
        self.assertIn('playSourceEpisode(exact, voice: voice)',flow)
    def test_online_buttons_share_native_source_identity(self):
        source=(ROOT/'Anivibe/Features/Online/OnlineSourcesSection.swift').read_text()
        self.assertNotIn('webPlayback = WebPlaybackRequest',source)
        self.assertIn('playEpisode(exact, voice)',source)
    def test_web_fallback_is_offered_on_native_failure(self):
        source=(ROOT/'Anivibe/Features/Player/PlayerScreen.swift').read_text()
        self.assertIn('if let url = model.kodikWebURL',source)
        self.assertIn('WebPlayerView(url: request.url)',source)
    def test_kodik_has_explicit_registry_priority(self):
        source=(ROOT/'Packages/AnivibeCore/Sources/AnivibeCore/Providers/ProviderRegistry.swift').read_text()
        self.assertIn('return lhs.1.providerID == KodikProvider.providerID',source)
if __name__=='__main__': unittest.main(verbosity=2)
