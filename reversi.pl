% ==============================================================
% Reversi (Отелло) — реалізація на Prolog
% Алгоритм: MinMax з відсіканням Альфа-Бета
% HTTP-сервер: SWI-Prolog, порт 8080
% Веб-інтерфейс: відкрити http://localhost:8080/ у браузері
% ==============================================================

:- module(reversi, []).

:- use_module(library(http/thread_httpd)).    % HTTP-сервер у потоці
:- use_module(library(http/http_dispatch)).   % диспетчеризація запитів
:- use_module(library(http/http_json)).       % JSON: читання / відповідь
:- use_module(library(http/http_files)).      % роздача статичних файлів
:- use_module(library(lists)).
:- use_module(library(apply)).                % maplist/3, foldl/4
:- use_module(library(aggregate)).            % aggregate_all/3


% ==============================================================
% HTTP-маршрути та запуск сервера
% ==============================================================

:- http_handler(root(api/new_game),    handle_new_game,    []).
:- http_handler(root(api/valid_moves), handle_valid_moves, []).
:- http_handler(root(api/make_move),   handle_make_move,   []).
:- http_handler(root(api/ai_move),     handle_ai_move,     []).
% Статичні файли (HTML/CSS/JS) — найнижчий пріоритет
:- http_handler(root(.),               serve_static,       [prefix, priority(-100)]).

% serve_static(++Request)
% Роздає файли з папки public/ (зокрема index.html за замовчуванням).
%
serve_static(Request) :-
    http_reply_from_files(public, [indexes(['index.html'])], Request).

% start_server(++Port)
% Запускає HTTP-сервер і блокує головний потік (щоб процес не завершився).
%
% Мультипризначення:
%   start_server(++Port) — запуск; тільки один змістовний режим.
%
start_server(Port) :-
    http_server(http_dispatch, [port(Port)]),
    format("~n=== Reversi server started ===~n"),
    format("Open in browser: http://localhost:~w/~n~n", [Port]),
    % Якщо запущено неінтерактивно (наприклад, через start.bat),
    % блокуємо головний потік щоб сервер не завершився одразу.
    (   current_prolog_flag(interactive, true)
    ->  true
    ;   thread_get_message(stop)    % чекаємо повідомлення 'stop'
    ).

:- initialization(start_server(8080), main).


% ==============================================================
% Представлення дошки
%
% Дошка = плаский список із 64 цілих чисел (рядковий порядок):
%   0 = порожня клітинка
%   1 = чорна фішка
%   2 = біла фішка
% Індекс клітинки (Row, Col): Index = Row * 8 + Col  (0-базовий)
% ==============================================================

% initial_board(--Board)
% Створює початкову розстановку Реверсі:
%   4 фішки в центрі дошки (класична початкова позиція).
%
% Мультипризначення:
%   initial_board(--Board) — генерація початкової дошки.
%   initial_board(+Board)  — перевірка; але практично не застосовується.
%
initial_board(Board) :-
    length(Empty, 64),
    maplist(=(0), Empty),              % 64 порожні клітинки
    set_cell(Empty,  3, 3, 2, B1),    % біла  (рядок 3, стовп 3)
    set_cell(B1,     3, 4, 1, B2),    % чорна (рядок 3, стовп 4)
    set_cell(B2,     4, 3, 1, B3),    % чорна (рядок 4, стовп 3)
    set_cell(B3,     4, 4, 2, Board). % біла  (рядок 4, стовп 4)

% in_bounds(++Row, ++Col)
% Перевіряє, що клітинка (Row, Col) знаходиться всередині дошки 8×8.
%
% Мультипризначення:
%   in_bounds(++Row, ++Col) — перевірка меж; детермінований.
%   Зворотний режим (генерація Row/Col) теоретично можливий через
%   between/3, але не застосовується — є valid_moves/3.
%
in_bounds(Row, Col) :-
    Row >= 0, Row =< 7,
    Col >= 0, Col =< 7.

% cell_index(++Row, ++Col, --Index)
% Обчислює лінійний індекс клітинки в списку-дошці.
%
% Мультипризначення:
%   cell_index(++Row, ++Col, --Index) — обчислення індексу.
%   Зворотний режим (Row/Col з Index) неоднозначний — не застосовується.
%
cell_index(Row, Col, Index) :-
    in_bounds(Row, Col),
    Index is Row * 8 + Col.

