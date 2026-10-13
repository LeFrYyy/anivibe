Для этой поставки сначала прочитайте [DELIVERY.md](DELIVERY.md): новая четвёртая миграция профилей/друзей применяется отдельно. Архив основан на старом Anivibe (21).zip; сохранена его клиентская конфигурация Kodik.

# Запуск, почта, OAuth, миграции и VPS

## Подключённый облачный проект

В `Config/Supabase.xcconfig` уже указаны URL `https://kdbkkigoefierimdzdrq.supabase.co` и предоставленный публичный publishable key. Файл подключается до `Secrets.xcconfig`: локальные значения и GitHub Actions secrets имеют приоритет. Не копируйте пример с placeholder-значениями поверх рабочей конфигурации Supabase. Для подписи можно создать `Secrets.xcconfig` только с `PRODUCT_BUNDLE_IDENTIFIER` и `DEVELOPMENT_TEAM`.

Клиент Auth отправляет API key в `apikey`, а пользовательский JWT — в `Authorization` только для запросов, где он нужен. Publishable key больше не используется как Bearer. Синхронизация продолжает отправлять пользовательский JWT.

Настройки в архиве не создают облачные таблицы, SMTP и Google provider. Выполните три миграции и настройки Auth в Dashboard. Реальная iOS-сборка и вход не проверены. Swift-тесты ядра этой поставки выполнены; результаты и ограничения находятся в DELIVERY.md.

## 1. Приложение

Нужен Mac с Xcode 16+ для проекта с синхронизированными папками, iOS 17+ на устройстве.

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
open Anivibe.xcodeproj
```

Настройте `PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM`, подпись. Без Supabase вход выключен, локальные функции остаются доступны. Без собственного партнёрского Kodik token источник выключен. Наличие метаданных не подтверждает право воспроизводить видео.

Пример клиентской конфигурации:

```xcconfig
ANIVIBE_SUPABASE_URL = https:/$()/YOUR_PROJECT_REF.supabase.co
ANIVIBE_SUPABASE_ANON_KEY = YOUR_PUBLISHABLE_OR_ANON_KEY
ANIVIBE_KODIK_TOKEN = YOUR_AUTHORIZED_PARTNER_TOKEN
```

Anon/publishable ключ — клиентский. RLS должна быть включена. Service-role, пароль БД, SMTP и Google client secret никогда не помещать в `.xcconfig`/Info.plist. Любое значение, упакованное в IPA, извлекается из клиента.

## 2. Локальная Supabase

Нужны Supabase CLI и Docker. Эти инструменты в текущей доработке не запускались; PostgreSQL был проверен отдельно.

```bash
supabase start
supabase db reset
supabase status
```

`db reset` удаляет локальные данные; **не выполнять против production**. Используйте URL/anon key локального проекта из status. В симуляторе допустим localhost; реальный iPhone не видит localhost вашего Mac.

В `supabase/config.toml` включено подтверждение email, шестизначный код, срок 600 секунд, повторная отправка не чаще 60 секунд и local rate limits. Шаблон письма: `supabase/templates/confirmation.html` с `{{ .Token }}`. Локальные письма смотрите в почтовом сервисе Supabase (адрес/порт из `supabase status`, обычно 54324). Поддержка конкретных TOML-полей зависит от версии CLI; конфигурация синтаксически проверена, не проверена самим CLI.

## 3. Облачный проект Supabase

1. Создайте/выберите проект, включите Email provider и **Confirm email**.
2. В Authentication → URL Configuration добавьте native redirect `anivibe://auth/callback**`. Wildcard нужен для случайного state в callback. Не добавляйте произвольные внешние домены. Перед production желательно заменить общий scheme на scheme вашего Bundle ID или Associated Domains, согласованно изменив Coordinator и Info.plist.
3. Настройте SMTP и шаблон подтверждения ниже.
4. Сверьте историю миграций. Если исходная миграция ранее выполнялась вручную, отметьте её применённой только после проверки схемы (команда `supabase migration repair --status applied 20261011000000` после link). Не отмечайте миграцию только ради обхода ошибки.
5. Резервная копия, staging, затем:

