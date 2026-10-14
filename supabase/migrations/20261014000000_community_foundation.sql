-- Additive Anivibe Community v1. PostgreSQL 15+. Never reset an existing project.
begin;
create table public.community_rules (
 id boolean primary key default true check(id), policy_version integer not null default 1 check(policy_version>0),
 completion_ratio numeric not null default .90 check(completion_ratio between .5 and 1),
 overlap_ratio numeric not null default .80 check(overlap_ratio between .5 and 1),
 episode_xp integer not null default 10 check(episode_xp between 0 and 10000),
 episode_coins integer not null default 5 check(episode_coins between 0 and 10000),
 daily_goal integer not null default 3 check(daily_goal between 1 and 100),
 daily_xp integer not null default 30 check(daily_xp between 0 and 10000),
 daily_coins integer not null default 20 check(daily_coins between 0 and 10000),
 daily_timezone text not null default 'UTC',
 heartbeat_max_seconds integer not null default 30 check(heartbeat_max_seconds between 15 and 45),
 presence_seconds integer not null default 45 check(presence_seconds between 30 and 120)
);
insert into public.community_rules(id) values(true);
create table public.social_preferences (
 user_id uuid primary key references public.profiles(user_id) on delete cascade,
 invite_policy text not null default 'friends' check(invite_policy in ('friends','none')),
 hide_watching boolean not null default false
);
create table public.friendship_stats (
 user_low uuid references public.profiles(user_id) on delete cascade,
 user_high uuid references public.profiles(user_id) on delete cascade,
 xp numeric not null default 0 check(xp>=0), episodes bigint not null default 0 check(episodes>=0),
 started_at timestamptz not null default now(), last_watch_at timestamptz,
 primary key(user_low,user_high), check(user_low<user_high)
);
-- Persistent pair stats deliberately do NOT reference the deletable friendship edge.
insert into public.friendship_stats(user_low,user_high,started_at)
 select user_low,user_high,created_at from public.friendships where status='accepted';
create table public.coin_wallets (
 user_id uuid primary key references public.profiles(user_id) on delete cascade,
 balance bigint not null default 0 check(balance>=0)
);
create table public.coin_ledger (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(user_id) on delete cascade,
 amount bigint not null check(amount<>0), reason text not null, event_key text not null,
 created_at timestamptz not null default now(), unique(user_id,event_key)
);
create table public.friendship_xp_ledger (
 id uuid primary key default gen_random_uuid(), user_low uuid not null, user_high uuid not null,
 amount integer not null check(amount>0), reason text not null, event_key text not null unique,
 created_at timestamptz not null default now(),
 foreign key(user_low,user_high) references public.friendship_stats on delete cascade
);
create table public.friend_upgrades (
 user_id uuid primary key references public.profiles(user_id) on delete cascade,
 friend_cap integer not null check(friend_cap in (15,30)), updated_at timestamptz not null default now()
);
create table public.community_notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(user_id) on delete cascade,
 kind text not null, payload jsonb not null default '{}', event_key text not null,
 created_at timestamptz not null default now(), read_at timestamptz, unique(user_id,event_key)
);
create index community_notifications_page on public.community_notifications(user_id,created_at desc);
-- Catalog media is curated, bundled and byte-validated by scripts/validate_community_media.py.
-- No client upload/catalog approval endpoint exists. The operator verifies assets before publishing.
create table public.cosmetic_media (
 id text primary key, asset_key text not null unique, poster_key text,
 mime text not null check(mime in ('image/png','video/mp4')),
 byte_length integer not null check(byte_length between 1 and 1048576),
 width integer not null check(width between 32 and 1024), height integer not null check(height between 32 and 512),
 duration numeric, sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'),
 approved boolean not null default false,
 check((mime='image/png' and duration is null) or (mime='video/mp4' and duration between .1 and 8))
);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('community-media','community-media',true,1048576,array['image/png','video/mp4'])
on conflict(id) do update set public=true,file_size_limit=1048576,allowed_mime_types=array['image/png','video/mp4'];
create policy community_media_operator_only on storage.objects as restrictive
for all to anon,authenticated using(bucket_id<>'community-media') with check(bucket_id<>'community-media');
create table public.shop_items (
 id text primary key, name text not null, category text not null check(category in ('avatar','banner','animated_banner','friend_cap')),
 price integer not null check(price between 1 and 1000000), active boolean not null default true,
 media_id text references public.cosmetic_media(id), cap integer check(cap in (15,30)), prerequisite text references public.shop_items(id),
 check((category='friend_cap' and cap is not null and media_id is null) or (category<>'friend_cap' and cap is null and media_id is not null))
);
insert into public.shop_items(id,name,category,price,cap) values('friends_15','До 15 друзей','friend_cap',300,15);
insert into public.shop_items(id,name,category,price,cap,prerequisite) values('friends_30','До 30 друзей','friend_cap',800,30,'friends_15');
create table public.user_inventory (
 user_id uuid references public.profiles(user_id) on delete cascade, item_id text references public.shop_items(id),
 purchased_at timestamptz not null default now(), primary key(user_id,item_id)
);
create table public.equipped_cosmetics (
 user_id uuid references public.profiles(user_id) on delete cascade,
 slot text check(slot in ('avatar','banner')), item_id text not null, primary key(user_id,slot),
 foreign key(user_id,item_id) references public.user_inventory(user_id,item_id) on delete cascade
);
create table public.shop_receipts (
 user_id uuid references public.profiles(user_id) on delete cascade, request_id uuid,
 item_id text not null references public.shop_items(id), charged integer not null check(charged>=0),
 created_at timestamptz not null default now(), primary key(user_id,request_id)
);
create table public.community_daily (
 user_low uuid, user_high uuid, day date, completed integer not null default 0 check(completed>=0),
 rewarded boolean not null default false, primary key(user_low,user_high,day),
 foreign key(user_low,user_high) references public.friendship_stats on delete cascade
);
create table public.comment_moderation_audit (
 id uuid primary key default gen_random_uuid(), comment_id uuid not null references public.title_comments on delete cascade,
 state text not null check(state in ('published','hidden')), reason text not null check(char_length(reason) between 1 and 500),
 reviewed_at timestamptz not null default now()
);

