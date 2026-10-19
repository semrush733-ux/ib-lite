import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../backend.dart';
import '../config.dart';
import '../engine.dart';
import '../enhance.dart';
import '../i18n.dart';
import '../network.dart';
import '../speedtest.dart';
import '../vpn.dart';
import '../parental.dart';
import '../report.dart';
import '../store.dart';
import '../streaming.dart';
import '../subtitle_style.dart';
import '../theme.dart';
import '../voice.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'home.dart' show wallpaperAsset;
import 'profiles.dart';

enum _Section { network, vpn, vod, live, subtitles, parental, profiles, wallpaper, categories, streaming, cache, language, info }

/// The Google Play build has no VPN section.
// The Google Play build has no VPN and no streaming-service boxes (a player for the customer's
// own media: no other companies' names on the home screen).
final _sections = [
  for (final s in _Section.values)
    if (!(kPlay && (s == _Section.vpn || s == _Section.streaming))) s
];

const _titles = {
  _Section.network: 'Network',
  _Section.vpn: 'VPN',
  _Section.vod: 'VOD Player',
  _Section.live: 'Live Player',
  _Section.subtitles: 'Subtitles',
  _Section.parental: 'Parental Control',
  _Section.profiles: 'Profiles',
  _Section.wallpaper: 'Main Wallpaper',
  _Section.categories: 'Manage Categories',
  _Section.streaming: 'Streaming Boxes',
  _Section.cache: 'Clear Cache',
  _Section.language: 'Language',
  _Section.info: 'Application Info',
};

const _icons = {
  _Section.network: Icons.wifi_rounded,
  _Section.vpn: Icons.vpn_lock_rounded,
  _Section.vod: Icons.movie_creation_rounded,
  _Section.live: Icons.live_tv_rounded,
  _Section.subtitles: Icons.closed_caption_rounded,
  _Section.parental: Icons.family_restroom_rounded,
  _Section.profiles: Icons.people_alt_rounded,
  _Section.wallpaper: Icons.photo_library_rounded,
  _Section.language: Icons.translate_rounded,
  _Section.categories: Icons.dashboard_customize_rounded,
  _Section.streaming: Icons.subscriptions_rounded,
  _Section.cache: Icons.cleaning_services_rounded,
  _Section.info: Icons.info_rounded,
};

// Each section has its own colour, like the app icons on a phone.
const _colors = {
  _Section.network: Color(0xFF1E88FF),
  _Section.vpn: Color(0xFF14B8A6),
  _Section.vod: Color(0xFFFF8A00),
  _Section.live: Color(0xFFFF3B4E),
  _Section.subtitles: Color(0xFFFACC15),
  _Section.parental: Color(0xFF22C55E),
  _Section.profiles: Color(0xFF38BDF8),
  _Section.wallpaper: Color(0xFFD946EF),
  _Section.language: Color(0xFF06B6D4),
  _Section.categories: Color(0xFF6366F1),
  _Section.streaming: Color(0xFFEF4444),
  _Section.cache: Color(0xFF8B5CF6),
  _Section.info: Color(0xFFF5B400),
};

