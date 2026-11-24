import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/rewards.dart';
import '../../data/repositories/rewards_repository.dart';
import '../../services/app_exception.dart';
import '../../services/rewards_service.dart';
import '../../services/server_clock.dart';
import '../../app/routes.dart';
import '../../state/async_view.dart' show ErrorRetry;
import '../../widgets/aura.dart';
import '../../widgets/wallet_pill.dart';
import '../economy/rewards_ui.dart';
import '../system/loading_skeleton_screen.dart' show Shimmer, SkeletonBox;

/// One wheel wedge, drawn from a server prize: the label split into an
/// amount and a unit ("150" / "tokens"), coloured by rarity.
@immutable
class _Seg {
  const _Seg(this.amount, this.unit, this.color, {this.jackpot = false});
  final String amount;
  final String unit;
  final Color color;
  final bool jackpot;

  static const _purple = Color(0xFF6D28D9);
  static const _pink = Color(0xFF9D174D);
  static const _empty = Color(0xFF2A2440);

  /// The wedges of [g], in slot order (slot 0 under the pointer).
  static List<_Seg> of(BonusGame g) {
    final n = math.max(1, g.slots);
    return [
      for (var i = 0; i < n; i++)
        if (i < g.prizes.length) _from(g.prizes[i], i) else const _Seg('', '', _empty),
    ];
  }

  static _Seg _from(BonusPrize p, int i) {
    final m = RegExp(r'^([\d.,]+[×x]?)\s+(.+)$').firstMatch(p.label.trim());
    final (amount, unit) = m == null ? (p.label.trim(), '') : (m.group(1)!, m.group(2)!);
    final color = switch (p.rarity) {
      'legendary' => const Color(0xFFB45309),
      'epic' => const Color(0xFF0E7490),
      _ => i.isEven ? _purple : _pink,
    };
    return _Seg(amount, unit, color, jackpot: p.rarity == 'legendary');
  }

  @override
  bool operator ==(Object other) =>
      other is _Seg && other.amount == amount && other.unit == unit && other.color == color && other.jackpot == jackpot;

  @override
  int get hashCode => Object.hash(amount, unit, color, jackpot);
}

/// Wheel tab — "Lucky Spin". Scrollable body only (shell provides chrome).
///
/// Shows the server's wheel-type bonus games (07-rewards.md §5): the free
/// spins the player is entitled to (welcome spin, a spin-day daily claim's
/// spin) and the paid `store` wheels. SPIN calls the play route; the wheel
/// lands on the reply's `slot_index` and shows its `prize`. Nothing about
/// the outcome is decided on the device. See docs/DESIGN_SPEC.md.
class WheelScreen extends ConsumerStatefulWidget {
  const WheelScreen({super.key});

  @override
  ConsumerState<WheelScreen> createState() => _WheelScreenState();
}

