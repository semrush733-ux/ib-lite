import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend.dart';
import '../continue_watching.dart';
import '../downloads.dart';
import '../i18n.dart';
import '../m3u.dart';
import '../parental.dart';
import '../prefetch.dart';
import '../profiles.dart';
import '../puppy.dart';
import '../reminders.dart';
import '../speedtest.dart';
import '../store.dart';
import '../streaming.dart';
import '../theme.dart';
import '../voice.dart';
import '../weather.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'browse.dart';
import 'catchup.dart';
import 'connect.dart';
import 'device.dart';
import 'downloads.dart';
import 'player.dart' show PlayerScreen, liveEntries;
import 'playlists.dart';
import 'profiles.dart';
import 'settings.dart';
import 'streaming.dart';
import 'update_web.dart' if (dart.library.io) 'update.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String _two(int n) => n.toString().padLeft(2, '0');

/// The home screen: logo and buttons along the top, four large tiles (Live TV, Movies,
/// TV Series, Catch Up), and three information boxes along the bottom (this device,
/// the playlist's expiry, place / date / time / weather).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, this.account, this.demo = false});

  final Source api;
  final XAccount? account;

  /// The demo from the website ("Watch the demo"): nothing is saved, Back goes back to the
  /// first screen, the website's playlists are not followed.
  final bool demo;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// "Start with the last channel" (Settings › Live Player) is tried once per app start.
  static bool _lastChannelTried = false;

  /// A key was pressed on the home screen before the last channel started: the customer is
  /// going somewhere else, so it does not start by itself.
  bool _userActed = false;

  bool _noteEarlyKey(KeyEvent e) {
    if (e is KeyDownEvent && mounted && ModalRoute.of(context)?.isCurrent == true) _userActed = true;
    return false;
  }

  XAccount? _account;
  bool _offline = false;
  bool _refreshing = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    log('screen=home profile=${Store.profileId} kids=${Store.kidsMode}');
    // TV Guide reminders play from the playlist that is open.
    if (!widget.demo) Reminders.api = widget.api;
    ContinueWatching.changes.addListener(_onBackendChange);
    // Every list downloads once in the background, out of the player's way.
    ListPrefetch.start(widget.api);
    Backend.changes.addListener(_onBackendChange);
    Backend.refreshSignal.addListener(_onRefreshSignal);
    if (_account == null) _refreshAccount();
    // A few seconds after start: pick up a new server / login set on the website.
    if (!widget.demo) {
      Timer(const Duration(seconds: 6), _followSite);
      _follow = Timer.periodic(const Duration(minutes: 5), (_) => _followSite());
    }
    Weather.refresh().then((_) {
      if (mounted) setState(() {});
    });
    // Date, time and weather in the corner stay current.
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() {});
      Weather.refresh();
    });
    if (!_lastChannelTried && !widget.demo) {
      _lastChannelTried = true;
      if (Store.startWithLastChannel && Store.lastLive != null) {
        // The home screen shows for a moment first.
        HardwareKeyboard.instance.addHandler(_noteEarlyKey);
        Timer(const Duration(milliseconds: 700), () {
          _startLastChannel().whenComplete(() => HardwareKeyboard.instance.removeHandler(_noteEarlyKey));
        });
      }
    }
  }

  /// The channel watched last plays by itself, with the channels of its category around it
  /// (Up / Down zap on from there). Back leaves it on the home screen.
  Future<void> _startLastChannel() async {
    final item = Store.lastLive;
    if (!mounted || item == null || !Store.allowed(item)) return;
    final cat = item.categoryId;
    // A locked category needs the parental PIN: not by itself at start.
    if (cat.isNotEmpty && Store.isLocked(XKind.live, cat) && !Store.parentalUnlocked) return;
    var items = <XItem>[];
    var loaded = false;
    if (cat.isNotEmpty) {
      try {
        items = await widget.api.items(XKind.live, categoryId: cat);
        // Some servers ignore the category filter and send everything.
        if (items.any((i) => i.categoryId == cat) && items.any((i) => i.categoryId != cat)) {
          items = items.where((i) => i.categoryId == cat).toList();
        }
        loaded = true;
      } catch (e) {
        log('last channel: its category did not load (${e.runtimeType})');
      }
    }
    items = items.where(Store.allowed).toList();
    var index = items.indexWhere((i) => i.id == item.id);
    if (index < 0) {
      // The category came but the channel is no longer in it: nothing to start.
      if (loaded) {
        log('last channel: no longer on the server');
        return;
      }
      items = [item];
      index = 0;
    }
    // A message or an update window may be open first: wait for the home screen to be on top.
    for (var i = 0; i < 16 && mounted && !_userActed && ModalRoute.of(context)?.isCurrent != true; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!mounted || _userActed || ModalRoute.of(context)?.isCurrent != true) return;
    log('start with the last channel');
    Store.addRecent(item);
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(api: widget.api, entries: liveEntries(widget.api, items), index: index, live: true)));
    _afterBack();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_noteEarlyKey);
    _tick?.cancel();
    _follow?.cancel();
    ContinueWatching.changes.removeListener(_onBackendChange);
    Backend.changes.removeListener(_onBackendChange);
    Backend.refreshSignal.removeListener(_onRefreshSignal);
    super.dispose();
  }

  /// "Reload" from the Admin Panel: playlist and website looked at again.
  void _onRefreshSignal() {
    if (!mounted) return;
    log('reload asked by the admin panel');
    _reload();
  }

  void _onBackendChange() {
    if (mounted) setState(() {});
  }

  /// The saved playlist is used straight away and checked in the background.
  Future<void> _refreshAccount() async {
    try {
      final account = await widget.api.login();
      if (!mounted) return;
      setState(() {
        _account = account;
        _offline = false;
      });
    } on XtreamAuthException catch (e) {
      // The demo's login does not work: nothing of the customer's is touched.
      if (widget.demo) {
        if (mounted) setState(() => _offline = true);
        return;
      }
      await Store.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => ConnectScreen(message: e.message)),
        (_) => false,
      );
    } catch (_) {
      if (mounted) setState(() => _offline = true);
    }
  }

  /// The playlist on the website may have changed (e.g. the provider moved to a new server, or
  /// the username was changed in the admin panel): reopen it with the new details.
  Timer? _follow;
  bool _pendingFollow = false;
  (Source, XAccount)? _ready;

  Future<void> _followSite() async {
    if (widget.demo) return;
    final id = Store.playlistId;
    if (id <= 0 || !Backend.configured) return;
    try {
      final lists = await Backend.playlists();
      BPlaylist? p;
      for (final l in lists) {
        if (l.id == id) p = l;
      }
      if (!mounted) return;
      if (p == null) {
        // The playlist was deleted on the website.
        if (ModalRoute.of(context)?.isCurrent != true) {
          _pendingFollow = true; // not in the middle of a channel: when back on this screen
          return;
        }
        if (lists.isEmpty) {
          // None left: back to the start screen (QR code / sign-in) to add one.
          log('playlist removed on the website: none left, back to the start screen');
          await Store.logout();
          await Store.forgetSitePlaylist();
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(
                builder: (_) => const ConnectScreen(
                    message: 'This playlist was removed. Scan the QR code or add a playlist on the website.')),
            (_) => false,
          );
          return;
        }
        // Another playlist is still there: open that one.
        log('playlist removed on the website: opening "${lists.first.name}"');
        final result = await openSitePlaylist(lists.first);
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => HomeScreen(api: result.$1, account: result.$2)),
          (_) => false,
        );
        return;
      }
      // Compared with what the website said when this playlist was opened, not with the player's
      // own connection (an M3U link opens through the Xtream API, http may become https…).
      final sig = sitePlaylistSig(p);
      final before = Store.playlistSig;
      if (before.isEmpty) {
        await Store.setPlaylistSig(sig); // first check after the update: this is what is open
        return;
      }
      if (sig == before) return;
      // Never pull the viewer out of a channel or film: wait until they are back on this screen.
      if (!mounted || (ModalRoute.of(context)?.isCurrent ?? false) == false) {
        _pendingFollow = true;
        return;
      }
      log('playlist changed on the website: reopening');
      final result = await openSitePlaylist(p);
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) {
        _ready = result; // opened meanwhile: switched over when they come back
        _pendingFollow = true;
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => HomeScreen(api: result.$1, account: result.$2)),
        (_) => false,
      );
    } catch (e) {
      log('follow website playlist: ${e.runtimeType}');
    }
  }

  /// The round-arrow button: checks the playlist and the website again.
  Future<void> _reload() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await Future.wait([
      _followSite(),
      _refreshAccount(),
      Backend.refreshStatus().catchError((Object _) {}),
      Backend.loadConfig().catchError((Object _) {}),
    ]);
    if (mounted) setState(() => _refreshing = false);
  }

  void _open(XKind kind) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => BrowseScreen(api: widget.api, kind: kind)))
        .then((_) => _afterBack());
  }

  /// Voice search: say a channel, film or series. The right section opens with the results;
  /// when it is not clear which one, the customer picks it.
  Future<void> _voiceSearch() async {
    final heard = await Voice.listen(prompt: t('Say a channel, film or series'));
    if (!mounted || heard.isEmpty) return;
    final said = heard.first;
    final words = ' ${voiceNorm(said)} ';
    XKind? kind;
    if (RegExp(r' (series|season|episode|drama|serial) ').hasMatch(words)) {
      kind = XKind.series;
    } else if (RegExp(r' (movie|movies|film|films) ').hasMatch(words)) {
      kind = XKind.vod;
    } else if (RegExp(r' (channel|channels|live) ').hasMatch(words)) {
      kind = XKind.live;
    }
    final query = voiceQuery(said);
    final chosen = kind ?? await _askKind(query);
    if (chosen == null || !mounted) return;
    log('voice search kind=${chosen.name}');
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => BrowseScreen(api: widget.api, kind: chosen, search: query)))
        .then((_) => _afterBack());
  }

  Future<XKind?> _askKind(String query) {
    return showDialog<XKind>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: Row(
          children: [
            const Icon(Icons.mic_rounded, color: C.accent),
            const SizedBox(width: 10),
            Expanded(child: Text('"$query"', maxLines: 2, overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: Text(t('Where should I search?'), style: const TextStyle(color: C.dim, fontSize: 15)),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, XKind.live), child: Text(t('Live TV'))),
          TextButton(onPressed: () => Navigator.pop(ctx, XKind.vod), child: Text(t('Movies'))),
          TextButton(onPressed: () => Navigator.pop(ctx, XKind.series), child: Text(t('Series'))),
        ],
      ),
    );
  }

  /// Back on the home screen: a playlist change from the website that waited is applied now.
  void _afterBack() {
    if (!_pendingFollow || !mounted) return;
    _pendingFollow = false;
    final r = _ready;
    _ready = null;
    if (r == null) {
      _followSite();
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => HomeScreen(api: r.$1, account: r.$2)),
      (_) => false,
    );
  }

  void _openCatchup() {
    final api = widget.api;
    if (api is XtreamApi) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CatchupScreen(api: api))).then((_) => _afterBack());
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: const Text('Catch Up'),
        content: const Text(
          'Catch Up works with Xtream Codes playlists, where the server keeps recordings of past '
          'programmes. An M3U playlist link does not carry recordings.',
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: C.accent))),
        ],
      ),
    );
  }

  /// "Change Playlist": the playlists added on the website for this device.
  Future<void> _choosePlaylist() async {
    // In the demo this button leaves it.
    if (widget.demo) {
      Navigator.of(context).maybePop();
      return;
    }
    // In a Kids profile only a parent changes the playlist.
    if (Store.kidsMode && !await askParentalPin(context)) return;
    if (!mounted) return;
    final choice = await Navigator.of(context).push<BPlaylist>(
        MaterialPageRoute(builder: (_) => PlaylistsScreen(current: playlistTitle(widget.api))));
    // A playlist was deleted there: follow the website now (the one in use may be gone).
    if (PlaylistsScreen.takeDeleted() && mounted && choice == null) {
      await _followSite();
      return;
    }
    if (choice == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 20),
        behavior: SnackBarBehavior.floating,
        width: 360,
        content: Text('Loading "${choice.name}"…', textAlign: TextAlign.center),
      ));
    try {
      final result = await openSitePlaylist(choice);
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => HomeScreen(api: result.$1, account: result.$2)),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          width: 420,
          content: Text(friendlyError(e), textAlign: TextAlign.center),
        ));
    }
  }

  /// The playlist's name for the top bar (shortened); [fallback] when there is none.
  String _shortName(String name, String fallback) {
    final n = name.trim();
    if (n.isEmpty) return fallback;
    return n.length > 22 ? '${n.substring(0, 21)}…' : n;
  }

  Future<void> _openSettings() async {
    // In a Kids profile Settings need the parental PIN.
    if (Store.kidsMode && !await askParentalPin(context)) return;
    if (!mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(api: widget.api)))
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  /// The profile button: "Who's watching?".
  Future<void> _openProfiles() async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute<bool>(builder: (_) => ProfilesScreen(api: widget.api)));
    if (!mounted) return;
    if (changed == true) {
      // Another profile: the home screen starts over with its lists (the demo stays a demo).
      if (widget.demo) {
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
            builder: (_) => HomeScreen(api: widget.api, account: _account, demo: true)));
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => HomeScreen(api: widget.api, account: _account)),
        (_) => false,
      );
    } else {
      setState(() {});
    }
  }

  // ------------------------------------------------------------ Continue Watching

  Future<void> _playContinue(CwEntry e, {bool fromStart = false}) async {
    await playContinue(context, widget.api, e, fromStart: fromStart);
    if (mounted) setState(() {});
  }

  Future<void> _continueMenu(CwEntry e) async {
    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Text(e.subtitle.isEmpty ? e.note : '${e.subtitle}\n${e.note}', style: const TextStyle(color: C.dim, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 2), child: const Text('Remove from the row')),
          TextButton(onPressed: () => Navigator.pop(ctx, 1), child: const Text('Play from the start')),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('Continue', style: TextStyle(color: C.accent)),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 2) {
      ContinueWatching.remove(e.key);
      setState(() {});
    } else {
      _playContinue(e, fromStart: choice == 1);
    }
  }

  Widget _continueRow(List<CwEntry> list, double w, double h, double pad, double gap) {
    final rowH = (h * 0.2).clamp(92.0, 170.0).toDouble();
    final cardW = ((w - 2 * pad - 3 * gap) / 3.6).clamp(220.0, 420.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: h * 0.028),
        Text(t('Continue Watching'),
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, shadows: [Shadow(color: Color(0x99000000), blurRadius: 6)])),
        const SizedBox(height: 8),
        SizedBox(
          height: rowH,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: list.length,
            separatorBuilder: (_, __) => SizedBox(width: gap),
            itemBuilder: (context, i) => SizedBox(
              width: cardW,
              child: _ContinueCard(
                entry: list[i],
                height: rowH,
                onTap: () => _playContinue(list[i]),
                onLongPress: () => _continueMenu(list[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showAccount() {
    final a = _account;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: Row(
          children: [
            const Icon(Icons.account_circle_rounded, color: C.accent),
            const SizedBox(width: 10),
            Expanded(child: Text(playlistTitle(widget.api), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Playlist', widget.api is XtreamApi ? 'Xtream Codes' : 'M3U'),
              _infoRow('Status', a == null ? (_offline ? 'No connection' : 'Checking…') : (a.isTrial ? 'Trial' : 'Active')),
              _infoRow('Expires', a?.expires == null ? (a == null ? '—' : 'Never') : formatDate(a!.expires!)),
              if (a != null && a.note.isNotEmpty) _infoRow('Note', a.note),
              _infoRow('App', Backend.statusLine.isEmpty ? '—' : Backend.statusLine),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _choosePlaylist();
            },
            child: const Text('Change playlist'),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: C.accent)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 90, child: Text(k, style: const TextStyle(color: C.dim, fontSize: 14))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
          ],
        ),
      );

  void _showUpdate() {
    final update = Backend.update;
    if (update != null) showUpdateDialog(context, update);
  }

  String get _appExpiry {
    if (Backend.licType == 'lifetime') return 'Lifetime';
    final e = Backend.licExpiry;
    if (e == null) return Backend.statusLine.isEmpty ? '—' : Backend.statusLine;
    return '${e.year}-${_two(e.month)}-${_two(e.day)}${Backend.licStatus == 'trial' ? '  (free trial)' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            wallpaperAsset(Store.wallpaper),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, __, ___) => const SizedBox(),
          ),
          // Deep red wash over the picture, darker at the edges.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xEB2C0B0F), Color(0xD1361016), Color(0xF0140608)],
                stops: [0, 0.5, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.2, -0.3),
                radius: 1.1,
                colors: [Color(0x00000000), Color(0x99000000)],
              ),
            ),
          ),
          SafeArea(child: _content()),
          // The puppy roams the edges; stops when the viewer uses the remote, and stands still
          // while another screen is open on top.
          const Positioned.fill(child: IgnorePointer(child: ExcludeFocus(child: RunningPuppy(size: 56)))),
        ],
      ),
    );
    // The demo: Back returns to the first screen. Otherwise Back asks whether to close the app.
    return widget.demo ? page : ExitGuard(child: page);
  }

  Widget _content() {
    final kids = Store.kidsMode;
    final profile = Profiles.active;
    // The demo has no half-watched films of the customer's own playlist.
    final continueList = widget.demo ? const <CwEntry>[] : ContinueWatching.all;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final pad = w * 0.04;
      final gap = w * 0.016;
      // A short screen (a phone) with the Continue Watching row: the page scrolls and the tiles
      // keep a fixed height, so nothing gets squeezed.
      final compact = continueList.isNotEmpty && box.maxHeight < 470;
      final tiles = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _HomeTile(
              autofocus: true,
              icon: Icons.live_tv_rounded,
              title: t('Live TV'),
              onTap: () => _open(XKind.live),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: _HomeTile(icon: Icons.movie_creation_outlined, title: t('Movies'), onTap: () => _open(XKind.vod)),
          ),
          SizedBox(width: gap),
          Expanded(
            child: _HomeTile(icon: Icons.movie_filter_outlined, title: t('TV Series'), onTap: () => _open(XKind.series)),
          ),
          // Catch Up lists every channel: not in a Kids profile.
          if (!kids) ...[
            SizedBox(width: gap),
            Expanded(
              child: _HomeTile(icon: Icons.replay_rounded, title: t('Catch Up'), onTap: _openCatchup),
            ),
          ],
        ],
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(pad, box.maxHeight * 0.05, pad, box.maxHeight * 0.04),
        child: _scrollIf(compact, Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- top bar ----
            Row(
              children: [
                const Logo(size: 30),
                if (widget.demo) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: C.accent, borderRadius: BorderRadius.circular(8)),
                    child: Text(t('Demo').toUpperCase(),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ),
                ],
                SizedBox(width: w * 0.04),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _ProfileButton(profile: profile, onTap: _openProfiles),
                        const SizedBox(width: 14),
                        if (!kids || widget.demo) ...[
                          _PillButton(
                            icon: widget.demo ? Icons.logout_rounded : Icons.playlist_play_rounded,
                            label: widget.demo
                                ? t('Exit demo')
                                : _shortName(playlistTitle(widget.api), t('Change Playlist')),
                            onTap: _choosePlaylist,
                          ),
                          const SizedBox(width: 14),
                        ],
                        _PillButton(icon: Icons.settings_rounded, label: t('Settings'), onTap: _openSettings),
                        if (Downloads.available && !kids) ...[
                          const SizedBox(width: 14),
                          _PillButton(
                            icon: Icons.download_rounded,
                            label: t('Downloads'),
                            onTap: () => Navigator.of(context)
                                .push(MaterialPageRoute<void>(builder: (_) => DownloadsScreen(api: widget.api))),
                          ),
                        ],
                        if (Backend.updateAvailable) ...[
                          const SizedBox(width: 14),
                          _PillButton(icon: Icons.system_update_rounded, label: t('Update'), onTap: _showUpdate),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Voice search (phones, Android / Google TV boxes; Fire TV has no speech screen for apps).
                if (Voice.canListen) ...[
                  _IconSquare(icon: Icons.mic_rounded, tooltip: t('Voice search'), onTap: _voiceSearch),
                  const SizedBox(width: 12),
                ],
                _IconSquare(
                  icon: _refreshing ? Icons.hourglass_top_rounded : Icons.sync_rounded,
                  tooltip: 'Reload',
                  onTap: _reload,
                ),
                const SizedBox(width: 12),
                _IconSquare(icon: Icons.speed_rounded, tooltip: 'Speed test', onTap: () => showSpeedTest(context)),
                const SizedBox(width: 12),
                _IconSquare(icon: Icons.tv_rounded, tooltip: 'My device', onTap: () => showDeviceDialog(context)),
                const SizedBox(width: 12),
                _IconSquare(icon: Icons.person_rounded, tooltip: 'Account', onTap: _showAccount),
              ],
            ),
            SizedBox(height: box.maxHeight * 0.05),
            // ---- the four tiles ----
            if (compact)
              SizedBox(height: (box.maxHeight * 0.36).clamp(110.0, 400.0).toDouble(), child: tiles)
            else
              Expanded(child: tiles),
            // ---- Continue Watching: half-watched films and episodes of this profile ----
            if (continueList.isNotEmpty) _continueRow(continueList, w, box.maxHeight, pad, gap),
            // ---- streaming service boxes (Settings › Streaming Boxes) ----
            if (enabledStreaming().isNotEmpty) ...[
              SizedBox(height: box.maxHeight * 0.03),
              SizedBox(
                height: box.maxHeight * 0.12,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: enabledStreaming().length,
                  separatorBuilder: (_, __) => SizedBox(width: gap),
                  itemBuilder: (context, i) {
                    final s = enabledStreaming()[i];
                    return SizedBox(
                      width: (w - 2 * pad - 4 * gap) / 5,
                      child: _StreamBox(
                        name: s.name,
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => StreamingScreen(api: widget.api, service: s))),
                      ),
                    );
                  },
                ),
              ),
            ],
            SizedBox(height: box.maxHeight * 0.045),
            // ---- information along the bottom: device, playlist, date and weather (same height) ----
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _InfoBox(
                    lines: [
                      'MAC Address: ${Backend.deviceId.isEmpty ? '—' : Backend.deviceId}',
                      'Device Key: ${Backend.pairingCode.isEmpty ? '—' : Backend.pairingCode}',
                      'Application Expiry: $_appExpiry',
                    ],
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: SizedBox(
                            width: 440,
                            child: PlaylistInfoBox(
                              name: widget.demo ? widget.api.label : playlistTitle(widget.api),
                              account: _account,
                              offline: _offline,
                              m3u: widget.api is M3uSource,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: gap),
                  const _WeatherBox(),
                ],
              ),
            ),
          ],
        )),
      );
    });
  }

  Widget _scrollIf(bool on, Widget child) => on ? SingleChildScrollView(child: child) : child;
}