```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

Файлы выполняются по порядку:

- `20261011000000_anivibe_init.sql` — исходная схема;
- `20261013000000_source_episode_identity.sql` — source_key и новый composite PK;
- `20261013010000_history_tombstones_lww.sql` — deleted_at/updated_at истории, индекс, серверный LWW trigger.

Не повторяйте отдельные SQL-файлы вручную: новые ALTER предполагают последовательное применение миграций. Нельзя оставить старые клиенты с `on_conflict=user_id,anime_id,episode` после изменения ключа. Согласуйте обновление всех клиентов.

**Rollback:** новые source/tombstone данные не умещаются в старую схему без потерь. Не удаляйте колонки/строки для «починки». Восстанавливайте проверенную резервную копию в отдельную staging базу и согласовывайте откат клиента/сервера. Автоматический destructive rollback намеренно не добавлен.

## 4. Реальная почта

Пример провайдера — Brevo (транзакционный SMTP); допускается другой SMTP-провайдер с доменной верификацией. Условия и тарифы проверяйте у выбранного сервиса.

1. Зарегистрируйте транзакционный сервис, подтвердите отправляющий домен.
2. Настройте SPF/DKIM и DMARC по значениям сервиса. Не копируйте записи другого домена.
3. Создайте отдельные SMTP credentials. Это не пароль вашей личной почты.
4. Supabase Authentication → SMTP Settings: host, port, username, SMTP password, sender email и sender name.
5. Confirm signup email template: скопируйте HTML из `supabase/templates/confirmation.html` или введите `Ваш код: {{ .Token }}`.
6. Настройте OTP length **6**, expiry **600 сек**, resend interval **60 сек**; production лимиты выбирайте по объёму сервиса и угрозам.
7. Зарегистрируйтесь через приложение, получите код, подтвердите его. Затем проверьте неверный, истёкший и повторно использованный код.
8. Проверьте Auth logs и SMTP delivery logs. Не публикуйте логины/коды/token/Authorization headers и полные адреса почты в общих логах.

Сервер генерирует и проверяет код. Клиент не хранит проверочный код и не выдаёт сессию локально. Задержка кнопки resend улучшает UX, но безопасность обеспечивают серверные ограничения.

**Ограничение:** фиксированного числа попыток именно для каждого challenge в нашем собственном коде нет; используется rate limit GoTrue. Для полного выполнения ТЗ нужен отдельный пер-challenge счётчик/сервис или подтверждённая соответствующая политика провайдера. Секреты заполняйте только в server settings/.env. Никакое письмо в этой среде фактически не отправлялось.

## 5. Google OAuth

1. В Google Cloud Console создайте проект, настройте OAuth consent screen и test users.
2. Создайте OAuth client типа Web Application, предназначенный для серверного Supabase provider.
3. Authorized redirect URI: `https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback` или ваш `https://api.example.com/auth/v1/callback` при self-hosting.
4. Supabase Authentication → Providers → Google: включите provider, укажите client ID и client secret **на сервере**.
5. Добавьте native callback allowlist из пункта 3. Не путайте Google callback на сервер и возврат из сервера в iOS.
6. В приложении «Войти через Google» запускает ASWebAuthenticationSession; генерирует verifier через Security, SHA-256 challenge через CryptoKit, проверяет state/scheme/host/path, меняет auth code на сессию через GoTrue PKCE token endpoint.
7. Проверьте Google на устройстве с test account. Система авторизации должна проверять подпись/issuer/audience на сервере; клиент не доверяет произвольному Google token.

Автоматическое связывание/уникальность identity остаётся ответственностью GoTrue и политики provider. UI безопасной ручной привязки/отвязки способов входа и полноценное редактирование профиля пока отсутствуют. Для публикации App Store оцените требования Apple к Sign in with Apple — такой provider сейчас не добавлен.

## 6. VPS Ubuntu — инструкция для адаптации, не подтверждённый deployment

Архитектуру не меняем на самописный сервер: используйте официальный self-hosted Supabase stack. Нет готового запущенного VPS и выбранного production commit стека. Его compose и конфигурацию сначала проверьте на staging.

