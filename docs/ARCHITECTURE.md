# Hookah Empire — Architecture v0.1

## 1. Архитектурные цели

Архитектура должна позволять Беброиду добавлять контент без переписывания core-систем.

Основные принципы:

- data-driven контент
- небольшие сфокусированные системы
- разделение gameplay/UI
- минимум autoloads
- стабильные ID
- signals/events для cross-system communication
- детерминированные вычисления, где возможно
- простая scene composition

---

## 2. Рекомендуемая структура папок

```text
hookahEmpire/
├── project.godot
├── AGENTS.md
├── docs/
│   ├── GDD.md
│   ├── MVP_PLAN.md
│   ├── ARCHITECTURE.md
│   ├── PROGRESS.md
│   └── RECIPE_RESEARCH.md
├── scenes/
│   ├── main/
│   ├── garage/
│   ├── characters/
│   ├── hookah/
│   ├── dialogue/
│   └── ui/
├── scripts/
│   ├── core/
│   ├── systems/
│   ├── entities/
│   ├── ui/
│   └── utils/
├── data/
│   ├── ingredients/
│   ├── guests/
│   ├── furniture/
│   ├── dialogues/
│   ├── trends/
│   └── story/
├── art/
│   ├── characters/
│   ├── environment/
│   ├── furniture/
│   └── ui/
├── ui/
│   └── theme/
├── audio/
│   ├── music/
│   ├── sfx/
│   └── ambience/
└── tests/
    ├── unit/
    └── integration/
```

Корневая `ui/` — общие UI-ресурсы (темы, стили, шрифты); сцены и скрипты конкретных экранов лежат в `scenes/ui/` и `scripts/ui/`. `art/ui/` — только арт.

Не создавать все подпапки до того, как они понадобятся. Дерево — целевая организация, а не требование сгенерировать пустые папки.

---

## 3. Scene architecture

Рекомендуемый top-level flow:

```text
Main.tscn
└── Main
    ├── WorldRoot
    └── UI
```

Main отвечает за переключение между high-level game screens/scenes.

### Garage scene

```text
Garage.tscn
└── Garage
    ├── Floor
    ├── Walls
    ├── FurnitureRoot
    ├── CharactersRoot
    ├── HookahsRoot
    ├── InteractionsRoot
    └── Navigation/Collision helpers
```

### UI overlay

```text
GameUI
├── HUD
├── InteractionPrompt
├── DialogueLayer
├── RecipeBookLayer
├── FurnitureLayer
├── PauseLayer
└── Toast/FeedbackLayer
```

### Manual prep scene

```text
HookahPrepManual.tscn
└── HookahPrepManual
    ├── Background
    ├── BowlArea
    ├── IngredientTray
    ├── FoilArea
    ├── HoleArea
    ├── CoalArea
    ├── LightingArea
    ├── FeedbackUI
    └── Exit/Confirm controls
```

---

## 4. Autoloads / global state

Держать минимальным.

Рекомендуемые MVP-autoloads:

### GameState

Хранит persistent gameplay state и эмитит coarse-grained signals при изменении важных значений.

Примеры:

```text
money
reputation
current_day
story_progress
current_trend_id
owned_recipe_ids
owned_furniture
friend_progress
```

### SaveService

Отвечает за serialization/deserialization и save file versioning.

Избегать создания autoload на каждую feature-систему.

`RecipeSystem`, `TrendSystem`, `GuestSystem` и т. д. — обычные service objects/nodes, инстансируемые игровым потоком по необходимости.

---

## 5. Core systems

### RecipeSystem

Обязанности:

- валидировать ingredient selections;
- нормализовать пропорции;
- канонизировать рецепты;
- создавать стабильные recipe IDs;
- рассчитывать taste profile;
- рассчитывать synergy;
- рассчитывать balance;
- хранить/обновлять player recipe records.

НЕ делает:

- не рисует Recipe Book UI;
- не двигает игрока;
- не управляет диалогом;
- не управляет save files напрямую.

### GuestSystem

Обязанности:

- spawn/manage guest entities;
- хранить guest profiles;
- оценивать GuestFit;
- порождать guest reaction events.

