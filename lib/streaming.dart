import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';
import 'config.dart';
import 'store.dart';
import 'theme.dart' show log;
import 'tmdb.dart' show cleanTitle, CleanTitle;
import 'xtream.dart';

/// Streaming service boxes on the home screen (Settings › Streaming Boxes): Netflix, Prime Video…
/// A box shows the playlist's own movies and series of that service, found two ways:
///  1. the playlist's categories named after the service ("NETFLIX MOVIES", "AMAZON PRIME"…);
///  2. the website's daily list of the service's titles (from TMDB, the film database), matched
///     with the playlist's titles.
/// Only the service's name is shown, never the company's logo.
class StreamingService {
  const StreamingService(this.id, this.name, this.words);
  final String id;
  final String name;

  /// Whole words in a category name that mean this service (lower case, letters and digits).
  final List<String> words;
}

const kStreamingServices = <StreamingService>[
  StreamingService('netflix', 'Netflix', ['netflix', 'nflx']),
  StreamingService('prime', 'Prime Video', ['amazon', 'prime']),
  StreamingService('disney', 'Disney+', ['disney']),
  StreamingService('hbo', 'HBO Max', ['hbo']),
  StreamingService('apple', 'Apple TV+', ['apple', 'appletv']),
  StreamingService('paramount', 'Paramount+', ['paramount']),
  StreamingService('hulu', 'Hulu', ['hulu']),
  StreamingService('peacock', 'Peacock', ['peacock']),
];

/// The boxes switched on in Settings, in the order above (none in the Google Play build).
List<StreamingService> enabledStreaming() =>
    kPlay ? const <StreamingService>[] : [for (final s in kStreamingServices) if (Store.streamingOn(s.id)) s];

const _accentFrom = 'àáâãäåèéêëìíîïòóôõöùúûüçñ';
const _accentTo = 'aaaaaaeeeeiiiiooooouuuucn';
final Map<int, int> _accents = {for (var i = 0; i < _accentFrom.length; i++) _accentFrom.codeUnitAt(i): _accentTo.codeUnitAt(i)};

/// Lower case, letters and digits only ("Spider-Man: No Way Home" → "spider man no way home").
/// Quick: it runs over every title of a big playlist.
String normName(String s) {
  final out = StringBuffer();
  var space = true;
  for (var c in s.toLowerCase().replaceAll('&', ' and ').codeUnits) {
    c = _accents[c] ?? c;
    if ((c >= 48 && c <= 57) || (c >= 97 && c <= 122)) {
      out.writeCharCode(c);
      space = false;
    } else if (!space) {
      out.write(' ');
      space = true;
    }
  }
  return out.toString().trimRight();
}

final _pipeTag = RegExp(r'^\s*\|[^|]{1,10}\|\s*');
final _season = RegExp(r'\s+S\d{1,2}(\s*E\d{1,3})?$', caseSensitive: false);
final _trailYear = RegExp(r'^(.*\S)[\s\-:]+((?:19|20)\d\d)$');

/// A playlist title without its tags: "|NF| Dark (2017) S01" → "Dark", 2017.
CleanTitle streamTitle(String raw) {
  final c = cleanTitle(raw.replaceFirst(_pipeTag, ''));
  return CleanTitle(c.title.replaceFirst(_season, ''), c.year);
}

bool categoryIsFor(String categoryName, StreamingService s) {
  final n = ' ${normName(categoryName)} ';
  for (final w in s.words) {
    if (n.contains(' $w ')) return true;
  }
  return false;
}

class StreamingFound {
  const StreamingFound(this.movies, this.series, this.matched);
  final List<XItem> movies;
  final List<XItem> series;

  /// How many titles came from the website's list (the rest from the playlist's categories).
  final int matched;
}

class StreamingFinder {
  static Map<String, dynamic>? _lists;
  static DateTime _listsAt = DateTime(2000);
  static final Map<String, StreamingFound> _found = {};

