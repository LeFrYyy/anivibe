-- Additive migration: private sharing defaults, no broad SELECT grant on library/history.
begin;
alter table public.profiles
  add column friends_visibility text not null default 'private' check (friends_visibility in ('private','friends','public')),
  add column history_visibility text not null default 'private' check (history_visibility in ('private','friends','public')),
  add column library_visibility text not null default 'private' check (library_visibility in ('private','friends','public'));
grant update (friends_visibility,history_visibility,library_visibility) on public.profiles to authenticated;

create function public.anivibe_can_view_profile(p_target uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
   select 1 from public.profiles p where p.user_id=p_target and (
     p.user_id=auth.uid() or p.visibility='public' or exists(
       select 1 from public.friendships f where p_target in (f.user_low,f.user_high)
       and auth.uid() in (f.user_low,f.user_high)
       and (f.status='accepted' or (f.status='pending' and f.requester_id=p_target))
     )
   )
 )
$$;
create function public.anivibe_can_view_shared(p_target uuid,p_mode text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (
   auth.uid()=p_target or p_mode='public' or (p_mode='friends' and exists(
     select 1 from public.friendships f where f.status='accepted'
     and p_target in (f.user_low,f.user_high) and auth.uid() in (f.user_low,f.user_high)
   ))
 )
$$;
revoke all on function public.anivibe_can_view_profile(uuid),public.anivibe_can_view_shared(uuid,text) from public,anon,authenticated;

create function public.anivibe_social_profile(p_target uuid,p_history_offset integer default 0,p_library_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 p public.profiles%rowtype; fa boolean; ha boolean; la boolean;
 fs jsonb := '[]'; hs jsonb := '[]'; ls jsonb := '[]'; fc integer; stats jsonb;
 hm boolean := false; lm boolean := false;
begin
 if not public.anivibe_can_view_profile(p_target) then raise exception 'request_not_allowed'; end if;
 if p_history_offset is null or p_library_offset is null or p_history_offset<0 or p_library_offset<0
    or p_history_offset>100000 or p_library_offset>100000 then raise exception 'request_not_allowed'; end if;
 select * into strict p from public.profiles where user_id=p_target;
 fa := public.anivibe_can_view_shared(p_target,p.friends_visibility);
 ha := public.anivibe_can_view_shared(p_target,p.history_visibility);
 la := public.anivibe_can_view_shared(p_target,p.library_visibility);
 if fa then
   select count(*) into fc from public.friendships f where f.status='accepted' and p_target in (f.user_low,f.user_high);
   select coalesce(jsonb_agg(to_jsonb(q) order by q.display_name,q.user_id),'[]'::jsonb) into fs from (
     select peer.* from public.friendships f join public.profiles peer
     on peer.user_id=case when f.user_low=p_target then f.user_high else f.user_low end
     where f.status='accepted' and p_target in (f.user_low,f.user_high)
     -- Sharing a friend list does not make private peers' identities public.
     and public.anivibe_can_view_profile(peer.user_id)
   ) q;
 end if;
 if ha then
   select coalesce(jsonb_agg(to_jsonb(q) order by q.watched_at desc,q.id desc),'[]'::jsonb) into hs from (
     select * from public.watch_history where user_id=p_target and deleted_at is null
     order by watched_at desc,id desc limit 40 offset p_history_offset
   ) q;
   hm := exists(select 1 from public.watch_history where user_id=p_target and deleted_at is null
     order by watched_at desc,id desc offset (p_history_offset+40) limit 1);
 end if;
 if la then
   select coalesce(jsonb_agg(to_jsonb(q) order by q.updated_at desc,q.anime_id desc),'[]'::jsonb) into ls from (
     select * from public.library_entries where user_id=p_target and not is_deleted and (status is not null or is_favorite)
     order by updated_at desc,anime_id desc limit 40 offset p_library_offset
   ) q;
   lm := exists(select 1 from public.library_entries where user_id=p_target and not is_deleted and (status is not null or is_favorite)
     order by updated_at desc,anime_id desc offset (p_library_offset+40) limit 1);
   select jsonb_build_object('watching',count(*) filter(where status='watching'),
     'completed',count(*) filter(where status='completed'),'planned',count(*) filter(where status='planned'),
     'onHold',count(*) filter(where status='onHold'),'favorites',count(*) filter(where is_favorite),
     'titles',count(*)) into stats from public.library_entries
     where user_id=p_target and not is_deleted and (status is not null or is_favorite);
 end if;
 return jsonb_build_object('profile',to_jsonb(p),'friends_allowed',fa,'history_allowed',ha,'library_allowed',la,
   'friends',fs,'friends_count',fc,'history',hs,'library',ls,'stats',stats,
   'history_has_more',hm,'library_has_more',lm);
end $$;
revoke all on function public.anivibe_social_profile(uuid,integer,integer) from public,anon;
grant execute on function public.anivibe_social_profile(uuid,integer,integer) to authenticated;

create table public.account_collections (
 user_id uuid not null references auth.users(id) on delete cascade,
 id uuid not null,
 folder jsonb not null check (jsonb_typeof(folder)='object' and folder ?& array['id','items','name','createdAt'] and jsonb_typeof(folder->'items')='array'
   and jsonb_typeof(folder->'name')='string' and char_length(folder->>'name') between 1 and 120
   and (folder->>'id')::uuid=id and jsonb_typeof(folder->'createdAt')='string'
   and jsonb_array_length(folder->'items')<=2000 and octet_length(folder::text)<=2000000),
 sort_order integer not null check(sort_order between 0 and 100000),
 updated_at timestamptz not null,
 mutation_id uuid not null,
 is_deleted boolean not null default false,
 primary key(user_id,id)
);
create index account_collections_user_updated_idx on public.account_collections(user_id,updated_at,id);
alter table public.account_collections enable row level security;
revoke all on public.account_collections from public,anon,authenticated;
grant select,insert,update on public.account_collections to authenticated;
create policy collections_select_own on public.account_collections for select to authenticated using(user_id=(select auth.uid()));
create policy collections_insert_own on public.account_collections for insert to authenticated with check(user_id=(select auth.uid()));
create policy collections_update_own on public.account_collections for update to authenticated
 using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create function public.anivibe_collection_lww() returns trigger language plpgsql set search_path='' as $$
begin
 if new.updated_at > now()+interval '5 minutes' then new.updated_at := now(); end if;
 if tg_op='UPDATE' then
   if new.user_id<>old.user_id or new.id<>old.id then raise exception 'request_not_allowed'; end if;
   if (new.updated_at,new.mutation_id)<=(old.updated_at,old.mutation_id) then return null; end if;
 end if;
 return new;
end $$;
revoke all on function public.anivibe_collection_lww() from public,anon,authenticated;
create trigger account_collections_lww before insert or update on public.account_collections
 for each row execute function public.anivibe_collection_lww();
notify pgrst,'reload schema';
commit;
