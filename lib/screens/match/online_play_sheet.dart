import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/store_repository.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';
import '../../app/game_area.dart';
import '../../app/game_module.dart';
import '../../configs/games/core/active_game.dart';

/// Online Play — the mockup's `opOpen` flow as a single modal bottom sheet:
/// currency → side (White/Black) → stake → preview → Find match (no players
/// step: chess is 2P).
/// See docs/DESIGN_SPEC.md.
///
/// [onBuyMore] fires when the player taps "Buy more" on the insufficient-balance
/// dialog (the sheet is already closed) — the caller routes to the Store.
Future<void> showOnlinePlaySheet(BuildContext context, {VoidCallback? onBuyMore}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xBD05040C), // rgba(5,4,12,0.74)
    builder: (_) => OnlinePlaySheet(onBuyMore: onBuyMore),
  );
}

class OnlinePlaySheet extends ConsumerStatefulWidget {
  const OnlinePlaySheet({super.key, this.onBuyMore});
  final VoidCallback? onBuyMore;

  @override
  ConsumerState<OnlinePlaySheet> createState() => _OnlinePlaySheetState();
}

class _OnlinePlaySheetState extends ConsumerState<OnlinePlaySheet> {
  // Chess is always 2-player, so the "How many players?" step (0) is skipped —
  // the sheet opens directly on "Choose your stake" (step 1).
  int _step = 1; // 1 currency ("Choose your stake") · 2 side · 3 amount · 4 preview
  final int _players = 2;
  bool _isTokens = true;
  /// The active game's online side options (chess: White / Black); empty =
  /// no side step.
  late final List<OnlineSide> _sides = GameArea.onlineSides(ref.read(activeGameProvider));
  int _sideIdx = 0;
  bool get _hasSides => _sides.isNotEmpty;
  String get _sideLabel => _hasSides ? _sides[_sideIdx].label : '';
  int _stake = 200;

  static const _minStake = 50;
  static const _maxStake = 5000;
  static const _stakeStep = 50;

  static const _tiers = <(int, String)>[
    (50, 'pot 100'),
    (100, 'pot 200'),
    (200, 'pot 400'),
    (500, 'pot 1,000'),
    (1000, 'pot 2,000'),
    (2000, 'pot 4,000'),
  ];

  String get _currency => _isTokens ? 'Tokens' : 'Gold';

  /// Wallet balance for a currency, from the shared wallet (0 until it loads).
  int _walletBalance(bool tokens) => walletBalance(ref, tokens ? Currency.gems : Currency.gold) ?? 0;

  /// Buy-in balance for the chosen currency.
  int get _balance => _walletBalance(_isTokens);

