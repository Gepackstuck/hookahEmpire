# Hookah Empire — MVP Plan v0.1

## Цель

Построить связный Garage MVP из пустого проекта Godot 4.7.2 до 20-минутного playable-интро, заканчивающегося приглашением принять первых внешних гостей.

## Карта milestones

```text
M0 Foundation
 ↓
M1 Garage + Player
 ↓
M2 Dialogue + Friends
 ↓
M3 Ingredients + Recipes + Recipe Book
 ↓
M4 Quick Preparation
 ↓
M5 Manual Preparation
 ↓
M6 Guest Session + Scoring
 ↓
M7 Heat + Charcoal + Re-preparation
 ↓
M8 Trends + Economy + MVP Progression
 ↓
M9 Furniture + Garage Customization
 ↓
M10 20-minute Intro Vertical Slice
 ↓
M11 Save/Load + Menus + Polish + QA
 ↓
MVP DONE
```

---

# M0 — Foundation

## Задача

Создать стабильную структуру проекта, которую Беброид сможет расширять без превращения кодовой базы в монолит.

## Реализовать

- Git repository hygiene.
- Структура папок.
- Main scene boot flow.
- Базовые project settings.
- Data directories.
- Placeholder UI theme.
- Минимальный game state service/autoload.
- Минимальный save service skeleton.
- Convention для debug logging.
- Documentation links.

## Ожидаемая структура

```text
project.godot
AGENTS.md
scenes/
scripts/
data/
art/
audio/
ui/
docs/
```

## Acceptance criteria

- Проект открывается в Godot 4.7.2 без parse-ошибок.
- Проект запускается с main scene.
- Виден минимальный placeholder screen.
- Core-папки существуют.
- Ни одна игровая система не дублируется.
- `docs/PROGRESS.md` обновлён.

## Ручная верификация

1. Открыть проект.
2. Запустить проект.
3. Закрыть и переоткрыть редактор.
4. Запустить снова.

---

# M1 — Garage + Player

## Задача

Сделать сам гараж играбельным.

## Реализовать

- Одна garage map.
- Isometric 2D camera.
- Player movement.
- Базовая collision.
- Interaction detection.
- Interactable markers/prompts.
- Один test table и один test hookah.

## Acceptance criteria

- Игрок может входить/выходить из основной walkable зоны.
- Камера следует корректно.
- Игрок не может пройти сквозь заблокированную мебель/стены.
- Игрок может подойти к interactable и запустить test interaction.
- Нет зависимости от финального арта.

## Ручная верификация

Пройтись по гаражу 2–3 минуты, взаимодействовать со столом и кальяном, подтвердить работу prompts/interaction.

---

# M2 — Dialogue + Friends

## Задача

Создать первый human-facing narrative layer.

## Реализовать

- Dialogue UI.
- Dialogue data schema.
- Dialogue runner.
- Choice buttons.
- Conditions/effects.
- Friend NPC spawn.
- Базовые guest idle/walk states.
- Story progression variable.

## Acceptance criteria

- Друг входит в гараж.
- Друг останавливается в target location.
- Диалог открывается автоматически или через interaction.
- Choice может ветвить на другой node.
- Диалог может установить gameplay state/effect.
- Dialogue content хранится как data, а не хардкодится в dialogue script.

## Ручная верификация

```text
Start game → друг приходит → завершить разговор
→ выбрать как минимум два разных варианта
→ подтвердить правильную ветку/state
```

---

# M3 — Ingredients + Recipes + Recipe Book

## Задача

Реализовать core discovery system до качества приготовления.

## Реализовать

- Ingredient data model.
- Ingredient catalog loader.
- Recipe canonicalization.
- Recipe ID generation.
- Recipe storage.
- Recipe statistics.
- Taste profile calculation.
- Base recipe quality calculation.
- Recipe Book UI.
- Create/reuse recipe flow.

## Acceptance criteria

- Как минимум 12 ingredient records загружаются из data.
- Игрок может составить микс из нескольких ингредиентов.
- Пропорции нормализуются корректно.
- Повторное использование того же canonical mix не создаёт дубликат рецепта.
- Новый микс появляется в recipe book игрока.
- Best/last result fields обновляются корректно.
- Core recipe math независим от UI.

## Ручная верификация

