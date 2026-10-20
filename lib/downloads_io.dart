import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'config.dart';
import 'downloads_core.dart';
import 'prefetch.dart' show Playback;

export 'downloads_core.dart';

/// Downloads films and episodes into the app's own storage so they play without internet.
///
/// Built so the player is never affected:
///  * one download at a time, on its own connection;
///  * it holds back while any video plays (full screen or the live preview) — most IPTV accounts
///    allow one connection, a second one would stop the picture — and carries on afterwards
///    from the byte where it stopped (no new start);
///  * progress reaches the screen at most 4 times a second (no extra work for the TV).
class Downloads extends ChangeNotifier {
  Downloads._();
  static final Downloads i = Downloads._();

  /// Android (TV, Fire TV, phones) and Windows; not in the Google Play build.
  static bool get available => !kPlay && (Platform.isAndroid || Platform.isWindows);

  /// Other places that may be playing a video (the live preview registers itself here).
  static final Set<bool Function()> watchers = {};

  final List<DlItem> items = [];
  bool _loaded = false;
  Directory? _dir;
  DlItem? _current;
  HttpClient? _client;
  bool _stop = false;
  Timer? _tick;

  bool get busy => items.any((d) => d.state == DlState.running);

  /// A video is on screen: downloads wait (one connection per account).
  bool get _playing => Playback.open > 0 || watchers.any((f) {
        try {
          return f();
        } catch (_) {
          return false;
        }
      });

  Future<void> init() async {
    if (_loaded || !available) return;
    _loaded = true;
    try {
      if (Platform.isWindows) {
        // Windows: Documents\<app name>\Downloads, where people can also find the files.
        final docs = await getApplicationDocumentsDirectory();
        _dir = Directory('${docs.path}\\$kAppName\\Downloads')..createSync(recursive: true);
      } else {
        final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        _dir = Directory('${base.path}/downloads')..createSync(recursive: true);
      }
      final f = File('${_dir!.path}/list.json');
      if (f.existsSync()) {
        final list = jsonDecode(f.readAsStringSync());
        if (list is List) {
          for (final j in list) {
            if (j is Map<String, dynamic>) items.add(DlItem.fromJson(j));
          }
        }
      }
      for (final d in items) {
        // A download cut by closing the app goes on by itself.
        if (d.state == DlState.running || d.state == DlState.waiting) d.state = DlState.queued;
        if (d.done && !File(d.path).existsSync()) {
          d.state = DlState.failed;
          d.error = Platform.isWindows ? 'The file was removed from this computer.' : 'The file was removed from the TV.';
        }
      }
    } catch (e) {
      debugPrint('downloads init: $e');
    }
    // Watches for "a video started / stopped" to hold back and carry on.
    _tick = Timer.periodic(const Duration(seconds: 2), (_) => _pump());
    _pump();
  }