% get_cell(++Board, ++Row, ++Col, --Value)
% Повертає значення клітинки дошки за координатами.
%
% Мультипризначення:
%   get_cell(++Board, ++Row, ++Col, --Value) — читання значення.
%   get_cell(++Board, ++Row, ++Col,  +Value) — перевірка значення.
%
get_cell(Board, Row, Col, Value) :-
    cell_index(Row, Col, Index),
    nth0(Index, Board, Value).        % nth0: індекс від 0

% set_cell(++Board, ++Row, ++Col, ++Value, --NewBoard)
% Повертає нову дошку із заміненим значенням у клітинці (Row, Col).
%
% Мультипризначення:
%   set_cell(++Board, ++Row, ++Col, ++Value, --NewBoard) — запис у клітинку.
%   Тільки цей режим є змістовним.
%
set_cell(Board, Row, Col, Value, NewBoard) :-
    cell_index(Row, Col, Index),
    replace_nth0(Index, Board, Value, NewBoard).

% replace_nth0(++N, ++List, ++Value, --NewList)
% Замінює N-й (від 0) елемент списку List на Value.
%
% Мультипризначення:
%   replace_nth0(++N, ++List, ++Value, --NewList) — заміна елементу.
%
replace_nth0(0, [_|Tail], Value, [Value|Tail]) :- !.
replace_nth0(N, [Head|Tail], Value, [Head|NewTail]) :-
    N > 0,
    N1 is N - 1,
    replace_nth0(N1, Tail, Value, NewTail).


% ==============================================================
% Логіка гри: допустимі ходи та виконання ходу
% ==============================================================

% opponent(++Player, --Opponent)
% Повертає суперника гравця.
%
% Мультипризначення:
%   opponent(++Player, --Opponent) — отримати суперника.
%   opponent( -Player, ++Opponent) — знайти гравця за суперником.
%
opponent(1, 2).
opponent(2, 1).

% Вісім напрямків руху на дошці: (зміна рядка, зміна стовпця)
direction(-1, -1). direction(-1, 0). direction(-1, 1).
direction( 0, -1).                   direction( 0, 1).
direction( 1, -1). direction( 1, 0). direction( 1, 1).

% scan_line(++Board, ++Row, ++Col, ++DR, ++DC,
%           ++Player, ++Opponent, ++Acc, --Flips)
% Рекурсивно іде в напрямку (DR,DC) від (Row,Col), збираючи фішки
% суперника в Acc. Повертає Flips = Acc, якщо знайдено свою фішку.
% Повертає Flips = [], якщо рядок "незамкнений".
%
% Мультипризначення:
%   scan_line(++,++,++,++,++,++,++,+,--) — пошук фішок для перевертання.
%   Тільки один змістовний режим.
%
scan_line(Board, Row, Col, DR, DC, Player, Opponent, Acc, Flips) :-
    NextRow is Row + DR,
    NextCol is Col + DC,
    (   \+ in_bounds(NextRow, NextCol)
    ->  Flips = []                              % вийшли за межі — нічого захопити
    ;   get_cell(Board, NextRow, NextCol, Cell),
        (   Cell =:= Player
        ->  Flips = Acc                         % своя фішка — лінія замкнена!
        ;   Cell =:= Opponent
        ->  scan_line(Board, NextRow, NextCol, DR, DC, Player, Opponent,
                      [NextRow-NextCol | Acc], Flips)
        ;   Flips = []                          % порожня клітинка — розрив лінії
        )
    ).

% flips_in_direction(++Board, ++Row, ++Col, ++DR, ++DC, ++Player, --Flips)
% Фішки суперника, які будуть перевернуті в напрямку (DR,DC),
% якщо Player поставить фішку на (Row,Col).
%
% Мультипризначення:
%   flips_in_direction(++,++,++,++,++,++,--) — отримати список для перевертання.
%
flips_in_direction(Board, Row, Col, DR, DC, Player, Flips) :-
    opponent(Player, Opponent),
    NextRow is Row + DR,
    NextCol is Col + DC,
    % Перша клітинка у напрямку має бути фішкою суперника
    (   in_bounds(NextRow, NextCol),
        get_cell(Board, NextRow, NextCol, Opponent)
    ->  scan_line(Board, NextRow, NextCol, DR, DC, Player, Opponent,
                  [NextRow-NextCol], Flips)
    ;   Flips = []
    ).

