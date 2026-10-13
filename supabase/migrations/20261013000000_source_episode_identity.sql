-- Apply after 20261011000000. Back up first; deploy all clients together.
-- Existing records keep source_key = '', so no fabricated mapping or data loss.
begin;
alter table public.watch_progress add column source_key text not null default '' check (char_length(source_key) <= 500);
alter table public.watch_history add column source_key text not null default '' check (char_length(source_key) <= 500);
alter table public.watch_progress drop constraint watch_progress_pkey;
alter table public.watch_progress add primary key (user_id, anime_id, episode, source_key);
commit;
