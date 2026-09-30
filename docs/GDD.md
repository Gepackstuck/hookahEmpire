# Hookah Empire — GDD v0.1

## 0. Статус документа

- Версия: 0.1
- Скоуп: только Garage MVP
- Базис движка: Godot 4.7.2
- Жанр: изометрический 2D management / simulation / cozy business
- Текущая роль: game-design источник истины для Беброида и разработчика

---

## 1. One-sentence pitch

Игрок начинает с приготовления кальянов для друзей в гараже, через эксперименты находит удачные вкусовые миксы, учится готовить кальян хорошо, зарабатывает репутацию и деньги, украшает гараж и доходит до момента, когда можно пригласить первых внешних гостей.

---

## 2. Ключевая фантазия игрока

> «Я сам придумал эту смесь, сам приготовил кальян, сам увидел реакцию посетителя и своими руками превратил гараж в место, куда хочется возвращаться».

Игра должна давать ощущение мастера и хозяина в первую очередь, и управленца — во вторую.

---

## 3. Дизайн-столпы

### Столп A — Recipe discovery

Игрок создаёт миксы сам, а не просто открывает заранее заданные рецепты.

### Столп B — Hands-on preparation

Игрок может переключаться между быстрым параметрическим режимом и ручным mini-game.

### Столп C — Human reactions

Хороший рецепт не универсально хорош. Предпочтения гостя, тренды, качество приготовления и сервис меняют результат.

### Столп D — Personal garage

Игрок меняет планировку и декор, создавая ощущение собственности.

### Столп E — Readable management

Деньги, репутация, жар и удовлетворённость гостей должны быть понятны без превращения MVP в бухгалтерский симулятор.

---

## 4. Границы MVP

### Включено

- одна локация — гараж.
- аватар игрока и движение.
- друзья как первые гости.
- диалоговая система с выборами и условиями.
- ингредиенты и создание рецептов.
- автоматическая книга рецептов, наполняемая миксами игрока.
- quick preparation mode.
- manual preparation mode.
- heat/charcoal monitoring.
- re-preparation по запросу гостя.
- модель предпочтений гостя.
- модель тренда.
- scoring результата.
- деньги и репутация.
- покупка и grid placement мебели.
- save/load.
- main menu, pause и settings.
- ~20-минутное интро.
- MVP-финал: друзья подталкивают игрока начать принимать внешних гостей.

### Явно исключено

- любая локация вне гаража.
- progression бизнес-этапов после гаража.
- крупные системы управления персоналом.
- delivery/e-commerce.
- мультиплеер.
- сложные деревья отношений персонажей.
- полноценная реалистичная физика дыма/жара.
- сотни ингредиентов.
- процедурная генерация города.

---

## 5. Основной цикл игрока

```text
Гость → предпочтения → выбор/создание рецепта → приготовление
      → подача → гость курит → фидбэк → деньги/репутация
      → эксперимент → улучшение гаража
```

Мета-цель внутри MVP — открыть как минимум 3 рецепта, достигающих 80+ contextual satisfaction в валидных showcase-попытках.

Этот порог — tutorial/progression-цель, а не утверждение, что 80 — универсальное определение хорошего кальяна.

---

## 6. Структура интро (~20 минут)

Точные тайминги настраиваемы. Ниже — целевой pacing.

### Beat 1 — Первый друг (~0–5 мин)

- Гараж почти пустой.
- Друг приходит.
- Диалог вводит фантазию и базовое взаимодействие.
- Игрок делает первый кальян через quick mode.
- Результат намеренно прощающий.

### Beat 2 — Открытие предпочтений (~5–10 мин)

- Приходит второй друг.
- Предпочтения отличаются от первого гостя.
- Игрок начинает видеть, что один и тот же микс работает неодинаково для разных людей.
- Открывается книга рецептов.

### Beat 3 — Открытие навыка (~10–14 мин)

- Разблокируется manual preparation mode.
- Игрок выполняет ключевые шаги приготовления.
- Качество приготовления начинает заметнее влиять на итог.

### Beat 4 — Service pressure (~14–17 мин)

- Могут быть активны несколько кальянов.
- Жар начинает иметь значение.
- Hookah master меняет угли.
- Игрок может пропустить угольный цикл без катастрофы.

### Beat 5 — Идентичность гаража (~17–20 мин)

- Вводится система мебели/декора.
- Игрок тратит часть заработанных денег на комнату.
- Друзья реагируют на растущий гараж.
- Игрок завершает первый progression-goal (3 сильных рецепта).
- Финальная сцена: друзья предлагают открыть гараж для внешних гостей.
- MVP здесь заканчивается.

---

## 7. Система рецептов

### 7.1 Определение рецепта

Рецепт — нормализованный набор ingredient IDs и пропорций, который игрок реально приготовил.

