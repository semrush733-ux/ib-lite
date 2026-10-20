import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart' show kBackMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'backend.dart';
import 'downloads.dart';
import 'config.dart';
import 'input_mode.dart';
import 'reminders.dart';
import 'remote_brand.dart';
import 'screens/device.dart';
import 'screens/intro.dart';
import 'screens/start_problem.dart';
import 'start.dart';
import 'store.dart';
import 'theme.dart';
import 'voice.dart';

/// MediaKit and the key watcher are set up once, also when "Try again" opens the app anew.
bool _basicsReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _open();
}

/// Opens the app. When something it needs fails while it opens (its saved settings, the player
/// library), [StartProblemApp] shows why and offers the newest version from the website, instead
/// of leaving the TV on the start logo.
Future<void> _open() async {
  try {
    if (!_basicsReady) {
      MediaKit.ensureInitialized();
      InputMode.init();
      _basicsReady = true;
    }
    await Store.init();
    await RemoteBrand.init();
    await Backend.init();
  } catch (e, stack) {
    log('start failed: $e');
    debugPrint('B1G start failed at: ${stack.toString().split('\n').take(8).join(' | ')}');
    runApp(StartProblemApp(error: '$e', retry: () => unawaited(_open())));
    return;
  }
  // Voice: Alexa / Google Assistant commands for the player, and whether a microphone can be offered.
  try {
    await Voice.init().timeout(const Duration(seconds: 3));
  } catch (e) {
    log('voice init: ${e.runtimeType}');
  }
  // Unfinished downloads carry on by themselves (they wait while a video plays).
  unawaited(Downloads.i.init().catchError((Object e) {
    log('downloads init: ${e.runtimeType}');
  }));
  // TV Guide reminders: a message when a chosen programme starts.
  try {
    Reminders.start();
  } catch (e) {
    log('reminders init: ${e.runtimeType}');
  }
  // Keep memory low on TV sticks with 1 GB of RAM.
  PaintingBinding.instance.imageCache.maximumSize = 300;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;
  // The remote is the main input: always show which element has focus.
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  if (!_desktop) {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky).catchError((Object _) {}));
    try {
      await SystemChrome.setPreferredOrientations(
          const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]).timeout(const Duration(seconds: 3));
    } catch (e) {
      log('screen mode: ${e.runtimeType}');
    }
  }
  runApp(const B1GApp());
}

/// Windows: keyboard and mouse stand in for the remote. Esc (and the mouse's back button) is the
/// remote's Back; F11 or Alt+Enter switches full screen (done by the Windows program, see
/// windows_extra/b1g_device.cpp).
bool get _desktop => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

class _BackIntent extends Intent {
  const _BackIntent();
}

class _FullScreenIntent extends Intent {
  const _FullScreenIntent();
}

void _back() => navigatorKey.currentState?.maybePop();

Future<void> _toggleFullScreen() async {
  try {
    await const MethodChannel('b1g/device').invokeMethod<bool>('toggleFullScreen');
  } catch (_) {}
}

final Map<ShortcutActivator, Intent>? _desktopShortcuts = _desktop
    ? {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.escape): const _BackIntent(),
        const SingleActivator(LogicalKeyboardKey.browserBack): const _BackIntent(),
        const SingleActivator(LogicalKeyboardKey.f11): const _FullScreenIntent(),
        const SingleActivator(LogicalKeyboardKey.enter, alt: true): const _FullScreenIntent(),
      }
    : null;

final Map<Type, Action<Intent>>? _desktopActions = _desktop
    ? {
        ...WidgetsApp.defaultActions,
        _BackIntent: CallbackAction<_BackIntent>(onInvoke: (_) {
          _back();
          return null;
        }),
        _FullScreenIntent: CallbackAction<_FullScreenIntent>(onInvoke: (_) {
          unawaited(_toggleFullScreen());
          return null;
        }),
      }
    : null;

class B1GApp extends StatelessWidget {
  const B1GApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      navigatorKey: navigatorKey,
      shortcuts: _desktopShortcuts,
      actions: _desktopActions,
      // Any touch switches the player to touch controls; any key switches back to remote hints.
      // AppGate checks the licence and looks for app updates, whatever screen is open.
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          InputMode.remote = false;
          if (_desktop && (e.buttons & kBackMouseButton) != 0) _back();
        },
        child: AppGate(child: child ?? const SizedBox()),
      ),
      // Start animation with its sound, then the app.
      home: IntroGate(next: Backend.allowed ? startScreen() : const ActivationScreen()),
    );
  }
}
