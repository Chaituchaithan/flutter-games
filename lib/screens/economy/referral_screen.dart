import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_profile.dart';
import '../../data/models/referral.dart';
import '../../data/repositories/referral_repository.dart';
import '../../l10n/l10n.dart';
import '../../widgets/aura.dart';
import '../system/loading_skeleton_screen.dart' show Shimmer, SkeletonBox;

/// Invite friends: your invite code (`/referrals/my-code`) with copy and the
/// system share sheet, how it works, and your results (`/referrals/stats`).
/// See docs/DESIGN_SPEC.md.
class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final code = ref.watch(referralCodeProvider);
    final stats = ref.watch(referralStatsProvider);
    return AuraScaffold(
      appBar: AuraAppBar(title: l.inviteFriendsTitle),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Center(child: _GiftHero()),
          const SizedBox(height: 18),
          Text(l.referralHeadline, style: AuraText.headline, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            l.referralBody,
            style: AuraText.body.copyWith(color: AuraColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          code.when(
            data: (c) => _CodeCard(code: c),
            loading: () => const _CodeSkeleton(),
            error: (_, _) => _LoadError(
              text: l.referralCouldntLoad,
              onRetry: () {
                ref.invalidate(referralCodeProvider);
                ref.invalidate(referralStatsProvider);
              },
            ),
          ),
          const SizedBox(height: 22),
          SectionBar(l.howItWorks),
          const SizedBox(height: 12),
          _Steps(steps: [l.referralStep1, l.referralStep2, l.referralStep3]),
          const SizedBox(height: 22),
          // Results.
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.group_add_rounded,
                  color: AuraColors.accentGlow,
                  label: l.friendsJoined,
                  value: stats.whenOrNull(data: (s) => s.totalReferrals),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  icon: Icons.redeem_rounded,
                  color: AuraColors.amber,
                  label: l.rewardsEarned,
                  value: stats.whenOrNull(data: (s) => s.rewardsGranted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (stats.hasValue)
            _ResultNote(stats: stats.value!)
          else if (stats.hasError)
            Center(
              child: TextButton(
                onPressed: () => ref.invalidate(referralStatsProvider),
                child: Text(l.retry),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// A gift box with a soft glow and a few sparkles.
class _GiftHero extends StatelessWidget {
  const _GiftHero();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 120,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [AuraColors.brandPink.withValues(alpha: 0.28), Colors.transparent],
              ),
            ),
          ),
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              gradient: AuraGradients.brand,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(color: AuraColors.brandPink.withValues(alpha: 0.45), blurRadius: 30, spreadRadius: -4, offset: const Offset(0, 10)),
              ],
            ),
            child: const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 46),
          ),
          const Positioned(left: 12, top: 10, child: Icon(Icons.auto_awesome, color: AuraColors.amber, size: 18)),
          const Positioned(right: 10, top: 26, child: Icon(Icons.auto_awesome, color: Colors.white70, size: 13)),
          const Positioned(right: 22, bottom: 4, child: Icon(Icons.auto_awesome, color: AuraColors.accentGlow, size: 15)),
        ],
      ),
    );
  }
}

