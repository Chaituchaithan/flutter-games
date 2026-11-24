import 'package:flutter/foundation.dart';

import '../../utils/amount.dart';
import '../../widgets/aura.dart' show Currency;

/// A purchasable currency pack (Tokens or Gold).
@immutable
class StorePack {
  const StorePack({
    required this.name,
    required this.amount,
    required this.price,
    this.bonus,
    this.badge,
    this.big = false,
  });

  final String name;
  final String amount;
  final String price;
  final String? bonus;
  final String? badge;
  final bool big;

  factory StorePack.fromJson(Map<String, dynamic> json) => StorePack(
        name: json['name'] as String? ?? '',
        amount: json['amount']?.toString() ?? '0',
        price: json['price'] as String? ?? '',
        bonus: json['bonus'] as String?,
        badge: json['badge'] as String?,
        big: json['big'] as bool? ?? false,
      );
}

/// The player's currency balances — the one source every screen reads.
/// `GET /wallet/balance` (docs/services/03-wallet.md §1); also known as
/// [WalletBalance].
@immutable
class Wallet {
  const Wallet({required this.tokens, required this.goldCoins, this.userId, this.updatedAt});

  /// Token (gems) and Gold balances, whole units.
  final int tokens;
  final int goldCoins;

  /// The signed-in player (`user_id`); null for the demo wallet.
  final String? userId;

  /// When the wallet last changed (not when it was read).
  final DateTime? updatedAt;

  /// Balance of [kind].
  int of(Currency kind) => kind == Currency.gems ? tokens : goldCoins;

  /// "12,000"-style display strings.
  String get gems => formatAmount(tokens);
  String get gold => formatAmount(goldCoins);
  String display(Currency kind) => formatAmount(of(kind));

  static String formatAmount(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  /// This wallet with [kind]'s balance replaced by a server-sent value (e.g. a
  /// transfer's `sender_balance`). Never computed on the device.
  Wallet withBalance(Currency kind, int amount) => Wallet(
        tokens: kind == Currency.gems ? amount : tokens,
        goldCoins: kind == Currency.gold ? amount : goldCoins,
        userId: userId,
        updatedAt: updatedAt,
      );

  /// `GET /wallet/balance`: `balance_tokens` → Tokens, `balance_gold` →
  /// Gold. Amounts arrive as strings ("100") or numbers; both are parsed.
  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
        tokens: parseAmount(json['balance_tokens']),
        goldCoins: parseAmount(json['balance_gold']),
        userId: json['user_id'] is String ? json['user_id'] as String : null,
        updatedAt: json['updated_at'] is String ? DateTime.tryParse(json['updated_at'] as String) : null,
      );

  static const demo = Wallet(tokens: 5000, goldCoins: 2000);
}

/// The name the wallet hand-off (03-wallet.md) uses for [Wallet].
typedef WalletBalance = Wallet;
