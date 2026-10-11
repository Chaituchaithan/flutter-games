import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Board size and square kinds.
const int kSize = 15;
const int kCenter = 7 * kSize + 7;

enum Premium { none, dl, tl, dw, tw }

/// The standard premium-square layout (symmetric).
final List<Premium> premiums = _buildPremiums();

List<Premium> _buildPremiums() {
  final p = List.filled(kSize * kSize, Premium.none);
  void set(List<(int, int)> cells, Premium k) {
    for (final (r, c) in cells) {
      for (final (rr, cc) in {
        (r, c),
        (c, r),
        (14 - r, c),
        (r, 14 - c),
        (14 - r, 14 - c),
        (14 - c, r),
        (c, 14 - r),
        (14 - c, 14 - r),
      }) {
        p[rr * kSize + cc] = k;
      }
    }
  }

  set([(0, 0), (0, 7)], Premium.tw);
  set([(1, 1), (2, 2), (3, 3), (4, 4), (7, 7)], Premium.dw);
  set([(1, 5), (5, 5)], Premium.tl);
  set([(0, 3), (2, 6), (3, 7), (6, 6)], Premium.dl);
  return p;
}

/// Letter scores; '?' is a blank (0).
const Map<String, int> letterValues = {
  'A': 1,
  'B': 3,
  'C': 3,
  'D': 2,
  'E': 1,
  'F': 4,
  'G': 2,
  'H': 4,
  'I': 1,
  'J': 8,
  'K': 5,
  'L': 1,
  'M': 3,
  'N': 1,
  'O': 1,
  'P': 3,
  'Q': 10,
  'R': 1,
  'S': 1,
  'T': 1,
  'U': 1,
  'V': 4,
  'W': 4,
  'X': 8,
  'Y': 4,
  'Z': 10,
  '?': 0,
};

/// The 100-tile English bag.
const Map<String, int> _distribution = {
  'A': 9,
  'B': 2,
  'C': 2,
  'D': 4,
  'E': 12,
  'F': 2,
  'G': 3,
  'H': 2,
  'I': 9,
  'J': 1,
  'K': 1,
  'L': 4,
  'M': 2,
  'N': 6,
  'O': 8,
  'P': 2,
  'Q': 1,
  'R': 6,
  'S': 4,
  'T': 6,
  'U': 4,
  'V': 2,
  'W': 2,
  'X': 1,
  'Y': 2,
  'Z': 1,
  '?': 2,
};

/// A tile: its face ('A'–'Z' or '?') and, for a placed blank, the letter it
/// stands for.
@immutable
class Tile {
  const Tile(this.face, {this.as});
  final String face;
  final String? as;

  bool get blank => face == '?';
  String get letter => blank ? (as ?? '?') : face;
  int get value => letterValues[face] ?? 0;

  Tile withLetter(String l) => Tile(face, as: l);
  Tile get cleared => Tile(face);
}

/// The word list: a hash set for lookups plus the sorted list for prefix
/// checks (binary search) during move generation.
class Lexicon {
  Lexicon(List<String> sortedWords) : _sorted = sortedWords, _set = sortedWords.toSet();
  factory Lexicon.fromText(String text) => Lexicon(
    [
      for (final w in text.split('\n'))
        if (w.length >= 2) w.trim(),
    ]..sort(),
  );

  final List<String> _sorted;
  final Set<String> _set;

  List<String> get words => _sorted;
  bool contains(String w) => _set.contains(w);

  /// Some word starts with [p].
  bool isPrefix(String p) {
    var lo = 0, hi = _sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sorted[mid].compareTo(p) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < _sorted.length && _sorted[lo].startsWith(p);
  }
}

/// A scored play: new tiles by square, the words formed and the score.
@immutable
class ScrabblePlay {
  const ScrabblePlay({required this.tiles, required this.words, required this.score});
  final Map<int, Tile> tiles;
  final List<String> words;
  final int score;

  /// The main word (longest).
  String get mainWord => words.isEmpty ? '' : words.reduce((a, b) => a.length >= b.length ? a : b);
}

/// Why a tentative play isn't valid.
enum PlayError { empty, notInLine, gap, notConnected, firstMoveCenter, tooShort, notAWord }

