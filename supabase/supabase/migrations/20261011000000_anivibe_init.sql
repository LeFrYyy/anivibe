-- Anivibe: личная библиотека, прогресс и история просмотра.
-- Каждая строка принадлежит пользователю (auth.users). RLS: доступ только к своим данным.

create table if not exists public.library_entries (
    user_id       uuid        not null default auth.uid() references auth.users (id) on delete cascade,
    anime_id      integer     not null check (anime_id > 0),
    title         text        not null check (char_length(title) between 1 and 500),
    cover_url     text        check (cover_url is null or cover_url ~ '^https://'),
    episode_count integer     check (episode_count is null or episode_count between 0 and 10000),
    status        text        check (status is null or status in ('watching', 'completed', 'planned', 'onHold')),
    is_favorite   boolean     not null default false,
    last_episode  integer     check (last_episode is null or last_episode between 1 and 10000),
    is_deleted    boolean     not null default false,
    updated_at    timestamptz not null default now(),
    primary key (user_id, anime_id)
);

create table if not exists public.watch_progress (
    user_id          uuid             not null default auth.uid() references auth.users (id) on delete cascade,
    anime_id         integer          not null check (anime_id > 0),
    episode          integer          not null check (episode between 1 and 10000),
    position_seconds double precision not null check (position_seconds >= 0 and position_seconds < 86400),
    duration_seconds double precision not null check (duration_seconds >= 0 and duration_seconds < 86400),
    updated_at       timestamptz      not null default now(),
    primary key (user_id, anime_id, episode)
);

create table if not exists public.watch_history (
    id         uuid        primary key,
    user_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
    anime_id   integer     not null check (anime_id > 0),
    title      text        not null check (char_length(title) between 1 and 500),
    cover_url  text        check (cover_url is null or cover_url ~ '^https://'),
    episode    integer     not null check (episode between 1 and 10000),
    watched_at timestamptz not null default now()
);

-- Индексы для инкрементальной синхронизации («изменения после даты»).
create index if not exists library_entries_user_updated_idx on public.library_entries (user_id, updated_at);
create index if not exists watch_progress_user_updated_idx on public.watch_progress (user_id, updated_at);
create index if not exists watch_history_user_watched_idx on public.watch_history (user_id, watched_at);

-- Row Level Security: пользователь видит и меняет только свои строки.
alter table public.library_entries enable row level security;
alter table public.watch_progress  enable row level security;
alter table public.watch_history   enable row level security;

create policy "library_entries: select own" on public.library_entries
    for select to authenticated using ((select auth.uid()) = user_id);
create policy "library_entries: insert own" on public.library_entries
    for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "library_entries: update own" on public.library_entries
    for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "library_entries: delete own" on public.library_entries
    for delete to authenticated using ((select auth.uid()) = user_id);

create policy "watch_progress: select own" on public.watch_progress
    for select to authenticated using ((select auth.uid()) = user_id);
create policy "watch_progress: insert own" on public.watch_progress
    for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "watch_progress: update own" on public.watch_progress
    for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "watch_progress: delete own" on public.watch_progress
    for delete to authenticated using ((select auth.uid()) = user_id);

create policy "watch_history: select own" on public.watch_history
    for select to authenticated using ((select auth.uid()) = user_id);
create policy "watch_history: insert own" on public.watch_history
    for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "watch_history: update own" on public.watch_history
    for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "watch_history: delete own" on public.watch_history
    for delete to authenticated using ((select auth.uid()) = user_id);

-- Анонимной роли доступ к таблицам не нужен.
revoke all on public.library_entries, public.watch_progress, public.watch_history from anon;
grant select, insert, update, delete on public.library_entries, public.watch_progress, public.watch_history to authenticated;

-- Защита от «будущих» дат (сбитые часы устройства ломали бы правило last-write-wins).
create or replace function public.anivibe_clamp_timestamp() returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if tg_table_name = 'watch_history' then
        if new.watched_at > now() + interval '5 minutes' then new.watched_at := now(); end if;
    else
        if new.updated_at > now() + interval '5 minutes' then new.updated_at := now(); end if;
    end if;
    return new;
end;
$$;

create trigger library_entries_clamp before insert or update on public.library_entries
    for each row execute function public.anivibe_clamp_timestamp();
create trigger watch_progress_clamp before insert or update on public.watch_progress
    for each row execute function public.anivibe_clamp_timestamp();
create trigger watch_history_clamp before insert or update on public.watch_history
    for each row execute function public.anivibe_clamp_timestamp();
