import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/account.dart';
import '../../services/account_service.dart';
import '../../services/account_store.dart';
import '../../services/app_exception.dart';
import '../../services/session.dart';
import '../../services/social_store.dart';
import '../safety/report_sheets.dart';
import '../../widgets/aura.dart';
import '../../widgets/player_avatar.dart';
import 'player_social_actions.dart';

/// Public profile of another player (mockup `playerProfile`). Presentation-only —
/// Challenge / Message / Report / Block all give toast/dialog feedback.
///
/// Pushed directly with the tapped player's details (Friends / Leaderboard rows);
/// the no-arg default renders a demo player for routing/tests. With a
/// [userId], the card reads `GET /users/{id}/profile`
/// (02-profile-and-sessions.md §8): what comes back depends on the owner's
/// privacy, and trimmed fields draw as hidden, never as errors.
class PlayerProfileScreen extends ConsumerWidget {
  const PlayerProfileScreen({
    super.key,
    this.userId,
    this.name = 'ZeroCool',
    this.color = AuraColors.avatarBlue,
    this.level = 9,
    this.rank = '#4',
    this.online = true,
  });

  /// The player's id; null = presentation-only card from the fields below.
  final String? userId;
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

  /// "Report player" sheet (12-safety.md §1); the demo card has no id.
  void _report(BuildContext context, String shownName) {
    final id = userId;
    if (id == null) {
      showAuraToast(context, 'Thanks. Our team will review your report.', kind: AuraToastKind.info);
      return;
    }
    showReportPlayerSheet(context, playerId: id, playerName: shownName);
  }

  /// Block / Unblock (09-social.md §6). The demo card (no id) only confirms.
  Future<void> _block(BuildContext context, WidgetRef ref, String shownName) async {
    final id = userId;
    if (id != null) {
      await confirmBlockToggle(context, ref, userId: id, name: shownName);
      return;
    }
    final ok = await showAuraDialog(
      context,
      icon: Icons.block_rounded,
      title: 'Block $shownName?',
      body: "You won't see their messages, and you'll stop being friends.",
      primaryLabel: 'Block',
      secondaryLabel: 'Cancel',
      destructive: true,
    );
    if (ok == true && context.mounted) {
      showAuraToast(context, '$shownName blocked', kind: AuraToastKind.error);
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = userId;
    final async = id == null ? null : ref.watch(playerProfileProvider(id));
    final profile = async?.value;
    final deleted = profile?.isDeleted ?? false;
    final shownName = deleted ? 'Deleted player' : (profile?.displayName ?? name);
    final myId = ref.watch(sessionProvider.select((u) => u?.id));
    final isSelf = id != null && id == myId;
    final blocked = id != null && ref.watch(blockListProvider).containsKey(id);
    // A friend's dot comes from presence (§2b); others are "offline".
    final friendsNow = id == null ? null : ref.watch(friendsProvider).value;
    final isOnline = friendsNow == null ? online : friendsNow.online.contains(id);
    return AuraScaffold(
      appBar: AuraAppBar(
        title: 'Profile',
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_horiz, color: AuraColors.textSecondary),
          color: AuraColors.bgRaised,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (v) => v == 'report' ? _report(context, shownName) : _block(context, ref, shownName),
          itemBuilder: (_) => [
            // Never offer Report on the player's own card.
            if (id == null || id != ref.read(sessionProvider)?.id)
              const PopupMenuItem(
                value: 'report',
                child: Text('Report', style: TextStyle(color: Colors.white)),
              ),
            // Never offer Block on the player's own card (a 400).
            if (!isSelf)
              PopupMenuItem(
                value: 'block',
                child: Text(blocked ? 'Unblock' : 'Block', style: const TextStyle(color: AuraColors.dangerText)),
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
            child: profile != null
                ? AvatarDisc(
                    glyph: shownName.isEmpty ? '?' : shownName.substring(0, 1).toUpperCase(),
                    avatarUrl: profile.avatarUrl,
                    name: shownName,
                    size: 96,
                    glow: true,
                  )
                : AuraAvatar(initials: name.substring(0, name.length >= 2 ? 2 : 1), size: 96, level: level),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(shownName,
                    overflow: TextOverflow.ellipsis, style: AuraText.headline.copyWith(fontSize: 24)),
              ),
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
              isOnline ? 'Online now' : 'Offline',
              style: TextStyle(
                color: isOnline ? AuraColors.green : AuraColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (async != null && async.hasError && profile == null) ...[
            const SizedBox(height: 12),
            Text(
              async.error is AppException
                  ? accountErrorText(async.error! as AppException, AccountOp.playerProfile)
                  : "Couldn't load this profile.",
              textAlign: TextAlign.center,
              style: AuraText.cardSub,
            ),
          ],
          if (profile != null && !deleted) ...[
            const SizedBox(height: 16),
            _AboutCard(profile: profile),
          ],
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
          // A real player: friend / gift / money actions (09-social.md). No
          // direct messages exist on the server, so no Message button.
          if (id != null && !isSelf && !deleted)
            PlayerSocialActions(userId: id, name: shownName)
          else if (id == null)
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

/// Bio, country and language from the server. A null field was trimmed by the
/// owner's privacy (or never set): shown as hidden.
class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.profile});
  final PublicProfile profile;

  @override
  Widget build(BuildContext context) {
    final bio = (profile.bio ?? '').trim();
    final hidden = profile.bio == null && profile.country == null && profile.preferredLanguage == null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AuraGlass.decoration(radius: 16),
      child: hidden
          ? Row(
              children: [
                const Icon(Icons.lock_outline_rounded, color: AuraColors.textSecondary, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text('This player keeps their profile private.', style: AuraText.cardSub)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bio.isNotEmpty) ...[
                  Text(bio, style: AuraText.body.copyWith(color: AuraColors.textPrimary)),
                  const SizedBox(height: 8),
                ],
                Text(
                  [
                    if (profile.country != null) profile.country!,
                    if (profile.preferredLanguage != null) profile.preferredLanguage!.toUpperCase(),
                  ].join(' · '),
                  style: AuraText.cardSub.copyWith(fontSize: 12),
                ),
              ],
            ),
    );
  }
}
