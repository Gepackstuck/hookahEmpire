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
└── Garage              (garage_world.gd)
    ├── Backdrop        (пол и стены, рисуются кодом)
    ├── Entities        (y_sort_enabled: объекты, игрок и NPC в одном списке сортировки)
    └── InteractionPrompt
```

Изменение в M1: мебель и персонажи лежат в одном `Entities` с Y-sort, а не в раздельных `FurnitureRoot`/`CharactersRoot`: сортировка по глубине не работает между разными родителями. Если понадобится разделение по типам, использовать группы, а не отдельные корни.

### Изометрия и сетка (M1)

- Логика работает в координатах сетки (клетки, float): `IsoProjection` переводит их в экран (клетка 64×32). Ось X сетки идёт на экране вправо-вниз, ось Y — влево-вниз.
- Игрок двигается свободно; проходимость и столкновения — в `GarageGrid` (чистая логика без нод). Собственные коллизии вместо Godot physics: те же данные сетки будут использовать расстановка мебели (M9) и NPC.
- NPC ходят по `GarageGrid.find_path()` (AStarGrid2D поверх той же сетки).
- Описание гаража и объектов — `data/garage/*.json`, валидируется `GarageLayout`.
- Ввод: input actions `move_up/down/left/right` и `interact` в `project.godot` (физические клавиши, работают на любой раскладке).

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
  "id": "friend_denis",
  "name": "Денис",
  "emoji": "🚶‍♂️",
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

### Dialogue (M2)

Диалоги лежат в `data/dialogues/*.json`, проверяются `DialogueLibrary.validate()` при загрузке (ошибки логируются, битый диалог не загружается).

```json
{
  "id": "friend_denis_intro",
  "start": [
    { "node": "repeat", "conditions": [{ "type": "story_progress_is", "value": "friend_01_intro_done" }] },
    { "node": "greet" }
  ],
  "speakers": { "denis": { "name": "Денис", "portrait": "🚶‍♂️" } },
  "nodes": {
    "greet": { "speaker": "denis", "text": "...", "next": "ask" },
    "ask": { "speaker": "denis", "text": "...", "choices": [
      { "text": "...", "next": "end_node",
        "conditions": [], "effects": [{ "type": "set_flag", "flag": "denis_intro_choice", "value": "sweet" }] }
    ] },
    "end_node": { "speaker": "denis", "text": "...", "effects": [{ "type": "set_story_progress", "value": "friend_01_intro_done" }], "end": true }
  }
}
```

- У узла ровно одна форма выхода: `choices`, `next` или `end`.
- `start` — id узла или список записей с условиями (берётся первая подходящая; последняя — без условий).
- Эффекты узла применяются при входе в узел, эффекты выбора — при выборе.
- Эффекты: `set_flag` (`flag`, `value`), `set_story_progress` (`value`). Условия: `flag_set`, `flag_equals`, `story_progress_is`. Новые типы добавляются в `StoryEffects` (и сразу попадают в валидацию).
- `DialogueRunner` не знает про UI и сюжет: сигналы `node_entered(node, choices)`, `effect_requested(effect)`, `finished(dialogue_id)`. Эффекты применяет `StoryEffects` к `GameState`, условия проверяет он же.
- Окно диалога (`DialogueBox`) получает узлы от Main; Main блокирует ввод в гараже на время диалога.

Приход друзей описывается в `data/story/intro_beats.json` (`StoryBeats`): прогресс-условие, задержка, гость, точка входа, точка остановки, диалог, новый `story_progress`. Описание гостя — `data/guests/<id>.json` (`GuestCatalog`). NPC ходят по `PathWalker` вдоль пути из `GarageGrid.find_path()`.

### Recipes (M3)

- Контент: `data/ingredients/ingredients.json` (вкусовые измерения sweet/fresh/sour/fruit/creamy/spicy/heavy, intensity, cost, теги), `modifiers.json` (`ice`: `profile_delta`), `synergy.json` (пары −1..1), `data/config/scoring.json` (веса, лимиты, конфликты, полосы качества), `data/recipes/secret_recipes.json`. Загрузчики `IngredientCatalog` и `ScoringConfig` валидируют данные; при ошибке `RecipeSystem.create()` возвращает `null`, и Main показывает сообщение вместо смесителя.
- `RecipeCanonical.canonicalize()` приводит доли к 20 целым единицам, отбрасывает ингредиенты с 0 единиц, сортирует по id и строит key `mint:10|strawberry:10;ice` → id `r_<md5[0..10]>`.
- `RecipeScoring.evaluate()` — чистые функции: профиль, крепость, Synergy, Balance, Quality, секретный рецепт.
- `RecipeSystem` (RefCounted) — `evaluate`, `commit` (новый/повторный), `rename`, `record_result`, `all_recipes`; хранит записи в `GameState.recipes`. Запись: id, key, name, custom_name, ingredients, modifiers, best_score, last_score, times_used (растёт только через `record_result`), created_seq, last_used_seq, secret_id. Секретные рецепты не переименовываются.
- `MixSelection` — состояние порций (общий бюджет 4 порции, до 4 активных ингредиентов); `RecipeBookQuery` — фильтр/сортировка книги.
- UI: `MixerScreen`, `RecipeBookScreen` (строятся кодом, общий стиль `UiStyle`); Main связывает их с гаражом и блокирует ввод мира, пока открыт экран.
- Гараж: `interaction.action` (`open_mixer`, `open_recipe_book`) → сигнал `GarageWorld.action_requested`; необязательный `interaction.rect` [x,y,w,h] задаёт зону взаимодействия отдельно от размера объекта; `visual.lift` поднимает эмодзи над полом, `visual.glow` включает сияние при фокусе.

### Preparation (M4)

- Данные: `data/preparation/preparation.json` — параметры (id, name, weight, base, weights, options, подсказки), `penalty_per_level`, `ok_tolerance`. `PreparationConfig` валидирует; при ошибке `PreparationService.create()` возвращает `null`.
- `ExecutionScoring` (чистые функции): `features(recipe)` → `targets` → `evaluate(recipe, choices)`; оптимум каждого параметра — линейная формула от признаков рецепта; оценка падает линейно от расстояния до оптимума.
- `PreparationService.prepare(recipe_id, choices, preparer, mode)` → результат (recipe_name, execution_score, execution_band, parameters[{name, option_name, hint, is_ok}], preparer, mode), записывает его в рецепт (`RecipeSystem.record_preparation`) и шлёт `preparation_completed`. Запрос не зависит от того, кто выбрал параметры (быстрое окно, ручной режим, нанятый кальянщик).
- `PreparationScreen` только собирает выбор и показывает результат. Garage: действие `open_preparation` у `table_hookah`.
- `HookahStation` — состояние кальяна на столе (empty/prepared/liked/disliked), из него Main берёт подсказку, действие и позу игрока и через `GarageWorld.configure_interaction` меняет взаимодействие стола «на лету». `SessionScoring` — оценка гостевой сессии (GuestFit, TrendFit, ContextScore, FinalScore, полосы, оплата; M6). `HeatModel` — жар кальяна, пороги, штрафы и обслуживание углей (M7, `data/config/heat.json`); `SessionScoring.rescore` пересчитывает итог со штрафами; ход сессии (жалобы, замена углей, redo) ведёт `Main` (`_run_smoking_phase`, `_replace_coals`, `_do_redo`). Друг умеет `set_smoking` и `show_emotion`, игрок — `set_smoking` (`SmokeEmitter`/`SmokePuff`).

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
## Сценарий первого заказа (M4, переработка)
- `ObjectiveTracker` (чистая логика): по контексту (гость, заказ известен, рецепты, состояние станции) возвращает текст цели и id объекта для стрелки. Main строит контекст и показывает метку.
- `GarageWorld.carry_hookah_to_guest_table()` — корутина: блокирует ввод, игрок идёт с кальяном к `hookah_serve_cell`, кальян появляется на столе (`GarageObject.drop_in`).
- Станция кальяна ("table_hookah") и стол гостя ("table_guest") настраиваются `Main._apply_station()`; `interaction.enabled` отключает взаимодействие без удаления объекта.


## Ручное приготовление (M5)
- `ManualPreparation` (чистая логика): состояние мини-игры (порции, набивка, натяжение, дырки, угли, розжиг), перевод действий в уровни параметров, подоценка состава, качество расстановки углей, подсказки-ориентиры.
- `ExecutionScoring.evaluate_levels` — общая оценка по дробным уровням; быстрый режим (`evaluate`) приводит выбор вариантов к уровням и зовёт её. `PreparationService.preview_manual` — то же для ручного режима.
- UI: `ManualPreparationScreen` (шаги, лоток, история, результат), `BowlView` (рисование чаши и ввод мыши), `DragToken` (перетаскивание), `ManualSfx` (звуки-заглушки). Main создаёт экран кодом и связывает с окном приготовления (`manual_requested` → `suspend` → `served` → `complete_with`).

## M8: тренды, экономика, цель MVP

- `TrendSystem` (`data/config/trends.json` + тренды в `session_scoring.json`) — текущий тренд, отсчёт визитов, авторская ротация; `trend_fit` считает через `SessionScoring`. Состояние хранится в `GameState` (`current_trend_id`, `trend_visits_left`).
- `EconomySystem` — баланс/репутация поверх `GameState` (`earn`, `spend`, `recipe_cost`, бесплатные ингредиенты, границы репутации; `data/config/economy.json`).
- `ProgressionGoal` — «сильный рецепт» (`strong_trends` в записи рецепта), прогресс «n/3», флаги `mvp_goal_done` и `mvp_ending_seen`; финальный диалог `mvp_ending`.
- `StatusHud` — только отображение; `Main` связывает системы (`_setup_m8`, `_apply_session_economy`, `_advance_trend`, `_maybe_play_ending`) и отдаёт экранам провайдеры `cost_info` / `trend_info`.

## M9: мебель и кастомизация гаража

- `FurnitureSystem` (`data/config/furniture.json`) — каталог, покупка, владение (`GameState.furniture`), проверка размещения (границы, наложения, зоны, стены, связность проходов), бонус комфорта/атмосферы с потолком. Чистая логика без нод.
- `FurnitureLayer` — узлы мебели в мире (`GarageObject`), блокировка клеток `GarageGrid`, режим расстановки с «призраком». Создаётся через `GarageWorld.setup_furniture`.
- `FurnitureContextMenu` — меню «переместить / повернуть / убрать» у предмета, выбранного кликом в мире (`FurnitureLayer.item_clicked`). Предметы с `surface_ok` ставятся на основания с `surface_height` (`FurnitureSystem.placement_info`, `surface_lift`).
- `FurnitureScreen` — окно магазина и расстановки; `Main` связывает покупку/расстановку с экономикой и передаёт бонус в оценку (`SessionScoring.build_result(..., furniture_bonus)`).

## M10: вводный срез
- `IntroGuide` (чистая логика, `data/config/intro.json`): ворота разблокировок по числу обслуженных гостей, шаги цели, параметры Бэна.
- `Buddy` — корутина-поведение Бэна поверх `Friend`; живёт вне `GarageWorld._objects`, диван получает от `Main` через `set_couch/clear_couch`.
- Мебель-подарок: запись `FurnitureSystem` с `gift: true` (`grant_gift`, `gift_entry`, продажа запрещена, не считается в «обставь гараж»).
- Картины с текстурой: `wall_picture` + `visual.texture` рисуется `GarageObject._draw_wall_texture`.
- `Main` связывает всё: `_setup_m10`, `_apply_unlocks`, `_maybe_ben_arrival`, `_refresh_guide`, `_show_notice`, `_autopilot_furnish`.
- Порядок отрисовки: `GarageWorld._sort_entities()` (y-сортировка, затем правило крупных объектов; настенные вывески/картины имеют нулевую глубину через `sort_rect()`; сидящий гость идёт сразу после своего стула). Клетки стульев блокируются в рантайме (`_ready`), а не в раскладке.
- Ручная забивка: угли греются партиями (`ManualPreparation.batch_temps`, `average_heat`), всегда 3 угля (`max_coals`).
- Замена углей идёт со стороны корзины: `hookah_coal_cell` в раскладке гаража.
- Статистика (`PlaytestStats`): тайминги интро, журнал визитов (заказ/тренд/рецепт), список сильных рецептов.
- Кликабельные предметы: картины (`image`), бумбокс (`kind: boombox` → действие `toggle_boombox`, `ChipTune` синтезирует мотив кодом), молоко 🥛 (`_drink_milk`).
- Цель MVP: `progression.json` → `goal_recipes: 1`.

## M11: профили и сохранение
- `ProfileStore` (чистый файловый слой) хранит профили в `user://profiles`; `SaveService` — клей: активный профиль запуска, загрузка в `GameState`, автосохранение; в headless выключены.
- Выбор профиля = `begin_profile(id)` + перезагрузка сцены; `Main._ready` при `needs_profile_choice()` показывает только `ProfileMenu`, иначе грузит профиль в `GameState` до создания систем.
- Автосохранение пишет `GameState.to_dict()`; текущий визит не хранится, `StoryBeats.rewind_progress` откатывает «гость в середине визита».

