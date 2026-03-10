% ==============================================================
% Reversi (Отелло) — реалізація на SWI-Prolog
% Алгоритм: MinMax з відсіканням Альфа-Бета
% HTTP-сервер: порт 8080
% Веб-інтерфейс: http://localhost:8080/
%
% Дошка = плаский список із Size*Size цілих чисел:
%   0 = порожня клітинка, 1 = чорна фішка, 2 = біла фішка
% ==============================================================

:- module(reversi, []).

:- use_module(library(http/thread_httpd)).   % HTTP-сервер у потоці
:- use_module(library(http/http_dispatch)).  % диспетчеризація запитів за URL
:- use_module(library(http/http_json)).      % читання JSON з тіла запиту / відправка JSON
:- use_module(library(http/http_files)).     % роздача статичних файлів (HTML/CSS/JS)
:- use_module(library(lists)).
:- use_module(library(apply)).               % maplist/2,3
:- use_module(library(aggregate)).           % aggregate_all/3


% ==============================================================
% HTTP-маршрути та запуск сервера
% ==============================================================

:- http_handler(root(api/new_game),  handle_new_game,  []).
:- http_handler(root(api/make_move), handle_make_move, []).
:- http_handler(root(api/ai_move),   handle_ai_move,   []).
:- http_handler(root(.),             serve_static,     [prefix, priority(-100)]).

% serve_static(++Request)
% Роздає файли з папки public/ як статичний веб-контент.
serve_static(Request) :-
    http_reply_from_files(public, [indexes(['index.html'])], Request).

% start_server(++Port)
% Запускає HTTP-сервер на заданому порту.
% У неінтерактивному режимі блокує головний потік.
start_server(Port) :-
    http_server(http_dispatch, [port(Port)]),
    format("~n=== Reversi server started ===~n"),
    format("Open in browser: http://localhost:~w/~n~n", [Port]),
    (   current_prolog_flag(interactive, true) % перевіряє режим запуску
    ->  true
    ;   thread_get_message(stop)               % блокує потік до повідомлення stop
    ).

:- initialization(start_server(8080), main).


% ==============================================================
% Розмір дошки (динамічний факт)
% Допустимі розміри: 6, 8, 10.
% ==============================================================

:- dynamic board_size/1.
board_size(8).   % розмір за замовчуванням

% set_size(++Size)
% Встановлює поточний розмір дошки, замінюючи попереднє значення.
set_size(Size) :-
    retractall(board_size(_)),   % видаляє всі поточні факти board_size
    assertz(board_size(Size)).   % додає новий факт в кінець бази

% Мультипризначеність:
% set_size(++Size) – єдиний режим: встановлення розміру дошки.

% setup_size_from_board(++Board)
% Виводить розмір дошки з довжини списку: Size = round(sqrt(|Board|)).
% Викликається на початку handle_make_move та handle_ai_move,
% щоб не передавати розмір явно в кожному запиті.
setup_size_from_board(Board) :-
    length(Board, Total),                    % Total = кількість клітинок
    Size is round(sqrt(float(Total))),       % float/sqrt/round: обчислює сторону квадрата
    set_size(Size).

% Мультипризначеність:
% setup_size_from_board(++Board) – єдиний режим: встановлення розміру з довжини дошки.


% ==============================================================
% Операції над дошкою
% ==============================================================

% in_bounds(++Row, ++Col)
% Перевіряє, що координати (Row, Col) є в межах поточної дошки.
in_bounds(Row, Col) :-
    board_size(S),
    Row >= 0, Row < S,
    Col >= 0, Col < S.

% Мультипризначеність:
% in_bounds(++Row, ++Col) – єдиний режим: перевірка допустимості координат.

% cell_index(++Row, ++Col, --Index)
% Лінійний індекс клітинки у пласкому списку (рядковий порядок).
cell_index(Row, Col, Index) :-
    board_size(S),
    in_bounds(Row, Col),
    Index is Row * S + Col.

% Мультипризначеність:
% cell_index(++Row, ++Col, --Index) – єдиний режим: обчислення індексу.

% get_cell(++Board, ++Row, ++Col, ?Value)
% Значення клітинки дошки за координатами (Row, Col).
get_cell(Board, Row, Col, Value) :-
    cell_index(Row, Col, Index),
    nth0(Index, Board, Value).   % nth0: доступ до елементу списку за індексом з 0

