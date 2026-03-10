/* ============================================================
   Reversi — Контролер гри (фронтенд)
   Взаємодіє з Prolog-сервером через REST API
   ============================================================ */

'use strict';

const API = 'http://localhost:8080/api';

// ============================================================
// Стан гри
// ============================================================
const state = {
  board:         Array(64).fill(0),
  size:          8,            // розмір дошки (6, 8 або 10)
  gameId:        0,            // зростає при кожній новій грі — ігнорує застарілі відповіді
  currentPlayer: 1,
  validMoves:    [],           // [{row, col}, ...]
  lastMove:      null,         // {row, col}
  gameOver:      false,
  winner:        -1,
  blackCount:    2,
  whiteCount:    2,
  mode:          'ha',         // hh / ha / aa
  humanPlayer:   1,            // номер гравця-людини (режим ha)
  depthBlack:    4,
  depthWhite:    4,
  moveNumber:    0,
  aiRunning:     false,
  aiTimer:       null,
  moveDelay:     600,          // затримка між ходами (мс), щоб зміна дошки була помітна
};

// ============================================================
// Допоміжні функції DOM
// ============================================================
const $  = id => document.getElementById(id);
const el = (tag, cls, html) => {
  const e = document.createElement(tag);
  if (cls)  e.className = cls;
  if (html) e.innerHTML = html;
  return e;
};

// ============================================================
// Побудова сітки дошки N×N (оновлюється при кожній новій грі)
// ============================================================
function buildBoardDOM() {
  const S     = state.size;
  const total = S * S;
  const board = $('board');
  board.innerHTML = '';

  // Встановлюємо CSS-сітку: N стовпців/рядків розміру --cell-size
  board.style.gridTemplateColumns = `repeat(${S}, var(--cell-size))`;
  board.style.gridTemplateRows    = `repeat(${S}, var(--cell-size))`;

  // Декоративні точки на чверть-позиціях дошки (0-based)
  const q = Math.floor(S / 4);
  const stars = new Set([
    (q) * S + q,         (q) * S + (S - q - 1),
    (S - q - 1) * S + q, (S - q - 1) * S + (S - q - 1)
  ]);

  for (let i = 0; i < total; i++) {
    const cell = el('div', 'cell');
    cell.dataset.idx = i;
    if (stars.has(i)) cell.dataset.star = '1';
    cell.addEventListener('click', onCellClick);
    board.appendChild(cell);
  }

  // Підписи стовпців: A, B, C, ...
  const colLabels = $('col-labels');
  colLabels.innerHTML = '<div class="corner-spacer"></div>';
  for (let c = 0; c < S; c++) {
    const span = document.createElement('span');
    span.textContent = String.fromCharCode(65 + c);
    colLabels.appendChild(span);
  }

  // Підписи рядків: 1, 2, 3, ...
  const rowLabels = $('row-labels');
  rowLabels.innerHTML = '';
  for (let r = 0; r < S; r++) {
    const span = document.createElement('span');
    span.textContent = r + 1;
    rowLabels.appendChild(span);
  }
}

// ============================================================
// Відображення дошки зі стану
// ============================================================
function renderBoard() {
  const S       = Math.round(Math.sqrt(state.board.length));
  const cells   = document.querySelectorAll('.cell');
  const validSet = new Set(state.validMoves.map(m => m.row * S + m.col));
  const lastIdx  = state.lastMove ? state.lastMove.row * S + state.lastMove.col : -1;

  cells.forEach((cell, i) => {
    // Скидаємо класи та вміст клітинки
    cell.className = 'cell';
    cell.innerHTML = '';

    const v = state.board[i];

    if (v === 1 || v === 2) {
      const disc = el('div', `disc disc-${v === 1 ? 'black' : 'white'}`);
      disc.classList.add('placed');
      cell.appendChild(disc);
    } else if (validSet.has(i) && !state.gameOver && !isAI(state.currentPlayer)) {
      cell.classList.add('valid-hint');
    }

    if (i === lastIdx) cell.classList.add('last-move');

    // Зберігаємо декоративну точку
    if (cell.dataset.star) cell.dataset.star = '1';
  });
}

// ============================================================
// Оновлення HUD (рахунок, індикатор ходу, статус)
// ============================================================
function updateHUD() {
  $('cnt-black').textContent = state.blackCount;
  $('cnt-white').textContent = state.whiteCount;

  // Підсвітка активного гравця
  $('score-black').classList.toggle('active-player', state.currentPlayer === 1 && !state.gameOver);
  $('score-white').classList.toggle('active-player', state.currentPlayer === 2 && !state.gameOver);

  const disc = $('turn-disc');
  disc.className = 'disc ' + (state.currentPlayer === 1 ? 'disc-black' : 'disc-white');

  const playerName = currentPlayerName();
  $('turn-text').textContent = state.gameOver
    ? 'Гра завершена'
    : `Хід: ${playerName}`;
}

