import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/safety.dart';
import '../../services/app_exception.dart';
import '../../services/safety_service.dart';
import '../../services/session.dart';
import '../../services/social_api.dart';
import '../../services/social_store.dart';
import '../../widgets/aura.dart';

/// "Report player" (docs/services/12-safety.md §1). Open it from a player
/// card, a chat line (pass [chatMessage] for a gateway line, or [quote] for
/// an in-game socket line, which can't be attached), or a match result or
/// detail screen ([matchId] is written into the description). Never open it
/// for the signed-in player: it returns null at once.
///
/// Resolves to true when a report was sent.
Future<bool?> showReportPlayerSheet(
  BuildContext context, {
  required String playerId,
  required String playerName,
  ChatEvidence? chatMessage,
  String? quote,
  String? matchId,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (playerId == container.read(sessionProvider)?.id) return null;
  // Already reported: say so without a network call.
  final already = await container
      .read(safetyControllerProvider)
      .alreadyReported(playerId: playerId, messageId: chatMessage?.messageId);
  if (!context.mounted) return null;
  if (already) {
    showAuraToast(context, "You've already reported this", kind: AuraToastKind.info);
    return false;
  }
  final sent = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => ReportPlayerSheet(
      playerId: playerId,
      playerName: playerName,
      chatMessage: chatMessage,
      quote: quote,
      matchId: matchId,
    ),
  );
  if (sent == true && context.mounted) {
    showAuraToast(context, 'Thanks. Our team will review your report.');
    // Blocking belongs to 09-social: its block list hides the player too.
    if (!container.read(blockListProvider).containsKey(playerId)) {
      final yes = await showAuraDialog(
        context,
        icon: Icons.block_rounded,
        title: 'Also block $playerName?',
        body: "They won't be able to challenge or message you.",
        primaryLabel: 'Block',
        secondaryLabel: 'Not now',
        destructive: true,
      );
      if (yes == true && context.mounted) {
        try {
          await container.read(blockListProvider.notifier).block(playerId);
          if (context.mounted) showAuraToast(context, '$playerName blocked');
        } on AppException catch (e) {
          if (context.mounted) showAuraToast(context, socialErrorText(e, SocialOp.block), kind: AuraToastKind.error);
        }
      }
    }
  }
  return sent;
}

class ReportPlayerSheet extends ConsumerStatefulWidget {
  const ReportPlayerSheet({
    super.key,
    required this.playerId,
    required this.playerName,
    this.chatMessage,
    this.quote,
    this.matchId,
  });

  final String playerId;
  final String playerName;
  final ChatEvidence? chatMessage;
  final String? quote;
  final String? matchId;

  @override
  ConsumerState<ReportPlayerSheet> createState() => _ReportPlayerSheetState();
}

class _ReportPlayerSheetState extends ConsumerState<ReportPlayerSheet> {
  final _text = TextEditingController();
  ReportReason? _reason;
  bool _includeLine = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? get _line => widget.chatMessage?.body ?? widget.quote;

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Pick a reason.');
      return;
    }
    final rule = SafetyRules.description(_text.text);
    if (rule != null) {
      setState(() => _error = rule);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await ref.read(safetyControllerProvider).reportPlayer(
            playerId: widget.playerId,
            reason: reason,
            description: _text.text,
            chatMessage: _includeLine ? widget.chatMessage : null,
            quote: _includeLine ? widget.quote : null,
            matchId: widget.matchId,
          );
      if (!mounted) return;
      if (out == ReportOutcome.alreadyReported) {
        showAuraToast(context, "You've already reported this", kind: AuraToastKind.info);
        Navigator.of(context).pop(false);
        return;
      }
      Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = safetyErrorText(e, SafetyOp.report);
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final line = _line;
    return _SheetFrame(
      children: [
        Text('Report ${widget.playerName}', style: AuraText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Text("They won't be told who reported them.", style: AuraText.cardSub),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in ReportReason.choices)
              _ReasonChip(
                label: r.label,
                selected: _reason == r,
                onTap: _busy ? null : () => setState(() {
                  _reason = r;
                  _error = null;
                }),
              ),
          ],
        ),
        if (line != null && line.isNotEmpty) ...[
          const SizedBox(height: 14),
          InkWell(
            onTap: _busy ? null : () => setState(() => _includeLine = !_includeLine),
            child: Row(
              children: [
                Icon(_includeLine ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                    color: _includeLine ? AuraColors.accentGlow : AuraColors.textSecondary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Include this message: "$line"',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AuraText.cardSub),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        AuraTextField(
          hint: 'Tell us more (optional)',
          controller: _text,
          maxLines: 4,
          errorText: _error,
          onChanged: (_) => setState(() => _error = null),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${_text.text.length}/${SafetyRules.descriptionMax}',
                style: AuraText.cardSub.copyWith(fontSize: 11)),
          ),
        ),
        const SizedBox(height: 12),
        GradientButton(label: 'Send report', loading: _busy, onPressed: _send),
      ],
    );
  }
}