Пример:

```text
Recipe ID: generated/stable hash
Ingredients:
- strawberry: 0.50
- mint: 0.30
- lime: 0.20

Best result: 91
Last result: 76
Uses: 5
Current popularity: 84
```

Книга хранит созданные игроком рецепты, а не developer-authored список, показываемый как unlocks.

### 7.2 Нормализация

Пропорции ингредиентов должны суммироваться в 1.0 (100%).

Эквивалентные рецепты должны сводиться к одной canonical-форме. Малые floating-point различия не должны создавать дубликаты.

Для MVP canonicalization должна:

1. удалять ингредиенты ниже минимально значимого количества;
2. сортировать ингредиенты по стабильному ID;
3. округлять пропорции до фиксированной точности, пригодной для UI и сравнения;
4. нормализовать суммарную пропорцию до 1.0;
5. генерировать стабильный recipe key.

### 7.3 Модель оценки рецепта

Прозрачная high-level формула:

```text
RecipeQuality = 0.70 * SynergyScore
              + 0.30 * BalanceScore

ContextScore = 0.45 * RecipeQuality
            + 0.25 * GuestFit
            + 0.15 * TrendFit
            + 0.15 * ExecutionScore

FinalScore = clamp(ContextScore - HeatPenalty - ServicePenalty, 0, 100)
```

Все компоненты нормализованы к 0–100.

Веса — стартовые балансные значения, а не незыблемый дизайн-закон. Они должны храниться как tunable config, чтобы их можно было править после playtest.

### 7.4 SynergyScore

Использовать data-driven ingredient interaction matrix.

Для микса с ингредиентами A, B, C система оценивает pairwise-совместимость и опциональные небольшие multi-ingredient модификаторы.

Концептуально:

```text
SynergyScore = weighted average of pairwise compatibility
             + optional recipe pattern bonus/penalty
```

Не хардкодить flavor-логику в код RecipeSystem. Отношения ингредиентов — в data.

### 7.5 BalanceScore

Balance измеряет, является ли комбинированный вкусовой профиль рецепта когерентным, а не подавленным несовместимыми крайностями.

Пример taste-измерений для MVP:

- sweet
- fresh
- sour
- fruit
- creamy
- spicy
- heavy

Каждый ингредиент вносит вклад в вектор; профиль рецепта — weighted blend.

### 7.6 GuestFit

У каждого гостя есть preference profile, выраженный как weighted taste dimensions плюс явные likes/dislikes.

GuestFit сравнивает профиль рецепта с профилем гостя.

UI должен передавать предпочтения через диалог и реакции, а не показывать все внутренние числа.

### 7.7 TrendFit

Тренд определяет, какие вкусовые направления, ingredient tags или recipe families сейчас популярны.

Пример:

```text
Current trend:
Fresh + Fruit

Mint: positive trend contribution
Citrus: positive trend contribution
Heavy creamy profiles: negative trend contribution
```

Тренд может меняться во время игры.

Важный результат:

> Рецепт, который был отличным вчера, может стать средним сегодня, не становясь объективно другим рецептом.

Это поддерживает потребность игрока продолжать экспериментировать.

---

## 8. MVP-набор ингредиентов

Начальный набор должен быть достаточно малым для ручного баланса.

Стартовые ингредиенты (11, фактический состав M3; мята убрана — её заменяет «Ледяная нотка»):

1. Strawberry
2. Watermelon
3. Grape
4. Peach
5. Mango
6. Blueberry
7. Lemon
8. Lime
9. Vanilla
10. Cola
11. Apple (добавлен в M3)

Ice/Fresh note («Ледяная нотка» ❄️) реализована как модификатор-галочка, а не ингредиент (решено в M3). Рецепт может состоять из 1–4 ингредиентов (один — для секретного рецепта «Двойное яблочко»: 100% яблоко).

Эти имена — placeholder-контент для MVP-баланса. Их числовые значения совместимости/вкуса должны считаться tunable game data и валидироваться через content-research pass, описанный в `docs/RECIPE_RESEARCH.md`.

Не реализовывать полный финальный каталог ингредиентов в MVP.

---

## 9. Модель данных ингредиента

Каждый ингредиент должен содержать как минимум:

```text
id
name
icon
cost
unlock_condition
sweet
fresh
sour
fruit
creamy
spicy
heavy
intensity
trend_tags[]
likes[]
dislikes[]
heat_sensitivity
```

Опциональные поля добавляются только при появлении реальной игровой потребности.

`heat_sensitivity` — игровая абстракция, делающая перегрев по-разному влияющим на разные миксы; она не пытается моделировать реальную науку курения.

---

## 10. Два режима приготовления

### 10.1 Quick mode

Назначение: быстрый сервис и доступность.

