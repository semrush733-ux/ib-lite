import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'main.dart' show toast;

const _red = Color(0xFFE3262F);
const _card = Color(0xFF1B1113);
const _line = Color(0xFF3A2A2D);
const _muted = Color(0xFFB9A9AC);

Color _levelColor(String l) => switch (l) {
      'admin' => const Color(0xFFF5B400),
      'reseller' => const Color(0xFF1E88FF),
      'subreseller' => const Color(0xFF14B8A6),
      _ => _muted,
    };

/// Accounts under me: admins, resellers and sub-resellers, with their credits.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key, required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<UsersPage> createState() => UsersPageState();
}

class UsersPageState extends State<UsersPage> {
  List<PanelUser>? _list;
  String? _error;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final l = await UsersApi.list(_q.text.trim());
      if (mounted) {
        setState(() {
          _list = l;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _open(Widget sheet) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF170E10),
      builder: (_) => sheet,
    );
    if (changed == true) {
      await reload();
      widget.onChanged();
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
              const Expanded(child: Text('Users', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
              if (p != null && !p.isSuper)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: _red.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(30)),
                  child: Text('${p.credits ?? 0} credits', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          Text(p?.isSuper == true ? 'Create admins, resellers and sub-resellers and give them credits.'
              : 'Create accounts under you and give them credits from your balance.',
              style: const TextStyle(color: _muted)),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _open(const _AddUserSheet()),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add user'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => reload(),
            decoration: const InputDecoration(hintText: 'Search username or email', prefixIcon: Icon(Icons.search)),
          ),
          const SizedBox(height: 14),
          if (_error != null) Text(_error!, style: const TextStyle(color: Color(0xFFFF8A90))),
          if (list == null && _error == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          if (list != null && list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Text('No users yet. Tap "Add user".', textAlign: TextAlign.center, style: TextStyle(color: _muted)),
            ),
          for (final u in list ?? const <PanelUser>[])
            Card(
              color: _card,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: _line)),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _open(_UserSheet(u: u)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: _levelColor(u.level).withValues(alpha: 0.18),
                        child: Text(u.username.isEmpty ? '?' : u.username[0].toUpperCase(),
                            style: TextStyle(color: _levelColor(u.level), fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(u.username,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        decoration: u.disabled ? TextDecoration.lineThrough : null)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _levelColor(u.level).withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(levelName(u.level),
                                    style: TextStyle(fontSize: 11, color: _levelColor(u.level), fontWeight: FontWeight.w800)),
                              ),
                            ]),
                            const SizedBox(height: 2),
                            Text(
                              '${u.clients} clients${u.parent.isNotEmpty ? '  ·  under ${u.parent}' : ''}${u.disabled ? '  ·  disabled' : ''}',
                              style: const TextStyle(color: _muted, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${u.credits}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          const Text('credits', style: TextStyle(color: _muted, fontSize: 11.5)),
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
  }
}

class _AddUserSheet extends StatefulWidget {
  const _AddUserSheet();

  @override
  State<_AddUserSheet> createState() => _AddUserSheetState();
}

class _AddUserSheetState extends State<_AddUserSheet> {
  final _user = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _credits = TextEditingController(text: '0');
  late String _level = (Api.profile?.canCreate.isNotEmpty ?? false) ? Api.profile!.canCreate.first : 'subreseller';
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final m = await UsersApi.add(
        level: _level,
        username: _user.text.trim(),
        email: _email.text.trim(),
        password: _pass.text,
        credits: int.tryParse(_credits.text.trim()) ?? 0,
      );
      if (!mounted) return;
      toast(context, m);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final levels = Api.profile?.canCreate ?? const <String>[];
    final p = Api.profile;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add user', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (final l in levels)
                  ChoiceChip(
                    label: Text(levelName(l)),
                    selected: _level == l,
                    selectedColor: _levelColor(l).withValues(alpha: 0.35),
                    onSelected: (_) => setState(() => _level = l),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(controller: _user, decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email (optional)', prefixIcon: Icon(Icons.email_outlined)),
            ),
            const SizedBox(height: 12),
            TextField(controller: _pass, decoration: const InputDecoration(labelText: 'Password (6+)', prefixIcon: Icon(Icons.lock))),
            const SizedBox(height: 12),
            TextField(
              controller: _credits,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Starting credits',
                prefixIcon: const Icon(Icons.toll_rounded),
                helperText: p?.isSuper == true ? 'Free for you as super admin.' : 'Taken from your ${p?.credits ?? 0} credits.',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Create account')),
          ],
        ),
      ),
    );
  }
}

class _UserSheet extends StatefulWidget {
  const _UserSheet({required this.u});
  final PanelUser u;

  @override
  State<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends State<_UserSheet> {
  final _amount = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;

  Future<void> _run(Future<String> Function() job) async {
    setState(() => _busy = true);
    try {
      final m = await job();
      if (!mounted) return;
      toast(context, m);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.u;
    final p = Api.profile;
    final n = int.tryParse(_amount.text.trim()) ?? 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(u.username, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text('${levelName(u.level)}  ·  ${u.credits} credits  ·  ${u.clients} clients',
                style: const TextStyle(color: _muted)),
            if (u.email.isNotEmpty) Text(u.email, style: const TextStyle(color: _muted, fontSize: 12.5)),
            const SizedBox(height: 18),
            const Text('Credits', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'How many',
                prefixIcon: const Icon(Icons.toll_rounded),
                helperText: p?.isSuper == true ? null : 'Given from your ${p?.credits ?? 0} credits; taken back ones return to you.',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || n <= 0 ? null : () => _run(() => UsersApi.credits(u.id, n)),
                    icon: const Icon(Icons.add),
                    label: const Text('Give'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || n <= 0 ? null : () => _run(() => UsersApi.credits(u.id, -n)),
                    icon: const Icon(Icons.remove),
                    label: const Text('Take back'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(controller: _pass, decoration: const InputDecoration(labelText: 'New password (6+)', prefixIcon: Icon(Icons.lock_reset))),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(() => UsersApi.update(u.id, password: _pass.text)),
              child: const Text('Change password'),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: u.disabled ? const Color(0xFF2ECC71) : const Color(0xFFFF7B81)),
              icon: Icon(u.disabled ? Icons.check_circle_outline : Icons.block),
              label: Text(u.disabled ? 'Enable this account' : 'Disable this account (cannot sign in)'),
              onPressed: _busy ? null : () => _run(() => UsersApi.update(u.id, disabled: !u.disabled)),
            ),
          ],
        ),
      ),
    );
  }
}
