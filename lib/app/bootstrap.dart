import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/games/games.dart';
import 'app_profile.dart';
import 'aura_app.dart';

/// Starts an app with [profile]'s games. Every entry point (`lib/main*.dart`)
/// calls this — the only difference between the apps is the profile.
void runAuraApp(AppProfile profile) {
  WidgetsFlutterBinding.ensureInitialized();
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
