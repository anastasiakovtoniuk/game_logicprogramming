/* ============================================================
   Reversi — Frontend Game Controller
   Communicates with Prolog backend via REST API
   ============================================================ */

'use strict';

const API = 'http://localhost:8080/api';

// ============================================================
// State
// ============================================================
const state = {
  board:         Array(64).fill(0),
  size:          8,            // board dimension (6, 8, or 10)
  gameId:        0,            // incremented on each new game to discard stale responses
  currentPlayer: 1,
  validMoves:    [],           // [{row, col}, ...]
  lastMove:      null,         // {row, col}
  gameOver:      false,
  winner:        -1,
  blackCount:    2,
  whiteCount:    2,
  mode:          'ha',         // hh / ha / aa
  humanPlayer:   1,            // which player number the human controls (ha mode)
  depthBlack:    4,
  depthWhite:    4,
  moveNumber:    0,
  aiRunning:     false,
  aiTimer:       null,
  moveDelay:     600,          // ms pause between moves so the board is visible
};

// ============================================================
// DOM helpers
// ============================================================
const $  = id => document.getElementById(id);
const el = (tag, cls, html) => {
  const e = document.createElement(tag);
  if (cls)  e.className = cls;
  if (html) e.innerHTML = html;
  return e;
};

// ============================================================
// Build the N×N board grid (rebuilt on each new game)
// ============================================================
function buildBoardDOM() {
  const S     = state.size;
  const total = S * S;
  const board = $('board');
  board.innerHTML = '';

  // Set CSS grid to N columns/rows of --cell-size each
  board.style.gridTemplateColumns = `repeat(${S}, var(--cell-size))`;
  board.style.gridTemplateRows    = `repeat(${S}, var(--cell-size))`;

  // Star points: quarter positions (S/4 and 3*S/4 - 1, 0-based)
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

  // Column labels: A, B, C, ...
  const colLabels = $('col-labels');
  colLabels.innerHTML = '<div class="corner-spacer"></div>';
  for (let c = 0; c < S; c++) {
    const span = document.createElement('span');
    span.textContent = String.fromCharCode(65 + c);
    colLabels.appendChild(span);
  }

  // Row labels: 1, 2, 3, ...
  const rowLabels = $('row-labels');
  rowLabels.innerHTML = '';
  for (let r = 0; r < S; r++) {
    const span = document.createElement('span');
    span.textContent = r + 1;
    rowLabels.appendChild(span);
  }
}

// ============================================================
// Render board from state
// ============================================================
function renderBoard() {
  const S      = Math.round(Math.sqrt(state.board.length));
  const cells   = document.querySelectorAll('.cell');
  const validSet = new Set(state.validMoves.map(m => m.row * S + m.col));
  const lastIdx  = state.lastMove ? state.lastMove.row * S + state.lastMove.col : -1;

  cells.forEach((cell, i) => {
    // Reset classes
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

    // Star dot
    if (cell.dataset.star) cell.dataset.star = '1';
  });
}

// ============================================================
// Update HUD (scores, turn indicator, status)
// ============================================================
function updateHUD() {
  $('cnt-black').textContent = state.blackCount;
  $('cnt-white').textContent = state.whiteCount;

  // active player highlight
  $('score-black').classList.toggle('active-player', state.currentPlayer === 1 && !state.gameOver);
  $('score-white').classList.toggle('active-player', state.currentPlayer === 2 && !state.gameOver);

  const disc = $('turn-disc');
  disc.className = 'disc ' + (state.currentPlayer === 1 ? 'disc-black' : 'disc-white');

  const playerName = currentPlayerName();
  $('turn-text').textContent = state.gameOver
    ? 'Game over'
    : `${playerName}'s turn`;
}

// ============================================================
// Helpers
// ============================================================
function currentPlayerName() {
  return state.currentPlayer === 1 ? 'Black' : 'White';
}

function isAI(player) {
  if (state.mode === 'aa') return true;
  if (state.mode === 'ha') return player !== state.humanPlayer;
  return false;  // hh: nobody is AI
}

function depthFor(player) {
  return player === 1 ? state.depthBlack : state.depthWhite;
}

function colLetter(col) { return String.fromCharCode(65 + col); }
function moveLabel(row, col) { return colLetter(col) + (row + 1); }

