import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/wallet.dart';
import '../../services/app_exception.dart';
import '../../services/wallet_api.dart';
import '../../services/wallet_store.dart';
import '../../widgets/aura.dart';
import '../match/match_detail_screen.dart';

/// Wallet / History (docs/services/03-wallet.md §2): the balances, then the
/// ledger newest first with an All / Tokens / Gold filter, grouped by day,
/// "Load more" at the end, pull to refresh from the top.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  static const _filters = <WalletCurrency?>[null, WalletCurrency.token, WalletCurrency.gold];

  late LedgerPager _pager;
  int _filter = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pager = LedgerPager(ref.read(walletApiProvider));
    _reload();
  }

  Future<void> _run(Future<void> Function() load) async {
    setState(() => _error = null);
    try {
      await load();
    } on AppException catch (e) {
      _error = e.message;
    } on Object {
      _error = 'Something went wrong. Try again.';
    }
    if (mounted) setState(() {});
  }

  Future<void> _reload() => _run(_pager.reload);

  Future<void> _refresh() async {
    await Future.wait([_reload(), ref.read(walletProvider.notifier).refresh(force: true)]);
  }

  void _setFilter(int i) {
    if (i == _filter) return;
    _filter = i;
    _pager.currency = _filters[i];
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    // A new session (sign-in / sign-out) swaps the wallet API: start over.
    ref.listen(walletApiProvider, (_, api) {
      _pager = LedgerPager(api, currency: _filters[_filter]);
      _reload();
    });
    final wallet = ref.watch(walletProvider).value;
    final rows = <Widget>[
      const SizedBox(height: 4),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _BalanceCard(label: 'TOKENS', kind: Currency.gems, amount: wallet?.gems ?? '—')),
            const SizedBox(width: 12),
            Expanded(child: _BalanceCard(label: 'GOLD', kind: Currency.gold, amount: wallet?.gold ?? '—')),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SegmentedTabs(labels: const ['All', 'Tokens', 'Gold'], index: _filter, onChanged: _setFilter),
      const SizedBox(height: 18),
      ..._history(),
      const SizedBox(height: 20),
    ];
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Wallet'),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AuraColors.accentGlow,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: rows),
      ),
    );
  }

  List<Widget> _history() {
    final p = _pager;
    if (!p.loaded) {
      if (_error != null) return [_Message(text: _error!, onRetry: _reload)];
      return const [_Spinner()];
    }
    if (p.isEmpty) return const [_Message(text: 'No history yet.')];
    final out = <Widget>[];
    String? day;
    for (final e in p.items) {
      final d = _dayLabel(e.createdAt);
      if (d != day) {
        day = d;
        if (out.isNotEmpty) out.add(const SizedBox(height: 8));
        out
          ..add(SectionBar(d))
          ..add(const SizedBox(height: 12));
      }
      out
        ..add(_EntryRow(key: ValueKey(e.entryId), entry: e))
        ..add(const SizedBox(height: 10));
    }
    if (_error != null) {
      out.add(_Message(text: _error!, onRetry: () => _run(_pager.loadMore)));
    } else if (p.loading) {
      out.add(const _Spinner());
    } else if (p.hasMore) {
      out.add(SecondaryButton(label: 'Load more', onPressed: () => _run(_pager.loadMore)));
    }
    return out;
  }

  static String _dayLabel(DateTime? t) {
    if (t == null) return 'Earlier';
    final local = t.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat(local.year == now.year ? 'EEE d MMM' : 'd MMM y').format(local);
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(AuraColors.accentGlow)),
          ),
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(text, style: AuraText.cardSub, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              SecondaryButton(label: 'Retry', onPressed: onRetry!),
            ],
          ],
        ),
      );
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.label, required this.kind, required this.amount});
  final String label;
  final Currency kind;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AuraText.section),
          const SizedBox(height: 12),
          Row(
            children: [
              CurrencyGlyph(kind: kind, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amount,
                    style: TextStyle(
                      fontFamily: AuraText.displayFamily,
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({super.key, required this.entry});
  final LedgerEntry entry;

  static IconData _icon(LedgerEntry e) => switch (e.kind) {
        'signup_grant' || 'opening_balance' || 'welcome_bonus' => Icons.card_giftcard_rounded,
        'entry_fee' || 'match_stake' || 'payout' || 'match_payout' => Icons.sports_esports_rounded,
        'refund' || 'match_refund' => Icons.undo_rounded,
        'buyin' || 'fee' || 'prize' => Icons.emoji_events_rounded,
        'transfer' => e.credit ? Icons.call_received_rounded : Icons.call_made_rounded,
        'gift' => Icons.redeem_rounded,
        'purchase' || 'iap_token_pack' || 'iap_gold_pack' => Icons.shopping_bag_rounded,
        'daily_bonus' || 'quest_reward' || 'achievement_reward' || 'inbox_reward' || 'referral_reward' =>
          Icons.star_rounded,
        'minigame_stake' || 'minigame_prize' => Icons.casino_rounded,
        'adjustment' => Icons.tune_rounded,
        _ => e.credit ? Icons.arrow_upward : Icons.arrow_downward,
      };

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final color = e.credit ? AuraColors.green : AuraColors.danger;
    final time = e.createdAt == null ? null : DateFormat.Hm().format(e.createdAt!.toLocal());
    final sub = [?e.detail, ?time].join(' · ');
    return AuraCard(
      padding: const EdgeInsets.all(12),
      // A match row opens that match (08-progress-and-history.md §6).
      onTap: e.matchId == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: e.matchId!))),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon(e), color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.label,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: AuraText.cardSub, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (e.currency != null) ...[
                CurrencyGlyph(kind: e.currency!.currency, size: 14),
                const SizedBox(width: 5),
              ],
              Text(
                e.signedAmount,
                style: TextStyle(
                  fontFamily: AuraText.displayFamily,
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
