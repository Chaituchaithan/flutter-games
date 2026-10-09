import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../services/app_exception.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';

/// Edit profile. Seeds from and saves back to the session. See docs/DESIGN_SPEC.md (v2 §Edit profile).
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
  bool _saving = false;

  /// The grid, plus the player's saved country if it isn't one of the 8.
  List<(String, String)> get _countryOptions {
    final c = _initial.country;
    if (c == null || _countries.any((e) => e.$2 == c)) return _countries;
    return [..._countries, (_flagFor(c), c)];
  }

  /// "IN" → 🇮🇳 (regional indicator letters).
  static String _flagFor(String code) => code.length == 2
      ? String.fromCharCodes(code.toUpperCase().codeUnits.map((u) => 0x1F1E6 + u - 0x41))
      : '🏳️';

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
    if (changedName == null && changedBio == null && changedCountry == null) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(sessionProvider.notifier).updateProfile(displayName: changedName, bio: changedBio, country: changedCountry);
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
    return AuraScaffold(
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
                              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)]),
                              border: Border.all(color: AuraColors.bgBase, width: 2.5),
                              boxShadow: [BoxShadow(color: AuraColors.brandPink.withValues(alpha: 0.8), blurRadius: 14, spreadRadius: -4, offset: const Offset(0, 6))],
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
    );
  }
}

class _CountryTile extends StatelessWidget {
  const _CountryTile({
    required this.flag,
    required this.code,
    required this.selected,
    required this.onTap,
  });

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
              decoration: BoxDecoration(
                gradient: AuraGradients.brand,
                borderRadius: BorderRadius.circular(14),
              ),
              child: inner,
            )
          : inner,
    );
  }
}
