import 'package:flutter/foundation.dart';

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
@immutable
class Wallet {
  const Wallet({required this.tokens, required this.goldCoins});

  /// Token (gems) and Gold balances, whole units.
  final int tokens;
  final int goldCoins;

  /// Balance of [kind].
  int of(Currency kind) => kind == Currency.gems ? tokens : goldCoins;

  /// "12,000"-style display strings.
  String get gems => formatAmount(tokens);
  String get gold => formatAmount(goldCoins);
  String display(Currency kind) => formatAmount(of(kind));

  static String formatAmount(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  /// `GET /wallet/balance`: `balance_tokens` → Tokens, `balance_gold` →
  /// Gold. Amounts arrive as strings ("80", maybe "80.00").
  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
        tokens: _amount(json['balance_tokens']),
        goldCoins: _amount(json['balance_gold']),
      );

  /// "12000" / "12000.00" → 12000.
  static int _amount(Object? v) => num.tryParse(v?.toString() ?? '')?.floor() ?? 0;

  static const demo = Wallet(tokens: 5000, goldCoins: 2000);
}
