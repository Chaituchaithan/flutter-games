import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/configs.dart';
import '../data/models/wallet.dart';
import 'api_client.dart';
import 'app_exception.dart';
import 'session.dart';

/// The wallet routes (docs/services/03-wallet.md): balance, history (the
/// ledger) and sending money to another player. Never logs request or reply
/// bodies.
abstract class WalletApi {
  /// `GET /wallet/balance`.
  Future<Wallet> balance();

  /// `GET /wallet/ledger`, newest first. [currency] null = both; [per] 1-100
  /// (server default 20); [after] = the previous page's `next_cursor`.
  Future<LedgerPage> ledger({WalletCurrency? currency, int? per, String? after});

  /// `POST /wallet/transfer`. [idempotencyKey]: a new UUID per send attempt,
  /// the same one on a retry of that attempt.
  Future<TransferResult> transfer({
    required String recipientId,
    required int amount,
    required WalletCurrency currency,
    required String idempotencyKey,
  });
}

/// Offline demo wallet (no server): the demo balance and a short history.
class DemoWalletApi implements WalletApi {
  const DemoWalletApi();

  @override
  Future<Wallet> balance() async => Wallet.demo;

  @override
  Future<LedgerPage> ledger({WalletCurrency? currency, int? per, String? after}) async {
    final rows = _rows.where((e) => currency == null || e.currency == currency).toList();
    return LedgerPage(items: rows, total: rows.length);
  }

  @override
  Future<TransferResult> transfer({
    required String recipientId,
    required int amount,
    required WalletCurrency currency,
    required String idempotencyKey,
  }) async {
    if (amount <= 0) throw walletError(_demoError(400, ApiErrorCode.validation, field: 'amount'));
    final have = Wallet.demo.of(currency.currency);
    if (amount > have) throw walletError(_demoError(409, ApiErrorCode.insufficientFunds), currency: currency);
    return TransferResult(senderBalance: have - amount, transferred: amount, currency: currency);
  }

  static AppException _demoError(int status, String code, {String? field}) =>
      AppException('', statusCode: status, code: code, field: field);

  static final _now = DateTime.now();
  static final _rows = [
    LedgerEntry(
        entryId: 'demo:4', createdAt: _now.subtract(const Duration(minutes: 20)), currency: WalletCurrency.gold,
        credit: true, amount: 19, kind: 'payout', matchId: 'demo-match', gameCode: 'ludo', variantCode: 'classic'),
    LedgerEntry(
        entryId: 'demo:3', createdAt: _now.subtract(const Duration(minutes: 26)), currency: WalletCurrency.gold,
        credit: false, amount: 10, kind: 'entry_fee', matchId: 'demo-match', gameCode: 'ludo', variantCode: 'classic'),
    LedgerEntry(
        entryId: 'demo:2', createdAt: _now.subtract(const Duration(days: 1)), currency: WalletCurrency.gold,
        credit: true, amount: 2000, kind: 'signup_grant'),
    LedgerEntry(
        entryId: 'demo:1', createdAt: _now.subtract(const Duration(days: 1)), currency: WalletCurrency.token,
        credit: true, amount: 5000, kind: 'signup_grant'),
  ];
}

class RemoteWalletApi implements WalletApi {
  RemoteWalletApi(this._api, {this.retryDelay = const Duration(seconds: 2)});
  final ApiClient _api;

  /// Wait before the one retry of a transfer (no network / `RATE_LIMITED`).
  final Duration retryDelay;

  static Map<String, dynamic> _map(Object? body) =>
      body is Map ? body.cast<String, dynamic>() : throw const AppException('Something went wrong. Try again.');

  @override
  Future<Wallet> balance() async {
    try {
      return Wallet.fromJson(_map(await _api.get(ApiEndpoints.walletBalance)));
    } on AppException catch (e) {
      throw walletError(e);
    }
  }

  @override
  Future<LedgerPage> ledger({WalletCurrency? currency, int? per, String? after}) async {
    final query = <String, dynamic>{
      'currency': ?currency?.wire,
      'per': ?per,
      // The cursor query is `after`; `cursor=` is silently ignored (open issue 3).
      'after': ?after,
    };
    try {
      return LedgerPage.fromJson(_map(await _api.get(ApiEndpoints.walletLedger, query: query.isEmpty ? null : query)));
    } on AppException catch (e) {
      throw walletError(e);
    }
  }

  @override
  Future<TransferResult> transfer({
    required String recipientId,
    required int amount,
    required WalletCurrency currency,
    required String idempotencyKey,
  }) async {
    Future<TransferResult> send() async => TransferResult.fromJson(
          _map(await _api.post(
            ApiEndpoints.walletTransfer,
            body: {'recipient_id': recipientId, 'amount': amount, 'currency': currency.wire},
            headers: {'Idempotency-Key': idempotencyKey},
          )),
          fallback: currency,
        );
    try {
      try {
        return await send();
      } on AppException catch (e) {
        // No network / a timeout: it may have gone through. Retry once with
        // the SAME key; the reply says whether it did. RATE_LIMITED: wait,
        // retry once.
        if (!(e.isOffline || e.kind == AppErrorKind.timeout || e.isRateLimited)) rethrow;
        await Future<void>.delayed(retryDelay);
        return await send();
      }
    } on AppException catch (e) {
      throw walletError(e, currency: currency, transfer: true);
    }
  }
}

/// The wallet's player-facing text for [e] (03-wallet.md error tables).
/// Keeps the status / code / field so callers still decide on them.
AppException walletError(AppException e, {WalletCurrency? currency, bool transfer = false}) {
  final text = walletErrorText(e, currency: currency, transfer: transfer);
  if (text == e.message) return e;
  return AppException(text, kind: e.kind, statusCode: e.statusCode, code: e.code, field: e.field, until: e.until);
}

String walletErrorText(AppException e, {WalletCurrency? currency, bool transfer = false}) {
  if (e.isOffline || e.kind == AppErrorKind.timeout) return "Can't reach the server. Check your connection.";
  return switch (e.code) {
    ApiErrorCode.validation when transfer => 'Enter a whole amount above 0.',
    ApiErrorCode.insufficientFunds => 'Not enough ${(currency ?? WalletCurrency.gold).noun}.',
    ApiErrorCode.notFound => transfer ? "That player can't receive money." : 'Wallet unavailable.',
    ApiErrorCode.giftQuotaExceeded => "You've reached today's sending limit.",
    ApiErrorCode.rateLimited => 'Too many requests. Try again in a minute.',
    // App bugs (send to self, bad currency, a reused key): generic text.
    ApiErrorCode.badRequest || ApiErrorCode.conflict => 'Something went wrong. Try again.',
    // KILL_SWITCH_ENGAGED keeps the operator's message; session codes keep
    // "Your session has ended…" from the client.
    _ => e.message.isEmpty ? 'Something went wrong. Try again.' : e.message,
  };
}

/// The live wallet when signed in against the real API; the demo otherwise.
final walletApiProvider = Provider<WalletApi>((ref) {
  final live = ref.watch(useRemoteAuthProvider) && ref.watch(sessionProvider.select((u) => u != null));
  return live ? RemoteWalletApi(ref.watch(apiClientProvider)) : const DemoWalletApi();
});
