begin;
create table public.canonical_anime (
 id uuid primary key default gen_random_uuid(), anilist_id bigint unique check(anilist_id>0), title text not null,
 created_at timestamptz not null default now()
);
create table public.canonical_episodes (
 id uuid primary key default gen_random_uuid(), anime_id uuid not null references public.canonical_anime on delete cascade,
 catalog_key text not null, label text not null, kind text not null check(kind in ('episode','special','movie','part')),
 sort_order integer not null, duration numeric check(duration between 30 and 21600),
 duration_verified boolean not null default false, unique(anime_id,catalog_key), unique(anime_id,sort_order),
 check(not duration_verified or duration is not null)
);
-- Explicit operator-curated identity, never inferred from an ordinal or a video URL.
create table public.episode_source_mappings (
 id uuid primary key default gen_random_uuid(), episode_id uuid not null references public.canonical_episodes on delete cascade,
 provider_id text not null, source_identity text not null, voice text not null default '',
 source_episode jsonb not null check(jsonb_typeof(source_episode)='object'),
 source_offset numeric not null default 0 check(source_offset between -300 and 300),
 source_duration numeric check(source_duration between 30 and 22000), verified boolean not null default false,
 unique(provider_id,source_identity,voice),
 check(not verified or source_duration is not null)
);
create table public.watch_sessions (
 id uuid primary key default gen_random_uuid(), host_id uuid not null references public.profiles on delete cascade,
 guest_id uuid not null references public.profiles on delete cascade, episode_id uuid not null references public.canonical_episodes,
 status text not null default 'invited' check(status in ('invited','active','closed')),
 wants_play boolean not null default false, playback text not null default 'waiting' check(playback in ('playing','paused','waiting','ended')),
 anchor_position numeric not null default 0 check(anchor_position>=0), anchor_at timestamptz not null default now(),
 revision bigint not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '10 minutes', check(host_id<>guest_id)
);
create index watch_sessions_participants on public.watch_sessions(host_id,guest_id,status);
create table public.watch_session_members (
 session_id uuid references public.watch_sessions on delete cascade, user_id uuid references public.profiles on delete cascade,
 mapping_id uuid references public.episode_source_mappings, state text not null default 'unavailable' check(state in ('ready','playing','paused','buffering','ended','unavailable')),
 last_seen timestamptz, duration_valid boolean not null default false, client_id uuid, sequence bigint not null default -1,
 primary key(session_id,user_id)
);
-- One accepted room per account. Row-level locks serialize cross-room accepts.
create table public.watch_presence (
 user_id uuid primary key references public.profiles on delete cascade, session_id uuid references public.watch_sessions on delete set null
);
create table public.watch_member_progress (
 session_id uuid references public.watch_sessions on delete cascade, user_id uuid references public.profiles on delete cascade,
 episode_id uuid references public.canonical_episodes, mapping_id uuid references public.episode_source_mappings,
 timeline nummultirange not null default '{}', played_at tstzmultirange not null default '{}',
 last_at timestamptz, last_position numeric, last_state text, confirmed_end numeric not null default 0,
 primary key(session_id,user_id,episode_id)
);
create table public.watch_events (
 session_id uuid references public.watch_sessions on delete cascade, user_id uuid references public.profiles on delete cascade,
 event_id uuid, created_at timestamptz not null default now(), primary key(session_id,user_id,event_id)
);
create table public.episode_progress (
 user_id uuid references public.profiles on delete cascade, episode_id uuid references public.canonical_episodes,
 timeline nummultirange not null default '{}', completed_at timestamptz, primary key(user_id,episode_id)
);
create table public.shared_episode_completions (
 id uuid primary key default gen_random_uuid(), user_low uuid not null, user_high uuid not null,
 episode_id uuid not null references public.canonical_episodes, session_id uuid not null references public.watch_sessions,
 policy_version integer not null, completed_at timestamptz not null default now(),
 unique(user_low,user_high,episode_id),
 foreign key(user_low,user_high) references public.friendship_stats on delete cascade
);
-- Rewatch policy v1: ONE lifetime reward per pair+canonical episode, across sessions/voices/refriending.
-- Policy_version records the rule used; a rule change does NOT unlock historical rewards.
create function public.anivibe_timeline_seconds(p_ranges nummultirange) returns numeric language sql immutable set search_path='' as $$
 select coalesce(sum(upper(r)-lower(r)),0) from unnest(p_ranges) r
$$;
create function public.anivibe_overlap_seconds(p_ranges tstzmultirange) returns numeric language sql immutable set search_path='' as $$
 select coalesce(sum(extract(epoch from upper(r)-lower(r))),0) from unnest(p_ranges) r
