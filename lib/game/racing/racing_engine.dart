import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

/// One car in the field.
@immutable
class RaceCar {
  const RaceCar(this.number, this.name, this.color);
  final int number;
  final String name;
  final Color color;
}

const raceField = [
  RaceCar(1, 'Viper', Color(0xFFE11D48)),
  RaceCar(2, 'Bolt', Color(0xFFFACC15)),
  RaceCar(3, 'Phantom', Color(0xFFA855F7)),
  RaceCar(4, 'Nitro', Color(0xFF3B82F6)),
  RaceCar(5, 'Blaze', Color(0xFFF97316)),
  RaceCar(6, 'Storm', Color(0xFF14B8A6)),
];

enum RaceBetKind { win, top3 }

enum RacePhase { betting, racing, finished }

/// One car's run: where it is (0 → 1 = finish line) at a time in the race.
/// A launch, then a smooth pace with a few surges and fades; finishes at
/// [finishAt] seconds and coasts past the line.
class RaceRun {
  RaceRun(this.finishAt, math.Random rng)
    : _waves = [
        for (var k = 1; k <= 3; k++) (k, (rng.nextDouble() * 2 - 1) * 0.03 / k, rng.nextDouble() * 2 * math.pi),
      ];

  final double finishAt;
  final List<(int, double, double)> _waves;

  double at(double t) {
    if (t <= 0) return 0;
    if (t >= finishAt) return 1 + (t - finishAt) / finishAt * 0.6; // past the line
    final u = t / finishAt;
    // Launch: the first 8% is an acceleration from the grid.
    final g = u < 0.08 ? u * u / 0.16 : u - 0.04;
    final base = g / 0.96;
    // Surges and fades: small waves, faded in and out (flat at the start
    // and the line), never strong enough to roll a car backwards.
    var wave = 0.0;
    for (final (k, a, phase) in _waves) {
      wave += a * math.sin(2 * math.pi * k * u + phase);
    }
    final envelope = math.pow(4 * u * (1 - u), 2).toDouble();
    return (base + wave * envelope).clamp(0.0, 1.0);
  }
}

/// A practice race meeting: odds from each car's form, Win / Top 3 bets,
/// the race, payouts.
class RacingGame extends ChangeNotifier {
  RacingGame({math.Random? rng, int? balance}) : _rng = rng ?? math.Random(), balance = balance ?? savedBalance {
    _newRace();
  }

  /// Practice balance kept for this app run (not real currency).
  static int savedBalance = 5000;
  static const startingBalance = 5000;

  /// Bookmaker margin: odds pay 92% of the fair price.
  static const margin = 0.92;
  static const raceSeconds = 11.0;

  final math.Random _rng;
  int balance;
  RacePhase phase = RacePhase.betting;
  int raceNo = 0;

  /// Form (strength) per car this race; chance to win ∝ strength.
  late List<double> strength;
  late List<double> winOdds;
  late List<double> top3Odds;

  /// Bets this race: (car index, kind) → amount.
  final Map<(int, RaceBetKind), int> bets = {};

  /// Finishing order (car indexes), decided at the start of the race.
  List<int> order = const [];
  List<RaceRun> runs = const [];

  /// Winners of past races (car index), newest first.
  final List<int> history = [];
  int lastReturn = 0;

  int get totalBet => bets.values.fold(0, (a, b) => a + b);

  void _setBalance(int v) {
    balance = v;
    savedBalance = v;
  }

  void _newRace() {
    raceNo++;
    phase = RacePhase.betting;
    bets.clear();
    // Form: a favourite or two, some outsiders.
    strength = [for (var i = 0; i < raceField.length; i++) math.exp(_rng.nextDouble() * 1.6 - 0.3)];
    final p = winChances(strength);
    final p3 = top3Chances(strength);
    winOdds = [for (final x in p) _price(x)];
    top3Odds = [for (final x in p3) _price(x)];
  }

  /// Decimal odds (stake included) for a fair chance [p], with the margin.
  static double _price(double p) => math.max(1.05, (margin / p * 10).floorToDouble() / 10);

