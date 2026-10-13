#!/usr/bin/env python3
"""Run after social_test.py on its disposable local *_test database."""
import unittest
from social_test import sql, uid, A, B, C
class CommentsTests(unittest.TestCase):
    def setUp(self):
        sql('truncate auth.users cascade')
        sql(f"insert into auth.users(id) values('{A}'),('{B}'),('{C}')")
    def action(self,actor,kind,comment='null',text='',value=0,anime=100,ok=True):
        text=text.replace("'","''")
        return sql(f"select public.anivibe_comment_action({anime},'{kind}',{comment},'{text}',{value})",actor,ok)
    def fresh(self,actor):
        sql(f"delete from public.comment_action_limits where user_id='{actor}'")
    def create(self,actor=A):
        self.action(actor,'create',text='Привет')
        return "'"+sql('select id from public.title_comments limit 1').stdout.strip()+"'"
    def test_create_read_and_profile_privacy(self):
        self.create()
        self.assertEqual(sql('select author_name from public.anivibe_comments(100)',B).stdout.strip(),'Пользователь')
        sql(f"update public.profiles set visibility='public',display_name='Автор' where user_id='{A}'")
        self.assertEqual(sql('select author_name from public.anivibe_comments(100)',B).stdout.strip(),'Автор')
        self.assertEqual(sql('select count(*) from public.anivibe_comments(101)',B).stdout.strip(),'0')
    def test_direct_writes_and_anon_denied(self):
        c=self.create()
        for query in [f"delete from public.title_comments where id={c}", f"update public.title_comments set body='hacked' where id={c}",f"insert into public.comment_reactions values({c},'{B}',1)", 'select * from public.comment_reports']:
            self.assertNotEqual(sql(query,B,False).returncode,0)
        self.assertNotEqual(sql('set role anon; select public.anivibe_comments(100)',ok=False).returncode,0)
    def test_delete_owner_only_and_wrong_title(self):
        c=self.create()
        self.assertNotEqual(self.action(B,'delete',c,ok=False).returncode,0)
        self.assertNotEqual(self.action(A,'delete',c,anime=101,ok=False).returncode,0)
        self.fresh(A);self.action(A,'delete',c)
        self.assertEqual(sql('select count(*) from public.anivibe_comments(100)',B).stdout.strip(),'0')
    def test_reaction_replace_clear_and_counts(self):
        c=self.create();self.action(B,'react',c,value=1)
        self.assertEqual(sql('select likes||\':\'||my_reaction from public.anivibe_comments(100)',B).stdout.strip(),'1:1')
        self.fresh(B);self.action(B,'react',c,value=-1)
        self.assertEqual(sql('select likes||\':\'||dislikes from public.anivibe_comments(100)',A).stdout.strip(),'0:1')
        self.fresh(B);self.action(B,'react',c,value=0)
        self.assertEqual(sql('select count(*) from public.comment_reactions').stdout.strip(),'0')
    def test_reports_private_queue_and_duplicate(self):
        c=self.create();self.action(B,'report',c,text='Спам');self.fresh(B);self.action(B,'report',c,text='Спам')
        self.assertEqual(sql('select count(*) from public.comment_reports').stdout.strip(),'1')
        self.assertEqual(sql('select count(*) from public.anivibe_comments(100)',B).stdout.strip(),'1')
        sql(f"update public.title_comments set state='hidden' where id={c}")
        self.assertEqual(sql('select count(*) from public.anivibe_comments(100)',B).stdout.strip(),'0')
    def test_content_duplicate_and_throttle(self):
        for body in ['', ' '*3,'x'*2001]:self.assertNotEqual(self.action(A,'create',text=body,ok=False).returncode,0)
        self.create();self.assertIn('request_rate_limited',self.action(A,'create',text='Ещё',ok=False).stderr)
        self.fresh(A);sql("update public.title_comments set created_at=now()-interval '1 minute'")
        self.assertIn('comment_invalid',self.action(A,'create',text='Привет',ok=False).stderr)
    def test_paging_and_popular(self):
        sql(f"insert into public.title_comments(anime_id,author_id,body) select 100,'{A}',n::text from generate_series(1,25) n")
        self.assertEqual(sql('select count(*) from public.anivibe_comments(100,0,false)',B).stdout.strip(),'20')
        self.assertEqual(sql('select count(*) from public.anivibe_comments(100,20,false)',B).stdout.strip(),'5')
        c="'"+sql("select id from public.title_comments where body='1'").stdout.strip()+"'";self.action(B,'react',c,value=1)
        self.assertEqual(sql('select body from public.anivibe_comments(100,0,true) limit 1',B).stdout.strip(),'1')
    def test_avatar_grants_and_owner_path(self):
        self.assertNotEqual(sql(f"update public.profiles set avatar_path='{A}/00000000-0000-0000-0000-000000000001.jpg' where user_id='{A}'",A,False).returncode,0)
        self.assertNotEqual(sql(f"select public.anivibe_set_avatar('{A}',null)",A,False).returncode,0)
        self.assertNotEqual(sql(f"select public.anivibe_set_avatar('{A}','{B}/00000000-0000-0000-0000-000000000001.jpg')",ok=False).returncode,0)
        path=A+'/00000000-0000-0000-0000-000000000001.jpg'
        sql(f"select public.anivibe_set_avatar('{A}','{path}')")
        self.assertEqual(sql(f"select public.anivibe_set_avatar('{A}',null)").stdout.strip(),path)
        self.assertEqual(sql("select public from storage.buckets where id='avatars'").stdout.strip(),'f')
    def test_concurrent_posts_are_serialized(self):
        import concurrent.futures
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(lambda text:self.action(A,'create',text=text,ok=False),['Первый','Второй']))
        self.assertEqual(sum(r.returncode==0 for r in results),1)
        self.assertEqual(sql('select count(*) from public.title_comments').stdout.strip(),'1')
    def test_restrictive_avatar_policy_blocks_broad_policy(self):
        sql("grant usage on schema storage to authenticated; grant select,insert on storage.objects to authenticated")
        sql("create policy test_broad_storage on storage.objects for all to authenticated using(true) with check(true)")
        try:
            sql("insert into storage.objects(bucket_id,name) values('avatars','secret'),('other','ok')")
            self.assertEqual(sql("select count(*) from storage.objects where bucket_id='avatars'",B).stdout.strip(),'0')
            self.assertNotEqual(sql("insert into storage.objects(bucket_id,name) values('avatars','bypass')",B,False).returncode,0)
        finally:
            sql('drop policy test_broad_storage on storage.objects; truncate storage.objects')
    def test_avatar_limit(self):
        for _ in range(10):self.assertEqual(sql(f"select public.anivibe_avatar_limit('{A}')").stdout.strip(),'t')
        self.assertEqual(sql(f"select public.anivibe_avatar_limit('{A}')").stdout.strip(),'f')
if __name__=='__main__':unittest.main(verbosity=2)
