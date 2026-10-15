import 'package:flutter/material.dart';

import '../backend.dart';
import '../input_mode.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';

enum _State { checking, active, expired, unknown }

/// The playlists on the customer's account, each with its address and a status dot:
/// green = account active, red = expired / blocked, grey = could not be checked.
/// The checks run one after the other in the background (a light login call each), so the TV
/// is never busy with several at once. OK on a playlist switches to it.
class PlaylistsScreen extends StatefulWidget {
  /// True once a playlist was deleted on this screen (read and reset by the home screen).
  static bool takeDeleted() {
    final d = _PlaylistsScreenState.deletedSomething;
    _PlaylistsScreenState.deletedSomething = false;
    return d;
  }

  const PlaylistsScreen({super.key, required this.current});

  /// Name of the playlist in use now (shown with a "Now playing" tag).
  final String current;

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  // Kept for the whole app session, so opening the page again does not check again.
  static final Map<String, _State> _known = {};
  static final Map<String, DateTime?> _expires = {};

  List<BPlaylist>? _lists;
  String? _error;

  @override
  void initState() {
    super.initState();
    log('screen=playlists');
    _load();
  }

  String _key(BPlaylist p) => '${p.url}|${p.username}';

  Future<void> _load() async {
    try {
      final lists = await Backend.playlists();
      if (!mounted) return;
      setState(() => _lists = lists);
      _checkAll(lists);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// Xtream login data of a playlist: its own fields, or the ones inside an Xtream-style M3U link.
  (String, String, String)? _xtream(BPlaylist p) {
    if (p.isXtream) return (parseServerInput(p.url).server, p.username, p.password);
    final parsed = parseServerInput(p.url);
    final user = parsed.username;
    final pass = parsed.password;
    if (user != null && pass != null && user.isNotEmpty && parsed.server.isNotEmpty) {
      return (parsed.server, user, pass);
    }
    return null;
  }

  Future<void> _checkAll(List<BPlaylist> lists) async {
    for (final p in lists) {
      if (!mounted) return;
      final key = _key(p);
      if (_known.containsKey(key) && _known[key] != _State.checking) continue;
      final login = _xtream(p);
      if (login == null) {
        _known[key] = _State.unknown;
        setState(() {});
        continue;
      }
      setState(() => _known[key] = _State.checking);
      try {
        final account = await XtreamApi(login.$1, login.$2, login.$3).login();
        final exp = account.expires;
        _expires[key] = exp;
        _known[key] = exp != null && exp.isBefore(DateTime.now()) ? _State.expired : _State.active;
      } on XtreamAuthException {
        _known[key] = _State.expired;
      } catch (_) {
        _known[key] = _State.unknown;
      }
      if (mounted) setState(() {});
    }
  }

  // Every playlist is listed by the name it has on the website; OK opens it.
  void _pick(BPlaylist p) => Navigator.of(context).pop(p);

  /// Delete: the customer types DELETE (and the PIN of a locked playlist) to confirm.
  Future<void> _delete(BPlaylist p) async {
    final word = TextEditingController();
    final pin = TextEditingController();
    String? problem;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBox) {
          void submit() {
            if (word.text.trim().toUpperCase() != 'DELETE') {
              setBox(() => problem = 'Type DELETE to confirm.');
              return;
            }
            Navigator.of(ctx).pop(true);
          }

          return AlertDialog(
            backgroundColor: C.panel,
            title: Text('Delete "${p.name}"?'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('The playlist is removed from this TV and from the website. '
                      'To make sure it is not by mistake, type DELETE below and press Submit (or Cancel).',
                      style: TextStyle(color: C.dim, height: 1.45)),
                  const SizedBox(height: 14),
                  TvField(
                    controller: word,
                    label: 'Type DELETE',
                    icon: Icons.delete_forever_rounded,
                    autofocus: true,
                    action: TextInputAction.done,
                    onSubmitted: (_) => submit(),
                  ),
                  if (problem != null) ...[
                    const SizedBox(height: 10),
                    Text(problem!, style: const TextStyle(color: C.danger, fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
              TextButton(
                onPressed: submit,
                child: const Text('Submit', style: TextStyle(color: C.danger, fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );
    word.dispose();
    pin.dispose();
    if (ok != true || !mounted) return;
    try {
      String msg;
      try {
        msg = await Backend.deletePlaylist(p.id);
      } on BackendException catch (e) {
        // Only where this TV cannot prove itself (browser / iPhone / Samsung / LG) and the
        // playlist is locked: its PIN is asked.
        if (e.code != 'b1g_pin_required' || !mounted) rethrow;
        final code = await _askPin(p);
        if (code == null || !mounted) return;
        msg = await Backend.deletePlaylist(p.id, pin: code);
      }
      log('playlist deleted on the device: ${p.id}');
      if (!mounted) return;
      _deleted = true;
      _PlaylistsScreenState.deletedSomething = _deleted;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg, textAlign: TextAlign.center)));
      setState(() => _lists = null);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e is BackendException ? e.message : friendlyError(e), textAlign: TextAlign.center)));
    }
  }

  Future<String?> _askPin(BPlaylist p) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: const Text('Playlist PIN'),
        content: SizedBox(
          width: 380,
          child: TvField(
            controller: c,
            label: '4-digit PIN of "${p.name}"',
            icon: Icons.lock_rounded,
            obscure: true,
            autofocus: true,
            keyboardType: TextInputType.number,
            action: TextInputAction.done,
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(c.text.trim()), child: const Text('Delete')),
        ],
      ),
    );
  }

