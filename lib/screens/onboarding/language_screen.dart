import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../widgets/aura.dart';

/// Language picker. See docs/DESIGN_SPEC.md (v2 §Language).
class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _Language {
  const _Language(this.native, this.english, this.flag);
  final String native;
  final String english;
  final String flag;
}

const _languages = <_Language>[
  _Language('English', 'English', '🇬🇧'),
  _Language('Español', 'Spanish', '🇪🇸'),
  _Language('Français', 'French', '🇫🇷'),
  _Language('Deutsch', 'German', '🇩🇪'),
  _Language('Português', 'Portuguese', '🇧🇷'),
  _Language('हिन्दी', 'Hindi', '🇮🇳'),
  _Language('العربية', 'Arabic', '🇸🇦'),
  _Language('日本語', 'Japanese', '🇯🇵'),
  _Language('한국어', 'Korean', '🇰🇷'),
  _Language('Bahasa Indonesia', 'Indonesian', '🇮🇩'),
  _Language('Türkçe', 'Turkish', '🇹🇷'),
  _Language('Русский', 'Russian', '🇷🇺'),
];

class _LanguageScreenState extends State<LanguageScreen> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: const AuraAppBar(showBack: true),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          // Gradient rounded-square globe tile.
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: AuraGradients.brand,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.language, color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Choose your language',
            textAlign: TextAlign.center,
            style: AuraText.headline,
          ),
          const SizedBox(height: 10),
          Text(
            'You can change this anytime in Settings.',
            textAlign: TextAlign.center,
            style: AuraText.body.copyWith(color: AuraColors.textSecondary),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final itemWidth = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: List.generate(_languages.length, (i) {
                  return SizedBox(
                    width: itemWidth,
                    child: _LanguageCard(
                      language: _languages[i],
                      selected: i == _selected,
                      onTap: () => setState(() => _selected = i),
                    ),
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 24),
          GradientButton(
            label: 'Continue',
            onPressed: () =>
                Navigator.pushReplacementNamed(context, Routes.onboarding),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final _Language language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AuraRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AuraRadii.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: AuraGlass.decoration(
            radius: AuraRadii.lg,
            border: selected ? AuraColors.accentGlow.withValues(alpha: 0.6) : null,
          ),
          child: Row(
        children: [
          Text(language.flag, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  language.native,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  language.english,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AuraColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
              const SizedBox(width: 6),
              _RadioDot(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          gradient: AuraGradients.brand,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 14, color: Colors.white),
      );
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 2),
      ),
    );
  }
}