class _WheelScreenState extends ConsumerState<WheelScreen> with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );

  /// The jackpot celebration (only when a legendary prize wins).
  late final AnimationController _jackpot = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600))
    ..addListener(() => setState(() {}));

  /// Marquee bulbs around the rim: a slow blink at rest, a chase while spinning.
  late final AnimationController _lights = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  double _fromAngle = 0;
  double _toAngle = 0;

  /// The play request is running: SPIN can't be tapped twice (a double tap
  /// on a paid wheel would pay twice).
  bool _playing = false;

  /// The wheel picked in the selector (by [WheelSpin.key]).
  String? _selected;

  /// The wheel being played or whose prize is showing: it stays on screen
  /// while the list re-reads (a used free spin leaves the list).
  WheelSpin? _active;

  /// The last play's reply (the prize banner), until it hides.
  BonusPlayResult? _result;

  /// Free spins used or refused this session (keys are per entitlement), so
  /// one isn't offered again while a re-read lags behind.
  final _spent = <String>{};

  /// Limits from the last reply's `plays_left_today`, until the next read.
  final _limits = <String, BonusGameLimits>{};

  /// Hides the win message 3 s after the wheel stops.
  Timer? _hideResult;

  bool get _busy => _playing || _controller.isAnimating;

  /// Ticks the "next free spin" countdown while the wheel is locked.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_busy) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _hideResult?.cancel();
    _lights.dispose();
    _jackpot.dispose();
    _controller.dispose();
    super.dispose();
  }

  BonusGameLimits _me(WheelSpin s) => _limits[s.key] ?? s.game.me;

  /// May [s] be spun now? Only a wheel from the latest list read.
  bool _canSpin(WheelSpin s, List<WheelSpin> list) =>
      !_busy &&
      list.any((x) => x.key == s.key) &&
      !(s.free && _spent.contains(s.key)) &&
      _me(s).blockReason == null;

  /// The wheel to show: the one in play (or showing its prize), else the
  /// selected one, else the first.
  WheelSpin? _shown(List<WheelSpin> list) {
    WheelSpin? find(String? key) => key == null ? null : list.where((s) => s.key == key).firstOrNull;
    final active = _active;
    if (active != null && (_busy || _result != null)) return find(active.key) ?? active;
    return find(_selected) ?? list.firstOrNull;
  }

  void _select(WheelSpin s) {
    if (_busy || s.key == _selected) return;
    _hideResult?.cancel();
    setState(() {
      _selected = s.key;
      _result = null;
      _active = null;
      // A different wheel: start upright.
      _fromAngle = _toAngle = 0;
    });
  }

  Future<void> _spin(WheelSpin s, List<WheelSpin> list) async {
    if (!_canSpin(s, list)) return;
    _hideResult?.cancel();
    setState(() {
      _playing = true;
      _result = null;
      _active = s;
      _selected = s.key;
    });
    try {
      final r = await ref
          .read(rewardsApiProvider)
          .playBonusGame(s.game.code, trigger: s.trigger, triggerRef: s.triggerRef);
      if (!mounted) return;
      // Land the server's slice under the pointer after five full turns.
      _fromAngle = _toAngle % (2 * math.pi);
      _toAngle = bonusWheelTarget(_fromAngle, r.slotIndex, s.game.slots);
      setState(() {
        _limits[s.key] = _me(s).withPlaysLeft(r.playsLeftToday);
        if (s.free) _spent.add(s.key);
      });
      await _controller.forward(from: 0);
      if (!mounted) return;
      // Header balance after the animation, from the reply.
      applyRewardToWallet(ref, balances: r.balances);
      setState(() => _result = r);
      if (r.prize.rarity == 'legendary' && !r.prize.isNothing) {
        HapticFeedback.heavyImpact();
        _jackpot.forward(from: 0);
      }
      _hideResult = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _result = null);
      });
      _refreshAfterPlay(s);
    } on AppException catch (e) {
      if (!mounted) return;
      final issue = bonusPlayIssue(e, cooldownUntil: _me(s).cooldownUntil);
      if (issue.kind == RewardIssueKind.notEnoughFunds) {
        unawaited(offerBonusShop(context, ref, s.game));
        return;
      }
      showRewardIssue(context, issue);
      if (issue.kind == RewardIssueKind.gone) {
        // Used, expired or over a limit: re-read what can be spun.
        if (s.free) setState(() => _spent.add(s.key));
        _refreshAfterPlay(s);
      }
    } on Object catch (_) {
      if (mounted) showAuraToast(context, 'Something went wrong. Try again.', kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  /// After a play: the welcome spin, history and limits changed.
  void _refreshAfterPlay(WheelSpin s) {
    ref.invalidate(welcomeBonusProvider);
    ref.invalidate(bonusPlaysProvider);
    ref.invalidate(bonusGamesProvider);
    ref.invalidate(bonusGameProvider(s.game.code));
  }

  void _showOdds(BonusGame g) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: AuraGlass.decoration(radius: 22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionBar('Odds · ${g.name}'),
                const SizedBox(height: 10),
                BonusOddsTable(prizes: g.prizes),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _resultText(BonusPlayResult r) {
    final text = bonusPrizeText(r.prize);
    return r.prize.rarity == 'legendary' && !r.prize.isNothing ? 'JACKPOT!  $text' : text;
  }

  @override
  Widget build(BuildContext context) {
    // A fresh list read has the server's limits.
    ref.listen(wheelSpinsProvider, (_, next) {
      if (next.hasValue && !next.isLoading) _limits.clear();
    });
    final spins = ref.watch(wheelSpinsProvider);
    final Widget body;
    if (spins.hasValue) {
      body = _content(spins.requireValue);
    } else if (spins.hasError) {
      body = Center(child: ErrorRetry(onRetry: () => refreshWheelSpins(ref)));
    } else {
      body = const _WheelSkeleton();
    }
    return Stack(
      children: [
        Padding(
          // Same insets as the Store tab, so the header pills line up.
          padding: const EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 0),
          child: Column(
            children: [
              const WalletTitleBar(title: 'Lucky Spin'),
              Expanded(child: body),
            ],
          ),
        ),
        // Jackpot only: golden burst, coin shower and the JACKPOT! shout.
        if (_jackpot.isAnimating)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _jackpot,
                builder: (_, _) => CustomPaint(
                  painter: _JackpotPainter(_jackpot.value),
                  child: Center(child: _JackpotShout(t: _jackpot.value)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The locked wheel's line: claim today, or the countdown to that day.
  String _unlockText(WheelUnlock u) {
    if (u.claimToday) return "Claim today's daily bonus to unlock this free spin";
    final at = u.at!;
    final left = ServerClock.until(at);
    if (left == Duration.zero) return 'Your free spin is ready to unlock: claim your daily bonus';
    return 'Next free spin in ${rewardCountdown(at, now: ServerClock.now())}\n'
        'on day ${u.day} of your daily bonus streak';
  }

  /// No wheel to spin right now.
  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.casino_outlined, color: AuraColors.textSecondary, size: 40),
            const SizedBox(height: 12),
            Text('No spins right now', style: AuraText.title.copyWith(fontSize: 18), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              'Claim your daily bonus to unlock spins on spin days.',
              style: AuraText.cardSub,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            SecondaryButton(label: 'Refresh', onPressed: () => refreshWheelSpins(ref)),
          ],
        ),
      ),
    );
  }

  Widget _content(List<WheelSpin> all) {
    final list = [for (final s in all) if (!(s.free && _spent.contains(s.key))) s];
    final spinnable = _shown(list);
    // Nothing to spin: show the next free wheel, locked, with its countdown.
    final unlock = spinnable == null ? ref.watch(nextWheelUnlockProvider).value : null;
    if (spinnable == null && unlock == null) return _empty();
    final locked = spinnable == null;
    final shown = spinnable ?? WheelSpin(game: unlock!.game, trigger: 'daily_bonus_day');
    final g = shown.game;
    final segs = _Seg.of(g);
    final me = _me(shown);
    final canSpin = !locked && _canSpin(shown, list);
    final blocked = me.blockReason;
    final used = shown.free && _spent.contains(shown.key);
    final String hint;
    if (locked) {
      hint = _unlockText(unlock!);
    } else if (used) {
      hint = 'Spin used';
    } else if (blocked != null) {
      hint = blockedText(blocked, cooldownUntil: me.cooldownUntil).text ?? 'Not available right now.';
    } else {
      hint = 'Land on a wedge to win tokens or gold';
    }
    final r = _result;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 12),
              if (list.length > 1) ...[
                _WheelPicker(spins: list, selected: shown.key, enabled: !_busy, onPick: _select),
                const SizedBox(height: 12),
              ],
              Center(
                child: locked
                    ? _LockedChip(day: unlock!.day)
                    : _SpinInfoChip(spin: shown, limits: me, used: used),
              ),
              const SizedBox(height: 28),
              Center(
                child: SizedBox(
                  width: 312,
                  height: 324,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_controller, _lights]),
                    builder: (context, _) {
                      // Long, natural slow-down (most of the time is spent easing in).
                      final t = Curves.easeOutQuart.transform(_controller.value);
                      final angle = _fromAngle + (_toAngle - _fromAngle) * t;
                      return Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Soft drop shadow under the whole wheel.
                          Positioned(
                            top: 12,
                            child: Container(
                              width: 300,
                              height: 300,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    blurRadius: 28,
                                    offset: const Offset(0, 14),
                                  ),
                                  BoxShadow(
                                    color: AuraColors.accentGlow.withValues(alpha: 0.25),
                                    blurRadius: 40,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Gold rim + marquee bulbs (fixed).
                          Positioned(
                            top: 12,
                            child: CustomPaint(
                              size: const Size(300, 300),
                              painter: _RimPainter(
                                phase: _lights.value,
                                spinning: _controller.isAnimating,
                                jackpot: _jackpot.isAnimating,
                              ),
                            ),
                          ),
                          // The wedges (rotating).
                          Positioned(
                            top: 12 + 22,
                            child: Transform.rotate(
                              angle: angle,
                              child: CustomPaint(
                                size: const Size(256, 256),
                                painter: _WheelPainter(segs: segs),
                              ),
                            ),
                          ),
                          // Centre hub: brass bezel around the SPIN button.
                          Positioned(
                            top: 12 + 150 - 50,
                            child: _SpinButton(
                              onTap: () => _spin(shown, list),
                              enabled: canSpin,
                              busy: _playing && !_controller.isAnimating,
                              phase: _lights.value,
                            ),
                          ),
                          // Flapper pointer: kicks back as each peg passes, then settles.
                          Positioned(
                            top: 0,
                            child: Transform.rotate(
                              angle: _flapperAngle(angle, segs.length),
                              alignment: const Alignment(0, -0.62),
                              child: CustomPaint(size: const Size(34, 44), painter: _PointerPainter()),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 26),
              // Fixed height: the wheel stays put when the win shows.
              SizedBox(
                height: 46,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: c),
                    ),
                    child: r != null
                        ? _ResultBanner(key: ValueKey('r${r.playId}'), text: _resultText(r))
                        : Text(hint, key: ValueKey(hint), style: AuraText.cardSub, textAlign: TextAlign.center),
                  ),
                ),
              ),
              if (locked && unlock!.claimToday)
                SecondaryButton(
                  label: 'Claim daily bonus',
                  onPressed: () => Navigator.pushNamed(context, Routes.dailyRewards).then((_) => refreshWheelSpins(ref)),
                ),
              if (g.hasOdds)
                TextButton(
                  onPressed: () => _showOdds(g),
                  child: Text('See odds', style: AuraText.cardSub.copyWith(color: AuraColors.accentGlow)),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Pointer deflection for wheel [angle]: pegs sit on the wedge borders; one
  /// passing under the pointer pushes it aside, then it springs back.
  static double _flapperAngle(double angle, int wedges) {
    final sweep = 2 * math.pi / math.max(1, wedges);
    // How far the nearest border has travelled past the pointer (0 → sweep).
    final d = (angle - sweep / 2) % sweep;
    const kick = 0.32; // fraction of a wedge the pointer stays pushed
    if (d >= sweep * kick) return 0;
    final f = 1 - d / (sweep * kick);
    return -0.42 * f * f;
  }
}

/// Loading: the wheel's outline shimmering where it will be.
class _WheelSkeleton extends StatelessWidget {
  const _WheelSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Shimmer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SkeletonBox(width: 150, height: 30, radius: 99),
            SizedBox(height: 28),
            SkeletonBox(height: 300, shape: BoxShape.circle),
            SizedBox(height: 26),
            SkeletonBox(width: 220, height: 14, radius: 6),
          ],
        ),
      ),
    );
  }
}

