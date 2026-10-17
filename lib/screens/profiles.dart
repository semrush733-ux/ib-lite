import 'package:flutter/material.dart';

import '../i18n.dart';
import '../parental.dart';
import '../profiles.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'home.dart';

/// "Who's watching?": the profiles of this TV. OK on a profile uses it; holding OK on a profile
/// (or a long press) changes or deletes it; "Add profile" makes a new one.
///
/// With [atStart] the screen is the first one after the start animation and opens the home
/// screen once a profile is picked. Otherwise it is opened from the home screen and returns
/// true when another profile was picked.
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key, required this.api, this.atStart = false});

  final Source api;
  final bool atStart;

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  @override
  void initState() {
    super.initState();
    log('screen=profiles count=${Profiles.all.length} start=${widget.atStart}');
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text, textAlign: TextAlign.center),
        behavior: SnackBarBehavior.floating,
        width: 460,
        duration: const Duration(seconds: 3),
      ));
  }

  /// Leaving a Kids profile (or changing profiles while in one) needs the parental PIN.
  Future<bool> _parentOk() async {
    if (!Profiles.active.kids) return true;
    return askParentalPin(context, title: 'Parental PIN');
  }

  Future<void> _pick(Profile p) async {
    final current = Profiles.active;
    if (p.id != current.id && current.kids && !p.kids && !await _parentOk()) return;
    if (!mounted) return;
    await Profiles.use(p);
    log('profile=${p.id} kids=${p.kids}');
    if (!mounted) return;
    if (widget.atStart) {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => HomeScreen(api: widget.api)));
    } else {
      Navigator.of(context).pop(p.id != current.id);
    }
  }

  /// Back: on the first screen the profile used last time goes on; otherwise just back.
  void _back() {
    if (widget.atStart) {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => HomeScreen(api: widget.api)));
    } else {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _add() async {
    if (!await _parentOk()) return;
    if (!mounted) return;
    if (Profiles.all.length >= Profiles.maxCount) {
      _toast('A TV can have up to ${Profiles.maxCount} profiles.');
      return;
    }
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _ProfileDialog(profile: Profile(id: '', name: '', color: Profiles.all.length % Profiles.colors.length)),
    );
    if (result == null || result.delete || !mounted) return;
    final p = await Profiles.add(name: result.name, color: result.color, kids: result.kids);
    log('profile added kids=${p.kids}');
    if (p.kids) await _offerPin();
    if (mounted) setState(() {});
  }

  /// A Kids profile only keeps children in when leaving it needs a PIN.
  Future<void> _offerPin() async {
    if (Store.parentalPin.isNotEmpty || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: const Text('Set a parental PIN'),
        content: const SizedBox(
          width: 440,
          child: Text(
            'With a PIN, children cannot leave the Kids profile or open Settings without you. '
            'The same PIN also opens locked categories.',
            style: TextStyle(height: 1.45),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Set PIN', style: TextStyle(color: C.accent)),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final pin = await askNewPin(context);
    if (pin == null) return;
    Store.setParentalPin(pin);
    Store.parentalUnlocked = false;
    _toast('Parental PIN saved.');
  }

  Future<void> _edit(Profile p) async {
    if (!await _parentOk()) return;
    if (!mounted) return;
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _ProfileDialog(profile: p, canDelete: p.id != 'main'),
    );
    if (result == null || !mounted) return;
    if (result.delete) {
      final sure = await _confirmDelete(p);
      if (!sure) return;
      await Profiles.delete(p);
      log('profile deleted');
      _toast('"${p.name}" was deleted.');
    } else {
      final updated = p.copyWith(name: result.name, color: result.color, kids: result.kids);
      await Profiles.update(updated);
      if (updated.kids && !p.kids) await _offerPin();
    }
    if (mounted) setState(() {});
  }

  Future<bool> _confirmDelete(Profile p) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: Text('Delete "${p.name}"?'),
        content: const Text('Its favourites, recently watched and Continue Watching are deleted too.'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: C.danger)),
          ),
        ],
      ),
    );
    return yes == true;
  }

  Future<void> _kidsCategories() async {
    if (!await _parentOk()) return;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => KidsCategoriesScreen(api: widget.api)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final list = Profiles.all;
    final active = Profiles.active;
    final canAdd = list.length < Profiles.maxCount;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: C.bg,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.35),
              radius: 1.2,
              colors: [Color(0xFF3A1116), Color(0xFF0E0A0B)],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(builder: (context, box) {
              final tile = (box.maxWidth / 7.2).clamp(110.0, 170.0).toDouble();
              return Padding(
                padding: const EdgeInsets.fromLTRB(36, 24, 36, 18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Logo(size: 26),
                        const Spacer(),
                        if (!widget.atStart)
                          TvFocus(
                            radius: 22,
                            color: C.panel,
                            onTap: _back,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.arrow_back_rounded, size: 20),
                                const SizedBox(width: 8),
                                Text(t('Back'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                              ]),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(t("Who's watching?"),
                        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                    SizedBox(height: box.maxHeight * 0.07),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final p in list) ...[
                            _ProfileTile(
                              size: tile,
                              profile: p,
                              current: p.id == active.id,
                              autofocus: p.id == active.id,
                              onTap: () => _pick(p),
                              onLongPress: () => _edit(p),
                            ),
                            SizedBox(width: tile * 0.22),
                          ],
                          if (canAdd)
                            _AddTile(size: tile, onTap: _add),
                        ],
                      ),
                    ),
                    SizedBox(height: box.maxHeight * 0.06),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        if (list.length > 1)
                          _Chip(
                            icon: Store.askProfileAtStart ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                            label: t('Ask when the app starts'),
                            on: Store.askProfileAtStart,
                            onTap: () async {
                              if (!await _parentOk()) return;
                              await Store.setAskProfileAtStart(!Store.askProfileAtStart);
                              if (mounted) setState(() {});
                            },
                          ),
                        _Chip(icon: Icons.child_care_rounded, label: t('Kids categories'), on: false, onTap: _kidsCategories),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Every profile has its own favourites, recently watched and Continue Watching. '
                      'Hold OK on a profile to rename or delete it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: C.dim),
                    ),
                    const Spacer(),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.size,
    required this.profile,
    required this.current,
    required this.onTap,
    required this.onLongPress,
    this.autofocus = false,
  });

  final double size;
  final Profile profile;
  final bool current;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: TvFocus(
        autofocus: autofocus,
        radius: 20,
        color: const Color(0x00000000),
        focusBorder: Colors.white,
        selected: current,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: size * 0.1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProfileAvatar(profile, size: size * 0.62),
              SizedBox(height: size * 0.09),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 3),
              Text(
                profile.kids ? t('Kids') : (current ? t('In use') : ' '),
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: profile.kids ? const Color(0xFF7CD992) : C.dim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.size, required this.onTap});
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: TvFocus(
        radius: 20,
        color: const Color(0x00000000),
        focusBorder: Colors.white,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: size * 0.1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: size * 0.62,
                height: size * 0.62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x14FFFFFF),
                  border: Border.all(color: const Color(0x55FFFFFF), width: 2),
                ),
                child: Icon(Icons.add_rounded, size: size * 0.32, color: C.text),
              ),
              SizedBox(height: size * 0.09),
              Text(t('Add profile'), style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              const Text(' ', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.on, required this.onTap});
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      radius: 22,
      color: C.panel,
      selected: on,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: on ? C.accent : C.dim),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _EditResult {
  const _EditResult({this.name = '', this.color = 0, this.kids = false, this.delete = false});
  final String name;
  final int color;
  final bool kids;
  final bool delete;
}

