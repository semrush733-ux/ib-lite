import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'more.dart';
import 'scan.dart';
import 'users.dart';

const _red = Color(0xFFE3262F);
const _bg = Color(0xFF0D0809);
const _card = Color(0xFF1B1113);
const _line = Color(0xFF3A2A2D);
const _muted = Color(0xFFB9A9AC);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.init();
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: _red, brightness: Brightness.dark, primary: _red, surface: _card);
    return MaterialApp(
      title: 'Admin Panel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: _bg,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(backgroundColor: _bg, elevation: 0, centerTitle: false),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF140B0D),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
          enabledBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
          focusedBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _red, width: 2)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _red,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      home: Api.signedIn ? const HomeShell() : const LoginScreen(),
    );
  }
}

void toast(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? const Color(0xFF7A1A1F) : const Color(0xFF1F5130),
      behavior: SnackBarBehavior.floating,
    ));
}

// ------------------------------------------------------------------------------------- sign in

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _site = TextEditingController(text: Api.site);
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  // The website is fixed in the app; the field only appears in a build without one.
  final bool _showSite = kDefaultSite.isEmpty;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.signIn(_site.text, _user.text, _pass.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const HomeShell()));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.admin_panel_settings_rounded, size: 64, color: _red),
                  const SizedBox(height: 14),
                  const Text('Admin Panel',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('Sign in with your reseller account',
                      textAlign: TextAlign.center, style: TextStyle(color: _muted)),
                  const SizedBox(height: 28),
                  if (_showSite) ...[
                    TextField(
                      controller: _site,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: 'Website', hintText: 'yourplayer.com', prefixIcon: Icon(Icons.public)),
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: _user,
                    decoration: const InputDecoration(labelText: 'Username or email', prefixIcon: Icon(Icons.person)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    onSubmitted: (_) => _go(),
                    decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock)),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, style: const TextStyle(color: Color(0xFFFF8A90))),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _busy ? null : _go,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : const Text('Sign in'),
                  ),
                  if (!_showSite) ...[
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF2ECC71)),
                        const SizedBox(width: 6),
                        Text('Connected to ${Api.site.replaceFirst(RegExp(r'^https?://'), '')}',
                            style: const TextStyle(color: _muted)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------- shell

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _clientsKey = GlobalKey<_ClientsPageState>();
  final _homeKey = GlobalKey<DashboardPageState>();

  @override
  void initState() {
    super.initState();
    Api.me().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object e) {
      if (!Api.signedIn && mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const LoginScreen()));
      }
    });
  }

  /// Opened as another account (or back): the whole app starts again with that account.
  void _restart() {
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const HomeShell()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    // Sub-resellers create no accounts: no Users tab for them.
    final showUsers = Api.profile == null || Api.profile!.canCreate.isNotEmpty;
    final pages = [
      DashboardPage(key: _homeKey),
      ClientsPage(key: _clientsKey),
      AddClientPage(onAdded: () {
        setState(() => _tab = 1);
        _clientsKey.currentState?.reload();
      }),
      if (showUsers) UsersPage(onChanged: () => setState(() {}), onSwitched: _restart),
      MorePage(onChanged: () => setState(() {}), onSwitched: _restart),
    ];
    if (_tab >= pages.length) _tab = 0;
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF140B0D),
        indicatorColor: _red.withValues(alpha: 0.3),
        selectedIndex: _tab,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 0) _homeKey.currentState?.reload();
          if (i == 1) _clientsKey.currentState?.reload();
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          const NavigationDestination(icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt), label: 'Clients'),
          const NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: 'Add'),
          if (showUsers)
            const NavigationDestination(
                icon: Icon(Icons.manage_accounts_outlined), selectedIcon: Icon(Icons.manage_accounts), label: 'Users'),
          const NavigationDestination(icon: Icon(Icons.apps_rounded), label: 'More'),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------------------------- clients

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  List<Client>? _list;
  String? _error;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final l = await Api.clients(_q.text.trim());
      if (mounted) setState(() {
        _list = l;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Api.profile;
    final list = _list;
    return RefreshIndicator(
      onRefresh: reload,
      color: _red,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p?.brand.isNotEmpty == true ? '${p!.brand} Admin' : 'Admin Panel',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    Text(p == null ? '' : 'Hi ${p.name}', style: const TextStyle(color: _muted)),
                  ],
                ),
              ),
              if (p != null && !p.isSuper)
                _Pill(icon: Icons.toll_rounded, text: '${p.credits ?? 0} credits'),
              if (p != null && p.isSuper) const _Pill(icon: Icons.verified_rounded, text: 'Super admin'),
            ],
          ),
          const SizedBox(height: 16),
          if (p != null && p.server.isEmpty)
            const _Notice(text: 'Set your server address in Settings first — every client you add uses it.'),
          TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => reload(),
            decoration: InputDecoration(
              hintText: 'Search name, username or MAC',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.close), onPressed: () {
                _q.clear();
                reload();
              }),
            ),
          ),
          const SizedBox(height: 14),
          if (_error != null) _Notice(text: _error!),
          if (list == null && _error == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          if (list != null && list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Text('No clients yet.\nTap "Add client" and scan the QR code on the TV.',
                  textAlign: TextAlign.center, style: TextStyle(color: _muted, height: 1.5)),
            ),
          for (final c in list ?? const <Client>[]) _ClientCard(c: c, onChanged: reload),
        ],
      ),
    );
  }
}