  /// A playlist was deleted here: the home screen checks which playlist to use when we go back.
  bool _deleted = false;
  static bool deletedSomething = false;

  @override
  Widget build(BuildContext context) {
    final lists = _lists;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(44, 26, 44, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  // Phones and touch screens have no remote Back key on screen: a back arrow.
                  if (!InputMode.remote)
                    ExcludeFocus(
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: C.text),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  const Icon(Icons.playlist_play_rounded, color: C.accent, size: 30),
                  const SizedBox(width: 12),
                  const Text('Playlists', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  const _Legend(color: Color(0xFF2ECC71), text: 'Active'),
                  const SizedBox(width: 18),
                  const _Legend(color: C.danger, text: 'Expired'),
                  const SizedBox(width: 18),
                  const _Legend(color: C.dim, text: 'Not checked'),
                ],
              ),
              const SizedBox(height: 22),
              Expanded(
                child: _error != null
                    ? Text(_error!, style: const TextStyle(color: C.danger))
                    : lists == null
                        ? const Loading()
                        : lists.isEmpty
                            ? const Center(
                                child: Text('No playlists on your account yet.\nAdd one from the website (Upload Playlist / QR).',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: C.dim, fontSize: 15, height: 1.5)),
                              )
                            : ListView(
                                children: [
                                  for (var i = 0; i < lists.length; i++)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _row(lists[i], i == 0),
                                    ),
                                ],
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BPlaylist p, bool first) {
    final key = _key(p);
    final state = _known[key] ?? _State.checking;
    final exp = _expires[key];
    final color = switch (state) {
      _State.active => const Color(0xFF2ECC71),
      _State.expired => C.danger,
      _ => C.dim,
    };
    final label = switch (state) {
      _State.checking => 'Checking…',
      _State.active => exp == null
          ? 'Active'
          : 'Active until ${exp.day.toString().padLeft(2, '0')}-${exp.month.toString().padLeft(2, '0')}-${exp.year}',
      _State.expired => 'Expired',
      _State.unknown => 'Not checked',
    };
    final now = p.name == widget.current || p.username == widget.current;
    return Row(
      children: [
        Expanded(child: _main(p, first, now, color, label, state)),
        const SizedBox(width: 10),
        TvFocus(
          radius: 12,
          color: C.panel,
          focusBorder: C.danger,
          onTap: () => _delete(p),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_outline_rounded, color: C.danger, size: 22),
                SizedBox(width: 6),
                Text('Delete', style: TextStyle(color: C.danger, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _main(BPlaylist p, bool first, bool now, Color color, String label, _State state) {
    return TvFocus(
      autofocus: first,
      radius: 12,
      color: C.panel,
      selected: now,
      onTap: () => _pick(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            _Dot(color: color, pulsing: state == _State.checking),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(5)),
                        child: Text(p.isXtream ? 'XTREAM' : 'M3U',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: C.dim)),
                      ),
                      if (now) ...[
                        const SizedBox(width: 8),
                        const Text('Now playing',
                            style: TextStyle(fontSize: 12, color: C.accent, fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(fontSize: 13.5, color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _Dot(color: color),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 13, color: C.dim)),
        ],
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.pulsing = false});
  final Color color;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
      ),
    );
    if (!pulsing) return dot;
    return const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: C.dim));
  }
}