% Мультипризначеність:
% get_cell(++Board, ++Row, ++Col, --Value) – читання значення клітинки.
% get_cell(++Board, ++Row, ++Col,  +Value) – перевірка значення клітинки.

% set_cell(++Board, ++Row, ++Col, ++Value, --NewBoard)
% Повертає нову дошку із заміненою клітинкою (Row, Col) ← Value.
set_cell(Board, Row, Col, Value, NewBoard) :-
    cell_index(Row, Col, Index),
    replace_nth0(Index, Board, Value, NewBoard).

% Мультипризначеність:
% set_cell(++Board, ++Row, ++Col, ++Value, --NewBoard) – єдиний режим: запис у клітинку.

% replace_nth0(++N, ++List, ++Value, --NewList)
% Замінює N-й елемент списку (нумерація з 0).
replace_nth0(0, [_|T], V, [V|T]) :- !.
replace_nth0(N, [H|T], V, [H|R]) :-
    N > 0, N1 is N - 1,
    replace_nth0(N1, T, V, R).

% Мультипризначеність:
% replace_nth0(++N, ++List, ++Value, --NewList) – єдиний режим: заміна N-го елементу.

% initial_board(--Board)
% Генерує початкову дошку Реверсі: 4 фішки в центрі.
% Центр визначається динамічно залежно від розміру дошки.
initial_board(Board) :-
    board_size(S),
    Total is S * S,
    length(B0, Total),            % створює список довжини Total
    maplist(=(0), B0),            % заповнює всі елементи нулями
    Half is S // 2,
    R1 is Half - 1, C1 is Half - 1,   % центр: ліво-верх  → біла
    R2 is Half - 1, C2 is Half,        %        право-верх → чорна
    R3 is Half,     C3 is Half - 1,    %        ліво-низ   → чорна
    R4 is Half,     C4 is Half,        %        право-низ  → біла
    set_cell(B0, R1, C1, 2, B1),
    set_cell(B1, R2, C2, 1, B2),
    set_cell(B2, R3, C3, 1, B3),
    set_cell(B3, R4, C4, 2, Board).

% Мультипризначеність:
% initial_board(--Board) – єдиний режим: генерація початкової дошки.

% count_pieces(++Board, ++Player, --Count)
% Підраховує кількість фішок гравця Player на дошці.
count_pieces(Board, Player, Count) :-
    aggregate_all(count, member(Player, Board), Count).
    % aggregate_all: підраховує кількість рішень для member(Player, Board)

% Мультипризначеність:
% count_pieces(++Board, ++Player, --Count) – єдиний режим: підрахунок фішок.


% ==============================================================
% Логіка гри: ходи та захоплення фішок
% ==============================================================

% opponent(++Player, --Opponent)
% Повертає суперника гравця: 1↔2.
opponent(1, 2).
opponent(2, 1).

% Мультипризначеність:
% opponent(++Player, --Opponent) – отримати суперника за номером гравця.
% opponent( -Player, ++Opponent) – інверсія: знайти гравця за суперником.

% 8 напрямків обходу дошки: (зміна рядка DR, зміна стовпця DC)
direction(-1, -1). direction(-1, 0). direction(-1, 1).
direction( 0, -1).                   direction( 0, 1).
direction( 1, -1). direction( 1, 0). direction( 1, 1).

% scan_line(++Board, ++Row, ++Col, ++DR, ++DC,
%           ++Player, ++Opp, ++Acc, --Flips)
% Йде в напрямку (DR, DC) від (Row, Col), накопичуючи в Acc фішки суперника.
% Повертає Acc, якщо лінія замкнена своєю фішкою; [] — якщо ні.
scan_line(Board, Row, Col, DR, DC, Player, Opp, Acc, Flips) :-
    NR is Row + DR, NC is Col + DC,
    (   \+ in_bounds(NR, NC)
    ->  Flips = []                           % вийшли за межі — лінія незамкнена
    ;   get_cell(Board, NR, NC, Cell),
        (   Cell =:= Player -> Flips = Acc   % своя фішка — лінія замкнена
        ;   Cell =:= Opp    -> scan_line(Board, NR, NC, DR, DC, Player, Opp,
                                         [NR-NC | Acc], Flips)
        ;   Flips = []                       % порожня клітинка — лінія незамкнена
        )
    ).

% Мультипризначеність:
% scan_line(++,++,++,++,++,++,++,++,--) – єдиний режим: сканування лінії захоплення.

