import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/feature_flags.dart';
import '../../app/routes.dart';
import '../../data/repositories/store_repository.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';
import '../../app/game_area.dart';
import '../../configs/games/core/active_game.dart';

/// Play with Friends — menu → create room / join room → room lobby → match.
/// Mirrors the mockup's `isFriends` (frMenu / frCreate / frJoin / frLobby).
///
/// Chess is always 2 players, so Create has no seat picker and the lobby has
/// two seats.
///
/// Navigation (mockup): Menu back → Home · Create/Join back → Menu ·
/// "Create & get code" → Lobby (you host, waiting for a friend) · Join (only
/// once all 6 characters are in) → Lobby · Lobby back → "Leave the room?" →
/// Home · Start match → matchmaking → game · Invite → Create ·
/// "All friends ›" → Friends.
///
/// With the realtime socket ON, Create/Join hand off to the live online
/// screen instead (the server issues the room code and runs the lobby); with
/// it bypassed the lobby is simulated locally, as in the mockup.
class PlayWithFriendsScreen extends ConsumerStatefulWidget {
  const PlayWithFriendsScreen({super.key});

  @override
  ConsumerState<PlayWithFriendsScreen> createState() => _PlayWithFriendsScreenState();
}

enum _Mode { menu, create, join, lobby }

/// Forces typed room-code text to uppercase (room codes are uppercase).
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

class _PlayWithFriendsScreenState extends ConsumerState<PlayWithFriendsScreen> {
  _Mode _mode = _Mode.menu;
  static const int _seats = 2; // chess
  bool _tokens = true;
  int _stake = 200;

  // Join: a real (hidden) text field so letters + digits can be typed on the
  // phone keyboard; it drives the 6 code cells.
  final TextEditingController _codeCtrl = TextEditingController();
  final FocusNode _codeFocus = FocusNode();
  String get _joinCode => _codeCtrl.text;
  bool get _joinReady => _joinCode.length == 6;

  // Lobby (simulated while the socket is bypassed).
  String _roomCode = '';
  bool _host = true;
  int _joined = 1;
  Timer? _lobbyTimer;
  bool get _lobbyReady => _joined >= _seats;

  static const _stakes = [0, 100, 200, 500, 1000];

