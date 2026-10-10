import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Invite friends / referral screen. See docs/DESIGN_SPEC.md.
class ReferralScreen extends StatelessWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Invite friends'),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Center(child: _GiftTile()),
          const SizedBox(height: 20),
          Text(
            'Give 1,000, get 2,000',
            style: AuraText.headline,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Your friend starts with 1,000 bonus Tokens. You earn 2,000 Tokens + 300 Gold when they play 3 matches.',
            style: AuraText.body.copyWith(color: AuraColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          const _CodeCard(),
          const SizedBox(height: 14),
          Row(
            children: const [
              Expanded(child: _ShareTile(label: 'WhatsApp', icon: Icons.chat, color: AuraColors.green)),
              SizedBox(width: 10),
              Expanded(child: _ShareTile(label: 'Telegram', icon: Icons.send, color: AuraColors.storeBlueA)),
              SizedBox(width: 10),
              Expanded(child: _ShareTile(label: 'SMS', icon: Icons.sms, color: AuraColors.gems)),
              SizedBox(width: 10),
              Expanded(child: _ShareTile(label: 'More', icon: Icons.ios_share, color: AuraColors.brandPurple)),
            ],
          ),
          const SizedBox(height: 22),
          const SectionBar(
            'Your referrals',
            trailing: Text(
              '2 / 5 joined',
              style: TextStyle(
                color: AuraColors.accentGlow,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _ReferralRow(
            initial: 'Z',
            color: AuraColors.avatarBlue,
            name: 'ZeroCool',
            status: 'Reward earned',
            statusColor: AuraColors.green,
            trailing: '+2,000',
          ),
          const SizedBox(height: 10),
          const _ReferralRow(
            initial: 'L',
            color: AuraColors.avatarPurple,
            name: 'LunaWolf',
            status: '1 / 3 matches played',
            statusColor: AuraColors.textSecondary,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _GiftTile extends StatelessWidget {
  const _GiftTile();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 118,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              gradient: AuraGradients.brand,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AuraColors.brandPink.withValues(alpha: 0.4),
                  blurRadius: 28,
                  spreadRadius: -4,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(Icons.card_giftcard, color: Colors.white, size: 44),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: _FloatChip(icon: Icons.diamond, text: '+2,000', color: AuraColors.gems),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: _FloatChip(icon: Icons.circle, text: '+300', color: AuraColors.gold),
          ),
        ],
      ),
    );
  }
}

class _FloatChip extends StatelessWidget {
  const _FloatChip({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AuraColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard();

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AuraColors.brandPurple.withValues(alpha: 0.3),
          AuraColors.brandPink.withValues(alpha: 0.14),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOUR CODE', style: AuraText.section.copyWith(color: Colors.white70)),
                const SizedBox(height: 6),
                Text(
                  'NOVA-7K2Q',
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => showAuraToast(context, 'Code copied ✓'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: AuraGradients.brand,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Copy',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareTile extends StatelessWidget {
  const _ShareTile({required this.label, required this.icon, required this.color});
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      onTap: () => showAuraToast(context, 'Shared via $label'),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AuraColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralRow extends StatelessWidget {
  const _ReferralRow({
    required this.initial,
    required this.color,
    required this.name,
    required this.status,
    required this.statusColor,
    this.trailing,
  });
  final String initial;
  final Color color;
  final String name;
  final String status;
  final Color statusColor;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          LetterAvatar(letter: initial, color: color, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(status, style: TextStyle(color: statusColor, fontSize: 13)),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trailing!,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: AuraColors.green,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.diamond, size: 14, color: AuraColors.gems),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
