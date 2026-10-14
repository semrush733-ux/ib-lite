import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart' show kUserAgent;
import 'prefetch.dart' show Playback;
import 'theme.dart' show log;

class Warmup {
  Warmup._();

  static final Map<String, DateTime> _done = {};

  /// Looks up the server and opens (and closes) one connection to it. At most once a minute
  /// per server.
  static void host(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty || !(u.scheme == 'http' || u.scheme == 'https')) return;
    final port = u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80);
    final key = '${u.host}:$port';
    final last = _done[key];
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(seconds: 60)) return;
    _done[key] = now;
    if (_done.length > 50) _done.remove(_done.keys.first);
    unawaited(_touch(u.host, port));
  }

  static Future<void> _touch(String host, int port) async {
    try {
      await InternetAddress.lookup(host).timeout(const Duration(seconds: 3));
      final s = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
      s.destroy();
    } catch (_) {}
  }

  /// Film / episode page (nothing is playing): asks the server for the start of the file, so
  /// the server (and any cache in front of it) has it ready when "Watch" is pressed.
  static void film(String url) {
    host(url);
    if (Playback.open > 0) return; // never next to a stream that plays
    unawaited(_head(url));
  }

  static http.Client? _filmClient;

  /// The player opened: stop the film head start (one connection at a time).
  static void stopFilm() {
    _filmClient?.close();
    _filmClient = null;
  }

  static Future<void> _head(String url) async {
    stopFilm();
    final client = _filmClient = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..headers['User-Agent'] = kUserAgent
        ..headers['Range'] = 'bytes=0-262143';
      final res = await client.send(req).timeout(const Duration(seconds: 6));
      var got = 0;
      await for (final chunk in res.stream.timeout(const Duration(seconds: 6))) {
        got += chunk.length;
        if (got >= 262144) break;
      }
      log('warmup film ${res.statusCode} ${got ~/ 1024} KB');
    } catch (_) {
    } finally {
      client.close();
      if (identical(_filmClient, client)) _filmClient = null;
    }
  }
}