  @override
  void initState() {
    super.initState();
    _codeFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _lobbyTimer?.cancel();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  String get _cur => _tokens ? 'Tokens' : 'Gold';
  String get _stakeText => _stake == 0 ? 'Free match' : '${_fmt(_stake)} $_cur each';
  String get _potText => _stake == 0 ? 'Bragging rights' : '${_fmt(_stake * _seats)} pot';
  String get _stakeLabel => _stake == 0 ? 'Free match' : '${_fmt(_stake)} $_cur';

  // ── Navigation ──

  void _go(_Mode m) {
    if (m == _Mode.join) _codeCtrl.clear();
    setState(() => _mode = m);
  }

  Future<void> _back() async {
    switch (_mode) {
      case _Mode.menu:
        Navigator.of(context).maybePop();
      case _Mode.create || _Mode.join:
        FocusScope.of(context).unfocus();
        _go(_Mode.menu);
      case _Mode.lobby:
        final leave = await showAuraDialog(
          context,
          icon: Icons.logout_rounded,
          title: 'Leave the room?',
          body: _host
              ? 'You are the host — the room will close for everyone and stakes are refunded.'
              : 'Your seat will be freed and your stake refunded.',
          primaryLabel: 'Leave room',
          secondaryLabel: 'Keep waiting',
          destructive: true,
        );
        if (leave == true && mounted) {
          _lobbyTimer?.cancel();
          Navigator.popUntil(context, ModalRoute.withName(Routes.home));
        }
    }
  }

  void _createRoom() {
    if (kSocketEnabled) {
      // Live: the server creates the room and shows its code while waiting.
      final route = GameArea.onlineRoute(ref.read(activeGameProvider));
      if (route != null) Navigator.pushNamed(context, route, arguments: {'mode': 'create', 'stake': _stake, 'tokens': _tokens});
      return;
    }
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final rng = Random();
    _roomCode = List.generate(6, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
    _host = true;
    _joined = 1;
    _go(_Mode.lobby);
    // Simulated friend joins after a moment (mockup simLobby: 1.6s).
    _lobbyTimer?.cancel();
    _lobbyTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted && _mode == _Mode.lobby) setState(() => _joined = _seats);
    });
  }

  void _joinRoom() {
    if (!_joinReady) return;
    FocusScope.of(context).unfocus();
    if (kSocketEnabled) {
      final route = GameArea.onlineRoute(ref.read(activeGameProvider));
      if (route != null) Navigator.pushNamed(context, route, arguments: {'mode': 'join', 'code': _joinCode});
      return;
    }
    _roomCode = _joinCode;
    _host = false;
    _joined = _seats; // you + the host
    _go(_Mode.lobby);
  }

  int _balance() {
    final s = ref.read(walletProvider).maybeWhen(
          data: (w) => _tokens ? w.gems : w.gold,
          orElse: () => _tokens ? '5,000' : '2,000',
        );
    return int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  Future<void> _startMatch() async {
    if (!_lobbyReady) return;
    if (_stake > _balance()) {
      final buyMore = await showInsufficientBalanceDialog(context);
      if (buyMore == true && mounted) {
        _lobbyTimer?.cancel();
        Navigator.pop(context, 'store'); // Home switches to the Store tab
      }
      return;
    }
    _lobbyTimer?.cancel();
    if (mounted) {
      Navigator.pushNamed(context, Routes.matchmaking, arguments: {'stake': _stake, 'tokens': _tokens, 'label': 'Friends room'});
    }
  }

  /// Opens the keyboard on tap — also when the field already has focus but
  /// the keyboard was dismissed (Android back), where requestFocus is a no-op.
  void _openKeyboard() {
    if (_codeFocus.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _codeFocus.requestFocus();
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
    return PopScope(
      // System back follows the same steps as the header back button.
      canPop: _mode == _Mode.menu,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AuraScaffold(
        scroll: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 14),
            _Header(title: title, onBack: _back, live: _mode == _Mode.lobby),
            switch (_mode) {
              _Mode.menu => _menu(),
              _Mode.create => _create(),
              _Mode.join => _join(),
              _Mode.lobby => _lobby(),
            },
          ],
        ),
      ),
    );
  }

  // ── Menu ──
  Widget _menu() {
    final me = ref.watch(currentUserProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 26),
        // Three overlapping avatars; the middle one sits on top (mockup).
        Center(
          child: SizedBox(
            width: 150,
            height: 90,
            child: Stack(
              children: [
                const Positioned(left: 88, top: 14, child: _MenuAvatar('LW', [Color(0xFFFB923C), Color(0xFFF43F5E)])),
                Positioned(left: 0, top: 14, child: _MenuAvatar(me.initials, const [AuraColors.brandPurple, AuraColors.brandPink])),
                const Positioned(left: 44, top: 0, child: _MenuAvatar('ZC', [Color(0xFF22D3EE), Color(0xFF6366F1)])),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              "Create a private room and share the code, or join a friend's room.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.5, color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
        ),
        const SizedBox(height: 26),
        _BigActionCard(
          accent: true,
          icon: Icons.add_rounded,
          title: 'Create room',
          sub: 'Pick your stake, get a code', // chess: no seats to pick
          onTap: () => _go(_Mode.create),
        ),
        const SizedBox(height: 12),
        _BigActionCard(
          accent: false,
          icon: Icons.login_rounded,
          title: 'Join room',
          sub: 'Enter a 6-character code',
          onTap: () => _go(_Mode.join),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(child: SectionBar('Online now')),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, Routes.friends),
              child: const Text(
                'All friends ›',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AuraColors.accentGlow),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Invite → Create room (mockup).
        _OnlineFriend(
          name: 'ZeroCool',
          colors: const [Color(0xFF22D3EE), Color(0xFF6366F1)],
          status: 'LV 9 · in lobby',
          onInvite: () => _go(_Mode.create),
        ),
        const SizedBox(height: 9),
        _OnlineFriend(
          name: 'LunaWolf',
          colors: const [Color(0xFFFB923C), Color(0xFFF43F5E)],
          status: 'LV 6 · online',
          onInvite: () => _go(_Mode.create),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // ── Create ──
  Widget _create() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel('Currency'),
        Row(
          children: [
            Expanded(child: _Pick(label: 'Tokens', on: _tokens, onTap: () => setState(() => _tokens = true))),
            const SizedBox(width: 10),
            Expanded(child: _Pick(label: 'Gold', on: !_tokens, onTap: () => setState(() => _tokens = false))),
          ],
        ),
        const _FieldLabel('Stake per player'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _stakes)
              _Pick(
                label: s == 0 ? 'Free' : (s >= 1000 ? '${s ~/ 1000}k' : '$s'),
                on: _stake == s,
                compact: true,
                onTap: () => setState(() => _stake = s),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _GlassBox(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SUMMARY',
                      style: TextStyle(
                        fontFamily: AuraText.displayFamily,
                        fontSize: 11,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_seats}P · $_stakeLabel',
                      style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Text(
                _potText,
                style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.amber, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        GradientButton(label: 'Create & get code', onPressed: _createRoom),
        const SizedBox(height: 12),
      ],
    );
  }

  // ── Join ──
  Widget _join() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Text(
          'Ask your friend for the room code shown on their screen.',
          style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.55)),
        ),
        const SizedBox(height: 18),
        // Tap the cells → phone keyboard (letters + numbers).
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openKeyboard,
          child: Stack(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) => _CodeCell(
                      char: i < _joinCode.length ? _joinCode[i] : '',
                      // The next cell to fill is highlighted (mockup), brighter while typing.
                      active: i == _joinCode.length,
                      focused: _codeFocus.hasFocus,
                    )),
              ),
              // Invisible field that captures the typing.
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0,
                    child: TextField(
                      controller: _codeCtrl,
                      focusNode: _codeFocus,
                      autofocus: true,
                      showCursor: false,
                      enableInteractiveSelection: false,
                      keyboardType: TextInputType.visiblePassword, // no autocorrect/suggestions
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.go,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                        LengthLimitingTextInputFormatter(6),
                        _UpperCaseFormatter(),
                      ],
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _joinRoom(),
                      decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _joinReady ? 'Code complete — tap Join room' : 'Tap the boxes to type the code',
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45)),
          ),
        ),
        const SizedBox(height: 16),
        // Disabled (dimmed) until all 6 characters are entered.
        GradientButton(label: 'Join room', onPressed: _joinRoom, enabled: _joinReady),
        const SizedBox(height: 12),
      ],
    );
  }

  // ── Lobby ──
  Widget _lobby() {
    final me = ref.watch(currentUserProvider);
    final pretty = _roomCode.length == 6 ? '${_roomCode.substring(0, 3)} ${_roomCode.substring(3)}' : _roomCode;
    // You are the host's seat 1 when hosting; when joining, the host sits first.
    final seats = _host
        ? [
            _SeatData(name: me.displayName, initials: me.initials, colors: const [AuraColors.brandPurple, AuraColors.brandPink], host: true),
            _joined >= 2
                ? const _SeatData(name: 'ZeroCool', initials: 'ZC', colors: [Color(0xFFF43F5E), Color(0xFFFB7185)])
                : const _SeatData.empty(),
          ]
        : [
            const _SeatData(name: 'Host', initials: 'HO', colors: [Color(0xFFF43F5E), Color(0xFFFB7185)], host: true),
            _SeatData(name: me.displayName, initials: me.initials, colors: const [AuraColors.brandPurple, AuraColors.brandPink]),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        // Room code card.
        _ShadowBase(
          radius: 24,
          shadow: BoxShadow(color: AuraColors.brandPurple.withValues(alpha: 0.8), blurRadius: 40, spreadRadius: -16, offset: const Offset(0, 18)),
          child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AuraColors.brandPurple.withValues(alpha: 0.30), AuraColors.brandPink.withValues(alpha: 0.12)],
            ),
            border: Border.all(color: AuraColors.accentGlow.withValues(alpha: 0.5), width: 1.5),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -40,
                top: -40,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [AuraColors.brandPink.withValues(alpha: 0.35), AuraColors.brandPink.withValues(alpha: 0)], stops: const [0, 0.7]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'ROOM CODE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AuraText.displayFamily,
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        pretty,
                        style: TextStyle(
                          fontFamily: AuraText.displayFamily,
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 6,
                          shadows: [Shadow(color: AuraColors.accentGlow.withValues(alpha: 0.7), blurRadius: 24)],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _LobbyBtn(
                          icon: Icons.copy_rounded,
                          label: 'Copy',
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: _roomCode));
                            showAuraToast(context, 'Room code copied');
                          },
                        ),
                        const SizedBox(width: 10),
                        _LobbyBtn(icon: Icons.ios_share_rounded, label: 'Share', onTap: () => showAuraToast(context, 'Sharing room code…', kind: AuraToastKind.info)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(child: SectionBar('Players')),
            Text(
              '$_joined / $_seats',
              style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.accentGlow, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _GlassBox(
          radius: 20,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          child: Row(
            children: [for (final s in seats) Expanded(child: _Seat(s))],
          ),
        ),
        const SizedBox(height: 12),
        _GlassBox(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_stakeText, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6))),
              Text(
                _potText,
                style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.amber, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        if (!_lobbyReady) ...[
          const SizedBox(height: 14),
          Center(
            child: Text('Waiting for your friend to join…', style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.5))),
          ),
        ],
        const SizedBox(height: 14),
        // Chess needs both players: Start unlocks at 2 / 2.
        GradientButton(label: _lobbyReady ? 'Start match' : 'Waiting for friend…', onPressed: _startMatch, enabled: _lobbyReady),
        const SizedBox(height: 12),
      ],
    );
  }
}