Создать три разных микса, переоткрыть recipe book, закрыть/переоткрыть игру, если save уже функционален, и подтвердить логическую консистентность записей.

---

# M4 — Quick Preparation

## Задача

Завершить полное hookah-preparation interaction в быстром режиме.

## Реализовать

- Recipe selection.
- Quick preparation panel.
- Parameter controls.
- Execution score calculation.
- Preparation completion event.
- Basic result screen.

## Acceptance criteria

- Выбранный рецепт можно приготовить от начала до конца.
- Разные parameter choices могут давать разные execution scores.
- Результат возвращается в calling guest/session.
- Фича переиспользуема несколькими гостями.

## Ручная верификация

Приготовить один и тот же рецепт дважды с намеренно разными parameter choices и подтвердить различие execution scores.

---

# M5 — Manual Preparation Mini-game

## Задача

Реализовать signature interaction игры.

## Реализовать

- Manual preparation scene.
- Ingredient drag/drop.
- Bowl fill interaction.
- Foil interaction.
- Hole placement.
- Coal placement.
- Lighting interaction.
- Progress/feedback indicators.
- Sound placeholders.
- Execution score result.

## Acceptance criteria

- Полную manual sequence можно пройти без dead ends.
- Действия игрока влияют как минимум на 3 internal quality sub-scores.
- Плохая manual-попытка даёт измеримо другой результат, чем аккуратная.
- Scene можно запускать и закрывать многократно без порчи main game state.
- UI остаётся понятным при первом использовании.

## Ручная верификация

Выполнить один rushed/poor run и один careful run. Подтвердить, что careful run даёт лучший `ExecutionScore` и что оба безопасно возвращаются в guest session.

---

# M6 — Guest Session + Scoring

## Задача

Связать рецепты и приготовление со значимыми реакциями гостей.

## Реализовать

- Guest preference profiles.
- Guest fit calculation.
- Trend fit placeholder/interface.
- Context score.
- Final score.
- Guest feedback text.
- Satisfaction bands.
- Payment calculation.
- Reputation event hooks.

## Acceptance criteria

- Два гостя с разными предпочтениями могут по-разному реагировать на один рецепт.
- Качество приготовления меняет final score.
- Guest reaction band соответствует final score.
- Генерируется payment.
- Recipe book записывает best/last result.
- Scoring тестируется с детерминированными входами.

## Ручная верификация

Подать один микс двум контрастным друзьям. Подтвердить, что их исходы могут отличаться даже при идентичном качестве приготовления.

---

# M7 — Heat + Charcoal + Re-preparation

## Задача

Ввести лёгкое service-management давление.

## Реализовать

- Hookah heat state.
- Time-based heat change.
- Normal/cold/hot/burned thresholds.
- Hookah master task state machine.
- Charcoal replacement.
- Heat penalty.
- Guest redo request.
- Second preparation attempt.

## Acceptance criteria

- Heat активного кальяна меняется со временем.
- Hookah master может обслужить кальян.
- Игнорирование кальяна может привести его в нежелательное состояние.
- Burnout применяет ограниченный penalty, а не hard failure.
- Гость может запросить redo.
- Redo тратит time и/или resources и обновляет final result.

## Ручная верификация

Дать одному кальяну перегреться и восстановить его через charcoal service. В отдельном прогоне дать ему сгореть и подтвердить penalty. Триггернуть guest redo и подтвердить, что второй результат заменяет/обновляет первый.

---

# M8 — Trends + Economy + MVP Progression

## Задача

Создать фактический experiment/progression loop.

## Реализовать

- Trend state.
- Authored trend rotation.
- Trend influence on score.
- Money balance.
- Ingredient costs.
- Reward rules.
- Reputation gain/loss.
- Three strong-recipes progression goal.
- End-of-MVP story trigger.

## Acceptance criteria

- Смена активного тренда меняет TrendFit.
- Один и тот же рецепт может работать по-разному под разными трендами.
- Игрок зарабатывает и тратит деньги.
- Репутация меняется от исходов гостей.
- Progress counter отслеживает qualifying strong recipes.
- Завершение progression condition триггерит ending dialogue.
- Ending явно указывает на будущих внешних гостей, но не загружает следующий бизнес-этап.

## Ручная верификация