create function public.anivibe_now() returns timestamptz language sql volatile set search_path='' as $$ select clock_timestamp() $$;
-- Do NOT add a client-settable clock or test GUC. DB tests replace this function only as DB owner.
create function public.anivibe_friend_cap(p_user uuid) returns integer language sql stable security definer set search_path='' as $$
 select coalesce((select friend_cap from public.friend_upgrades where user_id=p_user),10)
$$;
create function public.anivibe_notice(p_user uuid,p_kind text,p_payload jsonb,p_key text) returns void
language sql security definer set search_path='' as $$
 insert into public.community_notifications(user_id,kind,payload,event_key) values(p_user,p_kind,p_payload,p_key) on conflict do nothing
$$;
create function public.anivibe_level(p_xp numeric) returns jsonb language plpgsql immutable set search_path='' as $$
declare lvl integer:=1; base numeric:=0; step numeric; begin
 loop
  step:=case when lvl<10 then 20*lvl else ceil(200*power(1.15::numeric,lvl-10)) end;
  exit when p_xp<base+step;
  base:=base+step; lvl:=lvl+1;
 end loop;
 return jsonb_build_object('level',lvl,'xp',p_xp::text,'in_level',(p_xp-base)::text,'needed',step::text,
  'progress',least(1,greatest(0,(p_xp-base)/step)));
end $$;
create function public.anivibe_credit(p_user uuid,p_amount integer,p_reason text,p_key text) returns void
language plpgsql security definer set search_path='' as $$ begin
 if p_amount=0 then return; end if;
 insert into public.coin_wallets(user_id) values(p_user) on conflict do nothing;
 -- All multi-wallet callers process UUIDs in ascending order.
 perform 1 from public.coin_wallets where user_id=p_user for update;
 insert into public.coin_ledger(user_id,amount,reason,event_key) values(p_user,p_amount,p_reason,p_key) on conflict do nothing;
 if found then update public.coin_wallets set balance=balance+p_amount where user_id=p_user; end if;
end $$;

create or replace function public.anivibe_search_profiles(p_username text) returns setof public.profiles
language sql stable security invoker set search_path='' as $$
 select p.* from public.profiles p where auth.uid() is not null and p.user_id<>auth.uid()
 and char_length(btrim(p_username)) between 3 and 100
 and (p.user_id::text=lower(btrim(p_username))
   or position(lower(ltrim(btrim(p_username),'@')) in p.username)=1
   or position(lower(btrim(p_username)) in lower(p.display_name))>0)
 order by p.username nulls last,p.user_id limit 20
