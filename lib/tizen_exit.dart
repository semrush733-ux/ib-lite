import 'dart:io' show Platform, exit;

/// Closes the app where SystemNavigator cannot: on a computer (Windows) the window closes here.
/// Android closes through SystemNavigator; the Samsung TV through tizen_exit_web.dart.
void tizenExit() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) exit(0);
}