/// App settings, opened from the gear on the home screen: a box for every section; a box opens
/// that section on its own page, and Back (button or remote) returns to the boxes.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});
  final Source api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _Section? _section;
  _Section? _last;
  XKind _kind = XKind.live;
  final Map<XKind, List<XCategory>> _cats = {};
  final Map<XKind, String> _catsError = {};
  bool _clearing = false;
  String _cacheNote = '';

  @override
  void initState() {
    super.initState();
    log('screen=settings');
  }

  Future<void> _loadCats(XKind kind) async {
    if (_cats.containsKey(kind)) return;
    try {
      final list = Store.sortCategories(kind, await widget.api.categories(kind));
      Store.noteCategories(kind, list);
      if (!mounted) return;
      setState(() => _cats[kind] = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _catsError[kind] = friendlyError(e));
    }
  }

  void _open(_Section s) {
    if (s == _Section.profiles) {
      // Profiles have their own screen ("Who's watching?", with Add / change / delete).
      setState(() => _last = s);
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => ProfilesScreen(api: widget.api)))
          .then((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {
      _section = s;
      _last = s;
    });
    if (s == _Section.parental || s == _Section.categories) _loadCats(_kind);
  }

  /// From a section page back to the boxes (the remote's Back key does the same).
  void _close() => setState(() => _section = null);

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final small = MediaQuery.of(context).size.width < 900;
    final section = _section;
    return PopScope(
      canPop: section == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _section != null) _close();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: small ? const EdgeInsets.fromLTRB(18, 16, 18, 10) : const EdgeInsets.fromLTRB(44, 30, 44, 22),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: section == null ? _grid(small) : _page(section),
            ),
          ),
        ),
      ),
    );
  }

  Widget _backButton(VoidCallback onTap, {bool autofocus = false}) => TvFocus(
        autofocus: autofocus,
        radius: 24,
        color: C.panel,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_back_rounded, color: C.text, size: 22),
              const SizedBox(width: 8),
              Text(t('Back'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  /// The settings home: one box per section.
  Widget _grid(bool small) {
    return Column(
      key: const ValueKey('grid'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _backButton(() => Navigator.of(context).maybePop()),
            const SizedBox(width: 18),
            const _OnceIcon(icon: Icons.settings_rounded, color: C.accent, size: 24, order: 0),
            const SizedBox(width: 12),
            Text(t('Settings'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth < 520 ? 2 : (box.maxWidth < 700 ? 3 : 5);
            const gap = 16.0;
            final w = (box.maxWidth - gap * (cols - 1)) / cols;
            final rows = (_sections.length / cols).ceil();
            // All boxes on one screen when there is room; never smaller than 96 px.
            final tileH = ((box.maxHeight - gap * (rows - 1)) / rows).clamp(96.0, small ? 120.0 : 170.0).toDouble();
            return SingleChildScrollView(
              child: Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final s in _sections)
                    SizedBox(
                      width: w,
                      height: tileH,
                      child: TvFocus(
                        autofocus: s == (_last ?? _Section.network),
                        radius: 18,
                        color: C.panel,
                        onTap: () => _open(s),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color.alphaBlend(_colors[s]!.withValues(alpha: 0.10), const Color(0xFF221A1D)), const Color(0xFF151012)],
                            ),
                            border: Border.all(color: const Color(0x22FFFFFF)),
                          ),
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _OnceIcon(icon: _icons[s]!, color: _colors[s]!, size: small ? 28 : 36, order: s.index + 1),
                              const SizedBox(height: 12),
                              Text(t(_titles[s]!),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: small ? 14.5 : 16, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  /// One section on its own page, with Back to the boxes.
  Widget _page(_Section s) {
    return Column(
      key: ValueKey(s),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _backButton(_close, autofocus: true),
            const SizedBox(width: 18),
            _OnceIcon(icon: _icons[s]!, color: _colors[s]!, size: 24, order: 0),
            const SizedBox(width: 12),
            Expanded(
              child: Text(t(_titles[s]!),
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    switch (_section!) {
      case _Section.network:
        return const _NetworkPanel();
      case _Section.vpn:
        return const _VpnPanel();
      case _Section.vod:
        return _playerChoice(
          current: ExoEngine.available ? Store.engine : 'mpv',
          onPick: (e) => setState(() => Store.setEngine(e)),
          what: 'Movies and series',
          withMode: true,
        );
      case _Section.live:
        return _playerChoice(
          current: ExoEngine.available ? Store.liveEngine : 'mpv',
          onPick: (e) => setState(() => Store.setLiveEngine(e)),
          what: 'Live TV channels and the channel preview',
          withMode: false,
          live: true,
        );
      case _Section.subtitles:
        return _subtitles();
      case _Section.parental:
        return _parental();
      case _Section.profiles:
        return const SizedBox.shrink(); // opens its own screen
      case _Section.wallpaper:
        return _wallpapers();
      case _Section.categories:
        return _categories();
      case _Section.streaming:
        return _streaming();
      case _Section.language:
        return _languages();
      case _Section.cache:
        return _cache();
      case _Section.info:
        return _info();
    }
  }

  // ----------------------------------------------------------------- players

  Widget _playerChoice({
    required String current,
    required ValueChanged<String> onPick,
    required String what,
    required bool withMode,
    bool live = false,
  }) {
    final exo = ExoEngine.available;
    final mpvChosen = current == 'mpv';
    return ListView(
      children: [
        Text('Plays: $what', style: const TextStyle(fontSize: 14, color: C.dim)),
        const SizedBox(height: 14),
        if (exo)
          _option(
            selected: current == 'exo',
            icon: Icons.smart_display_rounded,
            iconColor: const Color(0xFF4AA3FF),
            title: 'Google ExoPlayer',
            badge: 'RECOMMENDED',
            text: 'Uses the TV\'s own video chip: smooth picture and quick start. Default.',
            onTap: () => onPick('exo'),
          ),
        const SizedBox(height: 10),
        _option(
          selected: mpvChosen,
          icon: Icons.memory_rounded,
          iconColor: const Color(0xFFB37BFF),
          title: 'MPV Player',
          text: 'Plays almost every format, Dolby (AC3) sound too. Choose it if something will not play well.',
          onTap: () => onPick('mpv'),
        ),
        const SizedBox(height: 16),
        const Text(
          'When a video will not start on the chosen player, the app tries the other one by itself. '
          'A channel whose sound ExoPlayer cannot play moves to MPV by itself, and stays there.',
          style: TextStyle(fontSize: 13.5, color: C.dim, height: 1.5),
        ),
        const SizedBox(height: 24),
        const Text('PICTURE ENHANCE',
            style: TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final m in const [('auto', 'Auto'), ('off', 'Off'), ('on', 'Always on')]) ...[
              _chip(m.$2, Store.enhanceMode == m.$1, () {
                Store.setEnhanceMode(m.$1);
                EnhanceLevel.reset();
                setState(() {});
              }),
              const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Sharper, crisper picture with a little more colour. Auto turns it on when this TV is strong '
          'enough and switches it off by itself the moment the picture would stutter.'
          '${Store.enhanceCap == 0 ? ' This TV: off (too heavy here).' : Store.enhanceCap > 0 ? ' This TV: up to ${EnhanceLevel.label(Store.enhanceCap)}.' : ''}',
          style: const TextStyle(fontSize: 13, color: C.dim, height: 1.45),
        ),
        const SizedBox(height: 24),
        const Text('MATCH FRAME RATE',
            style: TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        Row(
          children: [
            _chip('On', Store.matchFrameRate, () => setState(() => Store.setMatchFrameRate(true))),
            const SizedBox(width: 10),
            _chip('Off', !Store.matchFrameRate, () => setState(() => Store.setMatchFrameRate(false))),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Off by default. Turn it ON for a smoother picture: the TV switches to the frame rate of the '
          'channel (50 Hz for UK / European channels, 60 Hz for US) so moving pictures - football, '
          'news tickers, scrolling text - glide without judder or jerky movement.\n'
          '• Turn it ON if: the picture looks jerky or stutters on fast movement, or your TV / box is '
          'weaker and you want the best streaming experience.\n'
          '• Keep it OFF if: the screen goes black for a second every time you change channel, or your '
          'TV shows "no signal" / flickers when a channel starts.\n'
          'Works on Android TV boxes, Firestick and Android TVs that support it.',
          style: TextStyle(fontSize: 13, color: C.dim, height: 1.45),
        ),
        const SizedBox(height: 24),
        const Text('QUICK START FOR FILMS',
            style: TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        Row(
          children: [
            _chip('On', Store.vodPreload, () => setState(() => Store.setVodPreload(true))),
            const SizedBox(width: 10),
            _chip('Off', !Store.vodPreload, () => setState(() => Store.setVodPreload(false))),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'While you read a film\'s page, the film is already loaded in the background, so "Watch" '
          'starts straight away. It works only on TVs / boxes that are strong enough; weak ones skip '
          'it by themselves. Turn it off if your server allows only one connection and you watch '
          'live TV on another device at the same time.',
          style: TextStyle(fontSize: 13, color: C.dim, height: 1.45),
        ),
        if (withMode && mpvChosen) ...[
          const SizedBox(height: 24),
          const Text('MPV PICTURE MODE',
              style: TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          Row(
            children: [
              _chip('Direct (lighter)', Store.videoMode == 'direct', () => setState(() => Store.setVideoMode('direct'))),
              const SizedBox(width: 10),
              _chip('Standard', Store.videoMode == 'gpu', () => setState(() => Store.setVideoMode('gpu'))),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Use Standard if a video plays sound but shows no picture.',
              style: TextStyle(fontSize: 13, color: C.dim)),
        ],
        if (live) ...[
          const SizedBox(height: 24),
          Text(t('Start with the last channel').toUpperCase(),
              style: const TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          Row(
            children: [
              _chip('On', Store.startWithLastChannel, () => setState(() => Store.setStartWithLastChannel(true))),
              const SizedBox(width: 10),
              _chip('Off', !Store.startWithLastChannel, () => setState(() => Store.setStartWithLastChannel(false))),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Off by default. When it is on, the channel you watched last plays by itself when the app '
            'starts, with the other channels of its category (Up / Down go on from there). Back takes '
            'you to the home screen. Every profile has its own last channel.',
            style: TextStyle(fontSize: 13, color: C.dim, height: 1.45),
          ),
          const SizedBox(height: 24),
          const Text('REMOTE SHORTCUTS IN LIVE TV',
              style: TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          const Text(
            '• Fast-forward (⏩) or the Last / Recall key: back to the channel you watched just before. '
            'Press it again to switch back.\n'
            '• Rewind (⏪): Start Over - the programme on now plays from its beginning. Works on channels '
            'with catch-up (the server keeps recordings).\n'
            '• Up / Down: next / previous channel.  Left: channel list.  Right: audio and subtitles.\n'
            '• Guide or Info: TV Guide.  Hold OK: add to Favourites.\n'
            'Both are also buttons on the bar (press OK while watching).',
            style: TextStyle(fontSize: 13, color: C.dim, height: 1.55),
          ),
        ],
        const SizedBox(height: 24),
        Text(t('Voice control').toUpperCase(),
            style: const TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        Text(
          '• Fire TV (Alexa): while watching, hold the remote\'s Alexa (microphone) button and say "pause", '
          '"play", "rewind 30 seconds", "fast forward", "next", "previous" or "restart" (with an Echo: '
          '"Alexa, pause"). On live TV "next" / "previous" change the channel and "rewind" / "restart" '
          'start the programme over (channels with catch-up). Alexa cannot search inside the app: Amazon '
          'allows that only for its own catalogue.\n'
          '• Phones and Android / Google TV boxes: the microphone button (home screen, Search and the '
          'player bar). Say a channel, film or series to search it, or while watching: "next", "pause", '
          '"play", "back 30 seconds", "forward 2 minutes", "start over", "last channel", a channel name or '
          '"channel 25". The Google Assistant on Android TV also understands "pause", "next"...'
          '${Voice.canListen ? '' : '\nThis device has no speech screen for apps, so no microphone button is shown here.'}',
          style: const TextStyle(fontSize: 13, color: C.dim, height: 1.55),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- subtitles

  Widget _subtitles() {
    Widget row(String title, List<String> names, int selected, ValueChanged<int> pick) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.toUpperCase(),
                  style: const TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < names.length; i++)
                    _chip(names[i], i == selected, () {
                      pick(i);
                      SubtitleLook.changed();
                      setState(() {});
                    }),
                ],
              ),
            ],
          ),
        );
    return ListView(
      children: [
        const Text('How subtitles look in films, series and live channels, on both players.',
            style: TextStyle(fontSize: 13.5, color: C.dim)),
        const SizedBox(height: 14),
        const SubtitlePreview(),
        const SizedBox(height: 20),
        row('Size', SubtitleLook.sizeNames, Store.subSize, Store.setSubSize),
        row('Colour', SubtitleLook.colorNames, Store.subColor, Store.setSubColor),
        row('Background', SubtitleLook.backgroundNames, Store.subBackground, Store.setSubBackground),
        row('Position', SubtitleLook.positionNames, Store.subPosition, Store.setSubPosition),
        const Text(
          'Turn subtitles on in the player: OK (or Right) during a film, then Subtitles. "Higher" helps on TVs that '
          'cut off the bottom edge of the picture.',
          style: TextStyle(fontSize: 13, color: C.dim, height: 1.45),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- parental

  Future<void> _setPin() async {
    if (Store.parentalPin.isNotEmpty && !await askParentalPin(context, title: 'Current PIN')) return;
    if (!mounted) return;
    final pin = await askNewPin(context);
    if (pin == null || !mounted) return;
    Store.setParentalPin(pin);
    Store.parentalUnlocked = false;
    log('parental pin set');
    setState(() {});
    _toast('Parental PIN saved.');
  }

  Future<void> _removePin() async {
    if (!await askParentalPin(context, title: 'Current PIN')) return;
    Store.setParentalPin('');
    Store.parentalUnlocked = false;
    log('parental pin removed');
    if (mounted) setState(() {});
    _toast('Parental control is off.');
  }

  Future<void> _toggleLock(XCategory c) async {
    if (Store.parentalPin.isEmpty) {
      _toast('Set a PIN first.');
      await _setPin();
      if (Store.parentalPin.isEmpty) return;
    } else if (!await askParentalPin(context)) {
      return;
    }
    Store.setLocked(_kind, c.id, !Store.isLockMarked(_kind, c.id));
    if (mounted) setState(() {});
  }

  Widget _parental() {
    final hasPin = Store.parentalPin.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(hasPin ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: hasPin ? const Color(0xFF2ECC71) : C.dim, size: 20),
            const SizedBox(width: 8),
            Text(hasPin ? 'Parental control is ON' : 'Parental control is OFF  (no PIN set)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            _chip(hasPin ? 'Change PIN' : 'Set PIN', false, _setPin),
            if (hasPin) ...[const SizedBox(width: 10), _chip('Remove PIN', false, _removePin)],
          ],
        ),
        const SizedBox(height: 8),
        const Text('Locked categories ask for the PIN before they open, and their channels and titles are '
            'left out of "All" and Search.',
            style: TextStyle(fontSize: 13, color: C.dim)),
        const SizedBox(height: 14),
        _kindTabs(),
        const SizedBox(height: 12),
        Expanded(
          child: _catList(
            isOn: (c) => Store.isLockMarked(_kind, c.id),
            onIcon: Icons.lock_rounded,
            offIcon: Icons.lock_open_rounded,
            onColor: const Color(0xFF2ECC71),
            onTap: _toggleLock,
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- categories

  Widget _categories() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Untick a category to hide it everywhere in the app. Tick it again to bring it back. '
            'To move a category, hold OK on it in Live TV, Movies or Series.',
            style: TextStyle(fontSize: 13.5, color: C.dim)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _kindTabs()),
            if (Store.categoryOrder(_kind).isNotEmpty)
              _chip('Original order', false, () async {
                Store.setCategoryOrder(_kind, const []);
                final list = _cats[_kind];
                if (list != null) {
                  _cats.remove(_kind);
                  await _loadCats(_kind);
                }
                setState(() {});
              }),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _catList(
            isOn: (c) => !Store.isHiddenSetting(_kind, c.id),
            onIcon: Icons.check_box_rounded,
            offIcon: Icons.check_box_outline_blank_rounded,
            onColor: C.accent,
            onTap: (c) async {
              Store.setHidden(_kind, c.id, !Store.isHiddenSetting(_kind, c.id));
              setState(() {});
            },
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------- streaming boxes

  Widget _streaming() {
    return ListView(
      children: [
        const Text(
          'Switch on a service and its box appears on the home screen. The box shows the movies and series of that '
          'service from your own playlist: its categories named after the service, and — when the website has the film '
          'database (TMDB) set up — the service\'s titles found in your playlist.',
          style: TextStyle(fontSize: 13.5, color: C.dim, height: 1.45),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final s in kStreamingServices)
              SizedBox(
                width: 260,
                height: 54,
                child: TvFocus(
                  radius: 10,
                  color: C.panel,
                  selected: Store.streamingOn(s.id),
                  onTap: () {
                    Store.setStreamingOn(s.id, !Store.streamingOn(s.id));
                    StreamingFinder.clear();
                    setState(() {});
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(Store.streamingOn(s.id) ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                            size: 34, color: Store.streamingOn(s.id) ? C.accent : C.dim),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(s.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _kindTabs() {
    const names = {XKind.live: 'Live TV', XKind.vod: 'Movies', XKind.series: 'Series'};
    return Row(
      children: [
        for (final k in XKind.values) ...[
          _chip(names[k]!, _kind == k, () {
            setState(() => _kind = k);
            _loadCats(k);
          }),
          const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _catList({
    required bool Function(XCategory) isOn,
    required IconData onIcon,
    required IconData offIcon,
    required Color onColor,
    required Future<void> Function(XCategory) onTap,
  }) {
    final error = _catsError[_kind];
    if (error != null) return Text(error, style: const TextStyle(color: C.danger));
    final cats = _cats[_kind];
    if (cats == null) return const Loading();
    if (cats.isEmpty) return const Text('No categories.', style: TextStyle(color: C.dim));
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisExtent: 46,
        crossAxisSpacing: 10,
        mainAxisSpacing: 8,
      ),
      itemCount: cats.length,
      itemBuilder: (context, i) {
        final c = cats[i];
        final on = isOn(c);
        return TvFocus(
          radius: 9,
          color: C.panel,
          onTap: () => onTap(c),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(on ? onIcon : offIcon, size: 20, color: on ? onColor : C.dim),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: on ? C.text : C.dim, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------- wallpaper

  Widget _wallpapers() {
    final current = Store.wallpaper;
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 16 / 9,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: 21,
      itemBuilder: (context, i) {
        final on = current == i;
        return TvFocus(
          autofocus: on,
          selected: on,
          radius: 12,
          color: Colors.black,
          onTap: () {
            Store.setWallpaper(i);
            log('settings wallpaper=$i');
            setState(() {});
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(wallpaperAsset(i), fit: BoxFit.cover, cacheWidth: 400, filterQuality: FilterQuality.medium),
                if (i == 0)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(5)),
                      child: Text(t('Default'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ),
                if (on)
                  const Positioned(
                    right: 8,
                    top: 8,
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: C.accent,
                      child: Icon(Icons.check_rounded, size: 18, color: C.onAccent),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- language

  Widget _languages() {
    final chosen = Store.uiLanguage;
    final entries = <(String, String, String)>[('auto', t('Automatic (TV language)'), ''), ...kLanguages];
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 54,
        crossAxisSpacing: 10,
        mainAxisSpacing: 8,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final (code, english, own) = entries[i];
        final on = chosen == code;
        return TvFocus(
          autofocus: on,
          selected: on,
          radius: 10,
          color: C.panel,
          onTap: () {
            Store.setUiLanguage(code);
            log('settings language=$code');
            setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    size: 18, color: on ? C.accent : C.dim),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(own.isEmpty ? english : own,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      if (own.isNotEmpty && own != english)
                        Text(english, style: const TextStyle(fontSize: 11.5, color: C.dim)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------- cache

  Future<void> _clearCache() async {
    if (_clearing) return;
    setState(() {
      _clearing = true;
      _cacheNote = '';
    });
    try {
      await Backend.clearAppCache();
      _cacheNote = 'Done. Pictures, guide and temporary files were cleared.';
    } catch (_) {
      _cacheNote = 'The cache could not be cleared completely.';
    }
    log('settings cache cleared');
    if (mounted) setState(() => _clearing = false);
  }

  Widget _cache() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Removes saved pictures (logos, posters), guide data and temporary files. Your login, '
          'favourites and settings stay. Use it when pictures look old or the app feels slow.',
          style: TextStyle(fontSize: 14, color: C.dim, height: 1.5),
        ),
        const SizedBox(height: 20),
        TvFocus(
          radius: 12,
          color: const Color(0xFF2A2140),
          onTap: _clearCache,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _clearing
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: C.accent))
                    : const Icon(Icons.cleaning_services_rounded, color: Color(0xFFB37BFF)),
                const SizedBox(width: 12),
                Text(t('Clear cache now'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
        if (_cacheNote.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(_cacheNote, style: const TextStyle(fontSize: 14, color: Color(0xFF2ECC71))),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------- info

  Widget _info() {
    String two(int v) => v.toString().padLeft(2, '0');
    final end = Backend.licExpiry;
    final String expiry;
    switch (Backend.licStatus) {
      case 'trial':
      case 'active':
        expiry = Backend.licType == 'lifetime'
            ? 'Lifetime (never expires)'
            : end == null
                ? 'Never'
                : '${two(end.day)}-${two(end.month)}-${end.year}  (${Backend.licDaysLeft} days left'
                    '${Backend.licStatus == 'trial' ? ', free trial' : ''})';
      case 'expired':
        expiry = 'Ended';
      case 'suspended':
        expiry = 'Suspended';
      default:
        expiry = 'Unknown (no answer from the website yet)';
    }
    final rows = <List<String>>[
      ['Application', kAppName],
      ['Version', Backend.appVersionName.isEmpty ? '—' : Backend.appVersionName],
      ['Version code', Backend.appVersionCode > 0 ? '${Backend.appVersionCode}' : '—'],
      ['MAC Address', Backend.deviceId.isEmpty ? '—' : Backend.deviceId],
      ['Licence', Backend.statusLine.isEmpty ? '—' : Backend.statusLine],
      ['Expires', expiry],
      ['Playlist', widget.api.label],
    ];
    return ListView(
      children: [
        for (final r in rows)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                SizedBox(width: 170, child: Text(r[0], style: const TextStyle(fontSize: 14.5, color: C.dim))),
                Expanded(
                  child: Text(r[1],
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: r[0] == 'Expires' && Backend.licStatus == 'expired' ? C.danger : C.text)),
                ),
              ],
            ),
          ),
        if (Backend.updateAvailable)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('A newer version is available: use "Update" on the home screen.',
                style: TextStyle(fontSize: 13.5, color: C.accent)),
          ),
        const SizedBox(height: 16),
        // Something does not work: the app's recent log and this TV's details go to the support team.
        Align(
          alignment: Alignment.centerLeft,
          child: TvFocus(
            radius: 12,
            color: const Color(0xFF2A1D10),
            onTap: () => showReportDialog(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.report_problem_rounded, color: Color(0xFFF5B400)),
                  const SizedBox(width: 12),
                  Text(t('Report a problem'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          t('Something does not work? Send a report: the app\'s recent log and this TV\'s details go to the support team (no passwords).'),
          style: const TextStyle(fontSize: 13, color: C.dim, height: 1.45),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- helpers

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 340,
        content: Text(text, textAlign: TextAlign.center),
      ));
  }

  Widget _option({
    required bool selected,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String text,
    required VoidCallback onTap,
    String badge = '',
  }) {
    return TvFocus(
      selected: selected,
      radius: 12,
      color: C.panel,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      if (badge.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: const Color(0x332ECC71), borderRadius: BorderRadius.circular(5)),
                          child: Text(badge,
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF2ECC71),
                                  letterSpacing: 0.6)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(text, style: const TextStyle(fontSize: 13, color: C.dim)),
                ],
              ),
            ),
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? C.accent : C.dim),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return TvFocus(
      selected: selected,
      radius: 20,
      color: C.panel,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        child: Text(label, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
      ),
    );
  }
}

/// An icon that spins and pops in once when it first appears, then stays still.
class _OnceIcon extends StatefulWidget {
  const _OnceIcon({super.key, required this.icon, required this.color, this.size = 24, this.order = 0});
  final IconData icon;
  final Color color;
  final double size;
  final int order;

  @override
  State<_OnceIcon> createState() => _OnceIconState();
}

class _OnceIconState extends State<_OnceIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: 80 * widget.order), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(_c.value);
        final m = Matrix4.identity()
          ..setEntry(3, 2, 0.002)
          ..rotateY((1 - _c.value) * 2 * math.pi)
          ..scaleByDouble(0.3 + 0.7 * t, 0.3 + 0.7 * t, 1, 1);
        return Opacity(
          opacity: _c.value.clamp(0.0, 1.0),
          child: Transform(alignment: Alignment.center, transform: m, child: child),
        );
      },
      child: SettingsBadge(icon: widget.icon, color: widget.color, size: widget.size),
    );
  }
}

/// A settings icon drawn like a real app icon: a rounded tile with a deep colour gradient,
/// a glossy light on top, a soft shadow below and a white symbol with its own shadow.
class SettingsBadge extends StatelessWidget {
  const SettingsBadge({super.key, required this.icon, required this.color, this.size = 24});
  final IconData icon;
  final Color color;
  final double size; // size of the symbol; the tile is a little larger

  @override
  Widget build(BuildContext context) {
    final box = size * 1.7;
    final hsl = HSLColor.fromColor(color);
    final light = hsl.withLightness((hsl.lightness + 0.14).clamp(0.0, 1.0)).toColor();
    final dark = hsl.withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0)).toColor();
    final r = BorderRadius.circular(box * 0.28);
    return Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [light, color, dark]),
        boxShadow: [
          BoxShadow(color: dark.withValues(alpha: 0.55), blurRadius: box * 0.28, offset: Offset(0, box * 0.1)),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1),
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Glossy light over the upper half.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: box * 0.5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white.withValues(alpha: 0.32), Colors.white.withValues(alpha: 0.0)],
                  ),
                ),
              ),
            ),
            Icon(icon, color: Colors.white, size: size, shadows: [
              Shadow(color: dark.withValues(alpha: 0.9), blurRadius: size * 0.25, offset: Offset(0, size * 0.06)),
            ]),
          ],
        ),
      ),
    );
  }
}


/// Settings › Network: the connection in use, the Wi-Fi networks around the TV, and joining one.
/// The Google Play build has no location permission (Android wants it for Wi-Fi scans), so it
/// shows the connection, the speed test and the TV's own Wi-Fi page, without the list of networks.
class _NetworkPanel extends StatefulWidget {
  const _NetworkPanel();

  @override
  State<_NetworkPanel> createState() => _NetworkPanelState();
}

class _NetworkPanelState extends State<_NetworkPanel> with WidgetsBindingObserver {
  NetInfo _info = const NetInfo();
  List<WifiNet>? _nets = const [];
  bool _scanning = false;
  bool _askedPermission = false;
  String _note = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh(scan: !kPlay);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the permission question or the TV's Wi-Fi page: look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(scan: !kPlay);
  }

  Future<void> _refresh({bool scan = false}) async {
    final info = await Net.info();
    if (!mounted) return;
    setState(() => _info = info);
    if (scan) await _scan();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    var nets = await Net.scan();
    if (nets != null && nets.isEmpty) {
      // A fresh scan takes a moment on most TVs: ask once more shortly after.
      await Future<void>.delayed(const Duration(seconds: 3));
      nets = await Net.scan();
    }
    if (!mounted) return;
    setState(() {
      _nets = nets;
      _scanning = false;
    });
    if (nets == null && !_askedPermission) {
      _askedPermission = true;
      await Net.askPermission();
    }
  }

  Future<void> _join(WifiNet n) async {
    if (!_info.canJoin) {
      setState(() => _note = 'This TV only lets its own Wi-Fi page join networks. Opening it now…');
      await Net.openSettings();
      return;
    }
    var password = '';
    if (n.secured) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: C.panel,
          title: Text(n.ssid),
          content: SizedBox(
            width: 380,
            child: TvField(
              controller: controller,
              label: 'Wi-Fi password',
              icon: Icons.key_rounded,
              obscure: true,
              autofocus: true,
              action: TextInputAction.done,
              onSubmitted: (_) => Navigator.of(ctx).pop(true),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Connect')),
          ],
        ),
      );
      password = controller.text;
      controller.dispose();
      if (ok != true || !mounted) return;
    }
    setState(() => _note = 'Connecting to ${n.ssid}…');
    final r = await Net.join(n.ssid, password, n.secured);
    if (!mounted) return;
    if (r == 'failed') {
      setState(() => _note = 'Could not connect to ${n.ssid}. Check the password and try again.');
      return;
    }
    if (r == 'settings') return;
    // Give the TV a few seconds to connect, then show the result.
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final info = await Net.info();
      if (!mounted) return;
      setState(() => _info = info);
      if (info.type == 'wifi' && info.ssid == n.ssid) {
        setState(() => _note = 'Connected to ${n.ssid}.');
        return;
      }
    }
    setState(() => _note = 'Still connecting… If it does not connect, check the password.');
  }

  Widget _bars(int level, {double size = 20, Color? color}) => WifiSignal(level: level, size: size);


  @override
  Widget build(BuildContext context) {
    final i = _info;
    final connected = i.type != 'none';
    final title = switch (i.type) {
      'wifi' => i.ssid.isEmpty ? 'Wi-Fi' : i.ssid,
      'ethernet' => 'Cable (Ethernet)',
      'mobile' => 'Mobile data',
      'none' => 'Not connected',
      _ => 'Connected',
    };
    final details = <String>[
      if (i.type == 'wifi' && i.linkMbps > 0) '${i.linkMbps} Mbit/s',
      if (i.type == 'wifi' && i.frequency > 0) i.frequency > 4900 ? '5 GHz' : '2.4 GHz',
      if (i.ip.isNotEmpty) 'IP ${i.ip}',
    ];
    final nets = _nets;
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: C.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: connected ? const Color(0x552ECC71) : const Color(0x55FF6B6B)),
          ),
          child: Row(
            children: [
              if (i.type == 'wifi')
                _bars(i.level, size: 40)
              else
                Icon(i.type == 'ethernet' ? Icons.settings_ethernet_rounded : (connected ? Icons.public_rounded : Icons.wifi_off_rounded),
                    size: 40, color: connected ? const Color(0xFF2ECC71) : C.danger),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(connected ? 'CONNECTED' : 'OFFLINE',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                            color: connected ? const Color(0xFF2ECC71) : C.danger)),
                    const SizedBox(height: 2),
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    if (details.isNotEmpty)
                      Text(details.join('   ·   '), style: const TextStyle(fontSize: 13.5, color: C.dim)),
                  ],
                ),
              ),
              TvFocus(
                radius: 10,
                color: C.card,
                onTap: () => showSpeedTest(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.speed_rounded, size: 17, color: C.accent),
                      SizedBox(width: 8),
                      Text('Speed test', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TvFocus(
                radius: 10,
                color: C.card,
                onTap: Net.openSettings,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.settings_rounded, size: 17, color: C.dim),
                      SizedBox(width: 8),
                      Text('TV Wi-Fi settings', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (kPlay) ...[
          const SizedBox(height: 16),
          const Text('To join another Wi-Fi network, open the TV Wi-Fi settings.',
              style: TextStyle(fontSize: 13.5, color: C.dim, height: 1.5)),
        ] else ...[
        const SizedBox(height: 20),
        Row(
          children: [
            const Text('NEARBY WI-FI NETWORKS',
                style: TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const SizedBox(width: 14),
            if (_scanning)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
            const Spacer(),
            TvFocus(
              radius: 18,
              color: C.panel,
              onTap: () => _refresh(scan: true),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 17, color: C.accent),
                    SizedBox(width: 6),
                    Text('Scan again', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_note.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_note, style: const TextStyle(fontSize: 13.5, color: C.accent)),
        ],
        const SizedBox(height: 12),
        if (!Net.available)
          const Text('Network settings are available in the Android app.', style: TextStyle(color: C.dim))
        else if (nets == null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'To list Wi-Fi networks, Android needs the "location" permission for this app '
                '(it is only used for the Wi-Fi list).',
                style: TextStyle(fontSize: 13.5, color: C.dim, height: 1.5),
              ),
              const SizedBox(height: 10),
              TvFocus(
                radius: 10,
                color: C.card,
                onTap: Net.askPermission,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text('Allow', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          )
        else if (nets.isEmpty && !_scanning)
          Text(i.wifiOn ? 'No Wi-Fi networks found yet. Press "Scan again".' : 'Wi-Fi is switched off on this TV.',
              style: const TextStyle(color: C.dim))
        else ...[
          if (_best(nets, i) case final best?)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TvFocus(
                radius: 12,
                color: const Color(0xFF12301F),
                onTap: () => _join(best),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: Color(0xFF2ECC71), size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            const TextSpan(text: 'Stronger network nearby: ', style: TextStyle(color: C.dim)),
                            TextSpan(text: best.ssid, style: const TextStyle(fontWeight: FontWeight.w800)),
                            TextSpan(text: '  ·  ${signalWord(best.level)}', style: TextStyle(color: signalColor(best.level))),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14.5),
                        ),
                      ),
                      const Text('Switch', style: TextStyle(color: Color(0xFF2ECC71), fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          for (final n in _sorted(nets))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TvFocus(
                radius: 10,
                color: C.panel,
                selected: i.type == 'wifi' && i.ssid == n.ssid,
                onTap: () => _join(n),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    children: [
                      _bars(n.level),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(n.ssid,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                ),
                                if (identical(n, _sorted(nets).first) && n.level >= 3) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0x332ECC71),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: const Color(0x882ECC71)),
                                    ),
                                    child: const Text('Recommended',
                                        style: TextStyle(fontSize: 11, color: Color(0xFF2ECC71), fontWeight: FontWeight.w800)),
                                  ),
                                ],
                              ],
                            ),
                            Text(signalWord(n.level),
                                style: TextStyle(fontSize: 12, color: signalColor(n.level), fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      if (i.type == 'wifi' && i.ssid == n.ssid)
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Text('Connected',
                              style: TextStyle(fontSize: 12.5, color: Color(0xFF2ECC71), fontWeight: FontWeight.w800)),
                        ),
                      Text(n.band, style: const TextStyle(fontSize: 12, color: C.dim)),
                      const SizedBox(width: 10),
                      Icon(n.secured ? Icons.lock_rounded : Icons.lock_open_rounded, size: 16, color: C.dim),
                    ],
                  ),
                ),
              ),
            ),
        ],
        ],
      ],
    );
  }

  /// Strongest first; at equal strength 5 GHz first (faster).
  List<WifiNet> _sorted(List<WifiNet> nets) {
    final l = List<WifiNet>.of(nets);
    l.sort((a, b) {
      final c = b.level.compareTo(a.level);
      if (c != 0) return c;
      return (b.band.startsWith('5') ? 1 : 0).compareTo(a.band.startsWith('5') ? 1 : 0);
    });
    return l;
  }

  /// A clearly stronger network than the one in use (at least one bar more), worth switching to.
  WifiNet? _best(List<WifiNet> nets, NetInfo i) {
    if (nets.isEmpty) return null;
    final top = _sorted(nets).first;
    if (i.type == 'wifi' && i.ssid == top.ssid) return null;
    if (top.level < 3) return null;
    if (i.type == 'wifi' && top.level <= i.level) return null;
    if (i.type == 'ethernet') return null;
    return top;
  }
}


/// Settings › VPN: the customer's own WireGuard VPN (from their VPN provider), added from the
/// website, a link, or typed in; connect / disconnect for the whole TV.
class _VpnPanel extends StatefulWidget {
  const _VpnPanel();

  @override
  State<_VpnPanel> createState() => _VpnPanelState();
}

class _VpnPanelState extends State<_VpnPanel> {
  List<VpnProfile> _list = const [];
  String _busy = '';
  String _note = '';
  bool _noteBad = false;

  @override
  void initState() {
    super.initState();
    Vpn.state.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    Vpn.state.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await Vpn.refresh();
    final list = await Vpn.profiles();
    if (Vpn.activeName.isEmpty) Vpn.activeName = await Vpn.lastUsed();
    if (mounted) setState(() => _list = list);
  }

  void _say(String text, {bool bad = false}) {
    if (mounted) {
      setState(() {
        _note = text;
        _noteBad = bad;
      });
    }
  }

  Future<void> _addConfig(String name, String config) async {
    final problem = await Vpn.check(config);
    if (problem.isNotEmpty) {
      _say('This is not a valid WireGuard configuration: $problem', bad: true);
      return;
    }
    await Vpn.add(VpnProfile(name.trim().isEmpty ? 'My VPN' : name.trim(), config));
    await _load();
    _say('"${name.trim().isEmpty ? 'My VPN' : name.trim()}" was added. Select it to connect.');
  }

  Future<void> _fromSite() async {
    setState(() => _busy = 'site');
    try {
      final v = await Backend.vpnFromSite();
      if (v == null) {
        _say('No VPN is saved on the website for this TV yet. Add it on the website: Upload Playlist › VPN.',
            bad: true);
      } else {
        await _addConfig(v['name']!, v['config']!);
      }
    } catch (e) {
      _say('The website could not be reached.', bad: true);
    }
    if (mounted) setState(() => _busy = '');
  }

  Future<String?> _ask(String title, String label, IconData icon) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: TvField(
            controller: c,
            label: label,
            icon: icon,
            autofocus: true,
            action: TextInputAction.done,
            onSubmitted: (_) => Navigator.of(ctx).pop(true),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('OK')),
        ],
      ),
    );
    final text = c.text;
    c.dispose();
    return ok == true ? text : null;
  }

  Future<void> _fromLink() async {
    final url = await _ask('VPN configuration link', 'Link to the .conf file', Icons.link_rounded);
    if (url == null || url.trim().isEmpty) return;
    setState(() => _busy = 'link');
    try {
      final text = await Vpn.download(url);
      final parts = Uri.tryParse(url.trim())?.pathSegments.where((x) => x.isNotEmpty).toList() ?? const <String>[];
      final name = parts.isEmpty ? 'My VPN' : parts.last;
      await _addConfig(name.replaceAll(RegExp(r'\.conf$'), ''), text);
    } catch (e) {
      _say(e is FormatException ? e.message : 'The link could not be downloaded.', bad: true);
    }
    if (mounted) setState(() => _busy = '');
  }

  Future<void> _connect(VpnProfile p) async {
    if (Vpn.state.value == 'up' && Vpn.activeName == p.name) {
      setState(() => _busy = p.name);
      final err = await Vpn.disconnect();
      _say(err.isEmpty ? 'VPN switched off.' : err, bad: err.isNotEmpty);
    } else {
      setState(() => _busy = p.name);
      if (Vpn.state.value == 'up') await Vpn.disconnect();
      final err = await Vpn.connect(p);
      _say(err.isEmpty ? 'Connected through "${p.name}". All apps on this TV now use the VPN.' : err,
          bad: err.isNotEmpty);
    }
    if (mounted) setState(() => _busy = '');
  }

  Future<void> _delete(VpnProfile p) async {
    if (Vpn.state.value == 'up' && Vpn.activeName == p.name) await Vpn.disconnect();
    await Vpn.remove(p.name);
    await _load();
    _say('"${p.name}" was removed.');
  }

  Widget _action(IconData icon, String label, VoidCallback onTap, {bool busy = false}) => TvFocus(
        radius: 10,
        color: C.card,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent))
                  : Icon(icon, size: 17, color: C.accent),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final up = Vpn.state.value == 'up';
    if (!Vpn.available) {
      return const Text('The VPN works in the Android app.', style: TextStyle(color: C.dim));
    }
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: C.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: up ? const Color(0x772ECC71) : const Color(0x33FFFFFF)),
          ),
          child: Row(
            children: [
              Icon(up ? Icons.vpn_lock_rounded : Icons.lock_open_rounded,
                  size: 40, color: up ? const Color(0xFF2ECC71) : C.dim),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(up ? 'VPN ON' : 'VPN OFF',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                            color: up ? const Color(0xFF2ECC71) : C.dim)),
                    Text(up ? Vpn.activeName : 'Not protected',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              if (up) _action(Icons.power_settings_new_rounded, 'Switch off', () async {
                    await Vpn.disconnect();
                    _say('VPN switched off.');
                  }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Use the WireGuard VPN from your VPN provider (most providers offer a WireGuard ".conf" file). '
          'Add it once, then select it here to connect. The VPN covers every app on this TV.',
          style: TextStyle(fontSize: 13.5, color: C.dim, height: 1.5),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _action(Icons.language_rounded, 'Get from website', _fromSite, busy: _busy == 'site'),
            _action(Icons.link_rounded, 'Add from link', _fromLink, busy: _busy == 'link'),
          ],
        ),
        if (_note.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(_note, style: TextStyle(fontSize: 13.5, color: _noteBad ? C.danger : const Color(0xFF2ECC71))),
        ],
        const SizedBox(height: 18),
        const Text('MY VPNS',
            style: TextStyle(fontSize: 13, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        if (_list.isEmpty)
          const Text('No VPN added yet.', style: TextStyle(color: C.dim))
        else
          for (final p in _list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TvFocus(
                      radius: 10,
                      color: C.panel,
                      selected: up && Vpn.activeName == p.name,
                      onTap: () => _connect(p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            _busy == p.name
                                ? const SizedBox(
                                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent))
                                : Icon(Icons.shield_rounded,
                                    color: up && Vpn.activeName == p.name ? const Color(0xFF2ECC71) : C.dim),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                                  if (p.server.isNotEmpty)
                                    Text(p.server, style: const TextStyle(fontSize: 12.5, color: C.dim)),
                                ],
                              ),
                            ),
                            Text(up && Vpn.activeName == p.name ? 'Connected · OK to switch off' : 'OK to connect',
                                style: const TextStyle(fontSize: 12.5, color: C.dim)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TvFocus(
                    radius: 10,
                    color: C.panel,
                    onTap: () => _delete(p),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.delete_outline_rounded, color: C.dim, size: 20),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}


/// Colour for a Wi-Fi strength (0..4 bars): green strong, yellow-green good, amber fair, red weak.
Color signalColor(int level) => switch (level.clamp(0, 4)) {
      4 => const Color(0xFF22C55E),
      3 => const Color(0xFF84CC16),
      2 => const Color(0xFFF5A524),
      1 => const Color(0xFFFF6B3D),
      _ => const Color(0xFFEF4444),
    };

String signalWord(int level) => switch (level.clamp(0, 4)) {
      4 => 'Excellent signal',
      3 => 'Good signal',
      2 => 'Fair signal',
      1 => 'Weak signal',
      _ => 'Very weak',
    };

/// Wi-Fi strength drawn like the phone status bar: a dot and three arcs, the lit ones in the
/// strength colour, the rest dim.
class WifiSignal extends StatelessWidget {
  const WifiSignal({super.key, required this.level, this.size = 20});
  final int level;
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size * 1.25, height: size, child: CustomPaint(painter: _WifiPainter(level.clamp(0, 4), signalColor(level))));
}

class _WifiPainter extends CustomPainter {
  _WifiPainter(this.level, this.color);
  final int level;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height * 0.92);
    final off = Paint()..color = const Color(0x33FFFFFF);
    final on = Paint()..color = color;
    // Dot (level >= 1), then arcs for levels 2..4.
    canvas.drawCircle(c - Offset(0, s.height * 0.08), s.height * 0.11, level >= 1 ? on : off);
    for (var i = 1; i <= 3; i++) {
      final r = s.height * (0.26 + 0.24 * i);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.height * 0.13
        ..strokeCap = StrokeCap.round
        ..color = level >= i + 1 ? color : const Color(0x33FFFFFF);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi * 0.75, math.pi * 0.5, false, p);
    }
  }

  @override
  bool shouldRepaint(_WifiPainter o) => o.level != level || o.color != color;
}
