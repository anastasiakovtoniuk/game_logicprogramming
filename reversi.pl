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
:- use_module(library(apply)).                % maplist/3
:- use_module(library(aggregate)).            % aggregate_all/3


% ==============================================================
% HTTP-маршрути та запуск сервера
% ==============================================================

:- http_handler(root(api/new_game),    handle_new_game,    []).
:- http_handler(root(api/make_move),   handle_make_move,   []).
:- http_handler(root(api/ai_move),     handle_ai_move,     []).
:- http_handler(root(.),               serve_static,       [prefix, priority(-100)]).

serve_static(Request) :-
    http_reply_from_files(public, [indexes(['index.html'])], Request).

start_server(Port) :-
    http_server(http_dispatch, [port(Port)]),
    format("~n=== Reversi server started ===~n"),
    format("Open in browser: http://localhost:~w/~n~n", [Port]),
    (   current_prolog_flag(interactive, true)
    ->  true
    ;   thread_get_message(stop)
    ).

:- initialization(start_server(8080), main).


% ==============================================================
% Розмір дошки
%
% Дошка = плаский список із Size*Size цілих чисел:
%   0 = порожня, 1 = чорна, 2 = біла
% Розмір зберігається як глобальний динамічний факт.
% Допустимі розміри: 6, 8, 10.
% ==============================================================

:- dynamic board_size/1.
board_size(8).  % розмір за замовчуванням

% set_size(++Size)
% Встановлює поточний розмір дошки.
%
set_size(Size) :-
    retractall(board_size(_)),
    assertz(board_size(Size)).

% setup_size_from_board(++Board)
% Обчислює розмір дошки з довжини списку (Size = sqrt(Length)).
% Використовується в обробниках make_move та ai_move,
% щоб не передавати розмір явно в кожному запиті.
%
setup_size_from_board(Board) :-
    length(Board, Total),
    Size is round(sqrt(float(Total))),
    set_size(Size).


% ==============================================================
% Операції над дошкою
% ==============================================================

% in_bounds(++Row, ++Col)
% Перевіряє, що (Row, Col) знаходиться в межах поточної дошки.
%
% Мультипризначення:
%   in_bounds(++Row, ++Col) — перевірка; детермінований.
%
in_bounds(Row, Col) :-
    board_size(S),
    Row >= 0, Row < S,
    Col >= 0, Col < S.

% cell_index(++Row, ++Col, --Index)
% Лінійний індекс клітинки (рядковий порядок).
%
% Мультипризначення:
%   cell_index(++Row, ++Col, --Index) — обчислення індексу.
%
cell_index(Row, Col, Index) :-
    board_size(S),
    in_bounds(Row, Col),
    Index is Row * S + Col.

% get_cell(++Board, ++Row, ++Col, --Value)
% Значення клітинки дошки за координатами.
%
% Мультипризначення:
%   get_cell(++Board, ++Row, ++Col, --Value) — читання.
%   get_cell(++Board, ++Row, ++Col,  +Value) — перевірка.
%
get_cell(Board, Row, Col, Value) :-
    cell_index(Row, Col, Index),
    nth0(Index, Board, Value).

% set_cell(++Board, ++Row, ++Col, ++Value, --NewBoard)
% Нова дошка із заміненою клітинкою.
%
% Мультипризначення:
%   set_cell(++Board, ++Row, ++Col, ++Value, --NewBoard) — запис.
%
set_cell(Board, Row, Col, Value, NewBoard) :-
    cell_index(Row, Col, Index),
    replace_nth0(Index, Board, Value, NewBoard).

% replace_nth0(++N, ++List, ++Value, --NewList)
% Замінює N-й елемент списку.
%
replace_nth0(0, [_|T], V, [V|T]) :- !.
replace_nth0(N, [H|T], V, [H|R]) :-
    N > 0, N1 is N - 1,
    replace_nth0(N1, T, V, R).

% initial_board(--Board)
% Початкова розстановка Реверсі: 4 фішки в центрі.
% Центр визначається динамічно за поточним розміром дошки.
%
% Мультипризначення:
%   initial_board(--Board) — генерація початкової дошки.
%
initial_board(Board) :-
    board_size(S),
    Total is S * S,
    length(B0, Total),
    maplist(=(0), B0),
    Half is S // 2,
    R1 is Half - 1, C1 is Half - 1,   % центр: ліво-верх
    R2 is Half - 1, C2 is Half,        %        право-верх
    R3 is Half,     C3 is Half - 1,    %        ліво-низ
    R4 is Half,     C4 is Half,        %        право-низ
    set_cell(B0, R1, C1, 2, B1),       % біла
    set_cell(B1, R2, C2, 1, B2),       % чорна
    set_cell(B2, R3, C3, 1, B3),       % чорна
    set_cell(B3, R4, C4, 2, Board).    % біла