% all_flips(++Board, ++Row, ++Col, ++Player, --AllFlips)
% Усі фішки суперника, що перевертаються при ході Player на (Row,Col).
% Збирає результати по всіх 8 напрямках.
%
% Мультипризначення:
%   all_flips(++Board,++Row,++Col,++Player,--AllFlips) — основне призначення.
%
all_flips(Board, Row, Col, Player, AllFlips) :-
    findall(
        DirFlips,
        (   direction(DR, DC),
            flips_in_direction(Board, Row, Col, DR, DC, Player, DirFlips),
            DirFlips \= []
        ),
        Groups
    ),
    append(Groups, AllFlips).          % об'єднуємо списки всіх напрямків

% valid_move(++Board, ++Row, ++Col, ++Player)
% Хід (Row,Col) є допустимим: клітинка порожня і є хоча б одне захоплення.
%
% Мультипризначення:
%   valid_move(++Board, ++Row, ++Col, ++Player) — перевірка ходу.
%
valid_move(Board, Row, Col, Player) :-
    get_cell(Board, Row, Col, 0),
    all_flips(Board, Row, Col, Player, Flips),
    Flips \= [].

% valid_moves(++Board, ++Player, --Moves)
% Список усіх допустимих ходів для гравця у вигляді Row-Col пар.
%
% Мультипризначення:
%   valid_moves(++Board, ++Player, --Moves) — генерація списку ходів.
%   valid_moves(++Board, ++Player,  +Moves) — перевірка списку.
%
valid_moves(Board, Player, Moves) :-
    findall(
        Row-Col,
        (   between(0, 7, Row),
            between(0, 7, Col),
            valid_move(Board, Row, Col, Player)
        ),
        Moves
    ).

% flip_cells(++Board, ++Flips, ++Player, --NewBoard)
% Перевертає всі фішки зі списку Flips у колір Player.
%
% Мультипризначення:
%   flip_cells(++Board, ++Flips, ++Player, --NewBoard) — перевертання.
%
flip_cells(Board, [],              _Player, Board).
flip_cells(Board, [Row-Col | Rest], Player, NewBoard) :-
    set_cell(Board, Row, Col, Player, Temp),
    flip_cells(Temp, Rest, Player, NewBoard).

% make_move(++Board, ++Row, ++Col, ++Player, --NewBoard)
% Виконує хід: ставить фішку Player на (Row,Col) і перевертає захоплені.
%
% Мультипризначення:
%   make_move(++Board,++Row,++Col,++Player,--NewBoard) — виконання ходу.
%
make_move(Board, Row, Col, Player, NewBoard) :-
    all_flips(Board, Row, Col, Player, Flips),
    set_cell(Board, Row, Col, Player, BoardAfterPlace),
    flip_cells(BoardAfterPlace, Flips, Player, NewBoard).

% count_pieces(++Board, ++Player, --Count)
% Кількість фішок гравця Player на дошці.
%
% Мультипризначення:
%   count_pieces(++Board, ++Player, --Count) — підрахунок фішок.
%
count_pieces(Board, Player, Count) :-
    aggregate_all(count, member(Player, Board), Count).

% game_over(++Board, --Winner)
% Перевіряє кінець гри (жоден гравець не може ходити).
% Winner = 1 (чорні), 2 (білі), 0 (нічия).
%
% Мультипризначення:
%   game_over(++Board, --Winner) — перевірка та визначення переможця.
%
game_over(Board, Winner) :-
    valid_moves(Board, 1, []),
    valid_moves(Board, 2, []),
    count_pieces(Board, 1, Black),
    count_pieces(Board, 2, White),
    (   Black > White -> Winner = 1
    ;   White > Black -> Winner = 2
    ;   Winner = 0
    ).


% ==============================================================
% Функція оцінки позиції
%
% Оцінка ЗАВЖДИ з точки зору чорних (гравець 1):
%   позитивна = перевага чорних
%   негативна = перевага білих
% ==============================================================

% Таблиця вагових коефіцієнтів позицій (стандартна евристика Реверсі):
%   кути (+100) — найцінніші, назавжди залишаються у гравця
%   клітинки поряд з кутом (-20/-50) — небезпечні, дають кут суперникові
%   краї (+10/+5) — стабільні позиції
%   центр (-1/-2) — нейтральні чи злегка негативні
position_weights([
    100, -20,  10,   5,   5,  10, -20, 100,
    -20, -50,  -2,  -2,  -2,  -2, -50, -20,
     10,  -2,  -1,  -1,  -1,  -1,  -2,  10,
      5,  -2,  -1,  -1,  -1,  -1,  -2,   5,
      5,  -2,  -1,  -1,  -1,  -1,  -2,   5,
     10,  -2,  -1,  -1,  -1,  -1,  -2,  10,
    -20, -50,  -2,  -2,  -2,  -2, -50, -20,
    100, -20,  10,   5,   5,  10, -20, 100
]).

