import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/daily_bonus_repository.dart';
import '../l10n/l10n.dart';

/// Watches the daily-bonus status and hands [builder] the line to show:
/// "Day N ready" when claimable, else a live "Next in 5h 12m" countdown.
/// Re-reads the status the moment the next claim opens.
class DailyBonusStatusBuilder extends ConsumerStatefulWidget {
  const DailyBonusStatusBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, String sub, bool ready) builder;

  @override
  ConsumerState<DailyBonusStatusBuilder> createState() => _DailyBonusStatusBuilderState();
}

class _DailyBonusStatusBuilderState extends ConsumerState<DailyBonusStatusBuilder> {
  Timer? _reopen;
  DateTime? _scheduledFor;

  /// Live countdown ticker: fires when the shown value changes (each minute,
  /// then each second in the last hour) — not a constant 1s rebuild.
  Timer? _tick;

  @override
  void dispose() {
    _reopen?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  /// Re-read the status when the next claim opens.
  void _scheduleRefresh(DateTime? at) {
    if (at == _scheduledFor) return;
    _scheduledFor = at;
    _reopen?.cancel();
    if (at == null) return;
    final wait = at.difference(DateTime.now());
    _reopen = Timer(
      wait.isNegative ? Duration.zero : wait + const Duration(seconds: 2),
      () => ref.invalidate(dailyBonusStatusProvider),
    );
  }

  /// Rebuild exactly when the countdown text changes.
  void _scheduleTick(DateTime? at) {
    _tick?.cancel();
    if (at == null) return;
    final left = at.difference(DateTime.now());
    if (left.isNegative) return;
    final next = left.inHours >= 1
        ? Duration(milliseconds: left.inMilliseconds % 60000 + 1) // next minute boundary
        : Duration(milliseconds: left.inMilliseconds % 1000 + 1); // next second
    _tick = Timer(next, () {
      if (mounted) setState(() {});
    });
  }

  /// "5h 12m" (an hour or more), else "12m 05s".
  static String _until(DateTime at) {
    var d = at.difference(DateTime.now());
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours, m = d.inMinutes % 60, sec = d.inSeconds % 60;
    return h >= 1 ? '${h}h ${m}m' : '${m}m ${sec.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(dailyBonusStatusProvider);
    final s = status.asData?.value;
    if (s != null) _scheduleRefresh(s.canClaim ? null : s.nextClaimAt);
    _scheduleTick(s == null || s.canClaim ? null : s.nextClaimAt);
    final ready = s?.canClaim ?? false;
    final next = s?.nextClaimAt;
    final String sub;
    if (s == null) {
      sub = status.isLoading ? context.l10n.checking : context.l10n.openRewards;
    } else if (ready) {
      sub = context.l10n.dayReady(s.nextReward.dayNumber);
    } else {
      sub = next != null ? context.l10n.nextIn(_until(next)) : context.l10n.claimedToday;
    }
    return widget.builder(context, sub, ready);
  }
}
