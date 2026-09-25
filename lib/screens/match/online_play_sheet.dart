import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../data/repositories/store_repository.dart';
import '../../widgets/aura.dart';

/// Online Play — the mockup's `opOpen` flow as a single modal bottom sheet:
/// players → currency → stake → preview → Create game. See docs/VERIFICATION_AUDIT.md §C.1.
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
  int _step = 0; // 0 players · 1 currency · 2 stake · 3 preview
  int _players = 2;
  bool _isTokens = true;
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

  /// Wallet balance for a currency, read from the shared wallet (falls back to
  /// the demo balances while it loads).
  int _walletBalance(bool tokens) {
    final s = ref.read(walletProvider).maybeWhen(
          data: (w) => tokens ? w.gems : w.gold,
          orElse: () => tokens ? '5,000' : '2,000',
        );
    return int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

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
    Navigator.pushNamed(context, Routes.matchmaking);
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
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
        0 => ('1 / 3', 'How many players?', 'Pick the match size'),
        1 => ('2 / 3', 'Choose your stake', 'Token or Gold buy-in'),
        2 => ('3 / 3 · buy-in', 'How many $_currency?', '$_players Players · $_currency'),
        _ => ('preview', 'Match preview', 'Online · ${_players}P · $_currency'),
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
                          style: const TextStyle(color: AuraColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
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
                        0 => _players_(),
                        1 => _currency_(),
                        2 => _stake_(),
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

  // ── Step 0: players ──
  Widget _players_() {
    return Row(
      children: [
        Expanded(
          child: _OptCard(
            selected: _players == 2,
            onTap: () => setState(() { _players = 2; _step = 1; }),
            child: _playerContent('2', '1v1', 2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _OptCard(
            selected: _players == 4,
            onTap: () => setState(() { _players = 4; _step = 1; }),
            child: _playerContent('4', 'free-for-all', 4),
          ),
        ),
      ],
    );
  }

  Widget _playerContent(String big, String sub, int dots) {
    const colors = [AuraColors.avatarPurple, AuraColors.avatarBlue, AuraColors.avatarOrange, AuraColors.avatarGreen];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(big, style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 40, fontWeight: FontWeight.w700, height: 1)),
        const SizedBox(height: 8),
        Text('Players · $sub', style: AuraText.cardSub),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < dots; i++)
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Container(width: 11, height: 11, decoration: BoxDecoration(color: colors[i % 4], shape: BoxShape.circle)),
              ),
          ],
        ),
      ],
    );
  }

  // ── Step 1: currency ──
  Widget _currency_() {
    return Row(
      children: [
        Expanded(
          child: _OptCard(
            selected: _isTokens,
            onTap: () => setState(() { _isTokens = true; _step = 2; }),
            child: _currencyContent(Currency.gems, 'Tokens', 'Balance ${_fmt(_walletBalance(true))}'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _OptCard(
            selected: !_isTokens,
            onTap: () => setState(() { _isTokens = false; _step = 2; }),
            child: _currencyContent(Currency.gold, 'Gold', 'Balance ${_fmt(_walletBalance(false))}'),
          ),
        ),
      ],
    );
  }

  Widget _currencyContent(Currency kind, String title, String balance) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CurrencyGlyph(kind: kind, size: 34),
        const SizedBox(height: 14),
        Text(title, style: AuraText.cardTitle),
        const SizedBox(height: 4),
        Text(balance, style: AuraText.cardSub),
      ],
    );
  }

  // ── Step 2: stake ──
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
                radius: 16,
                padding: const EdgeInsets.all(8),
                onTap: () => _setStake(amt),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(amt >= 1000 ? '${amt ~/ 1000}k' : '$amt',
                        style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(pot, style: AuraText.cardSub.copyWith(fontSize: 11)),
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
                child: Text(_fmt(_stake),
                    style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
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
        GradientButton(label: 'Preview match  →', onPressed: () => setState(() => _step = 3)),
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
        Text(value, style: TextStyle(fontFamily: AuraText.displayFamily, color: valueColor, fontSize: 18, fontWeight: FontWeight.w700)),
      ],
    );
  }

  // ── Step 3: preview ──
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
                  const LetterAvatar(letter: 'NR', color: AuraColors.brandPurple, size: 56, glow: true),
                  const SizedBox(width: 20),
                  Text('VS', style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.textSecondary, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 3)),
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
                    child: Text('?', style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.textSecondary, fontSize: 24, fontWeight: FontWeight.w700)),
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
              _infoRow('Entry stake', _fmt(_stake)),
              _divider(),
              _infoRow('Total prize pot', _fmt(_stake * _players), valueColor: AuraColors.amber),
              _divider(),
              _infoRow('Format', 'Winner takes all'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GradientButton(label: 'Create game', onPressed: _createGame),
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
        Text(value, style: TextStyle(fontFamily: AuraText.displayFamily, color: valueColor ?? Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// Selectable glass card with a brand-gradient border when [selected]
/// (opaque dark interior so the border reads as a frame, not a fill).
class _OptCard extends StatelessWidget {
  const _OptCard({
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
