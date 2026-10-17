import 'package:flutter/material.dart';

import 'downloads.dart';
import 'screens/player.dart';
import 'store.dart';
import 'theme.dart';
import 'xtream.dart';

/// A half-watched film or episode for the "Continue Watching" row on the home screen.
class CwEntry {
  const CwEntry({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.image,
    required this.position,
    required this.duration,
    required this.at,
    required this.item,
    this.episode,
    this.upNext = false,
  });

  /// The resume key: "vod:<id>" for a film, "ep:<id>" for an episode.
  final String key;

  /// The film's or the series' name.
  final String title;

  /// "S1 E3  ·  Episode title" for an episode; year and genre for a film.
  final String subtitle;
  final String image;

  /// Seconds watched and the length (0 when not known yet).
  final int position;
  final int duration;

  /// When it was last watched (ms since 1970).
  final int at;

  /// The film, or the series of the episode.
  final XItem item;
  final XEpisode? episode;

  /// The next episode after a finished one (not started yet).
  final bool upNext;

  bool get isEpisode => episode != null;

  double get progress => duration > 0 ? (position / duration).clamp(0.0, 1.0).toDouble() : 0.0;

  /// "23 min left", "Next episode", or how far it got.
  String get note {
    if (upNext) return 'Next episode';
    if (duration > 0) {
      final left = ((duration - position) / 60).ceil();
      if (left > 0) return left >= 60 ? '${left ~/ 60} h ${left % 60} min left' : '$left min left';
    }
    final m = position ~/ 60;
    return m >= 60 ? 'At ${m ~/ 60} h ${m % 60} min' : 'At $m min';
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        't': title,
        's': subtitle,
        'img': image,
        'pos': position,
        'dur': duration,
        'at': at,
        'item': item.toJson(),
        if (episode != null) 'ep': episodeToJson(episode!),
        if (upNext) 'next': 1,
      };

  static CwEntry? fromJson(Map<String, dynamic> j) {
    final item = XItem.fromJson(j['item']);
    final key = (j['key'] ?? '').toString();
    if (item == null || key.isEmpty) return null;
    int n(Object? v) => int.tryParse('${v ?? 0}') ?? 0;
    return CwEntry(
      key: key,
      title: (j['t'] ?? item.name).toString(),
      subtitle: (j['s'] ?? '').toString(),
      image: (j['img'] ?? item.icon).toString(),
      position: n(j['pos']),
      duration: n(j['dur']),
      at: n(j['at']),
      item: item,
      episode: episodeFromJson(j['ep']),
      upNext: '${j['next'] ?? ''}' == '1',
    );
  }
}

Map<String, dynamic> episodeToJson(XEpisode e) =>
    {'id': e.id, 't': e.title, 'e': e.ext, 's': e.season, 'n': e.number, if (e.duration.isNotEmpty) 'd': e.duration};

XEpisode? episodeFromJson(Object? j) {
  if (j is! Map) return null;
  final id = (j['id'] ?? '').toString();
  if (id.isEmpty) return null;
  return XEpisode(
    id: id,
    title: (j['t'] ?? '').toString(),
    ext: (j['e'] ?? '').toString(),
    season: int.tryParse('${j['s'] ?? 0}') ?? 0,
    number: int.tryParse('${j['n'] ?? 0}') ?? 0,
    duration: (j['d'] ?? '').toString(),
  );
}

/// "S1 E3  ·  Episode title"
String episodeLabel(XEpisode e) => 'S${e.season} E${e.number}${e.title.isEmpty ? '' : '  ·  ${e.title}'}';

/// The Continue Watching list of the profile in use (newest first). The player keeps it up to
/// date; a finished film leaves it, a finished episode makes room for the next one.
class ContinueWatching {
  ContinueWatching._();

  static const _max = 20;