Игрок выбирает компактный набор параметров:

- recipe
- packing level
- foil setting
- hole pattern
- coal layout
- lighting quality

Игра конвертирует выборы в `ExecutionScore`.

Quick mode должен быть значительно быстрее manual mode.

### 10.2 Manual mode

Назначение: signature mini-game игры.

Последовательность:

```text
Ingredients → mixing → bowl fill → foil → holes → coal placement → lighting
```

Игра должна давать ясный фидбэк, приятные звуки и визуальный отклик.

Manual mode должен быть достаточно прощающим, чтобы игрок учился через действие.

### Manual mode scoring

Предлагаемые sub-scores:

```text
MixAccuracy
PackingAccuracy
FoilAccuracy
HolePatternAccuracy
CoalPlacementAccuracy
LightingAccuracy
```

Затем:

```text
ExecutionScore = weighted average of sub-scores
```

Реалистичная симуляция горения не требуется.

---

## 11. Система жара и углей

У каждого активного кальяна есть:

```text
heat: 0..100
heat_state:
- too_cold
- normal
- too_hot
- burned
```

Жар меняется со временем.

Замена углей — interrupt-like service task для hookah master.

Целевой опыт игрока:

- небрежность заметна;
- провал поправим;
- одна ошибка не должна стирать 20-минутную сессию.

### Предлагаемые стартовые пороги

```text
0–24   too_cold
25–69  normal
70–89  too_hot
90–100 burned
```

Это балансные дефолты, они должны быть конфигурируемыми.

---

## 12. Hookah master

В MVP hookah master — простой service NPC.

Обязанности:

- идти к активному кальяну, когда угли требуют сервиса;
- заменять или обновлять угли;
- возвращаться в idle.

NPC не нуждается в сложном pathfinding в первом прототипе.

Task-based state machine достаточна:

```text
idle → go_to_hookah → service → return → idle
```

Если сервиса требуют несколько кальянов, использовать простую priority queue по срочности.

---

## 13. Re-preparation

Гость может запросить redo.

Поток:

```text
Guest feedback
→ player chooses redo or keep
→ preparation again
→ new score
→ guest reaction updated
```

Redo должен иметь цену:

- time cost;
- ingredient cost, если микс реально переделывается.

Но он также должен быть обучающей возможностью, а не чистым наказанием.

---

## 14. Модель гостя

MVP должен начинаться с 4–6 named friend NPCs.

У каждого гостя есть:

```text
id
name
personality
patience
preference_profile
likes[]
dislikes[]
preferred_strength
preferred_temperature
conversation_tags[]
```

Гости должны сообщать предпочтения естественным языком.

### Предлагаемые архетипы друзей

1. Sweet-tooth friend — любит сладкие фруктовые профили.
2. Freshness friend — любит mint/citrus профили.
3. Balanced friend — не любит крайности.
4. Experimental friend — вознаграждает необычные, но когерентные рецепты.
5. Heavy-profile friend — предпочитает более богатые, тяжёлые профили.
6. Social critic — даёт более явный фидбэк и учит системам.

Это игровые архетипы, а не фиксированные личностные стереотипы; диалоги можно настраивать независимо.

---

## 15. Модель реакции гостя

Ответ гостя имеет как минимум три слоя:

1. немедленная вербальная реакция;
2. satisfaction score;
3. эффект на деньги/репутацию/прогресс истории.

Предлагаемые bands:

```text
0–39   Bad
40–59  Weak
60–74  Okay
75–84  Good
85–94  Excellent
95–100 Exceptional
```

Игрок не обязательно должен видеть каждый внутренний вход в score.

---

## 16. Репутация

Единое MVP-значение репутации:

```text
0..100
```

Репутация меняется от результатов гостей и крупных story beats.

Предлагаемые стартовые эффекты:

```text
Excellent result: +2
Good result: +1
Okay: 0
Weak: -1
Burned hookah: additional -1 maximum per event
Exceptional discovery/story beat: special bonus
```

Все значения — балансные дефолты.

Репутация — в первую очередь progression/readability система, а не сложная социальная симуляция.

---

## 17. Деньги и экономика

MVP использует простой money loop.

Источники:

- оплата гостей
- небольшие story rewards

Стоки:

- ингредиенты
- мебель
- декоративные апгрейды

MVP должен быть достаточно щедрым, чтобы игрок экспериментировал без страха банкротства.

Избегать fail-state экономики в garage MVP.

---

## 18. UX книги рецептов

Книга рецептов — центральная фича.

Каждая запись должна показывать:

```text
Recipe name/auto-generated label
Ingredient list
Best score
Last score
Times used
Current trend indicator
```

Player-facing поведение:

- filter/search по ингредиенту;
- sort by best score or latest used;
- open recipe для повторного использования;
- различать player-discovered mixes от locked/unseen mixes.