% count_pieces(++Board, ++Player, --Count)
% Кількість фішок гравця на дошці.
%
count_pieces(Board, Player, Count) :-
    aggregate_all(count, member(Player, Board), Count).


% ==============================================================
% Логіка гри
% ==============================================================

% opponent(++Player, --Opponent)
% Суперник гравця.
%
% Мультипризначення:
%   opponent(++Player, --Opponent) — отримати суперника.
%   opponent( -Player, ++Opponent) — інверсія.
%
opponent(1, 2).
opponent(2, 1).

% 8 напрямків: (зміна рядка, зміна стовпця)
direction(-1, -1). direction(-1, 0). direction(-1, 1).
direction( 0, -1).                   direction( 0, 1).
direction( 1, -1). direction( 1, 0). direction( 1, 1).

% scan_line(++Board, ++Row, ++Col, ++DR, ++DC,
%           ++Player, ++Opponent, ++Acc, --Flips)
% Іде в напрямку (DR,DC), збираючи фішки суперника.
% Повертає Acc, якщо знайдено свою фішку; [] інакше.
%
% Мультипризначення:
%   scan_line(++,++,++,++,++,++,++,+Acc,--Flips) — сканування рядка.
%
scan_line(Board, Row, Col, DR, DC, Player, Opp, Acc, Flips) :-
    NR is Row + DR, NC is Col + DC,
    (   \+ in_bounds(NR, NC)
    ->  Flips = []
    ;   get_cell(Board, NR, NC, Cell),
        (   Cell =:= Player -> Flips = Acc               % лінія замкнена
        ;   Cell =:= Opp    -> scan_line(Board, NR, NC, DR, DC, Player, Opp,
                                         [NR-NC | Acc], Flips)
        ;   Flips = []                                    % порожня клітинка
        )
    ).

% flips_in_direction(++Board, ++Row, ++Col, ++DR, ++DC, ++Player, --Flips)
% Фішки для перевертання в одному напрямку.
%
% Мультипризначення:
%   flips_in_direction(++,++,++,++,++,++,--) — отримати список захоплень.
%
flips_in_direction(Board, Row, Col, DR, DC, Player, Flips) :-
    opponent(Player, Opp),
    NR is Row + DR, NC is Col + DC,
    (   in_bounds(NR, NC), get_cell(Board, NR, NC, Opp)
    ->  scan_line(Board, NR, NC, DR, DC, Player, Opp, [NR-NC], Flips)
    ;   Flips = []
    ).

% all_flips(++Board, ++Row, ++Col, ++Player, --AllFlips)
% Усі захоплені фішки по всіх 8 напрямках.
%
% Мультипризначення:
%   all_flips(++Board,++Row,++Col,++Player,--AllFlips) — повний список захоплень.
%
all_flips(Board, Row, Col, Player, AllFlips) :-
    findall(F,
        (   direction(DR, DC),
            flips_in_direction(Board, Row, Col, DR, DC, Player, F),
            F \= []
        ),
        Groups),
    append(Groups, AllFlips).

% valid_move(++Board, ++Row, ++Col, ++Player)
% Хід (Row,Col) допустимий: порожня клітинка і є захоплення.
%
% Мультипризначення:
%   valid_move(++Board, ++Row, ++Col, ++Player) — перевірка ходу.
%
valid_move(Board, Row, Col, Player) :-
    get_cell(Board, Row, Col, 0),
    all_flips(Board, Row, Col, Player, Flips),
    Flips \= [].

% valid_moves(++Board, ++Player, --Moves)
% Список усіх допустимих ходів у вигляді Row-Col.
%
% Мультипризначення:
%   valid_moves(++Board, ++Player, --Moves) — генерація ходів.
%   valid_moves(++Board, ++Player,  +Moves) — перевірка.
%
valid_moves(Board, Player, Moves) :-
    board_size(S), Max is S - 1,
    findall(Row-Col,
        (   between(0, Max, Row),
            between(0, Max, Col),
            valid_move(Board, Row, Col, Player)
        ),
        Moves).

