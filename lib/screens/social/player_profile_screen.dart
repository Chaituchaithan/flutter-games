import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Public profile of another player (mockup `playerProfile`). Presentation-only —
/// Challenge / Message / Report / Block all give toast/dialog feedback.
///
/// Pushed directly with the tapped player's details (Friends / Leaderboard rows);
/// the no-arg default renders a demo player for routing/tests.
class PlayerProfileScreen extends StatelessWidget {
  const PlayerProfileScreen({
    super.key,
    this.name = 'ZeroCool',
    this.color = AuraColors.avatarBlue,
    this.level = 9,
    this.rank = '#4',
    this.online = true,
  });

  final String name;
  final Color color;
  final int level;
  final String rank;
  final bool online;

  void _challenge(BuildContext context) {
    showAuraToast(context, 'Challenge sent to $name', kind: AuraToastKind.success);
  }

  void _message(BuildContext context) {
    showAuraToast(context, 'Messaging coming soon', kind: AuraToastKind.info);
  }

  void _report(BuildContext context) {
    showAuraToast(context, 'Report submitted — thanks', kind: AuraToastKind.info);
  }

  Future<void> _block(BuildContext context) async {
    final ok = await showAuraDialog(
      context,
      icon: Icons.block_rounded,
      title: 'Block $name?',
      body: "They won't be able to challenge or message you, and you'll no longer "
          'match together.',
      primaryLabel: 'Block',
      secondaryLabel: 'Cancel',
      destructive: true,
    );
    if (ok == true && context.mounted) {
      showAuraToast(context, '$name blocked', kind: AuraToastKind.error);
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: AuraAppBar(
        title: 'Profile',
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_horiz, color: AuraColors.textSecondary),
          color: AuraColors.bgRaised,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (v) => v == 'report' ? _report(context) : _block(context),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'report',
              child: Text('Report', style: TextStyle(color: Colors.white)),
            ),
            PopupMenuItem(
              value: 'block',
              child: Text('Block', style: TextStyle(color: AuraColors.dangerText)),
            ),
          ],
        ),
      ),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: AuraAvatar(initials: name.substring(0, name.length >= 2 ? 2 : 1), size: 96, level: level),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(name, style: AuraText.headline.copyWith(fontSize: 24)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AuraColors.accentGlow.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('LV $level',
                    style: const TextStyle(color: AuraColors.accentGlow, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              online ? 'Online now' : 'Offline',
              style: TextStyle(
                color: online ? AuraColors.green : AuraColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const IntrinsicHeight(
            child: Row(
              children: [
                Expanded(child: StatTile(value: '312', label: 'Wins')),
                SizedBox(width: 10),
                Expanded(child: StatTile(value: '64%', label: 'Win rate')),
                SizedBox(width: 10),
                Expanded(child: StatTile(value: '18', label: 'Streak')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.leaderboard_rounded,
                  label: 'Season rank',
                  value: rank,
                  valueColor: AuraColors.amber,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.favorite_rounded,
                  label: 'Favourite',
                  value: 'Chess',
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: GradientButton(label: 'Challenge', onPressed: () => _challenge(context)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SecondaryButton(label: 'Message', onPressed: () => _message(context)),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value, this.valueColor});
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AuraGlass.decoration(radius: 16),
      child: Row(
        children: [
          Icon(icon, color: AuraColors.textSecondary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: AuraText.cardSub.copyWith(fontSize: 11)),
                const SizedBox(height: 2),
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
            ),
          ),
        ],
      ),
    );
  }
}
