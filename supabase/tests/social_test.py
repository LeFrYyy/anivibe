#!/usr/bin/env python3
"""Destructive tests ONLY on a local disposable *_test database, never hosted Supabase."""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
DB = os.environ.get('PGTEST_DB', 'anivibe_social_test')
HOST = os.environ.get('PGHOST', 'localhost')
if not DB.endswith('_test') or not DB.replace('_', '').isalnum() or not (HOST in ('localhost', '127.0.0.1') or HOST.startswith('/')):
    raise SystemExit('Refusing tests: use a local disposable *_test database only.')
def sql(query, actor=None, ok=True, database=DB):
    if actor:
        query = "begin; set local role authenticated; set local request.jwt.claims='{\"sub\":\""+actor+"\",\"role\":\"authenticated\"}'; " + query + '; commit;'
    result = subprocess.run(['psql','-X','-qAt','-v','ON_ERROR_STOP=1','-d',database,'-c',query],capture_output=True,text=True)
    if ok and result.returncode:
        raise AssertionError(result.stderr)
    return result

def uid(number): return f'00000000-0000-0000-0000-{number:012x}'
A, B, C = uid(1), uid(2), uid(3)
def action(actor,target,verb,ok=True): return sql(f"select public.anivibe_friend_action('{target}','{verb}')",actor,ok)
class SocialDatabaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sql(f'drop database if exists {DB}',database='postgres')
        sql(f'create database {DB}',database='postgres')
        subprocess.run(['psql','-X','-q','-v','ON_ERROR_STOP=1','-d',DB,'-f',str(ROOT/'supabase/tests/local_auth_stub.sql')],check=True,capture_output=True)
        migrations=sorted((ROOT/'supabase/migrations').glob('*.sql'))
        for index,path in enumerate(migrations):
            subprocess.run(['psql','-X','-q','-v','ON_ERROR_STOP=1','-d',DB,'-f',str(path)],check=True,capture_output=True)
            if index==0:
                sql("insert into public.library_entries(user_id,anime_id,title,status) values('00000000-0000-0000-0000-00000000000a',1,'Existing title','watching')")
        assert sql("select count(*) from public.profiles").stdout.strip()=='2'
        assert sql("select title from public.library_entries where anime_id=1").stdout.strip()=='Existing title'
        print('Migration backfill and existing library preservation passed.')
    def setUp(self):
        sql('truncate auth.users cascade')
        users=','.join(f"('{uid(n)}')" for n in range(1,26))
        sql('insert into auth.users(id) values '+users)
        sql("update public.profiles set username='user_'||right(user_id::text,4)")
    def count(self,query,actor=None): return sql(query,actor).stdout.strip().splitlines()[-1]
    def test_profiles_created_private(self):
        self.assertEqual(self.count("select count(*) from public.profiles where visibility='private'"),'25')
        self.assertEqual(self.count('select count(*) from public.profiles',A),'1')
    def test_normalization_and_uniqueness(self):
        sql("update public.profiles set username=' Alice ', display_name=' Alice ' where user_id='"+A+"'",A)
        self.assertEqual(self.count("select username from public.profiles where user_id='"+A+"'",A),'alice')
        self.assertNotEqual(sql("update public.profiles set username='ALICE' where user_id='"+B+"'",B,False).returncode,0)
    def test_invalid_profiles_rejected(self):
        for assignment in ["username='admin'", "username='ab'", "username='тест'", "display_name=''", "bio=repeat('x',501)", "visibility='friends'", "created_at=now()", "user_id='"+B+"'"]:
            self.assertNotEqual(sql('update public.profiles set '+assignment+" where user_id='"+A+"'",A,False).returncode,0,assignment)
    def test_foreign_private_profile_and_update_hidden(self):
        self.assertEqual(self.count("select count(*) from public.profiles where user_id='"+B+"'",A),'0')
        self.assertEqual(self.count("with changed as (update public.profiles set display_name='hacked' where user_id='"+B+"' returning 1) select count(*) from changed",A),'0')
    def test_anon_has_no_access(self):
        self.assertNotEqual(sql('set role anon; select * from public.profiles',ok=False).returncode,0)
        self.assertNotEqual(sql("set role anon; select public.anivibe_friend_action('"+B+"','send')",ok=False).returncode,0)
    def public(self,*ids):
        for user in ids: sql("update public.profiles set visibility='public' where user_id='"+user+"'")
    def test_search_obeys_privacy(self):
        self.public(B)
        self.assertEqual(self.count("select count(*) from public.anivibe_search_profiles('user_')",A),'1')
        self.assertEqual(self.count("select count(*) from public.anivibe_search_profiles('u')",A),'0')
    def test_send_accept_and_scope(self):
        self.public(B); action(A,B,'send')
        self.assertNotEqual(action(A,B,'accept',False).returncode,0)
        self.assertEqual(self.count('select count(*) from public.friendships',C),'0')
        # A deliberately sends a request: B may inspect A's private profile, but C cannot.
        self.assertEqual(self.count("select count(*) from public.profiles where user_id='"+A+"'",B),'1')
        self.assertEqual(self.count("select count(*) from public.profiles where user_id='"+A+"'",C),'0')
        action(B,A,'accept')
        self.assertEqual(self.count("select status from public.friendships",A),'accepted')
        action(A,B,'remove')
        self.assertEqual(self.count('select count(*) from public.friendships',A),'0')
    def test_decline_and_cancel_direction(self):
        self.public(B); action(A,B,'send')
        self.assertNotEqual(action(A,B,'decline',False).returncode,0)
        self.assertNotEqual(action(B,A,'cancel',False).returncode,0)
        action(B,A,'decline')
        self.assertEqual(self.count('select count(*) from public.friendships',A),'0')
    def test_cannot_write_edges_directly(self):
        self.assertNotEqual(sql(f"insert into public.friendships(user_low,user_high,requester_id,status) values('{A}','{B}','{A}','accepted')",A,False).returncode,0)
        self.assertNotEqual(sql('delete from public.friendships',A,False).returncode,0)
    def test_rate_limit_and_duplicate(self):
        self.public(B,C); action(A,B,'send')
        self.assertNotEqual(action(A,B,'send',False).returncode,0)
        self.assertIn('request_rate_limited',action(A,C,'send',False).stderr)
        self.assertEqual(self.count('select count(*) from public.friendships',A),'1')
    def test_private_target_and_self_request_rejected(self):
        self.assertNotEqual(action(A,B,'send',False).returncode,0)
        self.assertNotEqual(action(A,A,'send',False).returncode,0)
    def test_requires_username(self):
        self.public(B); sql(f"update public.profiles set username=null where user_id='{A}'")
        self.assertIn('profile_incomplete',action(A,B,'send',False).stderr)
    def test_concurrent_friend_limit(self):
        for n in range(4,13): sql(f"insert into public.friendships(user_low,user_high,requester_id,status) values('{A}','{uid(n)}','{A}','accepted')")
        for other in [B,C]: sql(f"insert into public.friendships(user_low,user_high,requester_id,status) values('{A}','{other}','{A}','pending')")
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(lambda other:action(other,A,'accept',False),[B,C]))
        self.assertEqual(sum(result.returncode==0 for result in results),1)
        self.assertEqual(self.count(f"select count(*) from public.friendships where status='accepted' and '{A}' in(user_low,user_high)"),'10')
        self.assertTrue(any('friends_limit_reached' in result.stderr for result in results))
    def test_concurrent_reverse_requests_no_duplicate(self):
        self.public(A,B)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures=[pool.submit(action,A,B,'send',False),pool.submit(action,B,A,'send',False)]
            results=[future.result() for future in futures]
        self.assertEqual(sum(result.returncode==0 for result in results),1)
        self.assertEqual(self.count('select count(*) from public.friendships'),'1')
    def test_account_deletion_cascades(self):
        self.public(B); action(A,B,'send'); sql(f"delete from auth.users where id='{A}'")
        self.assertEqual(self.count('select count(*) from public.friendships'),'0')
        self.assertEqual(self.count(f"select count(*) from public.profiles where user_id='{A}'"),'0')
    def details(self, actor, target, history_offset=0):
        return json.loads(sql(f"select public.anivibe_social_profile('{target}',{history_offset},0)", actor).stdout.strip())
    def history_fixture(self, target=B, n=1):
        sql(f"insert into public.watch_history(id,user_id,anime_id,title,episode,watched_at) select md5(i::text)::uuid,'{target}',i,'Title '||i,1,now()-i*interval '1 minute' from generate_series(1,{n}) i")
    def test_social_sections_default_private_even_for_public_profile(self):
        self.public(B); self.history_fixture()
        d=self.details(A,B)
        self.assertFalse(d['history_allowed']); self.assertEqual(d['history'],[])
        self.assertFalse(d['friends_allowed']); self.assertIsNone(d['friends_count'])
        self.assertFalse(d['library_allowed']); self.assertIsNone(d['stats'])
    def test_social_history_only_for_accepted_friends(self):
        self.public(B); self.history_fixture()
        sql(f"update public.profiles set history_visibility='friends' where user_id='{B}'",B)
        action(A,B,'send')
        self.assertFalse(self.details(A,B)['history_allowed'])
        action(B,A,'accept')
        self.assertEqual(len(self.details(A,B)['history']),1)
        action(A,B,'remove')
        self.assertFalse(self.details(A,B)['history_allowed'])
    def test_social_profile_itself_must_be_visible(self):
        sql(f"update public.profiles set history_visibility='public' where user_id='{B}'",B)
        self.assertNotEqual(sql(f"select public.anivibe_social_profile('{B}',0,0)",A,False).returncode,0)
    def test_shared_friend_list_does_not_expose_private_peer(self):
        self.public(B)
        sql(f"update public.profiles set friends_visibility='public' where user_id='{B}'",B)
        sql(f"insert into public.friendships(user_low,user_high,requester_id,status) values('{B}','{C}','{B}','accepted')")
        d=self.details(A,B)
        self.assertEqual(d['friends_count'],1); self.assertEqual(d['friends'],[])
        self.public(C)
        self.assertEqual(self.details(A,B)['friends'][0]['user_id'],C)
    def test_history_paging_filters_tombstones_and_excludes_email(self):
        self.public(B); self.history_fixture(n=45)
        sql(f"update public.profiles set history_visibility='public' where user_id='{B}'",B)
        sql(f"update public.watch_history set deleted_at=now(),updated_at=now()+interval '1 second' where user_id='{B}' and anime_id=1")
        page=self.details(A,B); next_page=self.details(A,B,40)
        self.assertEqual(len(page['history']),40); self.assertTrue(page['history_has_more'])
        self.assertEqual(len(next_page['history']),4); self.assertFalse(next_page['history_has_more'])
        self.assertNotIn('email',page['profile']); self.assertNotIn('position_seconds',json.dumps(page))
    def folder_upsert(self, actor=A, owner=A, name='Folder', when='2020-10-13T10:00:00Z', mutation=1, deleted=False, ok=True):
        folder=json.dumps({'id':uid(500),'name':name,'items':[],'createdAt':'2020-10-13T10:00:00Z'})
        return sql(f"insert into public.account_collections(user_id,id,folder,sort_order,updated_at,mutation_id,is_deleted) values('{owner}','{uid(500)}','{folder}'::jsonb,0,'{when}','{uid(mutation)}',{str(deleted).lower()}) on conflict(user_id,id) do update set folder=excluded.folder,updated_at=excluded.updated_at,mutation_id=excluded.mutation_id,is_deleted=excluded.is_deleted",actor,ok)
    def test_collections_owner_rls(self):
        self.folder_upsert()
        self.assertEqual(self.count('select count(*) from public.account_collections',A),'1')
        self.assertEqual(self.count('select count(*) from public.account_collections',B),'0')
        self.assertNotEqual(self.folder_upsert(actor=B,owner=A,ok=False).returncode,0)
        self.assertNotEqual(sql('set role anon; select * from public.account_collections',ok=False).returncode,0)
        self.assertNotEqual(sql('delete from public.account_collections',A,False).returncode,0)
    def test_collections_stale_write_cannot_resurrect_deleted_folder(self):
        self.folder_upsert(name='Deleted',when='2020-10-13T11:00:00Z',deleted=True,mutation=2)
        self.folder_upsert(name='Stale',when='2020-10-13T10:00:00Z')
        self.assertEqual(self.count('select is_deleted from public.account_collections',A),'t')
        self.assertEqual(self.count("select folder->>'name' from public.account_collections",A),'Deleted')
    def test_collections_equal_timestamp_uuid_tie_break(self):
        self.folder_upsert(name='Newer',mutation=3)
        self.folder_upsert(name='Older',mutation=1)
        self.assertEqual(self.count("select folder->>'name' from public.account_collections",A),'Newer')
    def test_anon_cannot_call_social_rpc(self):
        self.assertNotEqual(sql(f"set role anon; select public.anivibe_social_profile('{B}',0,0)",ok=False).returncode,0)
if __name__=='__main__': unittest.main(verbosity=2)
