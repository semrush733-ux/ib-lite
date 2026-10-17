import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'main.dart' show toast, SettingsPage;

const _red = Color(0xFFE3262F);
const _card = Color(0xFF1B1113);
const _line = Color(0xFF3A2A2D);
const _muted = Color(0xFFB9A9AC);
const _green = Color(0xFF22C55E);
const _amber = Color(0xFFF5B400);

Color statusColor(String s) => switch (s) {
      'active' => _green,
      'trial' => const Color(0xFF1E88FF),
      'expired' => const Color(0xFFFF7B81),
      'suspended' => const Color(0xFF9E9E9E),
      _ => _muted,
    };

String statusName(String s) => switch (s) {
      'suspended' => 'Blocked',
      'active' => 'Active',
      'trial' => 'Trial',
      'expired' => 'Expired',
      _ => s,
    };

// ------------------------------------------------------------------------------------------ data

class TvPlaylist2 {
  TvPlaylist2(Map<String, dynamic> j)
      : id = (j['id'] as num?)?.toInt() ?? 0,
        name = '${j['name'] ?? ''}',
        username = '${j['username'] ?? ''}',
        locked = j['locked'] == true,
        owner = '${j['owner'] ?? ''}';
  final int id;
  final String name, username, owner;
  final bool locked;
}

class TvDevice {
  TvDevice(Map<String, dynamic> j)
      : id = '${j['device_id'] ?? ''}',
        mac = '${j['mac'] ?? j['device_id'] ?? ''}',
        status = '${j['status'] ?? ''}',
        plan = '${j['plan'] ?? ''}',
        ends = '${j['ends'] ?? ''}',
        daysLeft = (j['days_left'] as num?)?.toInt() ?? 0,
        online = j['online'] == true,
        lastSeen = '${j['last_seen'] ?? ''}',
        country = '${j['country'] ?? ''}',
        app = '${j['app'] ?? ''}',
        playlists = [for (final p in (j['playlists'] as List? ?? const [])) TvPlaylist2(p as Map<String, dynamic>)];
  final String id, mac, status, plan, ends, lastSeen, country, app;
  final int daysLeft;
  final bool online;
  final List<TvPlaylist2> playlists;

  String get title => playlists.isEmpty ? mac : (playlists.first.username.isNotEmpty ? playlists.first.username : playlists.first.name);
  String get owners => playlists.map((p) => p.owner).where((o) => o.isNotEmpty).toSet().join(', ');
}

class Panel {
  Panel._();

  static Future<Map<String, dynamic>> dashboard() => Api.call('/panel/dashboard');

  static Future<List<TvDevice>> devices({String filter = 'all', String q = '', int days = 7, int reseller = 0}) async {
    final j = await Api.call('/panel/devices', query: {
      'filter': filter,
      if (q.isNotEmpty) 'q': q,
      'days': '$days',
      if (reseller > 0) 'reseller': '$reseller',
    });
    return [for (final d in (j['devices'] as List? ?? const [])) TvDevice(d as Map<String, dynamic>)];
  }

  /// To the chosen TVs, or (all) to every TV of a filter.
  static Future<String> notify({List<String> ids = const [], bool all = false, String filter = 'all', required String title, required String body}) async {
    final j = await Api.call('/panel/notify', body: {
      'title': title,
      'body': body,
      if (all) 'all': '1',
      if (all) 'filter': filter,
      if (!all) 'device_ids': ids,
    });
    return '${j['message']}';
  }

  static Future<String> command(String action, List<String> ids, {int playlistId = 0}) async {
    final j = await Api.call('/panel/command', body: {'action': action, 'device_ids': ids, if (playlistId > 0) 'playlist_id': playlistId});
    return '${j['message']}';
  }
}

// ------------------------------------------------------------------------------------- dashboard

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => DashboardPageState();
}

class DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? _d;
  String? _error;
  final _dlKey = GlobalKey<DownloaderCardState>();

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      unawaited(_dlKey.currentState?.reload());
      final d = await Panel.dashboard();
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _open(String filter, String title) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DevicesPage(filter: filter, title: title)));
  }

  @override
  Widget build(BuildContext context) {
    final p = Api.profile;
    final c = (_d?['counts'] as Map?) ?? const {};
    int n(String k) => (c[k] as num?)?.toInt() ?? 0;
    final tiles = <(String, String, String, IconData, Color)>[
      ('online', 'Online now', '${n('online')}', Icons.wifi_tethering_rounded, _green),
      ('active', 'Active', '${n('active')}', Icons.verified_rounded, _green),
      ('trial', 'On trial', '${n('trial')}', Icons.hourglass_bottom_rounded, const Color(0xFF1E88FF)),
      ('expiring', 'Ending in 7 days', '${n('expiring7')}', Icons.notification_important_rounded, _amber),
      ('expired', 'Expired', '${n('expired')}', Icons.timer_off_rounded, const Color(0xFFFF7B81)),
      ('suspended', 'Blocked', '${n('suspended')}', Icons.block_rounded, const Color(0xFF9E9E9E)),
      ('all', 'All TVs', '${n('total')}', Icons.tv_rounded, _muted),
      ('lifetime', 'Lifetime', '${n('lifetime')}', Icons.all_inclusive_rounded, const Color(0xFFB37BFF)),
    ];
    final top = (_d?['top'] as List?) ?? const [];
    return RefreshIndicator(
      onRefresh: reload,
      color: _red,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (Api.impersonating) const _AsBanner(),
          if (((_d?['servers_bad'] as num?)?.toInt() ?? 0) > 0)
            Card(
              color: const Color(0x33FF4D4D),
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFFF4D4D))),
              child: ListTile(
                leading: const Icon(Icons.dns_rounded, color: Color(0xFFFF4D4D)),
                title: Text('${_d?['servers_bad']} server(s) have a DNS / connection problem',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Tap to see which', style: TextStyle(color: _muted)),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HealthPage())),
              ),
            ),
          Text('Hello ${p?.name ?? ''}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          Text(p?.isSuper == true ? 'Every TV on your website' : 'Your clients and your team\'s',
              style: const TextStyle(color: _muted)),
          const SizedBox(height: 14),
          DownloaderCard(key: _dlKey),
          const SizedBox(height: 14),
          if (_error != null) Text(_error!, style: const TextStyle(color: Color(0xFFFF8A90))),
          if (_d == null && _error == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          if (_d != null) ...[
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.7,
              children: [
                for (final t in tiles)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _open(t.$1, t.$2),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.$5.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            Icon(t.$4, color: t.$5, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(t.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted))),
                          ]),
                          Text(t.$3, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
              child: Row(
                children: [
                  Expanded(child: _big('Activations this month', '${n('month_activations')}')),
                  Expanded(child: _big('Credits used this month', '${_d?['credits_month'] ?? 0}')),
                ],
              ),
            ),
            if (top.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Top sellers this month', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (var i = 0; i < top.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(backgroundColor: _red.withValues(alpha: 0.18), child: Text('${i + 1}')),
                  title: Text('${(top[i] as Map)['username']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: Text('${(top[i] as Map)['activations']} activations · ${(top[i] as Map)['credits']} cr',
                      style: const TextStyle(color: _muted)),
                ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotifyPage())),
                    icon: const Icon(Icons.campaign_rounded),
                    label: const Text('Send message'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _open('expiring', 'Ending in 7 days'),
                    icon: const Icon(Icons.notification_important_rounded),
                    label: const Text('Ending soon'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _big(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: _muted, fontSize: 12.5)),
        ],
      );
}

