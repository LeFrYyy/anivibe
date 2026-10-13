-- Additive: existing library/history/progress rows are untouched.
begin;
create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  display_name text not null default 'Пользователь' check (char_length(btrim(display_name)) between 1 and 60),
  bio text not null default '' check (char_length(bio) <= 500),
  visibility text not null default 'private' check (visibility in ('private','public')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_format check (username is null or (username ~ '^[a-z0-9_]{3,24}$' and username not in ('admin','administrator','support','supabase','anivibe')))
);
create table public.friendships (
  user_low uuid not null references public.profiles(user_id) on delete cascade,
  user_high uuid not null references public.profiles(user_id) on delete cascade,
  requester_id uuid not null references public.profiles(user_id) on delete cascade,
  status text not null check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_low,user_high),
  check (user_low < user_high),
  check (requester_id in (user_low,user_high))
);
create index friendships_high_idx on public.friendships(user_high,status);
create index friendships_low_status_idx on public.friendships(user_low,status);
create table public.friend_request_limits (
  user_id uuid primary key references public.profiles(user_id) on delete cascade,
  last_sent_at timestamptz,
  sent_day date,
  sent_count integer not null default 0
);
-- Only the server writes ownership, timestamps and friend edges.
revoke all on public.profiles,public.friendships,public.friend_request_limits from public,anon,authenticated;
grant select on public.profiles,public.friendships to authenticated;
grant update (username,display_name,bio,visibility) on public.profiles to authenticated;
alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.friend_request_limits enable row level security;
create policy profiles_select on public.profiles for select to authenticated using (
  user_id=(select auth.uid()) or visibility='public' or exists (
    select 1 from public.friendships f where (f.status='accepted' or (f.status='pending' and f.requester_id=user_id))
    and user_id in (f.user_low,f.user_high) and (select auth.uid()) in (f.user_low,f.user_high)
  )
);
create policy profiles_update on public.profiles for update to authenticated
  using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy friendships_select on public.friendships for select to authenticated
  using ((select auth.uid()) in (user_low,user_high));
create function public.anivibe_profile_updated() returns trigger language plpgsql set search_path='' as $$
begin
  new.username := nullif(lower(btrim(new.username)),'');
  new.display_name := btrim(new.display_name);
  new.bio := btrim(new.bio);
  new.updated_at := now();
  return new;
end $$;
create trigger anivibe_profile_updated before update on public.profiles
  for each row execute function public.anivibe_profile_updated();
create function public.anivibe_new_profile() returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into public.profiles(user_id,created_at) values(new.id,coalesce(new.created_at,now())) on conflict do nothing;
  return new;
end $$;
revoke all on function public.anivibe_new_profile(),public.anivibe_profile_updated() from public,anon,authenticated;
create trigger anivibe_new_profile after insert on auth.users for each row execute function public.anivibe_new_profile();
insert into public.profiles(user_id,created_at) select id,coalesce(created_at,now()) from auth.users on conflict do nothing;

-- No email/auth metadata is returned. Invoker rights preserve profile RLS.
create function public.anivibe_search_profiles(p_username text) returns setof public.profiles
language sql stable security invoker set search_path='' as $$
  select p.* from public.profiles p
  where auth.uid() is not null
  and char_length(btrim(p_username)) between 3 and 24
  and lower(btrim(p_username)) ~ '^[a-z0-9_]+$'
  and starts_with(p.username,lower(btrim(p_username)))
  and p.user_id <> auth.uid()
  order by p.username limit 20
$$;
revoke all on function public.anivibe_search_profiles(text) from public,anon;
grant execute on function public.anivibe_search_profiles(text) to authenticated;

create function public.anivibe_friend_action(p_target uuid,p_action text) returns void
language plpgsql security definer set search_path='' as $$
declare
  actor uuid := auth.uid(); lo uuid; hi uuid; edge public.friendships%rowtype;
  limits public.friend_request_limits%rowtype; friend_count integer; target_count integer;
begin
  if actor is null or p_target is null or p_action is null or actor=p_target or p_action not in ('send','accept','decline','cancel','remove') then
    raise exception 'request_not_allowed';
  end if;
  lo := least(actor,p_target); hi := greatest(actor,p_target);
  -- Ordered row locks serialize all actions involving either user, including friend-limit checks.
  perform user_id from public.profiles where user_id in (lo,hi) order by user_id for update;
  if not exists(select 1 from public.profiles where user_id=actor) or
     not exists(select 1 from public.profiles where user_id=p_target) then raise exception 'request_not_allowed'; end if;
  select * into edge from public.friendships where user_low=lo and user_high=hi for update;
  if p_action='send' then
    if not exists(select 1 from public.profiles where user_id=actor and username is not null) then raise exception 'profile_incomplete'; end if;
    if edge.status is not null then raise exception 'request_already_exists'; end if;
    if not exists(select 1 from public.profiles where user_id=p_target and visibility='public' and username is not null) then
      raise exception 'request_not_allowed'; end if;
    select count(*) into friend_count from public.friendships where status='accepted' and actor in (user_low,user_high);
    select count(*) into target_count from public.friendships where status='accepted' and p_target in (user_low,user_high);
    if friend_count>=10 or target_count>=10 then raise exception 'friends_limit_reached'; end if;
    if (select count(*) from public.friendships where status='pending' and requester_id=actor)>=20 or
       (select count(*) from public.friendships where status='pending' and p_target in (user_low,user_high) and requester_id<>p_target)>=50
      then raise exception 'request_rate_limited'; end if;
    insert into public.friend_request_limits(user_id) values(actor) on conflict do nothing;
    select * into limits from public.friend_request_limits where user_id=actor for update;
    if limits.last_sent_at > now()-interval '10 seconds' or
       (limits.sent_day=current_date and limits.sent_count>=50) then raise exception 'request_rate_limited'; end if;
    update public.friend_request_limits set last_sent_at=now(),sent_day=current_date,
      sent_count=case when limits.sent_day=current_date then limits.sent_count+1 else 1 end where user_id=actor;
    insert into public.friendships(user_low,user_high,requester_id,status) values(lo,hi,actor,'pending');
  elsif p_action='accept' then
    if edge.status<>'pending' or edge.status is null or edge.requester_id=actor then raise exception 'request_not_allowed'; end if;
    select count(*) into friend_count from public.friendships where status='accepted' and actor in (user_low,user_high);
    select count(*) into target_count from public.friendships where status='accepted' and p_target in (user_low,user_high);
    if friend_count>=10 or target_count>=10 then raise exception 'friends_limit_reached'; end if;
    update public.friendships set status='accepted',updated_at=now() where user_low=lo and user_high=hi;
  else
    if edge.status is null or
       (p_action='cancel' and (edge.status<>'pending' or edge.requester_id<>actor)) or
       (p_action='decline' and (edge.status<>'pending' or edge.requester_id=actor)) or
       (p_action='remove' and edge.status<>'accepted') then raise exception 'request_not_allowed'; end if;
    delete from public.friendships where user_low=lo and user_high=hi;
  end if;
end $$;
revoke all on function public.anivibe_friend_action(uuid,text) from public,anon;
grant execute on function public.anivibe_friend_action(uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;
