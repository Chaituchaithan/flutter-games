import 'dart:async';

import 'package:google_fonts/google_fonts.dart';

/// Auto-loaded before any test in this directory. Disables google_fonts runtime
/// HTTP fetching so tests never depend on the network (they fall back to the
/// default font instead of throwing). The real app still fetches at runtime.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
