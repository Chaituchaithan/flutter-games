import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../data/models/daily_bonus.dart' show formatAmount;
import '../../data/models/rewards.dart';
import '../../data/repositories/rewards_repository.dart';
import '../../services/app_exception.dart';
import '../../services/rewards_service.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';
import '../economy/rewards_ui.dart';
import '../../services/server_clock.dart';

/// Welcome bonus sheet (07-rewards.md §1): what the welcome grant pays now,
/// the claim deadline, then the free Welcome-wheel spin. Shown once after
/// sign-up or guest create while something is claimable; amounts come from
/// `GET /welcome-bonus/me`, never from the app.
class WelcomeBonusScreen extends ConsumerStatefulWidget {
  const WelcomeBonusScreen({super.key});

  @override
  ConsumerState<WelcomeBonusScreen> createState() => _WelcomeBonusScreenState();
}

class _WelcomeBonusScreenState extends ConsumerState<WelcomeBonusScreen> {
  bool _claiming = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The expiry / next-part countdown.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _close() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushNamedAndRemoveUntil(Routes.home, (r) => false);
    }
  }

  Future<void> _spin(BonusGameOffer spin) async {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      unawaited(nav.pushReplacementNamed(
        Routes.bonusGame,
        arguments: {'code': spin.code, 'trigger': spin.trigger, 'triggerRef': spin.triggerRef},
      ));
    } else {
      unawaited(nav.pushNamedAndRemoveUntil(Routes.home, (r) => false));
      unawaited(openBonusGame(context, spin));
    }
  }

  Future<void> _claim(WelcomeBonus w) async {
    if (_claiming) return;
    setState(() => _claiming = true);
    try {
      final c = await ref.read(rewardsApiProvider).claimWelcome();
      if (!mounted) return;
      applyRewardToWallet(ref, balances: c.balances);
      final what = rewardSummary(tokens: c.credited.tokens, gold: c.credited.gold, powerUps: c.credited.powerUpQty);
      if (what.isNotEmpty) showAuraToast(context, 'Claimed $what', kind: AuraToastKind.gold);
      ref.invalidate(welcomeBonusProvider);
      // The free spin comes straight after the claim.
      final spin = w.freeSpin;
      if (spin != null && spin.available) {
        await _spin(spin);
      } else {
        _close();
      }
    } on AppException catch (e) {
      if (!mounted) return;
      final issue = showRewardIssue(context, welcomeClaimIssue(e, nextDueAt: w.nextDueAt));
      ref.invalidate(welcomeBonusProvider);
      if (issue.kind == RewardIssueKind.alreadyDone || issue.kind == RewardIssueKind.gone) _close();
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bonus = ref.watch(welcomeBonusProvider);
    return BusyGuard(
      busy: _claiming,
      child: AuraScaffold(
        scroll: false,
        glowColor: AuraColors.amber,
        glowAlignment: const Alignment(0, -0.6),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: bonus.when(
                  loading: () => SizedBox(height: constraints.maxHeight, child: const Center(child: CircularProgressIndicator())),
                  error: (_, _) => SizedBox(
                    height: constraints.maxHeight,
                    child: ErrorRetry(onRetry: () => ref.invalidate(welcomeBonusProvider)),
                  ),
                  data: (w) => _content(w),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _content(WelcomeBonus? w) {
    final grant = w?.grant;
    final now = w?.claimableNow ?? const WelcomeAmounts();
    final live = w != null && w.isLive && !now.isEmpty;
    final spin = w?.freeSpin;
    final spinOpen = spin != null && spin.available;
    // Fall back to the grant's totals when nothing is due right now.
    final tokens = live ? now.tokens : (grant?.tokensTotal ?? 0);
    final gold = live ? now.gold : (grant?.goldTotal ?? 0);
    final powerUps = live ? now.powerUpQty : (grant?.powerUpQty ?? 0);
    final String headline;
    final String body;
    if (w == null) {
      headline = 'Welcome!';
      body = "There's no welcome bonus on this account.";
    } else if (grant!.status == 'blocked') {
      headline = 'Welcome!';
      body = grant.blockedReason == 'device_dupe'
          ? 'This device already received a welcome bonus.'
          : "The welcome bonus isn't available for this account.";
    } else if (grant.status == 'expired') {
      headline = 'Welcome!';
      body = 'This welcome bonus has expired.';
    } else if (live) {
      headline = "You're all set!";
      body = "Here's your starter pack to jump straight into the action.";
    } else if (spinOpen) {
      headline = 'One more gift!';
      body = 'Your free Welcome-wheel spin is waiting.';
    } else {
      headline = "You're all set!";
      body = 'Your welcome bonus has been paid.';
    }
    final notes = <String>[
      if (live && grant!.status == 'pending' && grant.expiresAt != null && grant.expiresAt!.isAfter(ServerClock.now()))
        'Claim within ${rewardCountdown(grant.expiresAt!)}',
      if (w != null && w.nextDueAt != null && w.nextDueAt!.isAfter(ServerClock.now()))
        'Next part in ${rewardCountdown(w.nextDueAt!)}',
      if (w != null && w.waitingForFirstMatch) 'Play a match to unlock the rest',
    ];
    final showTiles = w != null && (grant!.status != 'blocked' && grant.status != 'expired');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Center(
          child: Text(
            'WELCOME GIFT',
            style: TextStyle(color: AuraColors.amber, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
        ),
        const SizedBox(height: 24),
        const Center(child: _StarBadge(size: 150)),
        const SizedBox(height: 28),
        Text(headline, textAlign: TextAlign.center, style: AuraText.headline.copyWith(fontSize: 31)),
        const SizedBox(height: 10),
        Text(body, textAlign: TextAlign.center, style: AuraText.body.copyWith(color: AuraColors.textSecondary)),
        const SizedBox(height: 28),
        if (showTiles)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (tokens > 0 || (gold == 0 && powerUps == 0))
                Expanded(
                  child: _RewardTile(
                    glyph: const CurrencyGlyph(kind: Currency.gems, size: 26),
                    amount: '+${formatAmount(tokens)}',
                    label: 'Tokens',
                  ),
                ),
              if (gold > 0) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _RewardTile(
                    glyph: const CurrencyGlyph(kind: Currency.gold, size: 26),
                    amount: '+${formatAmount(gold)}',
                    label: 'Gold',
                  ),
                ),
              ],
              if (powerUps > 0) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _RewardTile(
                    glyph: const Icon(Icons.bolt_rounded, color: AuraColors.accentGlow, size: 26),
                    amount: '+$powerUps',
                    label: 'Boosts',
                  ),
                ),
              ],
              if (spin != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _RewardTile(
                    glyph: const Icon(Icons.refresh, color: AuraColors.accentGlow, size: 26),
                    amount: spinOpen ? '+1' : '✓',
                    label: 'Free spin',
                  ),
                ),
              ],
            ],
          ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(notes.join('  ·  '), textAlign: TextAlign.center, style: AuraText.cardSub),
        ],
        const SizedBox(height: 28),
        if (live)
          GradientButton(label: 'Claim', loading: _claiming, onPressed: () => _claim(w))
        else if (spinOpen)
          GradientButton(label: 'Spin the wheel', onPressed: () => _spin(spin))
        else
          GradientButton(label: 'Continue', onPressed: _close),
        if (live || spinOpen) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: _claiming ? null : _close,
            child: const Text('Later', style: TextStyle(color: AuraColors.textSecondary)),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({
    required this.glyph,
    required this.amount,
    required this.label,
  });

  final Widget glyph;
  final String amount;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 26, child: Center(child: glyph)),
          const SizedBox(height: 8),
          Text(
            amount,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: AuraText.caption),
        ],
      ),
    );
  }
}