% calc_weighted(++Cells, ++Weights, +Acc, --Score)
% Рекурсивно обчислює зважену суму (чорні +W, білі -W).
%
calc_weighted([],     [],     Acc, Acc).
calc_weighted([C|Cs], [W|Ws], Acc, Score) :-
    (   C =:= 1 -> A1 is Acc + W   % чорна фішка — додаємо вагу
    ;   C =:= 2 -> A1 is Acc - W   % біла фішка  — віднімаємо вагу
    ;   A1 = Acc                    % порожньо     — пропускаємо
    ),
    calc_weighted(Cs, Ws, A1, Score).

% evaluate(++Board, --Score)
% Оцінює поточну позицію з точки зору чорних.
% Рання гра: позиційна оцінка; пізня гра: перевага у фішках.
%
% Мультипризначення:
%   evaluate(++Board, --Score) — обчислення евристичної оцінки.
%
evaluate(Board, Score) :-
    position_weights(Weights),
    calc_weighted(Board, Weights, 0, PosScore),
    count_pieces(Board, 1, Black),
    count_pieces(Board, 2, White),
    Total is Black + White,
    % Ендшпіль (залишилось мало порожніх): кількість фішок важливіша
    (   Total >= 50
    ->  Score is (Black - White) * 10 + PosScore
    ;   Score = PosScore
    ).


% ==============================================================
% Алгоритм MinMax з відсіканням Альфа-Бета
%
% Оцінка ЗАВЖДИ з точки зору чорних (гравець 1):
%   MAX-гравець = чорні (1): шукає максимальну оцінку
%   MIN-гравець = білі  (2): шукає мінімальну оцінку
%
% Альфа-бета відсікання:
%   Alpha — найкраще (найбільше), що MAX вже гарантував вище по дереву
%   Beta  — найкраще (найменше), що MIN вже гарантував вище по дереву
%   Якщо Alpha >= Beta — поточна гілка не вплине на результат → відкидаємо
%
% Глибина вимірюється у пів-ходах (плаях):
%   Depth=2 → AI дивиться на 1 хід вперед (свій + відповідь суперника)
%   Depth=4 → 2 ходи вперед; Depth=6 → 3; Depth=8 → 4
% ==============================================================

% minimax(++Board, ++CurrentPlayer, ++Depth, ++Alpha, ++Beta,
%         --BestMove, --Score)
%
% ++Board         — поточна дошка
% ++CurrentPlayer — гравець, що зараз ходить (1 або 2)
% ++Depth         — глибина пошуку (у пів-ходах, що залишились)
% ++Alpha         — нижня межа для MAX (починається з -1000000)
% ++Beta          — верхня межа для MIN (починається з +1000000)
% --BestMove      — найкращий хід (Row-Col) або 'none' (пропуск/кінець)
% --Score         — оцінка з точки зору чорних
%
% Мультипризначення:
%   minimax(++,++,++,++,++,--,--) — пошук оптимального ходу AI.
%   Тільки один змістовний режим.
%
minimax(Board, CurrentPlayer, Depth, Alpha, Beta, BestMove, Score) :-
    valid_moves(Board, CurrentPlayer, Moves),
    (   Depth =:= 0
    ->  % Межа пошуку — повертаємо евристичну оцінку
        evaluate(Board, Score),
        BestMove = none
    ;   Moves = []
    ->  % Поточний гравець не може ходити — пробуємо суперника
        opponent(CurrentPlayer, Opponent),
        valid_moves(Board, Opponent, OppMoves),
        (   OppMoves = []
        ->  % Ніхто не може ходити — кінець гри
            terminal_score(Board, Score),
            BestMove = none
        ;   % Суперник ходить, поточний гравець пропускає
            minimax(Board, Opponent, Depth, Alpha, Beta, _, Score),
            BestMove = none
        )
    ;   CurrentPlayer =:= 1
    ->  % Хід чорних (MAX): шукаємо максимум
        max_search(Moves, Board, Depth, Alpha, Beta,
                   none, -1000000, BestMove, Score)
    ;   % Хід білих (MIN): шукаємо мінімум
        min_search(Moves, Board, Depth, Alpha, Beta,
                   none,  1000000, BestMove, Score)
    ).

