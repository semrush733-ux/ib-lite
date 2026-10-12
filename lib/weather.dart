import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart' show log;

/// City, country and the current temperature for the home screen's corner box.
///
/// The place comes from the TV's internet address. Several free services are asked in turn
/// (one may be down, rate-limited or blocked by the internet provider), the last place found is
/// kept, so the box is filled at once on the next start, and a failed look is tried again after
/// two minutes instead of waiting. The weather comes from open-meteo.com. No keys needed.
/// Note: with a VPN on, the place shown is the VPN's.
class Weather {
  Weather._();

  static String city = '';
  static String country = '';
  static double? temp;
  static bool day = true;
  static DateTime? _at;
  static DateTime? _failedAt;
  static Future<void>? _loading;
  static bool _restored = false;

  static bool get known => city.isNotEmpty || temp != null;

  static Future<void> refresh() {
    if (_at != null && DateTime.now().difference(_at!) < const Duration(minutes: 30)) return Future.value();
    if (_failedAt != null && DateTime.now().difference(_failedAt!) < const Duration(minutes: 2)) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  static Future<void> _restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final p = await SharedPreferences.getInstance();
      if (city.isEmpty) city = p.getString('wx_city') ?? '';
      if (country.isEmpty) country = p.getString('wx_country') ?? '';
    } catch (_) {}
  }

  static Future<void> _save(double lat, double lon) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('wx_city', city);
      await p.setString('wx_country', country);
      await p.setDouble('wx_lat', lat);
      await p.setDouble('wx_lon', lon);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> _json(String url) async {
    try {
      final r = await http.get(Uri.parse(url), headers: const {'Accept': 'application/json'}).timeout(const Duration(seconds: 7));
      if (r.statusCode != 200) return null;
      final d = jsonDecode(r.body);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

  static double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  /// (city, country, lat, lon) from the first service that answers.
  static Future<(String, String, double, double)?> _locate() async {
    final tries = <Future<(String, String, double, double)?> Function()>[
      () async {
        final d = await _json('https://ipwho.is/?fields=success,city,country,latitude,longitude');
        if (d == null || d['success'] != true) return null;
        final la = _num(d['latitude']), lo = _num(d['longitude']);
        return la == null || lo == null ? null : ('${d['city'] ?? ''}', '${d['country'] ?? ''}', la, lo);
      },
      () async {
        final d = await _json('https://freeipapi.com/api/json');
        final la = _num(d?['latitude']), lo = _num(d?['longitude']);
        return d == null || la == null || lo == null ? null : ('${d['cityName'] ?? ''}', '${d['countryName'] ?? ''}', la, lo);
      },
      () async {
        final d = await _json('https://ipapi.co/json/');
        final la = _num(d?['latitude']), lo = _num(d?['longitude']);
        return d == null || d['error'] == true || la == null || lo == null
            ? null
            : ('${d['city'] ?? ''}', '${d['country_name'] ?? ''}', la, lo);
      },
      () async {
        final d = await _json('https://get.geojs.io/v1/ip/geo.json');
        final la = _num(d?['latitude']), lo = _num(d?['longitude']);
        return d == null || la == null || lo == null ? null : ('${d['city'] ?? ''}', '${d['country'] ?? ''}', la, lo);
      },
    ];
    for (final t in tries) {
      final r = await t();
      if (r != null && (r.$1.isNotEmpty || r.$2.isNotEmpty)) return r;
    }
    return null;
  }

  static Future<void> _load() async {
    await _restore();
    try {
      double? lat, lon;
      final found = await _locate();
      if (found != null) {
        city = found.$1;
        country = found.$2;
        lat = found.$3;
        lon = found.$4;
        await _save(lat, lon);
      } else {
        // No service answered: weather for the last place we knew.
        final p = await SharedPreferences.getInstance();
        lat = p.getDouble('wx_lat');
        lon = p.getDouble('wx_lon');
        log('location unavailable');
      }
      if (lat != null && lon != null) {
        final c = (await _json(
            'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,is_day'))?['current'];
        if (c is Map) {
          final t = c['temperature_2m'];
          if (t is num) temp = t.toDouble();
          day = c['is_day'] != 0;
        }
      }
      if (found != null) {
        _at = DateTime.now();
        _failedAt = null;
      } else {
        _failedAt = DateTime.now();
      }
    } catch (e) {
      _failedAt = DateTime.now();
      log('weather unavailable: ${e.runtimeType}');
    }
  }
}
