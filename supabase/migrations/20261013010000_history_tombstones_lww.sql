-- Preserve deleted history across devices and implement server-side last-write-wins.
begin;
alter table public.watch_history add column deleted_at timestamptz;
alter table public.watch_history add column updated_at timestamptz;
update public.watch_history set updated_at = watched_at;
alter table public.watch_history alter column updated_at set default now();
alter table public.watch_history alter column updated_at set not null;
create index watch_history_user_updated_idx on public.watch_history(user_id, updated_at);

-- This replaces the existing BEFORE trigger function used by all three tables.
create or replace function public.anivibe_clamp_timestamp() returns trigger
language plpgsql set search_path = '' as $$
begin
    if new.updated_at > now() + interval '5 minutes' then new.updated_at := now(); end if;
    if tg_table_name = 'watch_history' then
        if new.watched_at > now() + interval '5 minutes' then new.watched_at := now(); end if;
        if new.deleted_at > now() + interval '5 minutes' then new.deleted_at := now(); end if;
    end if;
    if tg_op = 'UPDATE' and new.updated_at <= old.updated_at then return old; end if;
    return new;
end;
$$;
commit;