/// "Report a problem with this match" (§3): participants only, after the
/// game ends. Resolves to true when the flag was sent.
Future<bool?> showFlagMatchSheet(BuildContext context, {required String matchId}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (await container.read(safetyControllerProvider).matchFlagged(matchId)) {
    if (context.mounted) showAuraToast(context, "You've already reported this", kind: AuraToastKind.info);
    return false;
  }
  if (!context.mounted) return null;
  final sent = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => FlagMatchSheet(matchId: matchId),
  );
  if (sent == true && context.mounted) showAuraToast(context, "Thanks. We'll look into this match.");
  return sent;
}

class FlagMatchSheet extends ConsumerStatefulWidget {
  const FlagMatchSheet({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<FlagMatchSheet> createState() => _FlagMatchSheetState();
}

class _FlagMatchSheetState extends ConsumerState<FlagMatchSheet> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final rule = SafetyRules.flagReason(_text.text);
    if (rule != null) {
      setState(() => _error = rule);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(safetyControllerProvider).flagMatch(widget.matchId, _text.text);
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = safetyErrorText(e, SafetyOp.flagMatch);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      children: [
        Text('Report a problem with this match', style: AuraText.title),
        const SizedBox(height: 6),
        Text(
          'For the game itself: cheating, a bot, a bug or an unfair result. '
          'To report how a player behaved, use Report player.',
          style: AuraText.cardSub,
        ),
        const SizedBox(height: 14),
        AuraTextField(
          hint: 'What happened? (${SafetyRules.flagReasonMin} to ${SafetyRules.flagReasonMax} characters)',
          controller: _text,
          maxLines: 4,
          errorText: _error,
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 16),
        GradientButton(
          label: 'Send',
          loading: _busy,
          enabled: SafetyRules.flagReason(_text.text) == null,
          onPressed: _send,
        ),
      ],
    );
  }
}

/// "Report a problem with this match" button for result and detail screens.
/// Shows "Reported" once this account flagged the match, and hides itself
/// after a `403` (not a participant). Pass [played] false to hide it for
/// matches the player wasn't in.
class ReportMatchButton extends ConsumerStatefulWidget {
  const ReportMatchButton({super.key, required this.matchId, this.played = true});
  final String matchId;
  final bool played;

  @override
  ConsumerState<ReportMatchButton> createState() => _ReportMatchButtonState();
}

class _ReportMatchButtonState extends ConsumerState<ReportMatchButton> {
  bool? _flagged;

  @override
  void initState() {
    super.initState();
    ref.read(safetyControllerProvider).matchFlagged(widget.matchId).then((v) {
      if (mounted) setState(() => _flagged = v);
    });
  }

  Future<void> _open() async {
    final sent = await showFlagMatchSheet(context, matchId: widget.matchId);
    if (!mounted) return;
    if (sent != null) setState(() => _flagged = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.played || widget.matchId.isEmpty) return const SizedBox.shrink();
    final done = _flagged == true;
    return TextButton.icon(
      onPressed: done || _flagged == null ? null : _open,
      icon: Icon(done ? Icons.check_rounded : Icons.flag_outlined, size: 18),
      label: Text(done ? 'Reported' : 'Report a problem with this match'),
      style: TextButton.styleFrom(
        foregroundColor: AuraColors.textSecondary,
        disabledForegroundColor: AuraColors.textMuted,
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.label, required this.selected, this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: selected ? AuraGradients.brand : null,
            color: selected ? null : AuraColors.card,
            borderRadius: BorderRadius.circular(99),
            border: selected ? null : Border.all(color: AuraColors.cardBorder),
          ),
          child: Text(label,
              style: TextStyle(
                color: selected ? Colors.white : AuraColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              )),
        ),
      );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: AuraColors.bgBase,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}
