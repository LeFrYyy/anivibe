-- Additive migration: personal Tier List (Beta) with private/public visibility and LWW sync.
begin;

create table public.tier_lists (
  user_id uuid primary key references auth.users(id) on delete cascade,
  visibility text not null default 'private' check (visibility in ('private', 'public')),
  data jsonb not null check (
    jsonb_typeof(data) = 'object'
    and data ?& array['tiers', 'visibility', 'updatedAt', 'mutationID']
    and jsonb_typeof(data->'tiers') = 'array'
    and octet_length(data::text) <= 500000
  ),
  updated_at timestamptz not null,
  mutation_id uuid not null
);

alter table public.tier_lists enable row level security;
revoke all on public.tier_lists from public, anon, authenticated;
grant select, insert, update on public.tier_lists to authenticated;

create policy tier_lists_select_own on public.tier_lists
  for select to authenticated using (user_id = (select auth.uid()));
create policy tier_lists_insert_own on public.tier_lists
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy tier_lists_update_own on public.tier_lists
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create function public.anivibe_tier_list_lww() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.updated_at > now() + interval '5 minutes' then
    new.updated_at := now();
  end if;
  if tg_op = 'UPDATE' then
    if new.user_id <> old.user_id then
      raise exception 'request_not_allowed';
    end if;
    if (new.updated_at, new.mutation_id) <= (old.updated_at, old.mutation_id) then
      return null;
    end if;
  end if;
  return new;
end $$;
revoke all on function public.anivibe_tier_list_lww() from public, anon, authenticated;

create trigger tier_lists_lww before insert or update on public.tier_lists
  for each row execute function public.anivibe_tier_list_lww();

create or replace function public.anivibe_social_profile(p_target uuid, p_history_offset integer default 0, p_library_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  p public.profiles%rowtype; fa boolean; ha boolean; la boolean;
  fs jsonb := '[]'; hs jsonb := '[]'; ls jsonb := '[]'; fc integer; stats jsonb;
  hm boolean := false; lm boolean := false;
  tl jsonb := null;
begin
  if not public.anivibe_can_view_profile(p_target) then raise exception 'request_not_allowed'; end if;
  if p_history_offset is null or p_library_offset is null or p_history_offset < 0 or p_library_offset < 0
     or p_history_offset > 100000 or p_library_offset > 100000 then raise exception 'request_not_allowed'; end if;
  select * into strict p from public.profiles where user_id = p_target;
  fa := public.anivibe_can_view_shared(p_target, p.friends_visibility);
  ha := public.anivibe_can_view_shared(p_target, p.history_visibility);
  la := public.anivibe_can_view_shared(p_target, p.library_visibility);
  if fa then
    select count(*) into fc from public.friendships f where f.status = 'accepted' and p_target in (f.user_low, f.user_high);
    select coalesce(jsonb_agg(to_jsonb(q) order by q.display_name, q.user_id), '[]'::jsonb) into fs from (
      select peer.* from public.friendships f join public.profiles peer
      on peer.user_id = case when f.user_low = p_target then f.user_high else f.user_low end
      where f.status = 'accepted' and p_target in (f.user_low, f.user_high)
      and public.anivibe_can_view_profile(peer.user_id)
    ) q;
  end if;
  if ha then
    select coalesce(jsonb_agg(to_jsonb(q) order by q.watched_at desc, q.id desc), '[]'::jsonb) into hs from (
      select * from public.watch_history where user_id = p_target and deleted_at is null
      order by watched_at desc, id desc limit 40 offset p_history_offset
    ) q;
    hm := exists(select 1 from public.watch_history where user_id = p_target and deleted_at is null
      order by watched_at desc, id desc offset (p_history_offset + 40) limit 1);
  end if;
  if la then
    select coalesce(jsonb_agg(to_jsonb(q) order by q.updated_at desc, q.anime_id desc), '[]'::jsonb) into ls from (
      select * from public.library_entries where user_id = p_target and not is_deleted and (status is not null or is_favorite)
      order by updated_at desc, anime_id desc limit 40 offset p_library_offset
    ) q;
    lm := exists(select 1 from public.library_entries where user_id = p_target and not is_deleted and (status is not null or is_favorite)
      order by updated_at desc, anime_id desc offset (p_library_offset + 40) limit 1);
    select jsonb_build_object(
      'watching', count(*) filter(where status = 'watching'),
      'completed', count(*) filter(where status = 'completed'),
      'planned', count(*) filter(where status = 'planned'),
      'onHold', count(*) filter(where status = 'onHold'),
      'dropped', count(*) filter(where status = 'dropped'),
      'favorites', count(*) filter(where is_favorite),
      'titles', count(*)
    ) into stats from public.library_entries
    where user_id = p_target and not is_deleted and (status is not null or is_favorite);
  end if;

  select t.data into tl from public.tier_lists t
  where t.user_id = p_target and (auth.uid() = p_target or t.visibility = 'public');

  return jsonb_build_object(
    'profile', to_jsonb(p),
    'friends_allowed', fa,
    'history_allowed', ha,
    'library_allowed', la,
    'friends', fs,
    'friends_count', fc,
    'history', hs,
    'library', ls,
    'stats', stats,
    'history_has_more', hm,
    'library_has_more', lm,
    'tier_list', tl
  );
end $$;
revoke all on function public.anivibe_social_profile(uuid, integer, integer) from public, anon;
grant execute on function public.anivibe_social_profile(uuid, integer, integer) to authenticated;

notify pgrst, 'reload schema';
commit;
