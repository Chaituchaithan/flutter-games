import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Master switch for the **static → dynamic** migration.
///
/// When `false` (default, and today's behaviour) every repository serves its
/// bundled static source, so the UI is identical to the presentation build.
/// Flip to `true` (per build via override, or per-domain later) once the
/// backend is live. See docs/INTEGRATION_PLAN.md §2.
final useRemoteSourcesProvider = Provider<bool>((ref) => false);