$$;
create or replace function public.anivibe_friend_action(p_target uuid,p_action text) returns void
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
    if friend_count>=public.anivibe_friend_cap(actor) or target_count>=public.anivibe_friend_cap(p_target) then raise exception 'friends_limit_reached'; end if;
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
  perform public.anivibe_notice(p_target,'friend_request',jsonb_build_object('peer_id',actor),gen_random_uuid()::text);
  elsif p_action='accept' then
    if edge.status<>'pending' or edge.status is null or edge.requester_id=actor then raise exception 'request_not_allowed'; end if;
    select count(*) into friend_count from public.friendships where status='accepted' and actor in (user_low,user_high);
    select count(*) into target_count from public.friendships where status='accepted' and p_target in (user_low,user_high);
    if friend_count>=public.anivibe_friend_cap(actor) or target_count>=public.anivibe_friend_cap(p_target) then raise exception 'friends_limit_reached'; end if;
    update public.friendships set status='accepted',updated_at=now() where user_low=lo and user_high=hi;
    insert into public.friendship_stats(user_low,user_high) values(lo,hi) on conflict do nothing;
    perform public.anivibe_notice(p_target,'friend_accepted',jsonb_build_object('peer_id',actor),gen_random_uuid()::text);
  else
    if edge.status is null or
       (p_action='cancel' and (edge.status<>'pending' or edge.requester_id<>actor)) or
       (p_action='decline' and (edge.status<>'pending' or edge.requester_id=actor)) or
       (p_action='remove' and edge.status<>'accepted') then raise exception 'request_not_allowed'; end if;
    delete from public.friendships where user_low=lo and user_high=hi;
  end if;
end $$;

create function public.anivibe_shop_purchase(p_item text,p_request uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); item public.shop_items; receipt public.shop_receipts; balance_now bigint; charge integer:=0;
begin
 if actor is null or p_request is null or p_item is null then raise exception 'request_not_allowed' using errcode='42501'; end if;
 perform 1 from public.profiles where user_id=actor for update;
 if not found then raise exception 'request_not_allowed'; end if;
 insert into public.coin_wallets(user_id) values(actor) on conflict do nothing;
 select balance into balance_now from public.coin_wallets where user_id=actor for update;
 select * into receipt from public.shop_receipts where user_id=actor and request_id=p_request;
 if found then
  if receipt.item_id<>p_item then raise exception 'request_conflict'; end if;
  return jsonb_build_object('item_id',p_item,'balance',balance_now,'charged',receipt.charged,'replayed',true);
 end if;
 select * into item from public.shop_items where id=p_item and active for share;
 if not found or (item.media_id is not null and not exists(select 1 from public.cosmetic_media where id=item.media_id and approved)) then
  raise exception 'item_unavailable'; end if;
 if not exists(select 1 from public.user_inventory where user_id=actor and item_id=p_item) then
  if item.prerequisite is not null and not exists(select 1 from public.user_inventory where user_id=actor and item_id=item.prerequisite) then
   raise exception 'prerequisite_required'; end if;
  if balance_now<item.price then raise exception 'insufficient_coins'; end if;
  charge:=item.price;
  update public.coin_wallets set balance=balance-item.price where user_id=actor;
  insert into public.user_inventory(user_id,item_id) values(actor,p_item);
  insert into public.coin_ledger(user_id,amount,reason,event_key) values(actor,-item.price,'purchase','purchase:'||p_request);
  if item.category='friend_cap' then
   insert into public.friend_upgrades values(actor,item.cap,public.anivibe_now()) on conflict(user_id) do update
    set friend_cap=greatest(friend_upgrades.friend_cap,excluded.friend_cap),updated_at=excluded.updated_at;
  end if;
 end if;
 insert into public.shop_receipts(user_id,request_id,item_id,charged) values(actor,p_request,p_item,charge);
 return jsonb_build_object('item_id',p_item,'balance',balance_now-charge,'charged',charge,'replayed',false);
end $$;
create function public.anivibe_cosmetic_equip(p_slot text,p_item text default null) returns void
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); category text; begin
 if actor is null or p_slot is null or p_slot not in ('avatar','banner') then raise exception 'request_not_allowed' using errcode='42501'; end if;
 perform 1 from public.profiles where user_id=actor for update;
 if p_item is null then delete from public.equipped_cosmetics where user_id=actor and slot=p_slot; update public.profiles set updated_at=public.anivibe_now() where user_id=actor; return; end if;
 select i.category into category from public.shop_items i join public.user_inventory u on u.item_id=i.id
 join public.cosmetic_media m on m.id=i.media_id and m.approved where u.user_id=actor and i.id=p_item;
 if category is null or (p_slot='avatar' and category<>'avatar') or (p_slot='banner' and category not in ('banner','animated_banner')) then
  raise exception 'request_not_allowed' using errcode='42501'; end if;
 insert into public.equipped_cosmetics values(actor,p_slot,p_item) on conflict(user_id,slot) do update set item_id=excluded.item_id;
 update public.profiles set updated_at=public.anivibe_now() where user_id=actor;
