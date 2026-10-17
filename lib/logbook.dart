import 'dart:collection';

/// The last lines the app wrote to its log, kept in memory for "Report a problem".
///
/// Nothing private leaves the TV with it: stream and website addresses keep only their host
/// (an Xtream address carries the username and password in its path), and anything written as
/// user= / password= / token= is masked.
class LogBook {
  LogBook._();

  static const _max = 500;
  static final _lines = ListQueue<String>();

  static final _url = RegExp(r'([a-z][a-z0-9+.\-]*://)([^/\s?#]+)([^\s]*)', caseSensitive: false);
  static final _secret = RegExp(
      r'\b((?:user(?:name)?|pass(?:word)?|pwd|token|key|pin|pairing_code)\s*[=:]\s*)[^&\s,;]+',
      caseSensitive: false);

  /// The line as it may be sent: addresses cut to scheme and host, secrets masked.
  static String clean(String line) {
    var s = line.replaceAllMapped(_url, (m) {
      final host = m[2] ?? '';
      final at = host.lastIndexOf('@');
      final rest = m[3] ?? '';
      return '${m[1]}${at >= 0 ? host.substring(at + 1) : host}${rest.isEmpty ? '' : '/…'}';
    });
    s = s.replaceAllMapped(_secret, (m) => '${m[1]}***');
    return s.length > 400 ? '${s.substring(0, 400)}…' : s;
  }

  static void add(String message) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _lines.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} ${clean(message)}');
    while (_lines.length > _max) {
      _lines.removeFirst();
    }
  }

  /// The newest [last] lines, oldest first.
  static String text({int last = 350}) {
    final skip = _lines.length > last ? _lines.length - last : 0;
    return _lines.skip(skip).join('\n');
  }
}

/// What the player played last, for "Report a problem" (never the address with the login).
class LastStream {
  LastStream._();

  static String title = '';
  static String kind = ''; // live / film / episode / catch-up
  static String host = '';
  static String format = '';
  static String engine = '';
  static String video = '';
  static String state = ''; // connecting / playing / reconnecting / failed / closed
  static String error = '';
  static DateTime? at;

  static String _hostOf(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return '';
    return u.hasPort ? '${u.host}:${u.port}' : u.host;
  }

  static void opened({
    required String title,
    required String kind,
    required String url,
    required String format,
    required String engine,
    required bool retry,
  }) {
    if (!retry || LastStream.title != title) {
      video = '';
      error = '';
    }
    LastStream.title = title;
    LastStream.kind = kind;
    host = _hostOf(url);
    LastStream.format = format;
    LastStream.engine = engine;
    state = retry ? 'reconnecting' : 'connecting';
    at = DateTime.now();
  }

  static void playing(String video, String engine) {
    LastStream.video = video;
    LastStream.engine = engine;
    state = 'playing';
    at = DateTime.now();
  }

  static void failed(String why) {
    state = 'failed';
    if (why.isNotEmpty) error = LogBook.clean(why);
    at = DateTime.now();
  }

  static void noteError(String text) {
    error = LogBook.clean(text);
  }

  static void closed() {
    if (state == 'playing' || state == 'connecting' || state == 'reconnecting') state = 'closed';
  }

  static Map<String, String> toMap() {
    if (title.isEmpty) return const {};
    String two(int n) => n.toString().padLeft(2, '0');
    final t = at;
    return {
      'title': title,
      'kind': kind,
      if (host.isNotEmpty) 'host': host,
      if (format.isNotEmpty) 'format': format,
      if (engine.isNotEmpty) 'engine': engine,
      if (video.isNotEmpty) 'video': video,
      'state': state,
      if (error.isNotEmpty) 'error': error.length > 280 ? error.substring(0, 280) : error,
      if (t != null) 'time': '${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
    };
  }
}
