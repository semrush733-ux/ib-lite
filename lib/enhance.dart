import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'store.dart';

/// Picture Enhance: a light sharpen plus a small colour / contrast lift on the video.
///
/// Level 0 = off, 1 = low, 2 = high. "Auto" starts at what this device can carry (from its
/// memory and processor) and never above what it managed before; while a stream plays the player
/// watches for skipped pictures and steps down by itself (remembered), so it never becomes a load.
class EnhanceLevel {
  EnhanceLevel._();

  static int? _device;

  /// What the hardware allows when nothing is learned yet.
  static Future<int> _deviceLevel() async {
    if (_device != null) return _device!;
    var level = 0;
    if (!kIsWeb) {
      try {
        final m = await const MethodChannel('b1g/device').invokeMethod<Map<dynamic, dynamic>>('deviceClass');
        final ram = (m?['ramMb'] as num?)?.toInt() ?? 0;
        final cores = (m?['cores'] as num?)?.toInt() ?? Platform.numberOfProcessors;
        final low = m?['lowRam'] == true;
        if (!low && ram >= 3300 && cores >= 4) {
          level = 2;
        } else if (!low && ram >= 1800 && cores >= 4) {
          level = 1;
        }
      } catch (_) {}
    }
    return _device = level;
  }

  /// The level a new video starts with.
  static Future<int> start() async {
    final mode = Store.enhanceMode;
    if (mode == 'off') return 0;
    final cap = Store.enhanceCap;
    if (mode == 'on') return cap < 0 ? 2 : (cap == 0 ? 1 : cap); // the viewer asked for it
    final dev = await _deviceLevel();
    return cap < 0 ? dev : (cap < dev ? cap : dev);
  }

  /// The device stuttered at [level]: remember one lower as its best.
  static void tooHeavy(int level) {
    final lower = (level - 1).clamp(0, 2);
    final cap = Store.enhanceCap;
    if (cap < 0 || lower < cap) Store.setEnhanceCap(lower);
  }

  /// Settings → "Picture Enhance" changed: learn again from scratch.
  static void reset() => Store.setEnhanceCap(-1);

  static String label(int level) => level >= 2 ? 'High' : (level == 1 ? 'Low' : 'Off');
}
