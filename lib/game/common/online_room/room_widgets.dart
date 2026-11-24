/// Screens pieces shared by the rooms-family online games (Ludo, Snake &
/// Ladder): a centred message, the room code card and the quick-chat sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../widgets/aura.dart';
import 'room_controller.dart';
import 'room_models.dart';

/// A centred message (connecting, an error, left the room).
class RoomMessage extends StatelessWidget {
  const RoomMessage({super.key, required this.title, required this.text, this.busy = false, this.onBack});
  final String title;
  final String text;
  final bool busy;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: AuraAppBar(title: title),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) const CircularProgressIndicator(color: AuraColors.accentGlow),
            const SizedBox(height: 18),
            Text(text, textAlign: TextAlign.center, style: AuraText.body),
            if (onBack != null) ...[
              const SizedBox(height: 24),
              SecondaryButton(label: 'Back', onPressed: onBack!),
            ],
          ],
        ),
      ),
    );
  }
}

/// The room code, large, with Copy and Share.
class RoomCodeCard extends StatelessWidget {
  const RoomCodeCard({super.key, required this.code, required this.gameName});
  final String code;

  /// Named in the share text ("Join my Ludo room: CODE").
  final String gameName;

  @override
  Widget build(BuildContext context) {
    final shown = code.toUpperCase();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AuraGlass.decoration(radius: 20),
      child: Column(
        children: [
          Text('ROOM CODE', style: AuraText.cardSub.copyWith(letterSpacing: 1.2)),
          const SizedBox(height: 8),
          SelectableText(
            shown,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: shown));
                    showAuraToast(context, 'Room code copied', kind: AuraToastKind.success);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SecondaryButton(
                  label: 'Share',
                  onPressed: () => SharePlus.instance.share(ShareParams(text: 'Join my $gameName room: $shown')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The 12 preset lines as buttons, and the latest lines.
Future<void> showRoomChat(BuildContext context, RoomController c) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF17112C),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => ListenableBuilder(
      listenable: c,
      builder: (ctx, _) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Quick chat', style: AuraText.title),
            const SizedBox(height: 10),
            for (final l in c.chat.reversed.take(4).toList().reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${c.nameOf(l.fromUserId)}: ${l.message}', style: AuraText.cardSub),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final line in roomQuickChat)
                  ActionChip(
                    label: Text(line),
                    onPressed: () {
                      c.sendChat(line);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