  DlItem? byId(String id) {
    for (final d in items) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Address the player opens for a finished download (null when not downloaded).
  String? localUrl(String id) {
    final d = byId(id);
    if (d == null || !d.done || !File(d.path).existsSync()) return null;
    return Uri.file(d.path).toString();
  }

  Future<void> add({
    required String id,
    required String title,
    required String url,
    String subtitle = '',
    String cover = '',
  }) async {
    await init();
    if (byId(id) != null || _dir == null || url.isEmpty) return;
    final segs = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    final last = segs.isEmpty ? '' : segs.last;
    var ext = last.contains('.') ? last.split('.').last.toLowerCase() : 'mp4';
    if (ext.length > 4 || ext.isEmpty) ext = 'mp4';
    final safe = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final d = DlItem(id: id, title: title, subtitle: subtitle, cover: cover, url: url, ext: ext, path: '${_dir!.path}/$safe.$ext');
    items.insert(0, d);
    _save();
    notifyListeners();
    _pump();
  }

  void pause(String id) {
    final d = byId(id);
    if (d == null || d.done) return;
    d.state = DlState.paused;
    d.speed = 0;
    if (identical(d, _current)) _abort();
    _save();
    notifyListeners();
    _pump();
  }

  void resume(String id) {
    final d = byId(id);
    if (d == null || d.done) return;
    d.state = DlState.queued;
    d.error = '';
    _save();
    notifyListeners();
    _pump();
  }

  void remove(String id) {
    final d = byId(id);
    if (d == null) return;
    if (identical(d, _current)) _abort();
    items.remove(d);
    try {
      final f = File(d.path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    _save();
    notifyListeners();
    _pump();
  }

  void _abort() {
    _stop = true;
    try {
      _client?.close(force: true);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- the worker

  void _pump() {
    if (_dir == null) return;
    final cur = _current;
    if (cur != null) {
      // A video started: the download lets go of the connection and waits.
      if (_playing && cur.state == DlState.running) {
        cur.state = DlState.waiting;
        cur.speed = 0;
        _abort();
        notifyListeners();
      }
      return;
    }
    DlItem? next;
    for (final d in items.reversed) {
      // oldest first
      if (d.state == DlState.queued || d.state == DlState.waiting) {
        next = d;
        break;
      }
    }
    if (next == null) return;
    if (_playing) {
      if (next.state != DlState.waiting) {
        next.state = DlState.waiting;
        notifyListeners();
      }
      return;
    }
    _run(next);
  }

  Future<void> _run(DlItem d) async {
    _current = d;
    _stop = false;
    d.state = DlState.running;
    d.error = '';
    notifyListeners();
    var tries = 0;
    while (!_stop) {
      try {
        await _fetch(d);
        if (_stop) break;
        d.state = DlState.done;
        d.speed = 0;
        break;
      } catch (e) {
        if (_stop) break;
        tries++;
        // 28: Android / Linux "no space"; 39 and 112: Windows "disk full".
        final code = e is FileSystemException ? e.osError?.errorCode : null;
        final full = e is FileSystemException &&
            (code == 28 || (Platform.isWindows && (code == 39 || code == 112)) || '${e.osError}'.contains('No space'));
        if (full || tries >= 6) {
          d.state = DlState.failed;
          d.speed = 0;
          d.error = full ? (Platform.isWindows ? 'The disk is full.' : 'The TV storage is full.') : _reason(e);
          break;
        }
        d.speed = 0;
        notifyListeners();
        await Future<void>.delayed(Duration(seconds: 3 * tries));
        if (_playing) break;
      }
    }
    if (d.state == DlState.running) d.state = _playing ? DlState.waiting : DlState.queued;
    _current = null;
    _client = null;
    _save();
    notifyListeners();
    // Next one (or carry on later).
    Future<void>.delayed(const Duration(milliseconds: 300), _pump);
  }

  String _reason(Object e) {
    final s = '$e';
    if (s.contains('403') || s.contains('401')) return 'The server refused the download (account limit?).';
    if (s.contains('404')) return 'The server no longer has this file.';
    return 'No connection to the server. Try again.';
  }

  Future<void> _fetch(DlItem d) async {
    final file = File(d.path);
    var have = file.existsSync() ? file.lengthSync() : 0;
    if (d.total > 0 && have >= d.total) {
      d.got = d.total;
      return;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 20)
      ..userAgent = kUserAgent;
    _client = client;
    try {
      final req = await client.getUrl(Uri.parse(d.url));
      req.followRedirects = true;
      req.maxRedirects = 8;
      if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}');
      if (res.statusCode == 200 && have > 0) {
        // The server does not continue: start the file again.
        have = 0;
      }
      if (res.statusCode == 206) {
        final cr = res.headers.value(HttpHeaders.contentRangeHeader) ?? '';
        final total = int.tryParse(cr.split('/').last) ?? 0;
        if (total > 0) d.total = total;
      } else if (res.contentLength > 0) {
        d.total = res.contentLength;
      }
      final sink = file.openSync(mode: have > 0 ? FileMode.append : FileMode.write);
      d.got = have;
      var windowBytes = 0;
      var windowStart = DateTime.now();
      var lastShow = DateTime.now();
      var lastSave = DateTime.now();
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 25))) {
          if (_stop) break;
          sink.writeFromSync(chunk);
          d.got += chunk.length;
          windowBytes += chunk.length;
          final now = DateTime.now();
          final ms = now.difference(windowStart).inMilliseconds;
          if (ms >= 700) {
            final s = windowBytes * 1000 ~/ ms;
            d.speed = d.speed == 0 ? s : (d.speed * 2 + s) ~/ 3; // calm number, no jumping
            windowBytes = 0;
            windowStart = now;
          }
          if (now.difference(lastShow).inMilliseconds >= 250) {
            lastShow = now;
            notifyListeners();
          }
          if (now.difference(lastSave).inSeconds >= 5) {
            lastSave = now;
            _save();
          }
        }
      } finally {
        sink.closeSync();
      }
      if (_stop) return;
      if (d.total > 0 && d.got < d.total) throw const HttpException('Connection ended early');
      if (d.total == 0) d.total = d.got;
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  void _save() {
    final dir = _dir;
    if (dir == null) return;
    try {
      File('${dir.path}/list.json').writeAsStringSync(jsonEncode(items.map((d) => d.toJson()).toList()));
    } catch (_) {}
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}