/// The wheels on offer, when there is more than one: free spins first.
class _WheelPicker extends StatelessWidget {
  const _WheelPicker({required this.spins, required this.selected, required this.enabled, required this.onPick});
  final List<WheelSpin> spins;
  final String selected;
  final bool enabled;
  final ValueChanged<WheelSpin> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in spins)
          GestureDetector(
            onTap: enabled ? () => onPick(s) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: s.key == selected ? AuraGradients.brand : null,
                color: s.key == selected ? null : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Colors.white.withValues(alpha: s.key == selected ? 0.0 : 0.14)),
              ),
              child: Text(
                s.game.name.isEmpty ? s.game.code : s.game.name,
                style: TextStyle(
                  fontFamily: AuraText.displayFamily,
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "Free spin" / "100 Tokens per spin · 4 left today".
/// "Locked · day N" over a wheel that isn't spinnable yet.
class _LockedChip extends StatelessWidget {
  const _LockedChip({required this.day});
  final int day;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_clock_rounded, size: 15, color: AuraColors.textSecondary),
          const SizedBox(width: 6),
          Text('Free spin · daily bonus day $day', style: AuraText.cardSub.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}

class _SpinInfoChip extends StatelessWidget {
  const _SpinInfoChip({required this.spin, required this.limits, required this.used});
  final WheelSpin spin;
  final BonusGameLimits limits;
  final bool used;

  @override
  Widget build(BuildContext context) {
    final g = spin.game;
    final String text;
    if (spin.free) {
      text = used ? 'Free spin used' : 'Free spin';
    } else {
      final left = g.maxPlaysPerDay > 0 ? ' · ${limits.playsLeftToday} left today' : '';
      text = g.cost.free ? 'Free$left' : '${bonusCostText(g.cost)} per spin$left';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: AuraGlass.decoration(radius: 99, shadow: false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spin.free ? Icons.card_giftcard_rounded : Icons.refresh, size: 15, color: AuraColors.accentGlow),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: AuraColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AuraColors.green.withValues(alpha: 0.18),
            AuraColors.amber.withValues(alpha: 0.14),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AuraColors.green.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AuraText.displayFamily,
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Centre hub: a brass bezel with rivets around a casino-style jewel
/// button — deep red dome with a bevel and gloss, embossed gold SPIN, a
/// breathing glow and a shine sweep while a spin is available.
class _SpinButton extends StatefulWidget {
  const _SpinButton({required this.onTap, required this.enabled, required this.phase, this.busy = false});
  final VoidCallback onTap;
  final bool enabled;

  /// Waiting for the server's draw.
  final bool busy;

  /// 0 → 1, repeating (drives the glow and the shine).
  final double phase;

  @override
  State<_SpinButton> createState() => _SpinButtonState();
}

class _SpinButtonState extends State<_SpinButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    final breathe = 0.5 + 0.5 * math.sin(widget.phase * 2 * math.pi);
    return GestureDetector(
      onTapDown: on ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTapUp: on
          ? (_) {
              setState(() => _down = false);
              widget.onTap();
            }
          : null,
      child: SizedBox(
        width: 100,
        height: 100,
        child: CustomPaint(
          painter: _HubPainter(),
          child: Center(
            child: AnimatedScale(
              scale: _down ? 0.9 : 1,
              duration: const Duration(milliseconds: 90),
              child: SizedBox.square(
                dimension: 72,
                child: CustomPaint(
                  painter: _JewelPainter(on: on, pressed: _down, glow: on ? breathe : 0, shine: on ? widget.phase : -1),
                  child: Center(
                    child: widget.busy
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Color(0xFFFCD34D))),
                          )
                        : _SpinLabel(on: on),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Embossed gold "SPIN": a dark under-stroke, then the gold face.
class _SpinLabel extends StatelessWidget {
  const _SpinLabel({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: AuraText.displayFamily,
      fontSize: 18,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.5,
      height: 1,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        // Depth: a dark copy just below.
        Transform.translate(
          offset: const Offset(0, 1.6),
          child: Text('SPIN', style: style.copyWith(color: on ? const Color(0xFF5A0610) : Colors.black45)),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: on
                ? const [Color(0xFFFFF7D1), Color(0xFFFCD34D), Color(0xFFD97706)]
                : const [Color(0xFFE5E7EB), Color(0xFF9CA3AF), Color(0xFF6B7280)],
            stops: const [0, 0.5, 1],
          ).createShader(r),
          child: Text('SPIN', style: style.copyWith(color: Colors.white)),
        ),
      ],
    );
  }
}

/// The dome: outer glow, a bevelled rim (light top, dark bottom), the red
/// jewel with depth, a glossy crescent, and a shine that sweeps across.
class _JewelPainter extends CustomPainter {
  _JewelPainter({required this.on, required this.pressed, required this.glow, required this.shine});
  final bool on;
  final bool pressed;
  final double glow;

  /// Shine position 0 → 1 (−1 = none).
  final double shine;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final base = on ? const Color(0xFFDC2626) : const Color(0xFF6B7280);
    if (on) {
      canvas.drawCircle(
        c,
        r + 2,
        Paint()
          ..color = const Color(0xFFFBBF24).withValues(alpha: 0.25 + 0.35 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 6 * glow),
      );
    }
    // Bevelled rim.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: pressed
              ? [Color.lerp(base, Colors.black, 0.55)!, Color.lerp(base, Colors.white, 0.35)!]
              : [Color.lerp(base, Colors.white, 0.45)!, Color.lerp(base, Colors.black, 0.6)!],
        ).createShader(rect),
    );
    // The jewel.
    final jr = r - 4;
    canvas.drawCircle(
      c,
      jr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 0.95,
          colors: on
              ? [const Color(0xFFFF6B6B), base, const Color(0xFF7F1D1D), const Color(0xFF450A0A)]
              : [const Color(0xFFD1D5DB), base, const Color(0xFF374151), const Color(0xFF1F2937)],
          stops: const [0, 0.45, 0.85, 1],
        ).createShader(Rect.fromCircle(center: c, radius: jr)),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: jr)));
    // Shine sweep (a soft diagonal band crossing the dome).
    if (shine >= 0 && shine < 0.45) {
      final t = shine / 0.45;
      final x = c.dx - jr * 1.6 + t * jr * 3.2;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.32), Colors.white.withValues(alpha: 0)],
            stops: const [0.4, 0.5, 0.6],
          ).createShader(Rect.fromCenter(center: Offset(x, c.dy), width: jr * 2, height: jr * 2)),
      );
    }
    canvas.restore();
    // Glossy crescent on the top half.
    if (!pressed) {
      final gloss = Rect.fromCenter(center: c - Offset(0, jr * 0.45), width: jr * 1.4, height: jr * 0.8);
      canvas.drawOval(
        gloss,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withValues(alpha: on ? 0.55 : 0.35), Colors.white.withValues(alpha: 0)],
          ).createShader(gloss),
      );
      canvas.drawCircle(c + Offset(-jr * 0.42, -jr * 0.5), jr * 0.07, Paint()..color = Colors.white.withValues(alpha: 0.85));
    }
    // Thin dark ring between rim and jewel.
    canvas.drawCircle(
      c,
      jr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_JewelPainter old) =>
      old.on != on || old.pressed != pressed || old.glow != glow || old.shine != shine;
}

