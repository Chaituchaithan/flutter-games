import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/store_repository.dart';
import '../../widgets/aura.dart';

/// Season Pass (mockup `isSeason`): "SEASON 4 · Neon Tide" card (tier, XP
/// bar), the Premium-track upsell (or "Premium track active"), then 20 tiers
/// of FREE / PREMIUM rewards.
///
/// Reward states: Claimed (green) · Tap to claim (reached, glowing) ·
/// Premium (reached, needs the pass → unlock dialog) · Locked (not reached,
/// dimmed). Claiming shows a toast and marks it Claimed.
///
/// Navigation: back → Home. "Unlock Premium track" → "Unlock Premium track?"
/// → 950 Gold (not enough → "Not enough balance" → Buy more → Store tab).
///
/// Season progress has no service yet, so it holds the mockup's state
/// (tier 12, 720 / 1,000 XP, free tiers 1–9 claimed) for this session.
class SeasonPassScreen extends ConsumerStatefulWidget {
  const SeasonPassScreen({super.key});

  @override
  ConsumerState<SeasonPassScreen> createState() => _SeasonPassScreenState();
}

enum _Kind { tok, gold, pow, frame, emote, avatar }

class _Reward {
  const _Reward(this.kind, this.label, [this.amount = 0]);
  final _Kind kind;
  final String label;
  final int amount;
}

class _SeasonPassScreenState extends ConsumerState<SeasonPassScreen> {
  static const _tierMax = 20;
  static const _passPrice = 950;

  final int _tier = 12;
  final int _xp = 720;
  bool _passOwned = false;
  final Set<String> _claimed = {for (var i = 1; i <= 9; i++) 'f$i'};

  static String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  static _Reward _tok(int v) => _Reward(_Kind.tok, '${_fmt(v)} Tokens', v);
  static _Reward _gold(int v) => _Reward(_Kind.gold, '${_fmt(v)} Gold', v);

  // Mockup seasonDefs(): free + premium reward per tier.
  static final _free = <_Reward>[
    _tok(150), _tok(200), _gold(40), _tok(300), const _Reward(_Kind.pow, 'Hint Boost'),
    _tok(400), _gold(60), _tok(500), const _Reward(_Kind.pow, 'Time Freeze'), _tok(600),
    _gold(80), _tok(700), const _Reward(_Kind.pow, 'Double XP'), _tok(800), _gold(100),
    _tok(1000), const _Reward(_Kind.pow, 'Streak Shield'), _tok(1200), _gold(150), const _Reward(_Kind.frame, 'Neon Tide frame'),
  ];
  static final _prem = <_Reward>[
    _gold(100), _gold(120), _tok(500), _gold(150), const _Reward(_Kind.pow, 'Double XP'),
    _gold(200), _tok(800), _gold(250), const _Reward(_Kind.pow, 'Extra Spins'), _gold(300),
    const _Reward(_Kind.emote, 'Tidal Wave emote'), _gold(350), _tok(1500), _gold(400), const _Reward(_Kind.pow, 'Streak Shield'),
    _gold(500), const _Reward(_Kind.avatar, 'Abyss avatar'), _gold(600), _gold(800), const _Reward(_Kind.frame, 'Legendary Tide frame'),
  ];

  int _goldBalance() => walletBalance(ref, Currency.gold) ?? 0;

  void _claim(String key, _Reward r) {
    if (_claimed.contains(key)) return;
    setState(() => _claimed.add(key));
    final label = switch (r.kind) {
      _Kind.tok => '+${_fmt(r.amount)} Tokens',
      _Kind.gold => '+${_fmt(r.amount)} Gold',
      _ => '${r.label} unlocked',
    };
    showAuraToast(context, 'Tier reward claimed · $label', kind: r.kind == _Kind.gold ? AuraToastKind.gold : AuraToastKind.success);
  }