  /// Forgets what was found (another playlist, or "Clear cache").
  static void clear() => _found.clear();

  /// The website's lists of every service's titles (refreshed there once a day; kept here 6 hours).
  static Future<Map<String, dynamic>> _siteLists() async {
    if (_lists != null && DateTime.now().difference(_listsAt) < const Duration(hours: 6)) return _lists!;
    final p = await SharedPreferences.getInstance();
    try {
      final data = await Backend.streamingLists();
      _lists = data;
      _listsAt = DateTime.now();
      await p.setString('streaming_lists', jsonEncode(data));
    } catch (e) {
      log('streaming lists: ${e.runtimeType}');
      if (_lists == null) {
        try {
          final saved = jsonDecode(p.getString('streaming_lists') ?? '{}');
          _lists = saved is Map<String, dynamic> ? saved : <String, dynamic>{};
        } catch (_) {
          _lists = <String, dynamic>{};
        }
      }
    }
    return _lists!;
  }

  static Future<StreamingFound> find(Source api, StreamingService s) async {
    final key = '${api.label}|${s.id}';
    final known = _found[key];
    if (known != null) return known;
    final movies = <XItem>[], series = <XItem>[];
    final seen = <String>{};
    var matched = 0;
    bool add(XItem it) {
      if (!Store.allowed(it) || !seen.add('${it.kind.name}:${it.id}')) return false;
      (it.kind == XKind.vod ? movies : series).add(it);
      return true;
    }

    // 1) The website's list of the service's titles, most popular first.
    final lists = await _siteLists();
    final mine = lists[s.id];
    if (mine is Map) {
      for (final kind in const [XKind.vod, XKind.series]) {
        final titles = mine[kind == XKind.vod ? 'movie' : 'tv'];
        if (titles is! List || titles.isEmpty) continue;
        List<XItem> all;
        try {
          all = await api.items(kind);
        } catch (_) {
          continue;
        }
        // Every title by its name; "The Witcher 2019" also as "the witcher" (with 2019 as its year).
        final byName = <String, List<(XItem, int)>>{};
        void put(String k, XItem it, int y) {
          if (k.isNotEmpty) byName.putIfAbsent(k, () => []).add((it, y));
        }
        for (final it in all) {
          final c = streamTitle(it.name);
          final y = int.tryParse(c.year) ?? 0;
          put(normName(c.title), it, y);
          final m = _trailYear.firstMatch(c.title);
          if (m != null) put(normName(m.group(1)!), it, y > 0 ? y : int.parse(m.group(2)!));
        }
        for (final t in titles) {
          if (t is! List || t.isEmpty) continue;
          final hits = byName[normName('${t[0]}')];
          if (hits == null) continue;
          final year = t.length > 1 ? int.tryParse('${t[1]}') ?? 0 : 0;
          for (final (it, y) in hits) {
            if (year > 0 && y > 0 && (y - year).abs() > 1) continue; // same name, another film
            if (add(it)) matched++;
          }
        }
      }
    }

    // 2) The playlist's own categories named after the service.
    for (final kind in const [XKind.vod, XKind.series]) {
      List<XCategory> cats;
      try {
        cats = await api.categories(kind);
      } catch (_) {
        continue;
      }
      for (final c in cats) {
        if (!categoryIsFor(c.name, s) || Store.isHidden(kind, c.id)) continue;
        if (Store.isLocked(kind, c.id) && !Store.parentalUnlocked) continue;
        try {
          var items = await api.items(kind, categoryId: c.id);
          // Some servers ignore the category filter and send everything.
          if (items.any((i) => i.categoryId == c.id) && items.any((i) => i.categoryId != c.id)) {
            items = items.where((i) => i.categoryId == c.id).toList();
          }
          items.forEach(add);
        } catch (_) {}
      }
    }
    log('streaming ${s.id}: movies=${movies.length} series=${series.length} matched=$matched');
    final found = StreamingFound(movies, series, matched);
    _found[key] = found;
    return found;
  }
}
