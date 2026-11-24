import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/configs.dart';
import '../configs/games/core/game_codes.dart';
import '../data/models/social.dart';
import 'app_exception.dart';
import 'server_clock.dart';
import 'session.dart';
import 'social_api.dart';
import 'socket/app_socket.dart';

/// App-side state for docs/services/09-social.md: the name cache, the block
/// list, friends + requests, the presence heartbeat and room chat.

/// Loads every page of a page list (friend lists and block lists are small).
Future<List<T>> loadAllPages<T>(Future<PageList<T>> Function(int page) read, {int maxPages = 20}) async {
  final out = <T>[];
  for (var page = 1; page <= maxPages; page++) {
    final p = await read(page);
    out.addAll(p.data);
    if (!p.hasMore || p.data.isEmpty) break;
  }
  return out;
}

// ---------------------------------------------------------------------------
// PlayerNameCache
// ---------------------------------------------------------------------------

/// User id → name and avatar for this session. Friend and request lists carry
/// ids only; names come from cards the app already has (friends-online,
/// blocks) or, lazily, from `GET /users/{id}/profile` a few at a time.
class PlayerNameCache extends Notifier<Map<String, UserCard>> {
  /// Profile reads in flight at once (the general limit is ~100 a minute).
  static const batch = 4;

  final _pending = <String>{};
  final _queue = <String>[];
  int _running = 0;

  @override
  Map<String, UserCard> build() {
    ref.watch(sessionProvider.select((u) => u?.id));
    _pending.clear();
    _queue.clear();
    return const {};
  }

  UserCard? operator [](String id) => state[id];

  /// Add cards the app already holds (a card with no name never replaces one
  /// with a name).
  void seed(Iterable<UserCard> cards) {
    final next = Map.of(state);
    var changed = false;
    for (final c in cards) {
      if (c.userId.isEmpty) continue;
      final had = next[c.userId];
      if (had != null && c.username == null) continue;
      if (had?.username == c.username && had?.avatarUrl == c.avatarUrl) continue;
      next[c.userId] = c;
      changed = true;
    }
    if (changed) state = next;
  }

  /// Fetch the names not yet known, [batch] at a time. Errors leave the id
  /// unnamed (rows draw "Player") and are retried on the next call.
  void ensure(Iterable<String> ids) {
    for (final id in ids) {
      if (id.isEmpty || state.containsKey(id) || _pending.contains(id)) continue;
      _pending.add(id);
      _queue.add(id);
    }
    _pump();
  }

  void _pump() {
    while (_running < batch && _queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      _running++;
      unawaited(() async {
        try {
          final card = await ref.read(socialApiProvider).playerCard(id);
          if (ref.mounted) seed([card]);
        } on Object catch (_) {
          // Leave unnamed; a later ensure() asks again.
        } finally {
          _running--;
          _pending.remove(id);
          if (ref.mounted) _pump();
        }
      }());
    }
  }
}

final playerNameCacheProvider = NotifierProvider<PlayerNameCache, Map<String, UserCard>>(PlayerNameCache.new);

// ---------------------------------------------------------------------------
// BlockList
// ---------------------------------------------------------------------------

/// The players I blocked (`GET /blocks`, every page), held in memory and used
/// to HIDE them everywhere: the server enforces blocks only on friend
/// requests (§6, Known issues 4). Loaded on sign-in, updated locally on block
/// and unblock.
class BlockList extends Notifier<Map<String, BlockedUser>> {
  bool _loaded = false;
  bool get loaded => _loaded;

  @override
  Map<String, BlockedUser> build() {
    ref.watch(sessionProvider.select((u) => u?.id));
    ref.watch(socialApiProvider);
    _loaded = false;
    Future.microtask(() {
      if (ref.mounted) unawaited(load().catchError((Object _) {}));
    });
    return const {};
  }

  bool isBlocked(String? userId) => userId != null && state.containsKey(userId);

