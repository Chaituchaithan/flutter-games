import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../configs/configs.dart';
import '../../services/account_standing.dart';
import '../../services/api_client.dart';
import '../../services/app_exception.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';

/// Where players reach support (shown on the restricted and limits screens).
const supportContact = 'support@royalearcade.com';

/// "Account restricted" full screen (docs/services/12-safety.md §4): a ban
/// at sign-in or during a session. Tokens are already cleared by the time
/// this shows; the only way on is back to sign-in.
class AccountRestrictedScreen extends ConsumerWidget {
  const AccountRestrictedScreen({super.key, this.until});

  /// When a timed ban ends (UTC); null = until staff lift it.
  final DateTime? until;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      child: _FullState(
        icon: Icons.block_rounded,
        color: AuraColors.danger,
        title: 'Account suspended',
        body: banMessage(until),
        note: 'Questions? Contact $supportContact',
        primary: 'Back to sign-in',
        onPrimary: () {
          // Whatever got us here, nothing of the session may survive.
          if (ref.read(sessionProvider) != null) ref.read(sessionProvider.notifier).forceSignOut();
          Navigator.of(context).pushNamedAndRemoveUntil(Routes.login, (r) => false);
        },
      ),
    );
  }
}

/// "Not available in your region" (§6). Retry is offered (the player may
/// have moved or switched network), never automatic.
class RegionBlockedScreen extends ConsumerStatefulWidget {
  const RegionBlockedScreen({super.key});

  @override
  ConsumerState<RegionBlockedScreen> createState() => _RegionBlockedScreenState();
}

class _RegionBlockedScreenState extends ConsumerState<RegionBlockedScreen> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    var blocked = false;
    try {
      await ref.read(apiClientProvider).get(ApiEndpoints.games);
    } on AppException catch (e) {
      blocked = e.code == ApiErrorCode.geoBlocked;
    } on Object catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    if (blocked) {
      showAuraToast(context, "Still not available here. Try again later.", kind: AuraToastKind.info);
      return;
    }
    ref.read(accountStandingProvider.notifier).clearGeo();
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushNamedAndRemoveUntil(Routes.splash, (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: _FullState(
          icon: Icons.public_off_rounded,
          color: AuraColors.amber,
          title: 'Not available here',
          body: GeoBlock.full.text,
          primary: 'Retry',
          busy: _busy,
          onPrimary: _retry,
        ),
      );
}

/// Settings > Responsible gaming (§5): help text only. No player route reads
/// or sets limits yet, so there is no limit editor.
class ResponsibleGamingScreen extends StatelessWidget {
  const ResponsibleGamingScreen({super.key});

  static const _limits = [
    ('Loss limits', 'A cap on how much you can lose in a day, a week or a month. A tournament buy-in that would pass it is refused.'),
    ('Tournament spend limit', 'A cap on what you spend on tournament buy-ins in a day.'),
    ('Session limits', 'Poker and Teen Patti tables sit you out after a long session or when a daily loss limit is reached.'),
    ('Cooling off', 'A short break: you can\'t join tournaments until it ends.'),
    ('Self-exclusion', 'A longer break from tournaments, until a date you choose with our team.'),
  ];

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Responsible gaming'),
      scroll: true,
      showGlow: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(
            'Play for fun, and stop when it stops being fun. These limits help you stay in control.',
            style: AuraText.body.copyWith(color: AuraColors.textSecondary),
          ),
          const SizedBox(height: 16),
          for (final (title, text) in _limits) ...[
            AuraCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(color: AuraColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(text, style: AuraText.cardSub),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          AuraCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.support_agent_rounded, color: AuraColors.accentGlow),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Contact support to set or change a limit: $supportContact',
                      style: AuraText.body.copyWith(color: AuraColors.textPrimary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _FullState extends StatelessWidget {
  const _FullState({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.primary,
    required this.onPrimary,
    this.note,
    this.busy = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String? note;
  final String primary;
  final VoidCallback onPrimary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      glowColor: color,
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
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
              ),
              child: Icon(icon, color: color, size: 46),
            ),
          ),
          const SizedBox(height: 26),
          Text(title, textAlign: TextAlign.center, style: AuraText.headline.copyWith(fontSize: 28)),
          const SizedBox(height: 10),
          Text(body,
              textAlign: TextAlign.center, style: AuraText.body.copyWith(color: AuraColors.textSecondary, fontSize: 14.5)),
          if (note != null) ...[
            const SizedBox(height: 14),
            Text(note!, textAlign: TextAlign.center, style: AuraText.cardSub),
          ],
          const Spacer(),
          GradientButton(label: primary, loading: busy, onPressed: onPrimary),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}