// ============================================================
// Apply server response to local state
// ============================================================
function applyResponse(data) {
  state.board         = data.board;
  state.currentPlayer = data.next_player ?? data.current_player ?? state.currentPlayer;
  state.validMoves    = data.valid_moves ?? [];
  state.blackCount    = data.black_count;
  state.whiteCount    = data.white_count;
  state.gameOver      = data.game_over === 1;
  state.winner        = data.winner;   // -1 = no winner yet, 0=draw, 1=black, 2=white
  if (data.last_move) state.lastMove = data.last_move;
}

// ============================================================
// History
// ============================================================
function addHistoryEntry(player, row, col, passed) {
  const list = $('history');
  const li = el('li');
  if (passed) {
    li.innerHTML = `<span class="h-${player === 1 ? 'black' : 'white'}">${player === 1 ? 'Black' : 'White'}</span> <span class="h-pass">passed</span>`;
  } else {
    const cls  = player === 1 ? 'h-black' : 'h-white';
    const name = player === 1 ? 'Black' : 'White';
    li.innerHTML = `<span class="${cls}">${name}</span> → ${moveLabel(row, col)}`;
  }
  list.appendChild(li);
  list.scrollTop = list.scrollHeight;
}

// ============================================================
// Sound: short click using Web Audio API (no external files)
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
// Status messages
// ============================================================
function setStatus(msg) {
  $('status-msg').textContent = msg;
}

// ============================================================
// API calls
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
// Main game flow
// ============================================================
async function startGame() {
  stopAI();
  state.mode       = $('sel-mode').value;
  state.size       = parseInt($('sel-size').value, 10);
  const depth      = parseInt($('sel-depth-black').value, 10);
  state.depthBlack = depth;
  state.depthWhite = state.mode === 'aa' ? parseInt($('sel-depth-white').value, 10) : depth;
  // Randomly assign human color in Human vs AI mode
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
    if (state.gameId !== myGameId) return;  // stale response from a previous startGame
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
      const colorName = state.humanPlayer === 1 ? 'Black' : 'White';
      setStatus(`You are ${colorName}.`);
    }
    scheduleAIIfNeeded();
  } catch (e) {
    setStatus('Cannot reach server. Is Prolog running?');
  }
}

// ============================================================
// Human click on cell
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
// Execute a move (human or AI)
// ============================================================
async function performMove(player, row, col) {
  const myGameId = state.gameId;
  try {
    const data = await apiMakeMove(state.board, player, row, col);
    if (state.gameId !== myGameId) return;
    if (data.error) {
      setStatus('Invalid move: ' + (data.message || data.error));
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

    // Check if current player passed (next_player stayed same player)
    if (data.next_player !== 0 && data.next_player === player) {
      const otherName = player === 1 ? 'White' : 'Black';
      setStatus(`${otherName} has no moves — skipped.`);
      addHistoryEntry(player === 1 ? 2 : 1, -1, -1, true);
    } else {
      setStatus('');
    }

    scheduleAIIfNeeded();
  } catch (err) {
    setStatus('Server error. Check Prolog.');
    console.error(err);
  }
}

// ============================================================
// AI move
// ============================================================
function scheduleAIIfNeeded() {
  if (state.gameOver) return;
  if (!isAI(state.currentPlayer)) return;
  clearTimeout(state.aiTimer);
  // Small delay so the board render is visible
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
      const pName = player === 1 ? 'Black' : 'White';
      setStatus(`${pName} AI has no valid moves — passed.`);
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
      const otherName = player === 1 ? 'White' : 'Black';
      setStatus(`${otherName} has no moves — skipped.`);
      addHistoryEntry(player === 1 ? 2 : 1, -1, -1, true);
    } else {
      setStatus('');
    }

    scheduleAIIfNeeded();
  } catch (err) {
    state.aiRunning = false;
    setStatus('AI error. Check Prolog server.');
    console.error(err);
  }
}

function stopAI() {
  clearTimeout(state.aiTimer);
  state.aiRunning = false;
}

