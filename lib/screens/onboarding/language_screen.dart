import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../data/languages.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';

export '../../data/languages.dart' show languageProvider, languageLabel;

/// Language picker (mockup `language`). First launch: globe hero +
/// "Choose your language", Continue → onboarding. From Settings
/// ([fromSettings]): a "← Language" header instead, and Continue saves the
/// choice and returns to Settings.
class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key, this.fromSettings = false});

  final bool fromSettings;

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}


class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  late int _selected = ref.read(languageProvider);

  void _continue() {
    ref.read(languageProvider.notifier).select(_selected);
    // Signed in: keep the profile's preferred_language in step (best effort).
    if (ref.read(sessionProvider) != null) {
      ref
          .read(sessionProvider.notifier)
          .updateProfile(preferredLanguage: appLanguages[_selected].code)
          .catchError((Object _) {});
    }
    if (widget.fromSettings) {
      Navigator.of(context).pop();
    } else {
      Navigator.pushReplacementNamed(context, Routes.onboarding);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fromSettings = widget.fromSettings;
    return AuraScaffold(
      appBar: AuraAppBar(showBack: true, title: fromSettings ? 'Language' : null),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          if (!fromSettings) ...[
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
          ],
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final itemWidth = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: List.generate(appLanguages.length, (i) {
                  return SizedBox(
                    width: itemWidth,
                    child: _LanguageCard(
                      language: appLanguages[i],
                      selected: i == _selected,
                      onTap: () => setState(() => _selected = i),
                    ),
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 24),
          GradientButton(label: 'Continue', onPressed: _continue),
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

  final AppLanguage language;
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
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
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
