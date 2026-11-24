import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/wallet.dart';
import '../widgets/aura.dart' show Currency;
import 'app_exception.dart';
import 'session.dart';
import 'wallet_api.dart';

/// The signed-in player's balance (docs/services/03-wallet.md "WalletStore"):
/// the one source every balance chip and stake check reads.
///
/// Re-read on: app start (first watch), resume, a game's end ([gameEnded]),
/// a transfer ([transfer]) and any purchase, bonus or gift ([moneyMoved]).
/// Otherwise [refresh] reads at most once every [minInterval]. Never polls,
/// never adds or subtracts on the device: it shows what the server sends.
///
/// `ref.invalidate(walletProvider)` still forces a fresh read (and keeps the
/// last value on screen while it loads).
class WalletStore extends AsyncNotifier<Wallet> {
  static const minInterval = Duration(seconds: 10);

  DateTime? _lastRead;
  Future<void>? _reading;

  @override
  Future<Wallet> build() async {
    // One store per signed-in user: a new player starts over.
    ref.watch(sessionProvider.select((u) => u?.id));
    final api = ref.watch(walletApiProvider);
    _lastRead = DateTime.now();
    return api.balance();
  }

  /// Re-reads the balance. Without [force], skipped when the last read is
  /// under [minInterval] old. A failed re-read keeps the last balance.
  Future<void> refresh({bool force = false}) {
    final last = _lastRead;
    if (!force && state.hasValue && last != null && DateTime.now().difference(last) < minInterval) {
      return Future.value();
    }
    return _reading ??= () async {
      _lastRead = DateTime.now();
      try {
        state = AsyncData(await ref.read(walletApiProvider).balance());
      } on Object catch (e, st) {
        if (!state.hasValue) state = AsyncError(e, st);
      } finally {
        _reading = null;
      }
    }();
  }

  /// A staked game ended (`game.wallet_update`, or the socket dropped before
  /// it): the payout is already written, so re-read now.
  Future<void> gameEnded() => refresh(force: true);

  /// A purchase, bonus, gift or reward moved money: re-read now.
  Future<void> moneyMoved() => refresh(force: true);

  /// Sets one currency's balance from a server reply (e.g. `sender_balance`).
  void applyBalance(WalletCurrency currency, int amount) {
    final w = state.value;
    if (w != null) state = AsyncData(w.withBalance(currency.currency, amount));
  }

  /// Sends [amount] of [currency] to [recipientId] (POST /wallet/transfer).
  /// [idempotencyKey]: new per send attempt, the same on a retry of it.
  /// Updates the chip from `sender_balance`, then re-reads the balance.
  /// Throws [AppException] with the wallet's player-facing text.
  Future<TransferResult> transfer({
    required String recipientId,
    required int amount,
    required WalletCurrency currency,
    required String idempotencyKey,
  }) async {
    final r = await ref.read(walletApiProvider).transfer(
          recipientId: recipientId,
          amount: amount,
          currency: currency,
          idempotencyKey: idempotencyKey,
        );
    applyBalance(r.currency, r.senderBalance);
    unawaited(refresh(force: true));
    return r;
  }
}

/// The live balance (03-wallet.md). No automatic retry on failure (Riverpod's
/// default backs off and re-calls the API on its own); a failed read waits for
/// the next real refresh.
final walletProvider = AsyncNotifierProvider<WalletStore, Wallet>(WalletStore.new, retry: (_, _) => null);

/// Live balance of [kind] for checks (stake / buy-in / claim): the latest
/// wallet, kept across refreshes; null until it first loads.
int? walletBalance(WidgetRef ref, Currency kind) => ref.read(walletProvider).value?.of(kind);

/// Re-read the balance after something moved money. For any feature: e.g. a
/// game's result screen calls `refreshWallet(ref)` after `game.wallet_update`.
/// [force] false = at most once every [WalletStore.minInterval] (e.g. resume).
Future<void> refreshWallet(WidgetRef ref, {bool force = true}) =>
    ref.read(walletProvider.notifier).refresh(force: force);

/// The wallet history as a growing list (03-wallet.md §2 "What the app does"):
/// [reload] starts from the top; [loadMore] passes `after=<next_cursor>` with
/// the same currency and page size until the cursor is null. Never uses `page`
/// for scrolling.
class LedgerPager {
  LedgerPager(this._api, {this.currency, this.per = 20});

  final WalletApi _api;

  /// The filter: null = token and gold.
  WalletCurrency? currency;
  final int per;

  final List<LedgerEntry> items = [];
  String? _cursor;
  int _generation = 0;

  /// Every row for the filter (from the last page read).
  int total = 0;
  bool loaded = false;
  bool loading = false;

  bool get hasMore => _cursor != null;

  /// "No history yet".
  bool get isEmpty => loaded && items.isEmpty && total == 0;

  /// Pull to refresh / a new filter: the first page, without `after`.
  Future<void> reload() async {
    final gen = ++_generation;
    loading = true;
    try {
      final page = await _api.ledger(currency: currency, per: per);
      if (gen != _generation) return;
      items
        ..clear()
        ..addAll(page.items);
      _cursor = page.nextCursor;
      total = page.total;
      loaded = true;
    } finally {
      if (gen == _generation) loading = false;
    }
  }

  /// The next page. A cursor the server refuses (`400 BAD_REQUEST`) reloads
  /// from the top.
  Future<void> loadMore() async {
    final after = _cursor;
    if (after == null || loading) return;
    final gen = ++_generation;
    loading = true;
    try {
      final page = await _api.ledger(currency: currency, per: per, after: after);
      if (gen != _generation) return;
      final seen = {for (final e in items) e.entryId};
      items.addAll(page.items.where((e) => !seen.contains(e.entryId)));
      _cursor = page.nextCursor;
      total = page.total;
    } on AppException catch (e) {
      if (gen != _generation) return;
      if (e.code == ApiErrorCode.badRequest) {
        loading = false;
        return reload();
      }
      rethrow;
    } finally {
      if (gen == _generation) loading = false;
    }
  }
}