/// Validate + score [placed] (square → tile, blanks already lettered) on
/// [board]. Returns (play, null) or (null, error, badWord).
(ScrabblePlay?, PlayError?, String?) evaluatePlay(List<Tile?> board, Map<int, Tile> placed, Lexicon lex) {
  if (placed.isEmpty) return (null, PlayError.empty, null);
  final squares = placed.keys.toList()..sort();
  final rows = squares.map((s) => s ~/ kSize).toSet();
  final cols = squares.map((s) => s % kSize).toSet();
  if (rows.length > 1 && cols.length > 1) return (null, PlayError.notInLine, null);
  final firstMove = board.every((t) => t == null);
  Tile? at(int sq) => placed[sq] ?? board[sq];

  // Direction of the main word: along the line of the tiles (a single tile
  // picks the direction that forms a longer word).
  bool horizontal;
  if (squares.length > 1) {
    horizontal = rows.length == 1;
  } else {
    final s = squares.first;
    final r = s ~/ kSize, c = s % kSize;
    final h = (c > 0 && board[s - 1] != null) || (c < 14 && board[s + 1] != null);
    final v = (r > 0 && board[s - kSize] != null) || (r < 14 && board[s + kSize] != null);
    horizontal = h || !v;
  }
  final step = horizontal ? 1 : kSize;

  // No gaps between the first and last new tile.
  for (var s = squares.first; s <= squares.last; s += step) {
    if (at(s) == null) return (null, PlayError.gap, null);
  }

  if (firstMove) {
    if (!placed.containsKey(kCenter)) return (null, PlayError.firstMoveCenter, null);
    if (placed.length < 2) return (null, PlayError.tooShort, null);
  } else {
    final touches = squares.any((s) => _neighbours(s).any((n) => board[n] != null));
    if (!touches) return (null, PlayError.notConnected, null);
  }

  final words = <(String, int)>[];
  int wordScore(int start, int dir) {
    var sum = 0, mult = 1;
    var s = start;
    while (s >= 0 && s < kSize * kSize && at(s) != null) {
      final t = at(s)!;
      var v = t.blank ? 0 : t.value;
      if (placed.containsKey(s)) {
        switch (premiums[s]) {
          case Premium.dl:
            v *= 2;
          case Premium.tl:
            v *= 3;
          case Premium.dw:
            mult *= 2;
          case Premium.tw:
            mult *= 3;
          case Premium.none:
        }
      }
      sum += v;
      if (dir == 1 && s % kSize == 14) break;
      s += dir;
    }
    return sum * mult;
  }

  String wordAt(int start, int dir) {
    final b = StringBuffer();
    var s = start;
    while (s >= 0 && s < kSize * kSize && at(s) != null) {
      b.write(at(s)!.letter);
      if (dir == 1 && s % kSize == 14) break;
      s += dir;
    }
    return b.toString();
  }

  int startOf(int s, int dir) {
    while (true) {
      final prev = s - dir;
      if (prev < 0 || (dir == 1 && s % kSize == 0) || at(prev) == null) return s;
      s = prev;
    }
  }

  // Main word.
  final mainStart = startOf(squares.first, step);
  final main = wordAt(mainStart, step);
  if (main.length >= 2) words.add((main, wordScore(mainStart, step)));
  // Cross words through each new tile.
  final cross = horizontal ? kSize : 1;
  for (final s in squares) {
    final st = startOf(s, cross);
    final w = wordAt(st, cross);
    if (w.length >= 2) words.add((w, wordScore(st, cross)));
  }
  if (words.isEmpty) return (null, PlayError.tooShort, null);
  for (final (w, _) in words) {
    if (!lex.contains(w)) return (null, PlayError.notAWord, w);
  }
  var score = words.fold<int>(0, (a, w) => a + w.$2);
  if (placed.length == 7) score += 50; // bingo
  return (ScrabblePlay(tiles: Map.of(placed), words: [for (final (w, _) in words) w], score: score), null, null);
}

Iterable<int> _neighbours(int s) sync* {
  final r = s ~/ kSize, c = s % kSize;
  if (r > 0) yield s - kSize;
  if (r < 14) yield s + kSize;
  if (c > 0) yield s - 1;
  if (c < 14) yield s + 1;
}