/// The profile in use, at the left of the top bar: opens "Who's watching?".
class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.profile, required this.onTap});

  final Profile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Focusable(
      radius: 24,
      onTap: onTap,
      builder: (f) => AnimatedScale(
        scale: f ? 1.06 : 1,
        duration: const Duration(milliseconds: 140),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 46,
          padding: const EdgeInsets.fromLTRB(5, 4, 16, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: f ? const Color(0xFF3A3D46) : const Color(0xCC1E1F25),
            border: Border.all(color: f ? Colors.white : const Color(0x33FFFFFF), width: f ? 2.2 : 1),
            boxShadow: f ? const [BoxShadow(color: Color(0x88E3262F), blurRadius: 18)] : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProfileAvatar(profile, size: 36),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
              if (profile.kids) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0x3322C55E), borderRadius: BorderRadius.circular(6)),
                  child: Text(t('Kids'),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF7CD992))),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A half-watched film or episode: poster, name, how far it got. OK plays on from there;
/// holding OK offers "Play from the start" and "Remove from the row".
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.entry, required this.height, required this.onTap, required this.onLongPress});

  final CwEntry entry;
  final double height;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final posterH = height - 16;
    final posterW = posterH * 2 / 3;
    return TvFocus(
      radius: 14,
      color: const Color(0xD91A0D10),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: posterW,
                height: posterH,
                color: C.card,
                child: NetImage(entry.image,
                    fit: BoxFit.cover,
                    cacheWidth: 220,
                    fallback: entry.isEpisode ? Icons.video_library_rounded : Icons.movie_rounded),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title,
                      maxLines: height > 112 ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.2)),
                  if (entry.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(entry.subtitle,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.dim)),
                  ],
                  const SizedBox(height: 9),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: entry.upNext ? 0.0 : entry.progress,
                      minHeight: 4,
                      color: C.accent,
                      backgroundColor: const Color(0x33FFFFFF),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(entry.upNext ? Icons.skip_next_rounded : Icons.play_arrow_rounded, size: 14, color: C.dim),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(entry.note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: C.dim, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A streaming service on the home screen: its name only (never the company's logo).
class _StreamBox extends StatelessWidget {
  const _StreamBox({required this.name, required this.onTap});
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      radius: 14,
      color: const Color(0xD91A0D10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Icon(Icons.play_circle_fill_rounded, color: C.accent, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(t('Movies & Series'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.dim)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The open playlist's name as saved on the website, or the login name when it was typed in.
String playlistTitle(Source api) => Store.playlistName.isNotEmpty ? Store.playlistName : api.label;

/// Signs in with a playlist added on the website and remembers it.
String sitePlaylistSig(BPlaylist p) => '${p.url}|${p.username}|${p.password}';

/// The demo set on the website (Lite Player › Demo playlist, or App Settings › Demo on the TV),
/// opened only to watch: nothing is saved, so the customer's own playlist starts clean.
Future<(Source, XAccount)> openDemoPlaylist(BPlaylist p) async {
  if (p.isXtream) {
    final api = XtreamApi(parseServerInput(p.url).server, p.username, p.password);
    final account = await api.login();
    return (api, account);
  }
  final src = M3uSource(p.url, epgUrl: p.epgUrl, title: p.name);
  final account = await src.login();
  return (src, account);
}

Future<(Source, XAccount)> openSitePlaylist(BPlaylist p) async {
  final opened = await _openSite(p);
  await Store.setPlaylistName(p.name);
  await Store.setPlaylistId(p.id);
  await Store.setPlaylistSig(sitePlaylistSig(p));
  return opened;
}

Future<(Source, XAccount)> _openSite(BPlaylist p) async {
  if (p.isXtream) {
    var api = XtreamApi(parseServerInput(p.url).server, p.username, p.password);
    XAccount account;
    try {
      account = await api.login();
    } on XtreamException {
      rethrow;
    } catch (_) {
      // Plain http failed: the server may be https only.
      if (!api.server.startsWith('http://')) rethrow;
      api = XtreamApi(api.server.replaceFirst('http://', 'https://'), p.username, p.password);
      account = await api.login();
    }
    await Store.saveSession(api.server, api.username, api.password);
    return (api, account);
  }
  // A link from an Xtream panel goes through the panel's API: TV guide, series and catch-up.
  final parsed = parseServerInput(p.url);
  if (parsed.username != null && parsed.password != null && p.url.toLowerCase().contains('get.php')) {
    try {
      final api = XtreamApi(parsed.server, parsed.username!, parsed.password!);
      final account = await api.login();
      await Store.saveSession(api.server, api.username, api.password);
      return (api, account);
    } on XtreamAuthException {
      rethrow;
    } catch (_) {
      // Not an Xtream panel: read it as a plain playlist below.
    }
  }
  final src = M3uSource(p.url, epgUrl: p.epgUrl);
  final account = await src.login();
  await Store.saveM3uSession(p.url, epgUrl: p.epgUrl);
  return (src, account);
}

/// Remote-friendly focus wrapper that tells its builder whether it has focus.
class _Focusable extends StatefulWidget {
  const _Focusable({required this.builder, required this.onTap, this.autofocus = false, this.radius = 14});

  final Widget Function(bool focused) builder;
  final VoidCallback onTap;
  final bool autofocus;
  final double radius;

  @override
  State<_Focusable> createState() => _FocusableState();
}

class _FocusableState extends State<_Focusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        autofocus: widget.autofocus,
        borderRadius: BorderRadius.circular(widget.radius),
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        onTap: widget.onTap,
        onFocusChange: (v) {
          if (v != _focused) setState(() => _focused = v);
        },
        child: widget.builder(_focused),
      ),
    );
  }
}

/// Top-bar button: a grey icon square joined to a red label.
class _PillButton extends StatelessWidget {
  const _PillButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Focusable(
      radius: 12,
      onTap: onTap,
      builder: (f) => AnimatedScale(
        scale: f ? 1.06 : 1,
        duration: const Duration(milliseconds: 140),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: f ? Colors.white : Colors.transparent, width: 2.2),
            boxShadow: f ? const [BoxShadow(color: Color(0x88E3262F), blurRadius: 18)] : const [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: f ? const [Color(0xFF8A1A20), Color(0xFF5A0E13)] : const [Color(0xFF3A3D46), Color(0xFF26282F)],
                    ),
                  ),
                  child: Icon(icon, size: 22, color: Colors.white),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: f
                          ? const [Color(0xFFFF4A52), Color(0xFFE3262F)]
                          : const [Color(0xFF8A1C23), Color(0xFFA6232B)],
                    ),
                  ),
                  child: Text(label,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Square icon button on the right of the top bar.
class _IconSquare extends StatelessWidget {
  const _IconSquare({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: _Focusable(
        radius: 14,
        onTap: onTap,
        builder: (f) => AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: f ? const [Color(0xFFFF4A52), Color(0xFFB81E26)] : const [Color(0xFF34363F), Color(0xFF1E1F25)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: f ? Colors.white : const Color(0x33FFFFFF), width: f ? 2.2 : 1),
            boxShadow: f ? const [BoxShadow(color: Color(0x88E3262F), blurRadius: 18)] : const [],
          ),
          child: Icon(icon, size: 28, color: Colors.white),
        ),
      ),
    );
  }
}

