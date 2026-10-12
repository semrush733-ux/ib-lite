import 'package:flutter/material.dart';

import 'config.dart';
import 'remote_brand.dart';

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

/// The app's logo, drawn in code: the brand symbol and the name next to it (first word white,
/// the rest red). Symbol and name come from the website (Settings -> App look) when set, so the
/// logo is sharp on every screen and the app stays light.
class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 34});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: RemoteBrand.changes,
      builder: (context, _, __) {
        final name = (RemoteBrand.logoName.isNotEmpty ? RemoteBrand.logoName : kAppName).trim();
        final space = name.indexOf(' ');
        final first = space > 0 ? name.substring(0, space) : name;
        final rest = space > 0 ? name.substring(space) : '';
        final symbol = RemoteBrand.symbol;
        final h = size * 1.5;
        Widget fallback(BuildContext c, Object e, StackTrace? st) => const SizedBox();
        return SizedBox(
          height: h,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: h,
                height: h,
                child: symbol != null
                    ? Image(image: symbol, fit: BoxFit.contain, filterQuality: FilterQuality.medium, errorBuilder: fallback)
                    : Image.asset('assets/symbol.png',
                        fit: BoxFit.contain, filterQuality: FilterQuality.medium, errorBuilder: fallback),
              ),
              SizedBox(width: size * 0.32),
              // No Flexible: the logo also sits in rows without a width limit (top bars).
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: first, style: const TextStyle(color: Colors.white)),
                  if (rest.isNotEmpty) TextSpan(text: rest, style: const TextStyle(color: C.accent)),
                ]),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, letterSpacing: -0.5, height: 1),
              ),
            ],
          ),
        );
      },
    );
  }
}