### HookahSystem

Обязанности:

- создавать active hookah sessions;
- управлять preparation state;
- хранить execution score;
- управлять heat state;
- сигнализировать, когда нужен charcoal service.

### TrendSystem

Обязанности:

- хранить текущий trend;
- менять trends согласно authored schedule;
- рассчитывать TrendFit из recipe profile.

### EconomySystem

Обязанности:

- payments;
- ingredient purchases;
- furniture purchases;
- валидация spend/earn операций.

### ReputationSystem

Обязанности:

- применять reputation events;
- клампить значение в допустимый диапазон;
- эмитить reputation changed signals.

### FurnitureSystem

Обязанности:

- catalog access;
- ownership;
- grid placement validation;
- move/remove;
- furniture bonuses.

### DialogueSystem

Обязанности:

- загружать dialogue nodes;
- рендерить текущий node через UI adapter;
- валидировать choices/conditions;
- применять dialogue effects;
- продвигать story node.

---

## 6. Рекомендуемое разделение ответственности

Полезное направление зависимостей:

```text
Data
 ↓
Core calculations/services
 ↓
Game session/state
 ↓
Scene entities/controllers
 ↓
UI
```

Core-системы не должны тянуться вверх к UI-нодам, где это возможно.

Например:

```text
RecipeSystem.calculate_final_score(...)
```

возвращает data.

UI решает, показывать ли результат как:

- 76/100;
- star rating;
- phrase;
- animation.

---

## 7. Data-driven контент

Использовать human-readable data files для контента, где практично.

Рекомендуемые схемы:

### Ingredient

```json
{
  "id": "strawberry",
  "name": "Strawberry",
  "cost": 4,
  "sweet": 0.9,
  "fresh": 0.2,
  "sour": 0.1,
  "fruit": 1.0,
  "creamy": 0.0,
  "spicy": 0.0,
  "heavy": 0.2,
  "intensity": 0.7,
  "trend_tags": ["fruit", "sweet"],
  "likes": ["mint", "lemon"],
  "dislikes": [],
  "heat_sensitivity": 0.5
}
```

Точный набор полей может эволюционировать во время M3, но стабильные ID обязательны.

### Guest

```json
{
  "id": "friend_sweet",
  "name": "Max",
  "personality": "sweet_tooth",
  "patience": 0.8,
  "preference_profile": {
    "sweet": 0.9,
    "fresh": 0.4,
    "sour": 0.2,
    "fruit": 0.8,
    "creamy": 0.3,
    "spicy": 0.1,
    "heavy": 0.2
  },
  "likes": ["strawberry", "watermelon"],
  "dislikes": ["lemon"],
  "preferred_strength": 0.6,
  "conversation_tags": ["first_visit", "recipe_feedback"]
}
```

### Furniture

```json
{
  "id": "small_table_01",
  "name": "Small Table",
  "price": 80,
  "grid_size": [2, 2],
  "rotation_allowed": true,
  "category": "table",
  "comfort_bonus": 2,
  "atmosphere_bonus": 1,
  "sprite": "res://art/furniture/small_table_01.png"
}
```

### Trend

```json
{
  "id": "trend_fresh_fruit",
  "name": "Fresh Fruit",
  "duration_sessions": 3,
  "taste_weights": {
    "sweet": 0.4,
    "fresh": 0.8,
    "sour": 0.4,
    "fruit": 0.9,
    "creamy": 0.1,
    "spicy": 0.0,
    "heavy": -0.2
  },
  "tag_bonuses": {
    "fresh": 0.2,
    "fruit": 0.15
  }
}
```

---

## 8. Recipe representation

Использовать runtime-структуру, похожую на:

```text
RecipeData
- recipe_id
- ingredients: Array[RecipeIngredient]
- created_at/session
- best_score
- last_score
- times_used
- current_popularity
```

Где:

```text
RecipeIngredient
- ingredient_id
- proportion
```

Не хранить дублированные derived values без измеренной performance-причины.

---

## 9. Scoring pipeline

Рекомендуемый порядок:

