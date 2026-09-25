import 'package:flutter/material.dart';

import '../widgets/aura.dart';
import 'root_key.dart';
import 'routes.dart';

bool _showing = false;

/// Mockup `Dialog · expired`. Shown when the API reports the session is no longer
/// valid (401 / inactivity). Uses [rootNavigatorKey] so it can fire from the API
/// layer without a BuildContext. On confirm, returns to Login.
Future<void> showSessionExpiredDialog() async {
  if (_showing) return; // never stack duplicates from repeated 401s
  final context = rootNavigatorKey.currentContext;
  if (context == null) return;
  _showing = true;
  try {
    await showAuraDialog(
      context,
      icon: Icons.schedule_rounded,
      title: 'Session expired',
      body: 'For your security you were signed out after a period of inactivity. '
          'Please log in again.',
      primaryLabel: 'Log in again',
    );
  } finally {
    _showing = false;
  }
  rootNavigatorKey.currentState?.pushNamedAndRemoveUntil(Routes.login, (r) => false);
}
