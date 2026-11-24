import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/social.dart';
import '../../data/models/wallet.dart';
import '../../services/app_exception.dart';
import '../../services/social_api.dart';
import '../../services/social_store.dart';
import '../../widgets/aura.dart';
import '../../widgets/player_avatar.dart';

/// Gift history (docs/services/09-social.md §4b): "Received" and "Sent",
/// newest first, `page=page+1` until `page == total_pages`. Re-read on open
/// (there is no push for a gift outside a game). Gifts from blocked players
/// are hidden.
class GiftsScreen extends ConsumerStatefulWidget {
  const GiftsScreen({super.key});

  @override
  ConsumerState<GiftsScreen> createState() => _GiftsScreenState();
}

class _GiftsScreenState extends ConsumerState<GiftsScreen> {
  int _tab = 0;
  final _pages = <int, _GiftPager>{};

  _GiftPager _pager(int tab) => _pages.putIfAbsent(tab, () {
        final api = ref.read(socialApiProvider);
        final p = _GiftPager(tab == 0 ? api.giftsReceived : api.giftsSent);
        p.load().whenComplete(() {
          if (mounted) setState(() {});
        });
        return p;
      });

  Future<void> _more(_GiftPager p) async {
    await p.more();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = _pager(_tab);
    final blocked = ref.watch(blockListProvider);
    final names = ref.watch(playerNameCacheProvider);
    final received = _tab == 0;
    final rows = withoutBlocked(p.items, blocked, (g) => received ? g.senderId : g.receiverId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(playerNameCacheProvider.notifier).ensure(rows.map((g) => received ? g.senderId : g.receiverId));
    });
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Gifts'),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          SegmentedTabs(labels: const ['Received', 'Sent'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
          const SizedBox(height: 16),
          if (p.loading && p.items.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else if (p.error != null && p.items.isEmpty)
            Column(
              children: [
                Text(socialErrorText(p.error!, SocialOp.load), style: AuraText.cardSub, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                SecondaryButton(
                  label: 'Retry',
                  onPressed: () {
                    _pages.remove(_tab);
                    setState(() {});
                  },
                ),
              ],
            )
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Text(received ? 'No gifts received yet' : 'No gifts sent yet',
                  textAlign: TextAlign.center, style: AuraText.body.copyWith(color: AuraColors.textSecondary)),
            )
          else ...[
            for (final g in rows) ...[
              _GiftRow(gift: g, received: received, other: names[received ? g.senderId : g.receiverId]),
              const SizedBox(height: 9),
            ],
            if (p.hasMore)
              Center(
                child: TextButton(
                  onPressed: p.loading ? null : () => _more(p),
                  child: Text(p.loading ? 'Loading…' : 'Load more'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _GiftPager {
  _GiftPager(this._read);
  final Future<PageList<Gift>> Function({int page, int perPage}) _read;
  final items = <Gift>[];
  int _page = 0;
  int _totalPages = 1;
  bool loading = false;
  AppException? error;

  bool get hasMore => _page < _totalPages;

  Future<void> load() => _fetch(1);
  Future<void> more() => hasMore && !loading ? _fetch(_page + 1) : Future.value();

  Future<void> _fetch(int page) async {
    loading = true;
    try {
      final p = await _read(page: page, perPage: 20);
      final seen = {for (final g in items) g.id};
      items.addAll(p.data.where((g) => !seen.contains(g.id)));
      _page = p.page;
      _totalPages = p.totalPages;
      error = null;
    } on AppException catch (e) {
      error = e;
    } finally {
      loading = false;
    }
  }
}

class _GiftRow extends StatelessWidget {
  const _GiftRow({required this.gift, required this.received, this.other});
  final Gift gift;
  final bool received;
  final UserCard? other;

  @override
  Widget build(BuildContext context) {
    final name = other?.name ?? 'Player';
    final look = GiftLook.of(gift.itemType);
    final amount = '${received ? '+' : '-'}${Wallet.formatAmount(gift.amount)} ${gift.currency.noun}';
    final when = gift.createdAt == null
        ? ''
        : MaterialLocalizations.of(context).formatShortDate(gift.createdAt!.toLocal());
    return AuraCard(
      padding: const EdgeInsets.all(11),
      child: Row(
        children: [
          AvatarDisc(glyph: name.substring(0, 1).toUpperCase(), avatarUrl: other?.avatarUrl, name: name, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(look?.icon ?? Icons.toll_rounded, size: 15, color: AuraColors.amber),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(received ? 'From $name' : 'To $name',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.cardTitle.copyWith(fontSize: 14)),
                    ),
                  ],
                ),
                if (gift.message != null) ...[
                  const SizedBox(height: 2),
                  Text(gift.message!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AuraText.cardSub),
                ],
                if (when.isNotEmpty) Text(when, style: AuraText.caption),
              ],
            ),
          ),
          Text(amount,
              style: TextStyle(
                  color: received ? AuraColors.green : AuraColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}