Color _statusColor(String s) => switch (s) {
      'active' => const Color(0xFF2ECC71),
      'trial' => const Color(0xFF35A7FF),
      'expired' => const Color(0xFFFF9F1C),
      'suspended' => const Color(0xFFFF5A5F),
      _ => _muted,
    };

String _short(String date) => date.length >= 10 ? date.substring(0, 10) : date;

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.c, required this.onChanged});
  final Client c;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final col = _statusColor(c.status);
    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: _line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final changed = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: const Color(0xFF170E10),
            builder: (_) => ClientSheet(c: c),
          );
          if (changed == true) onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: col.withValues(alpha: 0.18), child: Icon(Icons.tv_rounded, color: col)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                      if (c.locked) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.lock_rounded, size: 15, color: _muted)),
                    ]),
                    const SizedBox(height: 2),
                    Text('${c.deviceId}  ·  ${c.type == 'm3u' ? 'M3U' : 'Xtream'}${c.username.isNotEmpty ? '  ·  ${c.name}' : ''}', style: const TextStyle(color: _muted, fontSize: 12.5)),
                    if (!c.mine && c.owner.isNotEmpty)
                      Text('by ${c.owner}', style: const TextStyle(color: Color(0xFFF5B400), fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(c.status.toUpperCase(), style: TextStyle(color: col, fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(c.plan == 'lifetime' ? 'Lifetime' : (c.expires.isEmpty ? '' : _short(c.expires)),
                      style: const TextStyle(color: _muted, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ClientSheet extends StatefulWidget {
  const ClientSheet({super.key, required this.c});
  final Client c;

  @override
  State<ClientSheet> createState() => _ClientSheetState();
}

class _ClientSheetState extends State<ClientSheet> {
  late final _name = TextEditingController(text: widget.c.name);
  late final _user = TextEditingController(text: widget.c.username);
  final _pass = TextEditingController();
  late final _link = TextEditingController(text: widget.c.url);
  final _pin = TextEditingController();
  bool _removePin = false;
  late String _type = widget.c.type;
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

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final p = Api.profile;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(c.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text('MAC ${c.deviceId}  ·  ${c.status}${c.plan == 'lifetime' ? ' (lifetime)' : c.expires.isNotEmpty ? ' until ${_short(c.expires)}' : ''}',
                style: const TextStyle(color: _muted)),
            const SizedBox(height: 18),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Playlist name on the TV')),
            const SizedBox(height: 12),
            _TypePicker(value: _type, onChanged: (v) => setState(() => _type = v)),
            const SizedBox(height: 12),
            if (_type == 'm3u' && (c.url.isNotEmpty || c.username.isEmpty || c.type != 'm3u')) ...[
              TextField(
                controller: _link,
                minLines: 1,
                maxLines: 3,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'M3U link', prefixIcon: Icon(Icons.link)),
              ),
            ] else ...[
              TextField(controller: _user, decoration: const InputDecoration(labelText: 'Username')),
              const SizedBox(height: 12),
              TextField(controller: _pass, decoration: const InputDecoration(labelText: 'New password (empty = keep)')),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _pin,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: InputDecoration(
                labelText: c.locked ? 'New PIN (empty = keep)' : 'PIN lock (optional, 4 digits)',
                prefixIcon: const Icon(Icons.pin),
                counterText: '',
              ),
            ),
            if (c.locked)
              CheckboxListTile(
                value: _removePin,
                onChanged: (v) => setState(() => _removePin = v ?? false),
                title: const Text('Remove the PIN lock'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => Api.updateClient(c.id,
                      name: _name.text.trim(),
                      username: _user.text.trim(),
                      password: _pass.text,
                      type: _type,
                      m3uUrl: _type == 'm3u' ? _link.text.trim() : null,
                      pin: _pin.text.trim(),
                      removePin: _removePin)),
              child: const Text('Save changes'),
            ),
            const SizedBox(height: 18),
            Text(p != null && !p.isSuper ? 'Activate (1 credit = 1 year, 2 = lifetime)' : 'Activate',
                style: const TextStyle(color: _muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _run(() => Api.activate(c.deviceId, 'year')),
                    child: const Text('1 Year'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _run(() => Api.activate(c.deviceId, 'lifetime')),
                    child: const Text('Lifetime'),
                  ),
                ),
              ],
            ),
            if (c.status == 'trial' || c.status == 'active') ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF7B81)),
                onPressed: _busy ? null : () => expireNow(context, c.deviceId, c.deviceId, c.status, _run),
                icon: const Icon(Icons.timer_off_rounded),
                label: Text(c.status == 'trial' ? 'End the trial now' : 'End the licence now'),
              ),
            ],
            const SizedBox(height: 18),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF7B81)),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove this client from the TV'),
              onPressed: _busy
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: const Text('Remove client?'),
                          content: Text('The playlist "${c.name}" is removed from the TV ${c.deviceId}.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove')),
                          ],
                        ),
                      );
                      if (ok == true) await _run(() => Api.deleteClient(c.id));
                    },
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------- add client