% flip_cells(++Board, ++Flips, ++Player, --NewBoard)
% Перевертає всі фішки зі списку Flips.
%
flip_cells(Board, [],          _,      Board).
flip_cells(Board, [R-C | Rest], Player, NewBoard) :-
    set_cell(Board, R, C, Player, Temp),
    flip_cells(Temp, Rest, Player, NewBoard).

% make_move(++Board, ++Row, ++Col, ++Player, --NewBoard)
% Виконує хід: ставить фішку і перевертає захоплені.
%
% Мультипризначення:
%   make_move(++Board,++Row,++Col,++Player,--NewBoard) — виконання ходу.
%
make_move(Board, Row, Col, Player, NewBoard) :-
    all_flips(Board, Row, Col, Player, Flips),
    set_cell(Board, Row, Col, Player, B1),
    flip_cells(B1, Flips, Player, NewBoard).

% game_over(++Board, --Winner)
% Кінець гри: жоден гравець не може ходити.
% Winner = 1, 2, або 0 (нічия).
%
% Мультипризначення:
%   game_over(++Board, --Winner) — перевірка кінця гри.
%
game_over(Board, Winner) :-
    valid_moves(Board, 1, []),
    valid_moves(Board, 2, []),
    count_pieces(Board, 1, B),
    count_pieces(Board, 2, W),
    (   B > W -> Winner = 1
    ;   W > B -> Winner = 2
    ;   Winner = 0
    ).


% ==============================================================
% Функція оцінки позиції
%
% Оцінка з точки зору чорних (гравець 1):
%   позитивна = перевага чорних, негативна = перевага білих
%
% Вагові коефіцієнти генеруються динамічно за розміром дошки:
%   кути      (+100) — найцінніші позиції
%   біля куту (-20 / -50) — небезпечні
%   краї      (+10) — стабільні
%   центр     (-1)  — нейтральні
% ==============================================================

% cell_weight_rc(++Row, ++Col, ++Max, --Weight)
% Ваговий коефіцієнт клітинки (Max = Size - 1).
%
cell_weight_rc(R, C, Max, W) :-
    (   is_corner(R, C, Max)         -> W = 100
    ;   is_edge_corner_adj(R, C, Max)-> W = -20
    ;   is_diag_corner_adj(R, C, Max)-> W = -50
    ;   is_edge(R, C, Max)           -> W = 10
    ;   W = -1
    ).

is_corner(R, C, Max) :-
    (R =:= 0 ; R =:= Max), (C =:= 0 ; C =:= Max).

% Клітинки на краю, суміжні з кутом
is_edge_corner_adj(R, C, Max) :-
    (   R =:= 0,   (C =:= 1 ; C =:= Max-1)
    ;   R =:= Max, (C =:= 1 ; C =:= Max-1)
    ;   C =:= 0,   (R =:= 1 ; R =:= Max-1)
    ;   C =:= Max, (R =:= 1 ; R =:= Max-1)
    ).

% Клітинки по діагоналі від кута (найгірші позиції)
is_diag_corner_adj(R, C, Max) :-
    (R =:= 1 ; R =:= Max-1), (C =:= 1 ; C =:= Max-1).

is_edge(R, C, Max) :-
    R =:= 0 ; R =:= Max ; C =:= 0 ; C =:= Max.

% evaluate_flat(++Board, ++Idx, ++Size, +Acc, --Score)
% Рекурсивно обчислює зважену суму по всій дошці.
% Idx — поточний лінійний індекс клітинки.
%
evaluate_flat([], _, _, Acc, Acc).
evaluate_flat([Cell | Rest], Idx, Size, Acc, Score) :-
    Row is Idx // Size,
    Col is Idx mod Size,
    Max is Size - 1,
    cell_weight_rc(Row, Col, Max, W),
    (   Cell =:= 1 -> A1 is Acc + W
    ;   Cell =:= 2 -> A1 is Acc - W
    ;   A1 = Acc
    ),
    Idx1 is Idx + 1,
    evaluate_flat(Rest, Idx1, Size, A1, Score).

% evaluate(++Board, --Score)
% Евристична оцінка позиції.
% Рання гра: позиційна оцінка; ендшпіль (>75% заповнено): кількість фішок.
%
% Мультипризначення:
%   evaluate(++Board, --Score) — обчислення оцінки; один режим.
%
evaluate(Board, Score) :-
    board_size(Size),
    evaluate_flat(Board, 0, Size, 0, PosScore),
    count_pieces(Board, 1, Black),
    count_pieces(Board, 2, White),
    Total is Black + White,
    Threshold is (Size * Size * 3) // 4,
    (   Total >= Threshold
    ->  Score is (Black - White) * 10 + PosScore
    ;   Score = PosScore
    ).