  /// Chance each car wins (Plackett–Luce: proportional to strength).
  static List<double> winChances(List<double> s) {
    final total = s.fold(0.0, (a, b) => a + b);
    return [for (final x in s) x / total];
  }

  /// Chance each car finishes in the top three (exact over the orders of
  /// the first three places).
  static List<double> top3Chances(List<double> s) {
    final n = s.length;
    final out = List.filled(n, 0.0);
    final total = s.fold(0.0, (a, b) => a + b);
    for (var a = 0; a < n; a++) {
      final pa = s[a] / total;
      for (var b = 0; b < n; b++) {
        if (b == a) continue;
        final pb = s[b] / (total - s[a]);
        for (var c = 0; c < n; c++) {
          if (c == a || c == b) continue;
          final pc = s[c] / (total - s[a] - s[b]);
          final pr = pa * pb * pc;
          out[a] += pr;
          out[b] += pr;
          out[c] += pr;
        }
      }
    }
    return out;
  }

  bool placeBet(int car, RaceBetKind kind, int amount) {
    if (phase != RacePhase.betting || amount > balance) return false;
    bets[(car, kind)] = (bets[(car, kind)] ?? 0) + amount;
    _setBalance(balance - amount);
    notifyListeners();
    return true;
  }

  void clearBets() {
    if (phase != RacePhase.betting) return;
    _setBalance(balance + totalBet);
    bets.clear();
    notifyListeners();
  }

  /// Draw the finishing order (by form) and script the race to match it.
  void start() {
    if (phase != RacePhase.betting) return;
    final left = [for (var i = 0; i < raceField.length; i++) i];
    final o = <int>[];
    while (left.isNotEmpty) {
      final total = left.fold(0.0, (a, i) => a + strength[i]);
      var x = _rng.nextDouble() * total;
      var pick = left.last;
      for (final i in left) {
        x -= strength[i];
        if (x <= 0) {
          pick = i;
          break;
        }
      }
      o.add(pick);
      left.remove(pick);
    }
    order = o;
    // Finish times: the winner at [raceSeconds], the rest a little behind
    // (sometimes a photo finish).
    final finish = List.filled(raceField.length, 0.0);
    var t = raceSeconds;
    for (var k = 0; k < o.length; k++) {
      finish[o[k]] = t;
      t += _rng.nextDouble() < 0.25 ? 0.03 + _rng.nextDouble() * 0.08 : 0.12 + _rng.nextDouble() * 0.55;
    }
    runs = [for (var i = 0; i < raceField.length; i++) RaceRun(finish[i], _rng)];
    phase = RacePhase.racing;
    notifyListeners();
  }

  /// Positions at time [t]: car indexes, leader first.
  List<int> standings(double t) {
    final idx = [for (var i = 0; i < raceField.length; i++) i];
    idx.sort((a, b) {
      final fa = runs[a].finishAt <= t, fb = runs[b].finishAt <= t;
      if (fa && fb) return runs[a].finishAt.compareTo(runs[b].finishAt);
      return runs[b].at(t).compareTo(runs[a].at(t));
    });
    return idx;
  }

  /// Gap between first and second at the line (seconds).
  double get winningMargin => runs[order[1]].finishAt - runs[order[0]].finishAt;

  /// Race over: pay Win bets on the winner and Top 3 bets on the podium.
  void finish() {
    if (phase != RacePhase.racing) return;
    lastReturn = 0;
    for (final e in bets.entries) {
      final (car, kind) = e.key;
      final won = kind == RaceBetKind.win ? order.first == car : order.take(3).contains(car);
      if (won) lastReturn += (e.value * (kind == RaceBetKind.win ? winOdds[car] : top3Odds[car])).floor();
    }
    _setBalance(balance + lastReturn);
    history.insert(0, order.first);
    if (history.length > 20) history.removeLast();
    phase = RacePhase.finished;
    notifyListeners();
  }

  void nextRace() {
    _newRace();
    notifyListeners();
  }

  void refill() {
    _setBalance(startingBalance);
    notifyListeners();
  }
}