Использовать известный test recipe под двумя trend states и проверить, что final score может меняться. Заработать деньги, потратить часть, затем завершить 3-recipe goal.

---

# M9 — Furniture + Garage Customization

## Задача

Сделать гараж персонально кастомизируемым.

## Реализовать

- Furniture catalog.
- Purchase flow.
- Grid placement.
- Rotate where applicable.
- Move/remove owned items.
- Placement validity preview.
- Atmosphere/comfort values.
- Garage stat summary.

## Acceptance criteria

- Игрок может купить как минимум 6 furniture/decor items.
- Items snap to grid.
- Invalid overlap блокируется.
- Позиции остаются стабильными после выхода/возвращения в гараж.
- Furniture values могут влиять на небольшой contextual bonus, не доминируя над recipe/guest scoring.

## Ручная верификация

Купить table, picture, lamp и plant. Разместить, переместить и удалить их. Подтвердить, что гараж ведёт себя корректно и overlap не возникает.

---

# M10 — 20-minute Intro Vertical Slice

## Задача

Связать системы в одно связное playable-интро.

## Реализовать

- Intro pacing.
- Friend arrival schedule.
- Story gates.
- Tutorial hints.
- Recipe discovery beats.
- Manual mode introduction.
- Heat/service beat.
- Furniture beat.
- Three strong recipes goal.
- Final invitation scene.

## Acceptance criteria

Новый игрок может пройти намеренную последовательность без вмешательства разработчика:

```text
Start
→ first friend
→ first hookah
→ second friend
→ recipe discovery
→ manual preparation
→ heat/charcoal
→ garage decoration
→ 3 strong recipes
→ final dialogue
→ MVP end state
```

Путь должен быть понятен без чтения проектных доков.

## Ручная верификация

Играть с чистого save и записать примерное время каждого story beat. Целевая общая длительность: ~20 минут; точный тайминг может варьироваться во время баланса.

---

# M11 — Save/Load + Menus + Polish + QA

## Задача

Превратить vertical slice в стабильный MVP build.

## Реализовать

- New Game.
- Continue.
- Save.
- Load.
- Pause.
- Settings.
- Audio persistence.
- Save version.
- Error handling.
- Tutorial cleanup.
- UI consistency.
- Basic performance cleanup.
- Bug-fix pass.

## Acceptance criteria

- New Game запускает чистый run.
- Continue загружает ранее сохранённый run.
- Важное game state переживает save/load.
- Furniture positions переживают save/load.
- Recipe book переживает save/load.
- Story progress переживает save/load.
- Settings переживают restart.
- Нет известных blocker, мешающих пройти интро.
- Нет известных воспроизводимых progression deadlock.

## Ручная верификация

Сохранять в нескольких точках, закрывать/открывать игру, продолжать и проверять story, recipes, money, reputation и furniture state.

---

# MVP Exit Checklist

Всё должно быть true перед объявлением MVP complete:

- [ ] Game запускается в playable garage.
- [ ] Player movement и interaction работают.
- [ ] Friends приходят и используют dialogue system.
- [ ] Ingredient data загружается корректно.
- [ ] Recipe creation/canonicalization работает.
- [ ] Recipe Book работает.
- [ ] Quick preparation работает.
- [ ] Manual preparation работает.
- [ ] Preparation влияет на результат.
- [ ] Guest preferences влияют на результат.
- [ ] Trends влияют на результат.
- [ ] Heat/charcoal loop работает.
- [ ] Re-preparation работает.
- [ ] Money работает.
- [ ] Reputation работает.
- [ ] Furniture placement работает.
- [ ] Save/load работает.
- [ ] Main menu/pause/settings работают.
- [ ] Intro играется end-to-end.
- [ ] Three strong recipes достижимы.
- [ ] MVP заканчивается outside-guest invitation.
- [ ] Ни один future business stage не требуется для завершения MVP.

---

# Правила для будущих milestone-промптов

При запросе к Беброиду на реализацию milestone:

1. Назвать ровно один milestone.
2. Сказать прочитать релевантные секции GDD и архитектуры.
3. Сказать не реализовывать последующие milestones.
4. Требовать верификацию.
5. Требовать обновление `docs/PROGRESS.md`.
6. Запрашивать changed files и test results.