% ==============================================================
% Алгоритм MinMax з відсіканням Альфа-Бета
%
% Оцінка ЗАВЖДИ з точки зору чорних (гравець 1):
%   MAX-гравець = чорні (1): максимізує оцінку
%   MIN-гравець = білі  (2): мінімізує оцінку
%
% Глибина у пів-ходах (плаях):
%   2 пів-ходи = Easy:   AI дивиться на 1 хід вперед
%   4 пів-ходи = Medium: 2 ходи вперед
%   6 пів-ходів = Hard:  3 ходи вперед
%   8 пів-ходів = Expert: 4 ходи вперед
% ==============================================================

% minimax(++Board, ++CurrentPlayer, ++Depth, ++Alpha, ++Beta,
%         --BestMove, --Score)
%
% ++Board         — поточна дошка
% ++CurrentPlayer — хто зараз ходить (1 або 2)
% ++Depth         — глибина пошуку в пів-ходах
% ++Alpha         — нижня межа MAX (-1000000 на початку)
% ++Beta          — верхня межа MIN (+1000000 на початку)
% --BestMove      — найкращий хід Row-Col або 'none'
% --Score         — оцінка з точки зору чорних
%
% Мультипризначення:
%   minimax(++,++,++,++,++,--,--) — пошук ходу AI; один режим.
%
minimax(Board, Player, Depth, Alpha, Beta, BestMove, Score) :-
    valid_moves(Board, Player, Moves),
    (   Depth =:= 0
    ->  evaluate(Board, Score), BestMove = none
    ;   Moves = []
    ->  % Поточний гравець пропускає — пробуємо суперника
        opponent(Player, Opp),
        valid_moves(Board, Opp, OppMoves),
        (   OppMoves = []
        ->  terminal_score(Board, Score), BestMove = none
        ;   minimax(Board, Opp, Depth, Alpha, Beta, _, Score), BestMove = none
        )
    ;   Player =:= 1
    ->  max_search(Moves, Board, Depth, Alpha, Beta, none, -1000000, BestMove, Score)
    ;   min_search(Moves, Board, Depth, Alpha, Beta, none,  1000000, BestMove, Score)
    ).

% terminal_score(++Board, --Score)
% Оцінка кінцевої позиції: перемога / поразка / нічия.
%
terminal_score(Board, Score) :-
    count_pieces(Board, 1, B),
    count_pieces(Board, 2, W),
    (   B > W -> Score =  10000
    ;   W > B -> Score = -10000
    ;   Score = 0
    ).

% max_search(++Moves, ++Board, ++Depth, ++Alpha, ++Beta,
%            +CurMove, +CurScore, --BestMove, --BestScore)
% MAX-вузол: перебирає ходи чорних, шукає максимум, оновлює Alpha.
% Альфа-відсікання: зупиняємось якщо NewAlpha >= Beta.
%
max_search([], _, _, _, _, Best, BestScore, Best, BestScore).
max_search([R-C | Rest], Board, Depth, Alpha, Beta,
           CurBest, CurScore, BestMove, BestScore) :-
    make_move(Board, R, C, 1, NewBoard),
    D1 is Depth - 1,
    minimax(NewBoard, 2, D1, Alpha, Beta, _, ChildScore),
    (   ChildScore > CurScore
    ->  NB = R-C, NS = ChildScore, NA is max(Alpha, ChildScore)
    ;   NB = CurBest, NS = CurScore, NA = Alpha
    ),
    (   NA >= Beta
    ->  BestMove = NB, BestScore = NS
    ;   max_search(Rest, Board, Depth, NA, Beta, NB, NS, BestMove, BestScore)
    ).

% min_search(++Moves, ++Board, ++Depth, ++Alpha, ++Beta,
%            +CurMove, +CurScore, --BestMove, --BestScore)
% MIN-вузол: перебирає ходи білих, шукає мінімум, оновлює Beta.
% Бета-відсікання: зупиняємось якщо Alpha >= NewBeta.
%
min_search([], _, _, _, _, Best, BestScore, Best, BestScore).
min_search([R-C | Rest], Board, Depth, Alpha, Beta,
           CurBest, CurScore, BestMove, BestScore) :-
    make_move(Board, R, C, 2, NewBoard),
    D1 is Depth - 1,
    minimax(NewBoard, 1, D1, Alpha, Beta, _, ChildScore),
    (   ChildScore < CurScore
    ->  NB = R-C, NS = ChildScore, NB2 is min(Beta, ChildScore)
    ;   NB = CurBest, NS = CurScore, NB2 = Beta
    ),
    (   Alpha >= NB2
    ->  BestMove = NB, BestScore = NS
    ;   min_search(Rest, Board, Depth, Alpha, NB2, NB, NS, BestMove, BestScore)
    ).


