import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/home/home_screen.dart';
import '../screens/wheel/wheel_screen.dart';
import '../screens/store/store_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../services/connectivity.dart';
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
  const MainShell({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  void initState() {
    super.initState();
    if (widget.initialIndex != 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(mainTabProvider.notifier).select(widget.initialIndex),
      );
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