% terminal_score(++Board, --Score)
% Оцінка кінцевої позиції: перемога / поразка / нічия.
%
terminal_score(Board, Score) :-
    count_pieces(Board, 1, Black),
    count_pieces(Board, 2, White),
    (   Black > White -> Score =  10000   % чорні перемогли
    ;   White > Black -> Score = -10000   % білі перемогли
    ;   Score = 0                         % нічия
    ).

% max_search(++Moves, ++Board, ++Depth, ++Alpha, ++Beta,
%            +CurBestMove, +CurBestScore, --BestMove, --BestScore)
%
% Перебирає ходи для MAX-гравця (чорні), оновлює Alpha.
% Альфа-відсікання: якщо NewAlpha >= Beta — зупиняємось.
%
% +CurBestMove  — найкращий хід, знайдений досі
% +CurBestScore — оцінка найкращого ходу, знайденого досі
%
max_search([],              _Board, _Depth, _Alpha, _Beta,
           BestMove, BestScore, BestMove, BestScore).

max_search([Row-Col | RestMoves], Board, Depth, Alpha, Beta,
           CurBestMove, CurBestScore, BestMove, BestScore) :-
    opponent(1, Opponent),                      % Після ходу чорних — хід білих
    make_move(Board, Row, Col, 1, NewBoard),
    NewDepth is Depth - 1,
    minimax(NewBoard, Opponent, NewDepth, Alpha, Beta, _, ChildScore),
    % Чи покращив цей хід поточний максимум?
    (   ChildScore > CurBestScore
    ->  NewBestMove  = Row-Col,
        NewBestScore = ChildScore,
        NewAlpha     is max(Alpha, ChildScore)
    ;   NewBestMove  = CurBestMove,
        NewBestScore = CurBestScore,
        NewAlpha     = Alpha
    ),
    % Альфа-відсікання: MIN-гравець нагорі вже має кращий варіант
    (   NewAlpha >= Beta
    ->  BestMove  = NewBestMove,
        BestScore = NewBestScore
    ;   max_search(RestMoves, Board, Depth, NewAlpha, Beta,
                   NewBestMove, NewBestScore, BestMove, BestScore)
    ).

% min_search(++Moves, ++Board, ++Depth, ++Alpha, ++Beta,
%            +CurBestMove, +CurBestScore, --BestMove, --BestScore)
%
% Перебирає ходи для MIN-гравця (білі), оновлює Beta.
% Бета-відсікання: якщо Alpha >= NewBeta — зупиняємось.
%
min_search([],              _Board, _Depth, _Alpha, _Beta,
           BestMove, BestScore, BestMove, BestScore).

min_search([Row-Col | RestMoves], Board, Depth, Alpha, Beta,
           CurBestMove, CurBestScore, BestMove, BestScore) :-
    opponent(2, Opponent),                      % Після ходу білих — хід чорних
    make_move(Board, Row, Col, 2, NewBoard),
    NewDepth is Depth - 1,
    minimax(NewBoard, Opponent, NewDepth, Alpha, Beta, _, ChildScore),
    % Чи покращив цей хід поточний мінімум?
    (   ChildScore < CurBestScore
    ->  NewBestMove  = Row-Col,
        NewBestScore = ChildScore,
        NewBeta      is min(Beta, ChildScore)
    ;   NewBestMove  = CurBestMove,
        NewBestScore = CurBestScore,
        NewBeta      = Beta
    ),
    % Бета-відсікання: MAX-гравець нагорі вже має кращий варіант
    (   Alpha >= NewBeta
    ->  BestMove  = NewBestMove,
        BestScore = NewBestScore
    ;   min_search(RestMoves, Board, Depth, Alpha, NewBeta,
                   NewBestMove, NewBestScore, BestMove, BestScore)
    ).


% ==============================================================
% HTTP-обробники API
%
% Обмін даними: JSON через тіло запиту/відповіді.
% Дошка передається як JSON-масив із 64 чисел.
% ==============================================================

% move_to_obj(++Move, --JsonObj)
% Перетворює Prolog-пару Row-Col на JSON-об'єкт {row:R, col:C}.
%
move_to_obj(Row-Col, json{row: Row, col: Col}).