/// Brass bezel (metallic sweep) with eight rivets.
class _HubPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(c, r - 1, Paint()..shader = _brass.createShader(rect));
    // Inner groove.
    canvas.drawCircle(
      c,
      r - 12,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF7C4A03),
    );
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + math.pi / 8;
      final p = c + Offset(math.cos(a), math.sin(a)) * (r - 6.5);
      canvas.drawCircle(p, 2.6, Paint()..color = const Color(0xFF7C4A03));
      canvas.drawCircle(
        p - const Offset(0.6, 0.6),
        1.6,
        Paint()..color = const Color(0xFFFFF3C4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HubPainter oldDelegate) => false;
}

/// Polished brass: light/dark bands around the circle.
const _brass = SweepGradient(
  colors: [
    Color(0xFFFDE68A),
    Color(0xFFB45309),
    Color(0xFFFCD34D),
    Color(0xFF92400E),
    Color(0xFFFEF3C7),
    Color(0xFFB45309),
    Color(0xFFFDE68A),
  ],
);

/// The fixed outer rim: brass ring with 16 marquee bulbs.
class _RimPainter extends CustomPainter {
  _RimPainter({required this.phase, required this.spinning, this.jackpot = false});

  /// Jackpot: every bulb flashes together, fast.
  final bool jackpot;