$$;
create function public.anivibe_watch_position(p_room public.watch_sessions,p_now timestamptz) returns numeric
language sql stable set search_path='' as $$
 select least(coalesce(e.duration,21600),(p_room).anchor_position+case when (p_room).playback='playing' then
  greatest(0,extract(epoch from least(p_now,coalesce((select min(last_seen) from public.watch_session_members where session_id=(p_room).id),(p_room).anchor_at)
   + make_interval(secs=>(select presence_seconds from public.community_rules))) - (p_room).anchor_at)) else 0 end)
 from public.canonical_episodes e where e.id=(p_room).episode_id
$$;
create function public.anivibe_watch_refresh(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare s public.watch_sessions; n timestamptz:=public.anivibe_now(); mode text; pos numeric; ttl integer;
begin
 select * into s from public.watch_sessions where id=p_id for update;
 select presence_seconds into ttl from public.community_rules;
 pos:=public.anivibe_watch_position(s,n);
 mode:=case when (select count(*) from public.watch_session_members where session_id=s.id and state='ended')=2 then 'ended' when not s.wants_play then 'paused' when
  (select count(*) from public.watch_session_members where session_id=s.id and mapping_id is not null and state in ('ready','playing','paused')
   and last_seen>n-make_interval(secs=>ttl))=2 then 'playing' else 'waiting' end;
 update public.watch_sessions set anchor_position=pos,anchor_at=n,playback=mode,updated_at=n,
  revision=revision+case when playback<>mode then 1 else 0 end,expires_at=n+interval '5 minutes' where id=p_id;
end $$;
create function public.anivibe_watch_snapshot(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.watch_sessions; e public.canonical_episodes; a public.canonical_anime; n timestamptz:=public.anivibe_now();
 ttl integer; effective text; lo uuid; hi uuid; d numeric; overlap numeric;
begin
 select * into s from public.watch_sessions where id=p_id;
 select * into e from public.canonical_episodes where id=s.episode_id;
 select * into a from public.canonical_anime where id=e.anime_id;
 select presence_seconds into ttl from public.community_rules;
 lo:=least(s.host_id,s.guest_id); hi:=greatest(s.host_id,s.guest_id);
 effective:=case when s.expires_at<n or s.status='closed' then 'ended' when (select count(*) from public.watch_session_members where session_id=s.id and state='ended')=2 then 'ended' when not s.wants_play then 'paused' when
  (select count(*) from public.watch_session_members where session_id=s.id and mapping_id is not null and state in ('ready','playing','paused') and last_seen>n-make_interval(secs=>ttl))=2
  then s.playback else 'waiting' end;
 select public.anivibe_overlap_seconds(l.played_at*h.played_at) into overlap
  from public.watch_member_progress l join public.watch_member_progress h using(session_id,episode_id)
  where l.session_id=s.id and l.episode_id=s.episode_id and l.user_id=lo and h.user_id=hi;
 d:=case when e.duration_verified then e.duration else null end;
 return jsonb_build_object('id',s.id,'host_id',s.host_id,'guest_id',s.guest_id,'status',case when s.expires_at<n then 'closed' else s.status end,
  'episode_id',e.id,'anime_id',a.id,'anilist_id',a.anilist_id,'anime_title',a.title,'episode_label',e.label,'episode_order',e.sort_order,
  'playback',effective,'wants_play',s.wants_play,'position',public.anivibe_watch_position(s,n),'server_time',extract(epoch from n),'revision',s.revision,
  'duration',e.duration,'rewards_eligible',e.duration_verified and (select count(*) from public.watch_session_members where session_id=s.id and duration_valid)=2,
  'reward_block_reason',case when not e.duration_verified then 'untrusted_duration'
   when (select count(*) from public.watch_session_members m join public.episode_source_mappings sm on sm.id=m.mapping_id and sm.verified where m.session_id=s.id)<2 then 'untrusted_source'
   when (select count(*) from public.watch_session_members where session_id=s.id and duration_valid)<2 then 'awaiting_duration' else null end,
  'overlap_progress',case when d>0 then least(1,coalesce(overlap,0)/d) else 0 end,
  'completion_ratio',(select completion_ratio from public.community_rules),'overlap_ratio',(select overlap_ratio from public.community_rules),
  'rewarded',exists(select 1 from public.shared_episode_completions where user_low=lo and user_high=hi and episode_id=e.id),
  'members',coalesce((select jsonb_agg(jsonb_build_object('user_id',m.user_id,'mapping_id',m.mapping_id,'state',m.state,
   'online',m.last_seen>n-make_interval(secs=>ttl),'watched_progress',case when d>0 then least(1,public.anivibe_timeline_seconds(p.timeline)/d) else 0 end))
   from public.watch_session_members m left join public.watch_member_progress p on p.session_id=m.session_id and p.user_id=m.user_id and p.episode_id=e.id where m.session_id=s.id),'[]'::jsonb));
end $$;
create function public.anivibe_watch_award(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare s public.watch_sessions; e public.canonical_episodes; rules public.community_rules;
 lo uuid; hi uuid; lp public.watch_member_progress; hp public.watch_member_progress; reward_id uuid; day_key date; daily public.community_daily;
 before_level integer; after_level integer; key text; xp_add integer; coin_add integer; n timestamptz:=public.anivibe_now();
begin
 select * into s from public.watch_sessions where id=p_id for update;
 select * into rules from public.community_rules;
 select * into e from public.canonical_episodes where id=s.episode_id;
 if not e.duration_verified or e.duration is null or s.status<>'active' then return; end if;
 lo:=least(s.host_id,s.guest_id); hi:=greatest(s.host_id,s.guest_id);
 if not exists(select 1 from public.friendships where user_low=lo and user_high=hi and status='accepted') then return; end if;
 select * into lp from public.watch_member_progress where session_id=s.id and user_id=lo and episode_id=e.id;
 select * into hp from public.watch_member_progress where session_id=s.id and user_id=hi and episode_id=e.id;
 if lp.user_id is null or hp.user_id is null or
  public.anivibe_timeline_seconds(lp.timeline)<e.duration*rules.completion_ratio or public.anivibe_timeline_seconds(hp.timeline)<e.duration*rules.completion_ratio or
  lp.confirmed_end<e.duration*rules.completion_ratio or hp.confirmed_end<e.duration*rules.completion_ratio or
  public.anivibe_overlap_seconds(lp.played_at*hp.played_at)<e.duration*rules.overlap_ratio then return; end if;
 insert into public.friendship_stats(user_low,user_high) values(lo,hi) on conflict do nothing;
 perform 1 from public.friendship_stats where user_low=lo and user_high=hi for update;
 insert into public.shared_episode_completions(user_low,user_high,episode_id,session_id,policy_version,completed_at)
 values(lo,hi,e.id,s.id,rules.policy_version,n) on conflict do nothing returning id into reward_id;
 if reward_id is null then return; end if;
 key:='episode:'||reward_id;
 select (public.anivibe_level(xp)->>'level')::integer into before_level from public.friendship_stats where user_low=lo and user_high=hi;
 update public.friendship_stats set xp=xp+rules.episode_xp,episodes=episodes+1,last_watch_at=n where user_low=lo and user_high=hi;
 if rules.episode_xp>0 then insert into public.friendship_xp_ledger(user_low,user_high,amount,reason,event_key) values(lo,hi,rules.episode_xp,'episode',key); end if;
 -- Acquiring wallet locks in sorted order also serializes with concurrent purchases.
 perform public.anivibe_credit(lo,rules.episode_coins,'episode',key);
 perform public.anivibe_credit(hi,rules.episode_coins,'episode',key);
 day_key:=(n at time zone rules.daily_timezone)::date;
 insert into public.community_daily(user_low,user_high,day,completed) values(lo,hi,day_key,1) on conflict(user_low,user_high,day)
  do update set completed=community_daily.completed+1 returning * into daily;
 if not daily.rewarded and daily.completed>=rules.daily_goal then
  update public.community_daily set rewarded=true where user_low=lo and user_high=hi and day=day_key;
  key:='daily:'||lo||':'||hi||':'||day_key;
  update public.friendship_stats set xp=xp+rules.daily_xp where user_low=lo and user_high=hi;
  if rules.daily_xp>0 then insert into public.friendship_xp_ledger(user_low,user_high,amount,reason,event_key) values(lo,hi,rules.daily_xp,'daily',key); end if;
  perform public.anivibe_credit(lo,rules.daily_coins,'daily',key); perform public.anivibe_credit(hi,rules.daily_coins,'daily',key);
  perform public.anivibe_notice(lo,'daily_reward',jsonb_build_object('peer_id',hi,'xp',rules.daily_xp,'coins',rules.daily_coins),key);
  perform public.anivibe_notice(hi,'daily_reward',jsonb_build_object('peer_id',lo,'xp',rules.daily_xp,'coins',rules.daily_coins),key);
 end if;
 perform public.anivibe_notice(lo,'episode_reward',jsonb_build_object('peer_id',hi,'episode_id',e.id,'xp',rules.episode_xp,'coins',rules.episode_coins),'episode:'||reward_id);
 perform public.anivibe_notice(hi,'episode_reward',jsonb_build_object('peer_id',lo,'episode_id',e.id,'xp',rules.episode_xp,'coins',rules.episode_coins),'episode:'||reward_id);
 select (public.anivibe_level(xp)->>'level')::integer into after_level from public.friendship_stats where user_low=lo and user_high=hi;
 if after_level>before_level then
  perform public.anivibe_notice(lo,'level_up',jsonb_build_object('peer_id',hi,'level',after_level),'level:'||lo||':'||hi||':'||after_level);
  perform public.anivibe_notice(hi,'level_up',jsonb_build_object('peer_id',lo,'level',after_level),'level:'||lo||':'||hi||':'||after_level);
 end if;
end $$;
create function public.anivibe_watch_invite(p_peer uuid,p_episode uuid,p_mapping uuid,p_request uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); s public.watch_sessions; lo uuid:=least(actor,p_peer); hi uuid:=greatest(actor,p_peer); n timestamptz:=public.anivibe_now();
begin
 if actor is null or p_peer is null or actor=p_peer or p_request is null then raise exception 'request_not_allowed' using errcode='42501'; end if;
 perform user_id from public.profiles where user_id in (lo,hi) order by user_id for update;
 select * into s from public.watch_sessions where id=p_request;
 if found then
  if s.host_id<>actor or s.guest_id<>p_peer or s.episode_id<>p_episode then raise exception 'request_conflict'; end if;
  return public.anivibe_watch_snapshot(s.id);
 end if;
 if not exists(select 1 from public.friendships where user_low=lo and user_high=hi and status='accepted') or
  exists(select 1 from public.social_preferences where user_id=p_peer and invite_policy='none') then raise exception 'invites_disabled'; end if;
 if not exists(select 1 from public.episode_source_mappings where id=p_mapping and episode_id=p_episode) then raise exception 'mapping_missing'; end if;
 if (select count(*) from public.watch_sessions where host_id=actor and status='invited' and expires_at>n)>=5 or
  exists(select 1 from public.watch_sessions where host_id=actor and created_at>n-interval '10 seconds') then raise exception 'request_rate_limited'; end if;
 insert into public.watch_sessions(id,host_id,guest_id,episode_id,anchor_at,created_at,updated_at,expires_at)
 values(p_request,actor,p_peer,p_episode,n,n,n,n+interval '10 minutes');
 insert into public.watch_session_members(session_id,user_id,mapping_id) values(p_request,actor,p_mapping),(p_request,p_peer,null);
 perform public.anivibe_notice(p_peer,'watch_invite',jsonb_build_object('session_id',p_request,'peer_id',actor),'invite:'||p_request);
 return public.anivibe_watch_snapshot(p_request);
end $$;
create function public.anivibe_watch_get(p_session uuid) returns jsonb language plpgsql security definer set search_path='' as $$ begin
 if auth.uid() is null or not exists(select 1 from public.watch_sessions where id=p_session and auth.uid() in (host_id,guest_id)) then
  raise exception 'request_not_allowed' using errcode='42501'; end if;
 return public.anivibe_watch_snapshot(p_session);
end $$;
create function public.anivibe_watch_action(p_session uuid,p_action text,p_value numeric default null,p_episode uuid default null,p_mapping uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); s public.watch_sessions; n timestamptz:=public.anivibe_now(); peer uuid; active_room uuid; person uuid; d numeric;
begin
 if actor is null or p_action is null or p_action not in ('accept','decline','leave','play','pause','seek','next','source') then raise exception 'request_not_allowed'; end if;
 -- Read endpoints, lock ordered presence BEFORE room to avoid cross-room accept deadlocks.
 select * into s from public.watch_sessions where id=p_session and actor in (host_id,guest_id);
 if not found then raise exception 'request_not_allowed' using errcode='42501'; end if;
 insert into public.watch_presence(user_id) values(s.host_id),(s.guest_id) on conflict do nothing;
 perform user_id from public.watch_presence where user_id in (s.host_id,s.guest_id) order by user_id for update;
 select * into s from public.watch_sessions where id=p_session for update;
 if s.status='closed' or s.expires_at<n then
  if p_action in ('leave','decline') then return public.anivibe_watch_snapshot(p_session); end if;
  raise exception 'session_expired'; end if;
 if p_action in ('leave','decline') then
  if p_action='decline' and actor<>s.guest_id then raise exception 'request_not_allowed'; end if;
  update public.watch_sessions set status='closed',wants_play=false,playback='ended',revision=revision+1,updated_at=n where id=p_session;
  update public.watch_presence set session_id=null where session_id=p_session;
  return public.anivibe_watch_snapshot(p_session);
 end if;
 if not exists(select 1 from public.friendships where user_low=least(s.host_id,s.guest_id) and user_high=greatest(s.host_id,s.guest_id) and status='accepted') then raise exception 'request_not_allowed'; end if;
 if p_action='accept' then
  if actor<>s.guest_id then raise exception 'request_not_allowed'; end if;
  if s.status='active' then return public.anivibe_watch_snapshot(p_session); end if;
  for person in select user_id from public.watch_presence where user_id in (s.host_id,s.guest_id) order by user_id loop
   select session_id into active_room from public.watch_presence where user_id=person;
   if active_room is not null and exists(select 1 from public.watch_sessions where id=active_room and status='active' and expires_at>n) then raise exception 'already_in_session'; end if;
  end loop;
  if not exists(select 1 from public.episode_source_mappings where id=p_mapping and episode_id=s.episode_id) then raise exception 'mapping_missing'; end if;
  update public.watch_session_members set mapping_id=p_mapping,state='unavailable',duration_valid=false,last_seen=null where session_id=p_session and user_id=actor;
  update public.watch_presence set session_id=p_session where user_id in (s.host_id,s.guest_id);
  update public.watch_sessions set status='active',expires_at=n+interval '5 minutes',updated_at=n,revision=revision+1 where id=p_session;
 else
  if s.status<>'active' then raise exception 'session_not_active'; end if;
  if p_action='source' then
   if not exists(select 1 from public.episode_source_mappings where id=p_mapping and episode_id=s.episode_id) then raise exception 'mapping_missing'; end if;
   update public.watch_session_members set mapping_id=p_mapping,state='unavailable',duration_valid=false,last_seen=n where session_id=p_session and user_id=actor;
  elsif p_action='next' then
   if actor<>s.host_id or not exists(select 1 from public.canonical_episodes e join public.canonical_episodes old on old.anime_id=e.anime_id
    where e.id=p_episode and old.id=s.episode_id and e.sort_order>old.sort_order) then raise exception 'episode_invalid'; end if;
   update public.watch_sessions set episode_id=p_episode,anchor_position=0,anchor_at=n,wants_play=false,playback='waiting',revision=revision+1 where id=p_session;
   update public.watch_session_members set mapping_id=null,state='unavailable',duration_valid=false,last_seen=null where session_id=p_session;
  elsif p_action='seek' then
   select coalesce(duration,21600) into d from public.canonical_episodes where id=s.episode_id;
   if p_value is null or p_value::text in ('NaN','Infinity','-Infinity') or p_value<0 or p_value>d then raise exception 'position_invalid'; end if;
   update public.watch_sessions set anchor_position=p_value,anchor_at=n,revision=revision+1 where id=p_session;
   update public.watch_member_progress set last_at=null,last_state='ready' where session_id=p_session and episode_id=s.episode_id;
  else
   update public.watch_sessions set wants_play=(p_action='play'),revision=revision+1 where id=p_session;
  end if;
  perform public.anivibe_watch_refresh(p_session);
 end if;
 return public.anivibe_watch_snapshot(p_session);
end $$;
create function public.anivibe_watch_heartbeat(p_session uuid,p_episode uuid,p_mapping uuid,p_event uuid,p_client uuid,p_sequence bigint,
 p_position numeric,p_duration numeric,p_state text,p_rate numeric default 1) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); s public.watch_sessions; m public.watch_session_members; map public.episode_source_mappings;
 e public.canonical_episodes; prog public.watch_member_progress; rules public.community_rules; n timestamptz:=public.anivibe_now();
 pos numeric; dt numeric; advance numeric; credit numeric; timeline_part nummultirange; fresh_part nummultirange; wall_part tstzmultirange; segment numrange;
begin
 if actor is null or p_event is null or p_client is null or p_sequence is null or p_sequence<0 or
  p_state is null or p_state not in ('ready','playing','paused','buffering','ended','unavailable') or p_position is null or
  p_position::text in ('NaN','Infinity','-Infinity') or p_position not between 0 and 22000 or
  p_rate is null or p_rate::text in ('NaN','Infinity','-Infinity') or p_rate not between .25 and 3 then raise exception 'progress_invalid'; end if;
 select * into s from public.watch_sessions where id=p_session and actor in (host_id,guest_id) for update;
 if not found then raise exception 'request_not_allowed' using errcode='42501'; end if;
 if s.status<>'active' or s.expires_at<n then raise exception 'session_expired'; end if;
 if not exists(select 1 from public.friendships where user_low=least(s.host_id,s.guest_id) and user_high=greatest(s.host_id,s.guest_id) and status='accepted') then raise exception 'request_not_allowed'; end if;
 if p_episode<>s.episode_id or p_episode is null then return public.anivibe_watch_snapshot(p_session); end if;
 select * into m from public.watch_session_members where session_id=p_session and user_id=actor;
 if exists(select 1 from public.watch_events where session_id=p_session and user_id=actor and event_id=p_event) or
  (m.client_id=p_client and p_sequence<=m.sequence) then return public.anivibe_watch_snapshot(p_session); end if;
 select * into map from public.episode_source_mappings where id=p_mapping and episode_id=p_episode;
 if not found or m.mapping_id is distinct from p_mapping then raise exception 'mapping_missing'; end if;
 select * into e from public.canonical_episodes where id=p_episode;
 select * into rules from public.community_rules;
 insert into public.watch_events(session_id,user_id,event_id,created_at) values(p_session,actor,p_event,n);
 insert into public.watch_member_progress(session_id,user_id,episode_id,mapping_id) values(p_session,actor,p_episode,p_mapping) on conflict do nothing;
 select * into prog from public.watch_member_progress where session_id=p_session and user_id=actor and episode_id=p_episode;
 pos:=greatest(0,least(coalesce(e.duration,21600),p_position-map.source_offset));
 dt:=extract(epoch from n-prog.last_at); advance:=pos-prog.last_position;
 -- Only plausible forward 1x playback using SERVER elapsed time. Seeks, replay, missing duration,
 -- stale heartbeats, wrong voice mapping, pauses and buffering cannot claim elapsed time.
 if s.wants_play and s.playback='playing' and map.verified and e.duration_verified and p_duration is not null and p_duration::text not in ('NaN','Infinity','-Infinity')
  and abs(p_duration-map.source_duration)<=greatest(3,map.source_duration*.02)
  and prog.mapping_id=p_mapping and m.client_id=p_client and prog.last_state='playing' and p_state in ('playing','paused','ended')
  and p_rate=1 and dt between .1 and rules.heartbeat_max_seconds and advance>0 and advance<=dt+1.5 then
  credit:=least(advance,dt);
  timeline_part:=nummultirange(numrange(prog.last_position,least(pos,prog.last_position+credit),'[)'));
  -- A replayed timeline segment must NOT increase simultaneous verified time either.
  fresh_part:=timeline_part-prog.timeline;
  wall_part:='{}'::tstzmultirange;
  for segment in select unnest(fresh_part) loop
   wall_part:=wall_part+tstzmultirange(tstzrange(
    n-make_interval(secs=>(prog.last_position+credit-lower(segment))::double precision),
    n-make_interval(secs=>(prog.last_position+credit-upper(segment))::double precision),'[)'));
  end loop;
  update public.watch_member_progress set timeline=timeline+timeline_part,played_at=played_at+wall_part,
   confirmed_end=greatest(confirmed_end,least(pos,prog.last_position+credit)) where session_id=p_session and user_id=actor and episode_id=p_episode;
  insert into public.episode_progress(user_id,episode_id,timeline) values(actor,p_episode,timeline_part)
   on conflict(user_id,episode_id) do update set timeline=episode_progress.timeline+excluded.timeline;
  update public.episode_progress set completed_at=coalesce(completed_at,n) where user_id=actor and episode_id=p_episode
   and public.anivibe_timeline_seconds(timeline)>=e.duration*rules.completion_ratio;
 end if;
 update public.watch_member_progress set mapping_id=p_mapping,last_at=n,last_position=pos,last_state=p_state where session_id=p_session and user_id=actor and episode_id=p_episode;
 -- Freeze/extrapolate previous anchor BEFORE changing availability, then recompute both-member readiness.
 perform public.anivibe_watch_refresh(p_session);
 update public.watch_session_members set state=p_state,last_seen=n,duration_valid=coalesce(e.duration_verified and map.verified and p_duration is not null and p_duration::text not in ('NaN','Infinity','-Infinity') and abs(p_duration-map.source_duration)<=greatest(3,map.source_duration*.02),false),client_id=p_client,sequence=p_sequence where session_id=p_session and user_id=actor;
 perform public.anivibe_watch_refresh(p_session);
 perform public.anivibe_watch_award(p_session);
 return public.anivibe_watch_snapshot(p_session);
end $$;
-- Cron may call this as service_role. Expiration is also checked on every read/mutation.
create function public.anivibe_watch_cleanup() returns integer language plpgsql security definer set search_path='' as $$
declare removed integer; begin
 update public.watch_sessions set status='closed',playback='ended',wants_play=false,revision=revision+1 where status<>'closed' and expires_at<public.anivibe_now();
 get diagnostics removed=row_count;
 update public.watch_presence p set session_id=null where exists(select 1 from public.watch_sessions s where s.id=p.session_id and s.status='closed');
 delete from public.watch_events where created_at<public.anivibe_now()-interval '30 days';
 return removed;
end $$;

create function public.anivibe_episode_catalog(p_anilist bigint default null,p_after integer default 0,p_limit integer default 100) returns jsonb
language plpgsql stable security definer set search_path='' as $$ begin
 if auth.uid() is null then raise exception 'request_not_allowed'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'anime_id',a.id,'anilist_id',a.anilist_id,'anime_title',a.title,
  'label',e.label,'kind',e.kind,'sort_order',e.sort_order,'duration',e.duration,'verified',e.duration_verified,
  'sources',(select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'provider_id',m.provider_id,'voice',m.voice,'source_offset',m.source_offset,
  'source_episode',m.source_episode,'verified',m.verified) order by m.provider_id,m.voice),'[]'::jsonb) from public.episode_source_mappings m where m.episode_id=e.id)) order by a.title,e.sort_order)
  from (select ep.* from public.canonical_episodes ep join public.canonical_anime ca on ca.id=ep.anime_id
   where ca.anilist_id=p_anilist and ep.sort_order>greatest(0,p_after)
    and exists(select 1 from public.episode_source_mappings where episode_id=ep.id)
   order by ep.sort_order limit greatest(1,least(200,p_limit))) e join public.canonical_anime a on a.id=e.anime_id),'[]'::jsonb);