% next_state(++Board, ++JustMoved, --Next, --GameOver, --Winner, --ValidMoves)
% Визначає наступний стан гри після ходу JustMoved:
%   - якщо суперник може ходити → суперник ходить далі
%   - якщо суперник не може → JustMoved ходить знову (пропуск)
%   - якщо ніхто не може → кінець гри
%
% Мультипризначення:
%   next_state(++Board,++JustMoved,--Next,--Over,--Winner,--Moves) — основне.
%
next_state(Board, JustMoved, Next, GameOver, Winner, ValidMoves) :-
    opponent(JustMoved, Opponent),
    valid_moves(Board, Opponent, OppMoves),
    (   OppMoves \= []
    ->  Next = Opponent, GameOver = 0, Winner = -1, ValidMoves = OppMoves
    ;   valid_moves(Board, JustMoved, MyMoves),
        (   MyMoves \= []
        ->  Next = JustMoved, GameOver = 0, Winner = -1, ValidMoves = MyMoves
        ;   game_over(Board, W),
            Next = 0, GameOver = 1, Winner = W, ValidMoves = []
        )
    ).

% GET /api/new_game
% Повертає початковий стан дошки та допустимі ходи для чорних.
%
handle_new_game(_Request) :-
    initial_board(Board),
    valid_moves(Board, 1, Moves),
    maplist(move_to_obj, Moves, MoveObjs),
    count_pieces(Board, 1, Black),
    count_pieces(Board, 2, White),
    reply_json_dict(json{
        board:          Board,
        current_player: 1,
        black_count:    Black,
        white_count:    White,
        valid_moves:    MoveObjs,
        game_over:      0,
        winner:         -1
    }).

% POST /api/make_move  { board, player, row, col }
% Виконує хід людини, повертає новий стан гри.
%
handle_make_move(Request) :-
    http_read_json_dict(Request, Data),
    Board  = Data.board,
    Player = Data.player,
    Row    = Data.row,
    Col    = Data.col,
    (   valid_move(Board, Row, Col, Player)
    ->  make_move(Board, Row, Col, Player, NewBoard),
        next_state(NewBoard, Player, Next, Over, Winner, VMoves),
        maplist(move_to_obj, VMoves, MoveObjs),
        count_pieces(NewBoard, 1, Black),
        count_pieces(NewBoard, 2, White),
        reply_json_dict(json{
            board:          NewBoard,
            next_player:    Next,
            game_over:      Over,
            winner:         Winner,
            black_count:    Black,
            white_count:    White,
            valid_moves:    MoveObjs,
            last_move:      json{row: Row, col: Col}
        })
    ;   reply_json_dict(json{error: 1, message: "Недопустимий хід"})
    ).

% POST /api/ai_move  { board, player, depth }
% Обчислює та виконує хід AI за допомогою MinMax + Альфа-Бета.
% player: гравець, за якого грає AI (1=чорні, 2=білі)
% depth:  глибина пошуку у пів-ходах (2/4/6/8)
%
handle_ai_move(Request) :-
    http_read_json_dict(Request, Data),
    Board  = Data.board,
    Player = Data.player,
    Depth  = Data.depth,
    valid_moves(Board, Player, Moves),
    (   Moves = []
    ->  % AI не може ходити — пропуск
        count_pieces(Board, 1, Black),
        count_pieces(Board, 2, White),
        reply_json_dict(json{
            move:        json{row: -1, col: -1},
            board:       Board,
            next_player: Player,
            game_over:   0,
            winner:      -1,
            black_count: Black,
            white_count: White,
            valid_moves: [],
            passed:      1
        })
    ;   % Запускаємо MinMax
        minimax(Board, Player, Depth, -1000000, 1000000, BestMove, _Score),
        BestMove = BestRow-BestCol,
        make_move(Board, BestRow, BestCol, Player, NewBoard),
        next_state(NewBoard, Player, Next, Over, Winner, VMoves),
        maplist(move_to_obj, VMoves, MoveObjs),
        count_pieces(NewBoard, 1, Black),
        count_pieces(NewBoard, 2, White),
        reply_json_dict(json{
            move:        json{row: BestRow, col: BestCol},
            board:       NewBoard,
            next_player: Next,
            game_over:   Over,
            winner:      Winner,
            black_count: Black,
            white_count: White,
            valid_moves: MoveObjs,
            passed:      0
        })
    ).
