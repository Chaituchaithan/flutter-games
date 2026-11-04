import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/languages.dart';
import '../l10n/l10n.dart';
import 'app_profile.dart';
import 'root_key.dart';
import 'routes.dart';
import 'screen_orientation.dart';
import 'session_guard.dart';
import '../services/api_client.dart';
import '../services/session.dart';
import '../services/socket/app_socket.dart';
import '../theme.dart';

class AuraApp extends ConsumerStatefulWidget {
  const AuraApp({super.key});

  @override
  ConsumerState<AuraApp> createState() => _AuraAppState();
}

class _AuraAppState extends ConsumerState<AuraApp> {
  @override
  void initState() {
    super.initState();
    final api = ref.read(apiClientProvider);
    // Expired access token (15 min): refresh with the refresh token and retry.
    api.onRefreshToken = () => ref.read(sessionProvider.notifier).refreshSession();
    // Socket reconnects (e.g. after the 15-min token expiry) sign in with a
    // valid token — refreshed when the saved one has expired.
    ref.read(appSocketProvider).freshToken = () => ref.read(sessionProvider.notifier).validAccessToken();
    // Still 401 after that: clear the session and show "Session expired".
    api.onUnauthorized = () {
      ref.read(sessionProvider.notifier).forceSignOut();
      showSessionExpiredDialog();
    };
  }

  @override
  Widget build(BuildContext context) {
    // The language picked on the Language screen / saved in the profile.
    final language = appLanguages[ref.watch(languageProvider)].code;
    return MaterialApp(
      title: AppProfile.current.appName,
      locale: appLocaleFor(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AuraColors.bgBase,
        colorScheme: ColorScheme.fromSeed(seedColor: AuraColors.brandPurple, brightness: Brightness.dark),
        // Body face (Manrope) as the app-wide default; headings/numbers/buttons
        // opt into the display face via AuraText.
        fontFamily: AuraText.bodyFamily,
        useMaterial3: true,
      ),
      // Use the single-segment root ('/') as the entry. It maps to Splash via
      // onGenerateRoute's default case. (Routes.splash would generate a
      // multi-route stack ['/', '/splash'] on web and mis-navigate.)
      initialRoute: '/',
      onGenerateRoute: Routes.onGenerateRoute,
      // Portrait layout everywhere, even where the orientation lock can't
      // apply (browser / desktop windows, Android 16 large screens).
      builder: (context, child) => PortraitFrame(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Keeps the app in its portrait (phone) layout on wide windows: when the
/// window is wider than it is tall, or wider than a big phone, the app is
/// shown centred at phone width with dark side bars instead of stretching.
/// Phones in portrait are untouched.
class PortraitFrame extends StatelessWidget {
  const PortraitFrame({super.key, required this.child});
  final Widget child;

  /// Widest the app gets (a large phone).
  static const maxWidth = 520.0;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: LandscapeMode.screens, // a landscape screen (Snooker) uses the whole window
    builder: (context, n, _) => _frame(context, framing: n == 0),
  );

  /// Always the same widgets around [child], whether framed or not: only
  /// sizes change, so turning the phone (or opening Snooker) never rebuilds
  /// the navigator and its open screens.
  Widget _frame(BuildContext context, {required bool framing}) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final landscape = size.width > size.height;
    final phone = landscape ? (size.height * 0.5).clamp(320.0, maxWidth) : size.width.clamp(0.0, maxWidth);
    final framed = framing && phone < size.width;
    final width = framed ? phone : size.width;
    return ColoredBox(
      color: const Color(0xFF05040A),
      child: Center(
        child: SizedBox(
          width: width,
          height: size.height,
          child: ClipRect(
            // Screens size themselves from MediaQuery: give them the frame's
            // size (and no side insets) so layouts compute for phone width.
            child: MediaQuery(
              data: framed
                  ? mq.copyWith(
                      size: Size(width, size.height),
                      padding: mq.padding.copyWith(left: 0, right: 0),
                      viewPadding: mq.viewPadding.copyWith(left: 0, right: 0),
                      viewInsets: mq.viewInsets.copyWith(left: 0, right: 0),
                    )
                  : mq,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