  Future<void> load() async {
    final api = ref.read(socialApiProvider);
    final rows = await loadAllPages((p) => api.blocks(page: p, perPage: 100));
    if (!ref.mounted) return;
    _loaded = true;
    state = {for (final b in rows) b.userId: b};
    ref.read(playerNameCacheProvider.notifier).seed(rows.map((b) => b.card));
  }

  /// Blocks [userId]: also ends the friendship and declines pending requests
  /// on the server, so the friends state is refreshed.
  Future<void> block(String userId, {UserCard? card}) async {
    await ref.read(socialApiProvider).block(userId);
    state = {
      ...state,
      userId: BlockedUser(userId: userId, username: card?.username, avatarUrl: card?.avatarUrl, createdAt: ServerClock.now()),
    };
    ref.read(sentFriendRequestsProvider.notifier).forget(userId);
    ref.read(friendsProvider.notifier).removedLocally(userId);
  }

  Future<void> unblock(String userId) async {
    await ref.read(socialApiProvider).unblock(userId);
    state = Map.of(state)..remove(userId);
  }
}

final blockListProvider = NotifierProvider<BlockList, Map<String, BlockedUser>>(BlockList.new);

/// Drops lines from blocked players (chat, gift lists, suggestions).
List<T> withoutBlocked<T>(Iterable<T> items, Map<String, BlockedUser> blocked, String Function(T) userOf) =>
    [for (final i in items) if (!blocked.containsKey(userOf(i))) i];

// ---------------------------------------------------------------------------
// Friends
// ---------------------------------------------------------------------------

/// Requests I sent this session (there is no route to list them, §1a). After
/// a restart the card shows "Add friend" again; a second send answers
/// `DUPLICATE_FRIEND_REQUEST` → "Request already sent".
class SentFriendRequests extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(sessionProvider.select((u) => u?.id));
    return const {};
  }

  void remember(String userId) => state = {...state, userId};
  void forget(String userId) => state = {...state}..remove(userId);
}

final sentFriendRequestsProvider = NotifierProvider<SentFriendRequests, Set<String>>(SentFriendRequests.new);

/// How a player relates to me, for the buttons on their card.
enum FriendRelation { self, friend, incoming, sent, blocked, none }

@immutable
class FriendsState {
  const FriendsState({this.friends = const [], this.online = const {}, this.incoming = const [], this.incomingTotal = 0});

  /// Every friend, newest friendship first (as the server sends them).
  final List<FriendLink> friends;

  /// Friends online now (heartbeat in the last 120 s).
  final Set<String> online;

  /// Incoming pending requests, newest first.
  final List<FriendRequest> incoming;

  /// The Requests tab badge.
  final int incomingTotal;

  bool isFriend(String id) => friends.any((f) => f.userId == id);
  FriendRequest? incomingFrom(String id) {
    for (final r in incoming) {
      if (r.fromUserId == id) return r;
    }
    return null;
  }

  /// Online first, then by name ([nameOf] from the name cache).
  List<FriendLink> sorted(String Function(String id) nameOf) {
    final list = List.of(friends);
    list.sort((a, b) {
      final oa = online.contains(a.userId), ob = online.contains(b.userId);
      if (oa != ob) return oa ? -1 : 1;
      return nameOf(a.userId).toLowerCase().compareTo(nameOf(b.userId).toLowerCase());
    });
    return list;
  }

  FriendsState copyWith({List<FriendLink>? friends, Set<String>? online, List<FriendRequest>? incoming, int? incomingTotal}) =>
      FriendsState(
        friends: friends ?? this.friends,
        online: online ?? this.online,
        incoming: incoming ?? this.incoming,
        incomingTotal: incomingTotal ?? this.incomingTotal,
      );
}

/// Friends, who of them is online, and incoming requests. Re-read when the
/// Friends screen opens and on resume ([refresh]); online every 30 s while
/// that screen is open ([refreshOnline]). No push exists for any of it.
class FriendsController extends AsyncNotifier<FriendsState> {
  @override
  Future<FriendsState> build() async {
    ref.watch(sessionProvider.select((u) => u?.id));
    return _read(ref.watch(socialApiProvider));
  }