// ─────────────────────────── Pieces ───────────────────────────

/// Mockup screen header: 42px glass back button + left-aligned 22px title
/// (+ a green "Live" tag in the lobby).
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack, this.live = false});
  final String title;
  final VoidCallback onBack;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onBack,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.05)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            ),
            child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 22, color: Colors.white),
          ),
        ),
        if (live)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AuraColors.green,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AuraColors.green, blurRadius: 10)],
                ),
              ),
              const SizedBox(width: 6),
              const Text('Live', style: TextStyle(color: AuraColors.green, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
      ],
    );
  }
}

/// Paints a coloured drop shadow on an OPAQUE base under [child]. A Flutter
/// BoxShadow on a translucent box shows through it as a lighter inner panel
/// (CSS box-shadow never draws beneath its element), so the shadow goes here.
class _ShadowBase extends StatelessWidget {
  const _ShadowBase({required this.radius, required this.shadow, required this.child});
  final double radius;
  final BoxShadow shadow;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0C0A16),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [shadow],
        ),
        child: child,
      );
}

/// Glass panel (mockup: white 9%→3% gradient, 1px white 20% border).
class _GlassBox extends StatelessWidget {
  const _GlassBox({required this.child, required this.radius, required this.padding});
  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: 0.09), Colors.white.withValues(alpha: 0.03)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: child,
    );
  }
}

