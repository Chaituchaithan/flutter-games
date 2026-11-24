import 'package:flutter/foundation.dart';

import '../../utils/amount.dart';
import '../../widgets/aura.dart' show Currency;
import 'store_pack.dart';

export 'store_pack.dart' show Wallet, WalletBalance;

/// The two wallet currencies (`token` / `gold` on the wire). The app's
/// [Currency.gems] is the token currency.
enum WalletCurrency {
  token('token'),
  gold('gold');

  const WalletCurrency(this.wire);
  final String wire;

  Currency get currency => this == token ? Currency.gems : Currency.gold;

  /// "tokens" / "gold" in player-facing text.
  String get noun => this == token ? 'tokens' : 'gold';

  static WalletCurrency of(Currency c) => c == Currency.gems ? token : gold;

  /// Null for anything that isn't `token` or `gold`.
  static WalletCurrency? tryParse(Object? v) => switch (v) {
        'token' || 'tokens' => token,
        'gold' => gold,
        _ => null,
      };
}

/// One wallet movement from `GET /wallet/ledger` (03-wallet.md §2).
@immutable
class LedgerEntry {
  const LedgerEntry({
    required this.entryId,
    required this.createdAt,
    required this.currency,
    required this.credit,
    required this.amount,
    required this.kind,
    this.counterparty,
    this.counterpartyUserId,
    this.tournamentId,
    this.matchId,
    this.itemKind,
    this.itemName,
    this.gameCode,
    this.variantCode,
  });

  /// Unique and stable (`ledger:<n>` / `match:<n>:<kind>`); the list key.
  final String entryId;
  final DateTime? createdAt;

  /// Null when the server sends a currency the app doesn't know.
  final WalletCurrency? currency;

  /// `direction`: credit (into the wallet, `+`) or debit (`-`).
  final bool credit;

  /// Always positive; the sign comes from [credit].
  final int amount;
  final String kind;
  final String? counterparty;
  final String? counterpartyUserId;
  final String? tournamentId;
  final String? matchId;
  final String? itemKind;
  final String? itemName;
  final String? gameCode;
  final String? variantCode;

  /// `+19` / `-10` (with thousands separators).
  String get signedAmount => '${credit ? '+' : '-'}${Wallet.formatAmount(amount)}';

  /// A match row (entry fee, payout or refund of a game).
  bool get isMatch => matchId != null;