  Future<FriendsState> _read(SocialApi api) async {
    final (friends, requests, online) = await (
      loadAllPages((p) => api.friends(page: p, perPage: 100)),
      api.incomingRequests(perPage: 100),
      api.friendsOnline().then<FriendsOnline?>((o) => o).catchError((Object _) => null),
    ).wait;
    final names = ref.read(playerNameCacheProvider.notifier);
    if (online != null) names.seed(online.friends);
    return FriendsState(
      friends: friends,
      online: online?.ids ?? const {},
      incoming: requests.data,
      incomingTotal: requests.total,
    );
  }

  /// Re-read everything (keeps the last lists on screen while loading; a
  /// failure keeps them too, when there are any).
  Future<void> refresh() async {
    final next = await AsyncValue.guard(() => _read(ref.read(socialApiProvider)));
    if (!ref.mounted) return;
    if (next.hasError && state.hasValue) return;
    state = next;
  }

  /// `GET /presence/friends-online` only. Errors are ignored.
  Future<void> refreshOnline() async {
    final cur = state.value;
    if (cur == null) return;
    try {
      final o = await ref.read(socialApiProvider).friendsOnline();
      if (!ref.mounted) return;
      ref.read(playerNameCacheProvider.notifier).seed(o.friends);
      state = AsyncData((state.value ?? cur).copyWith(online: o.ids));
    } on Object catch (_) {}
  }

  /// "Add friend". Checks the incoming list first: a request from them is
  /// accepted instead (§1a "Mutual requests"). `DUPLICATE_FRIEND_REQUEST`
  /// also marks it sent; `CONFLICT` (already friends) refreshes the list.
  /// Returns the relation afterwards; throws [AppException] for the rest.
  Future<FriendRelation> add(String userId) async {
    final incoming = state.value?.incomingFrom(userId);
    if (incoming != null) {
      await accept(incoming);
      return FriendRelation.friend;
    }
    try {
      await ref.read(socialApiProvider).sendFriendRequest(userId);
      ref.read(sentFriendRequestsProvider.notifier).remember(userId);
      return FriendRelation.sent;
    } on AppException catch (e) {
      if (e.code == ApiErrorCode.duplicateFriendRequest) {
        ref.read(sentFriendRequestsProvider.notifier).remember(userId);
        // Maybe they sent me one since the last read.
        unawaited(refresh());
      } else if (e.code == ApiErrorCode.conflict) {
        unawaited(refresh());
      }
      rethrow;
    }
  }

  /// Accept: the friendship exists at once. A `404` (no longer pending)
  /// removes the row and reloads.
  Future<void> accept(FriendRequest r) async {
    try {
      await ref.read(socialApiProvider).acceptRequest(r.id);
      _dropRequest(r.id, addFriend: r.fromUserId);
    } on AppException catch (e) {
      if (e.statusCode == 404) {
        _dropRequest(r.id);
        unawaited(refresh());
      }
      rethrow;
    }
  }

  Future<void> decline(FriendRequest r) async {
    try {
      await ref.read(socialApiProvider).rejectRequest(r.id);
      _dropRequest(r.id);
    } on AppException catch (e) {
      if (e.statusCode == 404) {
        _dropRequest(r.id);
        unawaited(refresh());
        return;
      }
      rethrow;
    }
  }

  /// Remove a friend; a `404` counts as done (handled in the API).
  Future<void> remove(String userId) async {
    await ref.read(socialApiProvider).removeFriend(userId);
    removedLocally(userId);
  }

  /// The friendship and requests with [userId] ended (remove or block).
  void removedLocally(String userId) {
    final s = state.value;
    if (s == null) return;
    final kept = [for (final r in s.incoming) if (r.fromUserId != userId) r];
    state = AsyncData(s.copyWith(
      friends: [for (final f in s.friends) if (f.userId != userId) f],
      online: {...s.online}..remove(userId),
      incoming: kept,
      incomingTotal: (s.incomingTotal - (s.incoming.length - kept.length)).clamp(0, 1 << 30),
    ));
  }