% flips_in_direction(++Board, ++Row, ++Col, ++DR, ++DC, ++Player, --Flips)
% Список координат фішок для перевертання в одному напрямку (DR, DC).
flips_in_direction(Board, Row, Col, DR, DC, Player, Flips) :-
    opponent(Player, Opp),
    NR is Row + DR, NC is Col + DC,
    (   in_bounds(NR, NC), get_cell(Board, NR, NC, Opp)
    ->  scan_line(Board, NR, NC, DR, DC, Player, Opp, [NR-NC], Flips)
    ;   Flips = []   % сусідня клітинка не є фішкою суперника
    ).

% Мультипризначеність:
% flips_in_direction(++,++,++,++,++,++,--) – єдиний режим: захоплення в напрямку.

% all_flips(++Board, ++Row, ++Col, ++Player, --AllFlips)
% Об'єднує всі захоплені фішки по всіх 8 напрямках.
all_flips(Board, Row, Col, Player, AllFlips) :-
    findall(F,                               % збирає всі непусті списки захоплень
        (   direction(DR, DC),
            flips_in_direction(Board, Row, Col, DR, DC, Player, F),
            F \= []
        ),
        Groups),
    append(Groups, AllFlips).                % зливає всі групи в один список

% Мультипризначеність:
% all_flips(++Board, ++Row, ++Col, ++Player, --AllFlips) – єдиний режим: всі захоплення.

% valid_move(++Board, ++Row, ++Col, ++Player)
% Хід у клітинку (Row, Col) допустимий: вона порожня і є захоплення.
valid_move(Board, Row, Col, Player) :-
    get_cell(Board, Row, Col, 0),
    all_flips(Board, Row, Col, Player, Flips),
    Flips \= [].

% Мультипризначеність:
% valid_move(++Board, ++Row, ++Col, ++Player) – єдиний режим: перевірка допустимості ходу.

% valid_moves(++Board, ++Player, --Moves)
% Список усіх допустимих ходів у форматі Row-Col.
valid_moves(Board, Player, Moves) :-
    board_size(S), Max is S - 1,
    findall(Row-Col,
        (   between(0, Max, Row),   % between: перебирає цілі від 0 до Max
            between(0, Max, Col),
            valid_move(Board, Row, Col, Player)
        ),
        Moves).

% Мультипризначеність:
% valid_moves(++Board, ++Player, --Moves) – генерація списку всіх допустимих ходів.
% valid_moves(++Board, ++Player,  +Moves) – перевірка конкретного списку ходів.

% flip_cells(++Board, ++Flips, ++Player, --NewBoard)
% Послідовно перевертає всі фішки зі списку Flips на колір Player.
flip_cells(Board, [],           _,      Board).
flip_cells(Board, [R-C | Rest], Player, NewBoard) :-
    set_cell(Board, R, C, Player, Temp),
    flip_cells(Temp, Rest, Player, NewBoard).

% Мультипризначеність:
% flip_cells(++Board, ++Flips, ++Player, --NewBoard) – єдиний режим: перевертання фішок.

% make_move(++Board, ++Row, ++Col, ++Player, --NewBoard)
% Виконує хід: розміщує фішку гравця і перевертає захоплені.
make_move(Board, Row, Col, Player, NewBoard) :-
    all_flips(Board, Row, Col, Player, Flips),
    set_cell(Board, Row, Col, Player, B1),
    flip_cells(B1, Flips, Player, NewBoard).

% Мультипризначеність:
% make_move(++Board, ++Row, ++Col, ++Player, --NewBoard) – єдиний режим: виконання ходу.

% game_over(++Board, --Winner)
% Перевіряє кінець гри (жоден гравець не може ходити).
% Winner = 1 (чорні), 2 (білі), або 0 (нічия).
game_over(Board, Winner) :-
    valid_moves(Board, 1, []),
    valid_moves(Board, 2, []),
    count_pieces(Board, 1, B),
    count_pieces(Board, 2, W),
    (   B > W -> Winner = 1
    ;   W > B -> Winner = 2
    ;   Winner = 0
    ).

% Мультипризначеність:
% game_over(++Board, --Winner) – єдиний режим: визначення переможця після кінця гри.


% ==============================================================
% Функція оцінки позиції (евристика)
%
% Оцінка ЗАВЖДИ з точки зору чорних (гравець 1):
%   позитивне значення = перевага чорних
%   негативне значення = перевага білих
%
% Вагові коефіцієнти позицій (динамічні, залежать від розміру):
%   кути              (+100) — найстабільніші позиції
%   клітинки біля куту ( -20) — небезпечні (дають кут суперникові)
%   діагональ від куту ( -50) — найгірші позиції
%   краї              ( +10) — стабільні
%   решта             (  -1) — нейтральні
% ==============================================================

