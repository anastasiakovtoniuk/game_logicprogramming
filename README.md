# Reversi — гра на Prolog

Реалізація гри Реверсі (Отелло) на SWI-Prolog з веб-інтерфейсом та AI на основі алгоритму MinMax з відсіканням Альфа-Бета.

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
- Евристика: таблиця вагових коефіцієнтів позицій + кількість фішок в ендшпілі

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

## Джерела

- Russell, Norvig — *Artificial Intelligence: A Modern Approach*, розд. 5
- Документація SWI-Prolog HTTP: https://www.swi-prolog.org/pldoc/man?section=http
- Евристика Реверсі: https://www.samsoft.org.uk/reversi/strategy.html
- https://discourse.haskell.org/t/reversi-applying-moves-with-case-of-and-pattern-matching/12922
- https://www.haskell.org/documentation/

[Презентація PowerPoint](https://ukmaedu-my.sharepoint.com/:p:/g/personal/a_kovtoniuk_ukma_edu_ua/IQAm5_7BfjHMS4mxiSAAE0d0ATqgF670Txfx2HgdsVn5fZA?e=eempf1)