/// Shown while the super admin looks at the app as another account.
class _AsBanner extends StatelessWidget {
  const _AsBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14), border: Border.all(color: _amber)),
      child: Text('You are looking at the app as ${Api.profile?.name ?? 'another account'}. More → "Back to my account" returns.',
          style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

// -------------------------------------------------------------------------- TVs (search, select)

/// TVs with search and filters. Tap one for its actions; "Select" picks several for one message
/// or one action. With [pick] it returns the chosen ids instead (for the message screen).
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, this.filter = 'all', this.title = 'TVs', this.pick = false, this.initial = const []});
  final String filter;
  final String title;
  final bool pick;
  final List<String> initial;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  late String _filter = widget.filter;
  final _q = TextEditingController();
  List<TvDevice>? _list;
  String? _error;
  late final Set<String> _chosen = {...widget.initial};
  late bool _selecting = widget.pick;
  bool _busy = false;

  static const _filters = [
    ('all', 'All'),
    ('online', 'Online'),
    ('active', 'Active'),
    ('trial', 'Trial'),
    ('expiring', 'Ending soon'),
    ('expired', 'Expired'),
    ('suspended', 'Blocked'),
    ('lifetime', 'Lifetime'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final l = await Panel.devices(filter: _filter, q: _q.text.trim());
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _bulk(String action) async {
    final ids = _chosen.toList();
    if (ids.isEmpty) return;
    final ok = await confirm(context, '${actionName(action)} ${ids.length} TV(s)?');
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final m = await Panel.command(action, ids);
      if (!mounted) return;
      toast(context, m);
      setState(() {
        _selecting = false;
        _chosen.clear();
      });
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pick ? 'Choose TVs' : widget.title),
        actions: [
          if (list != null && list.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                _selecting = true;
                final all = list.map((d) => d.id).toSet();
                if (_chosen.containsAll(all)) {
                  _chosen.removeAll(all);
                } else {
                  _chosen.addAll(all);
                }
              }),
              child: const Text('All'),
            ),
          if (!widget.pick)
            TextButton(
              onPressed: () => setState(() {
                _selecting = !_selecting;
                if (!_selecting) _chosen.clear();
              }),
              child: Text(_selecting ? 'Cancel' : 'Select'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'MAC address, playlist name or login',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _load),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in _filters)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: _filter == f.$1,
                      onSelected: (_) {
                        setState(() => _filter = f.$1);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8A90)))),
          Expanded(
            child: list == null
                ? (_error == null ? const Center(child: CircularProgressIndicator()) : const SizedBox())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: list.isEmpty
                        ? ListView(children: const [
                            Padding(padding: EdgeInsets.all(40), child: Text('No TVs here.', textAlign: TextAlign.center, style: TextStyle(color: _muted))),
                          ])
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final d = list[i];
                              final on = _chosen.contains(d.id);
                              return Card(
                                color: on ? _red.withValues(alpha: 0.14) : _card,
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14), side: BorderSide(color: on ? _red : _line)),
                                child: ListTile(
                                  onTap: () async {
                                    if (_selecting) {
                                      setState(() => on ? _chosen.remove(d.id) : _chosen.add(d.id));
                                      return;
                                    }
                                    final changed = await showModalBottomSheet<bool>(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: const Color(0xFF170E10),
                                      builder: (_) => DeviceSheet(d: d),
                                    );
                                    if (changed == true) _load();
                                  },
                                  onLongPress: widget.pick
                                      ? null
                                      : () => setState(() {
                                            _selecting = true;
                                            _chosen.add(d.id);
                                          }),
                                  leading: _selecting
                                      ? Checkbox(value: on, onChanged: (_) => setState(() => on ? _chosen.remove(d.id) : _chosen.add(d.id)))
                                      : Icon(Icons.circle, size: 12, color: d.online ? _green : const Color(0xFF5A4A4D)),
                                  title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                    [
                                      d.mac,
                                      if (d.owners.isNotEmpty) 'by ${d.owners}',
                                      if (d.country.isNotEmpty) d.country,
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: _muted, fontSize: 12.5),
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(statusName(d.status), style: TextStyle(color: statusColor(d.status), fontWeight: FontWeight.w800)),
                                      Text(d.plan == 'lifetime' ? 'lifetime' : (d.ends.isEmpty ? '' : '${d.daysLeft} days'),
                                          style: const TextStyle(color: _muted, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: !_selecting
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                color: const Color(0xFF140B0D),
                child: widget.pick
                    ? FilledButton(
                        onPressed: () => Navigator.of(context).pop(_chosen.toList()),
                        child: Text('Use ${_chosen.length} TV(s)'),
                      )
                    : Row(
                        children: [
                          Text('${_chosen.length}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 6,
                              children: [
                                _act(Icons.campaign_rounded, 'Message', _busy || _chosen.isEmpty
                                    ? null
                                    : () => Navigator.of(context).push(MaterialPageRoute<void>(
                                        builder: (_) => NotifyPage(initial: _chosen.toList())))),
                                _act(Icons.refresh_rounded, 'Reload', _busy || _chosen.isEmpty ? null : () => _bulk('refresh')),
                                _act(Icons.block_rounded, 'Block', _busy || _chosen.isEmpty ? null : () => _bulk('block')),
                                _act(Icons.check_circle_outline, 'Unblock', _busy || _chosen.isEmpty ? null : () => _bulk('unblock')),
                                _act(Icons.timer_off_rounded, 'Expire', _busy || _chosen.isEmpty ? null : () => _bulk('expire')),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
    );
  }

  Widget _act(IconData icon, String label, VoidCallback? onTap) => TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}

String actionName(String a) => switch (a) {
      'refresh' => 'Reload the playlist on',
      'block' => 'Block',
      'unblock' => 'Unblock',
      'expire' => 'End the trial / licence now on',
      _ => a,
    };

/// One tap: the trial or licence of a TV ends now (the TV shows the activation screen in a few minutes).
Future<void> expireNow(BuildContext context, String id, String mac, String status, Future<void> Function(Future<String> Function()) run) async {
  final what = status == 'trial' ? 'trial' : 'licence';
  final ok = await confirm(context, 'End the $what of $mac now?\n\nThe TV shows the activation screen within a few minutes. Activate it again or renew to undo.');
  if (ok == true) await run(() => Panel.command('expire', [id]));
}

Future<bool?> confirm(BuildContext context, String text) => showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );

/// One TV: what it is, and everything that can be done to it.
class DeviceSheet extends StatefulWidget {
  const DeviceSheet({super.key, required this.d});
  final TvDevice d;

  @override
  State<DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends State<DeviceSheet> {
  bool _busy = false;

  Future<void> _run(Future<String> Function() job, {bool close = true}) async {
    setState(() => _busy = true);
    try {
      final m = await job();
      if (!mounted) return;
      toast(context, m);
      if (close) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reminder() {
    final d = widget.d;
    final name = d.title;
    final text = d.status == 'expired'
        ? 'Hello $name, your IPTV player licence has ended. Reply here to renew it and keep watching.'
        : 'Hello $name, your IPTV player ${d.status == 'trial' ? 'trial' : 'licence'} ends in ${d.daysLeft} day(s)'
            '${d.ends.isNotEmpty ? ' (${d.ends})' : ''}. Reply here to renew it without a break.';
    Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final blocked = d.status == 'suspended';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(d.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            SelectableText(d.mac, style: const TextStyle(color: _muted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip(statusName(d.status), statusColor(d.status)),
                _chip(d.online ? 'Online' : 'Offline', d.online ? _green : _muted),
                if (d.plan == 'lifetime') _chip('Lifetime', const Color(0xFFB37BFF)),
                if (d.ends.isNotEmpty && d.plan != 'lifetime') _chip('Ends ${d.ends}', _amber),
                if (d.country.isNotEmpty) _chip(d.country, _muted),
                if (d.app.isNotEmpty) _chip('App build ${d.app}', _muted),
              ],
            ),
            const SizedBox(height: 14),
            for (final p in d.playlists)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text([if (p.username.isNotEmpty) p.username, if (p.owner.isNotEmpty) 'by ${p.owner}', if (p.locked) 'PIN'].join(' · '),
                              style: const TextStyle(color: _muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    if (p.locked)
                      TextButton(
                        onPressed: _busy ? null : () => _run(() => Panel.command('pin_reset', [d.id], playlistId: p.id)),
                        child: const Text('Remove PIN'),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NotifyPage(initial: [d.id]))),
              icon: const Icon(Icons.campaign_rounded),
              label: const Text('Send a message to this TV'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(() => Panel.command('refresh', [d.id])),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reload'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: blocked ? _green : const Color(0xFFFF7B81)),
                    onPressed: _busy ? null : () => _run(() => Panel.command(blocked ? 'unblock' : 'block', [d.id])),
                    icon: Icon(blocked ? Icons.check_circle_outline : Icons.block_rounded),
                    label: Text(blocked ? 'Unblock' : 'Block'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy || blocked ? null : () => _run(() => Api.activate(d.id, 'year')),
                    child: const Text('Renew 1 year'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy || blocked ? null : () => _run(() => Api.activate(d.id, 'lifetime')),
                    child: const Text('Lifetime'),
                  ),
                ),
              ],
            ),
            if (d.status == 'trial' || d.status == 'active') ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF7B81)),
                onPressed: _busy ? null : () => expireNow(context, d.id, d.mac, d.status, _run),
                icon: const Icon(Icons.timer_off_rounded),
                label: Text(d.status == 'trial' ? 'End the trial now' : 'End the licence now'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _reminder,
              icon: const Icon(Icons.chat_rounded),
              label: const Text('Send a renewal reminder (WhatsApp…)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12.5)),
      );
}

// --------------------------------------------------------------------------------- send message

class NotifyPage extends StatefulWidget {
  const NotifyPage({super.key, this.initial = const []});
  final List<String> initial;

  @override
  State<NotifyPage> createState() => _NotifyPageState();
}

class _NotifyPageState extends State<NotifyPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late List<String> _ids = [...widget.initial];
  // chosen | all | online | expiring | expired | trial
  late String _to = widget.initial.isEmpty ? 'all' : 'chosen';
  bool _busy = false;

  static const _groups = [
    ('chosen', 'Chosen TVs'),
    ('all', 'All my TVs'),
    ('online', 'Online now'),
    ('expiring', 'Ending in 7 days'),
    ('trial', 'On trial'),
    ('expired', 'Expired'),
  ];

  Future<void> _choose() async {
    final ids = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(builder: (_) => DevicesPage(pick: true, initial: _ids)));
    if (ids != null && mounted) {
      setState(() {
        _ids = ids;
        _to = 'chosen';
      });
    }
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty && _body.text.trim().isEmpty) {
      toast(context, 'Write a title or a message.', error: true);
      return;
    }
    if (_to == 'chosen' && _ids.isEmpty) {
      toast(context, 'Choose the TVs first.', error: true);
      return;
    }
    final who = _to == 'chosen' ? '${_ids.length} chosen TV(s)' : _groups.firstWhere((g) => g.$1 == _to).$2.toLowerCase();
    final ok = await confirm(context, 'Send this message to $who?');
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final m = await Panel.notify(
        ids: _ids,
        all: _to != 'chosen',
        filter: _to,
        title: _title.text.trim(),
        body: _body.text.trim(),
      );
      if (!mounted) return;
      toast(context, m);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Message to TVs')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Text('Send to', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final g in _groups)
                ChoiceChip(
                  label: Text(g.$1 == 'chosen' && _ids.isNotEmpty ? 'Chosen TVs (${_ids.length})' : g.$2),
                  selected: _to == g.$1,
                  onSelected: (_) => g.$1 == 'chosen' ? _choose() : setState(() => _to = g.$1),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextButton.icon(onPressed: _choose, icon: const Icon(Icons.checklist_rounded), label: const Text('Choose TVs from the list')),
          const SizedBox(height: 10),
          TextField(
            controller: _title,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Server maintenance tonight', prefixIcon: Icon(Icons.title)),
          ),
          TextField(
            controller: _body,
            minLines: 4,
            maxLines: 8,
            maxLength: 1500,
            decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true),
          ),
          const Text('It appears on the TV screen within a few minutes, with an OK button. A TV that is off sees it when it is turned on.',
              style: TextStyle(color: _muted, fontSize: 12.5)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------------------------- more tab

class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.onChanged, required this.onSwitched});
  final VoidCallback onChanged;
  final VoidCallback onSwitched;

  @override
  Widget build(BuildContext context) {
    final superAdmin = Api.profile?.isSuper == true;
    void go(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    Widget tile(IconData icon, String title, String sub, VoidCallback onTap, {Color color = _red}) => Card(
          color: _card,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _line)),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.16), child: Icon(icon, color: color)),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(sub, style: const TextStyle(color: _muted, fontSize: 12.5)),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text('More', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (Api.impersonating)
          tile(Icons.undo_rounded, 'Back to my account', 'Leave ${Api.profile?.name ?? 'this account'}', () async {
            await Api.backToMine();
            onSwitched();
          }, color: _amber),
        tile(Icons.install_mobile_rounded, 'App downloads', 'Downloader code and links for every app', () => go(const DownloadsPage()), color: const Color(0xFF1E88FF)),
        tile(Icons.campaign_rounded, 'Send a message', 'To one TV, chosen TVs or all of them', () => go(const NotifyPage())),
        tile(Icons.tv_rounded, 'All TVs', 'Search by MAC, name or login; block, reload, renew', () => go(const DevicesPage(title: 'All TVs'))),
        tile(Icons.notification_important_rounded, 'Ending soon', 'Renew or remind before they stop', () => go(const DevicesPage(filter: 'expiring', title: 'Ending in 7 days')), color: _amber),
        tile(Icons.monitor_heart_rounded, 'Server health (DNS)', 'Every server, DNS check, alerts to your phone', () => go(const HealthPage()), color: _green),
        tile(Icons.report_problem_rounded, 'Problem reports', 'Sent from the TVs: what went wrong, TV model, app log', () => go(const ProblemsPage()), color: _amber),
        tile(Icons.download_rounded, 'Backup to Excel (CSV)', 'Every TV with status, plan and playlists', () => exportCsv(context)),
        if (superAdmin) ...[
          tile(Icons.system_update_rounded, 'App updates', 'Send a new build to all TVs or to test TVs first', () => go(const UpdatesPage()), color: const Color(0xFF1E88FF)),
          tile(Icons.palette_rounded, 'App look', 'Name, app name under the icon, icon, intro, news', () => go(const BrandingPage()), color: const Color(0xFFB37BFF)),
          tile(Icons.sell_rounded, 'Prices and trial', 'Trial days, yearly and lifetime price', () => go(const PricingPage()), color: _amber),
          tile(Icons.history_rounded, 'Activity log', 'Who did what, and when', () => go(const LogsPage()), color: _muted),
        ],
        tile(Icons.settings_rounded, 'Settings', 'Your server, replace a server, sign out', () => go(Scaffold(
              appBar: AppBar(title: const Text('Settings')),
              body: SettingsPage(onChanged: onChanged),
            )), color: _muted),
      ],
    );
  }
}

Future<void> exportCsv(BuildContext context) async {
  try {
    final j = await Api.call('/panel/export');
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${j['file'] ?? 'clients.csv'}');
    await f.writeAsString('${j['csv'] ?? ''}');
    await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv')], subject: 'Clients backup');
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
  }
}

// ---------------------------------------------------------------------------------- server health

class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

/// Every IPTV server (DNS) the playlists use, as the website sees it (it checks them every
/// 10 minutes, also when this app is closed, and sends alerts to the phone). "Check now" asks
/// the website to look again; "From this phone" tests from where the phone is.
class _HealthPageState extends State<HealthPage> {
  List<Map<String, dynamic>> _servers = const [];
  List<Map<String, dynamic>> _alerts = const [];
  Map<String, dynamic>? _notify;
  int _now = 0;
  String? _error;
  bool _busy = false;
  final Map<String, String> _phone = {}; // server -> result from this phone

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool check = false}) async {
    setState(() => _busy = true);
    try {
      final j = check
          ? await Api.call('/panel/server-health', body: {'check': '1'})
          : await Api.call('/panel/server-health');
      if (!mounted) return;
      setState(() {
        _servers = [for (final s in (j['servers'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)];
        _alerts = [for (final a in (j['alerts'] as List? ?? const [])) Map<String, dynamic>.from(a as Map)];
        _notify = j['notify'] is Map ? Map<String, dynamic>.from(j['notify'] as Map) : null;
        _now = (j['now'] as num?)?.toInt() ?? 0;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _fromPhone(String server) async {
    setState(() => _phone[server] = 'checking…');
    final sw = Stopwatch()..start();
    String r;
    try {
      final res = await http.get(Uri.parse('$server/player_api.php')).timeout(const Duration(seconds: 8));
      r = 'answers from this phone in ${sw.elapsedMilliseconds} ms (${res.statusCode})';
    } on TimeoutException {
      r = 'no answer from this phone in 8 s';
    } catch (_) {
      r = 'this phone cannot reach it (DNS or connection)';
    }
    if (mounted) setState(() => _phone[server] = r);
  }

  String _ago(int t) {
    if (t <= 0 || _now <= 0) return 'not checked yet';
    final m = ((_now - t) / 60).floor();
    if (m < 1) return 'just now';
    if (m < 60) return '$m min ago';
    return '${(m / 60).floor()} h ago';
  }

  (Color, String) _look(String status) => switch (status) {
        'up' => (_green, 'OK'),
        'dns' => (const Color(0xFFFF4D4D), 'DNS NOT FOUND'),
        'down' => (const Color(0xFFFF8A3D), 'NOT ANSWERING'),
        _ => (_muted, 'WAITING'),
      };

  Future<void> _notifySheet() async {
    final n = _notify ?? const {};
    final token = TextEditingController();
    final chat = TextEditingController(text: '${n['telegram_chat'] ?? ''}');
    final topic = TextEditingController(text: '${n['ntfy_topic'] ?? ''}');
    var on = (n['on'] ?? 1) == 1;
    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBox) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Alerts to my phone', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('When a server stays bad for two checks (about 20 minutes) a message comes, and again when it works.',
                    style: TextStyle(color: _muted)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: on,
                  onChanged: (v) => setBox(() => on = v),
                  title: const Text('Send alerts'),
                ),
                TextField(
                  controller: token,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: 'Telegram bot token',
                      helperText: n['telegram_set'] == true ? 'Saved. Empty = keep it.' : 'Telegram → @BotFather → /newbot'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: chat,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Telegram chat ID', helperText: 'Message your bot once, then @userinfobot shows your ID'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: topic,
                  decoration: const InputDecoration(
                      labelText: 'ntfy topic (optional)', helperText: 'Free "ntfy" app: subscribe to the same name'),
                ),
                const SizedBox(height: 14),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
              ],
            ),
          ),
        ),
      ),
    );
    if (save != true) return;
    try {
      final j = await Api.call('/panel/server-health', body: {
        'save_notify': '1',
        'on': on ? '1' : '',
        if (token.text.trim().isNotEmpty) 'telegram_token': token.text.trim(),
        'telegram_chat': chat.text.trim(),
        'ntfy_topic': topic.text.trim(),
      });
      if (mounted) toast(context, '${j['message']}');
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _test() async {
    try {
      final j = await Api.call('/panel/server-health', body: {'test': '1'});
      if (mounted) toast(context, '${j['message']}');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bad = _servers.where((s) => s['status'] == 'dns' || s['status'] == 'down').toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server health'),
        actions: [
          if (_notify != null)
            IconButton(tooltip: 'Alerts to my phone', onPressed: _notifySheet, icon: const Icon(Icons.notifications_active_rounded)),
          IconButton(tooltip: 'Check now', onPressed: _busy ? null : () => _load(check: true), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(),
        color: _red,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (_error != null) Text(_error!, style: const TextStyle(color: Color(0xFFFF8A90))),
            if (_busy && _servers.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
            if (bad.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: const Color(0x33FF4D4D),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFF4D4D))),
                child: Text('${bad.length} server(s) have a problem: ${bad.map((s) => s['host']).join(', ')}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            if (_notify != null && _notify!['telegram_set'] != true && '${_notify!['ntfy_topic'] ?? ''}'.isEmpty)
              Card(
                color: _card,
                child: ListTile(
                  leading: const Icon(Icons.phonelink_ring_rounded, color: _amber),
                  title: const Text('Get alerts on your phone'),
                  subtitle: const Text('Set up Telegram or ntfy once: tap here', style: TextStyle(color: _muted)),
                  onTap: _notifySheet,
                ),
              ),
            if (_notify != null && (_notify!['telegram_set'] == true || '${_notify!['ntfy_topic'] ?? ''}'.isNotEmpty))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: _test, icon: const Icon(Icons.send_rounded), label: const Text('Send a test alert')),
              ),
            Text('${_servers.length} servers (DNS) · checked by the website every 10 minutes',
                style: const TextStyle(color: _muted, fontSize: 12.5)),
            const SizedBox(height: 8),
            for (final s in _servers)
              Builder(builder: (context) {
                final look = _look('${s['status']}');
                final server = '${s['server']}';
                return Card(
                  color: _card,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14), side: BorderSide(color: look.$1.withValues(alpha: 0.5))),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.dns_rounded, color: look.$1, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText('${s['host']}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: look.$1.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                            child: Text(look.$2, style: TextStyle(color: look.$1, fontWeight: FontWeight.w900, fontSize: 11.5)),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          '$server${'${s['ip']}'.isNotEmpty ? '  ·  IP ${s['ip']}' : ''}'
                          '${(s['ms'] as num? ?? 0) > 0 ? '  ·  ${s['ms']} ms' : ''}\n'
                          '${s['note']}  ·  ${s['playlists']} playlists  ·  ${_ago((s['checked'] as num?)?.toInt() ?? 0)}',
                          style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.4),
                        ),
                        if (_phone[server] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Phone: ${_phone[server]}', style: const TextStyle(fontSize: 12.5)),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(onPressed: () => _fromPhone(server), child: const Text('Test from this phone')),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            if (_alerts.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Alerts', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              for (final a in _alerts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(a['kind'] == 'ok' ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                      color: a['kind'] == 'ok' ? _green : const Color(0xFFFF4D4D)),
                  title: Text('${a['text']}', style: const TextStyle(fontSize: 13.5)),
                  subtitle: Text(_ago((a['at'] as num?)?.toInt() ?? 0), style: const TextStyle(color: _muted, fontSize: 12)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------------- app updates

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key});

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  Map<String, dynamic>? _u;
  final _testers = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _take(Map<String, dynamic> j) {
    _u = j;
    _testers.text = ((j['test_devices'] as List?) ?? const []).join(', ');
    _notes.text = '${j['notes'] ?? ''}';
  }

  Future<void> _load() async {
    try {
      final j = await Api.call('/panel/updates');
      if (mounted) setState(() => _take(j));
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _save(Map<String, dynamic> body, {String? done}) async {
    setState(() => _busy = true);
    try {
      final j = await Api.call('/panel/updates', body: {'save': '1', ...body});
      if (!mounted) return;
      setState(() => _take(j));
      toast(context, done ?? 'Saved.');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addTesters() async {
    final ids = await Navigator.of(context).push<List<String>>(MaterialPageRoute(builder: (_) => const DevicesPage(pick: true)));
    if (ids == null || ids.isEmpty) return;
    final now = _testers.text.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).toSet()..addAll(ids);
    setState(() => _testers.text = now.join(', '));
  }

  @override
  Widget build(BuildContext context) {
    final u = _u;
    final latest = (u?['latest'] as Map?) ?? const {};
    final build = (latest['build'] as num?)?.toInt() ?? 0;
    final ok = latest['ok'] == true;
    final announced = (u?['announced'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('App updates')),
      body: u == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Newest build: ${build > 0 ? '#$build' : 'unknown'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      Text('${latest['msg'] ?? ''}', style: TextStyle(color: ok ? _green : _muted)),
                      const SizedBox(height: 6),
                      Text('TVs are offered: ${announced > 0 ? 'build $announced' : 'nothing'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (u['test_only'] == true) const Text('Only the test TVs see it now.', style: TextStyle(color: _amber)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (ok && build > announced)
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (await confirm(context, 'Offer build $build to ${u['test_only'] == true ? 'the test TVs' : 'all TVs'}?') == true) {
                              _save({'build': build}, done: 'Build $build offered.');
                            }
                          },
                    icon: const Icon(Icons.system_update_rounded),
                    label: Text('Send build $build to the TVs'),
                  ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: u['test_only'] == true,
                  onChanged: _busy ? null : (v) => _save({'test_only': v ? '1' : '0'}),
                  title: const Text('Test TVs first'),
                  subtitle: const Text('Only the TVs below get the update; turn off to send it to everyone.'),
                ),
                TextField(
                  controller: _testers,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Test TVs (MAC addresses, comma separated)'),
                ),
                Row(
                  children: [
                    TextButton.icon(onPressed: _addTesters, icon: const Icon(Icons.add), label: const Text('Add from list')),
                    const Spacer(),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _save({'test_devices': _testers.text.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).toList()}),
                      child: const Text('Save test TVs'),
                    ),
                  ],
                ),
                const Divider(height: 28),
                SwitchListTile(
                  value: u['follow'] == true,
                  onChanged: _busy ? null : (v) => _save({'follow': v ? '1' : '0'}),
                  title: const Text('Follow new builds automatically'),
                  subtitle: const Text('Every good new build is offered to the TVs by itself (within an hour).'),
                ),
                SwitchListTile(
                  value: u['force'] == true,
                  onChanged: _busy ? null : (v) => _save({'force': v ? '1' : '0'}),
                  title: const Text('Must update'),
                  subtitle: const Text('Customers cannot press "Later" (only for a broken version).'),
                ),
                TextField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'What\'s new (shown on the TV)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _busy ? null : () => _save({'notes': _notes.text}), child: const Text('Save text')),
              ],
            ),
    );
  }
}

// -------------------------------------------------------------------------------------- branding

class BrandingPage extends StatefulWidget {
  const BrandingPage({super.key});

  @override
  State<BrandingPage> createState() => _BrandingPageState();
}

class _BrandingPageState extends State<BrandingPage> {
  final Map<String, TextEditingController> _c = {
    for (final k in ['brand', 'app_label', 'logo_name', 'intro_name', 'news_label', 'news_title', 'news_body', 'app_icon_url', 'intro_url', 'intro_seconds'])
      k: TextEditingController(),
  };
  String _introType = 'builtin';
  bool _newsOn = false;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await Api.call('/panel/branding');
      final b = (j['branding'] as Map?) ?? const {};
      if (!mounted) return;
      setState(() {
        for (final e in _c.entries) {
          e.value.text = '${b[e.key] ?? ''}';
        }
        _introType = '${b['intro_type'] ?? 'builtin'}';
        _newsOn = '${b['news_on']}' == '1' || b['news_on'] == true;
        _loaded = true;
      });
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _upload(String field, {bool video = false}) async {
    final picker = ImagePicker();
    final f = video ? await picker.pickVideo(source: ImageSource.gallery) : await picker.pickImage(source: ImageSource.gallery);
    if (f == null) return;
    setState(() => _busy = true);
    try {
      final url = await Api.upload('/panel/branding/upload', f.path);
      if (!mounted) return;
      setState(() => _c[field]!.text = url);
      toast(context, 'Uploaded. Tap Save.');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final j = await Api.call('/panel/branding', body: {
        'save': '1',
        for (final e in _c.entries) e.key: e.value.text.trim(),
        'intro_type': _introType,
        'news_on': _newsOn ? '1' : '0',
      });
      if (mounted) toast(context, '${j['message'] ?? 'Saved.'}');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String key, String label, {String? hint, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _c[key],
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 3,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final icon = _c['app_icon_url']!.text;
    return Scaffold(
      appBar: AppBar(title: const Text('App look')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
              children: [
                _field('brand', 'Brand name (website and app)'),
                _field('app_label', 'App name under the icon', hint: 'needs a new build: made by itself within an hour'),
                _field('logo_name', 'Name on the logo inside the app'),
                _field('intro_name', 'Name in the start animation'),
                const SizedBox(height: 6),
                const Text('App icon (symbol)', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
                      clipBehavior: Clip.antiAlias,
                      child: icon.startsWith('http') ? Image.network(icon, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image)) : const Icon(Icons.image),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _upload('app_icon_url'),
                        icon: const Icon(Icons.upload_rounded),
                        label: const Text('Upload icon (square PNG, 512+)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Start animation (intro)', style: TextStyle(fontWeight: FontWeight.w800)),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in const [('builtin', 'Built-in'), ('image', 'Picture'), ('video', 'Video')])
                      ChoiceChip(label: Text(t.$2), selected: _introType == t.$1, onSelected: (_) => setState(() => _introType = t.$1)),
                  ],
                ),
                if (_introType != 'builtin') ...[
                  const SizedBox(height: 8),
                  _field('intro_url', _introType == 'video' ? 'Video address (MP4)' : 'Picture address'),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _upload('intro_url', video: _introType == 'video'),
                    icon: const Icon(Icons.upload_rounded),
                    label: Text(_introType == 'video' ? 'Upload a video' : 'Upload a picture'),
                  ),
                  const SizedBox(height: 8),
                  _field('intro_seconds', 'Seconds on screen (2–15)'),
                ],
                const Divider(height: 28),
                SwitchListTile(
                  value: _newsOn,
                  onChanged: (v) => setState(() => _newsOn = v),
                  title: const Text('News button on the website'),
                  contentPadding: EdgeInsets.zero,
                ),
                _field('news_label', 'Button text'),
                _field('news_title', 'News title'),
                _field('news_body', 'News text', lines: 3),
                const SizedBox(height: 10),
                FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
              ],
            ),
    );
  }
}

