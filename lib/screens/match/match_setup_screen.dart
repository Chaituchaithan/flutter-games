import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../widgets/aura.dart';

/// Match setup — a 3-step flow (players → stake → buy-in) presented as a
/// standalone screen. On completion navigate to Routes.matchPreview.
/// See docs/DESIGN_SPEC.md §9-11.
class MatchSetupScreen extends StatefulWidget {
  const MatchSetupScreen({super.key});

  @override
  State<MatchSetupScreen> createState() => _MatchSetupScreenState();
}

class _MatchSetupScreenState extends State<MatchSetupScreen> {
  int _step = 0;
  int _players = 2;
  bool _isTokens = true;
  int _stake = 200;

  static const int _minStake = 50;
  static const int _maxStake = 5000;
  static const int _stakeStep = 50;

  static const _tiers = <(int, String)>[
    (50, 'pot 100'),
    (100, 'pot 200'),
    (200, 'pot 400'),
    (500, 'pot 1,000'),
    (1000, 'pot 2,000'),
    (2000, 'pot 4,000'),
  ];

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _selectPlayers(int count) {
    setState(() {
      _players = count;
      _step = 1;
    });
  }

  void _selectCurrency(bool tokens) {
    setState(() {
      _isTokens = tokens;
      _step = 2;
    });
  }

  void _setStake(int value) {
    setState(() => _stake = value.clamp(_minStake, _maxStake));
  }

  String get _stepPill => switch (_step) {
        0 => '1/3',
        1 => '2/3',
        _ => '3/3 · buy-in',
      };

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          _header(),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(sizeFactor: anim, child: child),
            ),
            child: KeyedSubtree(
              key: ValueKey<int>(_step),
              child: switch (_step) {
                0 => _stepPlayers(),
                1 => _stepCurrency(),
                _ => _stepBuyIn(),
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton(
          onPressed: _back,
          style: TextButton.styleFrom(
            foregroundColor: AuraColors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 40),
          ),
          child: const Text(
            '‹ back',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: AuraGlass.decoration(radius: 20, shadow: false),
          child: Text(
            _stepPill,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: AuraColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _titleBlock(String title, String sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AuraText.title),
        const SizedBox(height: 6),
        Text(sub, style: AuraText.body),
        const SizedBox(height: 20),
      ],
    );
  }

  // ---- Step 0: players ----
  Widget _stepPlayers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titleBlock('How many players?', 'Pick the match size'),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _bigOptionCard(
                  selected: _players == 2,
                  onTap: () => _selectPlayers(2),
                  big: '2',
                  title: 'Players',
                  sub: '1v1',
                  dots: 2,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _bigOptionCard(
                  selected: _players == 4,
                  onTap: () => _selectPlayers(4),
                  big: '4',
                  title: 'Players',
                  sub: 'free-for-all',
                  dots: 4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bigOptionCard({
    required bool selected,
    required VoidCallback onTap,
    required String big,
    required String title,
    required String sub,
    required int dots,
  }) {
    const dotColors = [
      AuraColors.avatarPurple,
      AuraColors.avatarPink,
      AuraColors.avatarBlue,
      AuraColors.avatarOrange,
    ];
    return _SelectableCard(
      selected: selected,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            big,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: AuraColors.textPrimary,
              fontSize: 44,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          Text('$title · $sub', style: AuraText.cardSub),
          const SizedBox(height: 14),
          Row(
            children: List.generate(dots, (i) {
              return Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: dotColors[i % dotColors.length],
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ---- Step 1: currency ----
  Widget _stepCurrency() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titleBlock('Choose your stake', 'Token or Gold buy-in'),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _currencyCard(
                  selected: _isTokens,
                  onTap: () => _selectCurrency(true),
                  icon: Icons.diamond,
                  iconColor: AuraColors.gems,
                  title: 'Tokens',
                  balance: 'Balance 10,000',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _currencyCard(
                  selected: !_isTokens,
                  onTap: () => _selectCurrency(false),
                  icon: Icons.monetization_on,
                  iconColor: AuraColors.gold,
                  title: 'Gold',
                  balance: 'Balance 3,000',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _currencyCard({
    required bool selected,
    required VoidCallback onTap,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String balance,
  }) {
    return _SelectableCard(
      selected: selected,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 34),
          const SizedBox(height: 14),
          Text(title, style: AuraText.cardTitle),
          const SizedBox(height: 4),
          Text(balance, style: AuraText.cardSub),
        ],
      ),
    );
  }

  // ---- Step 2: buy-in ----
  Widget _stepBuyIn() {
    final currency = _isTokens ? 'Tokens' : 'Gold';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titleBlock('How many tokens?', '$_players Players · $currency'),
        const SectionHeader('Pick a tier'),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: [
            for (final (amount, pot) in _tiers)
              _tierChip(amount: amount, pot: pot),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionHeader('Custom amount'),
            Text(
              'min 50 · max 5,000',
              style: AuraText.cardSub.copyWith(fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _stepperRow(),
        const SizedBox(height: 22),
        _summaryCard(),
        const SizedBox(height: 22),
        GradientButton(
          label: 'Preview match →',
          onPressed: () => Navigator.pushNamed(context, Routes.matchPreview),
        ),
      ],
    );
  }

  Widget _tierChip({required int amount, required String pot}) {
    final selected = _stake == amount;
    final label = amount >= 1000 ? '${amount ~/ 1000}k' : '$amount';
    return _SelectableCard(
      selected: selected,
      radius: 16,
      padding: const EdgeInsets.all(10),
      onTap: () => _setStake(amount),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: AuraColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(pot, style: AuraText.cardSub.copyWith(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _stepperRow() {
    return Row(
      children: [
        _circleStepButton(
          icon: Icons.remove,
          onTap: () => _setStake(_stake - _stakeStep),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: AuraCard(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(
                _fmt(_stake),
                style: TextStyle(
                  fontFamily: AuraText.displayFamily,
                  color: AuraColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        _circleStepButton(
          icon: Icons.add,
          onTap: () => _setStake(_stake + _stakeStep),
        ),
      ],
    );
  }

  Widget _circleStepButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: AuraGlass.decoration(radius: 14, shadow: false),
          child: Icon(icon, color: AuraColors.textPrimary, size: 24),
        ),
      ),
    );
  }

  Widget _summaryCard() {
    return AuraCard(
      child: Column(
        children: [
          _summaryRow('Your stake', _fmt(_stake)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: AuraColors.cardBorder, height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total pot · 2×', style: AuraText.body.copyWith(color: AuraColors.textSecondary)),
              Text(
                _fmt(_stake * 2),
                style: TextStyle(
                  fontFamily: AuraText.displayFamily,
                  color: AuraColors.amber,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AuraText.body),
        Text(
          value,
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: AuraColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// A tappable card with a brand-gradient border when [selected].
class _SelectableCard extends StatelessWidget {
  const _SelectableCard({
    required this.child,
    required this.selected,
    required this.onTap,
    this.radius = 20,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final bool selected;
  final VoidCallback onTap;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            gradient: selected ? AuraGradients.brand : null,
            color: selected ? null : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              // Opaque dark interior so the (selected) brand gradient reads as a
              // thin border only. `color` is ignored when a `gradient` is set, so
              // this must NOT use a translucent glass gradient here.
              color: const Color(0xFF14101F),
              borderRadius: BorderRadius.circular(radius - 1.5),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