/// One of the four large home tiles: red at the top fading into grey glass, a large white
/// icon and the title. The tile with focus grows a little, gets a white frame and a white bar.
class _HomeTile extends StatelessWidget {
  const _HomeTile({required this.icon, required this.title, required this.onTap, this.autofocus = false});

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return _Focusable(
      autofocus: autofocus,
      radius: 22,
      onTap: onTap,
      builder: (f) => AnimatedScale(
        scale: f ? 1.045 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: f ? Colors.white : const Color(0x22FFFFFF), width: f ? 3 : 1),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: f
                  ? const [Color(0xFFEF3A42), Color(0xD9B5323A), Color(0xB3707078)]
                  : const [Color(0xD9AE2A32), Color(0xB3782E34), Color(0x99505058)],
              stops: const [0, 0.45, 1],
            ),
            boxShadow: [
              BoxShadow(
                color: f ? const Color(0x99E3262F) : const Color(0x55000000),
                blurRadius: f ? 34 : 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: LayoutBuilder(builder: (context, b) {
            final s = b.maxHeight;
            return Stack(
              children: [
                if (f)
                  Positioned.fill(
                    child: ClipRRect(borderRadius: BorderRadius.circular(20), child: const Sheen()),
                  ),
                // Soft light from the top-left corner.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.center,
                        colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: s * 0.26, color: Colors.white),
                      SizedBox(height: s * 0.04),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: (s * 0.085).clamp(18, 40).toDouble(),
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              shadows: const [Shadow(color: Color(0x66000000), blurRadius: 8)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // The white bar under the tile that has focus.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: s * 0.04,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: f ? b.maxWidth * 0.3 : 0,
                      height: 8,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// Dark rounded box with a light frame (bottom of the home screen).
class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xD90B0607),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x66FFFFFF), width: 1.4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Text(l, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

/// The playlist in use, between the device box and the clock (same look and height): its name
/// with a coloured dot (green fine, amber ends within a week, red ended / no connection), when it
/// ends, and the days left with the number of connections (screens at once) the line allows.
class PlaylistInfoBox extends StatelessWidget {
  const PlaylistInfoBox(
      {super.key, required this.name, required this.account, required this.offline, required this.m3u});

  final String name;
  final XAccount? account;
  final bool offline;
  final bool m3u;

  static const _green = Color(0xFF2ECC71);
  static const _amber = Color(0xFFFFC94A);

  /// Whole days from today to the day the playlist ends (negative: ended). Counted on calendar
  /// days (UTC dates), so a clock change (summer time) never makes it one day short.
  static int _daysLeft(DateTime end) {
    final now = DateTime.now();
    return DateTime.utc(end.year, end.month, end.day).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final a = account;
    var dot = _green;
    final lines = <(String, Color)>[];
    if (a == null) {
      dot = offline ? C.danger : C.dim;
      lines.add(offline ? ('No connection to the server', C.danger) : ('Checking the playlist…', C.text));
      lines.add((offline ? 'Press Reload to try again' : 'One moment please', C.dim));
    } else if (m3u) {
      // M3U links carry no end date: what the list holds instead.
      final holds = a.note.replaceFirst(RegExp(r'^M3U playlist\s*·\s*'), '').trim();
      lines.add(('Playlist Expiry: not given (M3U link)', C.text));
      lines.add((holds.isEmpty ? 'M3U playlist' : holds, C.text));
    } else {
      final e = a.expires;
      final parts = <String>[if (a.isTrial) 'Trial'];
      var color = C.text;
      if (e == null) {
        lines.add(('Playlist Expiry: Unlimited', C.text));
        if (!a.isTrial) parts.add('Active');
      } else {
        lines.add(('Playlist Expiry: ${_days[e.weekday - 1]} ${e.day}, ${_months[e.month - 1]} ${e.year}', C.text));
        final d = _daysLeft(e);
        parts.add(d < 0 ? 'Ended' : (d == 0 ? 'Ends today' : (d == 1 ? '1 day left' : '$d days left')));
        if (d < 0) {
          color = C.danger;
          dot = C.danger;
        } else if (d <= 7) {
          color = _amber;
          dot = _amber;
        }
      }
      if (a.maxConnections > 0) {
        parts.add(a.maxConnections == 1 ? '1 connection' : '${a.maxConnections} connections');
      }
      lines.add((parts.join('  ·  '), color));
    }
    Widget line(String text, Color color) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(text, maxLines: 1, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xD90B0607),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x66FFFFFF), width: 1.4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(
              children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Flexible(child: line('Playlist: ${name.isEmpty ? '—' : name}', C.text)),
              ],
            ),
          ),
          for (final l in lines)
            Padding(padding: const EdgeInsets.symmetric(vertical: 1.5), child: line(l.$1, l.$2)),
        ],
      ),
    );
  }
}

/// Place, date, time and the current temperature.
class _WeatherBox extends StatelessWidget {
  const _WeatherBox();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final place = [Weather.city, Weather.country].where((s) => s.isNotEmpty).join(', ');
    final date = '${_days[now.weekday - 1].substring(0, 3)}, ${now.day}.${_months[now.month - 1]} ${now.year}';
    return Container(
      width: 270,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: BoxDecoration(
        color: const Color(0xD90B0607),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x66FFFFFF), width: 1.4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (place.isNotEmpty) ...[
                const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFFFF5A5F)),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(place.isEmpty ? date : place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              Icon(Weather.day ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                  size: 18, color: Weather.day ? const Color(0xFFFFC94A) : const Color(0xFF8FB4FF)),
            ],
          ),
          if (place.isNotEmpty) Text(date, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('${_two(now.hour)}:${_two(now.minute)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (Weather.temp != null)
                Text('${Weather.temp!.toStringAsFixed(1)}°', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The picture for a wallpaper number (0 = the standard home background).
String wallpaperAsset(int n) =>
    n <= 0 || n > 20 ? 'assets/home_bg.webp' : 'assets/wallpapers/wp${n.toString().padLeft(2, '0')}.webp';