/// The code (letter-spaced, tap to copy), its usage / expiry, and the big
/// share button (system share sheet: WhatsApp, Telegram, SMS, …).
class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});
  final ReferralCode code;

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: code.code));
    HapticFeedback.selectionClick();
    showAuraToast(context, context.l10n.codeCopied, kind: AuraToastKind.success);
  }

  Future<void> _share(BuildContext context) async {
    final l = context.l10n;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: l.inviteMessage(AppProfile.current.appName, code.code),
        subject: AppProfile.current.appName,
        // iPad anchors the share popover to the card.
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final inactive = code.expired || code.usedUp;
    final usage = code.maxUses != null ? l.codeUsesOf(code.uses, code.maxUses!) : l.codeUses(code.uses);
    final expiry = code.expiresAt == null ? null : l.codeExpires(MaterialLocalizations.of(context).formatMediumDate(code.expiresAt!));
    return AuraCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AuraColors.brandPurple.withValues(alpha: 0.32), AuraColors.brandPink.withValues(alpha: 0.14)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.yourInviteCode, style: AuraText.section.copyWith(color: Colors.white70), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          // Dashed "ticket" with the code; tap anywhere on it to copy.
          GestureDetector(
            onTap: () => _copy(context),
            child: CustomPaint(
              painter: _DashedBorder(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          code.code,
                          style: TextStyle(
                            fontFamily: AuraText.displayFamily,
                            color: inactive ? Colors.white38 : Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                            decoration: inactive ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.copy_rounded, size: 15, color: Colors.white),
                          const SizedBox(width: 5),
                          Text(l.copyLabel, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            inactive
                ? (code.expired ? l.codeExpired : l.codeUsedUp)
                : [usage, ?expiry].join('  ·  '),
            textAlign: TextAlign.center,
            style: TextStyle(color: inactive ? AuraColors.danger : Colors.white60, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          Builder(
            builder: (btnContext) => GradientButton(
              label: l.shareInvite,
              enabled: !inactive,
              onPressed: () => _share(btnContext),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
    canvas.drawRRect(rrect, Paint()..color = Colors.black.withValues(alpha: 0.18));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.4);
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => false;
}

class _CodeSkeleton extends StatelessWidget {
  const _CodeSkeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Container(
      height: 190,
      decoration: AuraGlass.decoration(radius: AuraRadii.lg),
      padding: const EdgeInsets.all(18),
      child: const Column(
        children: [
          SkeletonBox(width: 120, height: 10),
          SizedBox(height: 16),
          SkeletonBox(height: 52, radius: 16),
          SizedBox(height: 14),
          SkeletonBox(width: 140, height: 10),
          Spacer(),
          SkeletonBox(height: 48, radius: 16),
        ],
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AuraCard(
    child: Column(
      children: [
        const Icon(Icons.cloud_off_rounded, color: Colors.white54, size: 30),
        const SizedBox(height: 8),
        Text(text, style: AuraText.cardSub, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
      ],
    ),
  );
}

/// Numbered steps joined by a line.
class _Steps extends StatelessWidget {
  const _Steps({required this.steps});
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    const icons = [Icons.ios_share_rounded, Icons.person_add_alt_1_rounded, Icons.redeem_rounded];
    return AuraCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 36,
                    child: Column(
                      children: [
                        Expanded(child: Container(width: 2, color: i == 0 ? Colors.transparent : Colors.white12)),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AuraGradients.brand,
                            boxShadow: [BoxShadow(color: AuraColors.brandPink.withValues(alpha: 0.35), blurRadius: 10)],
                          ),
                          child: Icon(icons[i], size: 16, color: Colors.white),
                        ),
                        Expanded(child: Container(width: 2, color: i == steps.length - 1 ? Colors.transparent : Colors.white12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          Text(
                            '${i + 1}.',
                            style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.accentGlow, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(steps[i], style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
                        ],
                      ),
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

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;

  /// Null while loading (shimmer).
  final int? value;

  @override
  Widget build(BuildContext context) => AuraCard(
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              value == null
                  ? const Shimmer(child: SkeletonBox(width: 28, height: 18))
                  : TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: value!.toDouble()),
                      duration: const Duration(milliseconds: 600),
                      builder: (_, v, _) => Text(
                        '${v.round()}',
                        style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                    ),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.caption),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ResultNote extends StatelessWidget {
  const _ResultNote({required this.stats});
  final ReferralStats stats;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final none = stats.totalReferrals == 0;
    return Row(
      children: [
        Icon(none ? Icons.info_outline_rounded : Icons.celebration_rounded, size: 16, color: none ? Colors.white54 : AuraColors.green),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            none ? l.noReferralsYet : l.referralsJoined(stats.totalReferrals),
            style: TextStyle(color: none ? Colors.white60 : AuraColors.green, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}