class _MenuAvatar extends StatelessWidget {
  const _MenuAvatar(this.initials, this.colors);
  final String initials;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 62,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        border: Border.all(color: const Color(0xFF0C0A16), width: 3),
        boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.8), blurRadius: 24, spreadRadius: -8, offset: const Offset(0, 10))],
      ),
      child: Text(initials, style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            fontWeight: FontWeight.w600,
            fontSize: 11,
            letterSpacing: 1,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
      );
}

/// Mockup `pick()` choice pill: brand gradient + pink glow when on, glass when
/// off. [compact] = the stake chips (42px tall, sized to the label).
class _Pick extends StatelessWidget {
  const _Pick({required this.label, required this.on, required this.onTap, this.compact = false});
  final String label;
  final bool on;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: compact ? 42 : 46,
        padding: compact ? const EdgeInsets.symmetric(horizontal: 14) : null,
        // Compact chips size to their label (an aligned Container would
        // stretch to the full Wrap width).
        alignment: compact ? null : Alignment.center,
        constraints: compact ? const BoxConstraints(minWidth: 56) : null,
        decoration: BoxDecoration(
          gradient: on
              ? AuraGradients.brand
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.03)],
                ),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: on ? Colors.white.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.18)),
          boxShadow: on
              ? [BoxShadow(color: AuraColors.brandPink.withValues(alpha: 0.7), blurRadius: 20, spreadRadius: -10, offset: const Offset(0, 10))]
              : null,
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: on ? Colors.white : Colors.white.withValues(alpha: 0.6),
              fontSize: compact ? 13 : 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// One room-code cell (mockup cellBase: 46×56, r14, 26px). Filled cells get a