% is_corner(++R, ++C, ++Max)
% Перевіряє, що (R, C) є кутовою клітинкою дошки.
is_corner(R, C, Max) :-
    (R =:= 0 ; R =:= Max), (C =:= 0 ; C =:= Max).

% is_edge_corner_adj(++R, ++C, ++Max)
% Перевіряє, що (R, C) є крайовою клітинкою, суміжною з кутом.
is_edge_corner_adj(R, C, Max) :-
    (   R =:= 0,   (C =:= 1 ; C =:= Max-1)
    ;   R =:= Max, (C =:= 1 ; C =:= Max-1)
    ;   C =:= 0,   (R =:= 1 ; R =:= Max-1)
    ;   C =:= Max, (R =:= 1 ; R =:= Max-1)
    ).

% is_diag_corner_adj(++R, ++C, ++Max)
% Перевіряє, що (R, C) стоїть по діагоналі від кута (найгірша позиція).
is_diag_corner_adj(R, C, Max) :-
    (R =:= 1 ; R =:= Max-1), (C =:= 1 ; C =:= Max-1).

% is_edge(++R, ++C, ++Max)
% Перевіряє, що (R, C) знаходиться на краю дошки.
is_edge(R, C, Max) :-
    R =:= 0 ; R =:= Max ; C =:= 0 ; C =:= Max.

% cell_weight_rc(++Row, ++Col, ++Max, --Weight)
% Ваговий коефіцієнт клітинки за її позицією (Max = Size - 1).
cell_weight_rc(R, C, Max, W) :-
    (   is_corner(R, C, Max)          -> W =  100
    ;   is_edge_corner_adj(R, C, Max) -> W =  -20
    ;   is_diag_corner_adj(R, C, Max) -> W =  -50
    ;   is_edge(R, C, Max)            -> W =   10
    ;   % Внутрішні клітинки: краще ближче до центру (стабільніші)
        DistR is min(R, Max - R),
        DistC is min(C, Max - C),
        D is min(DistR, DistC),        % D=1: поряд з краєм, D=2+: ближче до центру
        W is D - 2                     % D=1→-1, D=2→0, D=3→+1, ...
    ).

% Мультипризначеність:
% cell_weight_rc(++Row, ++Col, ++Max, --Weight) – єдиний режим: ваговий коефіцієнт клітинки.

% weight_move(++Max, ++Move, --WeightedMove)
% Прикріплює позиційну вагу до ходу для сортування.
weight_move(Max, R-C, W-(R-C)) :- cell_weight_rc(R, C, Max, W).

% strip_key(++Pair, --Move)
% Витягує хід з пари Вага-Хід.
strip_key(_-M, M).

% sort_moves(++Moves, --Sorted)
% Сортує ходи за спаданням позиційної ваги для кращого відсікання Альфа-Бета.
% Кути та краї переглядаються першими — і для MAX, і для MIN гравця.
sort_moves(Moves, Sorted) :-
    board_size(S), Max is S - 1,
    maplist(weight_move(Max), Moves, Keyed),
    msort(Keyed, Ascending),
    reverse(Ascending, Descending),
    maplist(strip_key, Descending, Sorted).

% evaluate_flat(++Board, ++Idx, ++Size, +Acc, --Score)
% Рекурсивно обчислює зважену суму оцінки по всій дошці.
% Idx — поточний лінійний індекс; Acc — накопичувач.
evaluate_flat([], _, _, Acc, Acc).
evaluate_flat([Cell | Rest], Idx, Size, Acc, Score) :-
    Row is Idx // Size,          % рядок поточної клітинки
    Col is Idx mod Size,         % стовпець поточної клітинки
    Max is Size - 1,
    cell_weight_rc(Row, Col, Max, W),
    (   Cell =:= 1 -> A1 is Acc + W   % чорна фішка — додаємо вагу
    ;   Cell =:= 2 -> A1 is Acc - W   % біла фішка  — віднімаємо вагу
    ;   A1 = Acc                       % порожня клітинка — без змін
    ),
    Idx1 is Idx + 1,
    evaluate_flat(Rest, Idx1, Size, A1, Score).

% Мультипризначеність:
% evaluate_flat(++Board, ++Idx, ++Size, +Acc, --Score) – єдиний режим: обчислення оцінки.