```text
Selected ingredients
        ↓
Canonical recipe
        ↓
Recipe profile
        ↓
SynergyScore
        ↓
BalanceScore
        ↓
RecipeQuality
        ↓
GuestFit
        ↓
TrendFit
        ↓
ExecutionScore
        ↓
HeatPenalty / ServicePenalty
        ↓
FinalScore
        ↓
Guest reaction + payment + reputation
        ↓
Recipe book stats
```

Каждую стадию делать независимо тестируемой.

---

## 10. Formula implementation contract

Стартовая формула:

```text
RecipeQuality = 0.70 * SynergyScore + 0.30 * BalanceScore

ContextScore = 0.45 * RecipeQuality
             + 0.25 * GuestFit
             + 0.15 * TrendFit
             + 0.15 * ExecutionScore

FinalScore = clamp(ContextScore - HeatPenalty - ServicePenalty, 0, 100)
```

Все tunables принадлежат configuration/data, а не разбросанным magic numbers.

---

## 11. Event/signal examples

Полезные signals:

```text
player_interacted(interactable_id)
dialogue_started(dialogue_id)
dialogue_finished(dialogue_id)
recipe_created(recipe_id)
hookah_preparation_completed(result)
hookah_heat_state_changed(hookah_id, state)
charcoal_service_requested(hookah_id)
guest_reaction_received(guest_id, result)
money_changed(delta)
reputation_changed(delta)
furniture_placed(item_id, cell)
story_progressed(node_id)
save_completed()
```

Не создавать универсальный event bus, если проект реально не нуждается в нём. Прямые signals и явные system interfaces предпочтительны в MVP.

---

## 12. Story progression

Story должна быть представлена стабильными IDs и requirements.

Пример:

```text
intro_start
friend_01_arrives
friend_01_first_hookah
friend_02_arrives
recipe_book_intro
manual_mode_intro
heat_intro
furniture_intro
three_good_recipes_goal
garage_outside_guest_invitation
```

Story controller должен оценивать progression по game state, а не инспектируя UI.

---

## 13. Save architecture

Сохранять в user-writable Godot user-data location, а не внутри репозитория.

Концептуальная save structure:

```json
{
  "save_version": 1,
  "money": 250,
  "reputation": 21,
  "story_progress": "heat_intro",
  "current_trend_id": "trend_fresh_fruit",
  "recipes": [],
  "owned_furniture": [],
  "friend_progress": {},
  "settings": {}
}
```

SaveService владеет file I/O.

GameState владеет in-memory state.

Системы запрашивают изменения state, а не пишут save files напрямую.

---

## 14. Testing strategy

Внешний test framework изначально не требуется.

Начать с небольших детерминированных test scripts для:

- recipe canonicalization;
- recipe profile generation;
- synergy calculation;
- guest fit;
- trend fit;
- final score;
- heat transitions;
- furniture collision/grid validation;
- save/load round trip.

Integration smoke test:

```text
new game → friend → recipe → preparation → result → reward → save
```

Gameplay manual test:

```text
play intro from clean save to MVP ending
```

---

## 15. Godot project/runtime verification

Точный путь к исполняемому файлу Godot на macOS может различаться в зависимости от Steam/app installation.

Беброид должен изучить локальное окружение перед изобретением команды.

Типичные цели project verification:

- detect parser errors;
- launch project headlessly, где практично;
- execute project test scripts, если доступны;
- report exact command used и его result.

Не заявлять успешный запуск, если команда фактически не завершилась успешно.

---

## 16. Art and scene decoupling

Gameplay-системы никогда не должны зависеть от финальных art asset names.

Использовать:

- stable IDs;
- scene/node contracts;
- exported references/configuration;
- data-driven lookup.

Это позволяет заменять placeholder art позже без переписывания gameplay-систем.

---

## 17. Anti-patterns to avoid

Избегать:

- один гигантский `Game.gd`, управляющий всем;
- ingredient logic, встроенная в UI buttons;
- dialogue branching, хардкоженный в десятках `if`;
- прямые save-file writes из случайных gameplay nodes;
- один singleton на subsystem;
- хардкоженные furniture positions;
- хардкоженные guest preferences в scene scripts;
- необратимые изменения без Git checkpoints;
- реализация future business stages во время MVP.