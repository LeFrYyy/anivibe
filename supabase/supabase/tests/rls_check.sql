-- Ручная проверка RLS в SQL Editor Supabase (выполняйте в тестовом проекте).
-- Подставьте UUID двух существующих тестовых пользователей.
-- Ожидается: пользователь A не видит и не может изменить строки пользователя B.

begin;
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated"}';

insert into public.library_entries (user_id, anime_id, title, status)
values ('00000000-0000-0000-0000-00000000000a', 16498, 'Test', 'watching');

-- Должно завершиться ошибкой RLS (чужой user_id):
-- insert into public.library_entries (user_id, anime_id, title) values ('00000000-0000-0000-0000-00000000000b', 1, 'X');

select count(*) as own_rows from public.library_entries; -- только строки пользователя A
rollback;
