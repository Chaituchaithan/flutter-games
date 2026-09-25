import 'package:flutter/widgets.dart';

/// App-wide navigator key so non-widget code (e.g. the API 401 handler) can
/// show dialogs and navigate without a BuildContext. Wired into MaterialApp.
final rootNavigatorKey = GlobalKey<NavigatorState>();