% evaluate(++Board, --Score)
% Евристична оцінка позиції з точки зору чорних.
% Рання гра: позиційна оцінка + мобільність × 10.
% Ендшпіль (>75% клітинок заповнено): лише перевага у фішках × 10.
evaluate(Board, Score) :-
    board_size(Size),
    evaluate_flat(Board, 0, Size, 0, PosScore),
    count_pieces(Board, 1, Black),
    count_pieces(Board, 2, White),
    valid_moves(Board, 1, BM), length(BM, BlackMoves),
    valid_moves(Board, 2, WM), length(WM, WhiteMoves),
    MobilityScore is (BlackMoves - WhiteMoves) * 10,
    Total is Black + White,
    Threshold is (Size * Size * 3) // 4,   % поріг переходу до ендшпілю
    (   Total >= Threshold
    ->  Score is (Black - White) * 10   % ендшпіль: лише кількість фішок
    ;   Score is PosScore + MobilityScore
    ).

% Мультипризначеність:
% evaluate(++Board, --Score) – єдиний режим: обчислення евристичної оцінки позиції.


% ==============================================================
% Алгоритм MinMax з відсіканням Альфа-Бета
%
% Оцінка ЗАВЖДИ з точки зору чорних (гравець 1):
%   MAX-гравець = чорні (1): максимізує оцінку
%   MIN-гравець = білі  (2): мінімізує оцінку
%
% Глибина у пів-ходах (плаях):
%   2 пів-ходи = Easy:   перегляд 1 повного ходу
%   4 пів-ходи = Medium: перегляд 2 повних ходів
%   6 пів-ходів = Hard:  перегляд 3 повних ходів
%   8 пів-ходів = Expert: перегляд 4 повних ходів
% ==============================================================

% minimax(++Board, ++Player, ++Depth, ++Alpha, ++Beta, --BestMove, --Score)
% Кореневий предикат MinMax: вибирає найкращий хід для Player.
%   Alpha — нижня межа (початково -1000000)
%   Beta  — верхня межа (початково +1000000)
%   BestMove — найкращий хід Row-Col, або none (якщо хід не потрібен)
%   Score — оцінка позиції з точки зору чорних
minimax(Board, Player, Depth, Alpha, Beta, BestMove, Score) :-
    valid_moves(Board, Player, Moves),
    (   Depth =:= 0
    ->  evaluate(Board, Score), BestMove = none        % досягнуто ліміту глибини
    ;   Moves = []
    ->  % поточний гравець пропускає — передаємо хід суперникові
        opponent(Player, Opp),
        valid_moves(Board, Opp, OppMoves),
        (   OppMoves = []
        ->  terminal_score(Board, Score), BestMove = none   % обидва пропускають — кінець
        ;   minimax(Board, Opp, Depth, Alpha, Beta, _, Score), BestMove = none
        )
    ;   sort_moves(Moves, Sorted),
        (   Player =:= 1
        ->  max_search(Sorted, Board, Depth, Alpha, Beta, none, -1000000, BestMove, Score)
        ;   min_search(Sorted, Board, Depth, Alpha, Beta, none,  1000000, BestMove, Score)
        )
    ).

% Мультипризначеність:
% minimax(++,++,++,++,++,--,--) – єдиний режим: пошук найкращого ходу AI.

% terminal_score(++Board, --Score)
% Оцінка кінцевої позиції: перемога (+10000), поразка (-10000), нічия (0).
terminal_score(Board, Score) :-
    count_pieces(Board, 1, B),
    count_pieces(Board, 2, W),
    (   B > W -> Score =  10000
    ;   W > B -> Score = -10000
    ;   Score = 0
    ).

% Мультипризначеність:
% terminal_score(++Board, --Score) – єдиний режим: оцінка кінцевої позиції.

% max_search(++Moves, ++Board, ++Depth, ++Alpha, ++Beta,
%            +CurBest, +CurScore, --BestMove, --BestScore)
% MAX-вузол: перебирає ходи чорних, шукає максимум, оновлює Alpha.
% Альфа-відсікання: зупиняємось, якщо NewAlpha >= Beta.
max_search([], _, _, _, _, Best, BestScore, Best, BestScore).
max_search([R-C | Rest], Board, Depth, Alpha, Beta,
           CurBest, CurScore, BestMove, BestScore) :-
    make_move(Board, R, C, 1, NewBoard),
    D1 is Depth - 1,
    minimax(NewBoard, 2, D1, Alpha, Beta, _, ChildScore),
    (   ChildScore > CurScore                               % знайшли кращий хід
    ->  NB = R-C, NS = ChildScore, NA is max(Alpha, ChildScore)
    ;   NB = CurBest, NS = CurScore, NA = Alpha
    ),
    (   NA >= Beta                                          % альфа-відсікання
    ->  BestMove = NB, BestScore = NS
    ;   max_search(Rest, Board, Depth, NA, Beta, NB, NS, BestMove, BestScore)
    ).