// ============================================================
// Допоміжні функції
// ============================================================
function currentPlayerName() {
  return state.currentPlayer === 1 ? 'Чорні' : 'Білі';
}

function isAI(player) {
  if (state.mode === 'aa') return true;
  if (state.mode === 'ha') return player !== state.humanPlayer;
  return false;  // hh: жоден не є AI
}

function depthFor(player) {
  return player === 1 ? state.depthBlack : state.depthWhite;
}

function colLetter(col) { return String.fromCharCode(65 + col); }
function moveLabel(row, col) { return colLetter(col) + (row + 1); }

// ============================================================
// Застосування відповіді сервера до стану гри
// ============================================================
function applyResponse(data) {
  state.board         = data.board;
  state.currentPlayer = data.next_player ?? data.current_player ?? state.currentPlayer;
  state.validMoves    = data.valid_moves ?? [];
  state.blackCount    = data.black_count;
  state.whiteCount    = data.white_count;
  state.gameOver      = data.game_over === 1;
  state.winner        = data.winner;   // -1 = гра триває, 0 = нічия, 1 = чорні, 2 = білі
  if (data.last_move) state.lastMove = data.last_move;
}

// ============================================================
// Журнал ходів
// ============================================================
function addHistoryEntry(player, row, col, passed) {
  const list = $('history');
  const li = el('li');
  if (passed) {
    li.innerHTML = `<span class="h-${player === 1 ? 'black' : 'white'}">${player === 1 ? 'Чорні' : 'Білі'}</span> <span class="h-pass">пропустили</span>`;
  } else {
    const cls  = player === 1 ? 'h-black' : 'h-white';
    const name = player === 1 ? 'Чорні' : 'Білі';
    li.innerHTML = `<span class="${cls}">${name}</span> → ${moveLabel(row, col)}`;
  }
  list.appendChild(li);
  list.scrollTop = list.scrollHeight;
}

// ============================================================
// Звук: короткий клік через Web Audio API (без зовнішніх файлів)
// ============================================================
const audioCtx = new (window.AudioContext || window.webkitAudioContext)();

function playMoveSound() {
  const osc    = audioCtx.createOscillator();
  const gain   = audioCtx.createGain();
  osc.connect(gain);
  gain.connect(audioCtx.destination);
  osc.type            = 'sine';
  osc.frequency.value = 480;
  gain.gain.setValueAtTime(0.25, audioCtx.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.12);
  osc.start(audioCtx.currentTime);
  osc.stop(audioCtx.currentTime + 0.12);
}

// ============================================================
// Повідомлення статусу
// ============================================================
function setStatus(msg) {
  $('status-msg').textContent = msg;
}

// ============================================================
// Запити до API
// ============================================================
async function apiNewGame(size) {
  const res = await fetch(`${API}/new_game`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ size })
  });
  if (!res.ok) throw new Error('Server error');
  return res.json();
}

async function apiMakeMove(board, player, row, col) {
  const res = await fetch(`${API}/make_move`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ board, player, row, col })
  });
  if (!res.ok) throw new Error('Server error');
  return res.json();
}

async function apiAiMove(board, player, depth) {
  const res = await fetch(`${API}/ai_move`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ board, player, depth })
  });
  if (!res.ok) throw new Error('Server error');
  return res.json();
}

// ============================================================
// Основна логіка гри
// ============================================================
async function startGame() {
  stopAI();
  state.mode       = $('sel-mode').value;
  state.size       = parseInt($('sel-size').value, 10);
  const depth      = parseInt($('sel-depth-black').value, 10);
  state.depthBlack = depth;
  state.depthWhite = state.mode === 'aa' ? parseInt($('sel-depth-white').value, 10) : depth;
  // Випадкове призначення кольору людині у режимі людина проти AI
  state.humanPlayer = (state.mode === 'ha') ? (Math.random() < 0.5 ? 1 : 2) : 1;
  state.lastMove   = null;
  state.moveNumber = 0;
  state.gameId++;
  const myGameId = state.gameId;
  $('history').innerHTML = '';
  setStatus('');
  hideModal();
  buildBoardDOM();

  try {
    const data = await apiNewGame(state.size);
    if (state.gameId !== myGameId) return;  // застаріла відповідь від попереднього запуску
    state.board         = data.board;
    state.currentPlayer = data.current_player;
    state.validMoves    = data.valid_moves ?? [];
    state.blackCount    = data.black_count;
    state.whiteCount    = data.white_count;
    state.gameOver      = false;
    state.winner        = -1;

    renderBoard();
    updateHUD();
    if (state.mode === 'ha') {
      const colorName = state.humanPlayer === 1 ? 'чорними' : 'білими';
      setStatus(`Ви граєте ${colorName}.`);
    }
    scheduleAIIfNeeded();
  } catch (e) {
    setStatus('Неможливо зʼєднатися з сервером. Чи запущено Prolog?');
  }
}