  static String? _s(Object? v) => v is String && v.isNotEmpty ? v : null;

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        entryId: j['entry_id']?.toString() ?? '',
        createdAt: j['created_at'] is String ? DateTime.tryParse(j['created_at'] as String) : null,
        currency: WalletCurrency.tryParse(j['currency']),
        credit: j['direction'] != 'debit',
        amount: parseAmount(j['amount']).abs(),
        kind: _s(j['kind']) ?? '',
        counterparty: _s(j['counterparty']),
        counterpartyUserId: _s(j['counterparty_user_id']),
        tournamentId: _s(j['tournament_id']),
        matchId: _s(j['match_id']),
        itemKind: _s(j['item_kind']),
        itemName: _s(j['item_name']),
        gameCode: _s(j['game_code']),
        variantCode: _s(j['variant_code']),
      );

  /// The player-facing label for this row's `kind`. Unknown kinds read
  /// "Wallet update"; `match_*` kinds read like Ludo's `entry_fee` & co.
  String get label => switch (kind) {
        'signup_grant' => 'Welcome credit',
        'opening_balance' => 'Opening balance',
        'entry_fee' || 'match_stake' => 'Entry fee',
        'payout' || 'match_payout' => 'Winnings',
        'refund' || 'match_refund' => 'Refund',
        'buyin' => 'Tournament buy-in',
        'fee' => 'Tournament fee',
        'prize' => 'Tournament prize',
        'transfer' => credit ? 'Received' : 'Sent',
        'gift' => credit ? 'Gift received' : 'Gift sent',
        'purchase' => 'Purchase',
        'iap_token_pack' => 'Bought tokens',
        'iap_gold_pack' => 'Bought gold',
        'daily_bonus' ||
        'welcome_bonus' ||
        'quest_reward' ||
        'achievement_reward' ||
        'inbox_reward' ||
        'referral_reward' =>
          'Bonus',
        'minigame_stake' || 'minigame_prize' => 'Bonus game',
        'adjustment' => 'Adjustment',
        _ => 'Wallet update',
      };

  /// A short detail line: the game for match rows (never the counterparty),
  /// the item for purchases, "a player" for transfers and gifts.
  String? get detail {
    if (gameCode != null) return gameName(gameCode!);
    if (kind == 'purchase') return itemName;
    if (kind == 'transfer' || kind == 'gift') return credit ? 'From a player' : 'To a player';
    return null;
  }

  /// `snake-and-ladder` → "Snake And Ladder". A catalogue name may replace it.
  static String gameName(String code) => code
      .split(RegExp(r'[-_ ]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// One page of the ledger: list shape 3 (`{items, page, pages, total,
/// next_cursor}`). Load more with `after = nextCursor` until it is null.
@immutable
class LedgerPage {
  const LedgerPage({required this.items, this.page = 1, this.pages = 1, this.total = 0, this.nextCursor});

  final List<LedgerEntry> items;
  final int page;
  final int pages;

  /// Every row for the filter; 0 = "No history yet".
  final int total;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  factory LedgerPage.fromJson(Map<String, dynamic> j) {
    final raw = j['items'];
    final cursor = j['next_cursor'];
    return LedgerPage(
      items: raw is List
          ? [for (final e in raw) if (e is Map) LedgerEntry.fromJson(e.cast<String, dynamic>())]
          : const [],
      page: parseAmount(j['page']),
      pages: parseAmount(j['pages']),
      total: parseAmount(j['total']),
      nextCursor: cursor is String && cursor.isNotEmpty ? cursor : null,
    );
  }
}

/// `POST /wallet/transfer` reply (03-wallet.md §4). Money arrives as strings.
@immutable
class TransferResult {
  const TransferResult({required this.senderBalance, required this.transferred, required this.currency});

  /// The sender's new balance in [currency]: update the balance chip from it.
  final int senderBalance;
  final int transferred;
  final WalletCurrency currency;

  /// A retried send with the same key gets the first reply again (fields may
  /// come in another order; parsed by name).
  factory TransferResult.fromJson(Map<String, dynamic> j, {WalletCurrency fallback = WalletCurrency.gold}) =>
      TransferResult(
        senderBalance: parseAmount(j['sender_balance']),
        transferred: parseAmount(j['transferred']),
        currency: WalletCurrency.tryParse(j['currency']) ?? fallback,
      );
}

/// One player's line in a game socket's `game.wallet_update` (§5).
@immutable
class WalletPayout {
  const WalletPayout({required this.userId, required this.amount, required this.result});
  final String userId;
  final int amount;

  /// `win` · `loss` · `forfeit` · `draw` (for the result screen only).
  final String result;
}

/// A game socket's `game.wallet_update` `data`: the end-of-match payouts.
/// Show the player's own [payoutFor], then re-read the balance
/// (`WalletStore.gameEnded`). Never add it to the balance on the device.
@immutable
class WalletUpdate {
  const WalletUpdate({required this.matchId, required this.payouts, this.potAmount = 0, this.rakeAmount = 0});

  final String? matchId;
  final List<WalletPayout> payouts;
  final int potAmount;
  final int rakeAmount;

  WalletPayout? payoutFor(String? userId) {
    for (final p in payouts) {
      if (p.userId == userId) return p;
    }
    return null;
  }

  factory WalletUpdate.fromJson(Map<String, dynamic> j) {
    final raw = j['payouts'];
    return WalletUpdate(
      matchId: j['match_id']?.toString(),
      payouts: raw is List
          ? [
              for (final p in raw)
                if (p is Map)
                  WalletPayout(
                    userId: p['user_id']?.toString() ?? '',
                    amount: parseAmount(p['amount']),
                    result: p['result']?.toString() ?? '',
                  ),
            ]
          : const [],
      potAmount: parseAmount(j['pot_amount']),
      rakeAmount: parseAmount(j['rake_amount']),
    );
  }
}