Книга должна передавать discovery и ownership.

---

## 19. Система трендов

MVP использует небольшой набор trend-состояний.

Пример trend-измерений:

- fruit
- fresh
- sour
- sweet
- creamy
- unusual/experimental

Тренд длится определённый игровой период, затем меняется.

Система трендов должна быть достаточно детерминированной для тестов.

Для MVP предпочитать authored trend rotations, а не сложную процедурную генерацию.

---

## 20. Гараж и мебель

### Grid

Мебель размещается на логической 2D-сетке.

Каждый предмет имеет:

```text
id
name
price
size
rotation_allowed
category
comfort_bonus
atmosphere_bonus
sprite
```

### MVP-мебель

- small table
- chair
- couch
- wall picture
- lamp
- plant
- rug
- small shelf

Точный арт-инвентарь может меняться без изменения placement code.

### Правила размещения

- snap to grid;
- предотвращать overlap для solid furniture;
- разрешать удаление/перемещение owned items;
- визуально preview valid/invalid placement;
- сохранять позиции в save data.

---

## 21. Диалоговая система

Диалог должен быть data-driven и поддерживать:

- speaker
- text
- choices
- next node
- conditions
- effects
- event triggers

Пример концептуального узла:

```json
{
  "id": "friend_01_offer",
  "speaker": "denis",
  "text": "Слушай, а если попробовать пустить сюда кого-то кроме нас?",
  "choices": [
    {
      "text": "Давай попробуем",
      "next": "garage_mvp_end"
    },
    {
      "text": "Я ещё не готов",
      "next": "garage_mvp_end_alt"
    }
  ]
}
```

Dialogue engine не должен знать, что означает конкретный story beat; он должен эмитить события/эффекты, которые интерпретируют игровые системы.

---

## 22. Главные меню

MVP menu structure:

```text
Main Menu
├── New Game
├── Continue
├── Settings
└── Exit

Pause
├── Continue
├── Recipe Book
├── Furniture
├── Settings
└── Main Menu
```

Settings могут начинаться минимально:

- master volume
- music volume
- SFX volume
- fullscreen/window mode
- language placeholder (локализация для MVP не требуется)

---

## 23. Save game

Save data должна включать как минимум:

```text
current_story_node / story_progress
money
reputation
day_or_session_count
discovered_recipes
recipe_stats
owned_furniture
furniture_positions
current_trend
unlocked_ingredients
friend_progress
settings
```

Использовать versioned save data с самого начала.

Пример:

```text
save_version: 1
```

Будущая миграция вне скоупа, но формат должен быть идентифицируемым.

---

## 24. Аудио-направление

Самый запоминающийся звук в MVP должен быть у manual preparation.

Целевые sound moments:

- ingredient drag/drop
- bowl interaction
- foil placement
- hole creation
- coal placement
- lighter/lighting
- water/bubbling при затяжке
- guest reaction
- небольшие UI confirmations

Bubbling/draw sound должен быть приятным и узнаваемым как feedback reward.

Аудио-реализация может начаться с placeholder-ассетов.

---

## 25. Визуальное направление

Reference feeling:

- isometric/cozy social simulation;
- читаемая планировка комнаты;
- тёплый интерьер в контрасте с простым окружением;
- выразительные, но экономные 2D-персонажи;
- ясные интерактивные объекты.

Не блокировать инженерию на финальном арте.

MVP должен работать с placeholder-артом и позже заменять ассеты без переписывания игровых систем.

---

## 26. Заметка о content research

Реальная совместимость вкусов кальяна — это content research, а не core architecture.

Начальная data table должна считаться tunable game content. Проект ведёт поддерживающие заметки в `docs/RECIPE_RESEARCH.md`.

Research должен вдохновлять на правдоподобные сочетания, а финальные числовые значения остаются game-balance значениями, а не утверждениями о научной или универсальной истине вкуса.

---

## 27. UX-принципы

- Игрок всегда должен знать, какое действие доступно.
- Провал должен быть читаемым и поправимым.
- Важное состояние должно иметь и визуальный, и текстовый фидбэк.
- Скрытые системы могут существовать, но игрок должен учиться им по исходам.
- Избегать чрезмерных floating numbers.
- Держать центральный цикл в одном-двух кликах.

---

## 28. Критерии успеха MVP

MVP успешен, когда новый игрок может пройти этот цикл без внешнего объяснения:

```text
Start → meet friend → choose/create mix → prepare → serve
      → observe reaction → understand result → change mix or technique
      → save progress → decorate garage → discover 3 strong mixes
      → reach the outside-guest invitation ending
```

Игра должна ощущаться связным коротким playable-опытом, а не коллекцией разрозненных прототипов.