import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Avatars picker — "Choose Avatar". See docs/DESIGN_SPEC.md.
class AvatarsScreen extends StatefulWidget {
  const AvatarsScreen({super.key});

  @override
  State<AvatarsScreen> createState() => _AvatarsScreenState();
}

class _AvatarsScreenState extends State<AvatarsScreen> {
  static const _avatars = <(String, Color)>[
    ('NR', AuraColors.brandPurple),
    ('ZX', AuraColors.avatarBlue),
    ('KO', AuraColors.brandOrange),
    ('VY', AuraColors.avatarGreen),
    ('AS', AuraColors.avatarPurple),
    ('MJ', AuraColors.brandPink),
    ('LE', AuraColors.gold),
    ('RU', AuraColors.avatarBlue),
  ];

  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final (letter, color) = _avatars[_selected];
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Choose Avatar'),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: LetterAvatar(letter: letter, color: color, size: 96, glow: true),
          ),
          const SizedBox(height: 12),
          const Text(
            'Tap a tile to equip it',
            textAlign: TextAlign.center,
            style: TextStyle(color: AuraColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final tileWidth = (constraints.maxWidth - gap * 3) / 4;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = 0; i < _avatars.length; i++)
                    _AvatarTile(
                      letter: _avatars[i].$1,
                      color: _avatars[i].$2,
                      size: tileWidth,
                      selected: i == _selected,
                      onTap: () => setState(() => _selected = i),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          GradientButton(
            label: 'Save Avatar',
            onPressed: () {
              showAuraToast(context, 'Avatar updated', kind: AuraToastKind.success);
              Navigator.of(context).maybePop();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _AvatarTile extends StatelessWidget {
  const _AvatarTile({
    required this.letter,
    required this.color,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final String letter;
  final Color color;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: Colors.white,
            fontSize: size * 0.30,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    return GestureDetector(
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
    );
  }
}
