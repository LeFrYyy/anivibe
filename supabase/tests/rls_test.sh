#!/usr/bin/env bash
# Автоматическая проверка миграции и RLS на локальном PostgreSQL (без Supabase CLI).
# Использование: PGURL=postgresql://postgres@localhost:5432/postgres ./supabase/tests/rls_test.sh
# ВНИМАНИЕ: создаёт и удаляет базу anivibe_rls_test. Не запускайте на продакшене.
set -euo pipefail
cd "$(dirname "$0")/../.."
PGURL="${PGURL:-postgresql://postgres@localhost:5432/postgres}"
DB=anivibe_rls_test
psql "$PGURL" -v ON_ERROR_STOP=1 -q -c "drop database if exists $DB" -c "create database $DB"
DBURL="${PGURL%/*}/$DB"
psql "$DBURL" -v ON_ERROR_STOP=1 -q -f supabase/tests/local_auth_stub.sql
psql "$DBURL" -v ON_ERROR_STOP=1 -q -f supabase/migrations/20261011000000_anivibe_init.sql

# Seed a legacy row before schema changes, then verify it survives unchanged.
psql "$DBURL" -v ON_ERROR_STOP=1 -q -c "insert into public.watch_progress(user_id,anime_id,episode,position_seconds,duration_seconds) values('00000000-0000-0000-0000-00000000000a',42,1,123,1000)"
psql "$DBURL" -v ON_ERROR_STOP=1 -q -f supabase/migrations/20261013000000_source_episode_identity.sql
psql "$DBURL" -v ON_ERROR_STOP=1 -q -f supabase/migrations/20261013010000_history_tombstones_lww.sql

A=00000000-0000-0000-0000-00000000000a
B=00000000-0000-0000-0000-00000000000b
as_user() { # $1 = uuid, $2 = sql
  psql "$DBURL" -v ON_ERROR_STOP=1 -qtA -c "begin; set local role authenticated; set local request.jwt.claims = '{\"sub\":\"$1\",\"role\":\"authenticated\"}'; $2; commit;"
}
expect_fail() {
  if as_user "$1" "$2" >/dev/null 2>&1; then echo "FAIL: ожидалась ошибка: $2"; exit 1; else echo "ok  (отклонено) $3"; fi
}
check() { # $1 user, $2 sql, $3 expected, $4 label
  got=$(as_user "$1" "$2" | tail -1)
  if [[ "$got" == "$3" ]]; then echo "ok  $4"; else echo "FAIL: $4 — ожидалось '$3', получено '$got'"; exit 1; fi
}

as_user $A "insert into public.library_entries (anime_id, title, status) values (16498, 'AoT', 'watching')" >/dev/null
echo "ok  вставка своей строки (user_id по умолчанию = auth.uid())"
as_user $B "insert into public.library_entries (user_id, anime_id, title) values ('$B', 1, 'B title')" >/dev/null
check $A "select count(*) from public.library_entries" 1 "A видит только свои строки"
check $B "select count(*) from public.library_entries where anime_id = 16498" 0 "B не видит строки A"
expect_fail $A "insert into public.library_entries (user_id, anime_id, title) values ('$B', 2, 'X')" "вставка от имени другого пользователя"
check $A "with u as (update public.library_entries set title = 'hack' where user_id = '$B' returning 1) select count(*) from u" 0 "A не может изменить строки B"
check $A "with d as (delete from public.library_entries where user_id = '$B' returning 1) select count(*) from d" 0 "A не может удалить строки B"
expect_fail $A "insert into public.library_entries (anime_id, title, status) values (5, 'X', 'bogus')" "недопустимый статус"
expect_fail $A "insert into public.library_entries (anime_id, title, cover_url) values (6, 'X', 'http://insecure')" "не-https обложка"
expect_fail $A "insert into public.watch_progress (anime_id, episode, position_seconds, duration_seconds) values (1, 0, 1, 1)" "серия 0"

