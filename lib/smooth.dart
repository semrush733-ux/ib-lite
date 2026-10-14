import 'store.dart';

/// How much video must be in the buffer before the picture starts / restarts.
class BufferProfile {
  const BufferProfile(this.startMs, this.rebufMs, this.mpvWait);
  final int startMs;
  final int rebufMs;
  final String mpvWait; // seconds MPV waits to refill after running dry
}

/// Smart buffer: the app learns, per IPTV server, how often streams stop to buffer.
/// A server that never stops gets a small buffer (channels open quicker); one that often stops
/// gets a bigger one (fewer stops). A stop adds a point, a long clean watch takes one away.
class Smooth {
  Smooth._();

  static String hostOf(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return '';
    return u.hasPort ? '${u.host}:${u.port}' : u.host;
  }

  static int score(String url) {
    final h = hostOf(url);
    return h.isEmpty ? 1 : Store.stallScore(h);
  }

  static BufferProfile profileFor(String url, {required bool live}) {
    final s = score(url);
    if (live) {
      // A server that never stops starts with very little in the buffer (picture comes fastest).
      if (s <= 0) return const BufferProfile(800, 2000, '1');
      if (s <= 2) return const BufferProfile(1100, 2500, '1');
      if (s <= 4) return const BufferProfile(2500, 5000, '2');
      return const BufferProfile(4000, 8000, '3');
    }
    if (s <= 0) return const BufferProfile(800, 2500, '1');
    if (s <= 2) return const BufferProfile(1200, 3000, '2');
    if (s <= 4) return const BufferProfile(2500, 5000, '3');
    return const BufferProfile(4000, 8000, '4');
  }

  static void stalled(String url) {
    final h = hostOf(url);
    if (h.isEmpty) return;
    Store.setStallScore(h, (Store.stallScore(h) + 1).clamp(0, 6));
  }

  static void cleanRun(String url) {
    final h = hostOf(url);
    if (h.isEmpty) return;
    Store.setStallScore(h, (Store.stallScore(h) - 1).clamp(0, 6));
  }
}