% ==============================================================
% HTTP-обробники API
% ==============================================================

move_to_obj(Row-Col, json{row: Row, col: Col}).

% next_state(++Board, ++JustMoved, --Next, --Over, --Winner, --VMoves)
% Визначає наступний стан після ходу JustMoved.
%
next_state(Board, JustMoved, Next, Over, Winner, VMoves) :-
    opponent(JustMoved, Opp),
    valid_moves(Board, Opp, OppMoves),
    (   OppMoves \= []
    ->  Next = Opp, Over = 0, Winner = -1, VMoves = OppMoves
    ;   valid_moves(Board, JustMoved, MyMoves),
        (   MyMoves \= []
        ->  Next = JustMoved, Over = 0, Winner = -1, VMoves = MyMoves
        ;   game_over(Board, W),
            Next = 0, Over = 1, Winner = W, VMoves = []
        )
    ).

% POST /api/new_game  { size }
% Ініціалізує нову гру з заданим розміром дошки.
%
handle_new_game(Request) :-
    http_read_json_dict(Request, Data),
    Size = Data.size,
    set_size(Size),
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
% Виконує хід людини, повертає новий стан.
%
handle_make_move(Request) :-
    http_read_json_dict(Request, Data),
    Board  = Data.board,
    Player = Data.player,
    Row    = Data.row,
    Col    = Data.col,
    setup_size_from_board(Board),
    (   valid_move(Board, Row, Col, Player)
    ->  make_move(Board, Row, Col, Player, NewBoard),
        next_state(NewBoard, Player, Next, Over, Winner, VMoves),
        maplist(move_to_obj, VMoves, MoveObjs),
        count_pieces(NewBoard, 1, Black),
        count_pieces(NewBoard, 2, White),
        reply_json_dict(json{
            board:       NewBoard,
            next_player: Next,
            game_over:   Over,
            winner:      Winner,
            black_count: Black,
            white_count: White,
            valid_moves: MoveObjs,
            last_move:   json{row: Row, col: Col}
        })
    ;   reply_json_dict(json{error: 1, message: "Invalid move"})
    ).

% POST /api/ai_move  { board, player, depth }
% Обчислює хід AI за допомогою MinMax + Альфа-Бета.
% depth: глибина пошуку в пів-ходах (2/4/6/8).
%
handle_ai_move(Request) :-
    http_read_json_dict(Request, Data),
    Board  = Data.board,
    Player = Data.player,
    Depth  = Data.depth,
    setup_size_from_board(Board),
    valid_moves(Board, Player, Moves),
    (   Moves = []
    ->  % AI has no valid moves — pass
        opponent(Player, Opp),
        valid_moves(Board, Opp, OppMoves),
        count_pieces(Board, 1, Black),
        count_pieces(Board, 2, White),
        (   OppMoves = []
        ->  % Both players have no moves — game over
            game_over(Board, WinnerVal),
            reply_json_dict(json{
                move:        json{row: -1, col: -1},
                board:       Board,
                next_player: 0,
                game_over:   1,
                winner:      WinnerVal,
                black_count: Black,
                white_count: White,
                valid_moves: [],
                passed:      1
            })
        ;   maplist(move_to_obj, OppMoves, OppMoveObjs),
            reply_json_dict(json{
                move:        json{row: -1, col: -1},
                board:       Board,
                next_player: Opp,
                game_over:   0,
                winner:      -1,
                black_count: Black,
                white_count: White,
                valid_moves: OppMoveObjs,
                passed:      1
            })
        )
    ;   minimax(Board, Player, Depth, -1000000, 1000000, BestMove, _Score),
        BestMove = BR-BC,
        make_move(Board, BR, BC, Player, NewBoard),
        next_state(NewBoard, Player, Next, Over, Winner, VMoves),
        maplist(move_to_obj, VMoves, MoveObjs),
        count_pieces(NewBoard, 1, Black),
        count_pieces(NewBoard, 2, White),
        reply_json_dict(json{
            move:        json{row: BR, col: BC},
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
