# Hookah Empire — Recipe Research Notes v0.1

## Назначение

Этот документ — content-research workspace для flavor-combination references, которые позже будут питать recipe data игры.

Цель — не представить какую-то комбинацию как универсально правильную. Игре нужны правдоподобные, интересные и сбалансированные отношения между вкусовыми ингредиентами.

## Research workflow

Для каждого ингредиента/пары:

1. Записать source.
2. Записать наблюдаемое/распространённое pairing.
3. Записать, описывается ли оно как complementary, contrasting или generally unpopular.
4. Конвертировать качественное наблюдение в **game-balance value**.
5. Держать source note отдельно от финального numeric balance.

## Предлагаемая таблица

| Ingredient A | Ingredient B | Relationship | Confidence | Game synergy | Source / note |
|---|---|---|---:|---:|---|
| strawberry | mint | TBD | TBD | TBD | Research needed |
| strawberry | lemon | TBD | TBD | TBD | Research needed |
| watermelon | mint | TBD | TBD | TBD | Research needed |
| grape | mint | TBD | TBD | TBD | Research needed |
| peach | lemon | TBD | TBD | TBD | Research needed |
| mango | mint | TBD | TBD | TBD | Research needed |
| blueberry | lemon | TBD | TBD | TBD | Research needed |
| vanilla | lemon | TBD | TBD | TBD | Research needed |
| cola | lemon | TBD | TBD | TBD | Research needed |
| lime | mint | TBD | TBD | TBD | Research needed |

## Важная implementation note

Не блокировать кодовую базу на завершении этого документа.

M3 может использовать временные balance values, чтобы RecipeSystem и Recipe Book стали тестируемыми. Заменить временную matrix после research-прохода.