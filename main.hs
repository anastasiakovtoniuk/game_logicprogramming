{-# LANGUAGE OverloadedStrings #-}

module Main where

import Reversi
import Web.Scotty
import Network.Wai.Middleware.Static (staticPolicy, addBase)
import qualified Data.Aeson as A
import Data.Aeson ((.=), object)
import Network.HTTP.Types.Status (badRequest400)
import System.IO (hSetEncoding, stdout, stderr)
import GHC.IO.Encoding (utf8)

-- =========================
-- JSON request payloads
-- =========================

data NewGameReq = NewGameReq
  { ngrSize :: Int
  }

instance A.FromJSON NewGameReq where
  parseJSON = A.withObject "NewGameReq" $ \o ->
    NewGameReq <$> o A..: "size"

data MakeMoveReq = MakeMoveReq
  { mmrBoard  :: [Int]
  , mmrPlayer :: Int
  , mmrRow    :: Int
  , mmrCol    :: Int
  }

instance A.FromJSON MakeMoveReq where
  parseJSON = A.withObject "MakeMoveReq" $ \o ->
    MakeMoveReq
      <$> o A..: "board"
      <*> o A..: "player"
      <*> o A..: "row"
      <*> o A..: "col"

data AiMoveReq = AiMoveReq
  { amrBoard  :: [Int]
  , amrPlayer :: Int
  , amrDepth  :: Int
  }

instance A.FromJSON AiMoveReq where
  parseJSON = A.withObject "AiMoveReq" $ \o ->
    AiMoveReq
      <$> o A..: "board"
      <*> o A..: "player"
      <*> o A..: "depth"

-- =========================
-- Helpers
-- =========================

decodeBodyAs :: A.FromJSON a => ActionM (Either String a)
decodeBodyAs = do
  raw <- body
  pure (A.eitherDecode raw)

badRequestJson :: String -> ActionM ()
badRequestJson msg = do
  status badRequest400
  json $ object
    [ "error"   .= (1 :: Int)
    , "message" .= msg
    ]

playerToInt :: Cell -> Int
playerToInt Black = 1
playerToInt White = 2
playerToInt Empty = 0

winnerToInt :: Winner -> Int
winnerToInt WinnerBlack = 1
winnerToInt WinnerWhite = 2
winnerToInt Draw        = 0

boolToInt :: Bool -> Int
boolToInt True  = 1
boolToInt False = 0

moveObj :: Pos -> A.Value
moveObj (r, c) = object
  [ "row" .= r
  , "col" .= c
  ]

nextPlayerInt :: Maybe Cell -> Int
nextPlayerInt Nothing  = 0
nextPlayerInt (Just p) = playerToInt p

nextWinnerInt :: Maybe Winner -> Int
nextWinnerInt Nothing  = -1
nextWinnerInt (Just w) = winnerToInt w

respondStateAfterMove :: Board -> Cell -> Maybe Pos -> Int -> ActionM ()
respondStateAfterMove newBoard justMoved movePos passedFlag = do
  let ns = nextState newBoard justMoved
      black = countPieces newBoard Black
      white = countPieces newBoard White
      moveValue = case movePos of
        Nothing -> moveObj (-1, -1)
        Just mv -> moveObj mv

  json $ object
    [ "move"        .= moveValue
    , "board"       .= flattenBoard newBoard
    , "next_player" .= nextPlayerInt (nsNextPlayer ns)
    , "game_over"   .= boolToInt (nsGameOver ns)
    , "winner"      .= nextWinnerInt (nsWinner ns)
    , "black_count" .= black
    , "white_count" .= white
    , "valid_moves" .= map moveObj (nsValidMoves ns)
    , "passed"      .= passedFlag
    ]

-- =========================
-- Main server
-- =========================

main :: IO ()
main = do
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8

  putStrLn "=== Reversi Haskell server started ==="
  putStrLn "Open: http://localhost:8080/"

  scotty 8080 $ do
    middleware $ staticPolicy (addBase "public")

    -- Головна сторінка
    get "/" $ file "public/index.html"

    -- POST /api/new_game  { size }
    post "/api/new_game" $ do
      payload <- decodeBodyAs
      case payload of
        Left err -> badRequestJson ("Invalid JSON: " ++ err)
        Right (NewGameReq size)
          | size <= 0 || odd size || size < 4 ->
              badRequestJson "Board size must be an even number >= 4"
          | otherwise -> do
              let board = initialBoard size
                  moves = validMoves board Black
                  black = countPieces board Black
                  white = countPieces board White

              json $ object
                [ "board"          .= flattenBoard board
                , "current_player" .= (1 :: Int)
                , "black_count"    .= black
                , "white_count"    .= white
                , "valid_moves"    .= map moveObj moves
                , "game_over"      .= (0 :: Int)
                , "winner"         .= (-1 :: Int)
                ]

    -- POST /api/make_move  { board, player, row, col }
    post "/api/make_move" $ do
      payload <- decodeBodyAs
      case payload of
        Left err -> badRequestJson ("Invalid JSON: " ++ err)
        Right req ->
          case boardFromFlatAuto (mmrBoard req) of
            Left err -> badRequestJson err
            Right board ->
              case intToPlayer (mmrPlayer req) of
                Left err -> badRequestJson err
                Right player ->
                  case makeMove board (mmrRow req, mmrCol req) player of
                    Nothing ->
                      json $ object
                        [ "error"   .= (1 :: Int)
                        , "message" .= ("Invalid move" :: String)
                        ]
                    Just newBoard -> do
                      let ns = nextState newBoard player
                          black = countPieces newBoard Black
                          white = countPieces newBoard White

                      json $ object
                        [ "board"       .= flattenBoard newBoard
                        , "next_player" .= nextPlayerInt (nsNextPlayer ns)
                        , "game_over"   .= boolToInt (nsGameOver ns)
                        , "winner"      .= nextWinnerInt (nsWinner ns)
                        , "black_count" .= black
                        , "white_count" .= white
                        , "valid_moves" .= map moveObj (nsValidMoves ns)
                        , "last_move"   .= object
                            [ "row" .= mmrRow req
                            , "col" .= mmrCol req
                            ]
                        ]

    -- POST /api/ai_move  { board, player, depth }
    post "/api/ai_move" $ do
      payload <- decodeBodyAs
      case payload of
        Left err -> badRequestJson ("Invalid JSON: " ++ err)
        Right req ->
          case boardFromFlatAuto (amrBoard req) of
            Left err -> badRequestJson err
            Right board ->
              case intToPlayer (amrPlayer req) of
                Left err -> badRequestJson err
                Right player -> do
                  let moves = validMoves board player
                      black = countPieces board Black
                      white = countPieces board White

                  if null moves
                    then do
                      let opp = opponent player
                          oppMoves = validMoves board opp

                      if null oppMoves
                        then
                          json $ object
                            [ "move"        .= moveObj (-1, -1)
                            , "board"       .= flattenBoard board
                            , "next_player" .= (0 :: Int)
                            , "game_over"   .= (1 :: Int)
                            , "winner"      .= winnerToInt (winner board)
                            , "black_count" .= black
                            , "white_count" .= white
                            , "valid_moves" .= ([] :: [A.Value])
                            , "passed"      .= (1 :: Int)
                            ]
                        else
                          json $ object
                            [ "move"        .= moveObj (-1, -1)
                            , "board"       .= flattenBoard board
                            , "next_player" .= playerToInt opp
                            , "game_over"   .= (0 :: Int)
                            , "winner"      .= (-1 :: Int)
                            , "black_count" .= black
                            , "white_count" .= white
                            , "valid_moves" .= map moveObj oppMoves
                            , "passed"      .= (1 :: Int)
                            ]
                    else
                      case chooseBestMove board player (amrDepth req) of
                        Nothing -> do
                          -- Захисний fallback, якщо minimax раптом не поверне хід
                          let opp = opponent player
                              oppMoves = validMoves board opp

                          if null oppMoves
                            then
                              json $ object
                                [ "move"        .= moveObj (-1, -1)
                                , "board"       .= flattenBoard board
                                , "next_player" .= (0 :: Int)
                                , "game_over"   .= (1 :: Int)
                                , "winner"      .= winnerToInt (winner board)
                                , "black_count" .= black
                                , "white_count" .= white
                                , "valid_moves" .= ([] :: [A.Value])
                                , "passed"      .= (1 :: Int)
                                ]
                            else
                              json $ object
                                [ "move"        .= moveObj (-1, -1)
                                , "board"       .= flattenBoard board
                                , "next_player" .= playerToInt opp
                                , "game_over"   .= (0 :: Int)
                                , "winner"      .= (-1 :: Int)
                                , "black_count" .= black
                                , "white_count" .= white
                                , "valid_moves" .= map moveObj oppMoves
                                , "passed"      .= (1 :: Int)
                                ]
                        Just mv -> do
                          let newBoard = makeMoveUnsafe board mv player
                          respondStateAfterMove newBoard player (Just mv) 0