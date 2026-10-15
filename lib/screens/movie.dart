import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../download_ui.dart';
import '../downloads.dart';
import '../engine.dart';
import '../input_mode.dart';
import '../smooth.dart';
import '../warmup.dart';
import '../store.dart';
import '../theme.dart';
import '../tmdb.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'player.dart';

/// Details page of one movie: picture, rating, length, plot, then "Watch now",
/// cast and stills. The basics come from the IPTV server; cast photos, stills
/// and (when the server has none) the trailer come from TMDB.
class MovieScreen extends StatefulWidget {
  const MovieScreen({super.key, required this.api, required this.movie});

  final Source api;
  final XItem movie;

  @override
  State<MovieScreen> createState() => _MovieScreenState();
}

class _MovieScreenState extends State<MovieScreen> with WidgetsBindingObserver {
  static const _device = MethodChannel('b1g/device');

  XMovieInfo _info = const XMovieInfo();
  TmdbMovie? _tmdb;
  bool _loading = true;

  /// Still chosen in the "Media" row; shown as the big picture.
  String? _picked;

  String get _resumeKey => '${widget.movie.kind.name}:${widget.movie.id}';

  /// Key of this film in the downloads.
  String get _dlId => 'vod:${widget.movie.id}';
  final FocusNode _dlFocus = FocusNode(debugLabel: 'download');
  final FocusNode _dlFocus2 = FocusNode(debugLabel: 'download-2');

