import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../backend.dart';
import '../config.dart';
import '../privacy.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import '../puppy.dart';
import 'home.dart';

/// First screen of a new device. There is no sign-in form on the TV: the customer scans the
/// QR code (or types the address) on a phone or computer, adds an M3U link or an Xtream Codes
/// login on the website, and the playlist appears here by itself.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, this.message});

  /// Shown in red, e.g. why the saved playlist stopped working.
  final String? message;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  Timer? _poll;
  List<BPlaylist> _lists = const [];
  bool _opening = false;
  String? _error;
  bool _tried = false;
  // "Watch the demo": loading it, or watching it (a playlist added meanwhile opens afterwards).
  bool _demoLoading = false;
  bool _demoOpen = false;

  @override
  void initState() {
    super.initState();
    log('screen=connect');
    _error = widget.message;
    Backend.changes.addListener(_onBackendChange);
    Backend.ensureRegistered().then((_) {
      if (!mounted) return;
      setState(() {});
      _check();
    });
    // Looks for a playlist from the website every few seconds.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    Backend.changes.removeListener(_onBackendChange);
    super.dispose();
  }

  void _onBackendChange() {
    if (mounted) setState(() {});
  }

  Future<void> _check() async {
    if (_opening || _demoOpen || !mounted || !Backend.configured) return;
    if (Backend.deviceId.isEmpty) await Backend.ensureRegistered();
    try {
      final lists = await Backend.playlists();
      if (!mounted) return;
      setState(() => _lists = lists);
      // One playlist: open it straight away (once; after a failure the customer chooses).
      if (lists.length == 1 && !_tried) {
        _tried = true;
        await _open(lists.first);
      }
    } catch (_) {
      // No connection yet: the next check tries again.
    }
  }

  /// The website's demo playlist, only to watch (nothing is saved); Back comes back here.
  Future<void> _openDemo() async {
    final demo = Backend.demo;
    if (demo == null || _opening || _demoOpen) return;
    setState(() {
      _demoOpen = true;
      _demoLoading = true;
      _error = null;
    });
    log('connect open demo type=${demo.type}');
    try {
      final result = await openDemoPlaylist(demo);
      if (!mounted) return;
      setState(() => _demoLoading = false);
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => HomeScreen(api: result.$1, account: result.$2, demo: true)));
    } catch (e) {
      log('demo failed: ${e.runtimeType}');
      if (mounted) setState(() => _error = '${t('Demo')}: ${friendlyError(e)}');
    }
    if (!mounted) return;
    setState(() {
      _demoOpen = false;
      _demoLoading = false;
    });
    _check();
  }

  Future<void> _open(BPlaylist p) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    log('connect open playlist id=${p.id} type=${p.type}');
    try {
      final result = await openSitePlaylist(p);
      if (!mounted) return;
      _poll?.cancel();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => HomeScreen(api: result.$1, account: result.$2)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _error = '"${p.name}": ${friendlyError(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final site = kSiteBase.replaceFirst(RegExp(r'^https?://'), '');
    return ExitGuard(child: Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/home_bg.webp', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xF2400A10), Color(0xE61A0608)],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(builder: (context, box) {
              final qr = (box.maxHeight * 0.42).clamp(160.0, 320.0);
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: box.maxWidth * 0.06, vertical: box.maxHeight * 0.07),
                child: Row(
                  children: [
                    // ---- left: what to do ----
                    Expanded(
                      flex: 11,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Logo(size: 40),
                            const SizedBox(height: 34),
                            const Text('Add your playlist',
                                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                            const SizedBox(height: 10),
                            Text(
                              'Your playlist is added on our website — no typing with the remote.',
                              style: TextStyle(fontSize: 16, color: C.text.withValues(alpha: 0.8)),
                            ),
                            const SizedBox(height: 26),
                            _step(1, 'Scan the QR code with your phone, or open',
                                site.isEmpty ? 'the website' : '$site/upload-playlist'),
                            _step(2, 'Your MAC Address and Device Key are filled in for you', ''),
                            _step(3, kPlay ? 'Add your playlist link or your server login' : 'Add an M3U link or your Xtream Codes login', ''),
                            _step(4, 'The playlist appears on this TV by itself', ''),
                            // No subscription yet: the demo playlist set on the website.
                            if (Backend.demo != null) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 14,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(t('Try the app first:'),
                                      style: TextStyle(fontSize: 16, color: C.text.withValues(alpha: 0.9))),
                                  _PlaylistButton(
                                    name: _demoLoading ? t('Loading the demo…') : t('Watch the demo'),
                                    icon: Icons.play_circle_fill_rounded,
                                    autofocus: _lists.isEmpty,
                                    onTap: _openDemo,
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 18),
                            if (_error != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0x33FF6B6B),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: C.danger.withValues(alpha: 0.6)),
                                ),
                                child: Text(_error!, style: const TextStyle(color: Color(0xFFFFB3B3), fontSize: 14.5)),
                              ),
                            if (_lists.length > 1 || (_lists.length == 1 && _tried && !_opening)) ...[
                              const SizedBox(height: 18),
                              const Text('Choose a playlist',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  for (var i = 0; i < _lists.length; i++)
                                    _PlaylistButton(
                                      name: _lists[i].name,
                                      autofocus: i == 0,
                                      onTap: () => _open(_lists[i]),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: box.maxWidth * 0.05),
                    // ---- right: QR code and the device's details ----
                    Expanded(
                      flex: 8,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: const Color(0xE60B0607),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0x55FFFFFF), width: 1.4),
                            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30)],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                                child: Backend.configured && Backend.deviceId.isNotEmpty
                                    ? QrImageView(
                                        data: Backend.uploadUrl,
                                        version: QrVersions.auto,
                                        size: qr,
                                        padding: EdgeInsets.zero,
                                        backgroundColor: Colors.white,
                                      )
                                    : SizedBox(
                                        width: qr,
                                        height: qr,
                                        child: Center(
                                          child: Backend.configured
                                              ? const CircularProgressIndicator(color: C.accent)
                                              : const Padding(
                                                  padding: EdgeInsets.all(16),
                                                  child: Text(
                                                    'The website address is not set in this build yet.',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(color: Colors.black87, fontSize: 15),
                                                  ),
                                                ),
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 18),
                              _idRow('MAC Address', Backend.deviceId, qr + 24),
                              const SizedBox(height: 6),
                              _idRow('Device Key', Backend.pairingCode, qr + 24),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: _opening
                                        ? const CircularProgressIndicator(strokeWidth: 2, color: C.accent)
                                        : const _Pulse(),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _opening ? 'Loading your playlist…' : 'Waiting for your playlist…',
                                    style: const TextStyle(color: C.dim, fontSize: 14),
                                  ),
                                ],
                              ),
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
          // What the app sends and why, and the full policy (also in Settings › Application Info).
          const Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(padding: EdgeInsets.fromLTRB(0, 18, 22, 0), child: PrivacyButton(color: Color(0xCC1A0608))),
            ),
          ),
          const Positioned.fill(child: IgnorePointer(child: ExcludeFocus(child: RunningPuppy()))),
        ],
      ),
    ));
  }

  Widget _step(int n, String text, String strong) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: C.accent, shape: BoxShape.circle),
              child: Text('$n', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: text),
                    if (strong.isNotEmpty) ...[
                      const TextSpan(text: '  '),
                      TextSpan(text: strong, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                    ],
                  ]),
                  style: TextStyle(fontSize: 16.5, color: C.text.withValues(alpha: 0.9), height: 1.3),
                ),
              ),
            ),
          ],
        ),
      );

  /// Label and value on one line, shrunk to fit the box (a MAC address is long).
  Widget _idRow(String label, String value, double width) => SizedBox(
        width: width,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$label:  ', style: const TextStyle(color: C.dim, fontSize: 16)),
              Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
            ],
          ),
        ),
      );
}

class _PlaylistButton extends StatefulWidget {
  const _PlaylistButton({
    required this.name,
    required this.onTap,
    this.autofocus = false,
    this.icon = Icons.playlist_play_rounded,
  });
  final String name;
  final VoidCallback onTap;
  final bool autofocus;
  final IconData icon;

  @override
  State<_PlaylistButton> createState() => _PlaylistButtonState();
}

class _PlaylistButtonState extends State<_PlaylistButton> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        autofocus: widget.autofocus,
        borderRadius: BorderRadius.circular(12),
        focusColor: Colors.transparent,
        onFocusChange: (v) => setState(() => _f = v),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: _f ? C.accent : const Color(0xCC231A1C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _f ? Colors.white : const Color(0x33FFFFFF), width: _f ? 2 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(widget.name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small dot that breathes while the app waits for the website.
class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.25, end: 1.0).animate(_c),
      child: Container(decoration: const BoxDecoration(color: C.accent, shape: BoxShape.circle)),
    );
  }
}
