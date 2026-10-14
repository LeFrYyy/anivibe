#!/usr/bin/env python3
"""Real PG15 integration tests. Destructive ONLY on local disposable *_test DB.
Owner-only synthetic clock/progress are fixtures, not production capabilities.
Run AFTER social_test.py. CI also restarts its disposable PostgreSQL container.
"""
import concurrent.futures
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sys
import unittest
import uuid
from social_test import sql, uid, A, B, C, SocialDatabaseTests

EP, EP2, ANIME = uid(100), uid(101), uid(102)
MAP_A, MAP_B, MAP_SPECIAL = uid(201), uid(202), uid(203)
ORIGIN=datetime(2026,10,14,0,0,0,tzinfo=timezone.utc)
CHECKPOINT=Path(__file__).with_name('community-persistence-checkpoint.json')
def quoted(value): return "'"+str(value).replace("'","''")+"'"
def scalar(query,actor=None): return sql(query,actor).stdout.strip().splitlines()[-1]
def data(query,actor=A): return json.loads(scalar(query,actor))
def clock(seconds):
    stamp=(ORIGIN+timedelta(seconds=seconds)).isoformat()
    # DB owner replaces code in this disposable DB only. A client-settable GUC is forbidden.
    sql(f"create or replace function public.anivibe_now() returns timestamptz language sql volatile set search_path='' as $$ select '{stamp}'::timestamptz $$")
def bootstrap():
    sql('truncate auth.users cascade; truncate public.canonical_anime cascade')
    sql('insert into auth.users(id) values '+','.join(f"('{uid(n)}')" for n in range(1,26)))
    sql("update public.profiles set username='user_'||right(user_id::text,4)")
    sql(f"insert into public.friendships(user_low,user_high,requester_id,status) values('{A}','{B}','{A}','accepted')")
    sql(f"insert into public.friendship_stats(user_low,user_high) values('{A}','{B}')")
    sql(f"insert into public.canonical_anime(id,anilist_id,title) values('{ANIME}',1,'Reviewed fixture')")
    sql(f"insert into public.canonical_episodes(id,anime_id,catalog_key,label,kind,sort_order,duration,duration_verified) values('{EP}','{ANIME}','season:1:episode:1','Episode 1','episode',1,100,true),('{EP2}','{ANIME}','season:1:special:1','Special 1','special',2,100,true)")
    for mid,eid,voice in [(MAP_A,EP,'Voice A'),(MAP_B,EP,'Voice B'),(MAP_SPECIAL,EP2,'Voice A')]:
        source=json.dumps(dict(providerID='manifest',titleID='fixture',season=1,number=1,payload='{}'))
        sql(f"insert into public.episode_source_mappings(id,episode_id,provider_id,source_identity,voice,source_episode,source_duration,verified) values('{mid}','{eid}','manifest','fixture:{mid}',{quoted(voice)},{quoted(source)}::jsonb,100,true)")
    clock(0)

def active_room(episode=EP,host_mapping=MAP_A,guest_mapping=MAP_B):
    room=str(uuid.uuid4())
    data(f"select public.anivibe_watch_invite('{B}','{episode}','{host_mapping}','{room}')",A)
    data(f"select public.anivibe_watch_action('{room}','accept',null,null,'{guest_mapping}')",B)
    return room

class CommunityDatabaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): SocialDatabaseTests.setUpClass()
    def setUp(self):
        bootstrap();self.clients={A:str(uuid.uuid4()),B:str(uuid.uuid4())};self.sequence={A:0,B:0};self.seconds=0
    def hb(self,room,actor,position,state='playing',episode=EP,mapping=None,event=None,ok=True):
        self.sequence[actor]+=1
        mapping=mapping or (MAP_A if actor==A else MAP_B)
        query=f"select public.anivibe_watch_heartbeat('{room}','{episode}','{mapping}','{event or uuid.uuid4()}','{self.clients[actor]}',{self.sequence[actor]},{position},100,'{state}',1)"
        result=sql(query,actor,ok)
        return json.loads(result.stdout.strip().splitlines()[-1]) if ok else result
    def start(self):
        room=active_room();self.hb(room,A,0,'paused');self.hb(room,B,0,'paused')
        data(f"select public.anivibe_watch_action('{room}','play')",A)
        self.hb(room,A,0);self.hb(room,B,0)
        return room
    def play_until(self,room,end):
        for pos in range(10,end+1,10):
            self.seconds=pos;clock(pos);self.hb(room,A,pos);self.hb(room,B,pos)
    def count(self,table): return int(scalar('select count(*) from public.'+table))
    def balance(self,actor=A): return int(scalar(f"select coalesce((select balance from public.coin_wallets where user_id='{actor}'),0)"))
    def fixture_progress(self,room,episode=EP,watched_a=95,watched_b=95,shared=95):
        # Trusted rows are inserted by owner to isolate completion edge cases; not by app clients.
        for actor,mid,watched,wall_start in [(A,MAP_A,watched_a,0),(B,MAP_B,watched_b,95-shared)]:
            start=(ORIGIN+timedelta(seconds=wall_start)).isoformat();end=(ORIGIN+timedelta(seconds=95)).isoformat()
            sql(f"insert into public.watch_member_progress(session_id,user_id,episode_id,mapping_id,timeline,played_at,confirmed_end) values('{room}','{actor}','{episode}','{mid}',nummultirange(numrange(0,{watched},'[)')),tstzmultirange(tstzrange('{start}','{end}','[)')),{watched}) on conflict(session_id,user_id,episode_id) do update set timeline=excluded.timeline,played_at=excluded.played_at,confirmed_end=excluded.confirmed_end")
    def award(self,room):sql(f"select public.anivibe_watch_award('{room}')")
    # Acceptance cases 1–15, plus privacy and anti-tampering cases below.
    def test_01_below_90_no_reward(self):
        room=self.start();self.play_until(room,80);self.assertEqual(self.count('shared_episode_completions'),0);self.assertEqual(self.balance(),0)
    def test_02_enough_individual_but_low_overlap_no_reward(self):
        room=active_room();self.fixture_progress(room,shared=79);self.award(room);self.assertEqual(self.count('shared_episode_completions'),0)
    def test_03_verified_90_rewards_one_atomic_transaction(self):
        room=self.start();self.play_until(room,90)
        self.assertEqual(self.count('shared_episode_completions'),1);self.assertEqual(self.count('coin_ledger'),2)
        self.assertEqual(self.balance(A),5);self.assertEqual(self.balance(B),5);self.assertEqual(scalar('select xp from public.friendship_stats'),'10')
        self.assertEqual(scalar('select completed from public.community_daily'),'1');self.assertEqual(self.count('friendship_xp_ledger'),1)
        self.assertEqual(self.count('episode_progress'),2)
    def test_04_one_member_finished_wait_for_other(self):
        room=active_room();self.fixture_progress(room,watched_b=89);self.award(room);self.assertEqual(self.count('shared_episode_completions'),0)
        self.fixture_progress(room);self.award(room);self.assertEqual(self.count('shared_episode_completions'),1)
    def test_05_lifetime_rewatch_across_sessions_and_refriend(self):
        room=active_room();self.fixture_progress(room);self.award(room)
        data(f"select public.anivibe_watch_action('{room}','leave')",A)
        sql(f"delete from public.friendships where user_low='{A}' and user_high='{B}'; insert into public.friendships(user_low,user_high,requester_id,status) values('{A}','{B}','{A}','accepted')")
        clock(120);new=active_room();self.fixture_progress(new);self.award(new)
        self.assertEqual(self.count('shared_episode_completions'),1);self.assertEqual(self.balance(),5)
    def test_06_voices_resolve_same_canonical_episode(self):
        room=active_room();self.fixture_progress(room);self.award(room)
        self.assertEqual(scalar(f"select count(distinct episode_id) from public.episode_source_mappings where id in ('{MAP_A}','{MAP_B}')"),'1')
        self.assertEqual(self.count('shared_episode_completions'),1)
    def test_07_special_is_distinct_even_when_provider_number_matches(self):
        first=active_room();self.fixture_progress(first);self.award(first);data(f"select public.anivibe_watch_action('{first}','leave')",A)
        clock(120);special=active_room(EP2,MAP_SPECIAL,MAP_SPECIAL)
        self.fixture_progress(special,EP2);self.award(special)
        self.assertEqual(self.count('shared_episode_completions'),2);self.assertEqual(self.balance(),10)
    def test_08_seek_jump_cannot_claim_unplayed_time(self):
        room=self.start();clock(1);data(f"select public.anivibe_watch_action('{room}','seek',90)",A)
        self.hb(room,A,90);self.hb(room,B,90)
        self.assertEqual(scalar('select public.anivibe_timeline_seconds(timeline) from public.watch_member_progress limit 1'),'0')
        self.assertEqual(self.count('shared_episode_completions'),0)
    def test_09_replay_adds_neither_unique_timeline_nor_shared_time(self):
        room=self.start();self.play_until(room,40)
        data(f"select public.anivibe_watch_action('{room}','seek',0)",A);self.hb(room,A,0);self.hb(room,B,0)
        for position in (10,20,30,40):
            clock(40+position);self.hb(room,A,position);self.hb(room,B,position)
        self.assertEqual(scalar('select public.anivibe_timeline_seconds(timeline) from public.watch_member_progress limit 1'),'40')
        self.assertEqual(scalar('select public.anivibe_overlap_seconds(played_at) from public.watch_member_progress limit 1'),'40.000000')
        self.assertEqual(self.balance(),0)
    def test_10_parallel_final_heartbeats_reward_once(self):
        room=self.start();self.play_until(room,80);clock(90)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(lambda actor:self.hb(room,actor,90),[A,B]))
        self.assertEqual(len(results),2);self.assertEqual(self.count('shared_episode_completions'),1);self.assertEqual(self.count('coin_ledger'),2)
    def test_11_purchase_retry_and_parallel_nonces_charge_once(self):
        sql(f"insert into public.coin_wallets values('{A}',1000)");nonce=str(uuid.uuid4())
        def buy(key):return data(f"select public.anivibe_shop_purchase('friends_15','{key}')",A)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(buy,[nonce,nonce]))
        self.assertEqual(self.balance(),700);self.assertEqual(self.count('user_inventory'),1);self.assertEqual(self.count('coin_ledger'),1)
        buy(str(uuid.uuid4()));self.assertEqual(self.balance(),700)
        self.assertTrue(any(r['replayed'] for r in results))
    def test_12_insufficient_balance_rolls_back_everything(self):
        result=sql(f"select public.anivibe_shop_purchase('friends_15','{uuid.uuid4()}')",A,False)
        self.assertIn('insufficient_coins',result.stderr);self.assertEqual(self.balance(),0)
        self.assertEqual(self.count('user_inventory'),0);self.assertEqual(self.count('coin_ledger'),0);self.assertEqual(self.count('shop_receipts'),0)
    def test_13_concurrent_accepts_obey_both_accounts_caps(self):
        sql('delete from public.friendships')
        for number in range(4,13):sql(f"insert into public.friendships(user_low,user_high,requester_id,status) values('{A}','{uid(number)}','{A}','accepted')")
        for other in (B,C):sql(f"insert into public.friendships(user_low,user_high,requester_id,status) values('{A}','{other}','{A}','pending')")
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(lambda actor:sql(f"select public.anivibe_friend_action('{A}','accept')",actor,False),[B,C]))
        self.assertEqual(sum(r.returncode==0 for r in results),1)
        self.assertEqual(scalar(f"select count(*) from public.friendships where status='accepted' and '{A}' in(user_low,user_high)"),'10')
    def test_14_new_connections_devices_see_server_inventory(self):
        sql(f"insert into public.coin_wallets values('{A}',1000)")
        data(f"select public.anivibe_shop_purchase('orbit','{uuid.uuid4()}')",A)
        sql("select public.anivibe_cosmetic_equip('avatar','orbit')",A)
        first=data('select public.anivibe_community_hub()',A);second=data('select public.anivibe_community_hub()',A)
        self.assertEqual(first['balance'],second['balance']);self.assertEqual(first['items'],second['items'])
        self.assertTrue(next(i for i in second['items'] if i['id']=='orbit')['equipped'])
    def test_15_reward_data_is_durable_across_connections(self):
        room=active_room();self.fixture_progress(room);self.award(room)
        first=data('select public.anivibe_community_hub()',A);second=data('select public.anivibe_community_hub()',A)
        self.assertEqual(first['balance'],second['balance']);self.assertEqual(first['friends'][0]['episodes'],1)
        # Real server restart is performed by the additional CI checkpoint step, not claimed here.
    def test_client_cannot_mutate_economy_progress_or_rules(self):
        for query in ['update public.coin_wallets set balance=9999','delete from public.shared_episode_completions',
            'update public.community_rules set completion_ratio=.5','delete from public.watch_member_progress',
            "update public.shop_items set price=1",f"select public.anivibe_credit('{A}',10000,'hacked','hacked')",
            f"select public.anivibe_watch_award('{uuid.uuid4()}')"]:
            self.assertNotEqual(sql(query,A,False).returncode,0,query)
        self.assertNotEqual(sql('set role anon; select public.anivibe_community_hub()',ok=False).returncode,0)
    def test_private_inventory_and_foreign_rooms_hidden(self):
        room=active_room();self.assertNotEqual(sql(f"select public.anivibe_watch_get('{room}')",C,False).returncode,0)
        self.assertEqual(scalar('select count(*) from public.watch_sessions',C),'0')
        self.assertEqual(scalar('select count(*) from public.watch_session_members',C),'0')
        self.assertNotEqual(sql(f"select public.anivibe_cosmetic_profile('{A}')",C,False).returncode,0)
    def test_unverified_duration_disables_rewards(self):
        room=active_room();sql(f"update public.canonical_episodes set duration=null,duration_verified=false where id='{EP}'")
        self.fixture_progress(room);self.award(room);self.assertEqual(self.balance(),0)
        self.assertFalse(data(f"select public.anivibe_watch_get('{room}')",A)['rewards_eligible'])
    def test_daily_three_distinct_rewards_once(self):
        room=active_room();self.fixture_progress(room);self.award(room)
        sql(f"update public.community_daily set completed=2 where user_low='{A}' and user_high='{B}'")
        # Two earlier distinct completions are represented by the owner fixture counter.
        data(f"select public.anivibe_watch_action('{room}','next',null,'{EP2}')",A)
        self.fixture_progress(room,EP2);self.award(room);self.award(room)
        self.assertEqual(self.balance(),30);self.assertEqual(scalar('select rewarded from public.community_daily'),'t')
        self.assertEqual(scalar("select count(*) from public.coin_ledger where reason='daily'"),'2')
    def test_friend_cap_prerequisite_and_atomic_upgrade(self):
        sql(f"insert into public.coin_wallets values('{A}',1500)")
        failed=sql(f"select public.anivibe_shop_purchase('friends_30','{uuid.uuid4()}')",A,False)
        self.assertIn('prerequisite_required',failed.stderr);self.assertEqual(self.balance(),1500)
        data(f"select public.anivibe_shop_purchase('friends_15','{uuid.uuid4()}')",A)
        data(f"select public.anivibe_shop_purchase('friends_30','{uuid.uuid4()}')",A)
        self.assertEqual(data('select public.anivibe_community_hub()',A)['friend_cap'],30);self.assertEqual(self.balance(),400)
    def test_notification_claim_can_succeed_only_once(self):
        nid=scalar(f"insert into public.community_notifications(user_id,kind,event_key) values('{A}','level_up','test') returning id")
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            values=list(pool.map(lambda _:scalar(f"select public.anivibe_notification_read('{nid}')",A),range(2)))
        self.assertEqual(sorted(values),['f','t'])
    def test_privacy_invites_disabled_and_status_hidden(self):
        sql("select public.anivibe_preferences('none',true)",B)
        failed=sql(f"select public.anivibe_watch_invite('{B}','{EP}','{MAP_A}','{uuid.uuid4()}')",A,False)
        self.assertIn('invites_disabled',failed.stderr)
        self.assertIsNone(data('select public.anivibe_community_hub()',A)['friends'][0]['watching'])
    def test_expiry_and_cleanup_after_abandonment(self):
        room=active_room();clock(601)
        self.assertTrue(data(f"select public.anivibe_watch_get('{room}')",A)['status']=='closed')
        sql('select public.anivibe_watch_cleanup()')
        self.assertEqual(scalar('select count(*) from public.watch_presence where session_id is not null'),'0')
    def test_old_solo_progress_does_not_fill_joint_progress(self):
        sql(f"insert into public.episode_progress(user_id,episode_id,timeline,completed_at) values('{A}','{EP}','{{[0,100)}}',now())")
        room=self.start();self.play_until(room,80);self.assertEqual(self.balance(),0)
        self.assertEqual(scalar(f"select count(*) from public.episode_progress where user_id='{A}' and episode_id='{EP}'"),'1')

def persistence_snapshot():
    return dict(balance=int(scalar(f"select balance from public.coin_wallets where user_id='{A}'")),
        completions=int(scalar('select count(*) from public.shared_episode_completions')),
        xp=scalar('select xp from public.friendship_stats'), ledger=int(scalar('select count(*) from public.coin_ledger')))

def write_checkpoint():
    bootstrap();room=active_room()
    helper=CommunityDatabaseTests();helper.fixture_progress(room);helper.award(room)
    snapshot=persistence_snapshot();CHECKPOINT.write_text(json.dumps(snapshot))
    print('Durable reward checkpoint committed before CI server restart.')
def verify_checkpoint():
    expected=json.loads(CHECKPOINT.read_text());actual=persistence_snapshot()
    assert actual==expected,(actual,expected)
    print('PostgreSQL server restart preserved wallet, completion, XP and ledger.')

if __name__=='__main__':
    if '--write-persistence' in sys.argv:write_checkpoint()
    elif '--verify-persistence' in sys.argv:verify_checkpoint()
    else:unittest.main(verbosity=2)
