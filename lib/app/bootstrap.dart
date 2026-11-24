import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/configs.dart';
import '../services/app_prefs.dart';
import 'app_profile.dart';
import 'aura_app.dart';

/// Starts an app with [profile]'s games. Every entry point (`lib/main*.dart`)
/// calls this — the only difference between the apps is the profile.
Future<void> runAuraApp(AppProfile profile) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Debug builds: the "Server" host from Settings (read before any request,
  // since the API base URL is fixed on first use).
  if (kDebugMode) AppConfig.useDebugHost(await const AppPrefs().get(AppConfig.serverHostPrefKey));
  // Portrait only: every screen and game board is designed for it (also set
  // in AndroidManifest / Info.plist so the screen never flips at launch).
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  AppProfile.current = profile;
  GameRegistry.setAppGames([for (final m in profile.modules) m.id]);
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
