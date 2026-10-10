import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../data/languages.dart';
import '../../services/app_exception.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';

/// Edit profile. Seeds from and saves back to the session. See docs/DESIGN_SPEC.md.
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

  // Seeded from the signed-in player (GET /users/me + /users/{id}/profile).
  late final _initial = ref.read(currentUserProvider);
  late String? _selected = _initial.country;
  late final _nameCtrl = TextEditingController(text: _initial.displayName);
  late final _bioCtrl = TextEditingController(text: _initial.bio);
  // Saved language, else the one picked on first launch.
  late int _language = languageIndexFor(_initial.preferredLanguage) ?? ref.read(languageProvider);
  late DateTime? _dob = DateTime.tryParse(_initial.dateOfBirth ?? '');
  bool _saving = false;

  /// Players must be at least 13.
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
      helpText: 'Date of birth',
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

  /// The grid, plus the player's saved country if it isn't one of the 8.
  List<(String, String)> get _countryOptions {
    final c = _initial.country;
    if (c == null || _countries.any((e) => e.$2 == c)) return _countries;
    return [..._countries, (_flagFor(c), c)];
  }

  /// "IN" → 🇮🇳 (regional indicator letters).
  static String _flagFor(String code) =>
      code.length == 2 ? String.fromCharCodes(code.toUpperCase().codeUnits.map((u) => 0x1F1E6 + u - 0x41)) : '🏳️';

  /// PATCH /users/me/profile with only the fields that changed.
  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final bio = _bioCtrl.text.trim();
    if (name.isEmpty) {
      showAuraToast(context, 'Display name can’t be empty', kind: AuraToastKind.error);
      return;
    }
    final changedName = name != _initial.displayName ? name : null;
    final changedBio = bio != _initial.bio ? bio : null;
    final changedCountry = _selected != _initial.country ? _selected : null;
    final lang = appLanguages[_language].code;
    final changedLanguage = lang != _initial.preferredLanguage ? lang : null;
    final dob = _dob == null ? null : _apiDate(_dob!);
    final changedDob = dob != null && dob != _initial.dateOfBirth ? dob : null;
    if (changedName == null &&
        changedBio == null &&
        changedCountry == null &&
        changedLanguage == null &&
        changedDob == null) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(sessionProvider.notifier)
          .updateProfile(
            displayName: changedName,
            bio: changedBio,
            country: changedCountry,
            preferredLanguage: changedLanguage,
            dateOfBirth: changedDob,
          );
      if (!mounted) return;
      showAuraToast(context, 'Profile saved');
      Navigator.of(context).maybePop();
    } on AppException catch (e) {
      if (mounted) showAuraToast(context, e.message, kind: AuraToastKind.error);
    } on Object catch (_) {
      if (mounted) showAuraToast(context, "Couldn't save your profile. Try again.", kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BusyGuard(
      busy: _saving,
      child: AuraScaffold(
        appBar: const AuraAppBar(title: 'Edit Profile'),
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
                        LetterAvatar(letter: _initial.initials, color: _initial.color, size: 88, glow: true),
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
                  const Text(
                    'Change avatar',
                    style: TextStyle(color: AuraColors.accentGlow, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const SectionHeader('Display name'),
            const SizedBox(height: 8),
            AuraTextField(hint: 'Your display name', icon: Icons.person_outline, controller: _nameCtrl),
            const SizedBox(height: 20),
            const SectionHeader('Bio'),
            const SizedBox(height: 8),
            AuraTextField(
              hint: 'Tell players about yourself',
              icon: Icons.edit_note_rounded,
              controller: _bioCtrl,
              maxLines: 4,
            ),
            const SizedBox(height: 20),
            const SectionHeader('Date of birth'),
            const SizedBox(height: 8),
            _PickerField(
              icon: Icons.cake_outlined,
              value: _dob == null ? null : formatDob(_dob!),
              hint: 'Add your birthday',
              trailingIcon: Icons.calendar_today_rounded,
              onTap: _pickDob,
            ),
            const SizedBox(height: 20),
            const SectionHeader('Language'),
            const SizedBox(height: 8),
            _PickerField(icon: Icons.translate_rounded, value: appLanguages[_language].label, onTap: _pickLanguage),
            const SizedBox(height: 20),
            const SectionHeader('Country'),
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
            const SizedBox(height: 28),
            GradientButton(label: 'Save changes', loading: _saving, onPressed: _save),
            const SizedBox(height: 8),
          ],
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
                child: Text('Language', style: AuraText.title.copyWith(fontSize: 20)),
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