// ============================================================
// Клік людини по клітинці
// ============================================================
async function onCellClick(e) {
  if (state.gameOver || state.aiRunning) return;
  if (isAI(state.currentPlayer)) return;

  const idx = parseInt(e.currentTarget.dataset.idx, 10);
  const S   = Math.round(Math.sqrt(state.board.length));
  const row = Math.floor(idx / S);
  const col = idx % S;

  const isValid = state.validMoves.some(m => m.row === row && m.col === col);
  if (!isValid) return;

  await performMove(state.currentPlayer, row, col);
}

// ============================================================
// Виконання ходу (людина або AI)
// ============================================================
async function performMove(player, row, col) {
  const myGameId = state.gameId;
  try {
    const data = await apiMakeMove(state.board, player, row, col);
    if (state.gameId !== myGameId) return;
    if (data.error) {
      setStatus('Недопустимий хід: ' + (data.message || data.error));
      return;
    }
    state.lastMove = { row, col };
    addHistoryEntry(player, row, col, false);
    playMoveSound();
    applyResponse(data);
    renderBoard();
    updateHUD();

    if (state.gameOver) {
      showGameOver();
      return;
    }

    // Перевірка: суперник пропустив хід (next_player лишився тим самим)
    if (data.next_player !== 0 && data.next_player === player) {
      const otherName = player === 1 ? 'Білі' : 'Чорні';
      setStatus(`${otherName} не мають ходів — пропускають.`);
      addHistoryEntry(player === 1 ? 2 : 1, -1, -1, true);
    } else {
      setStatus('');
    }

    scheduleAIIfNeeded();
  } catch (err) {
    setStatus('Помилка сервера. Перевірте Prolog.');
    console.error(err);
  }
}

// ============================================================
// Хід AI
// ============================================================
function scheduleAIIfNeeded() {
  if (state.gameOver) return;
  if (!isAI(state.currentPlayer)) return;
  clearTimeout(state.aiTimer);
  // Невелика затримка, щоб зміна дошки була видима до наступного ходу
  state.aiTimer = setTimeout(runAI, state.moveDelay);
}

async function runAI() {
  const myGameId = state.gameId;
  if (state.gameOver || !isAI(state.currentPlayer)) return;
  state.aiRunning = true;
  setStatus('');

  const player = state.currentPlayer;
  const depth  = depthFor(player);

  try {
    const data = await apiAiMove(state.board, player, depth);

    if (state.gameId !== myGameId) { state.aiRunning = false; return; }

    if (data.passed === 1) {
      addHistoryEntry(player, -1, -1, true);
      const pName = player === 1 ? 'Чорний' : 'Білий';
      setStatus(`${pName} ШІ не має допустимих ходів — пропускає.`);
      applyResponse(data);
      renderBoard();
      updateHUD();
      state.aiRunning = false;
      scheduleAIIfNeeded();
      return;
    }

    const { row, col } = data.move;
    state.lastMove = { row, col };
    addHistoryEntry(player, row, col, false);
    playMoveSound();
    applyResponse(data);
    renderBoard();
    updateHUD();

    state.aiRunning = false;

    if (state.gameOver) {
      showGameOver();
      return;
    }

    if (data.next_player !== 0 && data.next_player === player) {
      const otherName = player === 1 ? 'Білі' : 'Чорні';
      setStatus(`${otherName} не мають ходів — пропускають.`);
      addHistoryEntry(player === 1 ? 2 : 1, -1, -1, true);
    } else {
      setStatus('');
    }

    scheduleAIIfNeeded();
  } catch (err) {
    state.aiRunning = false;
    setStatus('Помилка ШІ. Перевірте Prolog сервер.');
    console.error(err);
  }
}

function stopAI() {
  clearTimeout(state.aiTimer);
  state.aiRunning = false;
}

