import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'xtream.dart';

/// Small on-device storage: login, favourites, resume positions.
class Store {
  static late SharedPreferences _p;
  static final Map<XKind, List<XItem>> _fav = {};
  static Map<String, int>? _resume;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    _fav.clear();
    _recent.clear();
    _resume = null;
    _cw = null;
    _kids = null;
  }

  // ---- profiles ----
  // Each profile has its own favourites, recently watched, resume positions and Continue
  // Watching. The first profile ("main") keeps the keys the app always used, so nothing changes
  // for a customer with one profile; the others store theirs under "p:<id>:".

  /// Id of the profile in use.
  static String get profileId => _p.getString('profile_active') ?? 'main';

  /// True while a Kids profile is in use: only categories for children are shown.
  static bool get kidsMode => _p.getBool('profile_kids') ?? false;

  static String _pk(String key) {
    final id = profileId;
    return id == 'main' ? key : 'p:$id:$key';
  }

  /// The profiles as saved (JSON, read by Profiles in profiles.dart); '' = only the main one.
  static String get profilesJson => _p.getString('profiles') ?? '';
  static Future<void> setProfilesJson(String json) => _p.setString('profiles', json);

  /// Ask "Who's watching?" when the app starts (only when there is more than one profile).
  static bool get askProfileAtStart => _p.getBool('profile_ask') ?? true;
  static Future<void> setAskProfileAtStart(bool v) => _p.setBool('profile_ask', v);

  /// Switches to another profile: its own lists are read from now on.
  static Future<void> setProfile(String id, {required bool kids}) async {
    await _p.setString('profile_active', id);
    await _p.setBool('profile_kids', kids);
    _fav.clear();
    _recent.clear();
    _resume = null;
    _cw = null;
    // Locked categories ask for the PIN again in the new profile.
    parentalUnlocked = false;
  }

  /// Forgets everything a deleted profile had saved.
  static Future<void> deleteProfileData(String id) async {
    if (id == 'main') return;
    for (final k in _p.getKeys().toList()) {
      if (k.startsWith('p:$id:')) await _p.remove(k);
    }
  }

  static bool _isPersonalKey(String k) {
    final base = k.startsWith('p:') ? k.substring(k.indexOf(':', 2) + 1) : k;
    return base == 'resume' ||
        base == 'cw' ||
        base == 'last_live' ||
        base.startsWith('fav_') ||
        base.startsWith('recent_');
  }

  // ---- login ----
  static String get server => _p.getString('server') ?? '';
  static String get username => _p.getString('username') ?? '';
  static String get password => _p.getString('password') ?? '';

  /// Address of the M3U playlist when the app is used with a playlist link.
  static String get m3uUrl => _p.getString('m3u_url') ?? '';

  /// XMLTV guide address for that playlist (set on the website, may be empty).
  static String get m3uEpgUrl => _p.getString('m3u_epg_url') ?? '';

  /// True when the saved login is an M3U playlist link, false for Xtream Codes.
  static bool get isM3u => _p.getString('mode') == 'm3u';

  static bool get loggedIn {
    if (!(_p.getBool('logged_in') ?? false)) return false;
    return isM3u ? m3uUrl.isNotEmpty : (server.isNotEmpty && username.isNotEmpty);
  }

  /// Favourites and resume positions belong to one account: a different
  /// account starts clean.
  static Future<void> _switchAccount(String identity) async {
    if (_p.getString('identity') == identity) return;
    // Favourites, recent, resume and Continue Watching of every profile belong to the old account.
    for (final k in _p.getKeys().toList()) {
      if (_isPersonalKey(k)) await _p.remove(k);
    }
    _fav.clear();
    _recent.clear();
    _resume = null;
    _cw = null;
    _kids = null;
    await _p.setString('identity', identity);
  }

  /// True when the saved login used the server address from the B1G website (the customer typed
  /// only username and password). Such a login follows the website when the address changes there.
  static bool get viaSite => _p.getBool('via_site') ?? false;

  /// Name of the open playlist as it is saved on the website ('' when signed in by hand).
  static String get playlistName => _p.getString('playlist_name') ?? '';
  static Future<void> setPlaylistName(String name) => _p.setString('playlist_name', name);

  /// Website id of the open playlist (0 when signed in by hand): the app follows changes to it.
  static int get playlistId => _p.getInt('playlist_id') ?? 0;
  static Future<void> setPlaylistId(int id) => _p.setInt('playlist_id', id);

  /// The website details (link, login) the open playlist was opened with.
  static String get playlistSig => _p.getString('playlist_sig') ?? '';
  static Future<void> setPlaylistSig(String v) => _p.setString('playlist_sig', v);

  static Future<void> saveSession(String server, String username, String password, {bool viaSite = false}) async {
    await _p.remove('playlist_name'); // set again by openSitePlaylist for website playlists
    await _p.remove('playlist_id');
    await _p.remove('playlist_sig');
    await _switchAccount('xtream|$server|$username');
    await _p.setString('mode', 'xtream');
    await _p.setString('server', server);
    await _p.setString('username', username);
    await _p.setString('password', password);
    await _p.setBool('via_site', viaSite);
    await _p.setBool('logged_in', true);
  }

  /// The provider moved to a new address: same account, so favourites and resume positions stay.
  static Future<void> moveServer(String server) async {
    await _p.setString('server', server);
    await _p.setString('identity', 'xtream|$server|$username');
  }

  static Future<void> saveM3uSession(String url, {String epgUrl = ''}) async {
    await _p.remove('playlist_name');
    await _p.remove('playlist_id');
    await _p.remove('playlist_sig');
    await _switchAccount('m3u|$url');
    await _p.setString('mode', 'm3u');
    await _p.setString('m3u_url', url);
    await _p.setString('m3u_epg_url', epgUrl);
    await _p.setBool('logged_in', true);
  }

  /// Keeps server and username so the next login is quicker.
  /// The website playlist this device had is gone: forget which one it was.
  static Future<void> forgetSitePlaylist() async {
    await _p.remove('playlist_id');
    await _p.remove('playlist_sig');
    await _p.remove('playlist_name');
  }

  static Future<void> logout() async {
    await _p.remove('password');
    await _p.setBool('logged_in', false);
  }

  // ---- favourites ----
  static List<XItem> favourites(XKind kind) {
    final cached = _fav[kind];
    if (cached != null) return cached;
    final list = <XItem>[];
    for (final raw in _p.getStringList(_pk('fav_${kind.name}')) ?? const <String>[]) {
      try {
        final item = XItem.fromJson(jsonDecode(raw));
        if (item != null) list.add(item);
      } catch (_) {}
    }
    _fav[kind] = list;
    return list;
  }

  static bool isFavourite(XItem item) => favourites(item.kind).any((f) => f.id == item.id);

  /// Returns true when the item is a favourite after the call.
  static bool toggleFavourite(XItem item) {
    final list = favourites(item.kind);
    final index = list.indexWhere((f) => f.id == item.id);
    if (index >= 0) {
      list.removeAt(index);
    } else {
      list.insert(0, item);
    }
    _p.setStringList(_pk('fav_${item.kind.name}'), list.map((f) => jsonEncode(f.toJson())).toList());
    return index < 0;
  }

  // ---- recently watched ----
  static final Map<XKind, List<XItem>> _recent = {};

  /// Last opened channels / movies / series of one kind, newest first.
  static List<XItem> recents(XKind kind) {
    final cached = _recent[kind];
    if (cached != null) return cached;
    final list = <XItem>[];
    for (final raw in _p.getStringList(_pk('recent_${kind.name}')) ?? const <String>[]) {
      try {
        final item = XItem.fromJson(jsonDecode(raw));
        if (item != null) list.add(item);
      } catch (_) {}
    }
    _recent[kind] = list;
    return list;
  }

  static void addRecent(XItem item) {
    final list = recents(item.kind);
    list.removeWhere((f) => f.id == item.id);
    list.insert(0, item);
    while (list.length > 30) {
      list.removeLast();
    }
    _p.setStringList(_pk('recent_${item.kind.name}'), list.map((f) => jsonEncode(f.toJson())).toList());
  }

  // ---- last live channel (per profile) ----
  /// The live channel watched last, null when there is none yet.
  static XItem? get lastLive {
    final raw = _p.getString(_pk('last_live'));
    if (raw == null || raw.isEmpty) return null;
    try {
      final item = XItem.fromJson(jsonDecode(raw));
      return item != null && item.kind == XKind.live ? item : null;
    } catch (_) {
      return null;
    }
  }

  static void setLastLive(XItem item) {
    if (item.kind != XKind.live) return;
    _p.setString(_pk('last_live'), jsonEncode(item.toJson()));
  }

  /// Settings › Live Player: the app opens the last channel by itself when it starts.
  static bool get startWithLastChannel => _p.getBool('start_last_channel') ?? false;
  static void setStartWithLastChannel(bool v) => _p.setBool('start_last_channel', v);

  // ---- order of the Movies / Series lists ----
  /// 'default' (as the server sends them), 'new' (recently added first), 'az', 'year'
  /// (newest year first) or 'rating' (best first).
  static String sortOrder(XKind kind) => _p.getString('sort_${kind.name}') ?? 'default';
  static void setSortOrder(XKind kind, String order) => _p.setString('sort_${kind.name}', order);

  // ---- resume positions (seconds) ----
  static Map<String, int> _loadResume() {
    final cached = _resume;
    if (cached != null) return cached;
    final map = <String, int>{};
    try {
      final data = jsonDecode(_p.getString(_pk('resume')) ?? '{}');
      if (data is Map) {
        data.forEach((k, v) {
          if (v is int) map[k.toString()] = v;
        });
      }
    } catch (_) {}
    _resume = map;
    return map;
  }

  static int resume(String key) => _loadResume()[key] ?? 0;

  static void setResume(String key, int seconds) {
    final map = _loadResume();
    map.remove(key);
    if (seconds > 0) {
      map[key] = seconds; // newest last
      while (map.length > 300) {
        map.remove(map.keys.first);
      }
    }
    _p.setString(_pk('resume'), jsonEncode(map));
  }

  // ---- Continue Watching (per profile) ----
  // Half-watched films and episodes for the row on the home screen, newest first. Plain JSON
  // maps here; continue_watching.dart reads and writes them.
  static List<Map<String, dynamic>>? _cw;

  static List<Map<String, dynamic>> continueRaw() {
    final cached = _cw;
    if (cached != null) return cached;
    final list = <Map<String, dynamic>>[];
    try {
      final data = jsonDecode(_p.getString(_pk('cw')) ?? '[]');
      if (data is List) {
        for (final e in data) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
    } catch (_) {}
    _cw = list;
    return list;
  }

  static void setContinueRaw(List<Map<String, dynamic>> list) {
    _cw = list;
    _p.setString(_pk('cw'), jsonEncode(list));
  }

  // ---- programme reminders (TV Guide, for the whole device) ----
  static String get remindersJson => _p.getString('reminders') ?? '[]';
  static Future<void> setRemindersJson(String json) => _p.setString('reminders', json);

  // ---- subtitle look (Settings › Subtitles) ----
  /// 0 small, 1 medium (standard), 2 large, 3 extra large.
  static int get subSize => (_p.getInt('sub_size') ?? 1).clamp(0, 3).toInt();
  static void setSubSize(int v) => _p.setInt('sub_size', v);

  /// 0 white, 1 yellow, 2 cyan, 3 green.
  static int get subColor => (_p.getInt('sub_color') ?? 0).clamp(0, 3).toInt();
  static void setSubColor(int v) => _p.setInt('sub_color', v);

  /// 0 soft shadow, 1 dark box behind the text, 2 black outline.
  static int get subBackground => (_p.getInt('sub_bg') ?? 0).clamp(0, 2).toInt();
  static void setSubBackground(int v) => _p.setInt('sub_bg', v);

  /// 0 at the bottom, 1 a little higher (TVs that cut off the edge of the picture).
  static int get subPosition => (_p.getInt('sub_pos') ?? 0).clamp(0, 1).toInt();
  static void setSubPosition(int v) => _p.setInt('sub_pos', v);

  // ---- playback ----
  /// Audio language picked last time (ISO code such as "eng"); empty = the stream's default.
  static String get audioLanguage => _p.getString('audio_lang') ?? '';
  static void setAudioLanguage(String code) => _p.setString('audio_lang', code);

  /// How the picture is drawn: "gpu" (standard, works with every video format) or "direct"
  /// (the device's hardware decoder draws straight to the screen: lightest for weak TV sticks,
  /// and the fallback when the standard way cannot start on a device).
  static String get videoMode {
    final v = _p.getString('video_mode') ?? '';
    if (v == 'direct' || v == 'gpu') return v;
    // Direct by default: lightest for TV hardware and avoids slow/out-of-sync
    // video on big screens. Emulator test builds keep the standard mode.
    return kNoAutoDirect ? 'gpu' : 'direct';
  }
  static void setVideoMode(String mode) => _p.setString('video_mode', mode);

  /// Which player engine plays streams: "exo" (Google ExoPlayer, the default on Android) or
  /// "mpv". The app's own controls are the same on both.
  static String get engine {
    final v = _p.getString('player_engine2') ?? '';
    if (v == 'exo' || v == 'mpv') return v;
    return 'exo';
  }
  static void setEngine(String engine) => _p.setString('player_engine2', engine);

  /// Smart buffer: how often streams of one server stopped to buffer (0 never … 6 often).
  /// Unknown servers start in the middle (1).
  static int stallScore(String host) => _p.getInt('stall_$host') ?? 1;
  static void setStallScore(String host, int v) => _p.setInt('stall_$host', v);

  /// Frame rate matching: the TV's screen follows the video (50 Hz for 25/50 fps channels...).
  static bool get matchFrameRate => _p.getBool('match_fps2') ?? false; // off unless the customer turns it on
  static void setMatchFrameRate(bool v) => _p.setBool('match_fps2', v);

  /// Picture Enhance: "auto" (on when the device is strong enough), "off" or "on".
  static String get enhanceMode {
    final v = _p.getString('enhance_mode') ?? '';
    return v == 'off' || v == 'on' ? v : 'auto';
  }
  static void setEnhanceMode(String v) => _p.setString('enhance_mode', v);

  /// The highest enhance level this device managed without stuttering (-1: not learned yet).
  static int get enhanceCap => _p.getInt('enhance_cap') ?? -1;
  static void setEnhanceCap(int v) => _p.setInt('enhance_cap', v);

  /// Windows: how the video chip decodes on this computer. '' = the usual way (the picture
  /// stays on the video chip); 'auto-copy' = learned that only the copy-back way works here.
  static String get winHwdec => _p.getString('win_hwdec') ?? '';
  static void setWinHwdec(String v) => _p.setString('win_hwdec', v);

  /// Windows: interlaced channels are deinterlaced (false: this computer could not keep up).
  static bool get winDeint => _p.getBool('win_deint') ?? true;
  static void setWinDeint(bool v) => _p.setBool('win_deint', v);

  /// Streams whose sound ExoPlayer cannot decode on this device: they play on MPV.
  static List<String> get exoNoSound => _p.getStringList('exo_no_sound') ?? const [];
  static void addExoNoSound(String key) {
    final l = [...exoNoSound.where((k) => k != key), key];
    _p.setStringList('exo_no_sound', l.length > 400 ? l.sublist(l.length - 400) : l);
  }

  /// Player for Live TV, chosen separately from the one for films and series ([engine]).
  static String get liveEngine {
    final v = _p.getString('live_engine') ?? '';
    if (v == 'exo' || v == 'mpv') return v;
    return 'exo';
  }
  static void setLiveEngine(String engine) => _p.setString('live_engine', engine);

  /// App language: "auto" (the TV's own language when the app has it, else English) or a code.
  static String get uiLanguage => _p.getString('ui_language') ?? 'auto';
  static void setUiLanguage(String code) => _p.setString('ui_language', code);

  /// Home screen wallpaper: 0 = the standard one, 1..20 = the pictures in assets/wallpapers.
  static int get wallpaper => _p.getInt('wallpaper') ?? 0;
  static void setWallpaper(int n) => _p.setInt('wallpaper', n);

  // ---- parental control and category management (per account) ----

  /// The PIN that unlocks locked categories; empty = parental control off.
  static String get parentalPin => _p.getString('parental_pin') ?? '';
  static void setParentalPin(String pin) => _p.setString('parental_pin', pin);

  /// The PIN was typed since the app started: locked categories stay open until the app closes.
  static bool parentalUnlocked = false;

  static String _catKey(XKind kind, String id) => '${kind.name}|$id';
  static String get _accountKey => _p.getString('identity') ?? '';

  static Set<String> _catSet(String name) => (_p.getStringList('$name|$_accountKey') ?? const <String>[]).toSet();

  static void _setCat(String name, XKind kind, String id, bool on) {
    final set = _catSet(name);
    final key = _catKey(kind, id);
    on ? set.add(key) : set.remove(key);
    _p.setStringList('$name|$_accountKey', set.toList());
  }

  /// Categories left out of the app: switched off in Settings › Manage categories, and in a Kids
  /// profile every category that is not for children.
  static bool isHidden(XKind kind, String id) =>
      _catSet('hidden_cats').contains(_catKey(kind, id)) || (kidsMode && !kidsAllowed(kind, id));

  /// Only the customer's own choice in Settings › Manage categories (no Kids profile rule).
  static bool isHiddenSetting(XKind kind, String id) => _catSet('hidden_cats').contains(_catKey(kind, id));
  static void setHidden(XKind kind, String id, bool hidden) => _setCat('hidden_cats', kind, id, hidden);

  // ---- categories for the Kids profile (per account) ----
  // Found by their names ("Kids", "Cartoons", "Family", "Disney"...) whenever the categories are
  // loaded, and the parent can switch any category on or off for children by hand.
  static ({Set<String> auto, Set<String> on, Set<String> off})? _kids;
  static String _kidsFor = '';

  static ({Set<String> auto, Set<String> on, Set<String> off}) get _kidsSets {
    final account = _accountKey;
    final cached = _kids;
    if (cached != null && _kidsFor == account) return cached;
    _kidsFor = account;
    return _kids = (auto: _catSet('kids_auto'), on: _catSet('kids_on'), off: _catSet('kids_off'));
  }

  /// May children see this category? The parent's choice first, else its name.
  static bool kidsAllowed(XKind kind, String id) {
    final key = _catKey(kind, id);
    final s = _kidsSets;
    if (s.off.contains(key)) return false;
    if (s.on.contains(key)) return true;
    return s.auto.contains(key);
  }

  /// Whether the parent chose this category by hand (true / false) or it follows its name (null).
  static bool? kidsChoice(XKind kind, String id) {
    final key = _catKey(kind, id);
    final s = _kidsSets;
    if (s.on.contains(key)) return true;
    if (s.off.contains(key)) return false;
    return null;
  }

  static void setKidsChoice(XKind kind, String id, bool? allowed) {
    _setCat('kids_on', kind, id, allowed == true);
    _setCat('kids_off', kind, id, allowed == false);
    _kids = null;
  }

  /// All hand-made choices of one kind go back to "by name".
  static void resetKidsChoices(XKind kind) {
    for (final name in const ['kids_on', 'kids_off']) {
      final set = _catSet(name)..removeWhere((k) => k.startsWith('${kind.name}|'));
      _p.setStringList('$name|$_accountKey', set.toList());
    }
    _kids = null;
  }

  static final RegExp _kidsWords = RegExp(
    r'\b(kids?|child|children|childrens|cartoons?|toons?|junior|jr|family|families|disney|pixar|dreamworks|'
    r'nick|nickelodeon|nickjr|cbeebies|cbbc|boomerang|baby|babies|kinder|kinderen|enfants?|infantil|infantiles|'
    r'bambini|dzieci|cocuk|çocuk|animation|animated|animados?|animación|animacion|dibujos)\b',
    caseSensitive: false,
  );
  static final RegExp _adultWords = RegExp(r'(adult|xxx|18\+|\+18|porn|sex|erot|for adults)', caseSensitive: false);

  /// A category name that is meant for children.
  static bool looksForKids(String name) => _kidsWords.hasMatch(name) && !_adultWords.hasMatch(name);

  /// Called whenever a category list arrives: the categories for children are noted by name.
  static void noteCategories(XKind kind, List<XCategory> cats) {
    final prefix = '${kind.name}|';
    final before = _catSet('kids_auto');
    final after = before.where((k) => !k.startsWith(prefix)).toSet()
      ..addAll([for (final c in cats) if (looksForKids(c.name)) _catKey(kind, c.id)]);
    if (after.length == before.length && after.containsAll(before)) return;
    _p.setStringList('kids_auto|$_accountKey', after.toList());
    _kids = null;
  }

  /// Categories behind the parental PIN.
  static bool isLocked(XKind kind, String id) =>
      parentalPin.isNotEmpty && _catSet('locked_cats').contains(_catKey(kind, id));
  static bool isLockMarked(XKind kind, String id) => _catSet('locked_cats').contains(_catKey(kind, id));
  static void setLocked(XKind kind, String id, bool locked) => _setCat('locked_cats', kind, id, locked);

  /// May this item be listed? Not in a hidden category, and not in a locked one while locked.
  static bool allowed(XItem item) =>
      !isHidden(item.kind, item.categoryId) && (parentalUnlocked || !isLocked(item.kind, item.categoryId));

  /// Streaming service boxes on the home screen (Settings › Streaming Boxes), off until switched on.
  static bool streamingOn(String id) => _p.getBool('stream_box_$id') ?? false;
  static void setStreamingOn(String id, bool on) => _p.setBool('stream_box_$id', on);

  /// The customer's own order of categories (hold OK on a category and move it).
  static List<String> categoryOrder(XKind kind) => _p.getStringList('cat_order|${kind.name}|$_accountKey') ?? const <String>[];
  static void setCategoryOrder(XKind kind, List<String> ids) => _p.setStringList('cat_order|${kind.name}|$_accountKey', ids);

  /// Categories in the customer's order: the moved ones where they were put, new ones after them.
  static List<XCategory> sortCategories(XKind kind, List<XCategory> cats) {
    final order = categoryOrder(kind);
    if (order.isEmpty) return cats;
    final rank = <String, int>{for (var i = 0; i < order.length; i++) order[i]: i};
    final known = cats.where((c) => rank.containsKey(c.id)).toList()..sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
    return [...known, ...cats.where((c) => !rank.containsKey(c.id))];
  }

  /// Subtitle language picked last time; empty = subtitles off.
  static String get subtitleLanguage => _p.getString('sub_lang') ?? '';
  static void setSubtitleLanguage(String code) => _p.setString('sub_lang', code);

  /// Stream format that worked last time for live channels: "ts" or "m3u8".
  static String get liveFormat => _p.getString('live_format') == 'm3u8' ? 'm3u8' : 'ts';

  static void setLiveFormat(String format) {
    if (format != liveFormat) _p.setString('live_format', format);
  }

  /// Film pages open the film in the background (paused) so "Watch" starts at once.
  static bool get vodPreload => _p.getBool('vod_preload') ?? true;
  static void setVodPreload(bool v) => _p.setBool('vod_preload', v);

  // ---- Fastest stream format per IPTV server (TS or HLS) ----
  // The player notes how long each format takes to show the picture; channels then open in the
  // faster one. Each server tries the other format once to learn it.
  static int formatMs(String host, String f) => _p.getInt('fmt_ms:$host:$f') ?? 0;
  static int formatCount(String host, String f) => _p.getInt('fmt_n:$host:$f') ?? 0;

  static void noteFormat(String host, String f, int ms) {
    if (host.isEmpty || (f != 'ts' && f != 'm3u8') || ms <= 0) return;
    final n = formatCount(host, f);
    final old = formatMs(host, f);
    _p.setInt('fmt_ms:$host:$f', n == 0 ? ms : (old * 3 + ms) ~/ 4);
    _p.setInt('fmt_n:$host:$f', (n + 1).clamp(0, 50));
  }

  static final Map<String, String> _fmtSession = {};

  /// The format to try first on this server ([fallback]: the general choice).
  static String bestFormat(String host, String fallback) {
    if (host.isEmpty) return fallback;
    final known = _fmtSession[host];
    if (known != null) return known;
    final other = fallback == 'ts' ? 'm3u8' : 'ts';
    String pick = fallback;
    final a = formatCount(host, fallback), b = formatCount(host, other);
    if (a > 0 && b > 0) {
      final fa = formatMs(host, fallback), fb = formatMs(host, other);
      if (fb + 300 < fa) pick = other;
    } else if (a >= 3 && b == 0) {
      pick = other; // learn the other format once
    }
    _fmtSession[host] = pick;
    return pick;
  }
}
