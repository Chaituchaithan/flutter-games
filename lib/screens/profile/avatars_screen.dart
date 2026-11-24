import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/account.dart';
import '../../data/models/store.dart';
import '../../services/account_service.dart';
import '../../services/account_store.dart';
import '../../services/app_exception.dart';
import '../../services/progress_service.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';
import '../../widgets/player_avatar.dart';
import '../economy/purchase_confirm_screen.dart';

/// Avatars picker — "Choose Avatar" (02-profile-and-sessions.md §3). The
/// catalogue (`GET /cosmetics/avatars`) with free and owned avatars
/// selectable and the rest locked ("Buy" / "Reach level N"). Saving is
/// `PATCH /users/me/profile {avatar_id}`. There is no photo upload.
class AvatarsScreen extends ConsumerStatefulWidget {
  const AvatarsScreen({super.key});

  @override
  ConsumerState<AvatarsScreen> createState() => _AvatarsScreenState();
}

class _AvatarsScreenState extends ConsumerState<AvatarsScreen> {
  int? _selected;
  bool _saving = false;

  bool _selectable(AvatarItem a, Inventory inv) => a.isFree || inv.avatarIds.contains(a.id);

  void _refresh() {
    ref.invalidate(avatarCatalogueProvider);
    ref.invalidate(inventoryProvider);
  }

  Future<void> _save(int? current) async {
    final id = _selected;
    if (id == null || id == current) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(accountStoreProvider.notifier).pickAvatar(id);
      if (!mounted) return;
      showAuraToast(context, 'Avatar updated', kind: AuraToastKind.success);
      Navigator.of(context).maybePop();
    } on AppException catch (e) {
      if (!mounted) return;
      showAuraToast(context, accountErrorText(e, AccountOp.avatar), kind: AuraToastKind.error);
      // Locked after all (403 FORBIDDEN): show the picker as the server sees it.
      if (e.code == ApiErrorCode.forbidden) {
        setState(() => _selected = null);
        _refresh();
      }
    } on Object catch (_) {
      if (mounted) showAuraToast(context, 'Something went wrong. Try again.', kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _lockLabel(AvatarItem a) {
    if ((a.requiredLevel ?? 0) > ref.read(playerLevelProvider)) return 'Lv ${a.requiredLevel}';
    if (a.isPurchasable) return 'Buy';
    if (a.requiredLevel != null) return 'Lv ${a.requiredLevel}';
    return 'Locked';
  }

  void _lockedTap(AvatarItem a) {
    // For sale: buy it here (`POST /cosmetics/avatars/{id}/purchase`, 11-store.md §6b).
    final store = StoreAvatar(a);
    final mine = ref.read(playerLevelProvider);
    if (a.requiredLevel != null && mine < a.requiredLevel!) {
      showAuraToast(context, 'Reach level ${a.requiredLevel} to unlock ${a.name}. You are level $mine.', kind: AuraToastKind.info);
      return;
    }
    if (store.forSale) {
      showBuySheet(
        context,
        BuyRequest(
          name: a.name,
          detail: a.requiredLevel == null ? null : 'Needs level ${a.requiredLevel}',
          currency: store.currency,
          price: a.priceAmount,
          icon: Icons.face_retouching_natural,
          successText: '${a.name} unlocked',
          buy: (c) => c.buyAvatar(store),
        ),
      );
      return;
    }
    final why = a.isPurchasable
        ? 'Buy ${a.name} in the Store${a.priceAmount == null ? '' : ' for ${a.priceAmount} ${a.priceCurrency ?? ''}'}.'
        : a.requiredLevel != null
            ? 'Reach level ${a.requiredLevel} to unlock ${a.name}.'
            : "${a.name} isn't unlocked yet.";
    showAuraToast(context, why.trim(), kind: AuraToastKind.info);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final me = ref.watch(accountStoreProvider);
    final current = me?.profile.avatarId ?? int.tryParse(user.avatarId ?? '');
    final catalogue = ref.watch(avatarCatalogueProvider);
    final inventory = ref.watch(inventoryProvider).value ?? const Inventory();
    final glyph = me?.glyph ?? user.initials;
    final selectedId = _selected ?? current;
    final items = catalogue.value ?? const <AvatarItem>[];
    AvatarItem? selectedItem;
    for (final a in items) {
      if (a.id == selectedId) selectedItem = a;
    }

    return BusyGuard(
      busy: _saving,
      child: AuraScaffold(
        appBar: const AuraAppBar(title: 'Choose Avatar'),
        scroll: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: AvatarDisc(
                glyph: glyph,
                code: selectedItem?.code,
                avatarUrl: selectedItem?.imageUrl ?? (selectedId == current ? user.avatarUrl : null),
                name: user.displayName,
                size: 96,
                glow: true,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              selectedItem?.name ?? 'Tap a tile to equip it',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AuraColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            if (catalogue.isLoading && items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(color: AuraColors.accentGlow)),
              )
            else if (catalogue.hasError && items.isEmpty)
              Column(
                children: [
                  Text("Couldn't load avatars.", style: AuraText.cardSub),
                  const SizedBox(height: 12),
                  SecondaryButton(label: 'Retry', onPressed: _refresh),
                ],
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 12.0;
                  final tileWidth = (constraints.maxWidth - gap * 3) / 4;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final a in items)
                        _AvatarTile(
                          glyph: glyph,
                          item: a,
                          size: tileWidth,
                          selected: a.id == selectedId,
                          lockLabel: _selectable(a, inventory) ? null : _lockLabel(a),
                          onTap: () => _selectable(a, inventory) ? setState(() => _selected = a.id) : _lockedTap(a),
                        ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 28),
            GradientButton(label: 'Save Avatar', loading: _saving, onPressed: () => _save(current)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _AvatarTile extends StatelessWidget {
  const _AvatarTile({
    required this.glyph,
    required this.item,
    required this.size,
    required this.selected,
    required this.onTap,
    this.lockLabel,
  });

  final String glyph;
  final AvatarItem item;
  final double size;
  final bool selected;
  final String? lockLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = avatarColor(code: item.code, url: item.imageUrl);
    final locked = lockLabel != null;
    final tile = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.18)!,
            Color.lerp(color, Colors.black, 0.12)!,
          ],
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Opacity(
              opacity: locked ? 0.45 : 1,
              child: Text(
                glyph,
                style: TextStyle(
                  fontFamily: AuraText.displayFamily,
                  color: Colors.white,
                  fontSize: size * 0.30,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (locked)
            Positioned(
              left: 0,
              right: 0,
              bottom: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_rounded, color: Colors.white, size: 12),
                  const SizedBox(width: 3),
                  Text(lockLabel!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: locked ? '${item.name}, locked' : item.name,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size,
          height: size,
          child: selected
              ? Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        gradient: AuraGradients.brand,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: tile,
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          gradient: AuraGradients.brand,
                          shape: BoxShape.circle,
                          border: Border.all(color: AuraColors.bgBase, width: 1.5),
                        ),
                        child: const Icon(Icons.check, color: Colors.white, size: 12),
                      ),
                    ),
                  ],
                )
              : tile,
        ),
      ),
    );
  }
}
