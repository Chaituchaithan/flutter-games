/// Every game the app knows about (one per backend game service). Configs,
/// routing and state are keyed by this enum — never by strings.
enum GameId {
  chess,
  snakesLadders,
  ludo,
  othello,
  scrabble,
  checkers,
  bingo,
  poker,
  rummy,
  crash,
  racing,
  roulette,
  uno,
  carrom,
}
