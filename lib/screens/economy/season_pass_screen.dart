import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Season pass reward track. See docs/DESIGN_SPEC.md (v2 §Season Pass).
class SeasonPassScreen extends StatelessWidget {
  const SeasonPassScreen({super.key});

  static const List<_Tier> _tiers = [
    _Tier(1,
        _Reward(_RType.tokens, '150 Tokens', _RState.claimed),
        _Reward(_RType.gold, '100 Gold', _RState.premium)),
    _Tier(2,
        _Reward(_RType.tokens, '200 Tokens', _RState.claimed),
        _Reward(_RType.gold, '120 Gold', _RState.premium)),
    _Tier(3,
        _Reward(_RType.gold, '40 Gold', _RState.claimed),
        _Reward(_RType.tokens, '500 Tokens', _RState.premium)),
    _Tier(4,
        _Reward(_RType.tokens, '300 Tokens', _RState.claimed),
        _Reward(_RType.gold, '150 Gold', _RState.premium)),
    _Tier(5,
        _Reward(_RType.boost, 'Hint Boost', _RState.claimed),
        _Reward(_RType.boost, 'Double XP', _RState.premium)),
    _Tier(6,
        _Reward(_RType.tokens, '400 Tokens', _RState.claimed),
        _Reward(_RType.gold, '200 Gold', _RState.premium)),
    _Tier(7,
        _Reward(_RType.gold, '60 Gold', _RState.claimed),
        _Reward(_RType.tokens, '800 Tokens', _RState.premium)),
    _Tier(8,
        _Reward(_RType.tokens, '500 Tokens', _RState.claimed),
        _Reward(_RType.gold, '250 Gold', _RState.premium)),
    _Tier(9,
        _Reward(_RType.boost, 'Time Freeze', _RState.claimed),
        _Reward(_RType.boost, 'Extra Spins', _RState.premium)),
    _Tier(10,
        _Reward(_RType.tokens, '600 Tokens', _RState.tapToClaim),
        _Reward(_RType.gold, '300 Gold', _RState.premium)),
    _Tier(11,
        _Reward(_RType.gold, '80 Gold', _RState.tapToClaim),
        _Reward(_RType.cosmetic, 'Tidal Wave emote', _RState.premium)),
    _Tier(12,
        _Reward(_RType.tokens, '700 Tokens', _RState.tapToClaim),
        _Reward(_RType.gold, '350 Gold', _RState.premium)),
    _Tier(13,
        _Reward(_RType.boost, 'Double XP', _RState.locked),
        _Reward(_RType.tokens, '1,500 Tokens', _RState.locked)),
    _Tier(14,
        _Reward(_RType.tokens, '800 Tokens', _RState.locked),
        _Reward(_RType.gold, '400 Gold', _RState.locked)),
    _Tier(15,
        _Reward(_RType.gold, '100 Gold', _RState.locked),
        _Reward(_RType.boost, 'Streak Shield', _RState.locked)),
    _Tier(16,
        _Reward(_RType.tokens, '1,000 Tokens', _RState.locked),
        _Reward(_RType.gold, '500 Gold', _RState.locked)),
    _Tier(17,
        _Reward(_RType.boost, 'Streak Shield', _RState.locked),
        _Reward(_RType.cosmetic, 'Abyss avatar', _RState.locked)),
    _Tier(18,
        _Reward(_RType.tokens, '1,200 Tokens', _RState.locked),
        _Reward(_RType.gold, '600 Gold', _RState.locked)),
    _Tier(19,
        _Reward(_RType.gold, '150 Gold', _RState.locked),
        _Reward(_RType.gold, '800 Gold', _RState.locked)),
    _Tier(20,
        _Reward(_RType.cosmetic, 'Neon Tide frame', _RState.locked),
        _Reward(_RType.cosmetic, 'Legendary Tide frame', _RState.locked)),
  ];

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: AuraAppBar(
        title: 'Season Pass',
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: AuraGlass.decoration(radius: 20, shadow: false),
          child: const Text(
            'Ends in 12d 04h',
            style: TextStyle(
              color: AuraColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          const _Hero(),
          const SizedBox(height: 16),
          const _PremiumUnlock(),
          const SizedBox(height: 20),
          Row(
            children: [
              const SizedBox(width: 44),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text('FREE', style: AuraText.section),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text('PREMIUM', style: AuraText.section.copyWith(color: AuraColors.goldLight)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final t in _tiers) ...[
            _TierRow(tier: t),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AuraColors.brandPurple.withValues(alpha: 0.32),
          AuraColors.brandPurple.withValues(alpha: 0.10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SEASON 4', style: AuraText.section.copyWith(letterSpacing: 1.4)),
          const SizedBox(height: 4),
          Text('Neon Tide', style: AuraText.headline.copyWith(fontSize: 30)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current tier',
                    style: TextStyle(color: AuraColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '12',
                        style: TextStyle(
                          fontFamily: AuraText.displayFamily,
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '/ 20',
                        style: TextStyle(color: AuraColors.textSecondary, fontSize: 15),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: '720',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(
                      text: ' / 1,000 XP',
                      style: TextStyle(color: AuraColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _ProgressBar(fraction: 0.72),
          const SizedBox(height: 10),
          const Text(
            'Win matches to earn XP · +50 per victory, +20 per loss',
            style: TextStyle(color: AuraColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: AuraColors.pagerInactive,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            Container(
              height: 10,
              width: constraints.maxWidth * fraction,
              decoration: BoxDecoration(
                gradient: AuraGradients.brand,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PremiumUnlock extends StatelessWidget {
  const _PremiumUnlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AuraColors.gold.withValues(alpha: 0.20),
            AuraColors.gold.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AuraColors.gold.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AuraColors.gold.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.star, color: AuraColors.gold, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Unlock Premium track',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '20 extra rewards · Legendary frame at tier 20',
                  style: AuraText.cardSub,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AuraColors.gold,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '950 Gold',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _RType { tokens, gold, boost, cosmetic }

enum _RState { claimed, tapToClaim, premium, locked }

class _Reward {
  const _Reward(this.type, this.label, this.state);
  final _RType type;
  final String label;
  final _RState state;
}

class _Tier {
  const _Tier(this.tier, this.free, this.premium);
  final int tier;
  final _Reward free;
  final _Reward premium;
}

class _TierRow extends StatelessWidget {
  const _TierRow({required this.tier});
  final _Tier tier;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Center(
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AuraColors.chipDark,
                  shape: BoxShape.circle,
                  border: Border.all(color: AuraColors.cardBorder),
                ),
                child: Center(
                  child: Text(
                    '${tier.tier}',
                    style: const TextStyle(
                      color: AuraColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: _RewardCell(reward: tier.free)),
          const SizedBox(width: 10),
          Expanded(child: _RewardCell(reward: tier.premium)),
        ],
      ),
    );
  }
}

class _RewardCell extends StatelessWidget {
  const _RewardCell({required this.reward});
  final _Reward reward;

  @override
  Widget build(BuildContext context) {
    final locked = reward.state == _RState.locked || reward.state == _RState.premium;
    return Opacity(
      opacity: locked ? 0.62 : 1,
      child: AuraCard(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            _typeIcon(),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reward.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _stateLine(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stateLine() {
    late final String text;
    late final Color color;
    switch (reward.state) {
      case _RState.claimed:
        text = 'Claimed';
        color = AuraColors.green;
      case _RState.tapToClaim:
        text = 'Tap to claim';
        color = AuraColors.brandPink;
      case _RState.premium:
        text = 'Premium';
        color = AuraColors.amber;
      case _RState.locked:
        text = 'Locked';
        color = AuraColors.textSecondary;
    }
    return Row(
      children: [
        if (reward.state == _RState.premium || reward.state == _RState.locked) ...[
          Icon(Icons.lock, size: 10, color: color),
          const SizedBox(width: 3),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _typeIcon() {
    late final Color color;
    late final Widget glyph;
    switch (reward.type) {
      case _RType.tokens:
        color = AuraColors.gems;
        glyph = const Text('T', style: TextStyle(color: AuraColors.gems, fontSize: 13, fontWeight: FontWeight.w900));
      case _RType.gold:
        color = AuraColors.gold;
        glyph = const Text('G', style: TextStyle(color: AuraColors.gold, fontSize: 13, fontWeight: FontWeight.w900));
      case _RType.boost:
        color = AuraColors.amber;
        glyph = const Icon(Icons.bolt, color: AuraColors.amber, size: 16);
      case _RType.cosmetic:
        color = AuraColors.brandPurple;
        glyph = const Icon(Icons.star, color: AuraColors.brandPurple, size: 15);
    }
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: glyph,
    );
  }
}
