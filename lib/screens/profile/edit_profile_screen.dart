import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../app/main_shell.dart';
import '../../app/routes.dart';
import '../../data/languages.dart';
import '../../data/models/account.dart';
import '../../services/account_service.dart';
import '../../services/account_store.dart';
import '../../services/app_exception.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';
import '../../widgets/player_avatar.dart';

/// Edit profile (02-profile-and-sessions.md §2): display name, avatar, bio,
/// birthday, language, country, full name, gender, time zone and contact
/// channel. Seeds from `GET /users/me` and saves the whole form in one
/// `PATCH /users/me/profile`; a `VALIDATION_ERROR` marks its field and keeps
/// the input.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  static const _countries = <(String, String)>[
    ('🇫🇷', 'FR'),
    ('🇩🇪', 'DE'),
    ('🇮🇹', 'IT'),
    ('🇧🇷', 'BR'),
    ('🇮🇳', 'IN'),
    ('🇺🇸', 'US'),
    ('🇯🇵', 'JP'),
    ('🇬🇧', 'GB'),
  ];

  /// IANA zones offered in the picker (plus the saved one if not listed).
  static const _zones = [
    'Asia/Kolkata',
    'Europe/London',
    'Europe/Paris',
    'Europe/Berlin',
    'Europe/Rome',
    'America/New_York',
    'America/Chicago',
    'America/Los_Angeles',
    'America/Sao_Paulo',
    'Asia/Tokyo',
    'Asia/Dubai',
    'Asia/Singapore',
    'Australia/Sydney',
    'UTC',
  ];

  static const _genderLabels = {
    'female': 'Female',
    'male': 'Male',
    'non_binary': 'Non-binary',
    'prefer_not_to_say': 'Prefer not to say',
  };

  static const _channelLabels = {'email': 'Email', 'push': 'Push', 'sms': 'SMS'};

  // Seeded from the signed-in player (GET /users/me).
  late final _initial = ref.read(currentUserProvider);
  late Me? _me = ref.read(accountStoreProvider);
  late String? _selected = _initial.country;
  late final _nameCtrl = TextEditingController(text: _initial.displayName);
  late final _bioCtrl = TextEditingController(text: _initial.bio);
  late final _fullNameCtrl = TextEditingController(text: _me?.fullName ?? '');
  // Saved language, else the one picked on first launch.
  late int _language = languageIndexFor(_initial.preferredLanguage) ?? ref.read(languageProvider);
  late DateTime? _dob = DateTime.tryParse(_initial.dateOfBirth ?? '');
  late String? _gender = _me?.gender;
  late String? _timezone = _me?.timezone;
  late String _channel = _me?.preferredChannel ?? 'email';
  bool _saving = false;

  /// Field → the rule to show next to it (client check or the server's 400).
  final Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _bioCtrl.addListener(() => setState(() {})); // the n/140 counter
    if (_me == null) {
      ref.read(accountStoreProvider.notifier).ensure().then((m) {
        if (!mounted || m == null) return;
        setState(() {
          _me = m;
          if (_fullNameCtrl.text.isEmpty) _fullNameCtrl.text = m.fullName ?? '';
          _gender = m.gender;
          _timezone = m.timezone;
          _channel = m.preferredChannel;
        });
      });
    }
  }

  /// Players must be at least 13 (and never born in the future).
  static DateTime get _latestDob {
    final now = DateTime.now();
    return DateTime(now.year - 13, now.month, now.day);
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// "12 Mar 1998".
  static String formatDob(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// API format "YYYY-MM-DD".
  static String _apiDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDob() async {
    FocusScope.of(context).unfocus();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: _latestDob,
      helpText: context.l10n.dateOfBirth,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AuraColors.brandPurple,
            onPrimary: Colors.white,
            surface: AuraColors.bgRaised,
            onSurface: AuraColors.textPrimary,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: AuraColors.bgRaised),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _dob = picked);
  }

  Future<void> _pickLanguage() async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _LanguageSheet(selected: _language),
    );
    if (picked != null && mounted) setState(() => _language = picked);
  }

  Future<void> _pickTimezone() async {
    FocusScope.of(context).unfocus();
    final zones = [
      if (_timezone != null && !_zones.contains(_timezone)) _timezone!,
      ..._zones,
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _OptionSheet(title: 'Time zone', options: {for (final z in zones) z: z}, selected: _timezone),
    );
    if (picked != null && mounted) setState(() => _timezone = picked);
  }

  Future<void> _pickGender() async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _OptionSheet(
        title: 'Gender',
        options: const {'': 'Not set', ..._genderLabels},
        selected: _gender ?? '',
      ),
    );
    if (picked != null && mounted) setState(() => _gender = picked.isEmpty ? null : picked);
  }

  /// The grid, plus the player's saved country if it isn't one of the 8.
  List<(String, String)> get _countryOptions {
    final c = _initial.country;
    if (c == null || _countries.any((e) => e.$2 == c)) return _countries;
    return [..._countries, (_flagFor(c), c)];
  }

  /// "IN" → 🇮🇳 (regional indicator letters).
  static String _flagFor(String code) =>
      code.length == 2 ? String.fromCharCodes(code.toUpperCase().codeUnits.map((u) => 0x1F1E6 + u - 0x41)) : '🏳️';

  /// After Save: land on the Profile tab (from Profile or from Settings).
  void _toProfile() {
    ref.read(mainTabProvider.notifier).select(3); // Profile tab
    Navigator.popUntil(context, ModalRoute.withName(Routes.home));
  }

  /// Client checks matching the server rules (§2). True when the form is valid.
  bool _validate() {
    _errors.clear();
    final name = AccountRules.displayName(_nameCtrl.text);
    if (name != null) _errors['display_name'] = _nameCtrl.text.trim().isEmpty ? context.l10n.displayNameEmpty : name;
    final bio = AccountRules.bio(_bioCtrl.text.trim());
    if (bio != null) _errors['bio'] = bio;
    final full = AccountRules.fullName(_fullNameCtrl.text);
    if (full != null) _errors['full_name'] = full;
    final dob = AccountRules.dateOfBirth(_dob);
    if (dob != null) _errors['date_of_birth'] = dob;
    setState(() {});
    return _errors.isEmpty;
  }

  /// PATCH /users/me/profile with only the fields that changed.
  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_validate()) return;
    final me = _me;
    final name = _nameCtrl.text.trim();
    final bio = _bioCtrl.text.trim();
    final fullName = _fullNameCtrl.text.trim();
    final lang = appLanguages[_language].code;
    final dob = _dob == null ? null : _apiDate(_dob!);
    final patch = ProfilePatch(
      displayName: name != _initial.displayName ? name : null,
      // `""` empties the bio; treat "" and null the same when comparing.
      bio: bio != _initial.bio ? bio : null,
      country: _selected != _initial.country ? _selected : null,
      preferredLanguage: lang != _initial.preferredLanguage ? lang : null,
      dateOfBirth: dob != null && dob != _initial.dateOfBirth ? dob : null,
      // Only gender can be cleared; an emptied full name keeps its value.
      fullName: fullName.isNotEmpty && fullName != (me?.fullName ?? '') ? fullName : null,
      gender: _gender != null && _gender != me?.gender ? _gender : null,
      clearGender: _gender == null && me?.gender != null,
      timezone: _timezone != null && _timezone != me?.timezone ? _timezone : null,
      preferredChannel: _channel != (me?.preferredChannel ?? 'email') ? _channel : null,
    );
    if (patch.isEmpty) {
      _toProfile();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(accountStoreProvider.notifier).updateProfile(patch);
      if (!mounted) return;
      showAuraToast(context, context.l10n.profileSaved);
      _toProfile();
    } on AppException catch (e) {
      if (!mounted) return;
      final text = accountErrorText(e, AccountOp.profile);
      // Mark the field (taken name → the name field) and keep the input.
      final field = e.code == ApiErrorCode.conflict ? 'display_name' : (e.isValidation ? e.field : null);
      if (field != null && _fieldShown.contains(field)) {
        setState(() => _errors[field] = text);
      } else {
        showAuraToast(context, text, kind: AuraToastKind.error);
      }
    } on Object catch (_) {
      if (mounted) showAuraToast(context, "Couldn't save your profile. Try again.", kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Fields drawn with an inline error.
  static const _fieldShown = {'display_name', 'bio', 'full_name', 'date_of_birth', 'country', 'timezone', 'gender', 'preferred_language'};

  Widget _fieldError(String key) {
    final e = _errors[key];
    if (e == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text(e, style: const TextStyle(color: AuraColors.dangerText, fontSize: 12)),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _fullNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BusyGuard(
      busy: _saving,
      child: AuraScaffold(
        appBar: AuraAppBar(title: context.l10n.editProfileTitle),
        scroll: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Column(
                children: [
                  // Avatar with a camera button — only the camera navigates to
                  // the avatar picker.
                  SizedBox(
                    width: 88,
                    height: 88,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const MyAvatar(size: 88, glow: true),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: GestureDetector(
                            onTap: () => Navigator.pushNamed(context, Routes.avatars),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                                ),
                                border: Border.all(color: AuraColors.bgBase, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: AuraColors.brandPink.withValues(alpha: 0.8),
                                    blurRadius: 14,
                                    spreadRadius: -4,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Plain label — does not navigate (use the camera button).
                  Text(
                    context.l10n.changeAvatar,
                    style: TextStyle(color: AuraColors.accentGlow, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionHeader(context.l10n.displayName),
            const SizedBox(height: 8),
            AuraTextField(
              hint: context.l10n.displayNameHint,
              icon: Icons.person_outline,
              controller: _nameCtrl,
              errorText: _errors['display_name'],
              onChanged: (_) {
                if (_errors.containsKey('display_name')) setState(() => _errors.remove('display_name'));
              },
            ),
            const SizedBox(height: 20),
            SectionHeader(context.l10n.bio),
            const SizedBox(height: 8),
            AuraTextField(
              hint: context.l10n.bioHint,
              icon: Icons.edit_note_rounded,
              controller: _bioCtrl,
              maxLines: 4,
              errorText: _errors['bio'],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 4),
              child: Text(
                '${_bioCtrl.text.trim().length}/140',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: _bioCtrl.text.trim().length > 140 ? AuraColors.dangerText : AuraColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SectionHeader(context.l10n.dateOfBirth),
            const SizedBox(height: 8),
            _PickerField(
              icon: Icons.cake_outlined,
              value: _dob == null ? null : formatDob(_dob!),
              hint: context.l10n.addBirthday,
              trailingIcon: Icons.calendar_today_rounded,
              onTap: _pickDob,
            ),
            _fieldError('date_of_birth'),
            const SizedBox(height: 20),
            SectionHeader(context.l10n.languageTitle),
            const SizedBox(height: 8),
            _PickerField(icon: Icons.translate_rounded, value: appLanguages[_language].label, onTap: _pickLanguage),
            _fieldError('preferred_language'),
            const SizedBox(height: 20),
            SectionHeader(context.l10n.country),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 10.0;
                final tileWidth = (constraints.maxWidth - gap * 3) / 4;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final (flag, code) in _countryOptions)
                      SizedBox(
                        width: tileWidth,
                        child: _CountryTile(
                          flag: flag,
                          code: code,
                          selected: _selected == code,
                          onTap: () => setState(() => _selected = code),
                        ),
                      ),
                  ],
                );
              },
            ),
            _fieldError('country'),
            const SizedBox(height: 28),
            const SectionHeader('Private details'),
            const SizedBox(height: 4),
            Text('Only you can see these.', style: AuraText.cardSub.copyWith(fontSize: 12)),
            const SizedBox(height: 10),
            AuraTextField(
              hint: 'Full name',
              icon: Icons.badge_outlined,
              controller: _fullNameCtrl,
              errorText: _errors['full_name'],
            ),
            const SizedBox(height: 12),
            _PickerField(
              icon: Icons.wc_rounded,
              value: _gender == null ? null : _genderLabels[_gender] ?? _gender,
              hint: 'Gender: not set',
              onTap: _pickGender,
            ),
            _fieldError('gender'),
            const SizedBox(height: 12),
            _PickerField(
              icon: Icons.schedule_rounded,
              value: _timezone,
              hint: 'Time zone',
              onTap: _pickTimezone,
            ),
            _fieldError('timezone'),
            const SizedBox(height: 20),
            const SectionHeader('Contact me by'),
            const SizedBox(height: 4),
            Text('Receipts, security alerts and support replies.', style: AuraText.cardSub.copyWith(fontSize: 12)),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final c in Me.channels) ...[
                  Expanded(
                    child: _ChoiceChip(
                      label: _channelLabels[c]!,
                      selected: _channel == c,
                      onTap: () => setState(() => _channel = c),
                    ),
                  ),
                  if (c != Me.channels.last) const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 28),
            GradientButton(label: context.l10n.saveChanges, loading: _saving, onPressed: _save),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// A pill choice (contact channel), styled like the country tiles.
class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AuraColors.card,
        borderRadius: BorderRadius.circular(12),
        border: selected ? null : Border.all(color: AuraColors.cardBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? AuraColors.textPrimary : AuraColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: selected
          ? Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(gradient: AuraGradients.brand, borderRadius: BorderRadius.circular(14)),
              child: inner,
            )
          : inner,
    );
  }
}

/// Bottom-sheet list of labelled options; pops the chosen key.
class _OptionSheet extends StatelessWidget {
  const _OptionSheet({required this.title, required this.options, this.selected});
  final String title;
  final Map<String, String> options;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final keys = options.keys.toList();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF17112C), Color(0xFF0B0916)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                child: Text(title, style: AuraText.title.copyWith(fontSize: 20)),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: keys.length,
                  itemBuilder: (_, i) {
                    final k = keys[i];
                    final on = k == selected;
                    return ListTile(
                      onTap: () => Navigator.pop(context, k),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      tileColor: on ? AuraColors.brandPurple.withValues(alpha: 0.18) : null,
                      title: Text(
                        options[k]!,
                        style: AuraText.body.copyWith(color: AuraColors.textPrimary, fontWeight: FontWeight.w600),
                      ),
                      trailing: on ? const Icon(Icons.check_circle_rounded, color: AuraColors.accentGlow) : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tap-to-pick field styled like [AuraTextField] (language, date of birth).
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.value,
    required this.onTap,
    this.hint = '',
    this.trailingIcon = Icons.keyboard_arrow_down_rounded,
  });

  final IconData icon;
  final String? value;
  final String hint;
  final IconData trailingIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final empty = value == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AuraRadii.sm),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AuraRadii.sm),
            border: Border.all(color: AuraColors.glassStroke),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AuraColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value ?? hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AuraText.body.copyWith(color: empty ? AuraColors.textMuted : AuraColors.textPrimary),
                ),
              ),
              Icon(trailingIcon, size: 18, color: AuraColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet language list; pops the chosen index.
class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet({required this.selected});
  final int selected;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF17112C), Color(0xFF0B0916)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                child: Text(context.l10n.languageTitle, style: AuraText.title.copyWith(fontSize: 20)),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: appLanguages.length,
                  itemBuilder: (_, i) {
                    final l = appLanguages[i];
                    final on = i == selected;
                    return ListTile(
                      onTap: () => Navigator.pop(context, i),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      tileColor: on ? AuraColors.brandPurple.withValues(alpha: 0.18) : null,
                      leading: Text(l.flag, style: const TextStyle(fontSize: 22)),
                      title: Text(
                        l.native,
                        style: AuraText.body.copyWith(color: AuraColors.textPrimary, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(l.english, style: AuraText.cardSub.copyWith(fontSize: 12)),
                      trailing: on ? const Icon(Icons.check_circle_rounded, color: AuraColors.accentGlow) : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  const _CountryTile({required this.flag, required this.code, required this.selected, required this.onTap});

  final String flag;
  final String code;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AuraColors.card,
        borderRadius: BorderRadius.circular(12),
        border: selected ? null : Border.all(color: AuraColors.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(flag, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(
            code,
            style: TextStyle(
              color: selected ? AuraColors.textPrimary : AuraColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: selected
          ? Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(gradient: AuraGradients.brand, borderRadius: BorderRadius.circular(14)),
              child: inner,
            )
          : inner,
    );
  }
}
