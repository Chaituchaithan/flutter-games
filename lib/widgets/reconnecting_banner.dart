import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/socket/app_socket.dart';
import '../services/socket/socket_client.dart';
import 'aura.dart';

/// "Reconnecting… 0:27" while the game socket is coming back after a drop.
/// The countdown is the 30 s the server keeps the player's seat
/// (00-conventions.md "Staying connected"). Hidden otherwise.
class ReconnectingBanner extends ConsumerStatefulWidget {
  const ReconnectingBanner({super.key});

  @override
  ConsumerState<ReconnectingBanner> createState() => _ReconnectingBannerState();
}

class _ReconnectingBannerState extends ConsumerState<ReconnectingBanner> {
  Timer? _tick;
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final c = ref.read(appSocketProvider).client;
      final next = c?.status == SocketStatus.reconnecting ? c?.reconnectDeadline : null;
      if (next != _deadline || next != null) setState(() => _deadline = next);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deadline = _deadline;
    if (deadline == null) return const SizedBox.shrink();
    final left = deadline.difference(DateTime.now());
    final secs = left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
    final text = secs > 0 ? 'Reconnecting… 0:${secs.toString().padLeft(2, '0')}' : 'Reconnecting…';
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AuraColors.bgBase.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AuraColors.amber.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AuraColors.amber),
                ),
                const SizedBox(width: 10),
                Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