  Future<void> _unlockPass() async {
    final ok = await showAuraDialog(
      context,
      icon: Icons.star_rounded,
      title: 'Unlock Premium track?',
      body: '950 Gold unlocks every premium reward for Season 4, including the Legendary Tide frame at tier 20.',
      primaryLabel: 'Unlock for 950 Gold',
      secondaryLabel: 'Not now',
      tone: AuraDialogTone.warning,
    );
    if (ok != true || !mounted) return;
    if (_goldBalance() < _passPrice) {
      final buyMore = await showInsufficientBalanceDialog(context);
      if (buyMore == true && mounted) Navigator.pop(context, 'store'); // Home opens the Store tab
      return;
    }
    setState(() => _passOwned = true);
    showAuraToast(context, 'Premium track unlocked', kind: AuraToastKind.gold);
  }

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      glowColor: AuraColors.brandPink,
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          _header(),
          const SizedBox(height: 18),
          _seasonCard(),
          const SizedBox(height: 12),
          if (_passOwned) _passActive() else _passUpsell(),
          const SizedBox(height: 22),
          _columnsHeader(),
          const SizedBox(height: 8),
          for (var i = 0; i < _tierMax; i++) ...[
            _tierRow(i + 1),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Season Pass', style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Text('Ends in 12d 04h', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.75))),
        ),
      ],
    );
  }

  Widget _seasonCard() {
    final pct = (_xp / 1000).clamp(0.0, 1.0);
    return DecoratedBox(
      // Purple drop shadow on an opaque base (no show-through panel).
      decoration: BoxDecoration(
        color: const Color(0xFF0D0A18),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: AuraColors.brandPurple.withValues(alpha: 0.8), blurRadius: 40, spreadRadius: -18, offset: const Offset(0, 20))],
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AuraColors.brandPurple.withValues(alpha: 0.30),
              AuraColors.brandPink.withValues(alpha: 0.14),
              const Color(0xFFFB923C).withValues(alpha: 0.10),
            ],
            stops: const [0, 0.6, 1],
          ),
          border: Border.all(color: AuraColors.accentGlow.withValues(alpha: 0.45)),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [AuraColors.brandPink.withValues(alpha: 0.4), AuraColors.brandPink.withValues(alpha: 0)], stops: const [0, 0.7]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SEASON 4', style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: 1.4, color: Colors.white.withValues(alpha: 0.6))),
                  const SizedBox(height: 4),
                  Text('Neon Tide', style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 30, height: 1, color: Colors.white)),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Current tier', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6))),
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(text: '$_tier', style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 26, height: 1, color: Colors.white)),
                                TextSpan(text: ' / $_tierMax', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
                              ]),
                            ),
                          ],
                        ),
                      ),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: _fmt(_xp), style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, color: Colors.white)),
                          const TextSpan(text: ' / 1,000 XP'),
                        ]),
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: pct,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          gradient: const LinearGradient(colors: [AuraColors.brandPurple, AuraColors.brandPink, Color(0xFFFB923C)]),
                          boxShadow: [BoxShadow(color: AuraColors.brandPink.withValues(alpha: 0.7), blurRadius: 14)],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Win matches to earn XP · +50 per victory, +20 per loss', style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.55))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passUpsell() {
    return GestureDetector(
      onTap: _unlockPass,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFFFBBF24).withValues(alpha: 0.22), const Color(0xFFF59E0B).withValues(alpha: 0.06)],
          ),
          border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)]),
              ),
              child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFF1A1206), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Unlock Premium track', style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 14.5, color: Colors.white)),
                  const Text('20 extra rewards · Legendary frame at tier 20', style: TextStyle(fontSize: 12, color: Color(0xFFFDE68A))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)]),
              ),
              child: Text('950 Gold', style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 12.5, color: const Color(0xFF1A1206))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passActive() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AuraColors.green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AuraColors.green.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AuraColors.green, size: 18),
          const SizedBox(width: 10),
          Text('Premium track active', style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 13.5, color: Colors.white)),
          const Spacer(),
          Flexible(
            child: Text('All 40 rewards unlockable', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
          ),
        ],
      ),
    );
  }

  Widget _columnsHeader() {
    final style = TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: 0.8);
    return Row(
      children: [
        const SizedBox(width: 34 + 10),
        Expanded(child: Text('FREE', style: style.copyWith(color: Colors.white.withValues(alpha: 0.45)))),
        const SizedBox(width: 10),
        Expanded(child: Text('PREMIUM', style: style.copyWith(color: const Color(0xFFFDE68A)))),
      ],
    );
  }

  Widget _tierRow(int n) {
    final reached = n <= _tier;
    final current = n == _tier;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: current ? AuraGradients.brand : null,
                color: current ? null : (reached ? AuraColors.accentGlow.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.06)),
                border: Border.all(color: reached ? AuraColors.accentGlow.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.12)),
                boxShadow: current ? [BoxShadow(color: AuraColors.brandPink.withValues(alpha: 0.9), blurRadius: 18, spreadRadius: -4)] : null,
              ),
              child: Text(
                '$n',
                style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 13, color: reached ? Colors.white : Colors.white.withValues(alpha: 0.4)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: _rewardCard('f$n', _free[n - 1], n, premium: false)),
          const SizedBox(width: 10),
          Expanded(child: _rewardCard('p$n', _prem[n - 1], n, premium: true)),
        ],
      ),
    );
  }

  Widget _rewardCard(String key, _Reward r, int tierN, {required bool premium}) {
    final reached = tierN <= _tier;
    final claimed = _claimed.contains(key);
    final needPass = premium && !_passOwned;
    final claimable = reached && !claimed && !needPass;
    final status = claimed ? 'Claimed' : (!reached ? 'Locked' : (needPass ? 'Premium' : 'Tap to claim'));
    final c = switch (r.kind) {
      _Kind.tok => const Color(0xFF22D3EE),
      _Kind.gold => const Color(0xFFFBBF24),
      _Kind.pow => AuraColors.accentGlow,
      _ => const Color(0xFFF472B6),
    };
    final iconColors = switch (r.kind) {
      _Kind.tok => const [Color(0xFF22D3EE), Color(0xFF3B82F6)],
      _Kind.gold => const [Color(0xFFFDE68A), Color(0xFFF59E0B)],
      _Kind.pow => const [AuraColors.brandPurple, AuraColors.brandPink],
      _ => const [AuraColors.brandPink, Color(0xFFFB923C)],
    };
    final glyph = switch (r.kind) {
      _Kind.tok => 'T',
      _Kind.gold => 'G',
      _Kind.pow => '⚡',
      _ => '★',
    };
    final card = Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: claimable
            ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.withValues(alpha: 0.19), c.withValues(alpha: 0.05)])
            : (!claimed && premium
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [const Color(0xFFFBBF24).withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.02)],
                  )
                : null),
        color: claimable || (!claimed && premium) ? null : (claimed ? AuraColors.green.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.04)),
        border: Border.all(
          color: claimable
              ? c
              : claimed
                  ? AuraColors.green.withValues(alpha: 0.35)
                  : (premium ? const Color(0xFFFBBF24).withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.1)),
          width: claimable ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: iconColors),
                ),
                child: Text(
                  glyph,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: r.kind == _Kind.gold ? const Color(0xFF1A1206) : Colors.white,
                  ),
                ),
              ),
              if (claimed) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_rounded, size: 16, color: AuraColors.green),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(r.label, style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.25, color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            status,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: claimed
                  ? AuraColors.green
                  : claimable
                      ? Colors.white
                      : (needPass && reached ? const Color(0xFFFDE68A) : Colors.white.withValues(alpha: 0.4)),
            ),
          ),
        ],
      ),
    );
    final tappable = claimable || (needPass && reached);
    return GestureDetector(
      onTap: !tappable ? null : (claimable ? () => _claim(key, r) : _unlockPass),
      child: Opacity(
        opacity: reached ? 1 : 0.5,
        // Claimable rewards glow in their colour (shadow outside only).
        child: claimable
            ? DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: const Color(0xFF0D0A18),
                  boxShadow: [BoxShadow(color: c.withValues(alpha: 0.9), blurRadius: 22, spreadRadius: -8)],
                ),
                child: card,
              )
            : card,
      ),
    );
  }
}