end $$;
create function public.anivibe_preferences(p_invites text,p_hide boolean) returns void
language plpgsql security definer set search_path='' as $$ begin
 if auth.uid() is null or p_invites is null or p_invites not in ('friends','none') or p_hide is null then raise exception 'request_not_allowed'; end if;
 insert into public.social_preferences values(auth.uid(),p_invites,p_hide) on conflict(user_id) do update
 set invite_policy=excluded.invite_policy,hide_watching=excluded.hide_watching;
end $$;
create function public.anivibe_notification_read(p_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$ begin
 update public.community_notifications set read_at=public.anivibe_now() where id=p_id and user_id=auth.uid() and read_at is null;
 return found;
end $$;
-- Server moderation only; granting an app user a role/admin UI is intentionally deferred.
create function public.anivibe_moderate_comment(p_comment uuid,p_state text,p_reason text) returns void
language plpgsql security definer set search_path='' as $$
declare author uuid; begin
 if p_state is null or p_state not in ('published','hidden') or char_length(btrim(p_reason)) not between 1 and 500 or p_reason is null then raise exception 'moderation_invalid'; end if;
 update public.title_comments set state=p_state where id=p_comment and state<>'deleted' returning author_id into author;
 if not found then raise exception 'comment_missing'; end if;
 insert into public.comment_moderation_audit(comment_id,state,reason) values(p_comment,p_state,btrim(p_reason));
 perform public.anivibe_notice(author,'comment_moderated',jsonb_build_object('comment_id',p_comment,'state',p_state,'reason',btrim(p_reason)),gen_random_uuid()::text);
end $$;

-- Business data is never writable through the REST tables.
do $$ declare tbl text; begin
 foreach tbl in array array['community_rules','social_preferences','friendship_stats','coin_wallets','coin_ledger','friendship_xp_ledger',
  'friend_upgrades','community_notifications','cosmetic_media','shop_items','user_inventory','equipped_cosmetics','shop_receipts','community_daily','comment_moderation_audit'] loop
  execute format('alter table public.%I enable row level security',tbl);
  execute format('revoke all on public.%I from public,anon,authenticated',tbl);
 end loop;
end $$;
grant select on public.social_preferences,public.friendship_stats,public.coin_wallets,public.coin_ledger,public.friendship_xp_ledger,
 public.friend_upgrades,public.community_notifications,public.shop_items,public.cosmetic_media,public.user_inventory,public.equipped_cosmetics,
 public.shop_receipts,public.community_daily to authenticated;
create policy prefs_own on public.social_preferences for select to authenticated using(user_id=auth.uid());
create policy stats_pair on public.friendship_stats for select to authenticated using(auth.uid() in (user_low,user_high));
create policy wallet_own on public.coin_wallets for select to authenticated using(user_id=auth.uid());
create policy coins_own on public.coin_ledger for select to authenticated using(user_id=auth.uid());
create policy xp_pair on public.friendship_xp_ledger for select to authenticated using(auth.uid() in (user_low,user_high));
create policy upgrades_own on public.friend_upgrades for select to authenticated using(user_id=auth.uid());
create policy notifications_own on public.community_notifications for select to authenticated using(user_id=auth.uid());
create policy shop_catalog on public.shop_items for select to authenticated using(active);
create policy media_catalog on public.cosmetic_media for select to authenticated using(approved);
create policy inventory_own on public.user_inventory for select to authenticated using(user_id=auth.uid());
create policy receipts_own on public.shop_receipts for select to authenticated using(user_id=auth.uid());
create policy daily_pair on public.community_daily for select to authenticated using(auth.uid() in (user_low,user_high));
-- RLS helpers cannot be called directly by authenticated clients in the existing project;
-- equipped presentation is exposed through an authenticated privacy-checked RPC instead.
create policy equipped_own on public.equipped_cosmetics for select to authenticated using(user_id=auth.uid());

revoke all on function public.anivibe_now(),public.anivibe_friend_cap(uuid),public.anivibe_notice(uuid,text,jsonb,text),
 public.anivibe_level(numeric),public.anivibe_credit(uuid,integer,text,text) from public,anon,authenticated;
revoke all on function public.anivibe_shop_purchase(text,uuid),public.anivibe_cosmetic_equip(text,text),public.anivibe_preferences(text,boolean),
 public.anivibe_notification_read(uuid),public.anivibe_moderate_comment(uuid,text,text) from public,anon,authenticated;
grant execute on function public.anivibe_shop_purchase(text,uuid),public.anivibe_cosmetic_equip(text,text),public.anivibe_preferences(text,boolean),
 public.anivibe_notification_read(uuid) to authenticated;
grant execute on function public.anivibe_moderate_comment(uuid,text,text) to service_role;
notify pgrst,'reload schema';
commit;
