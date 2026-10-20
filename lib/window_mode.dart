import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

/// Windows: the program's window. It opens full screen like a TV app (no title bar, no taskbar);
/// F11 / Alt+Enter switch to a maximised window and back, and that choice is remembered for the
/// next start (windows_extra/b1g_device.cpp). A video always plays full screen: when the viewer
/// chose a window, the player covers the screen while it is open and gives the window back after.
/// Other platforms: nothing to do.
class WindowMode {
  WindowMode._();

  static const _ch = MethodChannel('b1g/device');

  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// The open players made the window full screen (it goes back to a window when the last closes).
  static bool _forPlayer = false;
  static int _players = 0;

  /// F11 / Alt+Enter: the viewer's choice.
  static Future<void> toggle() async {
    if (!available) return;
    _forPlayer = false;
    try {
      await _ch.invokeMethod<bool>('toggleFullScreen');
    } catch (_) {}
  }

  static Future<bool> isFullScreen() async {
    if (!available) return false;
    try {
      return await _ch.invokeMethod<bool>('isFullScreen') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _set(bool on) async {
    try {
      await _ch.invokeMethod<bool>('setFullScreen', on);
    } catch (_) {}
  }

  /// A player screen opened: the video covers the whole screen.
  static Future<void> playerOpened() async {
    if (!available) return;
    _players++;
    if (_forPlayer || await isFullScreen()) return;
    _forPlayer = true;
    await _set(true);
  }

  /// A player screen closed: the window the viewer chose comes back.
  static Future<void> playerClosed() async {
    if (!available) return;
    _players = _players > 0 ? _players - 1 : 0;
    if (_players > 0 || !_forPlayer) return;
    _forPlayer = false;
    await _set(false);
  }
}
