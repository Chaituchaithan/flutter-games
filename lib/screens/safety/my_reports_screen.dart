import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/safety.dart';
import '../../services/app_exception.dart';
import '../../services/safety_service.dart';
import '../../widgets/aura.dart';
import '../../widgets/player_avatar.dart';

/// Settings > Safety > My reports (docs/services/12-safety.md §2): reports
/// this account sent, newest first, each with a status chip. Re-read every
/// time the screen opens (no "reviewed" notice exists) and on pull to refresh.
class MyReportsScreen extends ConsumerWidget {
  const MyReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myReportsProvider);
    Future<void> reload() => ref.refresh(myReportsProvider.future).then((_) {}, onError: (Object _) {});
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'My reports'),
      showGlow: false,
      body: RefreshIndicator(
        onRefresh: reload,
        color: AuraColors.accentGlow,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AuraColors.accentGlow)),
          error: (e, _) => _Message(
            text: e is AppException ? safetyErrorText(e, SafetyOp.myReports) : 'Something went wrong. Try again.',
            onRetry: reload,
          ),
          data: (reports) => reports.isEmpty
              ? const _Message(text: "You haven't reported anyone.")
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 4, bottom: 24),
                  itemCount: reports.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ReportTile(report: reports[i]),
                  ),
                ),
        ),
      ),
    );
  }
}

class ReportTile extends StatelessWidget {
  const ReportTile({super.key, required this.report});
  final Report report;

  @override
  Widget build(BuildContext context) {
    final name = report.reportedUsername ?? (report.reportedUserId == null ? 'Deleted player' : 'Player');
    final line = report.chatMessage?.body;
    final at = report.createdAt;
    return AuraCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarDisc(
                glyph: name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                avatarUrl: report.reportedAvatarUrl,
                name: name,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AuraColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      [report.reason.label, if (at != null) formatLocalTime(at).split(' ').first].join(' · '),
                      style: AuraText.cardSub.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              StatusChip(status: report.status),
            ],
          ),
          if (line != null && line.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('"$line"', maxLines: 3, overflow: TextOverflow.ellipsis, style: AuraText.cardSub),
          ],
          const SizedBox(height: 8),
          Text(report.status.text, style: AuraText.cardSub.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}

/// Received (grey), In review (blue), Action taken (green), Closed (grey).
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ReportStatus.reviewed => AuraColors.storeBlueB,
      ReportStatus.actionTaken => AuraColors.green,
      _ => AuraColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(99)),
      child: Text(status.chip, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Text(text, textAlign: TextAlign.center, style: AuraText.cardSub),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            Center(child: TextButton(onPressed: onRetry, child: const Text('Retry'))),
          ],
        ],
      );
}