  void _dropRequest(int id, {String? addFriend}) {
    final s = state.value;
    if (s == null) return;
    final kept = [for (final r in s.incoming) if (r.id != id) r];
    state = AsyncData(s.copyWith(
      incoming: kept,
      incomingTotal: (s.incomingTotal - (s.incoming.length - kept.length)).clamp(0, 1 << 30),
      friends: addFriend == null || s.isFriend(addFriend)
          ? null
          : [FriendLink(userId: addFriend, createdAt: ServerClock.now()), ...s.friends],
    ));
  }
}

final friendsProvider = AsyncNotifierProvider<FriendsController, FriendsState>(FriendsController.new, retry: (_, _) => null);

/// How [userId] relates to me, for the buttons on their card. Rebuilds when
/// the friend list, the block list or this session's sent requests change.
final friendRelationProvider = Provider.autoDispose.family<FriendRelation, String>((ref, userId) {
  final me = ref.watch(sessionProvider.select((u) => u?.id)) ?? DemoSocialApi.me;
  if (userId == me) return FriendRelation.self;
  if (ref.watch(blockListProvider).containsKey(userId)) return FriendRelation.blocked;
  final s = ref.watch(friendsProvider).value;
  if (s != null && s.isFriend(userId)) return FriendRelation.friend;
  if (s?.incomingFrom(userId) != null) return FriendRelation.incoming;
  if (ref.watch(sentFriendRequestsProvider).contains(userId)) return FriendRelation.sent;
  return FriendRelation.none;
});

/// "N players online" (§2c): read at most once a minute (the provider is
/// auto-disposed; screens invalidate it no faster than that).
final onlineCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(socialApiProvider).onlineCount(),
  retry: (_, _) => null,
);

// ---------------------------------------------------------------------------
// Presence heartbeat
// ---------------------------------------------------------------------------

/// Sends `POST /presence/heartbeat` once on start (sign-in, resume), then
/// every [interval] while the app is in the foreground; stops in the
/// background (§2a). Errors are ignored and never retried.
class PresenceService {
  PresenceService(this._beat, {this.interval = const Duration(seconds: 60), String? Function()? gameId})
      : _gameId = gameId ?? (() => null);

  final Future<void> Function({String? gameId}) _beat;
  final String? Function() _gameId;
  final Duration interval;
  Timer? _timer;

  bool get running => _timer != null;

