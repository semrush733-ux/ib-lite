import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha1;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart' show log;

/// The app's look as set on the website (Settings -> App look): the logo symbol, the wide logo
/// and the start screen (built-in animation, a video or a picture). Files are downloaded once
/// and kept on the device, so the next start shows them at once; until then the built-in ones
/// are used. In the browser version they are read straight from the website.
class RemoteBrand {
  RemoteBrand._();

  static SharedPreferences? _p;
  static String iconUrl = '', logoUrl = '', introType = 'builtin', introUrl = '';

  /// Name typed in the built-in start animation (website setting); '' = the app's own name.
  static String introName = '';
  static int introSeconds = 4;
  static String iconPath = '', logoPath = '', introPath = '';

  /// Increases when a new picture is ready (widgets showing the logo listen to it).
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<void> init() async {
    try {
      _p = await SharedPreferences.getInstance();
      final saved = _p!.getString('rb_state');
      if (saved == null) return;
      final m = jsonDecode(saved) as Map<String, dynamic>;
      iconUrl = (m['icon'] ?? '').toString();
      logoUrl = (m['logo'] ?? '').toString();
      introType = (m['introType'] ?? 'builtin').toString();
      introUrl = (m['introUrl'] ?? '').toString();
      introSeconds = int.tryParse('${m['introSeconds']}') ?? 4;
      introName = (m['introName'] ?? '').toString();
      if (!kIsWeb) {
        iconPath = _existing((m['iconPath'] ?? '').toString());
        logoPath = _existing((m['logoPath'] ?? '').toString());
        introPath = _existing((m['introPath'] ?? '').toString());
      }
    } catch (e) {
      log('remote brand init: ${e.runtimeType}');
    }
  }

  static String _existing(String path) => path.isNotEmpty && File(path).existsSync() ? path : '';

  /// Called with config.brand from the website.
  static Future<void> apply(Object? brand) async {
    if (brand is! Map) return;
    final icon = (brand['icon'] ?? '').toString().trim();
    final logo = (brand['logo'] ?? '').toString().trim();
    final intro = brand['intro'] is Map ? brand['intro'] as Map : const {};
    final type = (intro['type'] ?? 'builtin').toString();
    final iUrl = (intro['url'] ?? '').toString().trim();
    final secs = (int.tryParse('${intro['seconds']}') ?? 4).clamp(2, 15).toInt();
    final iName = (brand['intro_name'] ?? '').toString().trim();

    var changed = iName != introName || icon != iconUrl || logo != logoUrl || type != introType || iUrl != introUrl || secs != introSeconds;
    if (icon != iconUrl) iconPath = '';
    if (logo != logoUrl) logoPath = '';
    if (iUrl != introUrl) introPath = '';
    iconUrl = icon;
    logoUrl = logo;
    introType = type;
    introUrl = iUrl;
    introSeconds = secs;
    introName = iName;

    if (!kIsWeb) {
      if (iconUrl.isNotEmpty && iconPath.isEmpty) {
        iconPath = await _download(iconUrl, 5 << 20);
        changed |= iconPath.isNotEmpty;
      }
      if (logoUrl.isNotEmpty && logoPath.isEmpty) {
        logoPath = await _download(logoUrl, 5 << 20);
        changed |= logoPath.isNotEmpty;
      }
      if (introType != 'builtin' && introUrl.isNotEmpty && introPath.isEmpty) {
        introPath = await _download(introUrl, 40 << 20);
      }
    }
    await _p?.setString(
        'rb_state',
        jsonEncode({
          'icon': iconUrl,
          'logo': logoUrl,
          'introType': introType,
          'introUrl': introUrl,
          'introSeconds': introSeconds,
          'introName': introName,
          'iconPath': iconPath,
          'logoPath': logoPath,
          'introPath': introPath,
        }));
    if (changed) changes.value++;
  }

  static Future<String> _download(String url, int maxBytes) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final name = sha1.convert(utf8.encode(url)).toString();
      final ext = url.split('?').first.split('.').last.toLowerCase();
      final file = File('${dir.path}/brand_$name.${ext.length <= 4 ? ext : 'bin'}');
      if (file.existsSync() && file.lengthSync() > 0) return file.path;
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty || res.bodyBytes.length > maxBytes) return '';
      final tmp = File('${file.path}.part');
      await tmp.writeAsBytes(res.bodyBytes, flush: true);
      await tmp.rename(file.path);
      log('brand file ready: ${file.path.split('/').last}');
      return file.path;
    } catch (e) {
      log('brand download failed: ${e.runtimeType}');
      return '';
    }
  }

  /// The logo symbol from the website, or null for the built-in one.
  static ImageProvider? get symbol {
    if (kIsWeb) return iconUrl.isEmpty ? null : NetworkImage(iconUrl);
    return iconPath.isEmpty ? null : FileImage(File(iconPath));
  }

  /// The wide logo from the website, or null for the built-in one.
  static ImageProvider? get wideLogo {
    if (kIsWeb) return logoUrl.isEmpty ? null : NetworkImage(logoUrl);
    return logoPath.isEmpty ? null : FileImage(File(logoPath));
  }

  /// Where the intro video or picture is: a local file, or (browser) the website link.
  static String? get introSource {
    if (introType == 'builtin' || introUrl.isEmpty) return null;
    if (kIsWeb) return introUrl;
    return introPath.isEmpty ? null : introPath;
  }
}
