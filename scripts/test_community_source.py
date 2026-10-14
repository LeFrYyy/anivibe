#!/usr/bin/env python3
"""Source/contract/tool regressions only; these do NOT execute Swift or PostgreSQL."""
import copy
import importlib.util
import json
from pathlib import Path
import re
import unittest
ROOT=Path(__file__).resolve().parents[1]
def text(path):return (ROOT/path).read_text()
spec=importlib.util.spec_from_file_location('canonical_importer',ROOT/'scripts/import_canonical_catalog.py')
importer=importlib.util.module_from_spec(spec);spec.loader.exec_module(importer)

def sample():
    doc=json.loads(text('docs/canonical-catalog.example.json'));a=doc['anime'][0];a['title']='Reviewed fixture'
    source=a['episodes'][0]['sources'][0];source['source_identity']='title:season:1:episode:1';source['voice']='Voice';source['source_episode']['titleID']='title';source['source_episode']['payload']='{}'
    return doc
class CommunitySourceTests(unittest.TestCase):
    def test_additive_migrations_keep_original_data(self):
        for name in ['20261014000000_community_foundation.sql','20261014010000_shared_watch.sql','20261014020000_curated_cosmetics.sql']:
            body=text('supabase/migrations/'+name)
            self.assertNotIn('truncate ',body.lower());self.assertNotIn('drop table',body.lower())
    def test_every_community_rpc_matches_server_parameter_names(self):
        client=text('Packages/AnivibeCore/Sources/AnivibeCore/Community/SupabaseCommunityService.swift')
        server='\n'.join(p.read_text() for p in (ROOT/'supabase/migrations').glob('20261014*.sql'))
        functions={name:set(re.findall(r'\b(p_\w+)\s+',args)) for name,args in re.findall(r'create (?:or replace )?function public\.(\w+)\(([^)]*)\)',server)}
        for name,body in re.findall(r'(?:decode|rpc)\("(anivibe_\w+)", body: \[([^\n]*)\]',client):
            self.assertIn(name,functions);self.assertEqual(set(re.findall(r'"(p_\w+)"\s*:',body)),functions[name],name)
        self.assertIn('p_after',functions['anivibe_episode_catalog'])
    def test_both_friend_caps_under_ordered_locks(self):
        body=text('supabase/migrations/20261014000000_community_foundation.sql')
        self.assertIn('order by user_id for update',body)
        self.assertEqual(body.count('>=public.anivibe_friend_cap(actor)'),2)
        self.assertEqual(body.count('>=public.anivibe_friend_cap(p_target)'),2)
    def test_reward_unique_pair_canonical_not_session_voice_or_policy(self):
        body=text('supabase/migrations/20261014010000_shared_watch.sql')
        self.assertIn('unique(user_low,user_high,episode_id)',body)
        self.assertNotIn('unique(user_low,user_high,episode_id,policy_version)',body)
    def test_replay_does_not_add_simultaneous_time(self):
        body=text('supabase/migrations/20261014010000_shared_watch.sql')
        self.assertIn('fresh_part:=timeline_part-prog.timeline',body)
        self.assertIn('for segment in select unnest(fresh_part)',body)
        self.assertIn("s.wants_play and s.playback='playing'",body)
    def test_purchase_has_idempotency_wallet_lock_and_server_price(self):
        body=text('supabase/migrations/20261014000000_community_foundation.sql')
        self.assertIn('primary key(user_id,request_id)',body)
        self.assertIn('from public.coin_wallets where user_id=actor for update',body)
        self.assertIn('balance=balance-item.price',body)
        self.assertIn("raise exception 'prerequisite_required'",body)
    def test_client_has_no_privileged_keys_or_award_rpc(self):
        body=text('Packages/AnivibeCore/Sources/AnivibeCore/Community/SupabaseCommunityService.swift')
        self.assertNotIn('anivibe_watch_award',body);self.assertNotIn('anivibe_credit',body)
        self.assertIn('config.anonKey',body);self.assertIn('validSession()',body)
        self.assertGreaterEqual(body.count('userId.lowercased()'),3)
    def test_realtime_is_cancellable_and_reconnects(self):
        body=text('Packages/AnivibeCore/Sources/AnivibeCore/Community/SupabaseCommunityService.swift')
        for marker in ['webSocketTask','postgres_changes','onTermination','withTaskCancellationHandler','network.invalidateAndCancel()', 'backoff = min(30']:
            self.assertIn(marker,body)
    def test_shared_player_preserves_standalone_paths(self):
        player=text('Anivibe/Features/Player/PlayerViewModel.swift')
        self.assertIn('if let sharedWatch { sharedWatch.togglePlay(); return }',player)
        self.assertIn('private func performSeek',player)
        self.assertIn('sharedWatch?.stop()',player)
        screen=text('Anivibe/Features/Player/PlayerScreen.swift')
        self.assertIn('request.sharedWatch == nil && settings.autoplayNextEpisode',screen)
        self.assertIn('vm.useSharedSpeed()',screen);self.assertNotIn('vm.setSpeed(1)',screen)
    def test_media_lists_static_and_reduced_motion_foreground(self):
        view=text('Anivibe/Features/Community/CosmeticMediaView.swift')
        self.assertIn('!reduceMotion && scenePhase == .active && !powerSaving',view)
        self.assertIn('animator?.stop(); animator = nil',view)
        self.assertIn('ThumbnailMaxPixelSize: 768',view)
        self.assertIn('animate: false',text('Anivibe/Features/Community/CommunityViews.swift'))
    def test_invalid_unknown_catalog_duration_cannot_claim_rewards(self):
        body=text('supabase/migrations/20261014010000_shared_watch.sql')
        self.assertIn('if not e.duration_verified or e.duration is null',body)
        self.assertIn('m.client_id=p_client',body)
        self.assertIn('dt between .1 and rules.heartbeat_max_seconds',body)
    def test_server_clock_never_reads_a_client_testing_guc(self):
        body='\n'.join(p.read_text() for p in (ROOT/'supabase/migrations').glob('20261014*.sql'))
        self.assertNotIn('current_setting(',body);self.assertIn('select clock_timestamp()',body)
        self.assertIn('n at time zone rules.daily_timezone',body)
    def test_importer_keeps_source_identity_and_special_separate(self):
        doc=sample();ep=copy.deepcopy(doc['anime'][0]['episodes'][0]);ep['id']='00000000-0000-4000-8000-000000000102';ep['catalog_key']='season:1:special:1';ep['kind']='special';ep['sort_order']=2
        ep['sources'][0]['id']='00000000-0000-4000-8000-000000001002';ep['sources'][0]['source_identity']='title:season:1:special:1'
        doc['anime'][0]['episodes'].append(ep);sql=importer.generate(doc)
        self.assertIn('season:1:episode:1',sql);self.assertIn('season:1:special:1',sql)
    def test_ambiguous_source_identity_and_unverified_missing_duration_rejected(self):
        doc=sample();ep=copy.deepcopy(doc['anime'][0]['episodes'][0]);ep['id']='00000000-0000-4000-8000-000000000102';ep['catalog_key']='different';ep['sort_order']=2
        doc['anime'][0]['episodes'].append(ep)
        with self.assertRaises(ValueError):importer.generate(doc)
        doc=sample();doc['anime'][0]['episodes'][0]['duration_verified']=True
        with self.assertRaises(ValueError):importer.generate(doc)
    def test_importer_does_not_publish_placeholder_catalog(self):
        with self.assertRaises(ValueError):importer.generate(json.loads(text('docs/canonical-catalog.example.json')))
    def test_moderation_is_server_only_and_admin_not_granted(self):
        body=text('supabase/migrations/20261014000000_community_foundation.sql')
        self.assertIn('anivibe_moderate_comment(uuid,text,text) to service_role',body)
        self.assertNotIn('pornoactor',body);self.assertNotIn('admin_role',body)
    def test_prepared_acceptance_tests_include_real_restart_step(self):
        tests=text('supabase/tests/community_test.py')
        for number in range(1,16):self.assertIn(f'def test_{number:02}_',tests)
        ci=text('.github/workflows/ios.yml')
        self.assertIn('docker restart "${{ job.services.postgres.id }}"',ci)
        self.assertIn('--verify-persistence',ci)

if __name__=='__main__':unittest.main(verbosity=2)