// --------------------------------------------------------------------------------------- pricing

class PricingPage extends StatefulWidget {
  const PricingPage({super.key});

  @override
  State<PricingPage> createState() => _PricingPageState();
}

class _PricingPageState extends State<PricingPage> {
  final _trial = TextEditingController();
  final _year = TextEditingController();
  final _life = TextEditingController();
  final _cur = TextEditingController();
  Map<String, dynamic>? _p;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _take(Map<String, dynamic> j) {
    _p = j;
    _trial.text = '${j['trial_days'] ?? ''}';
    _year.text = '${j['price_year'] ?? ''}';
    _life.text = '${j['price_lifetime'] ?? ''}';
    _cur.text = '${j['currency'] ?? ''}';
  }

  Future<void> _load() async {
    try {
      final j = await Api.call('/panel/pricing');
      if (mounted) setState(() => _take(j));
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final j = await Api.call('/panel/pricing', body: {
        'save': '1',
        'trial_days': int.tryParse(_trial.text.trim()) ?? 0,
        'price_year': _year.text.trim(),
        'price_lifetime': _life.text.trim(),
        'currency': _cur.text.trim(),
      });
      if (!mounted) return;
      setState(() => _take(j));
      toast(context, 'Saved. New TVs get the new trial; prices show on the website.');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      appBar: AppBar(title: const Text('Prices and trial')),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                TextField(
                  controller: _trial,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Free trial (days) for new TVs'),
                ),
                const SizedBox(height: 10),
                TextField(controller: _cur, decoration: const InputDecoration(labelText: 'Currency sign', hintText: '£')),
                const SizedBox(height: 10),
                TextField(controller: _year, decoration: const InputDecoration(labelText: 'Price for 1 year')),
                const SizedBox(height: 10),
                TextField(controller: _life, decoration: const InputDecoration(labelText: 'Price for lifetime')),
                const SizedBox(height: 14),
                Text('Resellers pay ${p['credit_year']} credit for 1 year and ${p['credit_life']} credits for lifetime.',
                    style: const TextStyle(color: _muted)),
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
              ],
            ),
    );
  }
}