/// Celebratory badge: sparkle rays behind a rotated gradient rounded-square
/// containing an upright white star.
class _StarBadge extends StatelessWidget {
  const _StarBadge({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final tileSize = size * 0.62;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Faint sparkle rays behind.
          SizedBox(
            width: size,
            height: size,
            child: CustomPaint(painter: _SparklePainter()),
          ),
          // Rotated rounded-square with brand gradient.
          Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: tileSize,
              height: tileSize,
              decoration: BoxDecoration(
                gradient: AuraGradients.brand,
                // Softer corners than a circle so the diamond points read (mockup).
                borderRadius: BorderRadius.circular(tileSize * 0.3),
                boxShadow: [
                  BoxShadow(
                    color: AuraColors.brandPink.withValues(alpha: 0.4),
                    blurRadius: 32,
                    spreadRadius: -4,
                  ),
                ],
              ),
            ),
          ),
          // Upright star.
          Icon(Icons.star, color: Colors.white, size: tileSize * 0.5),
          // Small token accent.
          Positioned(
            right: size * 0.06,
            top: size * 0.12,
            child: CurrencyGlyph(kind: Currency.gems, size: size * 0.12),
          ),
          // Small coin accent.
          Positioned(
            left: size * 0.08,
            bottom: size * 0.14,
            child: Icon(Icons.monetization_on,
                color: AuraColors.gold, size: size * 0.11),
          ),
        ],
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = AuraColors.amber.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const rays = 8;
    final inner = size.width * 0.42;
    final outer = size.width * 0.5;
    for (var i = 0; i < rays; i++) {
      final angle = (math.pi * 2 / rays) * i + math.pi / 8;
      final p1 = center + Offset(math.cos(angle), math.sin(angle)) * inner;
      final p2 = center + Offset(math.cos(angle), math.sin(angle)) * outer;
      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
