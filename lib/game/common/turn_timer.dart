import 'dart:async';

import 'package:flutter/foundation.dart';

/// Per-turn countdown for local games (the chess "time per move" idea, shared
/// by the dice games). [start] begins a fresh turn; when it reaches zero
/// [onExpire] fires once (the game then plays the turn for the player).
/// [limitMs] null = unlimited (never expires).
class TurnTimer extends ChangeNotifier {
  TurnTimer({required this.limitMs, this.onExpire});

  final int? limitMs;
  VoidCallback? onExpire;

  Timer? _ticker;
  DateTime? _startedAt;
  int _elapsedBeforePause = 0;
  bool _running = false;
  bool _expired = false;

  bool get unlimited => limitMs == null;
  bool get running => _running;

  int get _elapsed =>
      _elapsedBeforePause + (_running && _startedAt != null ? DateTime.now().difference(_startedAt!).inMilliseconds : 0);

  /// Milliseconds left in this turn (the full limit when unlimited/idle).
  int get remainingMs => limitMs == null ? 0 : (limitMs! - _elapsed).clamp(0, limitMs!);

  /// 1 → 0 over the turn (null when unlimited).
  double? get fraction => limitMs == null ? null : remainingMs / limitMs!;

  /// "0:27" / "∞".
  String get text {
    if (limitMs == null) return '∞';
    final s = (remainingMs / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// Last 10 seconds.
  bool get urgent => limitMs != null && _running && remainingMs <= 10000;

  /// A new turn (or extra roll): full time again.
  void start() {
    _elapsedBeforePause = 0;
    _expired = false;
    _startedAt = DateTime.now();
    _running = true;
    _tick();
    notifyListeners();
  }

  /// Turn over (a move is being animated / game ended).
  void stop() {
    _running = false;
    _ticker?.cancel();
    notifyListeners();
  }

  void pause() {
    if (!_running) return;
    _elapsedBeforePause = _elapsed;
    _running = false;
    _ticker?.cancel();
    notifyListeners();
  }

  void resume() {
    if (_running || _expired || _startedAt == null) return;
    _startedAt = DateTime.now();
    _running = true;
    _tick();
    notifyListeners();
  }

  void _tick() {
    _ticker?.cancel();
    if (limitMs == null) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_running) return;
      if (remainingMs <= 0 && !_expired) {
        _expired = true;
        _running = false;
        _ticker?.cancel();
        notifyListeners();
        onExpire?.call();
        return;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

/// Setup choices — the same as chess Quick Play.
const turnTimeOptions = <({String label, int? ms})>[
  (label: '30 sec', ms: 30 * 1000),
  (label: '1 min', ms: 60 * 1000),
  (label: '2 min', ms: 2 * 60 * 1000),
  (label: 'Unlimited', ms: null),
];
