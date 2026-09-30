# Hookah Empire — Dev Setup

Локальная среда разработки. Путь к Godot зависит от машины и **не** хранится в репозитории.

## Переменная окружения

Указать путь к исполняемому файлу Godot 4.7.x (для macOS это бинарник внутри `Godot.app`, `.../Godot.app/Contents/MacOS/Godot`):

```bash
export GODOT_BIN="/путь/к/Godot.app/Contents/MacOS/Godot"
```

Добавить строку в `~/.zshrc`, чтобы не вводить каждый раз.

## Быстрый прогон всех проверок

```bash
tools/run_checks.sh
```

Скрипт выполняет импорт, parse-check всех `.gd`, юнит-тесты и headless-запуск. Вывод дублируется в `tests/last_run.log` (в `.gitignore`), код выхода 0 — всё прошло. Этот лог удобно отдавать агенту для анализа.

## Отдельные команды (из корня проекта)

Импорт ресурсов и обновление кэша глобальных классов (нужно после добавления файлов с `class_name`, а также на чистом клоне):

```bash
"$GODOT_BIN" --headless --path . --import
```

Быстрый запуск проекта в headless-режиме (загрузка main scene и выход):

```bash
"$GODOT_BIN" --headless --path . --quit-after 5
```

Проверка синтаксиса конкретного скрипта:

```bash
"$GODOT_BIN" --headless --path . --check-only --script res://scripts/core/game_state.gd
```

Юнит-тесты:

```bash
"$GODOT_BIN" --headless --path . --script res://tests/run_tests.gd
```

Раннер выходит с кодом 0, если все тесты прошли, иначе с кодом 1.

## Конвенция тестов

- Файлы `tests/unit/test_*.gd`, `extends TestCase` (`tests/test_case.gd`).
- Методы `test_*` запускаются раннером автоматически.
- Autoload-скрипты в тестах создаются через `preload(...).new()`, а не через глобальные имена.

## Логирование

Использовать `GameLog.debug/info/warn/error(tag, message)` (`scripts/utils/game_log.gd`). Формат: `[LEVEL][tag] message`.
