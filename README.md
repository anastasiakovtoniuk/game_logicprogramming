# Reversi — гра на Prolog

Реалізація гри Реверсі (Отелло) на SWI-Prolog з веб-інтерфейсом та AI на основі алгоритму MinMax з відсіканням Альфа-Бета.

## Запуск

1. Запустити сервер:
   ```
   "C:\Program Files\swipl\bin\swipl.exe" reversi.pl
   ```
   або двічі клікнути `start.bat`.

2. Відкрити у браузері: `http://localhost:8080/`

## Структура проєкту

```
reversi.pl       — логіка гри, алгоритм MinMax, HTTP-сервер
public/
  index.html     — веб-інтерфейс
  style.css      — стилі
  game.js        — контролер (JS ↔ Prolog через REST API)
start.bat        — скрипт запуску для Windows
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
