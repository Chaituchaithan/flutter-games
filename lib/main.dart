import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/root_key.dart';
import 'app/routes.dart';
import 'app/session_guard.dart';
import 'services/api_client.dart';
import 'services/session.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Light status-bar icons over the dark background.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
  runApp(const ProviderScope(child: AuraApp()));
}

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
    // Still 401 after that: clear the session and show "Session expired".
    api.onUnauthorized = () {
      ref.read(sessionProvider.notifier).forceSignOut();
      showSessionExpiredDialog();
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess',
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AuraColors.bgBase,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AuraColors.brandPurple,
          brightness: Brightness.dark,
        ),
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
