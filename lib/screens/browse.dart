import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../backend.dart';
import '../downloads.dart';
import '../engine.dart';
import '../i18n.dart';
import '../parental.dart';
import '../input_mode.dart';
import '../start_poster.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'guide.dart';
import 'movie.dart';
import 'player.dart';
import 'series.dart';

const _favId = '*fav';
const _searchId = '*search';
const _allId = '*all';
const _recentId = '*recent';

String kindTitle(XKind kind) {
  switch (kind) {
    case XKind.live:
      return t('Live TV');
    case XKind.vod:
      return t('Movies');
    case XKind.series:
      return t('Series');
  }
}

/// Name of the "everything" entry at the top of the category list.
String allTitle(XKind kind) {
  switch (kind) {
    case XKind.live:
      return t('All Live Channels');
    case XKind.vod:
      return t('All Movies');
    case XKind.series:
      return t('All Series');
  }
}

/// What one entry of this kind is called, for the counts ("312 channels").
String countLabel(XKind kind, int n) {
  switch (kind) {
    case XKind.live:
      return n == 1 ? 'channel' : 'channels';
    case XKind.vod:
      return n == 1 ? 'movie' : 'movies';
    case XKind.series:
      return n == 1 ? 'series' : 'series';
  }
}

/// Categories on the left, channels / titles on the right.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.api, required this.kind});

  final Source api;
  final XKind kind;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> with WidgetsBindingObserver {
  List<XCategory>? _cats;
  String? _catsError;
  String _selected = '';
  // The category the screen opens on (the server's first one); null = "All".
  String? _firstId;
  String _selectedName = '';
  List<XItem>? _items;
  String? _itemsError;
  final Map<String, List<XItem>> _cache = {};
  List<XItem>? _all;
  String _query = '';
  int _request = 0;
  Timer? _focusTimer;

  // Moving a category: hold OK (or the finger) on it, then Up / Down (or drag) and OK to place it.
  String? _moving;
  int _dragFrom = 0;

  // Live: the small preview on the right. OK on a channel starts it here,
  // OK on the same channel again goes full screen (like the big IPTV apps).
  PlaybackEngine? _pv;
  XItem? _pvItem;
  bool _pvBuffering = false;
  bool _pvFallbackTried = false;
  final List<StreamSubscription> _pvSubs = [];
  int _pvRequest = 0;

  // Live: the guide box under the preview follows the channel the remote is on.
  XItem? _focusItem;
  int _focusNumber = 0;
  List<XEpg> _focusEpg = const [];
  bool _focusEpgLoading = false;
  final Map<String, List<XEpg>> _epgCache = {};
  Timer? _epgTimer;
  int _epgRequest = 0;
  Timer? _clock;
  // The guide box scrolls (remote: move onto it, then Up / Down; touch: drag).
  final ScrollController _guideScroll = ScrollController();
  final FocusNode _guideFocus = FocusNode(debugLabel: 'guide-box');

  bool get _live => widget.kind == XKind.live;

  // Full screen is being opened: no new preview meanwhile (two streams at once).
  bool _goingFull = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Home button / app in the background: the preview lets go of the stream and the decoder.
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.hidden) && _pv != null) {
      _stopPreview();
    }
  }

  @override
  void initState() {
    super.initState();
    // Downloads hold back while the preview plays (one connection per account).
    Downloads.watchers.add(_pvActive);
    WidgetsBinding.instance.addObserver(this);
    _guideFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _loadCategories();
    if (_live) {
      // Keeps "now" and the progress bar of the guide box current.
      _clock = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    Downloads.watchers.remove(_pvActive);
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _focusTimer?.cancel();
    _epgTimer?.cancel();
    _clock?.cancel();
    _guideScroll.dispose();
    _guideFocus.dispose();
    _stopPreview();
    super.dispose();
  }

  bool _pvActive() => !_disposed && _pv != null;

  Future<void> _stopPreview() async {
    _pvRequest++;
    for (final s in _pvSubs) {
      s.cancel();
    }
    _pvSubs.clear();
    final engine = _pv;
    _pv = null;
    _pvItem = null;
    _pvBuffering = false;
    if (mounted && !_disposed) setState(() {});
    if (engine != null) await engine.dispose().catchError((Object _) {});
  }

  /// Plays a channel in the preview box, on the same engine as full screen
  /// (ExoPlayer on Android, MPV elsewhere or when the customer chose it).
  Future<void> _preview(XItem item, List<String> streamUrls) async {
    // In a browser the preview needs the HLS address through the website relay, like full screen.
    final urls = Backend.playable(streamUrls);
    if (urls.isEmpty || _goingFull) return;
    await _stopPreview();
    if (!mounted || _goingFull) return;
    final request = ++_pvRequest;
    PlaybackEngine engine;
    try {
      engine = ExoEngine.available && Store.liveEngine == 'exo'
          ? await ExoEngine.create(live: true)
          : MpvEngine(live: true, direct: false);
    } catch (_) {
      engine = MpvEngine(live: true, direct: false);
    }
    if (!mounted || request != _pvRequest || _goingFull || ModalRoute.of(context)?.isCurrent == false) {
      engine.dispose().catchError((Object _) {});
      return;
    }
    setState(() {
      _pv = engine;
      _pvItem = item;
      _pvBuffering = true;
      _pvFallbackTried = false;
    });
    _pvSubs.add(engine.buffering.listen((b) {
      if (mounted && request == _pvRequest && b != _pvBuffering) setState(() => _pvBuffering = b);
    }));
    _pvSubs.add(engine.position.listen((_) {
      if (mounted && request == _pvRequest && _pvBuffering) setState(() => _pvBuffering = false);
    }));
    _pvSubs.add(engine.messages.listen((m) {
      // Live channels have a second stream format; the preview tries it once.
      if (!m.error || request != _pvRequest || _pvFallbackTried || urls.length < 2) return;
      _pvFallbackTried = true;
      engine.open(urls[1], Duration.zero).catchError((Object _) {});
    }));
    log('preview open engine=${engine.name}');
    await engine.open(urls.first, Duration.zero).catchError((Object _) {});
  }

  /// The remote moved onto a channel: show its guide under the preview once it settles there.
  void _focusChannel(XItem item, int number) {
    if (_focusItem?.id == item.id) return;
    if (_guideScroll.hasClients) _guideScroll.jumpTo(0);
    final id = item.url.isEmpty ? item.id : item.epgId;
    final cached = _epgCache[id];
    setState(() {
      _focusItem = item;
      _focusNumber = number;
      _focusEpg = cached ?? const [];
      _focusEpgLoading = cached == null && id.isNotEmpty;
    });
    _epgTimer?.cancel();
    if (cached != null || id.isEmpty) return;
    final request = ++_epgRequest;
    _epgTimer = Timer(const Duration(milliseconds: 350), () async {
      List<XEpg> list = const [];
      try {
        list = await widget.api.fullEpg(id);
      } catch (_) {}
      // Keep only the last few channels' guides (a full guide is big).
      while (_epgCache.length >= 30) {
        _epgCache.remove(_epgCache.keys.first);
      }
      _epgCache[id] = list;
      if (!mounted || request != _epgRequest) return;
      setState(() {
        _focusEpg = list;
        _focusEpgLoading = false;
      });
    });
  }

  List<PlayEntry> _entriesFor(List<XItem> items) {
    final format = Store.liveFormat;
    return [
      for (final i in items)
        PlayEntry(
          title: i.name,
          urls: widget.api.liveUrlsFor(i, format),
          // Xtream channels use their stream id; playlist channels use the
          // tvg-id from the M3U (shown when an XMLTV guide is set).
          epgId: i.url.isEmpty ? i.id : (i.epgId.isEmpty ? null : i.epgId),
          logo: i.icon,
          item: i,
        ),
    ];
  }

  Future<void> _playFull(List<XItem> items, int index) async {
    if (_goingFull) return;
    _goingFull = true;
    try {
      await _playFullNow(items, index);
    } finally {
      _goingFull = false;
    }
  }

  Future<void> _playFullNow(List<XItem> items, int index) async {
    Store.addRecent(items[index]);
    // The channel is already playing in the preview: full screen takes over that same stream
    // (no reload, it simply carries on). Otherwise the preview stops and full screen opens it.
    final engine = _pv;
    PlaybackEngine? handOver;
    if (engine != null && _pvItem?.id == items[index].id && !_pvBuffering && !kIsWeb) {
      _pvRequest++;
      for (final s in _pvSubs) {
        s.cancel();
      }
      _pvSubs.clear();
      _pv = null;
      _pvItem = null;
      handOver = engine;
      if (mounted) setState(() {});
    } else {
      await _stopPreview();
    }
    if (!mounted) {
      handOver?.dispose().catchError((Object _) {});
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
            api: widget.api,
            entries: _entriesFor(items),
            index: index,
            live: true,
            adopt: handOver,
            handBack: (engine, i) => _takeBack(engine, i >= 0 && i < items.length ? items[i] : items[index]))));
  }

  /// Back from full screen: the channel that was playing there goes on in the preview.
  void _takeBack(PlaybackEngine engine, XItem item) {
    if (!mounted || _disposed) {
      engine.dispose().catchError((Object _) {});
      return;
    }
    final old = _pv;
    _pvRequest++;
    for (final s in _pvSubs) {
      s.cancel();
    }
    _pvSubs.clear();
    if (old != null && !identical(old, engine)) old.dispose().catchError((Object _) {});
    final request = _pvRequest;
    setState(() {
      _pv = engine;
      _pvItem = item;
      _pvBuffering = false;
      _pvFallbackTried = true;
    });
    _pvSubs.add(engine.buffering.listen((b) {
      if (mounted && request == _pvRequest && b != _pvBuffering) setState(() => _pvBuffering = b);
    }));
    _pvSubs.add(engine.position.listen((_) {
      if (mounted && request == _pvRequest && _pvBuffering) setState(() => _pvBuffering = false);
    }));
    log('preview carries on the full-screen channel (engine=${engine.name})');
  }

  /// TV Guide for the channels of this category, starting on the selected one.
  Future<void> _openGuide() async {
    final items = _items;
    if (items == null || items.isEmpty) return;
    final current = _focusItem ?? _pvItem;
    var index = current == null ? 0 : items.indexWhere((i) => i.id == current.id);
    if (index < 0) index = 0;
    await _stopPreview();
    if (!mounted) return;
    final entries = _entriesFor(items);
    final picked = await Navigator.of(context).push<GuideResult>(
        MaterialPageRoute(builder: (_) => GuideScreen(api: widget.api, entries: entries, index: index)));
    if (!mounted || picked == null) return;
    final channel = picked.channel;
    final archive = picked.archive;
    if (channel != null) {
      await _playFull(items, channel);
    } else if (archive != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(api: widget.api, entries: [archive], index: 0, live: false)));
    }
  }

  Future<void> _loadCategories() async {
    setState(() {
      _cats = null;
      _catsError = null;
    });
    try {
      final cats = Store.sortCategories(widget.kind, await widget.api.categories(widget.kind));
      if (!mounted) return;
      _firstId = cats
          .where((c) => !Store.isHidden(widget.kind, c.id) && !Store.isLocked(widget.kind, c.id))
          .firstOrNull
          ?.id;
      setState(() => _cats = cats);
      log('browse ${widget.kind.name} categories=${cats.length}');
      // Open the server's first category, not "All": the full list is heavy and loads only when
      // the user picks "All" themselves.
      final first = cats
          .where((c) => !Store.isHidden(widget.kind, c.id) && !Store.isLocked(widget.kind, c.id))
          .firstOrNull;
      if (first == null) {
        _select(_allId, allTitle(widget.kind));
      } else {
        _select(first.id, first.name);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _catsError = friendlyError(e));
    }
  }

  Future<List<XItem>> _loadAll() async {
    final all = _all ??= await widget.api.items(widget.kind);
    // The "All ..." row shows the total once it is known.
    if (mounted) setState(() {});
    return all;
  }

  /// When the search box closed: the remote's OK / the keyboard's Search key can arrive once more
  /// on the list behind it (it used to open "All" and show everything instead of the results).
  DateTime _searchClosed = DateTime(2000);
  bool get _justSearched => DateTime.now().difference(_searchClosed) < const Duration(milliseconds: 900);

  Future<void> _select(String id, String name) async {
    if (_justSearched && id != _searchId) return;
    _focusTimer?.cancel();
    if (id == _selected && _items != null && id != _favId && id != _recentId) return;
    final request = ++_request;
    // A locked category opens only with the parental PIN.
    if (!id.startsWith('*') && Store.isLocked(widget.kind, id) && !Store.parentalUnlocked) {
      if (!await askParentalPin(context)) return;
      if (!mounted) return;
    }
    final cached = _cache[id];
    final ready = id == _favId
        ? List<XItem>.of(Store.favourites(widget.kind))
        : id == _recentId
            ? List<XItem>.of(Store.recents(widget.kind))
            : cached?.where(Store.allowed).toList();
    setState(() {
      _selected = id;
      _selectedName = name;
      _itemsError = null;
      _items = ready;
    });
    if (ready != null) {
      if (id == _favId) log('browse ${widget.kind.name} favourites=${ready.length}');
      if (id == _recentId) log('browse ${widget.kind.name} recent=${ready.length}');
      return;
    }
    try {
      List<XItem> items;
      if (id == _allId) {
        items = await _loadAll();
      } else {
        items = await widget.api.items(widget.kind, categoryId: id);
        // Some servers ignore the category filter and send everything.
        if (items.any((i) => i.categoryId == id) && items.any((i) => i.categoryId != id)) {
          items = items.where((i) => i.categoryId == id).toList();
        }
      }
      _cache[id] = items;
      if (!mounted || request != _request) return;
      setState(() => _items = items.where(Store.allowed).toList());
      log('browse ${widget.kind.name} items=${items.length}');
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() => _itemsError = friendlyError(e));
    }
  }

  /// Moving over a category shows its content after a short pause, so the
  /// list can be skimmed without pressing OK on every row.
  void _focusCategory(String id, String name) {
    _focusTimer?.cancel();
    if (id == _selected) return;
    // Locked categories open only on OK (with the PIN), never by moving over them.
    if (!id.startsWith('*') && Store.isLocked(widget.kind, id) && !Store.parentalUnlocked) return;
    _focusTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _select(id, name);
    });
  }

  Future<void> _search() async {
    if (_justSearched) return; // the same key press again: no second search box
    _focusTimer?.cancel();
    final q = await _askSearch(context, _query);
    _searchClosed = DateTime.now();
    if (q == null || q.isEmpty || !mounted) return;
    final request = ++_request;
    setState(() {
      _query = q;
      _selected = _searchId;
      _selectedName = 'Search: $q';
      _items = null;
      _itemsError = null;
    });
    try {
      final all = await _loadAll();
      if (!mounted || request != _request) return;
      final words = _norm(q).split(' ').where((w) => w.isNotEmpty).toList();
      final found = all
          .where((i) => Store.allowed(i) && _matches(_norm(i.name), words))
          .take(400)
          .toList();
      setState(() => _items = found);
      log('browse ${widget.kind.name} search=${found.length}');
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() => _itemsError = friendlyError(e));
    }
  }

  /// Lower case, letters and digits only (so "Spider-Man" is found with "spider man").
  static String _norm(String s) {
    const from = 'àáâãäåèéêëìíîïòóôõöùúûüçñ';
    const to = 'aaaaaaeeeeiiiiooooouuuucn';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final k = from.indexOf(ch);
      final c = k >= 0 ? to[k] : ch;
      b.write(RegExp(r'[a-z0-9\u0600-\u06ff\u0900-\u097f]').hasMatch(c) ? c : ' ');
    }
    return b.toString().replaceAll(RegExp(r' +'), ' ').trim();
  }

  /// Every typed word is somewhere in the name.
  static bool _matches(String name, List<String> words) {
    if (words.isEmpty) return false;
    final joined = name.replaceAll(' ', '');
    for (final w in words) {
      if (!name.contains(w) && !joined.contains(w)) return false;
    }
    return true;
  }

  void _retryItems() {
    final id = _selected;
    final name = _selectedName;
    if (id == _searchId) {
      _search();
      return;
    }
    _selected = '';
    _select(id, name);
  }

  void _toggleFavourite(XItem item) {
    final added = Store.toggleFavourite(item);
    log('favourite ${added ? 'added' : 'removed'}');
    setState(() {
      if (_selected == _favId) _items = List<XItem>.of(Store.favourites(widget.kind));
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        width: 320,
        content: Text(added ? 'Added to Favourites' : 'Removed from Favourites', textAlign: TextAlign.center),
      ));
  }

  Future<void> _openItem(List<XItem> items, int index) async {
    final api = widget.api;
    final item = items[index];
    if (widget.kind == XKind.series && item.url.isEmpty) {
      Store.addRecent(item);
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => SeriesScreen(api: api, series: item)));
    } else if (_live) {
      // First OK on a channel: play it in the preview. OK on the same channel again: full screen.
      if (_pvItem?.id != item.id || _pv == null) {
        _focusChannel(item, index + 1);
        _preview(item, api.liveUrlsFor(item, Store.liveFormat));
        return;
      }
      await _playFull(items, index);
    } else {
      Store.addRecent(item);
      // Movies open on their details page first; "Watch now" there starts the player.
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MovieScreen(api: api, movie: item)));
    }
    if (mounted) {
      setState(() {
        if (_selected == _recentId) _items = List<XItem>.of(Store.recents(widget.kind));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: _live ? 206 : 236,
            color: C.panel,
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 12),
                  // Shrinks a little when it needs more room than the panel has (the back arrow on a
                  // phone, in the narrower Live TV panel), instead of running into the channel list.
                  // When it fits, it keeps its size and height exactly as before.
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!InputMode.remote)
                            ExcludeFocus(
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.arrow_back_rounded, color: C.text),
                                onPressed: () => Navigator.of(context).maybePop(),
                              ),
                            ),
                          const Logo(size: 18),
                          const SizedBox(width: 10),
                          Text(kindTitle(widget.kind), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(child: _categories()),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (_items != null)
                          Text('${_items!.length} ${countLabel(widget.kind, _items!.length)}',
                              style: const TextStyle(color: C.dim, fontSize: 14)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _live
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 280, child: _content()),
                              const SizedBox(width: 14),
                              Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 14), child: _previewPane())),
                            ],
                          )
                        : _content(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Full screen for a channel (the one playing in the preview carries on without reload).
  void _fullScreenFor(XItem item) {
    final items = _items;
    if (items == null) return;
    final i = items.indexWhere((x) => x.id == item.id);
    if (i >= 0) _playFull(items, i);
  }

  /// Remote on the guide box: Up / Down scroll it; Up at the top goes back to the buttons.
  KeyEventResult _guideKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (!_guideScroll.hasClients) return KeyEventResult.ignored;
    final pos = _guideScroll.position;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (pos.pixels >= pos.maxScrollExtent) return KeyEventResult.handled;
      _guideScroll.animateTo(math.min(pos.maxScrollExtent, pos.pixels + 70),
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (pos.pixels <= 0) return KeyEventResult.ignored;
      _guideScroll.animateTo(math.max(0, pos.pixels - 70), duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Live: quick buttons on top, the preview picture, the channel's guide under it.
  Widget _previewPane() {
    final engine = _pv;
    final playing = _pvItem;
    final item = _focusItem ?? playing;
    final now = DateTime.now();
    final upcoming = _focusEpg.where((e) => e.end.isAfter(now)).take(10).toList();
    final current = upcoming.isNotEmpty && !upcoming.first.start.isAfter(now) ? upcoming.first : null;
    final later = current == null ? upcoming : upcoming.skip(1).toList();
    final double progress = current == null
        ? 0.0
        : (now.difference(current.start).inSeconds / math.max(1, current.end.difference(current.start).inSeconds))
            .clamp(0.0, 1.0)
            .toDouble();
    final fav = item != null && Store.isFavourite(item);

    return LayoutBuilder(builder: (context, box) {
      final videoH = math.min(box.maxWidth * 9 / 16, (box.maxHeight - 52) * 0.6);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- buttons, above the picture
          if (item != null) ...[
            Row(
              children: [
                _paneButton(Icons.fullscreen_rounded, t('Full screen'), () => _fullScreenFor(item)),
                const SizedBox(width: 8),
                _paneButton(Icons.calendar_view_day_rounded, t('TV Guide'), _openGuide),
                const SizedBox(width: 8),
                _paneButton(fav ? Icons.star_rounded : Icons.star_border_rounded, t('Favourite'),
                    () => _toggleFavourite(item)),
              ],
            ),
            const SizedBox(height: 10),
          ],
          // ---- picture (touch: tap it for full screen)
          Center(
            child: GestureDetector(
              onTap: engine != null && playing != null ? () => _fullScreenFor(playing) : null,
              child: Container(
              width: videoH * 16 / 9,
              height: videoH,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x22FFFFFF)),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (engine != null)
                    IgnorePointer(child: ExcludeFocus(child: engine.view(fit: BoxFit.contain, subtitlePad: 12)))
                  else
                    _previewIdle(item),
                  // Same soft pulse as full screen, only when loading takes over half a second.
                  if (engine != null && _pvBuffering) SoftPulse(key: ValueKey('pv-${playing?.id}'), size: 40),
                  if (engine != null && playing != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 26, 14, 10),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xCC000000)],
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration:
                                  BoxDecoration(color: C.danger, borderRadius: BorderRadius.circular(4)),
                              child: const Text('LIVE',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(playing.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            ),
                            Text(InputMode.remote ? 'OK = full screen' : 'Tap = full screen',
                                style: const TextStyle(fontSize: 12, color: Color(0xFFD5DAE3))),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ),
          ),
          const SizedBox(height: 12),
          // ---- guide box (scrolls: remote Right onto it then Up / Down, or drag on touch)
          Expanded(
            child: Focus(
              focusNode: _guideFocus,
              onKeyEvent: _guideKey,
              child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1C2130), Color(0xFF151923), Color(0xFF2A1E08)],
                ),
                border: Border.all(
                    color: _guideFocus.hasFocus ? C.accent : const Color(0x1FFFC400), width: _guideFocus.hasFocus ? 2 : 1),
              ),
              child: item == null
                  ? const Center(
                      child: Text('Move to a channel to see what is on.\nOK plays it here, OK again goes full screen.',
                          textAlign: TextAlign.center, style: TextStyle(color: C.dim, fontSize: 14, height: 1.5)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Channel name with the time right next to it.
                        Row(
                          children: [
                            SizedBox(width: 38, height: 30, child: NetImage(item.icon, cacheWidth: 96)),
                            const SizedBox(width: 10),
                            if (_focusNumber > 0)
                              Text('$_focusNumber  ',
                                  style: const TextStyle(fontSize: 15, color: C.accent, fontWeight: FontWeight.w800)),
                            Flexible(
                              child: Text(item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                  color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(6)),
                              child: Text(_hm(now),
                                  style: const TextStyle(fontSize: 13.5, color: Color(0xFFD5DAE3), fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // The programmes scroll inside the box, so nothing runs off its bottom.
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _guideScroll,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_focusEpgLoading)
                                  Text(t('Loading the guide…'), style: const TextStyle(color: C.dim, fontSize: 13.5))
                                else if (upcoming.isEmpty)
                                  Text(t('No programme information for this channel.'),
                                      style: const TextStyle(color: C.dim, fontSize: 13.5))
                                else ...[
                                  if (current != null) ...[
                                    Row(
                                      children: [
                                        Text('${_hm(current.start)} – ${_hm(current.end)}',
                                            style: const TextStyle(
                                                fontSize: 13.5, color: C.accent, fontWeight: FontWeight.w800)),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(current.title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 15.5, color: C.accent, fontWeight: FontWeight.w800)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 4,
                                        color: C.accent,
                                        backgroundColor: const Color(0x26FFFFFF),
                                      ),
                                    ),
                                    if (current.description.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(current.description,
                                          style: const TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFFB9C0CC))),
                                    ],
                                    const SizedBox(height: 8),
                                  ],
                                  for (final e in later)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 5),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            width: 104,
                                            child: Text('${_hm(e.start)} – ${_hm(e.end)}',
                                                style: const TextStyle(fontSize: 13, color: Color(0xFFD5DAE3))),
                                          ),
                                          Expanded(
                                            child: Text(e.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _previewIdle(XItem? item) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(colors: [Color(0xFF1E2433), Colors.black], radius: 0.9),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item != null && item.icon.startsWith('http'))
              SizedBox(width: 120, height: 72, child: NetImage(item.icon, cacheWidth: 240))
            else
              const Icon(Icons.live_tv_rounded, color: C.dim, size: 46),
            const SizedBox(height: 10),
            Text(t('Press OK to watch here'), style: const TextStyle(color: C.dim, fontSize: 13.5)),
          ],
        ),
      ),
    );
  }

  /// The three buttons share the row evenly, so none of them runs off the edge.
  Widget _paneButton(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: TvFocus(
        radius: 9,
        color: const Color(0x1AFFFFFF),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: C.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- moving a category
  List<XCategory> get _visibleCats => (_cats ?? const <XCategory>[]).where((c) => !Store.isHidden(widget.kind, c.id)).toList();

  void _startMove(XCategory cat) {
    if (_moving != null) return;
    _focusTimer?.cancel();
    setState(() {
      _moving = cat.id;
      _dragFrom = _visibleCats.indexWhere((c) => c.id == cat.id);
    });
    log('category move start');
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        width: 380,
        content: Text(
            InputMode.remote ? 'Move it with Up / Down, then press OK to place it.' : 'Drag it up or down, then let go.',
            textAlign: TextAlign.center),
      ));
  }

  /// Puts the moving category at position [to] among the shown ones (hidden ones keep their place).
  void _moveTo(int to) {
    final id = _moving;
    final all = _cats;
    if (id == null || all == null) return;
    final shown = _visibleCats;
    final from = shown.indexWhere((c) => c.id == id);
    if (from < 0) return;
    to = to.clamp(0, shown.length - 1);
    if (to == from) return;
    final cat = shown[from];
    final next = List<XCategory>.of(all)..removeWhere((c) => c.id == id);
    final anchor = shown[to];
    var at = next.indexWhere((c) => c.id == anchor.id);
    if (to > from) at += 1; // below the category it passed
    next.insert(at, cat);
    setState(() => _cats = next);
    // The moved row keeps the focus (its key moves with it); keep it on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 120));
    });
  }

  void _moveBy(int step) {
    final from = _visibleCats.indexWhere((c) => c.id == _moving);
    if (from >= 0) _moveTo(from + step);
  }

  void _finishMove() {
    final id = _moving;
    final all = _cats;
    if (id == null || all == null) return;
    Store.setCategoryOrder(widget.kind, all.map((c) => c.id).toList());
    setState(() => _moving = null);
    log('category moved');
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        duration: Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        width: 320,
        content: Text('Category order saved', textAlign: TextAlign.center),
      ));
  }

  KeyEventResult _moveKeys(FocusNode node, KeyEvent event) {
    if (_moving == null || event is KeyUpEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp) {
      _moveBy(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      _moveBy(1);
      return KeyEventResult.handled;
    }
    // Stays on the list until the category is placed.
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) return KeyEventResult.handled;
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.browserBack) {
      _finishMove();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _categories() {
    if (_catsError != null) return ErrorBox(message: _catsError!, onRetry: _loadCategories, autofocus: true);
    final all = _cats;
    if (all == null) return const Loading();
    final cats = all.where((c) => !Store.isHidden(widget.kind, c.id)).toList();
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _moveKeys,
      child: ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: cats.length + 4,
      itemExtent: 42,
      // A moved category keeps its row (and the focus) while it changes place.
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final i = cats.indexWhere((c) => 'cat:${c.id}' == key.value);
        return i < 0 ? null : i + 4;
      },
      itemBuilder: (context, index) {
        if (index == 0) {
          return _CategoryRow(
            icon: Icons.search_rounded,
            name: t('Search'),
            selected: _selected == _searchId,
            onTap: _search,
          );
        }
        if (index == 1) {
          final total = _all?.length;
          final title = allTitle(widget.kind);
          return _CategoryRow(
            icon: Icons.apps_rounded,
            name: total == null ? title : '$title  ($total)',
            selected: _selected == _allId,
            autofocus: _firstId == null,
            // "All" is heavy: it opens only on OK, never by moving over it.
            onTap: () => _select(_allId, title),
          );
        }
        if (index == 2) {
          return _CategoryRow(
            icon: Icons.star_rounded,
            name: t('Favourites'),
            selected: _selected == _favId,
            onTap: () => _select(_favId, t('Favourites')),
            onFocus: () => _focusCategory(_favId, t('Favourites')),
          );
        }
        if (index == 3) {
          return _CategoryRow(
            icon: Icons.history_rounded,
            name: t('Recent'),
            selected: _selected == _recentId,
            onTap: () => _select(_recentId, t('Recent')),
            onFocus: () => _focusCategory(_recentId, t('Recent')),
          );
        }
        final cat = cats[index - 4];
        final locked = Store.isLocked(widget.kind, cat.id) && !Store.parentalUnlocked;
        final moving = _moving == cat.id;
        // A finger (or a mouse) drags the category it holds. Always ready, not only in touch mode:
        // a phone's volume button counts as a key, and the list may not have been rebuilt since.
        final canDrag = _moving == null || moving;
        return _CategoryRow(
          key: ValueKey<String>('cat:${cat.id}'),
          icon: moving ? Icons.swap_vert_rounded : (locked ? Icons.lock_rounded : null),
          name: cat.name,
          selected: _selected == cat.id || moving,
          moving: moving,
          // The remote starts on the category that opens first (the server's first one).
          autofocus: cat.id == _firstId,
          onTap: moving ? _finishMove : () => _select(cat.id, cat.name),
          onFocus: _moving != null ? null : () => _focusCategory(cat.id, cat.name),
          // Hold OK / the finger: the category can be moved. While it moves, its row keeps handling
          // OK itself (a no-op hold), so the still-held OK cannot place it at once.
          onLongPress: _moving == null ? () => _startMove(cat) : (moving ? () {} : null),
          onLongPressMove: canDrag ? (dy) => _moveTo(_dragFrom + (dy / 42).round()) : null,
          onLongPressEnd: canDrag ? _finishMove : null,
        );
      },
    ),
    );
  }

  Widget _content() {
    if (_itemsError != null) return ErrorBox(message: _itemsError!, onRetry: _retryItems);
    final items = _items;
    if (items == null) {
      return _cats == null && _catsError != null ? const SizedBox() : const Loading();
    }
    if (items.isEmpty) {
      final text = _selected == _favId
          ? 'No favourites yet.\nHold OK on a ${_live ? 'channel' : 'title'} to add it here.'
          : _selected == _recentId
              ? 'Nothing watched yet.\nWhat you open appears here.'
              : (_selected == _searchId ? 'Nothing found.' : 'This category is empty.');
      return Center(
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.dim, fontSize: 15, height: 1.5)),
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      final int columns;
      final double extent;
      if (_live) {
        columns = 1;
        extent = 48;
      } else {
        columns = math.max(2, (width / 128).floor());
        extent = ((width - (columns - 1) * 10) / columns) * 1.48;
      }
      return GridView.builder(
        key: ValueKey('$_selected|$_query'),
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: extent,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final fav = Store.isFavourite(item);
          void open() => _openItem(items, index);
          void hold() => _toggleFavourite(item);
          return _live
              ? _ChannelTile(
                  item: item,
                  number: index + 1,
                  favourite: fav,
                  playing: _pvItem?.id == item.id,
                  onTap: open,
                  onLongPress: hold,
                  onFocus: () => _focusChannel(item, index + 1),
                )
              : _PosterTile(item: item, favourite: fav, onTap: open, onLongPress: hold);
        },
      );
    });
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    super.key,
    required this.name,
    required this.selected,
    required this.onTap,
    this.onFocus,
    this.onLongPress,
    this.onLongPressMove,
    this.onLongPressEnd,
    this.moving = false,
    this.icon,
    this.autofocus = false,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onFocus;
  final VoidCallback? onLongPress;
  final ValueChanged<double>? onLongPressMove;
  final VoidCallback? onLongPressEnd;
  final bool moving;
  final IconData? icon;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TvFocus(
        autofocus: autofocus,
        selected: selected,
        color: moving ? Color.alphaBlend(C.accent.withValues(alpha: 0.30), C.panel) : C.panel,
        focusBorder: moving ? Colors.white : C.accent,
        radius: 8,
        onTap: onTap,
        onFocus: onFocus,
        onLongPress: onLongPress,
        onLongPressMove: onLongPressMove,
        onLongPressEnd: onLongPressEnd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: C.accent),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? C.text : const Color(0xFFC9CFDA),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.item,
    required this.number,
    required this.favourite,
    required this.onTap,
    required this.onLongPress,
    this.onFocus,
    this.playing = false,
  });

  final XItem item;
  final int number;
  final bool favourite;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      onTap: onTap,
      onLongPress: onLongPress,
      onFocus: onFocus,
      selected: playing,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text('$number',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: playing ? C.accent : C.dim)),
            ),
            SizedBox(width: 40, height: 40, child: NetImage(item.icon, cacheWidth: 96)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, height: 1.2, fontWeight: FontWeight.w600),
              ),
            ),
            if (favourite) const Icon(Icons.star_rounded, color: C.accent, size: 15),
          ],
        ),
      ),
    );
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({
    required this.item,
    required this.favourite,
    required this.onTap,
    required this.onLongPress,
  });

  final XItem item;
  final bool favourite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7.5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetImage(item.icon, fit: BoxFit.cover, cacheWidth: 220, fallback: Icons.movie_rounded),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(7, 22, 7, 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xE6000000)],
                  ),
                ),
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (favourite)
              const Positioned(top: 5, right: 5, child: Icon(Icons.star_rounded, color: C.accent, size: 16)),
          ],
        ),
      ),
    );
  }
}

Future<String?> _askSearch(BuildContext context, String initial) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.panel,
      title: const Text('Search'),
      content: SizedBox(
        width: 380,
        child: TvField(
          controller: controller,
          label: 'Name',
          icon: Icons.search_rounded,
          autofocus: true,
          action: TextInputAction.search,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('Search')),
      ],
    ),
  );
}
