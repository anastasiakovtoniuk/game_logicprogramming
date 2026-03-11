module Reversi
  ( Cell(..)
  , Pos
  , Board
  , Winner(..)
  , NextState(..)
  , SearchResult(..)
  , cellToInt
  , intToCell
  , intToPlayer
  , boardFromList
  , boardFromFlatAuto
  , flattenBoard
  , boardSize
  , initialBoard
  , inBounds
  , getCell
  , setCell
  , countPieces
  , opponent
  , validMove
  , validMoves
  , makeMove
  , makeMoveUnsafe
  , gameOver
  , winner
  , evaluate
  , terminalScore
  , minimax
  , chooseBestMove
  , nextState
  , prettyBoard
  ) where

import Data.Array (Array, (!), (//), array, assocs, bounds, elems, indices)
import Data.Function (on)
import Data.List (foldl', sortBy)

-- ==============================================================
-- Базові типи
-- ==============================================================

data Cell = Empty | Black | White
  deriving (Eq)

type Pos = (Int, Int)
type Board = Array Pos Cell

data Winner = WinnerBlack | WinnerWhite | Draw
  deriving (Eq, Show)

data NextState = NextState
  { nsNextPlayer :: Maybe Cell
  , nsGameOver   :: Bool
  , nsWinner     :: Maybe Winner
  , nsValidMoves :: [Pos]
  } deriving (Eq, Show)

data SearchResult = SearchResult
  { srMove  :: Maybe Pos
  , srScore :: Int
  } deriving (Eq, Show)

instance Show Cell where
  show Empty = "."
  show Black = "B"
  show White = "W"

cellToInt :: Cell -> Int
cellToInt Empty = 0
cellToInt Black = 1
cellToInt White = 2

intToCell :: Int -> Either String Cell
intToCell 0 = Right Empty
intToCell 1 = Right Black
intToCell 2 = Right White
intToCell x = Left ("Невідоме значення клітинки: " ++ show x)

intToPlayer :: Int -> Either String Cell
intToPlayer 1 = Right Black
intToPlayer 2 = Right White
intToPlayer x = Left ("Гравець має бути 1 або 2, отримано: " ++ show x)

-- ==============================================================
-- Побудова та перетворення дошки
-- ==============================================================

boardSize :: Board -> Int
boardSize b =
  let ((_, _), (maxRow, _)) = bounds b
  in maxRow + 1

boardFromList :: Int -> [Int] -> Either String Board
boardFromList size xs
  | size <= 0 = Left "Розмір дошки має бути додатним"
  | length xs /= size * size = Left "Довжина списку не відповідає Size*Size"
  | otherwise = do
      cells <- mapM intToCell xs
      let positions = [ (r, c) | r <- [0 .. size - 1], c <- [0 .. size - 1] ]
      pure $ array ((0, 0), (size - 1, size - 1)) (zip positions cells)

boardFromFlatAuto :: [Int] -> Either String Board
boardFromFlatAuto xs =
  let total = length xs
      size  = floor (sqrt (fromIntegral total :: Double))
  in if size * size /= total
       then Left "Неможливо вивести квадратний розмір дошки зі списку"
       else boardFromList size xs

flattenBoard :: Board -> [Int]
flattenBoard = map cellToInt . elems

initialBoard :: Int -> Board
initialBoard size =
  let positions = [ (r, c) | r <- [0 .. size - 1], c <- [0 .. size - 1] ]
      emptyBoard = array ((0, 0), (size - 1, size - 1)) [ (p, Empty) | p <- positions ]
      half = size `div` 2
      r1 = half - 1
      c1 = half - 1
      r2 = half - 1
      c2 = half
      r3 = half
      c3 = half - 1
      r4 = half
      c4 = half
  in emptyBoard //
       [ ((r1, c1), White)
       , ((r2, c2), Black)
       , ((r3, c3), Black)
       , ((r4, c4), White)
       ]

inBounds :: Board -> Pos -> Bool
inBounds board (row, col) =
  let size = boardSize board
  in row >= 0 && row < size && col >= 0 && col < size

getCell :: Board -> Pos -> Cell
getCell board pos = board ! pos

setCell :: Board -> Pos -> Cell -> Board
setCell board pos value = board // [(pos, value)]

countPieces :: Board -> Cell -> Int
countPieces board player = length (filter (== player) (elems board))

-- ==============================================================
-- Логіка гри: ходи та перевертання
-- ==============================================================

opponent :: Cell -> Cell
opponent Black = White
opponent White = Black
opponent Empty = Empty

directions :: [Pos]
directions =
  [ (-1, -1), (-1, 0), (-1, 1)
  , ( 0, -1),           ( 0, 1)
  , ( 1, -1), ( 1, 0),  ( 1, 1)
  ]

addPos :: Pos -> Pos -> Pos
addPos (r, c) (dr, dc) = (r + dr, c + dc)

scanLine :: Board -> Pos -> Pos -> Cell -> Cell -> [Pos] -> [Pos]
scanLine board current dir player opp acc =
  let next = addPos current dir
  in if not (inBounds board next)
       then []
       else case getCell board next of
              cell | cell == player -> acc
              cell | cell == opp    -> scanLine board next dir player opp (next : acc)
              _                     -> []

flipsInDirection :: Board -> Pos -> Pos -> Cell -> [Pos]
flipsInDirection board start dir player =
  let opp   = opponent player
      first = addPos start dir
  in if inBounds board first && getCell board first == opp
       then scanLine board first dir player opp [first]
       else []

allFlips :: Board -> Pos -> Cell -> [Pos]
allFlips board pos player =
  concat
    [ flips
    | dir <- directions
    , let flips = flipsInDirection board pos dir player
    , not (null flips)
    ]

validMove :: Board -> Cell -> Pos -> Bool
validMove board player pos =
  inBounds board pos
    && getCell board pos == Empty
    && not (null (allFlips board pos player))

validMoves :: Board -> Cell -> [Pos]
validMoves board player =
  [ pos
  | pos <- indices board
  , validMove board player pos
  ]

flipCells :: Board -> [Pos] -> Cell -> Board
flipCells board flips player = foldl' (\b p -> setCell b p player) board flips

makeMoveUnsafe :: Board -> Pos -> Cell -> Board
makeMoveUnsafe board pos player =
  let flips = allFlips board pos player
      withPlaced = setCell board pos player
  in flipCells withPlaced flips player

makeMove :: Board -> Pos -> Cell -> Maybe Board
makeMove board pos player
  | validMove board player pos = Just (makeMoveUnsafe board pos player)
  | otherwise = Nothing

gameOver :: Board -> Bool
gameOver board = null (validMoves board Black) && null (validMoves board White)

winner :: Board -> Winner
winner board =
  let black = countPieces board Black
      white = countPieces board White
  in case compare black white of
       GT -> WinnerBlack
       LT -> WinnerWhite
       EQ -> Draw

-- ==============================================================
-- Евристика: fixed-perspective, завжди з точки зору чорних
-- ==============================================================

isCorner :: Int -> Pos -> Bool
isCorner size (r, c) =
  let maxIx = size - 1
  in (r == 0 || r == maxIx) && (c == 0 || c == maxIx)

isEdgeCornerAdj :: Int -> Pos -> Bool
isEdgeCornerAdj size (r, c) =
  let maxIx = size - 1
  in    (r == 0     && (c == 1 || c == maxIx - 1))
     || (r == maxIx && (c == 1 || c == maxIx - 1))
     || (c == 0     && (r == 1 || r == maxIx - 1))
     || (c == maxIx && (r == 1 || r == maxIx - 1))

isDiagCornerAdj :: Int -> Pos -> Bool
isDiagCornerAdj size (r, c) =
  let maxIx = size - 1
  in (r == 1 || r == maxIx - 1) && (c == 1 || c == maxIx - 1)

isEdge :: Int -> Pos -> Bool
isEdge size (r, c) =
  let maxIx = size - 1
  in r == 0 || r == maxIx || c == 0 || c == maxIx

cellWeight :: Int -> Pos -> Int
cellWeight size pos@(r, c)
  | isCorner size pos        = 100
  | isEdgeCornerAdj size pos = -20
  | isDiagCornerAdj size pos = -50
  | isEdge size pos          = 10
  | otherwise =
      let maxIx = size - 1
          distR = min r (maxIx - r)
          distC = min c (maxIx - c)
          d = min distR distC
      in d - 2

sortMoves :: Board -> [Pos] -> [Pos]
sortMoves board = sortBy (flip compare `on` moveWeight)
  where
    moveWeight = cellWeight (boardSize board)

evaluatePositional :: Board -> Int
evaluatePositional board =
  let size = boardSize board
  in sum
       [ case cell of
           Black -> w
           White -> -w
           Empty -> 0
       | (pos, cell) <- assocs board
       , let w = cellWeight size pos
       ]

evaluate :: Board -> Int
evaluate board =
  let size = boardSize board
      posScore = evaluatePositional board
      black = countPieces board Black
      white = countPieces board White
      blackMoves = length (validMoves board Black)
      whiteMoves = length (validMoves board White)
      mobilityScore = (blackMoves - whiteMoves) * 10
      total = black + white
      threshold = (size * size * 3) `div` 4
  in if total >= threshold
       then (black - white) * 10
       else posScore + mobilityScore

terminalScore :: Board -> Int
terminalScore board =
  case winner board of
    WinnerBlack -> 10000
    WinnerWhite -> -10000
    Draw        -> 0

-- ==============================================================
-- Minimax + Alpha-Beta
-- Оцінка завжди з точки зору чорних.
-- Чорні = MAX, білі = MIN.
-- ==============================================================

infinity :: Int
infinity = 1000000

minimax :: Board -> Cell -> Int -> Int -> Int -> SearchResult
minimax board player depth alpha beta
  | depth == 0 = SearchResult Nothing (evaluate board)
  | null moves =
      let oppMoves = validMoves board opp
      in if null oppMoves
           then SearchResult Nothing (terminalScore board)
           else let child = minimax board opp depth alpha beta
                in SearchResult Nothing (srScore child)
  | player == Black = maxSearch sortedMoves alpha (Nothing, -infinity)
  | player == White = minSearch sortedMoves beta  (Nothing,  infinity)
  | otherwise = SearchResult Nothing (evaluate board)
  where
    opp = opponent player
    moves = validMoves board player
    sortedMoves = sortMoves board moves

    maxSearch :: [Pos] -> Int -> (Maybe Pos, Int) -> SearchResult
    maxSearch [] _ (bestMove, bestScore) = SearchResult bestMove bestScore
    maxSearch (mv : rest) currentAlpha (bestMove, bestScore) =
      let childBoard = makeMoveUnsafe board mv Black
          childRes = minimax childBoard White (depth - 1) currentAlpha beta
          childScore = srScore childRes
          (bestMove', bestScore') =
            if childScore > bestScore
              then (Just mv, childScore)
              else (bestMove, bestScore)
          alpha' = max currentAlpha bestScore'
      in if alpha' >= beta
           then SearchResult bestMove' bestScore'
           else maxSearch rest alpha' (bestMove', bestScore')

    minSearch :: [Pos] -> Int -> (Maybe Pos, Int) -> SearchResult
    minSearch [] _ (bestMove, bestScore) = SearchResult bestMove bestScore
    minSearch (mv : rest) currentBeta (bestMove, bestScore) =
      let childBoard = makeMoveUnsafe board mv White
          childRes = minimax childBoard Black (depth - 1) alpha currentBeta
          childScore = srScore childRes
          (bestMove', bestScore') =
            if childScore < bestScore
              then (Just mv, childScore)
              else (bestMove, bestScore)
          beta' = min currentBeta bestScore'
      in if alpha >= beta'
           then SearchResult bestMove' bestScore'
           else minSearch rest beta' (bestMove', bestScore')

chooseBestMove :: Board -> Cell -> Int -> Maybe Pos
chooseBestMove board player depth =
  srMove (minimax board player depth (-infinity) infinity)

-- ==============================================================
-- Визначення наступного стану після виконаного ходу
-- ==============================================================

nextState :: Board -> Cell -> NextState
nextState board justMoved =
  let opp = opponent justMoved
      oppMoves = validMoves board opp
  in if not (null oppMoves)
       then NextState
              { nsNextPlayer = Just opp
              , nsGameOver = False
              , nsWinner = Nothing
              , nsValidMoves = oppMoves
              }
       else
         let myMoves = validMoves board justMoved
         in if not (null myMoves)
              then NextState
                     { nsNextPlayer = Just justMoved
                     , nsGameOver = False
                     , nsWinner = Nothing
                     , nsValidMoves = myMoves
                     }
              else NextState
                     { nsNextPlayer = Nothing
                     , nsGameOver = True
                     , nsWinner = Just (winner board)
                     , nsValidMoves = []
                     }

-- ==============================================================
-- Допоміжне текстове відображення для CLI / відладки
-- ==============================================================

prettyBoard :: Board -> String
prettyBoard board =
  let size = boardSize board
      renderCell pos = case getCell board pos of
        Empty -> '.'
        Black -> 'B'
        White -> 'W'
      renderRow r = [ renderCell (r, c) | c <- [0 .. size - 1] ]
      rows = [ renderRow r | r <- [0 .. size - 1] ]
  in unlines rows