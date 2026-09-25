import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../widgets/aura.dart';

/// Play with Friends — menu → create room → join room → lobby. Presentation-only.
/// Mirrors the mockup's `isFriends` (frMenu/frCreate/frJoin/frLobby).
class PlayWithFriendsScreen extends StatefulWidget {
  const PlayWithFriendsScreen({super.key});

  @override
  State<PlayWithFriendsScreen> createState() => _PlayWithFriendsScreenState();
}

enum _Mode { menu, create, join, lobby }

class _PlayWithFriendsScreenState extends State<PlayWithFriendsScreen> {
  _Mode _mode = _Mode.menu;
  int _seats = 2;
  bool _tokens = true;
  int _stake = 200;
  String _joinCode = '';

  static const _stakes = [50, 100, 200, 500, 1000];

  String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  String get _stakeText => '${_fmt(_stake)} ${_tokens ? 'Tokens' : 'Gold'}';
  String get _potText => '${_fmt(_stake * _seats)} ${_tokens ? 'Tokens' : 'Gold'}';

  void _back() {
    if (_mode == _Mode.menu) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _mode = _Mode.menu);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_mode) {
      _Mode.menu => 'Play with Friends',
      _Mode.create => 'Create room',
      _Mode.join => 'Join room',
      _Mode.lobby => 'Room lobby',
    };
    return AuraScaffold(
      appBar: AuraAppBar(
        title: title,
        onBack: _back,
        trailing: _mode == _Mode.lobby
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AuraColors.green,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: AuraColors.green.withValues(alpha: 0.8), blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('Live', style: TextStyle(color: AuraColors.green, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              )
            : null,
      ),
      scroll: true,
      body: switch (_mode) {
        _Mode.menu => _menu(),
        _Mode.create => _create(),
        _Mode.join => _join(),
        _Mode.lobby => _lobby(),
      },
    );
  }

  // ── Menu ──
  Widget _menu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: Center(
            child: SizedBox(
              width: 150,
              child: Stack(
                clipBehavior: Clip.none,
                children: const [
                  Positioned(left: 0, top: 14, child: LetterAvatar(letter: 'N', color: AuraColors.brandPurple, size: 62, glow: true)),
                  Positioned(left: 44, top: 0, child: LetterAvatar(letter: 'Z', color: AuraColors.avatarBlue, size: 62, glow: true)),
                  Positioned(left: 88, top: 14, child: LetterAvatar(letter: 'L', color: AuraColors.avatarOrange, size: 62, glow: true)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          "Create a private room and share the code, or join a friend's room.",
          textAlign: TextAlign.center,
          style: AuraText.body.copyWith(color: AuraColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        _BigActionCard(
          accent: true,
          icon: Icons.add,
          title: 'Create room',
          sub: 'Pick seats & stake, get a code',
          onTap: () => setState(() => _mode = _Mode.create),
        ),
        const SizedBox(height: 12),
        _BigActionCard(
          accent: false,
          icon: Icons.login_rounded,
          title: 'Join room',
          sub: 'Enter a 6-character code',
          onTap: () => setState(() => _mode = _Mode.join),
        ),
        const SizedBox(height: 24),
        const SectionBar('Online now'),
        const SizedBox(height: 12),
        _OnlineFriend(name: 'ZeroCool', color: AuraColors.avatarBlue, status: 'LV 9 · in lobby', onInvite: () => showAuraToast(context, 'Invite sent to ZeroCool')),
        const SizedBox(height: 9),
        _OnlineFriend(name: 'LunaWolf', color: AuraColors.avatarOrange, status: 'LV 6 · online', onInvite: () => showAuraToast(context, 'Invite sent to LunaWolf')),
        const SizedBox(height: 12),
      ],
    );
  }

  // ── Create ──
  Widget _create() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const _FieldLabel('Seats'),
        Row(
          children: [
            Expanded(child: _pill('2 players', _seats == 2, () => setState(() => _seats = 2))),
            const SizedBox(width: 10),
            Expanded(child: _pill('4 players', _seats == 4, () => setState(() => _seats = 4))),
          ],
        ),
        const SizedBox(height: 18),
        const _FieldLabel('Currency'),
        Row(
          children: [
            Expanded(child: _pill('Tokens', _tokens, () => setState(() => _tokens = true))),
            const SizedBox(width: 10),
            Expanded(child: _pill('Gold', !_tokens, () => setState(() => _tokens = false))),
          ],
        ),
        const SizedBox(height: 18),
        const _FieldLabel('Stake per player'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _stakes)
              SizedBox(width: 78, child: _pill(_fmt(s), _stake == s, () => setState(() => _stake = s))),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AuraGlass.decoration(radius: 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SUMMARY', style: AuraText.section),
                    const SizedBox(height: 3),
                    Text('${_seats}P · $_stakeText',
                        style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Text(_potText,
                  style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.amber, fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        GradientButton(label: 'Create & get code', onPressed: () => setState(() => _mode = _Mode.lobby)),
        const SizedBox(height: 12),
      ],
    );
  }

  // ── Join ──
  Widget _join() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('Ask your friend for the room code shown on their screen.',
            style: AuraText.body.copyWith(color: AuraColors.textSecondary)),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) {
            final filled = i < _joinCode.length;
            final active = i == _joinCode.length;
            return Container(
              width: 46,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AuraColors.accentGlow.withValues(alpha: 0.08) : AuraColors.field,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: active
                      ? AuraColors.accentGlow
                      : (filled ? AuraColors.accentGlow.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.24)),
                  width: 1.5,
                ),
              ),
              child: Text(filled ? _joinCode[i] : '',
                  style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
            );
          }),
        ),
        const SizedBox(height: 22),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.9,
          children: [
            for (final k in const ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', '0', '⌫'])
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() {
                    if (k == '⌫') {
                      if (_joinCode.isNotEmpty) _joinCode = _joinCode.substring(0, _joinCode.length - 1);
                    } else if (_joinCode.length < 6) {
                      _joinCode += k;
                    }
                  }),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: AuraGlass.decoration(radius: 16, shadow: false),
                    child: k == '⌫'
                        ? const Icon(Icons.backspace_outlined, color: AuraColors.textPrimary, size: 22)
                        : Text(k, style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        GradientButton(label: 'Join room', onPressed: () => setState(() => _mode = _Mode.lobby)),
        const SizedBox(height: 12),
      ],
    );
  }

  // ── Lobby ──
  Widget _lobby() {
    final seatData = <(String, Color, bool)>[
      ('NR', AuraColors.brandPurple, true),
      ('ZC', AuraColors.avatarBlue, true),
      if (_seats == 4) ('', AuraColors.avatarGreen, false),
      if (_seats == 4) ('', AuraColors.avatarOrange, false),
    ];
    final joined = seatData.where((s) => s.$3).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: AuraGlass.decoration(
            radius: AuraRadii.xl,
            accentGradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AuraColors.brandPurple.withValues(alpha: 0.3), AuraColors.brandPink.withValues(alpha: 0.14)],
            ),
            border: AuraColors.accentGlow.withValues(alpha: 0.5),
          ),
          child: Column(
            children: [
              Text('ROOM CODE', style: AuraText.section.copyWith(letterSpacing: 1.5, color: Colors.white70)),
              const SizedBox(height: 6),
              Text('7K 2Q',
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                    shadows: [Shadow(color: AuraColors.accentGlow.withValues(alpha: 0.7), blurRadius: 24)],
                  )),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _lobbyBtn(Icons.copy_rounded, 'Copy', () => showAuraToast(context, 'Room code copied ✓')),
                  const SizedBox(width: 10),
                  _lobbyBtn(Icons.ios_share, 'Share', () => showAuraToast(context, 'Sharing room…')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(child: SectionBar('Players')),
            Text('$joined / $_seats',
                style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.accentGlow, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: AuraGlass.decoration(radius: AuraRadii.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < seatData.length; i++) _seat(seatData[i], i == 0),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: AuraGlass.decoration(radius: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_stakeText, style: AuraText.cardSub),
              Text(_potText,
                  style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.amber, fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        if (joined < _seats) ...[
          const SizedBox(height: 14),
          Center(child: Text('Waiting for friends to join…', style: AuraText.cardSub)),
        ],
        const SizedBox(height: 18),
        GradientButton(
          label: joined < _seats ? 'Start anyway' : 'Start game',
          onPressed: () => Navigator.pushNamed(context, Routes.matchmaking),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _seat((String, Color, bool) s, bool host) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            if (s.$3)
              LetterAvatar(letter: s.$1[0], color: s.$2, size: 48)
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
                ),
                child: Icon(Icons.add, color: AuraColors.textSecondary, size: 20),
              ),
            if (s.$3)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AuraColors.green, shape: BoxShape.circle, border: Border.all(color: AuraColors.bgBase, width: 2)),
                  child: const Icon(Icons.check, size: 9, color: Color(0xFF0A0816)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(s.$3 ? (host ? 'You' : s.$1) : 'Open',
            style: TextStyle(color: s.$3 ? Colors.white : AuraColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
        if (host) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: AuraColors.accentGlow.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)),
            child: Text('HOST',
                style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.accentGlow, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }

  Widget _lobbyBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 15),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AuraColors.accentGlow.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? AuraColors.accentGlow : Colors.white.withValues(alpha: 0.18),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AuraColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text.toUpperCase(), style: AuraText.section.copyWith(letterSpacing: 1)),
      );
}

