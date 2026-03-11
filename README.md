# Reversi / Othello — гра на Prolog та Haskell

Реалізація гри Реверсі (Отелло) на SWI-Prolog з веб-інтерфейсом та AI на основі алгоритму MinMax з відсіканням Альфа-Бета.

Завдання виконано командою:
- **Малій Олександра** — реалізація Prolog-підходу (~33%)
- **Ковтонюк Анастасія** — реалізація Haskell-підходу (~33%)
- **Пігуляк Антон** — підготовка та презентація матеріалу (~33%)

У проєкті є **дві серверні реалізації**:
- **Prolog** — оригінальна реалізація логіки гри та AI
- **Haskell** — альтернативна реалізація з тією самою логікою та сумісним REST API

Фронтенд (`HTML/CSS/JS`) спільний для обох реалізацій і працює через `http://localhost:8080/`.

## Запуск

1. Запустити сервер:
   ```
   "C:\Program Files\swipl\bin\swipl.exe" reversi.pl
   або
   & "C:\Program Files\swipl\bin\swipl.exe" .\reversi.pl 
   ```
   або двічі клікнути `start.bat`.
   
   Щоб запустити Haskell сервер:
   cabal run reversi-hs

2. Відкрити у браузері: `http://localhost:8080/`

## Структура проєкту

```
reversi.pl         — Prolog-реалізація гри, AI та HTTP-сервера
Reversi.hs         — Haskell-реалізація логіки гри та AI
Main.hs            — Haskell HTTP-сервер
reversi-hs.cabal   — Cabal-конфігурація для Haskell-запуску
start.bat          — запуск Prolog-сервера у Windows
public/
  index.html       — веб-інтерфейс
  style.css        — стилі
  game.js          — контролер (JS ↔ REST API)
README.md          — опис проєкту

```
## Алгоритм

**MinMax з відсіканням Альфа-Бета:**
- Чорні (гравець 1) — MAX-вузол, білі (гравець 2) — MIN-вузол
- Оцінка позиції з точки зору чорних (позитивна = перевага чорних)
- Глибина задається в пів-ходах (плаях): 2 / 4 / 6 / 8
- Ходи сортуються за позиційною вагою перед пошуком (покращує відсікання у 2–4×)

**Евристика оцінки позиції:**

| Позиція | Вага | Пояснення |
|---------|------|-----------|
| Кути | +100 | Абсолютно стабільні, ніколи не перевертаються |
| Суміжні з кутом (по краю) | −20 | Небезпечні: «дарують» кут суперникові |
| Діагональні від кута | −50 | Найгірші позиції на дошці |
| Решта краю | +10 | Відносно стабільні |
| Внутрішні | −1..+1 | Нейтральні; краще ближче до центру |

Рання гра: позиційна оцінка + мобільність × 10 (різниця кількості допустимих ходів).
Ендшпіль (>75% клітинок заповнено): виключно різниця кількості фішок × 10.

## Режими гри

| Режим | Опис |
|-------|------|
| Human vs Human | Двоє гравців за одним комп'ютером |
| Human vs AI | Людина проти Prolog AI (колір призначається випадково) |
| AI vs AI | Два AI грають між собою |

## REST API

| Endpoint | Метод | Опис |
|----------|-------|------|
| `/api/new_game` | GET | Початковий стан дошки |
| `/api/make_move` | POST | Виконати хід людини |
| `/api/ai_move` | POST | Обчислити та виконати хід AI |

## Структура коду

```
reversi.pl
  ├── HTTP-маршрути та запуск сервера
  ├── Розмір дошки (динамічний факт board_size/1)
  ├── Операції над дошкою (get_cell, set_cell, initial_board)
  ├── Логіка гри (scan_line, all_flips, valid_move, make_move, game_over)
  ├── Функція оцінки позиції (cell_weight_rc, evaluate_flat, evaluate)
  └── MinMax + Alpha-Beta (minimax, max_search, min_search, sort_moves)

Reversi.hs
  ├── Типи (Cell, Board, Winner, NextState, SearchResult)
  ├── Операції над дошкою (boardFromFlatAuto, flattenBoard, initialBoard)
  ├── Логіка гри (scanLine, allFlips, validMove, makeMove, gameOver)
  ├── Евристика (cellWeight, evaluatePositional, evaluate)
  └── MinMax + Alpha-Beta (minimax, chooseBestMove)

Main.hs
  └── HTTP-сервер Scotty + JSON-серіалізація + роздача static files
```

## Першоджерела використаних кодів

Уся ігрова логіка, евристика та архітектура розроблені авторами самостійно.
Зовнішні бібліотеки використані за стандартною документацією:
- SWI-Prolog: `http/thread_httpd`, `http_dispatch`, `http_json` — офіційна документація
- Haskell: бібліотеки `scotty`, `aeson`, `array` — Hackage документація

## Джерела

1. Russell S. J. Artificial Intelligence: A Modern Approach / S. J. Russell, P. Norvig. — 4th ed. — Hoboken : Pearson, 2020. — 1132 p. — (Розд. 5 : Adversarial Search and Games).
2. SWI-Prolog HTTP server libraries [Електронний ресурс] // SWI-Prolog Reference Manual. — Режим доступу : https://www.swi-prolog.org/pldoc/man?section=http. — Назва з екрана. — (Дата звернення: 11.03.2026).
3. Wilson R. Reversi strategy guide [Електронний ресурс] / R. Wilson // Sam's Reversi Page. — Режим доступу : https://www.samsoft.org.uk/reversi/strategy.html. — Назва з екрана. — (Дата звернення: 11.03.2026).
4. Reversi — applying moves with case of and pattern matching [Електронний ресурс] // Haskell Discourse. — Режим доступу : https://discourse.haskell.org/t/reversi-applying-moves-with-case-of-and-pattern-matching/12922. — Назва з екрана. — (Дата звернення: 11.03.2026).
5. Haskell documentation [Електронний ресурс] // Haskell.org. — Режим доступу : https://www.haskell.org/documentation/. — Назва з екрана. — (Дата звернення: 11.03.2026).

[Презентація PowerPoint](https://ukmaedu-my.sharepoint.com/:p:/g/personal/a_kovtoniuk_ukma_edu_ua/IQAm5_7BfjHMS4mxiSAAE0d0ATqgF670Txfx2HgdsVn5fZA?e=eempf1)