  /// 0 → 1, repeating.
  final double phase;
  final bool spinning;

  static const bulbs = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    // Brass ring and a dark inner lip the wedges sit in.
    canvas.drawCircle(c, r, Paint()..shader = _brass.createShader(rect));
    canvas.drawCircle(
      c,
      r - 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF78350F),
    );
    canvas.drawCircle(c, r - 19, Paint()..color = const Color(0xFF1A0B2E));
    canvas.drawCircle(
      c,
      r - 19,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF78350F),
    );

    // Bulbs: alternate blink at rest; a fast chase while the wheel turns.
    for (var i = 0; i < bulbs; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / bulbs;
      final p = c + Offset(math.cos(a), math.sin(a)) * (r - 11);
      final bool lit;
      if (jackpot) {
        lit = (phase * 14).floor().isEven;
      } else if (spinning) {
        lit =
            (i - (phase * bulbs * 2).floor()) % 4 == 0 ||
            (i - (phase * bulbs * 2).floor()) % 4 == 1;
      } else {
        lit = (i.isEven) == (phase < 0.5);
      }
      if (lit) {
        canvas.drawCircle(
          p,
          7,
          Paint()
            ..color = const Color(0xFFFFF7D6).withValues(alpha: 0.55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
      canvas.drawCircle(p, 4.6, Paint()..color = const Color(0xFF78350F));
      canvas.drawCircle(
        p,
        3.6,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.35),
            colors: lit
                ? const [Colors.white, Color(0xFFFDE68A), Color(0xFFF59E0B)]
                : const [
                    Color(0xFF9A6B2F),
                    Color(0xFF6B4410),
                    Color(0xFF3F2A0A),
                  ],
          ).createShader(Rect.fromCircle(center: p, radius: 3.6)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RimPainter old) =>
      old.phase != phase || old.spinning != spinning || old.jackpot != jackpot;
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.segs});

  final List<_Seg> segs;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final segCount = segs.length;
    final sweep = 2 * math.pi / segCount;

    // Segment 0 is centered at the top pointer.
    final startBase = -math.pi / 2 - sweep / 2;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final segPaint = Paint()..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFFFCD34D).withValues(alpha: 0.55)
      ..strokeWidth = 1.6;

    for (var i = 0; i < segCount; i++) {
      final start = startBase + sweep * i;
      segPaint.color = segs[i].color;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(rect, start, sweep, false)
        ..close();
      canvas.drawPath(path, segPaint);
      // Light from the rim falling toward the hub.
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.black.withValues(alpha: 0.35),
              Colors.transparent,
              Colors.white.withValues(alpha: 0.10),
            ],
            stops: const [0.25, 0.7, 1],
          ).createShader(rect),
      );
      canvas.drawPath(path, borderPaint);

      _drawLabel(canvas, center, radius, start + sweep / 2, sweep, segs[i]);
    }
    // Pegs on the wedge borders (they flick the pointer as they pass).
    for (var i = 0; i < segCount; i++) {
      final a = startBase + sweep * i;
      final p = center + Offset(math.cos(a), math.sin(a)) * (radius - 7);
      canvas.drawCircle(
        p + const Offset(0.8, 1.2),
        4.2,
        Paint()..color = Colors.black.withValues(alpha: 0.45),
      );
      canvas.drawCircle(
        p,
        4,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.4, -0.4),
            colors: [Color(0xFFFFFBEB), Color(0xFFFBBF24), Color(0xFF92400E)],
          ).createShader(Rect.fromCircle(center: p, radius: 4)),
      );
    }
  }

  void _drawLabel(
    Canvas canvas,
    Offset center,
    double radius,
    double midAngle,
    double sweep,
    _Seg seg,
  ) {
    final color = seg.jackpot ? const Color(0xFFFDE68A) : Colors.white;
    // The wedge's width where the label sits.
    final maxW = math.max(24.0, math.min(radius * 0.5, 2 * radius * 0.62 * math.sin(sweep / 2) - 6));
    final amount = TextPainter(
      text: TextSpan(
        text: seg.amount,
        style: TextStyle(
          fontFamily: AuraText.displayFamily,
          color: color,
          fontSize: segs.length > 8 ? 12 : 14,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    final unit = TextPainter(
      text: TextSpan(
        text: seg.unit,
        style: TextStyle(
          color: color.withValues(alpha: 0.75),
          fontSize: 9,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxW);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(midAngle);
    canvas.translate(radius * 0.62, 0);
    canvas.rotate(math.pi / 2); // text reads outward from centre
    amount.paint(canvas, Offset(-amount.width / 2, -amount.height - 1));
    unit.paint(canvas, Offset(-unit.width / 2, 1));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => !listEquals(old.segs, segs);
}

/// Brass flapper pointer with a ruby inset and a pivot bolt.
class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = Path()
      ..moveTo(w / 2, h)
      ..cubicTo(w * 0.16, h * 0.55, 0, h * 0.34, 0, h * 0.2)
      ..arcToPoint(Offset(w, h * 0.2), radius: Radius.circular(w / 2))
      ..cubicTo(w, h * 0.34, w * 0.84, h * 0.55, w / 2, h)
      ..close();
    canvas.drawShadow(body, Colors.black, 4, false);
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFEF3C7), Color(0xFFF59E0B), Color(0xFF92400E)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF78350F),
    );
    // Ruby.
    final gem = Offset(w / 2, h * 0.42);
    canvas.drawCircle(
      gem,
      5,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.4),
          colors: [Color(0xFFFECACA), Color(0xFFDC2626), Color(0xFF7F1D1D)],
        ).createShader(Rect.fromCircle(center: gem, radius: 5)),
    );
    // Pivot bolt.
    final bolt = Offset(w / 2, h * 0.19);
    canvas.drawCircle(bolt, 4, Paint()..color = const Color(0xFF78350F));
    canvas.drawCircle(
      bolt - const Offset(0.7, 0.7),
      2.4,
      Paint()..color = const Color(0xFFFFFBEB),
    );
  }

  @override
  bool shouldRepaint(covariant _PointerPainter oldDelegate) => false;
}