class _BigActionCard extends StatelessWidget {
  const _BigActionCard({required this.accent, required this.icon, required this.title, required this.sub, required this.onTap});
  final bool accent;
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      radius: AuraRadii.xl,
      onTap: onTap,
      gradient: accent
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AuraColors.brandPurple.withValues(alpha: 0.3), AuraColors.brandPink.withValues(alpha: 0.12)],
            )
          : null,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: accent ? AuraGradients.orb : const LinearGradient(colors: [AuraColors.gems, AuraColors.gemsDeep]),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AuraText.cardTitle.copyWith(fontSize: 18)),
                const SizedBox(height: 2),
                Text(sub, style: AuraText.cardSub.copyWith(fontSize: 12.5)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: accent ? Colors.white : AuraColors.textSecondary, size: 20),
        ],
      ),
    );
  }
}

class _OnlineFriend extends StatelessWidget {
  const _OnlineFriend({required this.name, required this.color, required this.status, required this.onInvite});
  final String name;
  final Color color;
  final String status;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      padding: const EdgeInsets.all(11),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                LetterAvatar(letter: name[0], color: color, size: 40),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: AuraColors.green, shape: BoxShape.circle, border: Border.all(color: AuraColors.bgBase, width: 2)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AuraText.cardTitle.copyWith(fontSize: 14)),
                const SizedBox(height: 1),
                Text(status, style: AuraText.cardSub.copyWith(fontSize: 11)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onInvite,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: AuraGlass.decoration(radius: 11, shadow: false),
              child: const Text('Invite', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
