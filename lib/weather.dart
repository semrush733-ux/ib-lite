import 'dart:convert';

import 'package:http/http.dart' as http;

import 'theme.dart' show log;

/// City, country and the current temperature for the home screen's corner box.
/// The place comes from the TV's internet address (ipwho.is), the weather from open-meteo.com;
/// both are free and need no key. Read once and kept for 30 minutes.
class Weather {
  Weather._();

  static String city = '';
  static String country = '';
  static double? temp;
  static bool day = true;
  static DateTime? _at;
  static Future<void>? _loading;

  static bool get known => city.isNotEmpty || temp != null;

  static Future<void> refresh() {
    if (_at != null && DateTime.now().difference(_at!) < const Duration(minutes: 30)) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  static Future<void> _load() async {
    try {
      final r = await http
          .get(Uri.parse('https://ipwho.is/?fields=success,city,country,latitude,longitude'))
          .timeout(const Duration(seconds: 8));
      final d = jsonDecode(r.body);
      if (d is! Map || d['success'] != true) return;
      city = (d['city'] ?? '').toString();
      country = (d['country'] ?? '').toString();
      final lat = d['latitude'], lon = d['longitude'];
      if (lat is num && lon is num) {
        final w = await http
            .get(Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,is_day'))
            .timeout(const Duration(seconds: 8));
        final c = (jsonDecode(w.body) as Map)['current'];
        if (c is Map) {
          final t = c['temperature_2m'];
          if (t is num) temp = t.toDouble();
          day = c['is_day'] != 0;
        }
      }
      _at = DateTime.now();
    } catch (e) {
      log('weather unavailable: ${e.runtimeType}');
    }
  }
}