# upsert как у PostgREST (on_conflict + merge-duplicates)
as_user $A "insert into public.watch_progress (user_id, anime_id, episode, position_seconds, duration_seconds, updated_at) values ('$A', 16498, 1, 10, 1440, now()) on conflict (user_id, anime_id, episode, source_key) do update set position_seconds = excluded.position_seconds, updated_at = excluded.updated_at" >/dev/null
as_user $A "insert into public.watch_progress (user_id, anime_id, episode, position_seconds, duration_seconds, updated_at) values ('$A', 16498, 1, 600, 1440, now()) on conflict (user_id, anime_id, episode, source_key) do update set position_seconds = excluded.position_seconds, updated_at = excluded.updated_at" >/dev/null
check $A "select position_seconds from public.watch_progress where anime_id = 16498 and episode = 1" 600 "upsert прогресса"
check $A "with i as (insert into public.watch_history (id, anime_id, title, episode, watched_at) values (gen_random_uuid(), 1, 'X', 1, now() + interval '1 year') returning watched_at) select (watched_at < now() + interval '1 minute')::text from i" true "дата из будущего ограничивается"
check $B "select count(*) from public.watch_progress" 0 "B не видит прогресс A"
if psql "$DBURL" -qtA -c "begin; set local role anon; select count(*) from public.library_entries; commit;" >/dev/null 2>&1; then
  echo "FAIL: anon имеет доступ"; exit 1; else echo "ok  (отклонено) роль anon не имеет доступа к таблицам"; fi

check $A "select position_seconds from public.watch_progress where anime_id=42 and source_key=''" 123 "миграция сохраняет старый прогресс"
as_user $A "insert into public.watch_progress(anime_id,episode,source_key,position_seconds,duration_seconds) values(42,1,'kodik:voice:6:1',20,1000)" >/dev/null
check $A "select count(*) from public.watch_progress where anime_id=42" 2 "каталог и источник не перезаписывают друг друга"
expect_fail $B "insert into public.watch_progress(user_id,anime_id,episode,source_key,position_seconds,duration_seconds) values('$A',42,2,'kodik:x',20,1000)" "RLS источников"
expect_fail $A "insert into public.watch_progress(anime_id,episode,source_key,position_seconds,duration_seconds) values(43,1,repeat('x',501),20,1000)" "ограничение длины source_key"
as_user $A "update public.watch_progress set position_seconds=999,updated_at=now()-interval '1 day' where anime_id=42 and source_key=''" >/dev/null
check $A "select position_seconds from public.watch_progress where anime_id=42 and source_key=''" 123 "старый запрос не затирает новый прогресс"
as_user $A "insert into public.watch_history(id,anime_id,title,episode,source_key,watched_at,updated_at) values('00000000-0000-0000-0000-000000000123',42,'Test',1,'kodik:voice:6:1',now()-interval '2 minutes',now()-interval '2 minutes')" >/dev/null
as_user $A "update public.watch_history set deleted_at=now(),updated_at=now() where id='00000000-0000-0000-0000-000000000123'" >/dev/null
as_user $A "update public.watch_history set deleted_at=null,updated_at=now()-interval '1 minute' where id='00000000-0000-0000-0000-000000000123'" >/dev/null
check $A "select (deleted_at is not null)::text from public.watch_history where id='00000000-0000-0000-0000-000000000123'" true "удалённая история не воскресает от старого запроса"

# Concurrent writers race on the same key. Latest timestamp must win, regardless of lock order.
base=$(psql "$DBURL" -qtA -c "select now()")
pids=()
for value in 10 20 30 40 50 60 70 80; do
  as_user $A "update public.watch_progress set position_seconds=$value, updated_at=timestamptz '$base' + interval '$value milliseconds' where anime_id=42 and source_key=''" >/dev/null &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
check $A "select position_seconds from public.watch_progress where anime_id=42 and source_key=''" 80 "8 конкурентных запросов: побеждает последнее изменение"

psql "$PGURL" -q -c "drop database $DB"
echo "Все проверки RLS пройдены."
