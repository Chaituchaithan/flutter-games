import '../../services/api_client.dart';
import '../../widgets/aura.dart' show Currency;
import '../models/store_pack.dart';

/// Wallet balance + purchasable packs.
abstract class StoreSource {
  Future<Wallet> wallet();
  Future<List<StorePack>> packs(Currency kind);
}

/// The wallet + pack lists that used to live inline in `store_screen.dart`.
class StaticStoreSource implements StoreSource {
  const StaticStoreSource();

  @override
  Future<Wallet> wallet() async => Wallet.demo;

  @override
  Future<List<StorePack>> packs(Currency kind) async =>
      kind == Currency.gold ? _gold : _tokens;

  static const _tokens = [
    StorePack(name: 'POUCH', amount: '1,000', price: '\$0.99'),
    StorePack(name: 'BAG', amount: '5,500', bonus: '+10%', price: '\$3.99', badge: '+10%'),
    StorePack(name: 'CHEST', amount: '12,000', bonus: '+2,000 bonus', price: '\$7.99', badge: 'POPULAR', big: true),
    StorePack(name: 'CRATE', amount: '30,000', bonus: '+25%', price: '\$14.99', badge: '+25%'),
    StorePack(name: 'VAULT', amount: '70,000', bonus: '+40%', price: '\$29.99', badge: '+40%', big: true),
    StorePack(name: 'TREASURY', amount: '150,000', bonus: 'MEGA', price: '\$49.99', badge: 'MEGA', big: true),
  ];

  static const _gold = [
    StorePack(name: 'STACK', amount: '500', price: '\$1.99'),
    StorePack(name: 'PILE', amount: '1,200', bonus: '+100 bonus', price: '\$3.99', badge: 'POPULAR', big: true),
    StorePack(name: 'HOARD', amount: '3,000', bonus: '+25%', price: '\$8.99', badge: '+25%'),
    StorePack(name: 'FORTUNE', amount: '8,000', bonus: 'MEGA', price: '\$19.99', badge: 'MEGA', big: true),
  ];
}

/// Live-API implementation (off until remote sources are switched on).
class RemoteStoreSource implements StoreSource {
  const RemoteStoreSource(this._api);
  final ApiClient _api;

  @override
  Future<Wallet> wallet() async =>
      Wallet.fromJson(await _api.get('/wallet') as Map<String, dynamic>);

  @override
  Future<List<StorePack>> packs(Currency kind) async {
    final data = await _api.get('/store/packs', query: {'currency': kind.name}) as List<dynamic>;
    return data.map((e) => StorePack.fromJson(e as Map<String, dynamic>)).toList();
  }
}
