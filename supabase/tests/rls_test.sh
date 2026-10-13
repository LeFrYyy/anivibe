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
as_user $A "insert into public.watch_progress (user_id, anime_id, episode, position_seconds, duration_seconds, updated_at) values ('$A', 16498, 1, 10, 1440, now()) on conflict (user_id, anime_id, episode) do update set position_seconds = excluded.position_seconds" >/dev/null
as_user $A "insert into public.watch_progress (user_id, anime_id, episode, position_seconds, duration_seconds, updated_at) values ('$A', 16498, 1, 600, 1440, now()) on conflict (user_id, anime_id, episode) do update set position_seconds = excluded.position_seconds" >/dev/null
check $A "select position_seconds from public.watch_progress where anime_id = 16498 and episode = 1" 600 "upsert прогресса"
check $A "with i as (insert into public.watch_history (id, anime_id, title, episode, watched_at) values (gen_random_uuid(), 1, 'X', 1, now() + interval '1 year') returning watched_at) select (watched_at < now() + interval '1 minute')::text from i" true "дата из будущего ограничивается"
check $B "select count(*) from public.watch_progress" 0 "B не видит прогресс A"
if psql "$DBURL" -qtA -c "begin; set local role anon; select count(*) from public.library_entries; commit;" >/dev/null 2>&1; then
  echo "FAIL: anon имеет доступ"; exit 1; else echo "ok  (отклонено) роль anon не имеет доступа к таблицам"; fi

psql "$PGURL" -q -c "drop database $DB"
echo "Все проверки RLS пройдены."