/// soft accent border; the next cell to fill gets the bright focus ring.
class _CodeCell extends StatelessWidget {
  const _CodeCell({required this.char, required this.active, required this.focused});
  final String char;
  final bool active;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final filled = char.isNotEmpty;
    final ring = active && focused;
    return Container(
      width: 46,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active
              ? AuraColors.accentGlow.withValues(alpha: focused ? 1 : 0.6)
              : (filled ? AuraColors.accentGlow.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.24)),
          width: 1.5,
        ),
        boxShadow: ring ? [BoxShadow(color: AuraColors.accentGlow.withValues(alpha: 0.18), spreadRadius: 3)] : null,
      ),
      child: Text(char, style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
    );
  }
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
    return GestureDetector(
      onTap: onTap,
      child: _ShadowBase(
        radius: 22,
        shadow: BoxShadow(
          color: accent ? AuraColors.brandPurple.withValues(alpha: 0.8) : Colors.black.withValues(alpha: 0.7),
          blurRadius: accent ? 40 : 28,
          spreadRadius: accent ? -16 : -14,
          offset: Offset(0, accent ? 18 : 12),
        ),
        child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: accent
                ? [AuraColors.brandPurple.withValues(alpha: 0.30), AuraColors.brandPink.withValues(alpha: 0.12)]
                : [Colors.white.withValues(alpha: 0.09), Colors.white.withValues(alpha: 0.03)],
          ),
          border: Border.all(
            color: accent ? AuraColors.accentGlow.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.2),
            width: accent ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: accent
                      ? const [AuraColors.brandPurple, AuraColors.brandPink]
                      : const [Color(0xFF22D3EE), Color(0xFF3B82F6)],
                ),
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
                  Text(title, style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: accent ? 0.7 : 0.55)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: accent ? 1 : 0.55), size: 22),
          ],
        ),
      ),
      ),
    );
  }
}

class _OnlineFriend extends StatelessWidget {
  const _OnlineFriend({required this.name, required this.colors, required this.status, required this.onInvite});
  final String name;
  final List<Color> colors;
  final String status;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return _GlassBox(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: [
          // Rounded-square gradient avatar with an online dot (mockup).
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                  ),
                ),
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AuraColors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF0C0A16), width: 2),
                    ),
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
                Text(name, style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white)),
                Text(status, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
              ],
            ),
          ),
          GestureDetector(
            onTap: onInvite,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: const Text('Invite', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LobbyBtn extends StatelessWidget {
  const _LobbyBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
            Text(label, style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _SeatData {
  const _SeatData({required this.name, required this.initials, required this.colors, this.host = false}) : filled = true;
  const _SeatData.empty()
      : name = 'Waiting…',
        initials = '?',
        colors = const [],
        host = false,
        filled = false;

  final String name;
  final String initials;
  final List<Color> colors;
  final bool host;
  final bool filled;
}

/// Lobby seat (mockup): 54px gradient avatar + green check when filled, a
/// dashed empty ring with "?" while waiting, the name, and a HOST chip.
class _Seat extends StatelessWidget {
  const _Seat(this.s);
  final _SeatData s;

  @override
  Widget build(BuildContext context) {
    final avatar = s.filled
        ? Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: s.colors),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 18, spreadRadius: -6, offset: const Offset(0, 8))],
            ),
            child: Text(s.initials, style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
          )
        : CustomPaint(
            painter: _DashedCirclePainter(),
            child: Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05)),
              child: Text('?', style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
            ),
          );
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            if (s.filled)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AuraColors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0C0A16), width: 2),
                  ),
                  child: const Icon(Icons.check_rounded, size: 9, color: Color(0xFF0A0816)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 74),
          child: Text(
            s.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: s.filled ? Colors.white : Colors.white.withValues(alpha: 0.4)),
          ),
        ),
        if (s.host) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: AuraColors.accentGlow.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)),
            child: Text('HOST', style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.accentGlow, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.3);
    final r = size.width / 2 - 1;
    const dashes = 18;
    for (var i = 0; i < dashes; i++) {
      final start = (i / dashes) * 2 * pi;
      canvas.drawArc(Rect.fromCircle(center: size.center(Offset.zero), radius: r), start, pi / dashes, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
