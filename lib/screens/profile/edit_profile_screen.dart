import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
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

  String _selected = 'FR';

  late final _nameCtrl = TextEditingController(text: ref.read(currentUserProvider).displayName);
  late final _bioCtrl = TextEditingController(text: ref.read(currentUserProvider).bio);

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
                const LetterAvatar(
                  letter: 'NR',
                  color: AuraColors.brandPurple,
                  size: 88,
                  glow: true,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, Routes.avatars),
                  style: TextButton.styleFrom(
                    foregroundColor: AuraColors.accentGlow,
                  ),
                  child: const Text(
                    'Change avatar',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const SectionHeader('Display name'),
          const SizedBox(height: 8),
          AuraTextField(hint: 'Nova Rider', icon: Icons.person_outline, controller: _nameCtrl),
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
                  for (final (flag, code) in _countries)
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
          GradientButton(
            label: 'Save changes',
            onPressed: () {
              ref.read(sessionProvider.notifier).updateProfile(
                    displayName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
                    bio: _bioCtrl.text.trim(),
                  );
              showAuraToast(context, 'Profile saved');
              Navigator.of(context).maybePop();
            },
          ),
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
