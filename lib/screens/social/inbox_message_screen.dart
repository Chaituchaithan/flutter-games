import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/inbox_message.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../services/app_exception.dart';
import '../../services/inbox_service.dart';
import '../../widgets/aura.dart';
import 'inbox_screen.dart';

/// One inbox message (§1c-1f): title, sent time, expiry, the body as plain
/// text, Claim when a reward is waiting, Delete. Opening it marks it read.
class InboxMessageScreen extends ConsumerStatefulWidget {
  const InboxMessageScreen({super.key, required this.message});
  final InboxMessage message;

  @override
  ConsumerState<InboxMessageScreen> createState() => _InboxMessageScreenState();
}

class _InboxMessageScreenState extends ConsumerState<InboxMessageScreen> {
  late InboxMessage _m = widget.message;
  bool _claiming = false;
  bool _deleting = false;

  /// After a `404 no claimable reward`: no Claim button.
  bool _noReward = false;

  /// The claim answered "expired".
  bool _expired = false;

  InboxStore get _store => ref.read(inboxStoreProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final read = await _store.open(_m);
      if (mounted) setState(() => _m = read);
    });
  }

  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    final out = await _store.claim(_m);
    if (!mounted) return;
    setState(() {
      _claiming = false;
      if (out.message != null) _m = out.message!;
      if (out.kind == ClaimOutcomeKind.noReward) _noReward = true;
      if (out.kind == ClaimOutcomeKind.expired) _expired = true;
    });
    final text = out.text;
    switch (out.kind) {
      case ClaimOutcomeKind.claimed:
        if (text != null) showAuraToast(context, text, kind: AuraToastKind.gold);
      case ClaimOutcomeKind.alreadyClaimed:
        showAuraToast(context, text ?? inboxAlreadyClaimedText, kind: AuraToastKind.info);
      case ClaimOutcomeKind.gone:
        showAuraToast(context, text ?? inboxGoneText, kind: AuraToastKind.error);
        Navigator.of(context).maybePop();
      case ClaimOutcomeKind.noReward:
        break;
      case ClaimOutcomeKind.expired:
      case ClaimOutcomeKind.failed:
        if (text != null) showAuraToast(context, text, kind: AuraToastKind.error);
    }
  }

  Future<void> _delete() async {
    if (_deleting) return;
    if (needsDeleteConfirm(_m)) {
      final ok = await showAuraDialog(
        context,
        icon: Icons.delete_outline_rounded,
        title: 'Delete this message?',
        body: 'The reward inside will be lost.',
        primaryLabel: 'Delete',
        secondaryLabel: 'Keep',
        destructive: true,
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _deleting = true);
    try {
      await _store.delete(_m);
      if (mounted) Navigator.of(context).maybePop();
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showAuraToast(context, inboxIssue(e, InboxOp.delete).text ?? inboxGenericText, kind: AuraToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    final expired = _expired || m.isExpired();
    final expiry = m.claimedAt != null ? null : (expired ? 'Expired' : expiryText(m.expiresAt));
    final canClaim = m.hasReward && !_noReward && m.claimedAt == null && !expired;
    final sent = m.createdAt?.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');

    return AuraScaffold(
      appBar: AuraAppBar(
        title: 'Message',
        trailing: GlassIconButton(
          icon: Icons.delete_outline_rounded,
          onTap: _deleting ? () {} : _delete,
        ),
      ),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          AuraCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InboxIcon(message: m, size: 48),
                    const SizedBox(width: 12),
                    Expanded(child: Text(m.title, style: AuraText.cardTitle.copyWith(fontSize: 17))),
                  ],
                ),
                const SizedBox(height: 10),
                if (sent != null)
                  Text(
                    'Sent ${sent.year}-${two(sent.month)}-${two(sent.day)} ${two(sent.hour)}:${two(sent.minute)}',
                    style: AuraText.cardSub.copyWith(fontSize: 12),
                  ),
                if (expiry != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    expiry,
                    style: AuraText.cardSub.copyWith(fontSize: 12, color: expired ? AuraColors.danger : AuraColors.brandOrange),
                  ),
                ],
                const SizedBox(height: 14),
                // Plain text with its line breaks; never HTML or Markdown.
                SelectableText(m.body, style: const TextStyle(color: AuraColors.textPrimary, fontSize: 14.5, height: 1.45)),
              ],
            ),
          ),
          if (m.hasReward) ...[
            const SizedBox(height: 16),
            AuraCard(
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard, color: AuraColors.brandOrange),
                  const SizedBox(width: 10),
                  Expanded(child: Text(m.rewardLabel, style: AuraText.cardTitle)),
                  if (m.claimedAt != null)
                    Text('Claimed', style: AuraText.cardSub.copyWith(color: AuraColors.green))
                  else if (expired)
                    Text('Expired', style: AuraText.cardSub.copyWith(color: AuraColors.danger)),
                ],
              ),
            ),
            if (canClaim) ...[
              const SizedBox(height: 16),
              GradientButton(label: 'Claim', loading: _claiming, enabled: !_claiming, onPressed: _claim),
            ],
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