  void start() {
    if (_timer != null) return;
    _send();
    _timer = Timer.periodic(interval, (_) => _send());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Foreground → start; background → stop. `inactive` (a system sheet over
  /// the app) changes nothing.
  void onLifecycle(AppLifecycleState s) {
    switch (s) {
      case AppLifecycleState.resumed:
        start();
      case AppLifecycleState.paused || AppLifecycleState.hidden || AppLifecycleState.detached:
        stop();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _send() {
    unawaited(_beat(gameId: _gameId()).catchError((Object _) {}));
  }
}

/// The heartbeat while signed in against the real server (and the first
/// block-list read). Listened to by the main shell for its lifetime
/// (auto-disposed with it, which stops the timer).
final presenceServiceProvider = Provider.autoDispose<PresenceService?>((ref) {
  final live = ref.watch(useRemoteAuthProvider) && ref.watch(sessionProvider.select((u) => u != null));
  if (!live) return null;
  // Signed in: load the block list now so blocked players are hidden
  // everywhere from the start (§6c).
  ref.read(blockListProvider);
  final api = ref.watch(socialApiProvider);
  final socket = ref.read(appSocketProvider);
  final svc = PresenceService(
    api.heartbeat,
    // In a game: the game's code (`ludo`, `snake-and-ladder`).
    gameId: () {
      final g = socket.gameScreenOpen ? socket.game : null;
      return g == null ? null : GameCodes.codeOf(g.id);
    },
  );
  final binding = WidgetsBinding.instance;
  final listener = AppLifecycleListener(binding: binding, onStateChange: svc.onLifecycle);
  final now = binding.lifecycleState;
  if (now == null || now == AppLifecycleState.resumed) svc.start();
  ref.onDispose(() {
    listener.dispose();
    svc.stop();
  });
  return svc;
});

// ---------------------------------------------------------------------------
// Room chat
// ---------------------------------------------------------------------------

/// One gateway chat room (§3): newest 50 on open, "load older" with
/// `before`, a poll of the newest page every [pollEvery] while on screen,
/// merged by `id`. Lines from blocked players are hidden via [isBlocked].
class ChatRoomController extends ChangeNotifier {
  ChatRoomController(
    this._api, {
    required this.type,
    required this.roomId,
    this.pageSize = 50,
    this.pollEvery = const Duration(seconds: 10),
    bool Function(String userId)? isBlocked,
  }) : _isBlocked = isBlocked ?? ((_) => false);

  final SocialApi _api;
  final ChatRoomType type;
  final String roomId;
  final int pageSize;
  final Duration pollEvery;
  bool Function(String userId) _isBlocked;

  /// Oldest first (as drawn, newest at the bottom).
  final List<ChatMessage> _all = [];
  final Set<String> _ids = {};
  Timer? _poll;
  bool loading = false;
  bool loadingOlder = false;
  bool hasOlder = true;
  AppException? error;

  /// The player can't post (muted / chat-banned, or not in this match).
  bool sendDisabled = false;

  List<ChatMessage> get messages => [for (final m in _all) if (!_isBlocked(m.senderUserId)) m];

  set isBlocked(bool Function(String userId) f) {
    _isBlocked = f;
    notifyListeners();
  }

  static int _cmp(ChatMessage a, ChatMessage b) {
    // `<epoch ms>-<n>` ids sort by time; compare the parts as numbers.
    final pa = a.id.split('-'), pb = b.id.split('-');
    final ta = int.tryParse(pa.first) ?? 0, tb = int.tryParse(pb.first) ?? 0;
    if (ta != tb) return ta.compareTo(tb);
    return (int.tryParse(pa.last) ?? 0).compareTo(int.tryParse(pb.last) ?? 0);
  }

  void _merge(Iterable<ChatMessage> list) {
    var added = false;
    for (final m in list) {
      if (_ids.add(m.id)) {
        _all.add(m);
        added = true;
      }
    }
    if (added) _all.sort(_cmp);
  }

  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Open: the newest page, then poll.
  Future<void> open() async {
    loading = true;
    _notify();
    try {
      final page = await _api.chatHistory(type, roomId, count: pageSize);
      _merge(page);
      hasOlder = page.length >= pageSize;
      error = null;
    } on AppException catch (e) {
      error = e;
      if (e.code == ApiErrorCode.forbidden) sendDisabled = true;
    } finally {
      loading = false;
      _notify();
    }
    startPolling();
  }

  void startPolling() {
    _poll ??= Timer.periodic(pollEvery, (_) => unawaited(pollNewest()));
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> pollNewest() async {
    try {
      _merge(await _api.chatHistory(type, roomId, count: pageSize));
      _notify();
    } on Object catch (_) {}
  }

  /// "Load older": `before=<the oldest id held>`; stops when a page comes
  /// back short.
  Future<void> loadOlder() async {
    if (loadingOlder || !hasOlder || _all.isEmpty) return;
    loadingOlder = true;
    _notify();
    try {
      final page = await _api.chatHistory(type, roomId, count: pageSize, before: _all.first.id);
      _merge(page);
      hasOlder = page.length >= pageSize;
    } finally {
      loadingOlder = false;
      _notify();
    }
  }

  /// Send: the returned line shows at once; the poll's copy is dropped by id.
  /// Throws [AppException]; a `403` disables the input.
  Future<void> send(String body) async {
    final t = body.trim();
    if (!validChatBody(t)) {
      throw const AppException('', statusCode: 400, code: ApiErrorCode.validation, field: 'body');
    }
    try {
      _merge([await _api.sendChat(type, roomId, t)]);
      _notify();
    } on AppException catch (e) {
      if (e.code == ApiErrorCode.forbidden) {
        sendDisabled = true;
        _notify();
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }
}

/// 1 to 2000 characters (§3a).
bool validChatBody(String body) {
  final t = body.trim();
  return t.isNotEmpty && t.length <= 2000;
}