/// Every valid play for [rack] on [board] (the computer's move search).
List<ScrabblePlay> generatePlays(List<Tile?> board, List<Tile> rack, Lexicon lex) {
  final found = <String, ScrabblePlay>{};
  final empty = board.every((t) => t == null);
  for (final horizontal in [true, false]) {
    final step = horizontal ? 1 : kSize;
    int sq(int line, int i) => horizontal ? line * kSize + i : i * kSize + line;
    for (var line = 0; line < kSize; line++) {
      // Anchors on this line: empty squares next to a tile (or the centre).
      final anchors = <int>[
        for (var i = 0; i < kSize; i++)
          if (board[sq(line, i)] == null &&
              (empty ? sq(line, i) == kCenter : _neighbours(sq(line, i)).any((n) => board[n] != null)))
            i,
      ];
      for (final a in anchors) {
        // Possible start positions: a run of existing tiles to the left is
        // a fixed prefix; otherwise up to 7 empty non-anchor squares.
        final starts = <int>[];
        if (a > 0 && board[sq(line, a - 1)] != null) {
          var s = a - 1;
          while (s > 0 && board[sq(line, s - 1)] != null) {
            s--;
          }
          starts.add(s);
        } else {
          starts.add(a);
          for (var k = 1; k <= 7 && a - k >= 0; k++) {
            final p = a - k;
            if (board[sq(line, p)] != null || anchors.contains(p)) break;
            if (p > 0 && board[sq(line, p - 1)] != null) break;
            starts.add(p);
          }
        }
        for (final start in starts) {
          _extend(board, rack, lex, line, start, a, sq, step, '', <int, Tile>{}, found);
        }
      }
    }
  }
  final out = found.values.toList()..sort((x, y) => y.score.compareTo(x.score));
  return out;
}

void _extend(
  List<Tile?> board,
  List<Tile> rack,
  Lexicon lex,
  int line,
  int i,
  int anchor,
  int Function(int, int) sq,
  int step,
  String word,
  Map<int, Tile> placed,
  Map<String, ScrabblePlay> found,
) {
  // Record when the word passed the anchor, ends here and used a tile.
  if (i > anchor && placed.isNotEmpty && word.length >= 2 && (i >= kSize || board[sq(line, i)] == null)) {
    if (lex.contains(word)) {
      final (play, _, _) = evaluatePlay(board, placed, lex);
      if (play != null) {
        final key = (play.tiles.keys.toList()..sort()).map((k) => '$k${play.tiles[k]!.letter}').join();
        found.putIfAbsent(key, () => play);
      }
    }
  }
  if (i >= kSize) return;
  final s = sq(line, i);
  final here = board[s];
  if (here != null) {
    final w = word + here.letter;
    if (lex.isPrefix(w)) _extend(board, rack, lex, line, i + 1, anchor, sq, step, w, placed, found);
    return;
  }
  final tried = <String>{};
  for (var k = 0; k < rack.length; k++) {
    final t = rack[k];
    final letters = t.blank ? List.generate(26, (j) => String.fromCharCode(65 + j)) : [t.face];
    final rest = [...rack]..removeAt(k);
    for (final l in letters) {
      final key = '${t.face}$l';
      if (!tried.add(key)) continue;
      final w = word + l;
      if (!lex.isPrefix(w)) continue;
      // Cross-check: the perpendicular word through this square must be valid.
      if (!_crossOk(board, s, l, step, lex)) continue;
      final tile = t.blank ? t.withLetter(l) : t;
      _extend(board, rest, lex, line, i + 1, anchor, sq, step, w, {...placed, s: tile}, found);
    }
  }
}

bool _crossOk(List<Tile?> board, int s, String letter, int step, Lexicon lex) {
  final cross = step == 1 ? kSize : 1;
  bool inBounds(int x) => x >= 0 && x < kSize * kSize && (cross != 1 || x ~/ kSize == s ~/ kSize);
  var before = '', after = '';
  var p = s - cross;
  while (inBounds(p) && board[p] != null) {
    before = board[p]!.letter + before;
    p -= cross;
  }
  p = s + cross;
  while (inBounds(p) && board[p] != null) {
    after += board[p]!.letter;
    p += cross;
  }
  if (before.isEmpty && after.isEmpty) return true;
  return lex.contains('$before$letter$after');
}

/// One turn's outcome, for the move log.
enum ScrabbleTurnKind { play, exchange, pass }

@immutable
class ScrabbleTurn {
  const ScrabbleTurn(this.player, this.kind, {this.play, this.count = 0});
  final int player;
  final ScrabbleTurnKind kind;
  final ScrabblePlay? play;

