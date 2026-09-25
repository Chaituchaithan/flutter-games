import 'package:flutter/foundation.dart';

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

/// The player's currency balances (display strings).
@immutable
class Wallet {
  const Wallet({required this.gems, required this.gold});
  final String gems;
  final String gold;

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
        gems: json['gems']?.toString() ?? '0',
        gold: json['gold']?.toString() ?? '0',
      );

  static const demo = Wallet(gems: '5,000', gold: '2,000');
}
