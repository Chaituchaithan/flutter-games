import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Force update — "Update required". Mirrors the mockup's `isUpdate`.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key});

  static const _whatsNew = [
    'Season 4 · Neon Tide pass with 40 rewards',
    '4-player rooms and spectator mode',
    'Faster matchmaking and anti-cheat fixes',
  ];

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      glowColor: AuraColors.brandPurple,
      glowAlignment: const Alignment(0, -0.7),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                gradient: AuraGradients.brand,
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
                boxShadow: [BoxShadow(color: AuraColors.brandPink.withValues(alpha: 0.6), blurRadius: 40, spreadRadius: -8, offset: const Offset(0, 14))],
              ),
              child: const Icon(Icons.system_update_alt_rounded, color: Colors.white, size: 46),
            ),
          ),
          const SizedBox(height: 26),
          Text('Update required', textAlign: TextAlign.center, style: AuraText.headline.copyWith(fontSize: 28)),
          const SizedBox(height: 10),
          Text(
            'This version can no longer connect to online matches. Update to keep playing — it takes under a minute.',
            textAlign: TextAlign.center,
            style: AuraText.body.copyWith(color: AuraColors.textSecondary, fontSize: 14.5),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _versionChip('v1.0.0', muted: true),
              const SizedBox(width: 10),
              Icon(Icons.arrow_forward_rounded, color: AuraColors.textSecondary.withValues(alpha: 0.6), size: 16),
              const SizedBox(width: 10),
              _versionChip('v1.2.0', muted: false),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AuraGlass.decoration(radius: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("WHAT'S NEW", style: AuraText.section),
                const SizedBox(height: 12),
                for (final item in _whatsNew) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(gradient: AuraGradients.orb, borderRadius: BorderRadius.circular(7)),
                        child: const Icon(Icons.check, color: Colors.white, size: 13),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.4))),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          const Spacer(),
          GradientButton(label: 'Update on the App Store', onPressed: () {}),
          const SizedBox(height: 12),
          Center(child: Text('Required update · 48 MB', style: AuraText.cardSub.copyWith(fontSize: 12))),
          const SizedBox(height: 14),
          Center(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Text(
                'Exit preview',
                style: TextStyle(
                  color: AuraColors.textPrimary.withValues(alpha: 0.4),
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  decorationColor: AuraColors.textPrimary.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _versionChip(String v, {required bool muted}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: muted ? Colors.white.withValues(alpha: 0.06) : AuraColors.accentGlow.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: muted ? Colors.white.withValues(alpha: 0.16) : AuraColors.accentGlow.withValues(alpha: 0.55)),
      ),
      child: Text(
        v,
        style: TextStyle(
          fontFamily: AuraText.displayFamily,
          color: muted ? AuraColors.textSecondary : Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
