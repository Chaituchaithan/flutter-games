import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/configs.dart';
import '../../configs/games/core/game_codes.dart';
import '../../data/models/social.dart';
import '../../services/app_exception.dart';
import '../../services/session.dart';
import '../../services/social_api.dart';
import '../../services/social_store.dart';
import '../../widgets/aura.dart';
import 'player_profile_screen.dart';

/// One lobby chat room per game (docs/services/09-social.md §3): the gateway's
/// free-text board, polled every 10 s while on screen, "Load older" with
/// `before`, lines from blocked players hidden. Not the in-game quick chat
/// (that goes over the game socket).
class LobbyChatScreen extends ConsumerStatefulWidget {
  const LobbyChatScreen({super.key, this.roomType = ChatRoomType.lobby, this.roomId});

  final ChatRoomType roomType;

  /// Null = the active game's code (`/chat/lobby/<game code>`).
  final String? roomId;

  @override
  ConsumerState<LobbyChatScreen> createState() => _LobbyChatScreenState();
}

class _LobbyChatScreenState extends ConsumerState<LobbyChatScreen> {
  late final ChatRoomController _chat;
  final _input = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final room = widget.roomId ?? GameCodes.codeOf(ref.read(activeGameProvider));
    _chat = ChatRoomController(
      ref.read(socialApiProvider),
      type: widget.roomType,
      roomId: room,
      isBlocked: (id) => ref.read(blockListProvider).containsKey(id),
    )..addListener(_changed);
    _chat.open();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _chat
      ..removeListener(_changed)
      ..dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (!validChatBody(text)) {
      setState(() => _error = 'Messages must be 1 to 2000 characters.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _chat.send(text);
      _input.clear();
    } on AppException catch (e) {
      _error = socialErrorText(e, widget.roomType == ChatRoomType.match ? SocialOp.matchChat : SocialOp.chatSend);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-filter when the block list changes.
    ref.listen(blockListProvider, (_, _) => setState(() {}));
    final names = ref.watch(playerNameCacheProvider);
    final me = ref.watch(sessionProvider.select((u) => u?.id)) ?? DemoSocialApi.me;
    final lines = _chat.messages;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(playerNameCacheProvider.notifier).ensure(lines.map((m) => m.senderUserId).where((id) => id != me));
    });
    return AuraScaffold(
      appBar: AuraAppBar(title: 'Lobby chat · ${_chat.roomId}'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _chat.loading && lines.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final m in lines.reversed)
                        _Line(
                          message: m,
                          mine: m.senderUserId == me,
                          name: m.senderUserId == me ? 'You' : (names[m.senderUserId]?.name ?? 'Player'),
                          onTapName: m.senderUserId == me
                              ? null
                              : () => Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => PlayerProfileScreen(
                                        userId: m.senderUserId, name: names[m.senderUserId]?.name ?? 'Player', online: false),
                                  )),
                        ),
                      if (_chat.hasOlder && lines.isNotEmpty)
                        Center(
                          child: TextButton(
                            onPressed: _chat.loadingOlder ? null : _chat.loadOlder,
                            child: Text(_chat.loadingOlder ? 'Loading…' : 'Load older'),
                          ),
                        ),
                      if (lines.isEmpty && !_chat.loading)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _chat.error != null && _chat.sendDisabled
                                ? socialErrorText(_chat.error!, widget.roomType == ChatRoomType.match ? SocialOp.matchChat : SocialOp.chatSend)
                                : 'No messages yet. Say hi!',
                            textAlign: TextAlign.center,
                            style: AuraText.cardSub,
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AuraTextField(
                  hint: _chat.sendDisabled ? "You can't chat right now." : 'Message',
                  icon: Icons.chat_bubble_outline_rounded,
                  controller: _input,
                  errorText: _error,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _chat.sendDisabled || _sending ? null : _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _chat.sendDisabled || _sending ? null : _send,
                icon: const Icon(Icons.send_rounded),
                color: AuraColors.accentGlow,
                tooltip: 'Send',
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.message, required this.mine, required this.name, this.onTapName});
  final ChatMessage message;
  final bool mine;
  final String name;
  final VoidCallback? onTapName;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: mine ? AuraColors.brandPurple.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: onTapName,
              child: Text(name, style: const TextStyle(color: AuraColors.accentGlow, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 2),
            Text(message.body, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
