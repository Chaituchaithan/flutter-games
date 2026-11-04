import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// The app is portrait everywhere except screens that ask for landscape
/// (Snooker). Such a screen calls [enter] when it opens (initState) and
/// [exit] when it closes (dispose); the phone turns, the system bars hide
/// for a full-screen table, and the portrait frame (`PortraitFrame`) steps
/// aside while it's up.
abstract final class LandscapeMode {
  /// How many landscape screens are open (one, or two for a moment when one
  /// replaces another, e.g. "Play again").
  static final ValueNotifier<int> screens = ValueNotifier(0);

  static void enter() {
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _afterFrame(() => screens.value++);
  }

  static void exit() => _afterFrame(() {
    if (screens.value > 0) screens.value--;
    if (screens.value > 0) return; // another landscape screen is up
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    // Back to the app's default: status and navigation bars shown.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
  });

  /// initState and dispose run while the tree is being built or torn down,
  /// when the frame above can't rebuild: count the screen just after.
  static void _afterFrame(VoidCallback f) {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => f())
      ..ensureVisualUpdate();
  }
}
