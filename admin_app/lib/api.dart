import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// The website set at build time (brand/brand.txt WEBSITE), changeable on the sign-in screen.
const String kDefaultSite = String.fromEnvironment('SITE', defaultValue: '');

class ApiException implements Exception {
  ApiException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

/// The security question on the sign-in screen: a times table sum from 2 x 2 to 9 x 9.
class Captcha {
  Captcha(Map<String, dynamic> j)
      : required = j['required'] != false,
        token = '${j['token'] ?? ''}',
        a = (j['a'] as num?)?.toInt() ?? 0,
        b = (j['b'] as num?)?.toInt() ?? 0;
  final bool required;
  final String token;
  final int a, b;
}

class Profile {
  Profile(Map<String, dynamic> j)
      : name = '${j['name'] ?? ''}',
        role = '${j['role'] ?? 'admin'}',
        credits = j['credits'] is num ? (j['credits'] as num).toInt() : null,
        server = '${j['server'] ?? ''}',
        m3u = '${j['m3u'] ?? ''}',
        clients = j['clients'] is num ? (j['clients'] as num).toInt() : 0,
        brand = '${j['brand'] ?? ''}',
        level = '${j['level'] ?? 'reseller'}',
        version = '${j['version'] ?? ''}',
        canCreate = j['can_create'] is List
            ? [for (final l in j['can_create'] as List) '$l']
            : (j['role'] == 'super' ? const ['admin', 'reseller', 'subreseller'] : const ['subreseller']);
  final String name, role, server, m3u, brand, level, version;
  final List<String> canCreate;
  final int? credits;
  final int clients;
  bool get isSuper => role == 'super';
}

class Device {
  Device(Map<String, dynamic> j)
      : id = '${j['device_id'] ?? ''}',
        status = '${j['status'] ?? ''}',
        plan = '${j['plan'] ?? ''}',
        expires = '${j['expires'] ?? ''}',
        daysLeft = j['days_left'] is num ? (j['days_left'] as num).toInt() : 0;
  final String id, status, plan, expires;
  final int daysLeft;
}

/// A playlist already on the TV (no login or link shown).
class TvPlaylist {
  TvPlaylist(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        name = '${j['name'] ?? ''}',
        type = '${j['type'] ?? 'xtream'}',
        username = '${j['username'] ?? ''}',
        locked = j['locked'] == true,
        mine = j['mine'] == true,
        managed = j['managed'] == true;
  final int id;
  final String name, type, username;
  final bool locked, mine, managed;
}

class Client {
  Client(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        name = '${j['name'] ?? ''}',
        type = '${j['type'] ?? 'xtream'}',
        username = '${j['username'] ?? ''}',
        url = '${j['url'] ?? ''}',
        locked = j['locked'] == true,
        owner = '${j['owner'] ?? ''}',
        mine = j['mine'] != false,
        deviceId = '${j['device_id'] ?? ''}',
        status = '${j['status'] ?? ''}',
        plan = '${j['plan'] ?? ''}',
        expires = '${j['expires'] ?? ''}',
        lastSeen = '${j['last_seen'] ?? ''}';
  final int id;
  final String name, type, username, url, deviceId, status, plan, expires, lastSeen, owner;
  final bool locked, mine;

  /// What to show as the client's title: the login, or the playlist name for an M3U link.
  String get title => username.isNotEmpty ? username : name;
}

class Api {
  Api._();
  static SharedPreferences? _p;
  static String site = '';
  static String token = '';
  static Profile? profile;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    // Built for one website (brand/brand.txt): always that one. Only a build without it asks.
    site = kDefaultSite.isNotEmpty ? kDefaultSite : (_p!.getString('site') ?? '');
    token = _p!.getString('token') ?? '';
  }

  static bool get signedIn => token.isNotEmpty;

  static String _base(String s) {
    var b = s.trim();
    if (b.isEmpty) return '';
    if (!b.startsWith('http')) b = 'https://$b';
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return '$b/wp-json/b1g/v1';
  }

