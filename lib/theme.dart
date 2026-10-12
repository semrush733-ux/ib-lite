import 'package:flutter/material.dart';

import 'config.dart';

class C {
  static const bg = Color(0xFF0E0A0B);
  static const panel = Color(0xFF181214);
  static const card = Color(0xFF231A1C);
  static const accent = Color(0xFFE3262F);
  /// Text and icons drawn on the accent colour.
  static const onAccent = Colors.white;
  static const text = Color(0xFFF2F4F8);
  static const dim = Color(0xFF8B93A3);
  static const danger = Color(0xFFFF6B6B);
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.accent, brightness: Brightness.dark),
  );
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    splashFactory: NoSplash.splashFactory,
    // No page animations: route changes stay instant on slow TV sticks.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: _NoTransitions(),
      TargetPlatform.iOS: _NoTransitions(),
    }),
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
  );
}

class _NoTransitions extends PageTransitionsBuilder {
  const _NoTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return child;
  }
}

void log(String message) => debugPrint('B1G $message');

/// The brand logo (brand/logo.png, copied to assets/logo.png by the build);
/// the app name in text when the picture is missing.
class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 34});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size * 1.5,
      child: Image.asset(
        'assets/logo.png',
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Text(
          kAppName,
          style: TextStyle(color: C.text, fontSize: size, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
