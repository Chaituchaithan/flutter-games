import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/languages.dart';
import '../l10n/l10n.dart';
import 'app_profile.dart';
import 'root_key.dart';
import 'routes.dart';
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
    );
  }
}