// ============================================================
// Game Over modal
// ============================================================
function showGameOver() {
  stopAI();
  const w = state.winner;

  // Trophy & title
  $('modal-trophy').textContent = w === 0 ? '🤝' : '🏆';
  if (w === 0) {
    $('modal-title').textContent    = "It's a Draw!";
    $('modal-subtitle').textContent = 'Both players finished with the same number of pieces.';
  } else {
    const wName = w === 1 ? 'Black' : 'White';
    $('modal-title').textContent    = `${wName} Wins!`;
    $('modal-subtitle').textContent = `${wName} dominates the board.`;
  }

  // Scores
  $('modal-black').textContent = state.blackCount;
  $('modal-white').textContent = state.whiteCount;

  // Highlight the winner column
  $('modal-col-black').classList.toggle('winner-col', w === 1);
  $('modal-col-white').classList.toggle('winner-col', w === 2);

  // Show which color is human in ha mode
  if (state.mode === 'ha') {
    $('modal-name-black').textContent = state.humanPlayer === 1 ? 'You (Black)' : 'AI (Black)';
    $('modal-name-white').textContent = state.humanPlayer === 2 ? 'You (White)' : 'AI (White)';
  } else {
    $('modal-name-black').textContent = state.mode === 'aa' ? 'AI (Black)' : 'Black';
    $('modal-name-white').textContent = state.mode === 'aa' ? 'AI (White)' : 'White';
  }

  $('modal').style.display = 'flex';
}

function hideModal() {
  $('modal').style.display = 'none';
}

// ============================================================
// Surrender
// ============================================================
async function surrender() {
  if (state.gameOver) return;
  stopAI();
  const loser  = state.currentPlayer;
  const winner = loser === 1 ? 2 : 1;
  const lName  = loser  === 1 ? 'Black' : 'White';
  const wName  = winner === 1 ? 'Black' : 'White';

  state.gameOver = true;
  state.winner   = winner;

  $('modal-trophy').textContent   = '🏳️';
  $('modal-title').textContent    = `${wName} Wins!`;
  $('modal-subtitle').textContent = `${lName} surrendered.`;
  $('modal-black').textContent    = state.blackCount;
  $('modal-white').textContent    = state.whiteCount;
  $('modal-col-black').classList.toggle('winner-col', winner === 1);
  $('modal-col-white').classList.toggle('winner-col', winner === 2);
  $('modal-name-black').textContent = 'Black';
  $('modal-name-white').textContent = 'White';
  $('modal').style.display = 'flex';

  updateHUD();
}

// ============================================================
// Mode visibility: hide irrelevant depth selectors
// ============================================================
function updateDepthVisibility() {
  const mode = $('sel-mode').value;
  // Single difficulty selector for ha/hh, two for aa
  $('field-depth-ai').style.display    = (mode !== 'hh') ? '' : 'none';
  $('field-depth-white').style.display = (mode === 'aa') ? '' : 'none';
  // In aa mode, relabel the first selector
  $('field-depth-ai').querySelector('label').textContent =
    (mode === 'aa') ? 'AI Difficulty — Black' : 'AI Difficulty';
}

// ============================================================
// Player label names (Human / AI)
// ============================================================
function updatePlayerLabels() {
  const mode = $('sel-mode').value;
  $('lbl-black').textContent = (mode === 'aa') ? 'Black AI' : 'Black';
  $('lbl-white').textContent = (mode === 'aa') ? 'White AI' : 'White';
}

// ============================================================
// Event wiring
// ============================================================
$('btn-new').addEventListener('click', startGame);

$('sel-mode').addEventListener('change', () => {
  updateDepthVisibility();
  updatePlayerLabels();
});

$('btn-surrender').addEventListener('click', surrender);

$('btn-exit').addEventListener('click', () => {
  if (confirm('Exit the game?')) {
    stopAI();
    state.gameOver = true;
    updateHUD();
    setStatus('Game ended. Press "New Game" to restart.');
    renderBoard();   // clear hints
  }
});

$('modal-play-again').addEventListener('click', startGame);
$('modal-close').addEventListener('click', hideModal);

// Close modal on backdrop click
$('modal').addEventListener('click', e => {
  if (e.target === $('modal')) hideModal();
});

// ============================================================
// Init
// ============================================================
updateDepthVisibility();
updatePlayerLabels();

// Attempt to start a game automatically
startGame();