end $$;
create function public.anivibe_community_hub() returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); rules public.community_rules; n timestamptz:=public.anivibe_now(); day_key date;
begin
 if actor is null then raise exception 'request_not_allowed' using errcode='42501'; end if;
 select * into rules from public.community_rules; day_key:=(n at time zone rules.daily_timezone)::date;
 return jsonb_build_object('user_id',actor,'balance',coalesce((select balance from public.coin_wallets where user_id=actor),0),
  'friend_cap',public.anivibe_friend_cap(actor),'day',day_key,'daily_goal',rules.daily_goal,'daily_xp',rules.daily_xp,'daily_coins',rules.daily_coins,
  'invite_policy',coalesce((select invite_policy from public.social_preferences where user_id=actor),'friends'),
  'hide_watching',coalesce((select hide_watching from public.social_preferences where user_id=actor),false),
  'unique_episodes',(select count(*) from public.episode_progress where user_id=actor and completed_at is not null),
  'friends',coalesce((select jsonb_agg(jsonb_build_object('peer_id',p.user_id,'name',p.display_name,'username',p.username,'avatar_path',p.avatar_path,
   'level',public.anivibe_level(coalesce(st.xp,0)),'episodes',coalesce(st.episodes,0),'started_at',coalesce(st.started_at,f.created_at),
   'last_watch_at',st.last_watch_at,'daily_completed',coalesce(d.completed,0),'daily_rewarded',coalesce(d.rewarded,false),
   'watching',case when coalesce(pref.hide_watching,false) then null else exists(select 1 from public.watch_sessions w where p.user_id in(w.host_id,w.guest_id) and w.status='active' and w.playback='playing' and w.expires_at>n and w.updated_at>n-make_interval(secs=>rules.presence_seconds)) end)
   order by p.display_name) from public.friendships f join public.profiles p on p.user_id=case when f.user_low=actor then f.user_high else f.user_low end
   left join public.friendship_stats st using(user_low,user_high) left join public.community_daily d on d.user_low=f.user_low and d.user_high=f.user_high and d.day=day_key
   left join public.social_preferences pref on pref.user_id=p.user_id where f.status='accepted' and actor in (f.user_low,f.user_high)),'[]'::jsonb),
  'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'category',i.category,'price',i.price,'cap',i.cap,'prerequisite',i.prerequisite,
   'asset_key',case when m.approved then m.asset_key end,'poster_key',case when m.approved then m.poster_key end,'mime',m.mime,'available',i.active and (i.media_id is null or m.approved),'owned',exists(select 1 from public.user_inventory u where u.user_id=actor and u.item_id=i.id),
   'equipped',exists(select 1 from public.equipped_cosmetics eq where eq.user_id=actor and eq.item_id=i.id)) order by i.category,i.price)
   from public.shop_items i left join public.cosmetic_media m on m.id=i.media_id where (i.active and (i.media_id is null or m.approved)) or exists(select 1 from public.user_inventory own where own.user_id=actor and own.item_id=i.id)),'[]'::jsonb),
  'sessions',coalesce((select jsonb_agg(public.anivibe_watch_snapshot(q.id)) from (select id from public.watch_sessions where actor in(host_id,guest_id) and status in('invited','active') and expires_at>n order by updated_at desc limit 20) q),'[]'::jsonb),
  'notifications',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'kind',q.kind,'created_at',q.created_at,'read',q.read_at is not null,'payload',q.payload) order by q.created_at desc)
   from (select * from public.community_notifications where user_id=actor order by created_at desc limit 50) q),'[]'::jsonb));