/// Jackpot celebration behind the shout: golden rays turning, a flash, and
/// spinning gold coins raining down. [t] runs 0 → 1 once.
class _JackpotPainter extends CustomPainter {
  _JackpotPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.48);
    final fade = t < 0.08 ? t / 0.08 : (t > 0.82 ? (1 - t) / 0.18 : 1.0);
    // Dim + opening flash.
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: 0.35 * fade));
    if (t < 0.18) {
      canvas.drawCircle(
        c,
        size.width * (0.2 + t * 4),
        Paint()
          ..color = const Color(0xFFFDE68A).withValues(alpha: 0.5 * (1 - t / 0.18))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
      );
    }
    // Turning rays.
    final rays = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFFFBBF24).withValues(alpha: 0.55 * fade), const Color(0x00FBBF24)],
      ).createShader(Rect.fromCircle(center: c, radius: size.width * 0.9));
    final turn = t * math.pi * 0.8;
    for (var k = 0; k < 14; k++) {
      final a = turn + k * 2 * math.pi / 14;
      final r = size.width * 0.95;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + r * math.cos(a - 0.09), c.dy + r * math.sin(a - 0.09))
          ..lineTo(c.dx + r * math.cos(a + 0.09), c.dy + r * math.sin(a + 0.09))
          ..close(),
        rays,
      );
    }
    // Coin shower.
    final rng = math.Random(9);
    for (var i = 0; i < 46; i++) {
      final x = rng.nextDouble() * size.width;
      final delay = rng.nextDouble() * 0.4;
      final speed = 0.7 + rng.nextDouble() * 0.6;
      final p = ((t - delay) * speed * 1.7).clamp(0.0, 1.3);
      if (p <= 0) continue;
      final y = -30 + p * (size.height + 60);
      final spin = p * 18 + i;
      final r = 7 + rng.nextDouble() * 6;
      final w = r * (0.25 + 0.75 * math.cos(spin).abs());
      final rect = Rect.fromCenter(center: Offset(x + math.sin(p * 6 + i) * 14, y), width: w * 2, height: r * 2);
      canvas.drawOval(rect, Paint()..color = const Color(0xFFB45309).withValues(alpha: fade));
      canvas.drawOval(rect.deflate(1.5), Paint()..color = const Color(0xFFFBBF24).withValues(alpha: fade));
      canvas.drawOval(
        Rect.fromCenter(center: rect.center - Offset(w * 0.25, r * 0.3), width: w * 0.7, height: r * 0.6),
        Paint()..color = Colors.white.withValues(alpha: 0.55 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_JackpotPainter old) => old.t != t;
}

/// "JACKPOT!" in gold, dropping in with a bounce and a short shake.
class _JackpotShout extends StatelessWidget {
  const _JackpotShout({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final inT = Curves.elasticOut.transform((t / 0.3).clamp(0.0, 1.0));
    final out = t > 0.85 ? (t - 0.85) / 0.15 : 0.0;
    final shake = t > 0.12 && t < 0.4 ? math.sin(t * 90) * 4 * (1 - (t - 0.12) / 0.28) : 0.0;
    return Opacity(
      opacity: (1 - out).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(shake, -40),
        child: Transform.scale(
          scale: 0.3 + 0.7 * inT,
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFF7D1), Color(0xFFFCD34D), Color(0xFFD97706)],
            ).createShader(r),
            child: Text(
              'JACKPOT!',
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                fontSize: 54,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                shadows: const [Shadow(color: Color(0xFF7C2D12), blurRadius: 0, offset: Offset(0, 4)), Shadow(color: Colors.black54, blurRadius: 18)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
