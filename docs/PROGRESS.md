# Hookah Empire — Progress v0.1

## Текущий статус

**M0 Foundation выполнен и верифицирован (автоматические проверки).** Остальные milestones не начаты.

Текущая цель: начать M1 по отдельной команде.

---

## Статус milestones

| Milestone | Статус | Заметки |
|---|---|---|
| M0 Foundation | Выполнен | Headless-проверки пройдены; запуск игры подтверждён разработчиком |
| M1 Garage + Player | Не начат | Playable garage |
| M2 Dialogue + Friends | Не начат | Первый social loop |
| M3 Ingredients + Recipes + Recipe Book | Не начат | Core discovery system |
| M4 Quick Preparation | Не начат | Fast preparation path |
| M5 Manual Preparation | Не начат | Signature mini-game |
| M6 Guest Session + Scoring | Не начат | Guest reactions становятся значимыми |
| M7 Heat + Charcoal + Re-preparation | Не начат | Service pressure |
| M8 Trends + Economy + MVP Progression | Не начат | Фактический experiment loop |
| M9 Furniture + Garage Customization | Не начат | Personalization |
| M10 20-minute Intro Vertical Slice | Не начат | Full MVP flow |
| M11 Save/Load + Menus + Polish + QA | Не начат | Release candidate |

---

## Решения, зафиксированные для v0.1

- Движок: Godot 4.7.2.
- Платформа разработки: macOS.
- Presentation target: преимущественно 2D isometric.
- MVP-локация: только гараж.
- Primary USP: player-created recipes + hands-on preparation.
- Два режима приготовления: quick и manual.
- Recipe book хранит player-created mixes.
- Guest satisfaction зависит от recipe, guest, trend и execution.
- Heat/charcoal — лёгкая service-management механика.
- Re-preparation поддерживается.
- Furniture placement — grid-based.
- Dialogue — data-driven.
- Save data — versioned.
- MVP заканчивается на invitation to serve outside guests.

### Зафиксировано в M0

- Рендерер: Compatibility (`gl_compatibility`), 3D-настройки Jolt/d3d12 удалены.
- Базовое разрешение: 1920×1080, stretch `canvas_items`, aspect `expand`.
- Формат контента: JSON в `data/`.
- Корневая `ui/` — общие UI-ресурсы (темы); экраны — в `scenes/ui/` и `scripts/ui/`.
- Autoloads: только `GameState` и `SaveService`. `GameState` хранит данные и сигналы без логики.
- Логирование: `GameLog.debug/info/warn/error(tag, message)`.
- Тесты: собственный раннер `tests/run_tests.gd`, без внешних фреймворков.
- Имя агента в документах: Беброид.
- Коммиты делает разработчик, агент их не создаёт.

---

## Открытые design decisions

Это должно решаться через prototype/playtest, а не преждевременно фиксироваться:

1. Точная ingredient interaction matrix и real-world-inspired content values.
2. Точные manual mini-game gestures и timing windows.
3. Точные economic prices/rewards.
4. Точная trend duration/rotation.
5. Сколько скрытой scoring-информации раскрывается игроку.
6. Финальный art style и asset pipeline.
7. Гейтится ли MVP ending только репутацией или комбинируется с 3-recipe goal.

---

## Правила обновления

После каждого значимого implementation milestone обновлять:

- status table;
- decisions, ставшие locked;
- open issues;
- verification notes.

Не помечать milestone complete только потому, что код написан. Помечать complete только после верификации milestone acceptance criteria.

---

## Последняя верификация

**M0 — 2026-09-30, Godot 4.7.2.stable (Steam), macOS.**

Команда: `GODOT_BIN=... tools/run_checks.sh` (лог: `tests/last_run.log`, не в git).

- Импорт ресурсов: OK.
- Parse-check всех 8 `.gd`: OK.
- Юнит-тесты: 6 тестов, 0 провалено.
- Headless-запуск main scene: OK, `[INFO][main] Boot OK, version 0.0.1-m0`.
- Запуск игры в редакторе: выполнен разработчиком. Проверка «закрыть/переоткрыть редактор и запустить снова» отдельно не подтверждена.

Известные замечания:

- Предупреждение Godot `Case mismatch` про папку `user://`: на диске `.../app_userdata/HookahEmpire`, в проекте `hookahEmpire`. На macOS безвредно; разобраться до M11 (save/load).
- В `run_checks.sh` любой вывод `ERROR:` считается провалом, поэтому тесты, намеренно вызывающие ошибки, должны глушить логи через `GameLog.muted`.
