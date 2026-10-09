import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';

/// Matchmaking "VS" (mockup `isVs`): searching → opponent reveal → countdown
/// → GO → the board.
///
/// Mockup timings: search 1.9s → reveal 1.4s → "2" 0.9s → "1" 0.9s →
/// "GO!" 0.6s → game. Animations: a pulsing background glow, a spinning
/// gradient ring around the VS badge while searching, and two radar rings
/// expanding from the empty opponent seat.
///
/// Set [autoStart] false to hold the searching state (tests).
class MatchmakingScreen extends ConsumerStatefulWidget {
  const MatchmakingScreen({
    super.key,
    this.autoStart = true,
    this.players = 2,
    this.stake = 200,
    this.tokens = true,
    this.label = 'Friends room',
    this.opponentName = 'ZeroCool',
  });

  final bool autoStart;
  final int players;

  /// Stake per player (0 = free match) and its currency.
  final int stake;
  final bool tokens;

  /// Top-left pill, shown as "<LABEL> · CHESS".
  final String label;
  final String opponentName;

  @override
  ConsumerState<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

enum _Phase { search, reveal, count, go }

class _MatchmakingScreenState extends ConsumerState<MatchmakingScreen> with TickerProviderStateMixin {
  _Phase _phase = _Phase.search;
  int _count = 3;
  Timer? _timer;

  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 3));
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _radar = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  // Opponent level (mockup: 4–12).
  final int _oppLevel = 4 + math.Random().nextInt(9);

  @override
  void initState() {
    super.initState();
    if (!widget.autoStart) return;
    _pulse.repeat();
    _spin.repeat();
    _radar.repeat();
    _timer = Timer(const Duration(milliseconds: 1900), () {
      if (!mounted) return;
      setState(() => _phase = _Phase.reveal);
      _spin.stop();
      _radar.stop();
      _timer = Timer(const Duration(milliseconds: 1400), _tick);
    });
  }

  /// Mockup vsTick: 3 → shows 2 (0.9s) → 1 (0.9s) → GO! (0.6s) → game.
  void _tick() {
    if (!mounted) return;
    if (_count <= 1) {
      setState(() {
        _phase = _Phase.go;
        _count = 0;
      });
      _timer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) Navigator.pushReplacementNamed(context, Routes.chess);
      });
      return;
    }
    setState(() {
      _phase = _Phase.count;
      _count -= 1;
    });
    _timer = Timer(const Duration(milliseconds: 900), _tick);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    _spin.dispose();
    _radar.dispose();
    super.dispose();
  }

  String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  bool get _hasStake => widget.stake > 0;
  String get _potFmt => _fmt(widget.stake * widget.players);
  String get _stakeFmt => _hasStake ? _fmt(widget.stake) : 'Free';
  Currency get _currency => widget.tokens ? Currency.gems : Currency.gold;

  String get _status => switch (_phase) {
        _Phase.search => 'Finding players…',
        _Phase.reveal => 'Opponents found!',
        _Phase.count => 'Match starts in',
        _Phase.go => 'GO!',
      };

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final searching = _phase == _Phase.search;
    return Scaffold(
      backgroundColor: const Color(0xFF070510),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.92),
            radius: 1.25,
            colors: [Color(0xFF1A1236), Color(0xFF0A0816), Color(0xFF070510)],
            stops: [0, 0.54, 1],
          ),
        ),
        child: Stack(
          children: [
            // Pulsing purple glow (auraPulse 3s: scale 1↔1.18, opacity .55↔.9).
            Positioned(
              top: 120,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, child) {
                    final t = 0.5 - 0.5 * math.cos(2 * math.pi * _pulse.value);
                    return Opacity(
                      opacity: 0.55 + 0.35 * t,
                      child: Transform.scale(scale: 1 + 0.18 * t, child: child),
                    );
                  },
                  child: Container(
                    width: 420,
                    height: 420,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [AuraColors.brandPurple.withValues(alpha: 0.28), AuraColors.brandPurple.withValues(alpha: 0)],
                        stops: const [0, 0.62],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top: mode label · pot + player count.
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              '${widget.label} · Chess'.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AuraText.displayFamily,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 1.5,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Colors.white.withValues(alpha: 0.09), Colors.white.withValues(alpha: 0.03)],
                            ),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_hasStake) ...[
                                CurrencyGlyph(kind: _currency, size: 14),
                                const SizedBox(width: 6),
                                Text('Pot $_potFmt  ', style: _pillText),
                              ],
                              Text('${widget.players}P', style: _pillText),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // YOU
                          _YouAvatar(initials: me.initials),
                          const SizedBox(height: 8),
                          Text(me.displayName, style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
                          const SizedBox(height: 8),
                          _LevelChip('LV ${me.level}', const Color(0xFFFBBF24), const Color(0xFFFBBF24)),
                          const SizedBox(height: 18),
                          // VS badge / countdown (+ spinning ring while searching).
                          SizedBox(
                            width: 104,
                            height: 104,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (searching)
                                  RotationTransition(
                                    turns: _spin,
                                    child: CustomPaint(size: const Size(104, 104), painter: _SpinRingPainter()),
                                  ),
                                _VsBadge(
                                  child: switch (_phase) {
                                    _Phase.count => Text('$_count', key: ValueKey(_count), style: _badgeText(40)),
                                    _Phase.go => Text('GO!', key: const ValueKey('go'), style: _badgeText(24)),
                                    _ => Text('VS', key: const ValueKey('vs'), style: _badgeText(26).copyWith(letterSpacing: 1)),
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // OPPONENT: searching radar → revealed player.
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            transitionBuilder: (child, a) => FadeTransition(
                              opacity: a,
                              child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(a), child: child),
                            ),
                            child: searching ? _searchingSeat() : _revealedOpponent(),
                          ),
                        ],
                      ),
                    ),
                    // Bottom: status · stake · cancel.
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    FittedBox(
                      fit: BoxFit.scaleDown, // never overflow on narrow phones
                      child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CurrencyGlyph(kind: _currency, size: 14),
                        const SizedBox(width: 6),
                        Text('Stake ', style: _metaText),
                        Text(_stakeFmt, style: _metaText.copyWith(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, color: Colors.white)),
                        if (_hasStake) ...[
                          const SizedBox(width: 18),
                          const Icon(Icons.emoji_events_outlined, size: 14, color: Color(0xFFFBBF24)),
                          const SizedBox(width: 6),
                          Text('Winner takes ', style: _metaText),
                          Text(_potFmt, style: _metaText.copyWith(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, color: const Color(0xFFFBBF24))),
                        ],
                      ],
                    ),
                    ),
                    if (searching) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.06),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.24), width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(
                            'Cancel search',
                            style: TextStyle(fontFamily: AuraText.bodyFamily, fontWeight: FontWeight.w600, fontSize: 15, color: Colors.white.withValues(alpha: 0.85)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle get _pillText => TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 12.5, color: Colors.white);
  TextStyle get _metaText => TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.65));
  TextStyle _badgeText(double size) =>
      TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: size, color: Colors.white);

  /// Empty dashed seat with two radar rings expanding out of it
  /// (auraRing 1.8s: scale .45→1.7, opacity .7→0; second ring 0.6s behind).
  Widget _searchingSeat() {
    return Column(
      key: const ValueKey('searching'),
      children: [
        SizedBox(
          width: 112,
          height: 112,
          child: AnimatedBuilder(
            animation: _radar,
            builder: (_, _) => Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                _radarRing((_radar.value) % 1, AuraColors.accentGlow),
                _radarRing((_radar.value + 2 / 3) % 1, AuraColors.brandPink), // 0.6s of 1.8s behind
                CustomPaint(
                  painter: _DashedCirclePainter(),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.04)),
                    child: Icon(Icons.person_outline_rounded, size: 36, color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Searching…', style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white.withValues(alpha: 0.7))),
        const SizedBox(height: 6),
        Text('1,284 players online', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.45))),
      ],
    );
  }

  Widget _radarRing(double t, Color color) {
    final eased = Curves.easeOut.transform(t);
    return IgnorePointer(
      child: Opacity(
        opacity: (0.7 * (1 - eased)).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.45 + (1.7 - 0.45) * eased,
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: 0.5), width: 2)),
          ),
        ),
      ),
    );
  }

  Widget _revealedOpponent() {
    final name = widget.opponentName;
    final initials = name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();
    return Column(
      key: const ValueKey('revealed'),
      children: [
        Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF43F5E), Color(0xFFFB7185)]),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 3),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 30, spreadRadius: -10, offset: const Offset(0, 14))],
          ),
          child: Text(initials, style: _badgeText(26)),
        ),
        const SizedBox(height: 7),
        Text(name, style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
        const SizedBox(height: 7),
        _LevelChip('LV $_oppLevel', const Color(0xFF67E8F9), const Color(0xFF22D3EE)),
      ],
    );
  }
}

