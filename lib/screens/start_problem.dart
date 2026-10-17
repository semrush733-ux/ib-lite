import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../backend.dart';
import '../config.dart';
import '../theme.dart';
import '../widgets.dart';
import 'update.dart';

/// Shown instead of the app when it cannot open (a part of Android or a library failed while the
/// app started): the reason in a few words, and the newest version from the website when it has
/// one ("Update now" downloads and installs it). A TV never stays on the start logo with nothing
/// to press, and a later fixed version reaches it by itself.
class StartProblemApp extends StatelessWidget {
  const StartProblemApp({super.key, required this.error, required this.retry});

  final String error;

  /// Opens the app again from the start.
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _StartProblem(error: error, retry: retry),
    );
  }
}

class _StartProblem extends StatefulWidget {
  const _StartProblem({required this.error, required this.retry});
  final String error;
  final VoidCallback retry;

  @override
  State<_StartProblem> createState() => _StartProblemState();
}

class _StartProblemState extends State<_StartProblem> {
  bool _checked = false;
  BUpdate? _update;
  int _installed = 0;
  final _updateNode = FocusNode(debugLabel: 'start-problem-update');

  bool get _canUpdateHere => !kIsWeb && defaultTargetPlatform == TargetPlatform.android && !kPlay;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  @override
  void dispose() {
    _updateNode.dispose();
    super.dispose();
  }

  /// Asks the website for its newest version (the same answer the app's update check gets).
  Future<void> _check() async {
    var installed = 0;
    try {
      final v = await const MethodChannel('b1g/device').invokeMethod<dynamic>('appVersion');
      if (v is Map) installed = int.tryParse('${v['code'] ?? 0}') ?? 0;
    } catch (_) {}
    BUpdate? update;
    if (_canUpdateHere && kApiBase.isNotEmpty) {
      try {
        final r = await http.get(
          Uri.parse('$kApiBase/app/config?platform=android-tv&version_code=$installed'),
          headers: {'User-Agent': kUserAgent},
        ).timeout(const Duration(seconds: 15));
        final j = jsonDecode(r.body);
        if (j is Map) update = BUpdate.fromJson(j['update']);
      } catch (e) {
        log('start problem: update check failed ${e.runtimeType}');
      }
    }
    log('start problem: installed=$installed website=${update?.versionCode ?? 0}');
    final BUpdate? offer = update != null && (installed <= 0 || update.versionCode > installed) ? update : null;
    if (!mounted) return;
    setState(() {
      _checked = true;
      _installed = installed;
      _update = offer;
    });
    // The remote lands on "Update now" as soon as there is one.
    if (offer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateNode.requestFocus();
      });
    }
  }

  Widget _button(String label, IconData icon, VoidCallback onTap,
      {bool primary = false, bool autofocus = false, FocusNode? node}) {
    return TvFocus(
      focusNode: node,
      autofocus: autofocus,
      color: primary ? C.accent : C.card,
      focusBorder: primary ? Colors.white : C.accent,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: primary ? C.onAccent : C.text),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: primary ? C.onAccent : C.text, fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = _update;
    final reason = widget.error.replaceAll(RegExp(r'\s+'), ' ').trim();
    final String status;
    if (!_checked) {
      status = 'Looking for a newer version on the website…';
    } else if (u != null) {
      status = 'Version ${u.versionName.isEmpty ? 'build ${u.versionCode}' : u.versionName} is ready on the website. '
          'Your login and favourites stay as they are.';
    } else if (_canUpdateHere) {
      status = 'No newer version on the website yet${_installed > 0 ? ' (this is build $_installed)' : ''}. '
          'Please try again later, or install the app again from the website.';
    } else {
      status = 'Please update the app from the store.';
    }
    return Scaffold(
      backgroundColor: C.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/symbol.png', width: 88, height: 88, errorBuilder: (_, __, ___) => const SizedBox()),
                const SizedBox(height: 22),
                Text('$kAppName could not open',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                const Text(
                  'Something on this device stopped the app while it was starting.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: C.dim, height: 1.4),
                ),
                const SizedBox(height: 18),
                Text(status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.45)),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    if (u != null)
                      _button('Update now', Icons.system_update_rounded, () => showUpdateDialog(context, u),
                          primary: true, node: _updateNode),
                    _button('Try again', Icons.refresh_rounded, widget.retry, autofocus: true),
                    _button('Close', Icons.close_rounded, () => SystemNavigator.pop()),
                  ],
                ),
                const SizedBox(height: 26),
                Text(
                  reason.length > 220 ? '${reason.substring(0, 220)}…' : reason,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: C.dim, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
