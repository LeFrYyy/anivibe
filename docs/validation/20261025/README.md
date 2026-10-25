# Проверки обновления 25.10.2026

Среда: Linux, Swift 6.0.3. Xcode и iOS SDK отсутствуют.

- `swift package clean && swift build --build-tests`: успешно, 0 warnings / 0 errors.
- `swift test --skip-build`: 234 теста, 228 прошли, 6 live-тестов пропущены, 0 ошибок.
- Все `scripts/test_*.py`: 77 проверок, 0 ошибок.
- `python3 scripts/check_project.py`: успешно.
- `find Anivibe -name '*.swift' -print0 | xargs -0 swiftc -parse`: 47 файлов, без диагностик.
- `git diff --check`: без ошибок.

Логи лежат рядом. Синтаксический разбор не проверяет типы SwiftUI/UIKit/AVFoundation и не заменяет сборку iOS. SwiftLint не установлен; отдельный SwiftLint-конфиг в проекте отсутствует. PostgreSQL/Deno/реальное видео/авторизация/UI/FPS здесь не проверялись; серверные файлы не менялись. Обновлённый GitHub Actions содержит сборку Debug Simulator и Release iPhone, но этот CI из данной среды не запускался.

6 live-тестов требуют `ANIVIBE_LIVE_TESTS=1`; их пропуск не означает подтверждённую доступность внешних провайдеров.
