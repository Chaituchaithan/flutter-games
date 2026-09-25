import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../widgets/aura.dart';

/// Matchmaking "VS" — searching → opponent reveal → countdown → GO.
/// Mirrors the mockup's `isVs`. Set [autoStart] false to render the searching
/// state statically (tests).
class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key, this.autoStart = true, this.players = 2, this.potText = '400'});

  final bool autoStart;
  final int players;
  final String potText;

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

enum _Phase { searching, reveal, count3, count2, count1, go }

class _MatchmakingScreenState extends State<MatchmakingScreen> {
  _Phase _phase = _Phase.searching;
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      void at(int ms, _Phase p) => _timers.add(Timer(Duration(milliseconds: ms), () {
            if (mounted) setState(() => _phase = p);
          }));
      at(1600, _Phase.reveal);
      at(2600, _Phase.count3);
      at(3400, _Phase.count2);
      at(4200, _Phase.count1);
      _timers.add(Timer(const Duration(milliseconds: 5000), () {
        if (mounted) Navigator.pushReplacementNamed(context, Routes.matchResult);
      }));
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  bool get _searching => _phase == _Phase.searching;

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      glowColor: AuraColors.brandPurple,
      glowAlignment: const Alignment(0, -0.1),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Text('ONLINE · ${widget.players}P',
                    style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: AuraGlass.decoration(radius: 99, shadow: false),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CurrencyGlyph(kind: Currency.gems, size: 14),
                    const SizedBox(width: 6),
                    Text('Pot ${widget.potText}',
                        style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _player('NR', AuraColors.brandPurple, 'Nova Rider', 'LV 7'),
                const SizedBox(height: 18),
                _vsBadge(),
                const SizedBox(height: 18),
                _opponent(),
              ],
            ),
          ),
          Column(
            children: [
              Text(
                switch (_phase) {
                  _Phase.searching => 'Finding your match…',
                  _Phase.reveal => 'Opponent found!',
                  _Phase.go => 'GO!',
                  _ => 'Get ready…',
                },
                style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CurrencyGlyph(kind: Currency.gems, size: 14),
                  const SizedBox(width: 6),
                  Text('Winner takes ', style: AuraText.cardSub),
                  Text(widget.potText,
                      style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.amber, fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
              if (_searching) ...[
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: SecondaryButton(label: 'Cancel search', onPressed: () => Navigator.of(context).maybePop()),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ],
      ),
    );
  }

  Widget _player(String initials, Color color, String name, String lvl) {
    return Column(
      children: [
        LetterAvatar(letter: initials, color: color, size: 96, glow: true),
        const SizedBox(height: 8),
        Text(name, style: AuraText.cardTitle.copyWith(fontSize: 16)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: BoxDecoration(color: AuraColors.amber.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
          child: Text(lvl, style: const TextStyle(color: AuraColors.amber, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _vsBadge() {
    final label = switch (_phase) {
      _Phase.count3 => '3',
      _Phase.count2 => '2',
      _Phase.count1 => '1',
      _Phase.go => 'GO!',
      _ => 'VS',
    };
    return Container(
      width: 84,
      height: 84,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: AuraGradients.brandDeep,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 3),
        boxShadow: [BoxShadow(color: AuraColors.brandPink.withValues(alpha: 0.8), blurRadius: 40, spreadRadius: -6)],
      ),
      child: Text(label,
          style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: label.length > 2 ? 22 : 30, fontWeight: FontWeight.w700, letterSpacing: 1)),
    );
  }

  Widget _opponent() {
    if (_searching) {
      return Column(
        children: [
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2, strokeAlign: BorderSide.strokeAlignInside),
            ),
            child: const Icon(Icons.search, color: AuraColors.textSecondary, size: 34),
          ),
          const SizedBox(height: 8),
          Text('Searching…', style: AuraText.cardTitle.copyWith(fontSize: 16, color: Colors.white.withValues(alpha: 0.7))),
          const SizedBox(height: 4),
          Text('1,284 players online', style: AuraText.cardSub.copyWith(fontSize: 11)),
        ],
      );
    }
    return _player('RV', AuraColors.danger, 'Rival Vex', 'LV 8');
  }
}