  static Future<Map<String, dynamic>> _call(String path, {Map<String, dynamic>? body, Map<String, String>? query}) async {
    final base = _base(site);
    if (base.isEmpty) throw ApiException('Enter your website address.');
    var uri = Uri.parse('$base$path');
    if (query != null) uri = uri.replace(queryParameters: query);
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token.isNotEmpty) 'X-Panel-Token': token,
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    http.Response res;
    try {
      res = body == null
          ? await http.get(uri, headers: headers).timeout(const Duration(seconds: 25))
          : await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw ApiException('No connection to the website. Check the internet.');
    }
    Map<String, dynamic> j;
    try {
      j = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(res.statusCode == 404
          ? 'The website does not have the Admin Panel yet (update the Lite Player plugin).'
          : 'Unexpected answer from the website (${res.statusCode}).');
    }
    if (res.statusCode == 401) {
      await signOut(local: true);
    }
    if (j['code'] == 'rest_no_route' || (res.statusCode == 404 && j['success'] == null)) {
      throw ApiException(
          'The website is running an old Lite Player plugin. Install Lite Player plugin 1.0.19 '
          '(WordPress → Plugins → Add New → Upload), then sign out and sign in again here.',
          404);
    }
    if (j['success'] != true) {
      throw ApiException('${j['message'] ?? 'Something went wrong.'}', res.statusCode);
    }
    return j;
  }

  /// For the other screens of the app.
  static Future<Map<String, dynamic>> call(String path, {Map<String, dynamic>? body, Map<String, String>? query}) =>
      _call(path, body: body, query: query);

