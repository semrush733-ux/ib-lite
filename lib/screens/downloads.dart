import 'package:flutter/material.dart';

import '../download_ui.dart';
import '../downloads.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'player.dart';

/// Films kept on this device: watch without internet, pause / resume / delete.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.api});
  final Source api;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  String _structure = '';

  @override
  void initState() {
    super.initState();
    Downloads.i.addListener(_changed);
    Downloads.i.init();
  }

  @override
  void dispose() {
    Downloads.i.removeListener(_changed);
    super.dispose();
  }

  /// The rows are rebuilt only when an item's state changes; the bars update themselves.
  void _changed() {
    final s = Downloads.i.items.map((d) => '${d.id}:${d.state.name}').join(',');
    if (s != _structure && mounted) setState(() => _structure = s);
  }

  Future<void> _play(DlItem d) async {
    final url = Downloads.i.localUrl(d.id);
    if (url == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        api: widget.api,
        entries: [
          PlayEntry(
            title: d.title,
            subtitle: d.subtitle,
            urls: [url],
            resumeKey: d.id,
            logo: d.cover,
          ),
        ],
        index: 0,
        live: false,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = Downloads.i.items;
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 18, 28, 6),
              child: Row(
                children: [
                  TvFocus(
                    radius: 22,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.arrow_back_rounded, size: 24)),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.download_rounded, color: C.accent, size: 26),
                  const SizedBox(width: 10),
                  const Text('Downloads', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('${items.length} ${items.length == 1 ? 'film' : 'films'}', style: const TextStyle(color: C.dim, fontSize: 14)),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text('Nothing downloaded yet.\nOpen a film and press Download — it plays here without internet.',
                          textAlign: TextAlign.center, style: TextStyle(color: C.dim, fontSize: 15, height: 1.5)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(28, 10, 28, 28),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _row(items[i], first: i == 0),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(DlItem d, {bool first = false}) {
    final running = d.state == DlState.running || d.state == DlState.queued || d.state == DlState.waiting;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xCC1A1E28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: 58, height: 86, child: NetImage(d.cover, fit: BoxFit.cover, cacheWidth: 160, fallback: Icons.movie_rounded)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                if (d.subtitle.isNotEmpty)
                  Text(d.subtitle, maxLines: 1, style: const TextStyle(fontSize: 12.5, color: C.dim)),
                const SizedBox(height: 10),
                ListenableBuilder(
                  listenable: Downloads.i,
                  builder: (context, _) => DownloadLine(d: d, compact: true),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (d.done) _btn(Icons.play_arrow_rounded, 'Watch', () => _play(d), primary: true, autofocus: first),
          if (running) _btn(Icons.pause_rounded, 'Pause', () => Downloads.i.pause(d.id), autofocus: first),
          if (d.state == DlState.paused || d.state == DlState.failed)
            _btn(Icons.play_for_work_rounded, d.state == DlState.failed ? 'Try again' : 'Resume', () => Downloads.i.resume(d.id), autofocus: first),
          const SizedBox(width: 8),
          _btn(Icons.delete_outline_rounded, 'Delete', () => _confirmDelete(d)),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(DlItem d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1E28),
        title: Text(d.done ? 'Delete this film from the TV?' : 'Cancel this download?'),
        content: Text(d.title),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: C.accent))),
        ],
      ),
    );
    if (ok == true) Downloads.i.remove(d.id);
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap, {bool primary = false, bool autofocus = false}) {
    return TvFocus(
      autofocus: autofocus,
      radius: 22,
      color: primary ? C.accent : const Color(0x22FFFFFF),
      focusBorder: primary ? Colors.white : C.accent,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: primary ? C.onAccent : C.text),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: primary ? C.onAccent : C.text)),
          ],
        ),
      ),
    );
  }
}
