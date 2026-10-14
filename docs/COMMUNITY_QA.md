# Community QA — 2026-10-14

## Выполнено здесь

- `python3 scripts/check_project.py` — **PASS**: статическая конфигурация Xcode/пакета.
- `python3 -m unittest discover -s scripts -p 'test_*.py'` — **52/52 PASS**: 35 прежних + 17 новых. Это проверки исходников/контрактов/импортёра, не исполнение Swift или PostgreSQL.
- `python3 scripts/validate_community_media.py` — **4/4 PASS**: действительные PNG/MP4, MIME/размер/геометрия/длительность/H.264/yuv420p/отсутствие аудио/SHA-256 и превью.
- Python syntax compile новых скриптов и PG test harness — **PASS**.
- YAML workflow загружен; build остаётся зависимым от core/database/avatar jobs.
- 18 новых/изменённых Swift-файлов: лексическая целостность скобок, комментариев, обычных/raw/multiline строк и интерполяций — **PASS, не компиляция**.
- 3 новые SQL-миграции: целостность dollar-строк и скобок выражений — **PASS, не PostgreSQL parser/runtime**.
- Превью оригинальных ресурсов `community-media-preview.jpg` просмотрено. Это **не** снимки приложения iOS.

Логи реальных локальных проверок находятся в `community-qa-results/`. Архив дополнительно проверяется на целостность и отсутствие приватных ключей/сборочного мусора.

## Подготовлено, НЕ выполнено здесь

- 11 `CommunityTests.swift`: RPC ownership/idempotency contract, кодек точного ProviderEpisode, большая XP-строка, ограниченная коррекция позиций, invalid duration/NaN, атомарное чтение уведомлений.
- 24 `supabase/tests/community_test.py`: 15 требуемых приёмочных случаев и дополнительная проверка запрета DML/скрытых функций, приватности, отключённых наград, ежедневного бонуса, prerequisites, одноразового уведомления, invite privacy, TTL и предыдущего индивидуального прогресса.
- `.github/workflows/ios.yml`: PostgreSQL integration suite, **настоящий restart контейнера БД** между сохранением/проверкой reward checkpoint, проверка реальных media, Swift tests и два xcodebuild.
- Swift compilation/XCTest, SQL migrations/RLS/parallel transactions, Supabase Realtime, iOS visual QA, real-device AVPlayer, Instruments/memory/FPS и нагрузочный тест.

Наличие этих тестов в репозитории не является доказательством их прохождения. В текущей среде нет `swift`, `xcodebuild`, `psql`/PostgreSQL или `deno`; нет доступа к Supabase deployment/репозиторию для запуска CI.

## Запуск реальных проверок

```sh
# macOS/Xcode
cd Packages/AnivibeCore
swift test

# ONLY disposable local PostgreSQL 15, *_test database, with local credentials
PGHOST=127.0.0.1 PGUSER=postgres PGTEST_DB=anivibe_social_test python3 supabase/tests/social_test.py
PGHOST=127.0.0.1 PGUSER=postgres PGTEST_DB=anivibe_social_test python3 supabase/tests/comments_test.py
PGHOST=127.0.0.1 PGUSER=postgres PGTEST_DB=anivibe_social_test python3 supabase/tests/community_test.py
```

SQL-tests создают/очищают **только** локальную disposable БД, а тестовые часы/готовые интервалы заменяют/вставляют её владельцем. Ни production migration, ни клиент не содержат client-settable testing clock. Для реального restart использовать подготовленный CI job; тест №15 сам проверяет только новые подключения, не выдаёт это за перезапуск сервера.

После зелёного CI — приёмка на двух устройствах по `COMMUNITY_SETUP_RU.md`. Отдельный solo telemetry / полный экран ledgers / APNs / back office / админка ещё не входят в эту поставку.