// ------------------------------------------------------------------------------------------ logs

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _q = TextEditingController();
  List<Map<String, dynamic>>? _logs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await Api.call('/panel/logs', query: {if (_q.text.trim().isNotEmpty) 'q': _q.text.trim()});
      if (mounted) setState(() => _logs = [for (final l in (j['logs'] as List? ?? const [])) l as Map<String, dynamic>]);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logs = _logs;
    return Scaffold(
      appBar: AppBar(title: const Text('Activity log')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: const InputDecoration(hintText: 'Search (MAC, user, action)', prefixIcon: Icon(Icons.search)),
            ),
          ),
          Expanded(
            child: logs == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: logs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: _line),
                      itemBuilder: (_, i) {
                        final l = logs[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${l['action']}'.replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            [l['detail'], l['device_id'], l['actor']].where((x) => '${x ?? ''}'.isNotEmpty).join(' · '),
                            style: const TextStyle(color: _muted, fontSize: 12.5),
                          ),
                          trailing: Text('${l['at'] ?? ''}'.replaceFirst(' ', '\n'), textAlign: TextAlign.end, style: const TextStyle(color: _muted, fontSize: 11.5)),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------------------- problem reports
// "Report a problem" on the TV: the reason, the customer's note, the TV's model, the last stream
// it played and the app's recent log (no logins or passwords).

class ProblemsPage extends StatefulWidget {
  const ProblemsPage({super.key});

  @override
  State<ProblemsPage> createState() => _ProblemsPageState();
}

class _ProblemsPageState extends State<ProblemsPage> {
  final _q = TextEditingController();
  String _status = 'new';
  List<Map<String, dynamic>>? _reports;
  int _new = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await Api.call('/panel/problems', query: {
        'status': _status,
        if (_q.text.trim().isNotEmpty) 'q': _q.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _reports = [for (final r in (j['reports'] as List? ?? const [])) if (r is Map) Map<String, dynamic>.from(r)];
        _new = int.tryParse('${j['new'] ?? 0}') ?? 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _reports ??= []);
      toast(context, '$e', error: true);
    }
  }

  Future<void> _open(Map<String, dynamic> r) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => ProblemPage(id: int.tryParse('${r['id']}') ?? 0)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _reports;
    return Scaffold(
      appBar: AppBar(title: Text(_new > 0 ? 'Problem reports ($_new new)' : 'Problem reports')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: const InputDecoration(hintText: 'Search (MAC, problem, note, TV model)', prefixIcon: Icon(Icons.search)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                for (final s in const [('new', 'New'), ('done', 'Done'), ('all', 'All')]) ...[
                  ChoiceChip(
                    label: Text(s.$2),
                    selected: _status == s.$1,
                    onSelected: (_) {
                      setState(() {
                        _status = s.$1;
                        _reports = null;
                      });
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: list == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: list.isEmpty
                        ? ListView(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  _status == 'new'
                                      ? 'No new reports.\nWhen a customer presses "Report a problem" on the TV, it shows up here.'
                                      : 'No reports.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: _muted, height: 1.5),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: _line),
                            itemBuilder: (_, i) {
                              final r = list[i];
                              final d = r['details'] is Map ? r['details'] as Map : const {};
                              final stream = d['stream'] is Map ? d['stream'] as Map : const {};
                              final done = r['status'] == 'done';
                              final reason = '${r['reason'] ?? ''}';
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: (done ? _green : _amber).withValues(alpha: 0.16),
                                  child: Icon(done ? Icons.check_rounded : Icons.report_problem_rounded,
                                      color: done ? _green : _amber),
                                ),
                                title: Text(reason.isEmpty ? 'Report #${r['id']}' : reason,
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  [r['device_id'], r['model'], stream['title'], r['note']]
                                      .where((x) => '${x ?? ''}'.trim().isNotEmpty)
                                      .join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: _muted, fontSize: 12.5),
                                ),
                                trailing: Text('${r['at'] ?? ''}'.replaceFirst(' ', '\n'),
                                    textAlign: TextAlign.end, style: const TextStyle(color: _muted, fontSize: 11.5)),
                                onTap: () => _open(r),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class ProblemPage extends StatefulWidget {
  const ProblemPage({super.key, required this.id});
  final int id;

  @override
  State<ProblemPage> createState() => _ProblemPageState();
}

class _ProblemPageState extends State<ProblemPage> {
  Map<String, dynamic>? _r;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await Api.call('/panel/problems/view', query: {'id': '${widget.id}'});
      final r = j['report'];
      if (mounted && r is Map) setState(() => _r = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _setDone(bool done) async {
    setState(() => _busy = true);
    try {
      await Api.call('/panel/problems/done', body: {'id': widget.id, 'done': done});
      await _load();
      if (mounted) toast(context, done ? 'Marked as done' : 'Opened again');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this report?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: _red))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Api.call('/panel/problems/delete', body: {'id': widget.id});
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  String _asText(Map<String, dynamic> r) {
    final d = r['details'] is Map ? r['details'] as Map : const {};
    final b = StringBuffer()
      ..writeln('Problem report #${r['id']}  ${r['at']}')
      ..writeln('MAC Address: ${r['device_id']}')
      ..writeln('Problem: ${r['reason']}')
      ..writeln('Note: ${r['note']}')
      ..writeln('App: ${r['app_version']} ${r['platform']}')
      ..writeln('TV / box: ${r['model']}');
    for (final part in const ['stream', 'device']) {
      final m = d[part];
      if (m is Map && m.isNotEmpty) {
        b.writeln('');
        b.writeln(part == 'stream' ? 'Last stream:' : 'Device:');
        m.forEach((k, v) => b.writeln('  $k: $v'));
      }
    }
    b
      ..writeln('')
      ..writeln('Log:')
      ..writeln('${r['log'] ?? ''}');
    return b.toString();
  }

  Widget _rows(String title, Map m) {
    final entries = m.entries.where((e) => '${e.value ?? ''}'.trim().isNotEmpty).toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _line)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 8),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 118, child: Text('${e.key}', style: const TextStyle(color: _muted, fontSize: 13))),
                    Expanded(child: SelectableText('${e.value}', style: const TextStyle(fontSize: 13.5))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      appBar: AppBar(title: Text('Report #${widget.id}')),
      body: r == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(builder: (context) {
              final d = r['details'] is Map ? r['details'] as Map : const {};
              final done = r['status'] == 'done';
              final log = '${r['log'] ?? ''}';
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${r['reason'] ?? ''}'.isEmpty ? 'Problem report' : '${r['reason']}',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      ),
                      Chip(
                        label: Text(done ? 'Done' : 'New'),
                        backgroundColor: (done ? _green : _amber).withValues(alpha: 0.18),
                        side: BorderSide.none,
                      ),
                    ],
                  ),
                  if ('${r['note'] ?? ''}'.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('"${r['note']}"', style: const TextStyle(fontSize: 15, height: 1.4)),
                  ],
                  const SizedBox(height: 12),
                  _rows('TV', {
                    'MAC Address': r['device_id'],
                    'Sent': r['at'],
                    'TV / box': r['model'],
                    'App': '${r['app_version'] ?? ''} ${r['platform'] ?? ''}'.trim(),
                    'Playlist': d['playlist'],
                    'Server': d['server'],
                    'Language': d['language'],
                    'Profile': d['profile'],
                  }),
                  if (d['stream'] is Map) _rows('Last stream', d['stream'] as Map),
                  if (d['device'] is Map) _rows('Device details', d['device'] as Map),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _setDone(!done),
                        icon: Icon(done ? Icons.undo_rounded : Icons.check_rounded),
                        label: Text(done ? 'Open again' : 'Mark done'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _asText(r)));
                          if (context.mounted) toast(context, 'Report and log copied');
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('Copy'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Share.share(_asText(r), subject: 'Problem report #${widget.id}'),
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('Share'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _delete,
                        icon: const Icon(Icons.delete_outline_rounded, color: _red),
                        label: const Text('Delete'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('App log (newest at the bottom)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0A0B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _line),
                    ),
                    child: SelectableText(
                      log.isEmpty ? '(empty)' : log,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.35),
                    ),
                  ),
                ],
              );
            }),
    );
  }
}

// --------------------------------------------------------------------------------- app downloads

class DlLink {
  DlLink(this.key, this.label, this.url);
  final String key;
  final String label;
  final String url;
}

class Downloads {
  Downloads(this.code, this.shortUrl, this.links);
  final String code;
  final String shortUrl;
  final List<DlLink> links;

  static const _gh = 'https://github.com/semrush733-ux/ib-lite/releases/download/';

  /// Used when the website has an older plugin without /panel/downloads.
  static Downloads fallback() => Downloads('4220938', 'aftv.news/4220938', [
        DlLink('tv_apk', 'TV app (Android TV / Firestick)', '${_gh}latest/LitePlayer.apk'),
        DlLink('admin_apk', 'Admin Panel (Android)', '${_gh}admin-latest/AdminPanel.apk'),
        DlLink('tv_ipa', 'TV app (iPhone / iPad)', '${_gh}ios-latest/LitePlayer.ipa'),
        DlLink('admin_ipa', 'Admin Panel (iPhone / iPad)', '${_gh}admin-ios-latest/AdminPanel.ipa'),
        DlLink('tizen', 'Samsung TV (.wgt)', '${_gh}tizen-latest/LitePlayer.wgt'),
        DlLink('webos', 'LG TV (.ipk)', '${_gh}webos-latest/LitePlayer.ipk'),
      ]);

  static Downloads? cached;

  static Downloads parse(Map<String, dynamic> j) => Downloads(
        '${j['code'] ?? ''}',
        '${j['short_url'] ?? ''}',
        [
          for (final l in (j['links'] as List? ?? const []))
            if (l is Map) DlLink('${l['key']}', '${l['label']}', '${l['url']}'),
        ],
      );

  static Future<Downloads> load() async {
    try {
      cached = parse(await Api.call('/panel/downloads'));
    } catch (_) {
      cached ??= fallback();
    }
    return cached!;
  }

  static Future<Downloads> save(Map<String, String> values) async {
    cached = parse(await Api.call('/panel/downloads', body: {'save': '1', ...values}));
    return cached!;
  }
}

Future<void> _copy(BuildContext context, String text, String what) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, '$what copied');
}