  /// Tiles exchanged.
  final int count;
  int get score => play?.score ?? 0;
}

/// A 2-player game: the bag, both racks, the board, scores and turn flow
/// (player 0 = you). Ends when the bag is empty and a player empties their
/// rack, or after 6 scoreless turns in a row; leftover tiles are deducted
/// (and added to the player who went out).
class ScrabbleGame extends ChangeNotifier {
  ScrabbleGame({math.Random? rng}) : _rng = rng ?? math.Random() {
    for (final e in _distribution.entries) {
      for (var i = 0; i < e.value; i++) {
        bag.add(Tile(e.key));
      }
    }
    bag.shuffle(_rng);
    for (final r in racks) {
      _refill(r);
    }
  }

  final math.Random _rng;
  final List<Tile?> board = List.filled(kSize * kSize, null);
  final List<Tile> bag = [];
  final List<List<Tile>> racks = [[], []];
  final List<int> scores = [0, 0];
  int turn = 0;
  int _scoreless = 0;
  final List<ScrabbleTurn> log = [];
  bool over = false;

  /// Who went out (emptied their rack at the end), if anyone.
  int? wentOut;

  ScrabbleTurn? get lastTurn => log.isEmpty ? null : log.last;

  void _refill(List<Tile> rack) {
    while (rack.length < 7 && bag.isNotEmpty) {
      rack.add(bag.removeLast());
    }
  }

  /// Commit a validated play for the player to move.
  void play(ScrabblePlay p) {
    final rack = racks[turn];
    for (final e in p.tiles.entries) {
      board[e.key] = e.value;
      final i = rack.indexWhere((t) => t.face == e.value.face);
      if (i >= 0) rack.removeAt(i);
    }
    scores[turn] += p.score;
    _refill(rack);
    log.add(ScrabbleTurn(turn, ScrabbleTurnKind.play, play: p));
    _scoreless = p.score > 0 ? 0 : _scoreless + 1;
    _next(emptiedRack: rack.isEmpty);
  }

  /// Swap [tiles] from the rack with the bag (needs 7 in the bag).
  bool get canExchange => bag.length >= 7;
  void exchange(List<Tile> tiles) {
    final rack = racks[turn];
    for (final t in tiles) {
      final i = rack.indexWhere((x) => x.face == t.face);
      if (i >= 0) rack.removeAt(i);
    }
    _refill(rack);
    bag.addAll(tiles.map((t) => t.cleared));
    bag.shuffle(_rng);
    log.add(ScrabbleTurn(turn, ScrabbleTurnKind.exchange, count: tiles.length));
    _scoreless++;
    _next();
  }

  void pass() {
    log.add(ScrabbleTurn(turn, ScrabbleTurnKind.pass));
    _scoreless++;
    _next();
  }

  void _next({bool emptiedRack = false}) {
    if (emptiedRack && bag.isEmpty) {
      wentOut = turn;
      _finish();
    } else if (_scoreless >= 6) {
      _finish();
    } else {
      turn = 1 - turn;
    }
    notifyListeners();
  }

  void _finish() {
    over = true;
    final left = [for (final r in racks) r.fold<int>(0, (a, t) => a + t.value)];
    for (var p = 0; p < 2; p++) {
      scores[p] -= left[p];
    }
    final out = wentOut;
    if (out != null) scores[out] += left[1 - out];
  }

  /// Winner (null = tie) once over.
  int? get winner => !over || scores[0] == scores[1] ? null : (scores[0] > scores[1] ? 0 : 1);
}

/// Computer move for [compute]: plays by difficulty — hard = best,
/// medium = a strong pick, easy = a modest pick; exchanges or passes when it
/// has nothing.
ScrabblePlay? chooseScrabblePlay(List<Tile?> board, List<Tile> rack, Lexicon lex, int difficulty, int seed) {
  final plays = generatePlays(board, rack, lex);
  if (plays.isEmpty) return null;
  final rng = math.Random(seed);
  final n = plays.length;
  final idx = switch (difficulty) {
    >= 3 => 0,
    2 => rng.nextInt(math.max(1, (n * 0.15).ceil())),
    _ => (n * 0.35).floor() + rng.nextInt(math.max(1, (n * 0.4).floor())),
  };
  return plays[idx.clamp(0, n - 1)];
}
