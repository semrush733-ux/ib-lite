import 'package:flutter/foundation.dart';

import 'downloads_core.dart';

export 'downloads_core.dart';

/// Browsers and Samsung / LG TVs cannot keep files: no downloads there.
class Downloads extends ChangeNotifier {
  Downloads._();
  static final Downloads i = Downloads._();
  static bool get available => false;
  static final Set<bool Function()> watchers = {};
  final List<DlItem> items = [];
  bool get busy => false;
  Future<void> init() async {}
  DlItem? byId(String id) => null;
  String? localUrl(String id) => null;
  Future<void> add({required String id, required String title, required String url, String subtitle = '', String cover = ''}) async {}
  void pause(String id) {}
  void resume(String id) {}
  void remove(String id) {}
}