% Мультипризначеність:
% max_search(++,++,++,++,++,+,+,--,--) – єдиний режим: перебір ходів MAX-вузла.

% min_search(++Moves, ++Board, ++Depth, ++Alpha, ++Beta,
%            +CurBest, +CurScore, --BestMove, --BestScore)
% MIN-вузол: перебирає ходи білих, шукає мінімум, оновлює Beta.
% Бета-відсікання: зупиняємось, якщо Alpha >= NewBeta.
min_search([], _, _, _, _, Best, BestScore, Best, BestScore).
min_search([R-C | Rest], Board, Depth, Alpha, Beta,
           CurBest, CurScore, BestMove, BestScore) :-
    make_move(Board, R, C, 2, NewBoard),
    D1 is Depth - 1,
    minimax(NewBoard, 1, D1, Alpha, Beta, _, ChildScore),
    (   ChildScore < CurScore                               % знайшли кращий хід
    ->  NB = R-C, NS = ChildScore, NB2 is min(Beta, ChildScore)
    ;   NB = CurBest, NS = CurScore, NB2 = Beta
    ),
    (   Alpha >= NB2                                        % бета-відсікання
    ->  BestMove = NB, BestScore = NS
    ;   min_search(Rest, Board, Depth, Alpha, NB2, NB, NS, BestMove, BestScore)
    ).

% Мультипризначеність:
% min_search(++,++,++,++,++,+,+,--,--) – єдиний режим: перебір ходів MIN-вузла.


% ==============================================================
% HTTP-обробники REST API
% ==============================================================

% move_to_obj(++Move, --JsonObj)
% Перетворює хід у форматі Row-Col на JSON-об'єкт {row, col}.
move_to_obj(Row-Col, json{row: Row, col: Col}).

% next_state(++Board, ++JustMoved, --Next, --Over, --Winner, --VMoves)
% Визначає наступний стан гри після ходу JustMoved:
%   — якщо суперник має ходи → його черга;
%   — якщо суперник без ходів, але JustMoved має → JustMoved ходить знову;
%   — якщо жоден не має ходів → кінець гри.
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

% Мультипризначеність:
% next_state(++Board, ++JustMoved, --Next, --Over, --Winner, --VMoves) – єдиний режим.

% handle_new_game(++Request)
% POST /api/new_game  { size: N }
% Ініціалізує нову гру з дошкою N×N, повертає початковий стан.
handle_new_game(Request) :-
    http_read_json_dict(Request, Data),   % читає тіло POST-запиту як JSON-словник
    Size = Data.size,
    set_size(Size),
    initial_board(Board),
    valid_moves(Board, 1, Moves),
    maplist(move_to_obj, Moves, MoveObjs),
    count_pieces(Board, 1, Black),
    count_pieces(Board, 2, White),
    reply_json_dict(json{                 % відповідає JSON-словником
        board:          Board,
        current_player: 1,
        black_count:    Black,
        white_count:    White,
        valid_moves:    MoveObjs,
        game_over:      0,
        winner:         -1
    }).

% handle_make_move(++Request)
% POST /api/make_move  { board, player, row, col }
% Виконує хід гравця, повертає новий стан дошки.
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

% handle_ai_move(++Request)
% POST /api/ai_move  { board, player, depth }
% Обчислює найкращий хід AI алгоритмом MinMax + Альфа-Бета.
% Якщо AI не має ходів — повертає passed:1 та передає хід суперникові.
handle_ai_move(Request) :-
    http_read_json_dict(Request, Data),
    Board  = Data.board,
    Player = Data.player,
    Depth  = Data.depth,
    setup_size_from_board(Board),
    valid_moves(Board, Player, Moves),
    (   Moves = []
    ->  % AI пропускає хід
        opponent(Player, Opp),
        valid_moves(Board, Opp, OppMoves),
        count_pieces(Board, 1, Black),
        count_pieces(Board, 2, White),
        (   OppMoves = []
        ->  % обидва без ходів — кінець гри
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
