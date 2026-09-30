# Hookah Empire — Progress v0.1

## Текущий статус

**Design phase. Ни один implementation milestone ещё не начат в исходном репозитории.**

Текущая цель: согласовать/итерировать MVP-дизайн и затем начать M0.

---

## Статус milestones

| Milestone | Статус | Заметки |
|---|---|---|
| M0 Foundation | Не начат | Project bootstrap и architecture |
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

Пока нет.
