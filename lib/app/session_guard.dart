import 'package:flutter/material.dart';

import '../services/app_exception.dart';
import '../widgets/aura.dart';
import 'root_key.dart';
import 'routes.dart';

bool _showing = false;

/// Mockup `Dialog · expired`. Shown when the API reports the session is no longer
/// valid (401 / inactivity). Uses [rootNavigatorKey] so it can fire from the API
/// layer without a BuildContext. On confirm, returns to Login.
Future<void> showSessionExpiredDialog([AppException? reason]) async {
  if (_showing) return; // never stack duplicates from repeated 401s
  final context = rootNavigatorKey.currentContext;
  if (context == null) return;
  // A ban (12-safety.md §4): the full "Account restricted" screen instead.
  if (reason?.isBanned ?? false) {
    showAccountRestricted(reason?.until);
    return;
  }
  _showing = true;
  final banned = reason?.isBanned ?? false;
  final endedElsewhere = reason?.code == ApiErrorCode.tokenBlacklisted;
  try {
    await showAuraDialog(
      context,
      icon: banned ? Icons.block_rounded : Icons.schedule_rounded,
      title: banned ? 'Account suspended' : (endedElsewhere ? 'Signed out' : 'Session expired'),
      body: banned
          ? banMessage(reason?.until)
          : endedElsewhere
              ? 'This session was ended (signed out elsewhere or the password changed). Please log in again.'
              : 'For your security you were signed out after a period of inactivity. Please log in again.',
      primaryLabel: 'Log in again',
    );
  } finally {
    _showing = false;
  }
  rootNavigatorKey.currentState?.pushNamedAndRemoveUntil(Routes.login, (r) => false);
}

/// "Account restricted" full screen over everything (ACCOUNT_BANNED from any
/// route, or a `full` scope in the ban check). Tokens are cleared by the caller.
void showAccountRestricted(DateTime? until) {
  rootNavigatorKey.currentState
      ?.pushNamedAndRemoveUntil(Routes.accountRestricted, (r) => false, arguments: {'until': until});
}

bool _regionShowing = false;

/// "Not available in your region" (12-safety.md §6) for a sign-in or read
/// refused by the region gate. Shown once until Retry clears it.
Future<void> showRegionBlocked() async {
  final nav = rootNavigatorKey.currentState;
  if (_regionShowing || nav == null) return;
  _regionShowing = true;
  try {
    await nav.pushNamed(Routes.regionBlocked);
  } finally {
    _regionShowing = false;
  }
}

/// For sign-in screens: a ban or a region refusal on sign-in gets its full
/// screen. Returns true when [e] was handled that way (show no toast).
bool handleSignInBlock(AppException e) {
  if (e.isBanned) {
    showAccountRestricted(e.until);
    return true;
  }
  // The API client already opened the region screen (GeoBlock.full).
  return e.code == ApiErrorCode.geoBlocked;
}
