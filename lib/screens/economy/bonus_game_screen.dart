import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/daily_bonus.dart' show formatAmount;
import '../../data/models/rewards.dart';
import '../../data/repositories/rewards_repository.dart';
import '../../services/app_exception.dart';
import '../../services/rewards_service.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';
import 'rewards_ui.dart';
import '../../services/server_clock.dart';

/// One bonus game — a wheel, scratch card, chest, flip or pick-a-card
/// (07-rewards.md §5). The server draws the prize; this screen only animates
/// `slot_index` and shows `prize`. Free games are opened from their trigger
/// ([trigger] + [triggerRef] go to the play route exactly as given); store
/// games ([trigger] `store`) cost tokens or gold.
class BonusGameScreen extends ConsumerStatefulWidget {
  const BonusGameScreen({super.key, required this.code, required this.trigger, this.triggerRef});

  /// The game's id or code (`welcome_wheel`, `daily_spin`, `scratch_gold`).
  final String code;
  final String trigger;
  final String? triggerRef;

  @override
  ConsumerState<BonusGameScreen> createState() => _BonusGameScreenState();
}

class _BonusGameScreenState extends ConsumerState<BonusGameScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  /// The request is running (the Play button can't be tapped twice: a double
  /// tap on a paid game would pay twice).
  bool _playing = false;
  BonusPlayResult? _result;

  /// Limits after the last play (the reply's `plays_left_today`).
  BonusGameLimits? _limits;

  /// A free play that was used or refused: no second offer.
  bool _spent = false;

  /// Wheel angle before the current spin.
  double _from = 0;
  double _to = 0;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  bool get _free => widget.trigger != 'store';

  Future<void> _play(BonusGame g) async {
    if (_playing || _anim.isAnimating) return;
    setState(() {
      _playing = true;
      _result = null;
    });
    try {
      final r = await ref
          .read(rewardsApiProvider)
          .playBonusGame(widget.code, trigger: widget.trigger, triggerRef: widget.triggerRef);
      if (!mounted) return;
      // Land the wheel's slice under the top pointer, after a few turns.
      _from = _to % (2 * math.pi);
      _to = bonusWheelTarget(_from, r.slotIndex, g.slots);
      setState(() {
        _result = r;
        _limits = (_limits ?? g.me).withPlaysLeft(r.playsLeftToday);
        if (_free) _spent = true;
      });
      await _anim.forward(from: 0);
      if (!mounted) return;
      // Header balance after the animation, from the reply.
      applyRewardToWallet(ref, balances: r.balances);
      ref.invalidate(welcomeBonusProvider);
      ref.invalidate(bonusPlaysProvider);
      ref.invalidate(bonusGamesProvider);
    } on AppException catch (e) {
      if (!mounted) return;
      final issue = bonusPlayIssue(e, cooldownUntil: g.me.cooldownUntil);
      if (issue.kind == RewardIssueKind.notEnoughFunds) {
        unawaited(offerBonusShop(context, ref, g));
        return;
      }
      showRewardIssue(context, issue);
      if (issue.kind == RewardIssueKind.gone && _free) {
        // A free play that isn't there (used, expired): close the game.
        setState(() => _spent = true);
        ref.invalidate(welcomeBonusProvider);
        Navigator.of(context).maybePop();
      } else {
        ref.invalidate(bonusGameProvider(widget.code));
      }
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(bonusGameProvider(widget.code));
    // Back reports whether the free play was used (see openBonusGame).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_playing && !_anim.isAnimating) Navigator.of(context).pop(_spent);
      },
      child: BusyGuard(
        busy: _playing,
        child: AuraScaffold(
          appBar: AuraAppBar(title: game.value?.name ?? 'Bonus game'),
          scroll: true,
          body: AsyncView<BonusGame>(
            value: game,
            onRetry: () => ref.invalidate(bonusGameProvider(widget.code)),
            data: _content,
          ),
        ),
      ),
    );
  }

  Widget _content(BonusGame g) {
    final me = _limits ?? g.me;
    final r = _result;
    final done = r != null && !_anim.isAnimating;
    final blocked = me.blockReason;
    final canPlay = g.supported && blocked == null && !(_free && _spent);
    final String label;
    if (_free && _spent) {
      label = 'Played';
    } else if (blocked != null) {
      label = blockedText(blocked, cooldownUntil: me.cooldownUntil).text ?? 'Not available right now.';
    } else if (g.cost.free) {
      label = g.gameType == 'wheel' ? 'Spin' : 'Play';
    } else {
      label = 'Play for ${bonusCostText(g.cost)}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AuraBadge(
              g.cost.free ? 'FREE' : '${formatAmount(g.cost.amount)} ${g.cost.kind.toUpperCase()}',
              color: AuraColors.amber,
            ),
            if (g.maxPlaysPerDay > 0) AuraBadge('${me.playsLeftToday} PLAYS LEFT TODAY'),
            if (me.pityLeft != null) AuraBadge('RARE GUARANTEED IN ${me.pityLeft} OPENS', color: AuraColors.brandPink),
            if (me.cooldownUntil != null && me.cooldownUntil!.isAfter(ServerClock.now()))
              AuraBadge(
                'NEXT PLAY IN ${rewardCountdown(me.cooldownUntil!).toUpperCase()}',
                color: AuraColors.accentGlow,
              ),
          ],
        ),
        const SizedBox(height: 18),
        AnimatedBuilder(
          animation: _anim,
          builder: (_, _) => g.gameType == 'wheel'
              ? _Wheel(
                  prizes: g.prizes,
                  slots: g.slots,
                  angle: _from + (_to - _from) * Curves.easeOutCubic.transform(_anim.value),
                )
              : _Cells(
                  game: g,
                  revealed: r == null || _anim.value < 0.35 ? null : r.slotIndex,
                  label: r?.prize.label,
                  rarity: r?.prize.rarity,
                ),
        ),
        const SizedBox(height: 18),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: done ? 1 : 0,
          child: AuraCard(
            child: Column(
              children: [
                Text(
                  r == null ? '' : bonusPrizeText(r.prize),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (r != null && r.pityTriggered) ...[
                  const SizedBox(height: 4),
                  const Text('Guaranteed rare prize!', style: TextStyle(color: AuraColors.amber, fontSize: 13)),
                ],
                if (r != null && r.prize.currency == 'token' && r.prize.prizeType == 'gold') ...[
                  const SizedBox(height: 4),
                  Text('Guest accounts get gold prizes as tokens.', style: AuraText.cardSub),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        GradientButton(
          label: label,
          enabled: canPlay && !_anim.isAnimating,
          loading: _playing,
          onPressed: () => _play(g),
        ),
        if (g.hasOdds) ...[
          const SizedBox(height: 22),
          const SectionBar('Odds'),
          const SizedBox(height: 10),
          BonusOddsTable(prizes: g.prizes),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}

/// The wheel: one slice per slot, slot 0 under the top pointer at angle 0.
class _Wheel extends StatelessWidget {
  const _Wheel({required this.prizes, required this.slots, required this.angle});
  final List<BonusPrize> prizes;
  final int slots;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            child: Transform.rotate(
              angle: angle,
              child: CustomPaint(painter: _WheelPainter(prizes, math.max(1, slots))),
            ),
          ),
          const Icon(Icons.arrow_drop_down_rounded, color: Colors.white, size: 54),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.prizes, this.slots);
  final List<BonusPrize> prizes;
  final int slots;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 6;
    final sweep = 2 * math.pi / slots;
    for (var i = 0; i < slots; i++) {
      final prize = i < prizes.length ? prizes[i] : null;
      final start = -math.pi / 2 - sweep / 2 + i * sweep;
      final base = prize == null ? const Color(0xFF2A2440) : bonusRarityColor(prize.rarity);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        sweep,
        true,
        Paint()..color = Color.lerp(base, i.isEven ? Colors.black : Colors.white, 0.12)!,
      );
      // Label along the slice's middle.
      final mid = start + sweep / 2;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(mid + math.pi / 2);
      final tp = TextPainter(
        text: TextSpan(
          text: prize?.label ?? '',
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: math.min(r * sweep * 0.8, r * 0.55));
      tp.paint(canvas, Offset(-tp.width / 2, -r + 14));
      canvas.restore();
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = AuraColors.amber,
    );
    canvas.drawCircle(
      c,
      r * 0.14,
      Paint()..shader = AuraGradients.brand.createShader(Rect.fromCircle(center: c, radius: r * 0.14)),
    );
  }

  @override
  bool shouldRepaint(_WheelPainter o) => o.slots != slots || o.prizes != prizes;
}

/// Scratch cells, chests, flip and pick cards: [revealed] (the play's
/// `slot_index`) turns over and shows the prize.
class _Cells extends StatelessWidget {
  const _Cells({required this.game, this.revealed, this.label, this.rarity});
  final BonusGame game;
  final int? revealed;
  final String? label;
  final String? rarity;

  IconData get _icon => switch (game.gameType) {
    'chest' => Icons.inventory_2_rounded,
    'scratch' => Icons.auto_awesome,
    'flip' => Icons.flip_rounded,
    _ => Icons.style_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final n = math.max(1, game.slots);
    final cols = n <= 3 ? n : (n == 4 ? 2 : 3);
    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: cols <= 2 ? 1.2 : 0.9,
      children: [
        for (var i = 0; i < n; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: i == revealed ? null : AuraGradients.brand,
              color: i == revealed ? bonusRarityColor(rarity ?? 'common') : null,
              border: Border.all(
                color: Colors.white.withValues(alpha: i == revealed ? 0.8 : 0.2),
                width: i == revealed ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(6),
            child: i == revealed
                ? Text(
                    label ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                  )
                : Icon(_icon, color: Colors.white.withValues(alpha: revealed == null ? 0.9 : 0.35), size: 30),
          ),
      ],
    );
  }
}