  /// Changes for the home screen.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static List<CwEntry> get all {
    final out = <CwEntry>[];
    for (final j in Store.continueRaw()) {
      final e = CwEntry.fromJson(j);
      // A category hidden or locked since (or not for children in a Kids profile) is left out.
      if (e != null && Store.allowed(e.item)) out.add(e);
    }
    return out;
  }

  static void _save(List<Map<String, dynamic>> list) {
    while (list.length > _max) {
      list.removeLast();
    }
    Store.setContinueRaw(list);
    changes.value++;
  }

  static String? _seriesOf(Map<String, dynamic> j) {
    if (j['ep'] == null) return null;
    final item = j['item'];
    return item is Map ? '${item['id'] ?? ''}' : null;
  }

  /// Puts [e] at the front. A series has one card: its latest episode.
  static void _put(CwEntry e) {
    final seriesId = e.isEpisode ? e.item.id : null;
    final list = [
      for (final j in Store.continueRaw())
        if (j['key'] != e.key && (seriesId == null || _seriesOf(j) != seriesId)) j,
    ];
    list.insert(0, e.toJson());
    _save(list);
  }

  static void remove(String key) {
    final raw = Store.continueRaw();
    if (!raw.any((j) => j['key'] == key)) return;
    _save([for (final j in raw) if (j['key'] != key) j]);
  }

  /// The player reports where a film or episode got to (every few seconds and when it closes).
  /// [next] is the episode that follows in the player's list, if any.
  static void note(PlayEntry entry, int position, int duration, {PlayEntry? next}) {
    final key = entry.resumeKey;
    if (key == null) return;
    final series = entry.series;
    final episode = entry.episode;
    final XItem item;
    final String title;
    final String subtitle;
    XEpisode? cardEpisode;
    if (series != null && episode != null) {
      item = series;
      title = series.name;
      subtitle = episodeLabel(episode);
      cardEpisode = episode;
    } else {
      final film = entry.item;
      if (film == null || film.kind != XKind.vod) return;
      item = film;
      title = film.name;
      subtitle = entry.subtitle;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (duration > 60 && position > duration * 0.95) {
      finished(entry, next: next);
      return;
    }
    if (position < 30) {
      // Only a few seconds in: not a new card, but a card that is there keeps the right place.
      final raw = Store.continueRaw();
      final i = raw.indexWhere((j) => j['key'] == key);
      if (i < 0) return;
      raw[i] = {...raw[i], 'pos': position, if (duration > 0) 'dur': duration};
      _save(raw);
      return;
    }
    _put(CwEntry(
      key: key,
      title: title,
      subtitle: subtitle,
      image: entry.logo.isNotEmpty ? entry.logo : item.icon,
      position: position,
      duration: duration,
      at: now,
      item: item,
      episode: cardEpisode,
    ));
  }

  /// A film or episode was watched to the end.
  static void finished(PlayEntry entry, {PlayEntry? next}) {
    final key = entry.resumeKey;
    if (key == null) return;
    remove(key);
    final series = entry.series;
    final nextEpisode = next?.episode;
    if (series == null || nextEpisode == null || next?.series?.id != series.id) return;
    _put(CwEntry(
      key: next!.resumeKey ?? 'ep:${nextEpisode.id}',
      title: series.name,
      subtitle: episodeLabel(nextEpisode),
      image: entry.logo.isNotEmpty ? entry.logo : series.icon,
      position: 0,
      duration: 0,
      at: DateTime.now().millisecondsSinceEpoch,
      item: series,
      episode: nextEpisode,
      upNext: true,
    ));
  }
}

/// One episode as the player gets it (with what Continue Watching needs).
PlayEntry episodeEntry(Source api, XItem series, XEpisode e, {String logo = ''}) => PlayEntry(
      title: series.name,
      subtitle: episodeLabel(e),
      urls: [api.episodeUrlFor(e)],
      resumeKey: 'ep:${e.id}',
      logo: logo.isNotEmpty ? logo : series.icon,
      episode: e,
      series: series,
    );

/// Plays a Continue Watching card where it stopped (or from the start). An episode plays with
/// the rest of its season after it, as from the series page.
Future<void> playContinue(BuildContext context, Source api, CwEntry e, {bool fromStart = false}) async {
  if (fromStart) Store.setResume(e.key, 0);
  log('continue watching ${e.isEpisode ? 'episode' : 'film'} start=${fromStart ? 0 : e.position}');
  var entries = <PlayEntry>[];
  var index = 0;
  final episode = e.episode;
  if (episode != null) {
    entries = [episodeEntry(api, e.item, episode, logo: e.image)];
    try {
      final info = await api.seriesInfo(e.item.id).timeout(const Duration(seconds: 8));
      for (final season in info.seasons.values) {
        final i = season.indexWhere((x) => x.id == episode.id);
        if (i >= 0) {
          entries = [for (final x in season) episodeEntry(api, e.item, x, logo: e.image)];
          index = i;
          break;
        }
      }
    } catch (err) {
      log('continue watching: series info ${err.runtimeType}');
    }
  } else {
    final film = e.item;
    entries = [
      PlayEntry(
        title: film.name,
        subtitle: e.subtitle,
        // Downloaded: plays from the TV (no internet needed).
        urls: [Downloads.i.localUrl('vod:${film.id}') ?? api.movieUrlFor(film)],
        resumeKey: e.key,
        logo: e.image,
        item: film,
      ),
    ];
  }
  if (!context.mounted) return;
  await Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => PlayerScreen(api: api, entries: entries, index: index, live: false)));
}