  Future<void> _createGame() async {
    if (_stake > _balance) {
      final buyMore = await showInsufficientBalanceDialog(context);
      if (buyMore == true && mounted) {
        Navigator.of(context).pop(); // close the sheet
        widget.onBuyMore?.call(); // caller routes to Store
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    // The active game's online screen: connect → matchmake → live board.
    final route = GameArea.onlineRoute(ref.read(activeGameProvider));
    if (route == null) return;
    Navigator.pushNamed(context, route, arguments: {
      'stake': _stake,
      'tokens': _isTokens,
      if (_hasSides) 'color': _sides[_sideIdx].value,
    });
  }

  void _back() {
    // Step 1 ("Choose your stake") is the first step now — back from it closes.
    if (_step > 1) {
      // No side step: stake (3) goes straight back to currency (1).
      setState(() => _step = (_step == 3 && !_hasSides) ? 1 : _step - 1);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _setStake(int v) => setState(() => _stake = v.clamp(_minStake, _maxStake));

  String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  (String, String, String) get _headerText => switch (_step) {
    1 => (_hasSides ? '1/3' : '1/2', 'Choose your stake', 'Token or Gold buy-in'),
    2 => ('2/3 · side', 'Choose your side', _sides.first.sub),
    3 => (
      _hasSides ? '3/3 · buy-in' : '2/2 · buy-in',
      _isTokens ? 'How many tokens?' : 'How much gold?',
      '$_players Players · $_currency',
    ),
    _ => ('preview', 'Match preview', ['Online', '${_players}P', _currency, if (_hasSides) _sideLabel].join(' · ')),
  };

  @override
  Widget build(BuildContext context) {
    final (badge, title, sub) = _headerText;
    final maxH = MediaQuery.sizeOf(context).height * 0.9;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF17112C), Color(0xFF0B0916)],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.22))),
              ),
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: _back,
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          _step == 0 ? '‹ close' : '‹ back',
                          style: const TextStyle(
                            color: AuraColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: AuraGlass.decoration(radius: 99, shadow: false),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontFamily: AuraText.displayFamily,
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(title, style: AuraText.title),
                  const SizedBox(height: 6),
                  Text(sub, style: AuraText.body.copyWith(color: AuraColors.textSecondary)),
                  const SizedBox(height: 20),
                  Flexible(
                    child: SingleChildScrollView(
                      child: switch (_step) {
                        1 => _currency_(),
                        2 => _side_(),
                        3 => _stake_(),
                        _ => _preview_(),
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Step 1: currency ("Choose your stake") ──
  Widget _currency_() {
    return Row(
      children: [
        Expanded(
          child: _OptCard(
            selected: _isTokens,
            onTap: () => setState(() {
              _isTokens = true;
              _step = _hasSides ? 2 : 3;
            }),
            child: _currencyContent(Currency.gems, 'Tokens', 'Balance ${_fmt(_walletBalance(true))}'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _OptCard(
            selected: !_isTokens,
            onTap: () => setState(() {
              _isTokens = false;
              _step = _hasSides ? 2 : 3;
            }),
            child: _currencyContent(Currency.gold, 'Gold', 'Balance ${_fmt(_walletBalance(false))}'),
          ),
        ),
      ],
    );
  }

  // Mockup currency card: centred glyph + Space Grotesk 700/17 title + muted
  // balance line.
  Widget _currencyContent(Currency kind, String title, String balance) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CurrencyGlyph(kind: kind, size: 40),
        const SizedBox(height: 10),
        Text(title, style: AuraText.cardTitle.copyWith(fontSize: 17)),
        const SizedBox(height: 4),
        Text(balance, style: AuraText.cardSub.copyWith(fontSize: 12)),
      ],
    );
  }

  // ── Step 2: side (the game's options, e.g. chess White / Black) ──
  Widget _side_() {
    return Row(
      children: [
        for (var i = 0; i < _sides.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: _OptCard(
              selected: _sideIdx == i,
              onTap: () => setState(() {
                _sideIdx = i;
                _step = 3;
              }),
              child: Column(
                children: [
                  _sides[i].icon(48),
                  const SizedBox(height: 10),
                  Text(_sides[i].label, style: AuraText.cardTitle.copyWith(fontSize: 17)),
                  const SizedBox(height: 4),
                  Text(_sides[i].sub, style: AuraText.cardSub.copyWith(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 3: stake ──
  Widget _stake_() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            for (final (amt, pot) in _tiers)
              _OptCard(
                selected: _stake == amt,
                radius: 14,
                padding: const EdgeInsets.all(8),
                onTap: () => _setStake(amt),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      amt >= 1000 ? '${amt ~/ 1000}k' : '$amt',
                      style: TextStyle(
                        fontFamily: AuraText.displayFamily,
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(pot, style: AuraText.cardSub.copyWith(fontSize: 10, color: AuraColors.textMuted)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(child: SectionHeader('Custom amount')),
            const SizedBox(width: 8),
            Text('min 50 · max 5,000', style: AuraText.cardSub.copyWith(fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _stepBtn(Icons.remove, () => _setStake(_stake - _stakeStep)),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: AuraGlass.decoration(radius: 14, shadow: false),
                child: Text(
                  _fmt(_stake),
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            _stepBtn(Icons.add, () => _setStake(_stake + _stakeStep)),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AuraGlass.decoration(
            radius: 16,
            accentGradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AuraColors.brandPurple.withValues(alpha: 0.18), Colors.white.withValues(alpha: 0.03)],
            ),
            shadow: false,
          ),
          child: Column(
            children: [
              _summaryRow('YOUR STAKE', _fmt(_stake), Colors.white),
              const SizedBox(height: 8),
              _summaryRow('TOTAL POT · $_players×', _fmt(_stake * _players), AuraColors.amber),
            ],
          ),
        ),
        const SizedBox(height: 18),
        GradientButton(label: 'Preview match  →', onPressed: () => setState(() => _step = 4)),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
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

  Widget _summaryRow(String label, String value, Color valueColor) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AuraText.cardSub.copyWith(letterSpacing: 0.3))),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: valueColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ── Step 4: preview ──
  Widget _preview_() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: AuraGlass.decoration(radius: AuraRadii.lg),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // The signed-in player.
                  LetterAvatar(letter: ref.watch(currentUserProvider).initials, color: AuraColors.brandPurple, size: 56, glow: true),
                  const SizedBox(width: 20),
                  Text(
                    'VS',
                    style: TextStyle(
                      fontFamily: AuraText.displayFamily,
                      color: AuraColors.textSecondary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
                    ),
                    child: Text(
                      '?',
                      style: TextStyle(
                        fontFamily: AuraText.displayFamily,
                        color: AuraColors.textSecondary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Matching you with $_players players online', style: AuraText.cardSub, textAlign: TextAlign.center),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AuraGlass.decoration(radius: AuraRadii.lg),
          child: Column(
            children: [
              if (_hasSides) ...[
                _infoRow('Your side', _sideLabel),
                _divider(),
              ],
              _infoRow('Entry stake', _fmt(_stake)),
              _divider(),
              _infoRow('Total prize pot', _fmt(_stake * _players), valueColor: AuraColors.amber),
              _divider(),
              _infoRow('Format', 'Winner takes all'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GradientButton(label: 'Find match', onPressed: _createGame),
      ],
    );
  }

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
  );

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AuraText.body.copyWith(color: AuraColors.textSecondary)),
        Text(
          value,
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: valueColor ?? Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Selectable glass card. Matches the mockup `selCard`/`unselCard`: a 2px
/// accent-glow border over a violet→pink tint with a soft purple glow when
/// [selected]; a hairline glass fill otherwise.
class _OptCard extends StatelessWidget {
  const _OptCard({
    required this.child,
    required this.selected,
    required this.onTap,
    this.radius = 18,
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
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: selected
                  ? [AuraColors.brandPurple.withValues(alpha: 0.32), AuraColors.brandPink.withValues(alpha: 0.16)]
                  : [Colors.white.withValues(alpha: 0.09), Colors.white.withValues(alpha: 0.03)],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: selected ? AuraColors.accentGlow : Colors.white.withValues(alpha: 0.22),
              width: selected ? 2 : 1.5,
            ),
            boxShadow: selected
                ? [BoxShadow(color: AuraColors.accentGlow.withValues(alpha: 0.45), blurRadius: 24, spreadRadius: -4)]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