class AddClientPage extends StatefulWidget {
  const AddClientPage({super.key, required this.onAdded});
  final VoidCallback onAdded;

  @override
  State<AddClientPage> createState() => _AddClientPageState();
}

class _AddClientPageState extends State<AddClientPage> {
  final _mac = TextEditingController();
  final _key = TextEditingController();
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _link = TextEditingController();
  final _pin = TextEditingController();
  String _type = 'xtream';
  Device? _device;
  List<TvPlaylist> _onTv = const [];
  bool _busy = false;

  Future<void> _fill((String, String)? r) async {
    if (r == null) return;
    _mac.text = r.$1;
    _key.text = r.$2;
    await _check();
  }

  Future<void> _check() async {
    if (_mac.text.trim().isEmpty || _key.text.trim().isEmpty) {
      toast(context, 'Enter the MAC Address and the Device Key.', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _device = null;
    });
    try {
      final r = await Api.lookup(_mac.text.trim(), _key.text.trim());
      if (mounted) {
        setState(() {
          _device = r.$1;
          _onTv = r.$2;
        });
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    setState(() => _busy = true);
    try {
      final m = await Api.addClient(
        mac: _mac.text.trim(),
        key: _key.text.trim(),
        name: _name.text.trim(),
        username: _user.text.trim(),
        password: _pass.text,
        type: _type,
        m3uUrl: _link.text.trim(),
        pin: _pin.text.trim(),
      );
      if (!mounted) return;
      toast(context, m);
      for (final c in [_mac, _key, _name, _user, _pass, _link, _pin]) {
        c.clear();
      }
      setState(() {
        _device = null;
        _onTv = const [];
      });
      widget.onAdded();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Add to my clients" for a playlist that is already on the TV.
  Future<void> _claim(TvPlaylist p) async {
    var pin = '';
    if (p.locked) {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('PIN for "${p.name}"'),
          content: TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            decoration: const InputDecoration(labelText: '4-digit PIN', counterText: ''),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
          ],
        ),
      );
      if (ok != true) return;
      pin = c.text.trim();
    }
    setState(() => _busy = true);
    try {
      final m = await Api.claim(_mac.text.trim(), _key.text.trim(), p.id, pin);
      if (!mounted) return;
      toast(context, m);
      final r = await Api.lookup(_mac.text.trim(), _key.text.trim());
      if (mounted) setState(() => _onTv = r.$2);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _onTvList() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Playlists on this TV (${_onTv.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          if (_onTv.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('None yet. Add one below.', style: TextStyle(color: _muted)),
            ),
          for (final p in _onTv)
            Row(
              children: [
                Icon(p.type == 'm3u' ? Icons.link : Icons.live_tv_rounded, size: 20, color: _muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name.isEmpty ? 'Playlist' : p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        [
                          p.type == 'm3u' ? 'M3U' : 'Xtream',
                          if (p.username.isNotEmpty) p.username,
                          if (p.locked) 'PIN',
                        ].join(' · '),
                        style: const TextStyle(color: _muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (p.mine)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text('In my clients', style: TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.w700)),
                  )
                else
                  TextButton(
                    onPressed: _busy ? null : () => _claim(p),
                    child: Text(p.managed ? 'Take over' : 'Add to my clients'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _device;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text('Add client', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const Text('Get the MAC Address and Device Key from the TV', style: TextStyle(color: _muted)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _BigButton(
                icon: Icons.qr_code_scanner_rounded,
                label: 'Scan with camera',
                onTap: () async {
                  final r = await Navigator.of(context)
                      .push<(String, String)>(MaterialPageRoute(builder: (_) => const ScanScreen()));
                  await _fill(r);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BigButton(
                icon: Icons.image_search_rounded,
                label: 'Scan a picture',
                onTap: () async => _fill(await scanFromPicture(context)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text('or type them', style: TextStyle(color: _muted)),
        const SizedBox(height: 8),
        TextField(
          controller: _mac,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'MAC Address', hintText: '00:1A:79:XX:XX:XX', prefixIcon: Icon(Icons.tv)),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Fa-f:\-]'))],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Device Key', prefixIcon: Icon(Icons.key)),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _check,
          icon: const Icon(Icons.search),
          label: const Text('Find this TV'),
        ),
        if (d != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _statusColor(d.status).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _statusColor(d.status).withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: _statusColor(d.status)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'TV found · ${d.status}${d.plan == 'lifetime' ? ' (lifetime)' : d.daysLeft > 0 ? ' · ${d.daysLeft} days left' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          _onTvList(),
          const SizedBox(height: 16),
          const Text('Add a new playlist', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _TypePicker(value: _type, onChanged: (v) => setState(() => _type = v)),
          const SizedBox(height: 14),
          if (_type == 'm3u') ...[
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Playlist name', prefixIcon: Icon(Icons.label_rounded)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _link,
              minLines: 1,
              maxLines: 3,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'M3U link',
                hintText: 'http://server/get.php?username=…&password=…&type=m3u_plus',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text('A link from your own server follows your server changes automatically.',
                  style: TextStyle(color: _muted, fontSize: 12.5)),
            ),
          ] else ...[
            TextField(controller: _user, decoration: const InputDecoration(labelText: 'Client username', prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 12),
            TextField(controller: _pass, decoration: const InputDecoration(labelText: 'Client password', prefixIcon: Icon(Icons.password))),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Playlist name on the TV (optional)')),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'PIN lock (optional, 4 digits)',
              prefixIcon: Icon(Icons.pin),
              counterText: '',
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: _busy ? null : _add, child: const Text('Add to this TV')),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------------------------- settings

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _src = TextEditingController();
  final _old = TextEditingController();
  final _new = TextEditingController();
  bool _busy = false;

  /// Checks how many playlists use the old server, asks, then replaces only those.
  Future<void> _replace() async {
    final o = _old.text.trim(), n = _new.text.trim();
    if (o.isEmpty || n.isEmpty) {
      toast(context, 'Enter the old and the new server.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final (found, count) = await Api.replaceServer(o, n, dryRun: true);
      if (!mounted) return;
      if (count == 0) {
        toast(context, 'No playlist uses $o.', error: true);
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace server?'),
          content: Text('$found\n\nThey move to:\n$n\n\nPlaylists on other servers stay as they are.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final (msg, _) = await Api.replaceServer(o, n);
      if (!mounted) return;
      toast(context, msg);
      _old.clear();
      _new.clear();
      widget.onChanged();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Api.profile;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Replace server', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                (Api.profile?.isSuper ?? false)
                    ? 'Every playlist on the website that uses the old server moves to the new one. Playlists on other servers are not touched.'
                    : 'Your clients\' playlists that use the old server move to the new one. Playlists on other servers are not touched.',
                style: const TextStyle(color: _muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _old,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Old server', hintText: 'http://old-domain.tt:8080', prefixIcon: Icon(Icons.dns_outlined)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _new,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'New server', hintText: 'http://new-domain.tt:8080', prefixIcon: Icon(Icons.dns)),
              ),
              const SizedBox(height: 6),
              const Text('Without a port (http://old-domain.tt) every port of that domain is replaced.',
                  style: TextStyle(color: _muted, fontSize: 12.5)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _replace,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Find and replace'),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Server for all my clients', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text(
                'Change it here once and every client\'s TV moves to the new address by itself (Xtream and M3U).',
                style: TextStyle(color: _muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              _Info(label: 'Now', value: (p?.server.isNotEmpty ?? false) ? p!.server : 'not set'),
              if ((p?.m3u ?? '').isNotEmpty) _Info(label: 'M3U link', value: p!.m3u),
              _Info(label: 'Clients', value: '${p?.clients ?? 0}'),
              _Info(
                  label: 'Website plugin',
                  value: (p?.version.isNotEmpty ?? false) ? p!.version : 'old version, please update to 1.0.19'),
              const SizedBox(height: 12),
              TextField(
                controller: _src,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'New server or M3U link',
                  hintText: 'http://domain.tt  or  http://domain.tt/get.php?username=…',
                ),
              ),
              const SizedBox(height: 6),
              const Text('Tip: pasting one client\'s full M3U link also keeps its exact link shape for M3U clients.',
                  style: TextStyle(color: _muted, fontSize: 12.5)),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (d) => AlertDialog(
                            title: const Text('Change the server for everyone?'),
                            content: Text('All ${p?.clients ?? 0} clients will use:\n${_src.text.trim()}'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Change')),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        setState(() => _busy = true);
                        try {
                          final m = await Api.saveServer(_src.text);
                          if (!context.mounted) return;
                          toast(context, m);
                          _src.clear();
                          widget.onChanged();
                        } catch (e) {
                          if (context.mounted) toast(context, '$e', error: true);
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: const Text('Save for all clients'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _Info(label: 'Name', value: p?.name ?? ''),
              _Info(label: 'Role', value: levelName(p?.level ?? 'reseller')),
              if (p != null && !p.isSuper) _Info(label: 'Credits', value: '${p.credits ?? 0}'),
              _Info(label: 'Website', value: Api.site),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
                onPressed: () async {
                  await Api.signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute<void>(builder: (_) => const LoginScreen()), (_) => false);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------------------------- bits

class _TypePicker extends StatelessWidget {
  const _TypePicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'xtream', label: Text('Xtream (best)'), icon: Icon(Icons.dns_rounded)),
        ButtonSegment(value: 'm3u', label: Text('M3U'), icon: Icon(Icons.list_alt_rounded)),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF4A52), Color(0xFF8A1A20)]),
            boxShadow: const [BoxShadow(color: Color(0x55E3262F), blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: Colors.white),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: _red.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(30)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: _red),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x33FF9F1C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x88FF9F1C)),
      ),
      child: Text(text),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 82, child: Text(label, style: const TextStyle(color: _muted))),
          Expanded(child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