/// New profile / change a profile: name, colour, Kids, and Delete for an existing one.
class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.profile, this.canDelete = false});
  final Profile profile;
  final bool canDelete;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.profile.name);
  late int _color = widget.profile.color;
  late bool _kids = widget.profile.kids;
  String _error = '';

  bool get _isNew => widget.profile.id.isEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Type a name.');
      return;
    }
    Navigator.of(context).pop(_EditResult(name: name.length > 20 ? name.substring(0, 20) : name, color: _color, kids: _kids));
  }

  @override
  Widget build(BuildContext context) {
    final preview = Profile(id: 'x', name: _name.text.isEmpty ? '?' : _name.text, color: _color, kids: _kids);
    return AlertDialog(
      backgroundColor: C.panel,
      title: Row(
        children: [
          ProfileAvatar(preview, size: 40),
          const SizedBox(width: 14),
          Text(_isNew ? t('Add profile') : t('Change profile')),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TvField(
              controller: _name,
              label: 'Name',
              icon: Icons.person_rounded,
              autofocus: _isNew,
              action: TextInputAction.done,
              onSubmitted: (_) => setState(() {}),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error, style: const TextStyle(color: C.danger, fontSize: 13.5)),
              ),
            const SizedBox(height: 16),
            const Text('COLOUR', style: TextStyle(fontSize: 12, color: C.dim, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < Profiles.colors.length; i++)
                  TvFocus(
                    radius: 22,
                    color: const Color(0x00000000),
                    focusBorder: Colors.white,
                    selected: i == _color,
                    onTap: () => setState(() => _color = i),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Profiles.colors[i],
                          border: Border.all(color: i == _color ? Colors.white : Colors.transparent, width: 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TvFocus(
              radius: 10,
              color: C.card,
              selected: _kids,
              onTap: () => setState(() => _kids = !_kids),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(_kids ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                        size: 34, color: _kids ? const Color(0xFF22C55E) : C.dim),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('Kids profile'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          const Text('Only categories for children (Kids, Cartoons, Family…). Leaving it needs the parental PIN.',
                              style: TextStyle(fontSize: 12.5, color: C.dim, height: 1.35)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.canDelete)
          TextButton(
            onPressed: () => Navigator.of(context).pop(const _EditResult(delete: true)),
            child: const Text('Delete', style: TextStyle(color: C.danger)),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          autofocus: !_isNew,
          onPressed: _save,
          child: const Text('Save', style: TextStyle(color: C.accent)),
        ),
      ],
    );
  }
}

/// Which categories children may see: found by their names, and changed here by hand.
class KidsCategoriesScreen extends StatefulWidget {
  const KidsCategoriesScreen({super.key, required this.api});
  final Source api;

  @override
  State<KidsCategoriesScreen> createState() => _KidsCategoriesScreenState();
}

class _KidsCategoriesScreenState extends State<KidsCategoriesScreen> {
  XKind _kind = XKind.live;
  final Map<XKind, List<XCategory>> _cats = {};
  final Map<XKind, String> _errors = {};

  @override
  void initState() {
    super.initState();
    log('screen=kids-categories');
    _load(_kind);
  }

  Future<void> _load(XKind kind) async {
    if (_cats.containsKey(kind)) return;
    try {
      final list = Store.sortCategories(kind, await widget.api.categories(kind));
      Store.noteCategories(kind, list);
      if (!mounted) return;
      setState(() => _cats[kind] = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errors[kind] = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    const names = {XKind.live: 'Live TV', XKind.vod: 'Movies', XKind.series: 'Series'};
    final cats = _cats[_kind];
    final error = _errors[_kind];
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 26, 40, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TvFocus(
                    autofocus: true,
                    radius: 22,
                    color: C.panel,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.arrow_back_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(t('Back'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 18),
                  const Icon(Icons.child_care_rounded, color: Color(0xFF22C55E), size: 26),
                  const SizedBox(width: 10),
                  Text(t('Kids categories'), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'A Kids profile shows only the ticked categories. Categories with "Kids", "Cartoons", "Family", '
                '"Disney"… in their name are ticked by themselves; tick or untick any category by hand.',
                style: TextStyle(fontSize: 13.5, color: C.dim, height: 1.4),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final k in XKind.values) ...[
                    _Chip(
                      icon: k == XKind.live ? Icons.live_tv_rounded : (k == XKind.vod ? Icons.movie_rounded : Icons.video_library_rounded),
                      label: t(names[k]!),
                      on: _kind == k,
                      onTap: () {
                        setState(() => _kind = k);
                        _load(k);
                      },
                    ),
                    const SizedBox(width: 10),
                  ],
                  const Spacer(),
                  _Chip(
                    icon: Icons.restart_alt_rounded,
                    label: 'By name only',
                    on: false,
                    onTap: () {
                      Store.resetKidsChoices(_kind);
                      setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: error != null
                    ? Text(error, style: const TextStyle(color: C.danger))
                    : cats == null
                        ? const Loading()
                        : cats.isEmpty
                            ? const Text('No categories.', style: TextStyle(color: C.dim))
                            : GridView.builder(
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 380,
                                  mainAxisExtent: 46,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 8,
                                ),
                                itemCount: cats.length,
                                itemBuilder: (context, i) {
                                  final c = cats[i];
                                  final on = Store.kidsAllowed(_kind, c.id);
                                  final byHand = Store.kidsChoice(_kind, c.id) != null;
                                  return TvFocus(
                                    radius: 9,
                                    color: C.panel,
                                    onTap: () {
                                      Store.setKidsChoice(_kind, c.id, !on);
                                      setState(() {});
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: Row(
                                        children: [
                                          Icon(on ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                              size: 20, color: on ? const Color(0xFF22C55E) : C.dim),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(c.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(fontSize: 14, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                                          ),
                                          if (byHand)
                                            const Icon(Icons.touch_app_rounded, size: 15, color: C.dim),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