Future<void> _openUrl(BuildContext context, String url) async {
  final u = Uri.tryParse(url.contains('://') ? url : 'https://$url');
  if (u == null || !await launchUrl(u, mode: LaunchMode.externalApplication)) {
    if (context.mounted) toast(context, 'Could not open the link', error: true);
  }
}

/// Copy box at the top of Home: the Downloader code and the short URL.
class DownloaderCard extends StatefulWidget {
  const DownloaderCard({super.key});

  @override
  State<DownloaderCard> createState() => DownloaderCardState();
}

class DownloaderCardState extends State<DownloaderCard> {
  Downloads? _d = Downloads.cached;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final d = await Downloads.load();
    if (mounted) setState(() => _d = d);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null || (d.code.isEmpty && d.shortUrl.isEmpty)) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E88FF).withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.install_mobile_rounded, color: Color(0xFF1E88FF), size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Downloader app', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DownloadsPage())),
              child: const Text('All apps'),
            ),
          ]),
          if (d.code.isNotEmpty) CopyRow(label: 'Code for Downloader App', value: d.code, big: true),
          if (d.shortUrl.isNotEmpty) CopyRow(label: 'Short URL', value: d.shortUrl),
        ],
      ),
    );
  }
}

class CopyRow extends StatelessWidget {
  const CopyRow({super.key, required this.label, required this.value, this.big = false});
  final String label;
  final String value;
  final bool big;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _copy(context, value, label),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
                  SelectableText(value,
                      style: TextStyle(fontSize: big ? 24 : 16, fontWeight: FontWeight.w800, letterSpacing: big ? 2 : 0)),
                ]),
              ),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () => _copy(context, value, label),
              ),
            ]),
          ),
        ),
      );
}

