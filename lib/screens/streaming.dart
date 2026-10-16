import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../input_mode.dart';
import '../store.dart';
import '../streaming.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'movie.dart';
import 'series.dart';

/// One streaming service box from the home screen: the playlist's movies and series of that
/// service (see streaming.dart for how they are found).
class StreamingScreen extends StatefulWidget {
  const StreamingScreen({super.key, required this.api, required this.service});
  final Source api;
  final StreamingService service;

  @override
  State<StreamingScreen> createState() => _StreamingScreenState();
}

class _StreamingScreenState extends State<StreamingScreen> {
  StreamingFound? _found;
  String? _error;
  XKind _kind = XKind.vod;

  @override
  void initState() {
    super.initState();
    log('screen=streaming ${widget.service.id}');
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _found = null;
      _error = null;
    });
    try {
      final found = await StreamingFinder.find(widget.api, widget.service);
      if (!mounted) return;
      setState(() {
        _found = found;
        if (found.movies.isEmpty && found.series.isNotEmpty) _kind = XKind.series;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _open(XItem item) async {
    Store.addRecent(item);
    if (item.kind == XKind.series && item.url.isEmpty) {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => SeriesScreen(api: widget.api, series: item)));
    } else {
      // Movies open on their details page first; "Watch now" there starts the player.
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MovieScreen(api: widget.api, movie: item)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 16, 26, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
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
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(widget.service.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 20),
                  if (found != null) ...[
                    _tab(t('Movies'), found.movies.length, XKind.vod),
                    const SizedBox(width: 10),
                    _tab(t('Series'), found.series.length, XKind.series),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(String label, int count, XKind kind) {
    final on = _kind == kind;
    return TvFocus(
      autofocus: on,
      selected: on,
      radius: 22,
      color: C.panel,
      onTap: () => setState(() => _kind = kind),
      // Moving over a tab shows it at once.
      onFocus: () {
        if (_kind != kind) setState(() => _kind = kind);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        child: Text('$label  ($count)',
            style: TextStyle(fontSize: 14.5, fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? C.text : C.dim)),
      ),
    );
  }

  Widget _body() {
    if (_error != null) return ErrorBox(message: _error!, onRetry: _load, autofocus: true);
    final found = _found;
    if (found == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 60, height: 60, child: Loading()),
            const SizedBox(height: 14),
            Text('Looking for ${widget.service.name} titles in your playlist…', style: const TextStyle(color: C.dim)),
          ],
        ),
      );
    }
    final items = _kind == XKind.vod ? found.movies : found.series;
    if (items.isEmpty) {
      final what = _kind == XKind.vod ? 'movies' : 'series';
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'No $what of ${widget.service.name} were found in your playlist.\n\n'
            'This box shows the playlist\'s own ${widget.service.name} categories, and the titles of '
            '${widget.service.name} found in your playlist when the website has the film database (TMDB) set up.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: C.dim, fontSize: 15, height: 1.5),
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final columns = math.max(2, (box.maxWidth / 140).floor());
      final extent = ((box.maxWidth - (columns - 1) * 10) / columns) * 1.48;
      return GridView.builder(
        key: ValueKey(_kind),
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: extent,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => _Poster(item: items[i], onTap: () => _open(items[i])),
      );
    });
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.item, required this.onTap});
  final XItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      onTap: onTap,
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
          ],
        ),
      ),
    );
  }
}