/// You: 96px avatar inside a conic purple→pink→orange ring.
class _YouAvatar extends StatelessWidget {
  const _YouAvatar({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(colors: [AuraColors.brandPurple, AuraColors.brandPink, Color(0xFFFB923C), AuraColors.brandPurple]),
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0C0A16)),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AuraColors.brandPurple, AuraColors.brandPink]),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Text(initials, style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 30, color: Colors.white)),
        ),
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip(this.text, this.fg, this.tint);
  final String text;
  final Color fg;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Text(text, style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 11, color: fg)),
    );
  }
}

/// 84px VS badge: violet → pink → orange, white rim, pink glow. The label
/// pops in on each change (VS → 2 → 1 → GO!).
class _VsBadge extends StatelessWidget {
  const _VsBadge({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C3AED), Color(0xFFDB2777), Color(0xFFF97316)],
          stops: [0, 0.6, 1],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 3),
        boxShadow: [BoxShadow(color: AuraColors.brandPink.withValues(alpha: 0.8), blurRadius: 40, spreadRadius: -6)],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (c, a) => ScaleTransition(scale: Tween(begin: 1.6, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: FadeTransition(opacity: a, child: c)),
        child: child,
      ),
    );
  }
}

/// Spinning ring around the VS badge while searching: a 3px arc coloured
/// #C084FC (top) → #EC4899 (right), rotating every 1.1s.
class _SpinRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 1.5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi * 3 / 4, math.pi / 2, false, paint..color = AuraColors.accentGlow);
    canvas.drawArc(rect, -math.pi / 4, math.pi / 2, false, paint..color = AuraColors.brandPink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashedCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.35);
    final r = size.width / 2 - 1;
    const dashes = 22;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(Rect.fromCircle(center: size.center(Offset.zero), radius: r), (i / dashes) * 2 * math.pi, math.pi / dashes, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