/// More → App downloads: the Downloader code and a link for every app (copy / open / share).
/// The super admin can change them here (or in WordPress → Settings).
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  Downloads? _d = Downloads.cached;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await Downloads.load();
    if (mounted) setState(() => _d = d);
  }

  IconData _icon(String k) => switch (k) {
        'tv_ipa' || 'admin_ipa' => Icons.phone_iphone_rounded,
        'admin_apk' => Icons.admin_panel_settings_rounded,
        'web' => Icons.language_rounded,
        _ => Icons.tv_rounded,
      };

  Future<void> _edit() async {
    final d = _d ?? Downloads.fallback();
    final ctl = <String, TextEditingController>{
      'code': TextEditingController(text: d.code),
      'short_url': TextEditingController(text: d.shortUrl),
      for (final l in Downloads.fallback().links) l.key: TextEditingController(text: ''),
      'web': TextEditingController(text: ''),
    };
    for (final l in d.links) {
      (ctl[l.key] ??= TextEditingController()).text = l.url;
    }
    final names = {
      'code': 'Downloader code',
      'short_url': 'Short URL',
      for (final l in Downloads.fallback().links) l.key: l.label,
      'web': 'Web player',
      for (final l in d.links) l.key: l.label,
    };
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Change downloads', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Text('Every seller sees these. Empty link = hidden.', style: TextStyle(color: _muted)),
              const SizedBox(height: 10),
              for (final e in ctl.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(controller: e.value, decoration: InputDecoration(labelText: names[e.key] ?? e.key)),
                ),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      final n = await Downloads.save({for (final e in ctl.entries) e.key: e.value.text.trim()});
      if (mounted) {
        setState(() => _d = n);
        toast(context, 'Saved');
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(
        title: const Text('App downloads'),
        actions: [
          if (Api.profile?.isSuper == true) IconButton(tooltip: 'Change', icon: const Icon(Icons.edit_rounded), onPressed: _edit),
        ],
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: _red,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (d.code.isNotEmpty) CopyRow(label: 'Code for Downloader App', value: d.code, big: true),
                  if (d.shortUrl.isNotEmpty) CopyRow(label: 'Short URL', value: d.shortUrl),
                  const SizedBox(height: 8),
                  const Text('Firestick / Android TV: open the Downloader app, type the code and press Go.',
                      style: TextStyle(color: _muted, fontSize: 12.5)),
                  const SizedBox(height: 16),
                  const Text('Apps', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  for (final l in d.links)
                    Card(
                      color: _card,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _line)),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: _red.withValues(alpha: 0.16), child: Icon(_icon(l.key), color: _red)),
                        title: Text(l.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(l.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12)),
                        onTap: () => _openUrl(context, l.url),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: 'Copy link', icon: const Icon(Icons.copy_rounded), onPressed: () => _copy(context, l.url, 'Link')),
                          IconButton(tooltip: 'Share', icon: const Icon(Icons.share_rounded), onPressed: () => Share.share('${l.label}\n${l.url}')),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
