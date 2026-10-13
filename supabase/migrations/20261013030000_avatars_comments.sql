-- Repeat-safe additive migration for the Anivibe avatars/comments schema.
-- Keeps existing rows. Previous migrations must already be installed.
begin;
alter table public.profiles add column if not exists avatar_path text;
do $migration$
begin
 if not exists (
  select 1 from pg_catalog.pg_constraint
  where conrelid='public.profiles'::regclass and conname='profiles_avatar_owner'
 ) then
  alter table public.profiles add constraint profiles_avatar_owner check (
   avatar_path is null or avatar_path ~ ('^' || user_id::text || '/[0-9a-f-]{36}\.jpg$'));
 end if;
end $migration$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('avatars','avatars',false,1048576,array['image/jpeg'])
on conflict(id) do update set public=false,file_size_limit=1048576,allowed_mime_types=array['image/jpeg'];
-- Restrictive policy also blocks accidental broad client storage policies on this bucket.
drop policy if exists anivibe_avatars_edge_only on storage.objects;
create policy anivibe_avatars_edge_only on storage.objects as restrictive
for all to anon,authenticated using(bucket_id<>'avatars') with check(bucket_id<>'avatars');
-- No client INSERT/UPDATE/DELETE storage policies. Only validated Edge uploads.
create table if not exists public.avatar_limits(user_id uuid primary key references auth.users on delete cascade,
 window_start timestamptz not null, attempts integer not null);
