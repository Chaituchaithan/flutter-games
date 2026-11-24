import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/account_standing.dart';
import 'aura.dart';

/// Which feature a [RestrictionBanner] guards (12-safety.md §4c).
enum RestrictedFeature { chat, play, tournaments }

/// "You can't send messages until …" and friends: shows only while
/// [accountStandingProvider] says the feature is closed (or a ban of an
/// unknown scope is active). Place it above the chat input, the Play
/// buttons or the tournament Join button, and disable those from the same
/// provider (`canChat`, `canStake`/`canPlay`, `canJoinTournaments`).
class RestrictionBanner extends ConsumerWidget {
  const RestrictionBanner({super.key, required this.feature});
  final RestrictedFeature feature;

  /// The banner text for [feature], or null when it is open.
  static String? textFor(AccountStanding s, RestrictedFeature feature) =>
      switch (feature) {
        RestrictedFeature.chat => s.chatBlockedText,
        RestrictedFeature.play => s.playBlockedText,
        RestrictedFeature.tournaments => s.tournamentBlockedText,
      } ??
      s.unknownRestrictionText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = textFor(ref.watch(accountStandingProvider), feature);
    if (text == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AuraColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AuraColors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AuraColors.amber, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: AuraColors.textPrimary, fontSize: 13))),
        ],
      ),
    );
  }
}
