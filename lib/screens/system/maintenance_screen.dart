import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Maintenance — "We'll be right back". Mirrors the mockup's `isMaintenance`.
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      glowColor: AuraColors.amber,
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
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AuraColors.amber.withValues(alpha: 0.3), AuraColors.gold.withValues(alpha: 0.08)],
                ),
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: AuraColors.amber.withValues(alpha: 0.5), width: 1.5),
              ),
              child: const Icon(Icons.build_rounded, color: AuraColors.goldLight, size: 46),
            ),
          ),
          const SizedBox(height: 26),
          Text('We\'ll be right back', textAlign: TextAlign.center, style: AuraText.headline.copyWith(fontSize: 28)),
          const SizedBox(height: 10),
          Text(
            'Chess is down for scheduled maintenance while Season 4 rolls out. Your balances and match history are safe.',
            textAlign: TextAlign.center,
            style: AuraText.body.copyWith(color: AuraColors.textSecondary, fontSize: 14.5),
          ),
          const SizedBox(height: 22),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: AuraGlass.decoration(radius: 14, shadow: false),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule_rounded, color: AuraColors.amber, size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('Estimated return', maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.cardSub.copyWith(fontSize: 13)),
                  ),
                  const SizedBox(width: 6),
                  Text('~42 min',
                      style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Container(
            decoration: AuraGlass.decoration(radius: 20),
            child: Column(
              children: const [
                _StatusRow(label: 'Game servers', status: 'Updating', color: AuraColors.amber),
                _StatusDivider(),
                _StatusRow(label: 'Matchmaking', status: 'Paused', color: AuraColors.amber),
                _StatusDivider(),
                _StatusRow(label: 'Store & wallet', status: 'Operational', color: AuraColors.green),
              ],
            ),
          ),
          const Spacer(),
          GradientButton(label: 'Try again', onPressed: () => Navigator.of(context).maybePop()),
          const SizedBox(height: 10),
          SecondaryButton(label: 'View status page', onPressed: () {}),
          const SizedBox(height: 14),
          const _ExitPreview(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Muted underlined "Exit preview" link (mockup) — pops this demo-state screen.
class _ExitPreview extends StatelessWidget {
  const _ExitPreview();

  @override
  Widget build(BuildContext context) {
    return Center(
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
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.status, required this.color});
  final String label;
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 8)]),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14))),
          Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatusDivider extends StatelessWidget {
  const _StatusDivider();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 36),
        child: Divider(height: 1, thickness: 1, color: Colors.white.withValues(alpha: 0.12)),
      );
}
