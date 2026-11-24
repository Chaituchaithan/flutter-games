import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/root_key.dart';
import '../app/routes.dart';
import '../data/repositories/inbox_repository.dart';
import 'account_store.dart';
import 'app_prefs.dart';

/// Push plumbing (docs/services/10-inbox-and-notifications.md §4), kept
/// minimal. The gateway stores push tokens but sends nothing today, so no
/// payload is parsed: a push (foreground or tap) only opens the Inbox and
/// re-reads the lists.
///
/// The OS side (permission, FCM / APNs token, taps) is behind [PushPlatform].
/// This build ships [NoPushPlatform]: no push package is bundled yet. A
/// Firebase Messaging implementation plugs in by overriding
/// [pushPlatformProvider] in `main()`.

enum PushPermission {
  /// The OS lets the app show notifications.
  granted,

  /// The player said no (or turned them off in system settings).
  denied,

  /// Never asked.
  notDetermined,

  /// No push support in this build / on this platform.
  unsupported,
}

/// The OS push service: permission, token, refreshes and taps.
abstract class PushPlatform {
  bool get supported;
  Future<PushPermission> permission();

  /// Shows the OS prompt (iOS; Android 13+ runtime permission).
  Future<PushPermission> requestPermission();

  /// The FCM token (Android, web) or the APNs-backed token (iOS); null when
  /// there is none.
  Future<String?> token();

  /// A new token from the provider (`onTokenRefresh`).
  Stream<String> get tokenRefreshes;

  /// A push arrived in the foreground or was tapped. The payload is ignored.
  Stream<void> get opens;

  /// Opens this app's page in the system settings. False when it can't.
  Future<bool> openSystemSettings();
}

/// No push package in this build: everything reports [PushPermission.unsupported].
class NoPushPlatform implements PushPlatform {
  const NoPushPlatform();
  @override
  bool get supported => false;
  @override
  Future<PushPermission> permission() async => PushPermission.unsupported;
  @override
  Future<PushPermission> requestPermission() async => PushPermission.unsupported;
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get tokenRefreshes => const Stream.empty();
  @override
  Stream<void> get opens => const Stream.empty();
  @override
  Future<bool> openSystemSettings() async => false;
}

final pushPlatformProvider = Provider<PushPlatform>((ref) => const NoPushPlatform());

@immutable
class PushState {
  const PushState({this.permission = PushPermission.unsupported, this.wanted = true, this.busy = false});

  final PushPermission permission;

  /// The player's choice on this device (the Settings switch).
  final bool wanted;
  final bool busy;

  bool get supported => permission != PushPermission.unsupported;

  /// The switch: on only when wanted AND the OS allows it.
  bool get on => wanted && permission == PushPermission.granted;

  /// Show "off" with a link to the system settings.
  bool get deniedByOs => permission == PushPermission.denied;

  PushState copyWith({PushPermission? permission, bool? wanted, bool? busy}) =>
      PushState(permission: permission ?? this.permission, wanted: wanted ?? this.wanted, busy: busy ?? this.busy);
}

/// Keeps the device's push token in step with the player's choice and the
/// OS permission, through [AccountStore.onPushToken] (which sends it with the
/// device registration on every sign-in, and PATCHes it on a refresh).
class PushController extends Notifier<PushState> {
  static const _wantedKey = 'push.wanted';
  static const _askedKey = 'push.asked';

  StreamSubscription<String>? _refreshes;
  StreamSubscription<void>? _opens;
  bool _started = false;

  PushPlatform get _platform => ref.read(pushPlatformProvider);
  AppPrefs get _prefs => ref.read(appPrefsProvider);

  @override
  PushState build() {
    ref.onDispose(() {
      _refreshes?.cancel();
      _opens?.cancel();
    });
    return const PushState();
  }

  /// App start: read the choice and the permission, hand the current token to
  /// the account store, listen for token refreshes and push opens.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final p = _platform;
    final wanted = await _prefs.get(_wantedKey) != '0';
    final perm = await p.permission();
    state = state.copyWith(permission: perm, wanted: wanted);
    _refreshes = p.tokenRefreshes.listen((t) {
      if (state.on) unawaited(ref.read(accountStoreProvider.notifier).onPushToken(t));
    });
    _opens = p.opens.listen((_) => openInbox());
    if (state.on) await _sendToken();
  }

  Future<void> _sendToken() async {
    final t = await _platform.token();
    await ref.read(accountStoreProvider.notifier).onPushToken(t);
  }

  /// The Settings switch. On: ask the OS when needed, then send the token.
  /// Off: `{"push_token": null}` for this device. Returns the new state.
  Future<PushState> setWanted(bool on) async {
    state = state.copyWith(busy: true);
    try {
      await _prefs.set(_wantedKey, on ? '1' : '0');
      if (!on) {
        state = state.copyWith(wanted: false);
        await ref.read(accountStoreProvider.notifier).onPushToken(null);
        return state;
      }
      var perm = await _platform.permission();
      if (perm == PushPermission.notDetermined) {
        await _prefs.set(_askedKey, '1');
        perm = await _platform.requestPermission();
      }
      state = state.copyWith(wanted: true, permission: perm);
      if (perm == PushPermission.granted) await _sendToken();
      return state;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// "At a sensible moment" (after the first finished game, not at first
  /// launch): ask once, then send the token if allowed.
  Future<void> askAfterGame() async {
    final p = _platform;
    if (!p.supported || !state.wanted) return;
    if (await _prefs.get(_askedKey) == '1') return;
    if (await p.permission() != PushPermission.notDetermined) return;
    await _prefs.set(_askedKey, '1');
    final perm = await p.requestPermission();
    state = state.copyWith(permission: perm);
    if (state.on) await _sendToken();
  }

  /// Back from the system settings: the permission may have changed.
  Future<void> recheckPermission() async {
    final perm = await _platform.permission();
    if (perm == state.permission) return;
    state = state.copyWith(permission: perm);
    if (state.on) await _sendToken();
  }

  Future<bool> openSystemSettings() => _platform.openSystemSettings();

  /// Any push: open the Inbox and re-read both lists and the badge.
  void openInbox() {
    refreshInboxEverywhere(ref);
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    var onInbox = false;
    nav.popUntil((r) {
      onInbox = r.settings.name == Routes.inbox;
      return true;
    });
    if (!onInbox) unawaited(nav.pushNamed(Routes.inbox));
  }
}

final pushControllerProvider = NotifierProvider<PushController, PushState>(PushController.new);
