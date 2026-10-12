import 'dart:async';

import 'package:flutter/material.dart';

import '../backend.dart';
import '../i18n.dart';
import '../m3u.dart';
import '../prefetch.dart';
import '../speedtest.dart';
import '../store.dart';
import '../theme.dart';
import '../weather.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'browse.dart';
import 'catchup.dart';
import 'connect.dart';
import 'device.dart';
import 'playlists.dart';
import 'settings.dart';
import 'update_web.dart' if (dart.library.io) 'update.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String _two(int n) => n.toString().padLeft(2, '0');

/// The home screen: logo and buttons along the top, four large tiles (Live TV, Movies,
/// TV Series, Catch Up), and three information boxes along the bottom (this device,
/// the playlist's expiry, place / date / time / weather).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, this.account});

  final Source api;
  final XAccount? account;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  XAccount? _account;
  bool _offline = false;
  bool _refreshing = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    log('screen=home');
    // Every list downloads once in the background, out of the player's way.
    ListPrefetch.start(widget.api);
    Backend.changes.addListener(_onBackendChange);
    if (_account == null) _refreshAccount();
    // A few seconds after start: pick up a new server / login set on the website.
    Timer(const Duration(seconds: 6), _followSite);
    _follow = Timer.periodic(const Duration(minutes: 20), (_) => _followSite());
    Weather.refresh().then((_) {
      if (mounted) setState(() {});
    });
    // Date, time and weather in the corner stay current.
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() {});
      Weather.refresh();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _follow?.cancel();
    Backend.changes.removeListener(_onBackendChange);
    super.dispose();
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

  Future<void> _followSite() async {
    final id = Store.playlistId;
    if (id <= 0 || !Backend.configured) return;
    try {
      final lists = await Backend.playlists();
      BPlaylist? p;
      for (final l in lists) {
        if (l.id == id) p = l;
      }
      if (p == null || !mounted) return;
      final api = widget.api;
      bool changed;
      if (p.isXtream) {
        changed = api is! XtreamApi ||
            bareServer(parseServerInput(p.url).server) != bareServer(api.server) ||
            p.username != api.username ||
            p.password != api.password;
      } else {
        changed = api is! M3uSource || p.url != api.url;
      }
      if (!changed) return;
      log('playlist changed on the website: reopening');
      final result = await openSitePlaylist(p);
      if (!mounted) return;
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
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BrowseScreen(api: widget.api, kind: kind)));
  }

  void _openCatchup() {
    final api = widget.api;
    if (api is XtreamApi) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CatchupScreen(api: api)));
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
    final choice = await Navigator.of(context).push<BPlaylist>(
        MaterialPageRoute(builder: (_) => PlaylistsScreen(current: playlistTitle(widget.api))));
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

  /// "Change Style": the next background picture.
  void _nextStyle() {
    Store.setWallpaper((Store.wallpaper + 1) % 21);
    setState(() {});
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(api: widget.api)))
        .then((_) {
      if (mounted) setState(() {});
    });
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

  String get _playlistExpiry {
    final a = _account;
    if (a == null) return _offline ? 'Playlist: no connection' : 'Playlist: checking…';
    final e = a.expires;
    if (e == null) return 'Playlist Expiry: Unlimited';
    return 'Playlist Expiry: ${_days[e.weekday - 1]} ${e.day}, ${_months[e.month - 1]} ${e.year}';
  }

  String get _appExpiry {
    if (Backend.licType == 'lifetime') return 'Lifetime';
    final e = Backend.licExpiry;
    if (e == null) return Backend.statusLine.isEmpty ? '—' : Backend.statusLine;
    return '${e.year}-${_two(e.month)}-${_two(e.day)}${Backend.licStatus == 'trial' ? '  (free trial)' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    return ExitGuard(child: Scaffold(
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
                colors: [Color(0xE6400A10), Color(0xB3500C14), Color(0xEB1A0608)],
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
        ],
      ),
    ));
  }

  Widget _content() {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final pad = w * 0.04;
      final gap = w * 0.016;
      return Padding(
        padding: EdgeInsets.fromLTRB(pad, box.maxHeight * 0.05, pad, box.maxHeight * 0.04),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- top bar ----
            Row(
              children: [
                const Logo(size: 30),
                SizedBox(width: w * 0.04),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _PillButton(icon: Icons.palette_rounded, label: t('Change Style'), onTap: _nextStyle),
                        const SizedBox(width: 14),
                        _PillButton(
                          icon: Icons.playlist_play_rounded,
                          label: _shortName(playlistTitle(widget.api), t('Change Playlist')),
                          onTap: _choosePlaylist,
                        ),
                        const SizedBox(width: 14),
                        _PillButton(icon: Icons.settings_rounded, label: t('Settings'), onTap: _openSettings),
                        if (Backend.updateAvailable) ...[
                          const SizedBox(width: 14),
                          _PillButton(icon: Icons.system_update_rounded, label: t('Update'), onTap: _showUpdate),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
            Expanded(
              child: Row(
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
                  SizedBox(width: gap),
                  Expanded(
                    child: _HomeTile(icon: Icons.replay_rounded, title: t('Catch Up'), onTap: _openCatchup),
                  ),
                ],
              ),
            ),
            SizedBox(height: box.maxHeight * 0.045),
            // ---- information along the bottom ----
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _InfoBox(
                  lines: [
                    'MAC Address: ${Backend.deviceId.isEmpty ? '—' : Backend.deviceId}',
                    'Device Key: ${Backend.pairingCode.isEmpty ? '—' : Backend.pairingCode}',
                    'Application Expiry: $_appExpiry',
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xCC0B0607),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x66FFFFFF), width: 1.4),
                  ),
                  child: Text(
                    _playlistExpiry,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _offline && _account == null ? C.danger : C.text,
                    ),
                  ),
                ),
                const Spacer(),
                const _WeatherBox(),
              ],
            ),
          ],
        ),
      );
    });
  }
}

/// The open playlist's name as saved on the website, or the login name when it was typed in.
String playlistTitle(Source api) => Store.playlistName.isNotEmpty ? Store.playlistName : api.label;

/// Signs in with a playlist added on the website and remembers it.
Future<(Source, XAccount)> openSitePlaylist(BPlaylist p) async {
  final opened = await _openSite(p);
  await Store.setPlaylistName(p.name);
  await Store.setPlaylistId(p.id);
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
                          : const [Color(0xFFB81E26), Color(0xFFE3262F)],
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
                  ? const [Color(0xFFFF3B44), Color(0xD9C1323A), Color(0xB3707078)]
                  : const [Color(0xF2E3262F), Color(0xC0A0343A), Color(0x99606068)],
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
