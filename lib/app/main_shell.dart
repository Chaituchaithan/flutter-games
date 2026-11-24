import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/feature_flags.dart';
import '../configs/games/core/game_id.dart';
import '../data/repositories/daily_bonus_repository.dart';
import '../data/repositories/inbox_repository.dart';
import '../data/repositories/rewards_repository.dart';
import '../data/repositories/store_repository.dart';
import 'routes.dart';
import '../screens/home/home_screen.dart';
import '../screens/wheel/wheel_screen.dart';
import '../screens/store/store_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/profile/progress_ui.dart';
import '../services/progress_service.dart';
import '../services/connectivity.dart';
import '../services/push_service.dart';
import '../services/session.dart';
import '../services/social_store.dart' show presenceServiceProvider;
import '../services/socket/app_socket.dart';
import '../services/socket/socket_client.dart' show SocketMessage;
import 'game_area.dart';
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
    _presence; // start the heartbeat
    // A game to go back to (a reconnect, or a cold start mid-game: ludo.md
    // §7): open that game's online screen — now, or when the frame arrives.
    final socket = ref.read(appSocketProvider);
    _resumes = socket.resumes.listen((_) => _openResume(socket));
    // 07-rewards.md "When to refetch": after every game ends, let the game
    // server settle the match (~2 s), then re-read quests and achievements.
    _gameEnds = socket.events.where((m) => _isGameEnd(m, socket)).listen((_) {
      refreshRewardsAfterGame(ref);
      // 10-inbox §4: ask for push permission after a finished game, once.
      ref.read(pushControllerProvider.notifier).askAfterGame();
      // 08-progress §"After a game": re-read XP / level / rating; level-up.
      if (mounted) progressAfterGame(ref, context, game: socket.game);
    });
    // 08-progress: hold levels and ratings (the "before" values of a game).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(progressStoreProvider.notifier).ensureLoaded();
    });
    // 10-inbox: badge on app start; push token and push taps.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(inboxBadgeProvider.notifier).refresh();
      ref.read(pushControllerProvider.notifier).start();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (socket.pendingResume != null) _openResume(socket);
    });
  }

  StreamSubscription<Object>? _resumes;
  StreamSubscription<Object>? _gameEnds;

  /// 09-social.md §2a: the presence heartbeat runs while the shell is up
  /// (signed in) and the app is in the foreground.
  late final ProviderSubscription<Object?> _presence = ref.listenManual(presenceServiceProvider, (_, _) {});

  static bool _isGameEnd(SocketMessage m, AppSocket socket) {
    if (m.event == 'game.over') return true;
    if (m.event == 'game.state_update') {
      // Ludo: a top-level flag; Snake & Ladder: on `last_action`.
      final last = m.data['last_action'];
      return m.data['game_over'] == true || (last is Map && last['game_over'] == true);
    }
    // Snake & Ladder: a game ended by a forfeit sends only this frame (Ludo
    // follows it with a final state update, counted above).
    return m.event == 'game.player_forfeited' &&
        m.data['game_over'] == true &&
        socket.game?.id == GameId.snakesLadders;
  }

  void _openResume(AppSocket socket) {
    final game = socket.game;
    final route = game == null ? null : GameArea.onlineRoute(game.id);
    if (!mounted || route == null || socket.gameScreenOpen) return;
    Navigator.of(context).pushNamed(route, arguments: {'mode': 'resume'});
  }

  /// How long Home settles before the Daily Rewards prompt slides in.
  static const _promptDelay = Duration(milliseconds: 900);

  /// Check the daily-bonus status once Home is up; if it can be claimed, show
  /// Daily Rewards (a slow or failed check just stays on Home).
  Future<void> _promptDailyBonus() async {
    // The welcome sheet comes first (once, while something is claimable);
    // then no daily prompt on top of it.
    if (await _promptWelcome()) return;
    final sub = ref.listenManual(dailyBonusStatusProvider, (_, _) {});
    try {
      // Give Home a moment to finish its first, heaviest frames (layout,
      // images, fonts, data landing) before sliding Daily Rewards over it.
      // Pushing ~80 ms after Home appeared stacked both screens' first
      // frames into the transition: half a second of dropped frames.
      final (s, _) = await (
        ref.read(dailyBonusStatusProvider.future).timeout(const Duration(seconds: 6)),
        Future<void>.delayed(_promptDelay),
      ).wait;
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

  /// Signed in against the real API: show the welcome bonus sheet if the
  /// grant has something to claim or the free spin (07-rewards.md §1a).
  Future<bool> _promptWelcome() async {
    final live = ref.read(useRemoteAuthProvider) && ref.read(sessionProvider) != null;
    if (!live) return false;
    final sub = ref.listenManual(welcomeBonusProvider, (_, _) {});
    try {
      final (w, _) = await (
        ref.read(welcomeBonusProvider.future).timeout(const Duration(seconds: 6)),
        Future<void>.delayed(_promptDelay),
      ).wait;
      if (w == null || !w.showSheet || !mounted) return false;
      if (ModalRoute.of(context)?.isCurrent != true) return false;
      unawaited(Navigator.pushNamed(context, Routes.welcomeBonus));
      return true;
    } on Object catch (_) {
      return false;
    } finally {
      sub.close();
    }
  }

  @override
  void dispose() {
    _gameEnds?.cancel();
    _presence.close();
    _resumes?.cancel();
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
      // 03-wallet.md: re-read on resume, at most once every 10 s.
      ref.read(walletProvider.notifier).refresh();
      // 07-rewards.md: rewards re-read when the app returns to the foreground.
      if (gone >= const Duration(seconds: 10)) refreshRewardsFrom(ref);
      // 10-inbox: the inbox badge re-reads on resume (at most once every 10 s).
      ref.read(inboxBadgeProvider.notifier).refresh();
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
                AuraBottomNav(
                  index: index,
                  onChanged: _select,
                  // Rewards red dot (07-rewards.md): Profile holds the rewards.
                  dots: {if (ref.watch(rewardsBadgeProvider).any) 3, if (ref.watch(inboxBadgeProvider).any) 0},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
