# Hookah Empire — Design Pack v0.1

Эта папка содержит начальную design/agent-документацию для Garage MVP.

## Файлы

- `AGENTS.md` — постоянные инструкции для Codex.
- `docs/GDD.md` — game-design источник истины.
- `docs/MVP_PLAN.md` — implementation roadmap M0–M11.
- `docs/ARCHITECTURE.md` — техническая структура и data contracts.
- `docs/PROGRESS.md` — milestone-трекинг и открытые решения.
- `docs/RECIPE_RESEARCH.md` — workspace для flavor-combination research.

## Куда положить

Скопировать содержимое этого пака в корень существующего Godot-проекта:

```text
hookahEmpire/
├── project.godot
├── AGENTS.md
└── docs/
    ├── GDD.md
    ├── MVP_PLAN.md
    ├── ARCHITECTURE.md
    ├── PROGRESS.md
    └── RECIPE_RESEARCH.md

Эти документы описывают только Garage MVP. Не расширять реализацию в следующие бизнес-этапы, пока MVP не завершён и не пере-скоуплен явно.