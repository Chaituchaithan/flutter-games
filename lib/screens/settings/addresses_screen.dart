import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/account.dart';
import '../../services/account_service.dart';
import '../../services/account_store.dart';
import '../../services/app_exception.dart';
import '../../widgets/aura.dart';
import 'account_widgets.dart';

/// Settings → Addresses (02-profile-and-sessions.md §5): home and billing,
/// with "Billing same as home" (= no billing address stored). Read from
/// `GET /users/me`; each save is the whole address.
class AddressesScreen extends ConsumerStatefulWidget {
  const AddressesScreen({super.key});

  @override
  ConsumerState<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends ConsumerState<AddressesScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(accountStoreProvider.notifier).ensure();
  }

  String _summary(Address? a) {
    // A home row holding only a country is "not filled in".
    if (a == null || !a.isFilled) return 'Not added';
    return [a.line1, a.city, a.postalCode, a.country].whereType<String>().where((s) => s.isNotEmpty).join(', ');
  }

  Future<void> _edit(AddressKind kind, Address? current) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => EditAddressScreen(kind: kind, initial: current),
    ));
  }

  Future<void> _toggleSame(bool same, Me me) async {
    if (same) {
      setState(() => _busy = true);
      try {
        await ref.read(accountStoreProvider.notifier).removeAddress(AddressKind.billing);
      } on AppException catch (e) {
        if (mounted) showAuraToast(context, accountErrorText(e, AccountOp.address), kind: AuraToastKind.error);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else {
      await _edit(AddressKind.billing, me.addresses.billing ?? (me.addresses.home?.isFilled == true ? me.addresses.home : null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(accountStoreProvider);
    return BusyGuard(
      busy: _busy,
      child: AuraScaffold(
        appBar: const AuraAppBar(title: 'Addresses'),
        scroll: true,
        showGlow: false,
        body: me == null
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: AuraColors.accentGlow)),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  Text('Used only when a payment or prize needs an address.', style: AuraText.cardSub),
                  const SizedBox(height: 16),
                  const SectionHeader('Home'),
                  const SizedBox(height: 10),
                  SettingsGroup(children: [
                    SettingsRow(
                      label: 'Home address',
                      sub: _summary(me.addresses.home),
                      onTap: () => _edit(AddressKind.home, me.addresses.home),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  const SectionHeader('Billing'),
                  const SizedBox(height: 10),
                  SettingsGroup(children: [
                    SettingsToggle(
                      label: 'Billing same as home',
                      value: me.addresses.billing == null,
                      onChanged: (v) => _toggleSame(v, me),
                    ),
                    if (me.addresses.billing != null)
                      SettingsRow(
                        label: 'Billing address',
                        sub: _summary(me.addresses.billing),
                        onTap: () => _edit(AddressKind.billing, me.addresses.billing),
                      ),
                  ]),
                ],
              ),
      ),
    );
  }
}

/// Edit one address; pops `true` when saved.
class EditAddressScreen extends ConsumerStatefulWidget {
  const EditAddressScreen({super.key, required this.kind, this.initial});
  final AddressKind kind;
  final Address? initial;

  @override
  ConsumerState<EditAddressScreen> createState() => _EditAddressScreenState();
}

class _EditAddressScreenState extends ConsumerState<EditAddressScreen> {
  late final _line1 = TextEditingController(text: widget.initial?.line1 ?? '');
  late final _line2 = TextEditingController(text: widget.initial?.line2 ?? '');
  late final _city = TextEditingController(text: widget.initial?.city ?? '');
  late final _region = TextEditingController(text: widget.initial?.region ?? '');
  late final _postal = TextEditingController(text: widget.initial?.postalCode ?? '');
  late final _country = TextEditingController(
      text: widget.initial?.country ?? ref.read(accountStoreProvider)?.profile.country ?? '');
  Map<String, String> _errors = {};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_line1, _line2, _city, _region, _postal, _country]) {
      c.dispose();
    }
    super.dispose();
  }

  Address get _address => Address(
        line1: _line1.text.trim(),
        line2: _line2.text.trim(),
        city: _city.text.trim(),
        region: _region.text.trim(),
        postalCode: _postal.text.trim(),
        country: _country.text.trim().toUpperCase(),
      );

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final a = _address;
    final errs = AccountRules.address(a);
    setState(() => _errors = errs);
    if (errs.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(accountStoreProvider.notifier).saveAddress(widget.kind, a);
      if (!mounted) return;
      showAuraToast(context, 'Address saved', kind: AuraToastKind.success);
      Navigator.pop(context, true);
    } on AppException catch (e) {
      if (!mounted) return;
      final text = accountErrorText(e, AccountOp.address);
      if (e.isValidation && e.field != null) {
        setState(() => _errors = {e.field!: text});
      } else {
        showAuraToast(context, text, kind: AuraToastKind.error);
      }
    } on Object catch (_) {
      if (mounted) showAuraToast(context, 'Something went wrong. Try again.', kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key, String hint, TextEditingController c, {IconData? icon, TextInputType? keyboard}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AuraTextField(hint: hint, icon: icon, controller: c, keyboardType: keyboard, errorText: _errors[key]),
      );

  @override
  Widget build(BuildContext context) {
    return BusyGuard(
      busy: _saving,
      child: AuraScaffold(
        appBar: AuraAppBar(title: widget.kind == AddressKind.home ? 'Home address' : 'Billing address'),
        scroll: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            if (widget.kind == AddressKind.home) ...[
              Text('Your home country is also your profile country.', style: AuraText.cardSub),
              const SizedBox(height: 16),
            ],
            _field('line1', 'Address line 1', _line1, icon: Icons.home_outlined),
            _field('line2', 'Address line 2 (optional)', _line2, icon: Icons.apartment_outlined),
            _field('city', 'City', _city, icon: Icons.location_city_outlined),
            _field('region', 'State or region (optional)', _region, icon: Icons.map_outlined),
            _field('postal_code', 'Postal code', _postal, icon: Icons.markunread_mailbox_outlined),
            _field('country', 'Country code (e.g. IN, GB)', _country, icon: Icons.flag_outlined),
            const SizedBox(height: 16),
            GradientButton(label: 'Save address', loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
