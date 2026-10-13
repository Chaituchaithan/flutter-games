import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/daily_bonus_repository.dart';
import '../data/repositories/store_repository.dart';
import 'routes.dart';
import '../screens/home/home_screen.dart';
import '../screens/wheel/wheel_screen.dart';
import '../screens/store/store_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../services/connectivity.dart';
import '../services/session.dart';
import '../widgets/aura.dart';

/// Active bottom-tab index (0 Home · 1 Wheel · 2 Store · 3 Profile). A provider
/// so any screen — including pushed routes like Inbox — can switch tabs
/// (e.g. an inbox "Shop" action) by setting this, then popping back to the shell.
class MainTabController extends Notifier<int> {
  @override
  int build() => 0;
  void select(int index) => state = index;
}

final mainTabProvider = NotifierProvider<MainTabController, int>(MainTabController.new);

/// Lets tab screens (e.g. Home) switch the active bottom-tab — used for taps
/// like "Lucky Wheel" → Wheel tab or a currency pill → Store tab. Access via
/// [MainShellScope.maybeOf] and no-op gracefully when absent (e.g. in tests).
class MainShellScope extends InheritedWidget {
  const MainShellScope({super.key, required this.selectTab, required super.child});

  /// Switch the visible bottom-tab (0 Home · 1 Wheel · 2 Store · 3 Profile).
  final void Function(int index) selectTab;

  static MainShellScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MainShellScope>();

  @override
  bool updateShouldNotify(MainShellScope oldWidget) => false;
}

/// Bottom-tab container for the four primary screens.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, this.initialIndex = 0, this.dailyBonusPrompt = false});
  final int initialIndex;

  /// Right after sign-in: open Daily Rewards when today's bonus is unclaimed.
  final bool dailyBonusPrompt;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.dailyBonusPrompt) WidgetsBinding.instance.addPostFrameCallback((_) => _promptDailyBonus());
    if (widget.initialIndex != 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(mainTabProvider.notifier).select(widget.initialIndex),
      );
    }
  }

  /// Check the daily-bonus status once Home is up; if it can be claimed, show
  /// Daily Rewards (a slow or failed check just stays on Home).
  Future<void> _promptDailyBonus() async {
    final sub = ref.listenManual(dailyBonusStatusProvider, (_, _) {});
    try {
      final s = await ref.read(dailyBonusStatusProvider.future).timeout(const Duration(seconds: 6));
      if (!s.canClaim || !mounted) return;
      // Only over Home itself — never on top of a screen the player opened.
      if (ModalRoute.of(context)?.isCurrent != true) return;
      unawaited(Navigator.pushNamed(context, Routes.dailyRewards));
    } on Object catch (_) {
      // No prompt; the Profile → Daily Bonus tile still shows it's ready.
    } finally {
      sub.close();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// When the app actually went to the background (null = it hasn't).
  DateTime? _backgroundedAt;

  /// Back from a real stay in the background: the balance may have changed
  /// elsewhere. Brief interruptions (notification shade, system dialogs,
  /// permission prompts) only go `inactive` → `resumed` and don't refetch.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _backgroundedAt;
      _backgroundedAt = null;
      if (away == null) return;
      final gone = DateTime.now().difference(away);
      if (gone >= const Duration(seconds: 30)) ref.invalidate(walletProvider);
      // Level / XP / profile edits from another device: re-read after a
      // longer absence (and only if the last read is that old too).
      if (gone >= const Duration(minutes: 5)) {
        ref.read(sessionProvider.notifier).reloadProfile(ifOlderThan: const Duration(minutes: 5));
      }
    }
  }

  void _select(int i) => ref.read(mainTabProvider.notifier).select(i);

  @override
  Widget build(BuildContext context) {
    final online = isOnline(ref.watch(connectivityProvider));
    final index = ref.watch(mainTabProvider);
    return Scaffold(
      backgroundColor: AuraColors.bgBase,
      body: AuraBackground(
        child: SafeArea(
          bottom: false,
          child: MainShellScope(
            selectTab: _select,
            child: Column(
              children: [
                if (!online)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: AuraOfflineBanner(onRetry: () => ref.invalidate(connectivityProvider)),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: index,
                    children: const [HomeScreen(), WheelScreen(), StoreScreen(), ProfileScreen()],
                  ),
                ),
                AuraBottomNav(index: index, onChanged: _select),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