alter table public.avatar_limits enable row level security;
revoke all on public.avatar_limits from public, anon, authenticated;
create or replace function public.anivibe_avatar_limit(p_user uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare n integer; begin
 insert into public.avatar_limits values(p_user,now(),1) on conflict(user_id) do update set
 attempts=case when avatar_limits.window_start < now()-interval '1 hour' then 1 else avatar_limits.attempts+1 end,
 window_start=case when avatar_limits.window_start < now()-interval '1 hour' then now() else avatar_limits.window_start end
 returning attempts into n;
 return n<=10;
end $$;
create or replace function public.anivibe_set_avatar(p_user uuid,p_path text) returns text
language plpgsql security definer set search_path='' as $$
declare old_path text; begin
 select avatar_path into old_path from public.profiles where user_id=p_user for update;
 if not found then raise exception 'profile_missing'; end if;
 update public.profiles set avatar_path=p_path where user_id=p_user;
 return old_path;
end $$;
revoke all on function public.anivibe_avatar_limit(uuid), public.anivibe_set_avatar(uuid,text) from public, anon, authenticated;
grant execute on function public.anivibe_avatar_limit(uuid), public.anivibe_set_avatar(uuid,text) to service_role;

create table if not exists public.title_comments(
 id uuid primary key default gen_random_uuid(), anime_id bigint not null check(anime_id>0),
 author_id uuid not null references auth.users(id) on delete cascade,
 body text not null check(char_length(body) between 1 and 2000 and body=btrim(body,E' \n\r\t')),
 state text not null default 'published' check(state in ('published','hidden','deleted')),
 created_at timestamptz not null default now());
create index if not exists title_comments_page on public.title_comments(anime_id,created_at desc,id desc) where state='published';
create index if not exists title_comments_author on public.title_comments(author_id,created_at desc);
create table if not exists public.comment_reactions(
 comment_id uuid references public.title_comments(id) on delete cascade,
 user_id uuid references auth.users(id) on delete cascade,
 value smallint not null check(value in (-1,1)), primary key(comment_id,user_id));
create table if not exists public.comment_reports(
 comment_id uuid references public.title_comments(id) on delete cascade,
 user_id uuid references auth.users(id) on delete cascade,
 reason text not null check(reason in ('Спам','Оскорбления','Неприемлемый контент','Другое')),
 created_at timestamptz not null default now(), primary key(comment_id,user_id));
create index if not exists comment_reports_author on public.comment_reports(user_id,created_at desc);
create table if not exists public.comment_action_limits(
 user_id uuid primary key references auth.users(id) on delete cascade,
 window_start timestamptz not null,last_action timestamptz not null,attempts integer not null);
alter table public.title_comments enable row level security;
alter table public.comment_reactions enable row level security;
alter table public.comment_reports enable row level security;
alter table public.comment_action_limits enable row level security;
revoke all on public.title_comments,public.comment_reactions,public.comment_reports,public.comment_action_limits from public,anon,authenticated;
grant select on public.title_comments,public.comment_reactions to authenticated;
drop policy if exists comments_read on public.title_comments;
create policy comments_read on public.title_comments for select to authenticated using(state='published');
drop policy if exists reactions_read on public.comment_reactions;
create policy reactions_read on public.comment_reactions for select to authenticated using(
 exists(select 1 from public.title_comments c where c.id=comment_id));

-- INVOKER: private profiles remain subject to the existing profiles RLS.
create or replace function public.anivibe_comments(p_anime bigint,p_offset integer default 0,p_popular boolean default false)
returns table(id uuid,author_id uuid,author_name text,body text,created_at timestamptz,likes integer,dislikes integer,my_reaction integer)
language sql stable security invoker set search_path='' as $$
 select c.id,c.author_id,coalesce(p.display_name,'Пользователь'),c.body,c.created_at,
 (select count(*)::integer from public.comment_reactions r where r.comment_id=c.id and r.value=1),
 (select count(*)::integer from public.comment_reactions r where r.comment_id=c.id and r.value=-1),
 coalesce((select r.value::integer from public.comment_reactions r where r.comment_id=c.id and r.user_id=auth.uid()),0)
 from public.title_comments c left join public.profiles p on p.user_id=c.author_id
 where c.anime_id=p_anime and c.state='published'
 order by case when p_popular then (select coalesce(sum(r.value),0) from public.comment_reactions r where r.comment_id=c.id) else 0 end desc,
 c.created_at desc,c.id desc
 limit 20 offset greatest(0,least(p_offset,10000))
$$;
create or replace function public.anivibe_comment_action(p_anime bigint,p_action text,p_comment uuid default null,p_text text default '',p_value integer default 0)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); c public.title_comments; lim public.comment_action_limits; n integer;
begin
 if actor is null then raise exception 'request_not_allowed' using errcode='42501'; end if;
 if p_anime is null or p_anime<=0 or p_action not in ('create','delete','react','report') or p_action is null then
 raise exception 'request_not_allowed' using errcode='42501'; end if;
 -- Lock actor first: serializes rate checks even on different comments.
 perform 1 from public.profiles where user_id=actor for update;
 if not found then raise exception 'profile_missing'; end if;
 select * into lim from public.comment_action_limits where user_id=actor;
 if found and lim.last_action>now()-interval '1 second' then raise exception 'request_rate_limited'; end if;
 if found and lim.window_start>now()-interval '1 hour' and lim.attempts>=200 then raise exception 'request_rate_limited'; end if;
 insert into public.comment_action_limits values(actor,now(),now(),1) on conflict(user_id) do update set
 attempts=case when comment_action_limits.window_start<now()-interval '1 hour' then 1 else comment_action_limits.attempts+1 end,
 window_start=case when comment_action_limits.window_start<now()-interval '1 hour' then now() else comment_action_limits.window_start end,last_action=now();
 if p_action='create' then
  p_text:=btrim(p_text,E' \n\r\t');
  if p_text is null or char_length(p_text) not between 1 and 2000 then raise exception 'comment_invalid'; end if;
  if exists(select 1 from public.title_comments where author_id=actor and created_at>now()-interval '15 seconds') or
   (select count(*) from public.title_comments where author_id=actor and created_at>now()-interval '1 hour')>=30 then
   raise exception 'request_rate_limited'; end if;
  if exists(select 1 from public.title_comments where author_id=actor and lower(body)=lower(p_text) and created_at>now()-interval '20 minutes') then
   raise exception 'comment_invalid'; end if;
  insert into public.title_comments(anime_id,author_id,body) values(p_anime,actor,p_text);
  return;
 end if;
 select * into c from public.title_comments where id=p_comment and anime_id=p_anime for update;
 if not found or c.state<>'published' then raise exception 'request_not_allowed' using errcode='42501'; end if;
 if p_action='delete' then
  if c.author_id<>actor then raise exception 'request_not_allowed' using errcode='42501'; end if;
  update public.title_comments set state='deleted',body='[Удалено]' where id=c.id;
 elsif p_action='react' then
  if p_value is null or p_value not in (-1,0,1) then raise exception 'request_not_allowed' using errcode='42501'; end if;
  if p_value=0 then delete from public.comment_reactions where comment_id=c.id and user_id=actor;
  else insert into public.comment_reactions values(c.id,actor,p_value) on conflict(comment_id,user_id) do update set value=excluded.value; end if;
 elsif p_action='report' then
  if p_text is null or p_text not in ('Спам','Оскорбления','Неприемлемый контент','Другое') or c.author_id=actor then
   raise exception 'request_not_allowed' using errcode='42501'; end if;
  if exists(select 1 from public.comment_reports where comment_id=c.id and user_id=actor) then return; end if;
  select count(*) into n from public.comment_reports where user_id=actor and created_at>now()-interval '1 day';
  if n>=10 then raise exception 'request_rate_limited'; end if;
  insert into public.comment_reports(comment_id,user_id,reason) values(c.id,actor,p_text) on conflict do nothing;
 end if;
end $$;
revoke all on function public.anivibe_comments(bigint,integer,boolean),public.anivibe_comment_action(bigint,text,uuid,text,integer) from public,anon;
grant execute on function public.anivibe_comments(bigint,integer,boolean),public.anivibe_comment_action(bigint,text,uuid,text,integer) to authenticated;
-- Reports are a real admin review queue, not automatic moderation. Dashboard SQL:
-- SELECT * FROM public.comment_reports ORDER BY created_at DESC;
-- UPDATE public.title_comments SET state='hidden' WHERE id='<reviewed UUID>';
notify pgrst,'reload schema';
commit;