// ============================================================
// Модальне вікно завершення гри
// ============================================================
function showGameOver() {
  stopAI();
  const w = state.winner;

  // Трофей і заголовок
  $('modal-trophy').textContent = w === 0 ? '🤝' : '🏆';
  if (w === 0) {
    $('modal-title').textContent    = 'Нічия!';
    $('modal-subtitle').textContent = 'Обидва гравці завершили з однаковою кількістю фішок.';
  } else {
    const wName = w === 1 ? 'Чорні' : 'Білі';
    $('modal-title').textContent    = `${wName} перемогли!`;
    $('modal-subtitle').textContent = `${wName} захопили дошку.`;
  }

  // Рахунок
  $('modal-black').textContent = state.blackCount;
  $('modal-white').textContent = state.whiteCount;

  // Підсвітка стовпця переможця
  $('modal-col-black').classList.toggle('winner-col', w === 1);
  $('modal-col-white').classList.toggle('winner-col', w === 2);

  // Підписи гравців: показуємо хто людина, а хто AI (режим ha)
  if (state.mode === 'ha') {
    $('modal-name-black').textContent = state.humanPlayer === 1 ? 'Ви (Чорні)' : 'ШІ (Чорні)';
    $('modal-name-white').textContent = state.humanPlayer === 2 ? 'Ви (Білі)' : 'ШІ (Білі)';
  } else {
    $('modal-name-black').textContent = state.mode === 'aa' ? 'ШІ (Чорні)' : 'Чорні';
    $('modal-name-white').textContent = state.mode === 'aa' ? 'ШІ (Білі)' : 'Білі';
  }

  $('modal').style.display = 'flex';
}

function hideModal() {
  $('modal').style.display = 'none';
}

// ============================================================
// Здача
// ============================================================
async function surrender() {
  if (state.gameOver) return;
  stopAI();
  const loser  = state.currentPlayer;
  const winner = loser === 1 ? 2 : 1;
  const lName  = loser  === 1 ? 'Чорні' : 'Білі';
  const wName  = winner === 1 ? 'Чорні' : 'Білі';

  state.gameOver = true;
  state.winner   = winner;

  $('modal-trophy').textContent   = '🏳️';
  $('modal-title').textContent    = `${wName} перемогли!`;
  $('modal-subtitle').textContent = `${lName} здалися.`;
  $('modal-black').textContent    = state.blackCount;
  $('modal-white').textContent    = state.whiteCount;
  $('modal-col-black').classList.toggle('winner-col', winner === 1);
  $('modal-col-white').classList.toggle('winner-col', winner === 2);
  $('modal-name-black').textContent = 'Чорні';
  $('modal-name-white').textContent = 'Білі';
  $('modal').style.display = 'flex';

  updateHUD();
}

// ============================================================
// Видимість селекторів складності залежно від режиму
// ============================================================
function updateDepthVisibility() {
  const mode = $('sel-mode').value;
  // Один селектор складності для ha/hh, два для aa
  $('field-depth-ai').style.display    = (mode !== 'hh') ? '' : 'none';
  $('field-depth-white').style.display = (mode === 'aa') ? '' : 'none';
  // У режимі aa перейменовуємо перший селектор
  $('field-depth-ai').querySelector('label').textContent =
    (mode === 'aa') ? 'Складність ШІ — Чорні' : 'Складність ШІ';
}

// ============================================================
// Підписи гравців (Людина / AI)
// ============================================================
function updatePlayerLabels() {
  const mode = $('sel-mode').value;
  $('lbl-black').textContent = (mode === 'aa') ? 'ШІ (Чорні)' : 'Чорні';
  $('lbl-white').textContent = (mode === 'aa') ? 'ШІ (Білі)' : 'Білі';
}

// ============================================================
// Прив'язка подій
// ============================================================
$('btn-new').addEventListener('click', startGame);

$('sel-mode').addEventListener('change', () => {
  updateDepthVisibility();
  updatePlayerLabels();
});

$('btn-surrender').addEventListener('click', surrender);

$('btn-exit').addEventListener('click', () => {
  if (confirm('Вийти з гри?')) {
    stopAI();
    state.gameOver = true;
    updateHUD();
    setStatus('Гру завершено. Натисніть «Нова гра» для перезапуску.');
    renderBoard();   // прибираємо підказки
  }
});

$('modal-play-again').addEventListener('click', startGame);
$('modal-close').addEventListener('click', hideModal);

// Закриття модального вікна кліком на фон
$('modal').addEventListener('click', e => {
  if (e.target === $('modal')) hideModal();
});

// ============================================================
// Ініціалізація
// ============================================================
updateDepthVisibility();
updatePlayerLabels();

// Автоматичний запуск гри при завантаженні сторінки
startGame();
