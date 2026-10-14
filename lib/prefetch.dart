import 'dart:async';

import 'theme.dart' show log;
import 'xtream.dart';

/// What the player is doing, so background downloads can keep out of its way.
class Playback {
  Playback._();

  /// Number of player screens open (normally 0 or 1).
  static int open = 0;

  /// Last moment the player was connecting or buffering.
  static DateTime? lastTrouble;

  /// The player is connecting or buffering right now.
  static bool busy = false;

  /// Called by the player whenever it redraws.
  static void report(bool isBusy) {
    busy = isBusy;
    if (isBusy) lastTrouble = DateTime.now();
  }

  /// Something is playing and it has been smooth for a while.
  static bool get calm {
    if (open == 0) return true;
    if (busy) return false;
    final t = lastTrouble;
    return t == null || DateTime.now().difference(t) > const Duration(seconds: 10);
  }
}

/// After a playlist opens, downloads every list (categories and all channels, movies and
/// series) once in the background, one at a time with pauses, so the menus open instantly
/// later. While a stream is connecting or buffering (slow network), it waits until playback
/// has been smooth again for a while before taking the next list.
class ListPrefetch {
  ListPrefetch._();

  static Source? _for;
  static int _run = 0;

  static void start(Source api) {
    if (identical(_for, api)) return;
    _for = api;
    // A new playlist: the old one's lists leave memory.
    if (api is XtreamApi) api.makeActive();
    final run = ++_run;
    unawaited(_go(api, run));
  }

  static Future<void> _waitCalm(int run) async {
    // A short breath between lists, longer while a video plays.
    await Future<void>.delayed(Duration(seconds: Playback.open > 0 ? 6 : 2));
    while (run == _run && !Playback.calm) {
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  static Future<void> _go(Source api, int run) async {
    // Let the home screen settle first.
    await Future<void>.delayed(const Duration(seconds: 4));
    for (final kind in const [XKind.live, XKind.vod, XKind.series]) {
      // Only the category lists (small). Channel / film lists load a category at a time when
      // opened; "All" and Search load the full list only when the customer asks for it
      // (big lists in the background made weak TVs slow, mostly right after a playlist switch).
      for (final step in const ['categories']) {
        await _waitCalm(run);
        if (run != _run) return;
        final watch = Stopwatch()..start();
        try {
          if (step == 'categories') {
            await api.categories(kind);
          } else {
            final list = await api.items(kind);
            log('prefetch ${kind.name} items=${list.length} in ${watch.elapsedMilliseconds}ms');
          }
        } catch (e) {
          log('prefetch ${kind.name} $step failed: ${e.runtimeType}');
        }
      }
    }
    log('prefetch done');
  }
}
