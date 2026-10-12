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

class Profile {
  Profile(Map<String, dynamic> j)
      : name = '${j['name'] ?? ''}',
        role = '${j['role'] ?? 'admin'}',
        credits = j['credits'] is num ? (j['credits'] as num).toInt() : null,
        server = '${j['server'] ?? ''}',
        m3u = '${j['m3u'] ?? ''}',
        clients = j['clients'] is num ? (j['clients'] as num).toInt() : 0,
        brand = '${j['brand'] ?? ''}';
  final String name, role, server, m3u, brand;
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

class Client {
  Client(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        name = '${j['name'] ?? ''}',
        type = '${j['type'] ?? 'xtream'}',
        username = '${j['username'] ?? ''}',
        deviceId = '${j['device_id'] ?? ''}',
        status = '${j['status'] ?? ''}',
        plan = '${j['plan'] ?? ''}',
        expires = '${j['expires'] ?? ''}',
        lastSeen = '${j['last_seen'] ?? ''}';
  final int id;
  final String name, type, username, deviceId, status, plan, expires, lastSeen;
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
    if (j['success'] != true) {
      throw ApiException('${j['message'] ?? 'Something went wrong.'}', res.statusCode);
    }
    return j;
  }

  static Future<void> signIn(String siteInput, String user, String pass) async {
    site = kDefaultSite.isNotEmpty ? kDefaultSite : siteInput.trim();
    token = '';
    final j = await _call('/panel/login', body: {'username': user.trim(), 'password': pass});
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

  static Future<(Device, int)> lookup(String mac, String key) async {
    final j = await _call('/panel/lookup', body: {'device_id': mac, 'pairing_code': key});
    return (Device(j['device'] as Map<String, dynamic>), (j['playlists'] as num?)?.toInt() ?? 0);
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
  }) async {
    final j = await _call('/panel/clients/add', body: {
      'device_id': mac,
      'pairing_code': key,
      'name': name,
      'username': username,
      'password': password,
      'type': type,
    });
    return '${j['message']}';
  }

  static Future<String> updateClient(int id, {String? name, String? username, String? password, String? type}) async {
    final j = await _call('/panel/clients/update', body: {
      'playlist_id': id,
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