  /// Sends a picture / video from the phone to the website's media library; returns its address.
  static Future<String> upload(String path, String filePath) async {
    final base = _base(site);
    final req = http.MultipartRequest('POST', Uri.parse('$base$path'))
      ..headers['X-Panel-Token'] = token
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(await http.MultipartFile.fromPath('file', filePath));
    http.Response res;
    try {
      res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 120)));
    } catch (_) {
      throw ApiException('Upload failed. Check the internet.');
    }
    Map<String, dynamic> j;
    try {
      j = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Upload failed (${res.statusCode}). The file may be too big for the website.');
    }
    if (j['success'] != true) throw ApiException('${j['message'] ?? 'Upload failed.'}');
    return '${j['url']}';
  }

  /// Super admin looking at another account ("Open as"): the own session waits here.
  static String get superToken => _p?.getString('super_token') ?? '';
  static bool get impersonating => superToken.isNotEmpty;

  static Future<void> openAs(int userId) async {
    final j = await _call('/panel/users/impersonate', body: {'user_id': userId});
    await _p?.setString('super_token', token);
    token = '${j['token']}';
    await _p?.setString('token', token);
    await me();
  }

  static Future<void> backToMine() async {
    final mine = superToken;
    if (mine.isEmpty) return;
    try {
      await _call('/panel/logout', body: {}); // ends the borrowed session
    } catch (_) {}
    token = mine;
    await _p?.setString('token', token);
    await _p?.remove('super_token');
    await me();
  }

  /// A new security question for signing in, or null when the website does not ask one
  /// (turned off, or an older website plugin).
  static Future<Captcha?> captcha(String siteInput) async {
    site = kDefaultSite.isNotEmpty ? kDefaultSite : siteInput.trim();
    token = '';
    try {
      final c = Captcha(await _call('/panel/captcha'));
      return c.required && c.token.isNotEmpty ? c : null;
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  static Future<void> signIn(String siteInput, String user, String pass, {String captchaToken = '', String captcha = ''}) async {
    site = kDefaultSite.isNotEmpty ? kDefaultSite : siteInput.trim();
    token = '';
    final j = await _call('/panel/login', body: {
      'username': user.trim(),
      'password': pass,
      if (captchaToken.isNotEmpty) 'captcha_token': captchaToken,
      if (captchaToken.isNotEmpty) 'captcha': captcha.trim(),
    });
    token = '${j['token']}';
    profile = Profile(j['profile'] as Map<String, dynamic>);
    await _p?.setString('site', site);
    await _p?.setString('token', token);
  }

  static Future<void> signOut({bool local = false}) async {
    if (!local && token.isNotEmpty) {
      try {
        await _call('/panel/logout', body: {});
      } catch (_) {}
    }
    token = '';
    profile = null;
    await _p?.remove('token');
    await _p?.remove('super_token');
  }

  static Future<Profile> me() async {
    final j = await _call('/panel/me');
    return profile = Profile(j['profile'] as Map<String, dynamic>);
  }

  static Future<String> saveServer(String source) async {
    final j = await _call('/panel/settings', body: {'source': source});
    profile = Profile(j['profile'] as Map<String, dynamic>);
    return '${j['message'] ?? 'Saved.'}';
  }

  /// Old server → new server, only for playlists that use the old one. [dryRun] only counts.
  static Future<(String, int)> replaceServer(String oldServer, String newServer, {bool dryRun = false}) async {
    final j = await _call('/panel/replace-server', body: {'old': oldServer, 'new': newServer, 'dry_run': dryRun ? 1 : 0});
    if (j['profile'] is Map) profile = Profile(j['profile'] as Map<String, dynamic>);
    return ('${j['message'] ?? ''}', (j['changed'] as num?)?.toInt() ?? 0);
  }

  static Future<(Device, List<TvPlaylist>)> lookup(String mac, String key) async {
    final j = await _call('/panel/lookup', body: {'device_id': mac, 'pairing_code': key});
    final list = [
      for (final p in (j['playlist_list'] as List? ?? const [])) TvPlaylist(p as Map<String, dynamic>),
    ];
    return (Device(j['device'] as Map<String, dynamic>), list);
  }

  /// Takes a playlist that is already on the TV into my clients.
  static Future<String> claim(String mac, String key, int playlistId, String pin) async {
    final j = await _call('/panel/clients/claim',
        body: {'device_id': mac, 'pairing_code': key, 'playlist_id': playlistId, 'pin': pin});
    return '${j['message'] ?? 'Added to your clients.'}';
  }

  static Future<List<Client>> clients([String q = '']) async {
    final j = await _call('/panel/clients', query: q.isEmpty ? null : {'q': q});
    return [for (final c in (j['clients'] as List)) Client(c as Map<String, dynamic>)];
  }

  static Future<String> addClient({
    required String mac,
    required String key,
    required String name,
    required String username,
    required String password,
    required String type,
    String m3uUrl = '',
    String pin = '',
  }) async {
    final j = await _call('/panel/clients/add', body: {
      'device_id': mac,
      'pairing_code': key,
      'name': name,
      'username': username,
      'password': password,
      'type': type,
      'm3u_url': m3uUrl,
      'pin': pin,
    });
    return '${j['message']}';
  }

  static Future<String> updateClient(int id,
      {String? name, String? username, String? password, String? type, String? m3uUrl, String? pin, bool removePin = false}) async {
    final j = await _call('/panel/clients/update', body: {
      'playlist_id': id,
      if (m3uUrl != null && m3uUrl.isNotEmpty) 'm3u_url': m3uUrl,
      if (pin != null && pin.isNotEmpty) 'pin': pin,
      if (removePin) 'remove_pin': '1',
      if (name != null) 'name': name,
      if (username != null) 'username': username,
      if (password != null && password.isNotEmpty) 'password': password,
      if (type != null) 'type': type,
    });
    return '${j['message']}';
  }

  static Future<String> deleteClient(int id) async {
    final j = await _call('/panel/clients/delete', body: {'playlist_id': id});
    return '${j['message']}';
  }

  static Future<String> activate(String mac, String plan) async {
    final j = await _call('/panel/activate', body: {'device_id': mac, 'plan': plan});
    if (j['profile'] is Map) profile = Profile(j['profile'] as Map<String, dynamic>);
    return '${j['message']}';
  }
}

class PanelUser {
  PanelUser(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        username = '${j['username'] ?? ''}',
        email = '${j['email'] ?? ''}',
        level = '${j['level'] ?? ''}',
        credits = (j['credits'] as num?)?.toInt() ?? 0,
        clients = (j['clients'] as num?)?.toInt() ?? 0,
        parent = '${j['parent'] ?? ''}',
        disabled = j['disabled'] == true,
        maxChildren = (j['max_children'] as num?)?.toInt() ?? 0,
        children = (j['children'] as num?)?.toInt() ?? 0,
        creditsUsed = (j['credits_used'] as num?)?.toInt() ?? 0,
        activations = (j['activations'] as num?)?.toInt() ?? 0,
        lastActivation = '${j['last_activation'] ?? ''}';
  final int id, credits, clients, maxChildren, children, creditsUsed, activations;
  final String username, email, level, parent, lastActivation;
  final bool disabled;
}

String levelName(String l) => switch (l) {
      'super' => 'Super admin',
      'admin' => 'Admin',
      'reseller' => 'Reseller',
      'subreseller' => 'Sub-reseller',
      _ => l,
    };

class UsersApi {
  UsersApi._();

  static Future<List<PanelUser>> list([String q = '']) async {
    final j = await Api._call('/panel/users', query: q.isEmpty ? null : {'q': q});
    return [for (final u in (j['users'] as List)) PanelUser(u as Map<String, dynamic>)];
  }

  static Future<String> add({
    required String level,
    required String username,
    required String email,
    required String password,
    int credits = 0,
  }) async {
    final j = await Api._call('/panel/users/add', body: {
      'level': level,
      'username': username,
      'email': email,
      'password': password,
      'credits': credits,
    });
    if (j['profile'] is Map) Api.profile = Profile(j['profile'] as Map<String, dynamic>);
    return '${j['message']}';
  }

  static Future<String> credits(int userId, int amount) async {
    final j = await Api._call('/panel/users/credits', body: {'user_id': userId, 'amount': amount});
    if (j['profile'] is Map) Api.profile = Profile(j['profile'] as Map<String, dynamic>);
    return '${j['message']}';
  }

  static Future<String> update(int userId, {String password = '', bool? disabled, String? level, int? maxChildren}) async {
    final j = await Api._call('/panel/users/update', body: {
      'user_id': userId,
      if (password.isNotEmpty) 'password': password,
      if (disabled != null) 'disabled': disabled ? '1' : '0',
      if (level != null) 'level': level,
      if (maxChildren != null) 'max_children': maxChildren,
    });
    return '${j['message']}';
  }

  /// Credits given, received and spent by an account (newest first).
  static Future<List<Map<String, dynamic>>> history(int userId) async {
    final j = await Api._call('/panel/users/history', query: {'user_id': '$userId'});
    return [for (final h in (j['history'] as List? ?? const [])) h as Map<String, dynamic>];
  }
}

/// MAC Address and Device Key from the TV's QR code (the link to the website's upload page).
(String, String)? parseQr(String raw) {
  final t = raw.trim();
  final uri = Uri.tryParse(t);
  if (uri != null && uri.queryParameters.containsKey('device_id')) {
    final mac = uri.queryParameters['device_id'] ?? '';
    final key = uri.queryParameters['pairing_code'] ?? '';
    if (mac.isNotEmpty && key.isNotEmpty) return (mac, key);
  }
  // Plain text "MAC KEY" or "MAC|KEY".
  final parts = t.split(RegExp(r'[\s|,;]+')).where((s) => s.isNotEmpty).toList();
  if (parts.length == 2) return (parts[0], parts[1]);
  return null;
}