end $$;
create function public.anivibe_cosmetic_profile(p_user uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$ begin
 if auth.uid() is null or not public.anivibe_can_view_profile(p_user) then raise exception 'request_not_allowed' using errcode='42501'; end if;
 return coalesce((select jsonb_object_agg(eq.slot,jsonb_build_object('asset_key',m.asset_key,'poster_key',m.poster_key,'mime',m.mime)) from public.equipped_cosmetics eq
 join public.shop_items i on i.id=eq.item_id join public.cosmetic_media m on m.id=i.media_id where eq.user_id=p_user and m.approved),'{}'::jsonb);
end $$;

do $$ declare tbl text; begin
 foreach tbl in array array['canonical_anime','canonical_episodes','episode_source_mappings','watch_sessions','watch_session_members','watch_presence',
  'watch_member_progress','watch_events','episode_progress','shared_episode_completions'] loop
  execute format('alter table public.%I enable row level security',tbl);
  execute format('revoke all on public.%I from public,anon,authenticated',tbl);
 end loop;
end $$;
-- Realtime invalidates state; the UI refetches the authorized snapshot RPC, not raw client claims.
grant select on public.watch_sessions,public.watch_session_members,public.episode_progress,public.shared_episode_completions to authenticated;
create policy watch_pair on public.watch_sessions for select to authenticated using(auth.uid() in(host_id,guest_id));
create policy members_pair on public.watch_session_members for select to authenticated using(exists(select 1 from public.watch_sessions s where s.id=session_id and auth.uid() in(s.host_id,s.guest_id)));
create policy progress_own on public.episode_progress for select to authenticated using(user_id=auth.uid());
create policy completions_pair on public.shared_episode_completions for select to authenticated using(auth.uid() in(user_low,user_high));
revoke all on function public.anivibe_timeline_seconds(nummultirange),public.anivibe_overlap_seconds(tstzmultirange),
 public.anivibe_watch_position(public.watch_sessions,timestamptz),public.anivibe_watch_refresh(uuid),public.anivibe_watch_snapshot(uuid),public.anivibe_watch_award(uuid) from public,anon,authenticated;
revoke all on function public.anivibe_watch_invite(uuid,uuid,uuid,uuid),public.anivibe_watch_get(uuid),public.anivibe_watch_action(uuid,text,numeric,uuid,uuid),
 public.anivibe_watch_heartbeat(uuid,uuid,uuid,uuid,uuid,bigint,numeric,numeric,text,numeric),public.anivibe_watch_cleanup(),
 public.anivibe_episode_catalog(bigint,integer,integer),public.anivibe_community_hub(),public.anivibe_cosmetic_profile(uuid) from public,anon,authenticated;
grant execute on function public.anivibe_watch_invite(uuid,uuid,uuid,uuid),public.anivibe_watch_get(uuid),public.anivibe_watch_action(uuid,text,numeric,uuid,uuid),
 public.anivibe_watch_heartbeat(uuid,uuid,uuid,uuid,uuid,bigint,numeric,numeric,text,numeric),public.anivibe_episode_catalog(bigint,integer,integer),
 public.anivibe_community_hub(),public.anivibe_cosmetic_profile(uuid) to authenticated;
grant execute on function public.anivibe_watch_cleanup() to service_role;
do $$ declare tbl text; begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  foreach tbl in array array['watch_sessions','community_notifications'] loop
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=tbl) then
    execute format('alter publication supabase_realtime add table public.%I',tbl);
   end if;
  end loop;
 end if;
end $$;
notify pgrst,'reload schema';
commit;