```bash
sudo apt-get update
sudo apt-get install -y git docker.io docker-compose-v2 postgresql-client nginx certbot python3-certbot-nginx
sudo systemctl enable --now docker nginx
sudo mkdir -p /opt/anivibe
sudo chown "$USER":"$USER" /opt/anivibe
cd /opt/anivibe
git clone https://github.com/supabase/supabase.git platform
cd platform
# Выберите официальный release/commit; не оставляйте непроверенный main для production.
git checkout YOUR_REVIEWED_SUPABASE_RELEASE_OR_COMMIT
cd docker
cp .env.example .env
chmod 600 .env
```

Заполните **все** обязательные значения официального `.env`: уникальные POSTGRES_PASSWORD/JWT_SECRET/anon/service-role keys, dashboard credentials, SITE_URL/API_EXTERNAL_URL, storage и остальные ключи установленной версии. Не используйте sample JWT/пароли. Сгенерируйте ключи официальным инструментом выбранного релиза.

Для email/Google настройки GoTrue должны соответствовать:

- `GOTRUE_MAILER_AUTOCONFIRM=false`;
- `GOTRUE_MAILER_OTP_LENGTH=6`, `GOTRUE_MAILER_OTP_EXP=600`;
- `GOTRUE_SMTP_HOST`, `PORT`, `USER`, `PASS`, `ADMIN_EMAIL`, `SENDER_NAME`;
- `GOTRUE_SMTP_MAX_FREQUENCY=60s` и обоснованные rate limits;
- `GOTRUE_EXTERNAL_GOOGLE_ENABLED=true`, `CLIENT_ID`, `SECRET`, `REDIRECT_URI`;
- `GOTRUE_SITE_URL`, `GOTRUE_URI_ALLOW_LIST` только для вашего HTTPS/native callback;
- собственный confirmation template с `{{ .Token }}`. Для self-host GoTrue используйте поддерживаемый выбранной версией механизм `MAILER_TEMPLATES_CONFIRMATION`/URL-шаблона.

Имена server env сверяйте с конфигурацией **выбранного релиза** GoTrue. Шаблон `.env.example` в Anivibe является перечнем ваших параметров, не заменой полного официального Supabase `.env`.

```bash
# Проверка конфига без печати всех secrets:
sudo docker compose config --quiet
sudo docker compose pull
sudo docker compose up -d
sudo docker compose ps
```

Перед внешним доступом:

- домены API/сайта должны иметь верные DNS;
- Nginx проксирует HTTPS к Kong на loopback;
- получите сертификат: `sudo certbot --nginx -d api.example.com` после настройки соответствующего server_name;
- DB/pooler/Studio/mail UI нельзя публиковать в интернет; loopback/private network, firewall, доступ только административным путям;
- Docker published ports могут обходить UFW: **не полагайтесь на UFW в одиночку**. Проверьте реальные bind-адреса/DOCKER-USER правила, убедитесь, что API доступен только через TLS;
- включите NTP, обновления, ограничение логов, резервные копии и мониторинг.

Применение миграций на **новой** self-host базе через контейнер (путь замените на распакованный проект):

```bash
ANIVIBE_DIR=/opt/anivibe/app
for migration in "$ANIVIBE_DIR"/supabase/migrations/*.sql; do
  sudo docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$migration" || exit 1
done
```

Это первоначальное ручное применение: не повторяйте его и не смешивайте без сверки с Supabase CLI migration ledger. Для следующих выпусков заведите единый мигратор/историю и выполняйте только новые миграции.

Бэкап БД (из официального docker directory):

```bash
umask 077
sudo docker compose exec -T db pg_dump -U postgres -d postgres -Fc > anivibe-backup.dump
```

Копируйте backup в закрытое внешнее хранилище, шифруйте, проверяйте restore на отдельной базе. Делайте отдельную резервную копию storage/файлов и локальных пользовательских JSON. Не храните единственный backup на том же диске VPS.

### 7 ГБ RAM

Без хранения/транскодирования видео такой VPS может быть подходящим стартом для небольшого приложения метаданных и библиотеки, но гарантий без нагрузки нет. Полный Supabase stack включает много служб. Ограничивайте PostgreSQL connections/cache и необязательные сервисы, оставляйте запас ОС, следите за RSS/OOM/диском и проводите нагрузочные проверки. Конкретная вместимость пользователей и социального realtime не измерена. Видео на VPS не переносилось.
