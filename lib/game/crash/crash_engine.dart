import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Crash rules (the "Aviator" style):
/// - each round has a short betting window, then a multiplier grows from
///   1.00× until the round "flies away" at a random crash point;
/// - a bet cashed out before the crash pays bet × multiplier; otherwise it's
///   lost. Optional auto cash-out at a target multiplier.
abstract final class CrashRules {
  /// Growth rate: 2× after ~5.8 s, 10× after ~19 s.
  static const growth = 0.12;
  static const bettingSeconds = 6.0;
  static const afterCrashSeconds = 3.0;
  static const maxCrash = 1000.0;

  static double multiplierAt(double seconds) => math.exp(growth * math.max(0, seconds));
  static double secondsFor(double multiplier) => math.log(multiplier) / growth;

  /// Fair crash point from a uniform draw u ∈ [0, 1): 99% RTP (1% edge),
  /// P(crash ≥ x) = 0.99 / x. Rounded down to 2 decimals.
  static double crashPointFrom(double u) {
    final raw = 0.99 / (1 - u);
    final x = raw < 1 ? 1.0 : math.min(raw, maxCrash);
    return (x * 100).floorToDouble() / 100;
  }
}

enum CrashPhase { betting, flying, crashed }

/// One of the player's two bet slots.
class CrashBet {
  int amount = 50;

  /// Auto cash-out target (null = off).
  double? autoCashOut;

  /// Staked in the current round.
  bool active = false;

  /// Waiting for the next round (pressed Bet during a flight).
  bool queued = false;

  /// Multiplier cashed out at this round (null = not yet).
  double? cashedAt;

  int get win => cashedAt == null ? 0 : (amount * cashedAt!).floor();
}

/// A computer player's bet this round.
@immutable
class CrashBotBet {
  const CrashBotBet(this.name, this.amount, this.target);
  final String name;
  final int amount;

  /// The multiplier this player cashes out at.
  final double target;
}

/// The running game: phases, the multiplier, both bets, the practice
/// balance and the other players. Drive it with [tick] (each frame).
class CrashGame extends ChangeNotifier {
  CrashGame({math.Random? rng, int? balance}) : _rng = rng ?? math.Random(), balance = balance ?? savedBalance {
    _startBetting(DateTime.now());
  }

  /// Practice balance kept for this app run (not real currency).
  static int savedBalance = 1000;
  static const startingBalance = 1000;

  static const _botNames = [
    'Nova',
    'Rex',
    'Mia',
    'Kai',
    'Zoe',
    'Leo',
    'Ivy',
    'Max',
    'Ana',
    'Sam',
    'Raj',
    'Lin',
    'Omar',
    'Eva',
    'Dev',
  ];

  final math.Random _rng;
  int balance;
  CrashPhase phase = CrashPhase.betting;
  DateTime _phaseStart = DateTime.now();
  double crashPoint = 1;
  double multiplier = 1;

  /// Seconds into the current phase.
  double elapsed = 0;

  /// Recent crash points, newest first.
  final List<double> history = [];
  final List<CrashBet> bets = [CrashBet(), CrashBet()..amount = 100];
  List<CrashBotBet> bots = const [];
  int round = 0;

  /// Seconds left to bet.
  double get bettingLeft => math.max(0, CrashRules.bettingSeconds - elapsed);

  void _setBalance(int v) {
    balance = v;
    savedBalance = v;
  }

  void _startBetting(DateTime now) {
    phase = CrashPhase.betting;
    _phaseStart = now;
    elapsed = 0;
    multiplier = 1;
    round++;
    for (final b in bets) {
      b.cashedAt = null;
      b.active = false;
      if (b.queued && b.amount <= balance) {
        _setBalance(balance - b.amount);
        b.active = true;
      }
      b.queued = false;
    }
    // Other players join this round.
    final n = 6 + _rng.nextInt(7);
    final names = List.of(_botNames)..shuffle(_rng);
    bots = [
      for (var i = 0; i < n; i++)
        CrashBotBet(
          names[i],
          [10, 20, 50, 100, 200, 500][_rng.nextInt(6)],
          // Most players leave early; a few hold for big multipliers.
          (100 * (1.1 + -math.log(1 - _rng.nextDouble()) * 1.4 * (_rng.nextDouble() < 0.15 ? 4 : 1))).floor() / 100,
        ),
    ];
  }

  void _startFlight(DateTime now) {
    phase = CrashPhase.flying;
    _phaseStart = now;
    elapsed = 0;
    crashPoint = CrashRules.crashPointFrom(_rng.nextDouble());
    multiplier = 1;
  }

  /// Advance to [now]: run the flight, auto cash-outs, the crash, and the
  /// next round.
  void tick(DateTime now) {
    elapsed = now.difference(_phaseStart).inMicroseconds / 1e6;
    switch (phase) {
      case CrashPhase.betting:
        if (elapsed >= CrashRules.bettingSeconds) _startFlight(now);
      case CrashPhase.flying:
        final m = CrashRules.multiplierAt(elapsed);
        if (m >= crashPoint) {
          multiplier = crashPoint;
          _crash(now);
        } else {
          multiplier = (m * 100).floorToDouble() / 100;
          for (final b in bets) {
            final auto = b.autoCashOut;
            if (b.active && b.cashedAt == null && auto != null && multiplier >= auto) _cashOut(b, auto);
          }
        }
      case CrashPhase.crashed:
        if (elapsed >= CrashRules.afterCrashSeconds) _startBetting(now);
    }
    notifyListeners();
  }

  void _crash(DateTime now) {
    phase = CrashPhase.crashed;
    _phaseStart = now;
    elapsed = 0;
    history.insert(0, crashPoint);
    if (history.length > 30) history.removeLast();
  }

  void _cashOut(CrashBet b, double at) {
    b.cashedAt = at;
    _setBalance(balance + b.win);
  }

  /// Bet / cancel for slot [i]: during betting it stakes now; during a
  /// flight (or after the crash) it queues for the next round.
  void toggleBet(int i) {
    final b = bets[i];
    if (phase == CrashPhase.betting) {
      if (b.active) {
        b.active = false;
        _setBalance(balance + b.amount);
      } else if (b.amount <= balance) {
        b.active = true;
        _setBalance(balance - b.amount);
      }
    } else {
      b.queued = !b.queued && b.amount <= balance;
    }
    notifyListeners();
  }

  /// Cash out slot [i] at the current multiplier.
  void cashOut(int i) {
    final b = bets[i];
    if (phase != CrashPhase.flying || !b.active || b.cashedAt != null) return;
    _cashOut(b, multiplier);
    notifyListeners();
  }

  void setAmount(int i, int amount) {
    final b = bets[i];
    if (b.active || b.queued) return;
    b.amount = amount.clamp(10, 10000);
    notifyListeners();
  }

  void setAuto(int i, double? target) {
    bets[i].autoCashOut = target == null ? null : (target.clamp(1.01, 100.0) * 100).roundToDouble() / 100;
    notifyListeners();
  }

  /// Top up the practice balance when it runs out.
  void refill() {
    _setBalance(startingBalance);
    notifyListeners();
  }
}