  // The film is opened (paused) while this page is read, so "Watch" starts at once.
  PlaybackEngine? _pre;
  Duration _preAt = Duration.zero;
  Timer? _preTimer;
  bool _started = false; // "Watch" was pressed: no preload any more

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App in the background: the preloaded film lets go of its connection.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) _dropPreload();
  }

  void _dropPreload() {
    _preTimer?.cancel();
    final e = _pre;
    _pre = null;
    e?.dispose().catchError((Object _) {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Downloads.i.addListener(_onDownloads);
    _load();
    _preTimer = Timer(const Duration(milliseconds: 900), _preload);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dropPreload();
    Downloads.i.removeListener(_onDownloads);
    _dlFocus.dispose();
    _dlFocus2.dispose();
    super.dispose();
  }

  Future<void> _preload() async {
    // Only on TVs / boxes strong enough (a second video decoder is too much for weak ones).
    if (!mounted || _started || kIsWeb || _pre != null || !Store.vodPreload || Store.enhanceCap <= 0) return;
    // A download holds the account's connection, and a downloaded film needs no head start.
    if (Downloads.i.busy || Downloads.i.localUrl(_dlId) != null) return;
    final url = widget.api.movieUrlFor(widget.movie);
    if (url.isEmpty) return;
    final saved = Store.resume(_resumeKey);
    final at = saved > 30 ? Duration(seconds: saved) : Duration.zero;
    PlaybackEngine? engine;
    try {
      final buf = Smooth.profileFor(url, live: false);
      // Only the Google player (ExoPlayer) preloads: it is light and holds the film paused
      // safely. MPV only gets the server ready.
      if (ExoEngine.available && Store.engine == 'exo' && !Store.exoNoSound.contains(url)) {
        engine = await ExoEngine.create(live: false, startMs: buf.startMs, rebufMs: buf.rebufMs);
      }
    } catch (_) {
      engine = null;
    }
    if (engine == null || !engine.canPreload) {
      engine?.dispose().catchError((Object _) {});
      if (!_started) Warmup.film(url);
      return;
    }
    // "Watch" pressed (or the page left) while the engine was being made: not needed any more.
    if (!mounted || _started || ModalRoute.of(context)?.isCurrent == false) {
      engine.dispose().catchError((Object _) {});
      return;
    }
    _pre = engine;
    _preAt = at;
    log('film preload engine=${engine.name} at=${at.inSeconds}s');
    await engine.preload(url, at).catchError((Object _) {});
  }

  Future<void> _load() async {
    try {
      final info = await widget.api.movieInfo(widget.movie);
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (_) {
      // The page still works with the name and the poster from the list.
      if (mounted) setState(() => _loading = false);
    }
    log('screen=movie details=${_info.plot.isNotEmpty} cast=${_info.cast.isNotEmpty} trailer=${_info.trailer.isNotEmpty}');
    if (!Tmdb.enabled) return;
    final extra = await Tmdb.movie(title: widget.movie.name, tmdbId: _info.tmdbId, year: _info.year);
    if (!mounted || extra == null) return;
    setState(() => _tmdb = extra);
    log('tmdb cast=${extra.cast.length} stills=${extra.stills.length} trailer=${extra.trailer.isNotEmpty}');
  }

  String get _trailerId => _info.trailer.isNotEmpty ? _info.trailer : (_tmdb?.trailer ?? '');

  Future<void> _watch({bool fromStart = false}) async {
    if (fromStart) Store.setResume(_resumeKey, 0);
    final movie = widget.movie;
    final year = _info.year.isNotEmpty ? _info.year : (_tmdb?.year ?? '');
    final genre = _info.genre.isNotEmpty ? _info.genre : (_tmdb?.genre ?? '');
    final entries = [
      PlayEntry(
        title: movie.name,
        subtitle: [year, genre].where((s) => s.isNotEmpty).join('  ·  '),
        // Downloaded: plays from the TV (no internet needed).
        urls: [Downloads.i.localUrl(_dlId) ?? widget.api.movieUrlFor(movie)],
        resumeKey: _resumeKey,
        logo: _info.cover.isNotEmpty ? _info.cover : movie.icon,
        item: movie,
      ),
    ];
    _preTimer?.cancel();
    _started = true;
    // The preloaded film is handed to the player (no new connection, no waiting).
    var pre = _pre;
    _pre = null;
    if (pre != null && Downloads.i.localUrl(_dlId) != null) {
      pre.dispose().catchError((Object _) {});
      pre = null;
    }
    if (pre != null && fromStart && _preAt > Duration.zero) await pre.seek(Duration.zero).catchError((Object _) {});
    if (!mounted) {
      pre?.dispose().catchError((Object _) {});
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(api: widget.api, entries: entries, index: 0, live: false, adopt: pre)));
    _started = false; // back on the page: a later "Watch" opens normally
    if (mounted) setState(() {});
  }

  void _toggleFavourite() {
    final added = Store.toggleFavourite(widget.movie);
    log('favourite ${added ? 'added' : 'removed'}');
    setState(() {});
  }

  Future<void> _trailer() async {
    bool opened = false;
    try {
      opened = await _device.invokeMethod<bool>('openUrl', 'https://www.youtube.com/watch?v=$_trailerId') ?? false;
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          width: 420,
          content: Text('No app on this device can open the trailer.', textAlign: TextAlign.center),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final info = _info;
    final tmdb = _tmdb;
    String pick(String a, String? b) => a.isNotEmpty ? a : (b ?? '');

    final plot = pick(info.plot, tmdb?.plot);
    final genre = pick(info.genre, tmdb?.genre);
    final year = pick(info.year, tmdb?.year);
    final duration = pick(info.duration, tmdb?.duration);
    var backdrop = pick(info.backdrop, tmdb?.backdrop);
    if (backdrop.isEmpty) backdrop = pick(info.cover, movie.icon);
    backdrop = _picked ?? backdrop;
    var rating = info.rating > 0 ? info.rating : (double.tryParse(movie.rating) ?? 0);
    if (rating <= 0) rating = tmdb?.rating ?? 0;

    final people = tmdb?.cast ?? const <TmdbPerson>[];
    final names = info.cast.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).take(8).toList();
    final stills = tmdb?.stills ?? const <String>[];
    final resume = Store.resume(_resumeKey);
    final favourite = Store.isFavourite(movie);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Picture on the right, fading into the page on the left and at the bottom.
          Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: size.width * 0.62,
              height: size.height,
              child: NetImage(backdrop, fit: BoxFit.cover, cacheWidth: 900, fallback: Icons.movie_rounded),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: [0.0, 0.38, 0.72, 1.0],
                colors: [C.bg, C.bg, Color(0xB30A0C10), Color(0x330A0C10)],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.5, 0.92],
                colors: [Colors.transparent, C.bg],
              ),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 30, 0, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 44),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: size.width * 0.56),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!InputMode.remote)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: ExcludeFocus(
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_rounded, color: C.text),
                                onPressed: () => Navigator.of(context).maybePop(),
                              ),
                            ),
                          ),
                        Text(
                          movie.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 32, height: 1.15, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 14,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (rating > 0) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 1; i <= 5; i++)
                                    Icon(
                                      rating / 2 >= i - 0.25
                                          ? Icons.star_rounded
                                          : (rating / 2 >= i - 0.75
                                              ? Icons.star_half_rounded
                                              : Icons.star_border_rounded),
                                      color: C.accent,
                                      size: 19,
                                    ),
                                ],
                              ),
                              _meta('${rating.toStringAsFixed(rating == rating.roundToDouble() ? 0 : 1)}/10'),
                            ],
                            if (duration.isNotEmpty) _meta(duration),
                            if (year.isNotEmpty) _meta(year),
                            if (info.country.isNotEmpty) _meta(info.country),
                          ],
                        ),
                        if (genre.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(genre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15, color: C.accent, fontWeight: FontWeight.w600)),
                          ),
                        const SizedBox(height: 10),
                        Text(
                          plot.isNotEmpty
                              ? plot
                              : (_loading ? 'Loading details…' : 'There is no description for this title.'),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            height: 1.4,
                            color: plot.isNotEmpty ? const Color(0xFFD5DAE3) : C.dim,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _action(
                              icon: Icons.play_arrow_rounded,
                              label: resume > 30 ? 'Resume from ${formatTime(Duration(seconds: resume))}' : 'Watch now',
                              primary: true,
                              autofocus: true,
                              onTap: _watch,
                            ),
                            if (resume > 30)
                              _action(
                                icon: Icons.replay_rounded,
                                label: 'From the start',
                                onTap: () => _watch(fromStart: true),
                              ),
                            _action(
                              icon: favourite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              label: favourite ? 'In Favourites' : 'Favourite',
                              highlight: favourite,
                              onTap: _toggleFavourite,
                            ),
                            if (_trailerId.isNotEmpty)
                              _action(icon: Icons.smart_display_rounded, label: 'Trailer', onTap: _trailer),
                            if (Downloads.available) ..._downloadButtons(),
                          ],
                        ),
                        if (Downloads.available && Downloads.i.byId(_dlId) != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: DownloadProgress(id: _dlId),
                          ),
                        if (info.director.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text('Director:  ${info.director}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5, color: C.dim)),
                          ),
                      ],
                    ),
                  ),
                ),
                if (people.isNotEmpty) ...[
                  _heading('Cast'),
                  SizedBox(
                    height: 186,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 42),
                      itemCount: people.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => _PersonCard(person: people[i]),
                    ),
                  ),
                ] else if (names.isNotEmpty) ...[
                  _heading('Cast'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 44),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final name in names)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xB31A1E28),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_rounded, size: 15, color: C.dim),
                                const SizedBox(width: 6),
                                Text(name, style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (stills.length > 1) ...[
                  _heading('Media'),
                  SizedBox(
                    height: 104,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 42),
                      itemCount: stills.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => TvFocus(
                        selected: _picked == stills[i],
                        onTap: () => setState(() => _picked = stills[i]),
                        onFocus: () {
                          if (_picked != stills[i]) setState(() => _picked = stills[i]);
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7.5),
                          child: SizedBox(
                            width: 172,
                            child: NetImage(stills[i], fit: BoxFit.cover, cacheWidth: 360, fallback: Icons.image_rounded),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (tmdb != null)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(44, 18, 44, 0),
                    child: Text(
                      'Cast photos and stills: TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF596070)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(44, 20, 44, 8),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _meta(String text) =>
      Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFFE6E9EF)));

  /// Download / Pause / Resume / Cancel / Delete — the first button keeps one focus node, so
  /// the remote stays on it when it changes (Download → Pause).
  List<Widget> _downloadButtons() {
    final d = Downloads.i.byId(_dlId);
    if (d == null) {
      return [_action(icon: Icons.download_rounded, label: 'Download', node: _dlFocus, onTap: _download)];
    }
    switch (d.state) {
      case DlState.done:
        return [
          _action(icon: Icons.download_done_rounded, label: 'Downloaded', highlight: true, node: _dlFocus, onTap: _watch),
          _action(icon: Icons.delete_outline_rounded, label: 'Delete download', node: _dlFocus2, onTap: () => _dlDo(() => Downloads.i.remove(_dlId))),
        ];
      case DlState.running:
      case DlState.queued:
      case DlState.waiting:
        return [
          _action(icon: Icons.pause_rounded, label: 'Pause', node: _dlFocus, onTap: () => _dlDo(() => Downloads.i.pause(_dlId))),
          _action(icon: Icons.close_rounded, label: 'Cancel', node: _dlFocus2, onTap: () => _dlDo(() => Downloads.i.remove(_dlId))),
        ];
      case DlState.paused:
      case DlState.failed:
        return [
          _action(
              icon: Icons.play_for_work_rounded,
              label: d.state == DlState.failed ? 'Try again' : 'Resume download',
              node: _dlFocus,
              onTap: () => _dlDo(() => Downloads.i.resume(_dlId))),
          _action(icon: Icons.close_rounded, label: 'Cancel', node: _dlFocus2, onTap: () => _dlDo(() => Downloads.i.remove(_dlId))),
        ];
    }
  }

  DlState? _dlSeen;

  /// The buttons change only when the download's state changes (not 4 times a second).
  void _onDownloads() {
    final st = Downloads.i.byId(_dlId)?.state;
    if (st == _dlSeen || !mounted) return;
    _dlSeen = st;
    setState(() {});
  }

  void _dlDo(VoidCallback f) {
    f();
    setState(() {});
    // The button under the remote may have gone (Cancel / Delete): back to the first one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_dlFocus.hasFocus && !_dlFocus2.hasFocus && FocusManager.instance.primaryFocus?.context == null) {
        _dlFocus.requestFocus();
      }
    });
  }

  Future<void> _download() async {
    final movie = widget.movie;
    final url = widget.api.movieUrlFor(movie);
    if (url.isEmpty) return;
    // The head start held a connection: let it go for the download.
    _dropPreload();
    final year = _info.year.isNotEmpty ? _info.year : (_tmdb?.year ?? '');
    await Downloads.i.add(
      id: _dlId,
      title: movie.name,
      url: url,
      subtitle: year,
      cover: _info.cover.isNotEmpty ? _info.cover : movie.icon,
    );
    log('download start ${movie.name}');
    if (mounted) setState(() {});
  }

  Widget _action({
    FocusNode? node,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
    bool autofocus = false,
    bool highlight = false,
  }) {
    final Color foreground = primary ? C.onAccent : (highlight ? C.accent : C.text);
    return TvFocus(
      focusNode: node,
      autofocus: autofocus,
      radius: 24,
      color: primary ? C.accent : const Color(0xCC1A1E28),
      focusBorder: primary ? Colors.white : C.accent,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: foreground),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: foreground)),
          ],
        ),
      ),
    );
  }
}

/// Photo, name and role of one cast member.
class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person});
  final TmdbPerson person;

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      onTap: () {},
      color: const Color(0x991A1E28),
      child: SizedBox(
        width: 104,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7.5)),
              child: Container(
                height: 128,
                width: double.infinity,
                color: const Color(0xFF2A303C),
                child: NetImage(person.photo, fit: BoxFit.cover, cacheWidth: 220, fallback: Icons.person_rounded),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 6, 7, 0),
              child: Text(person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 1, 7, 0),
              child: Text(person.character,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: C.dim)),
            ),
          ],
        ),
      ),
    );
  }
}
