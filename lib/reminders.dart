import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'parental.dart';
import 'screens/player.dart';
import 'start.dart' show navigatorKey;
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';
import 'xtream.dart';

/// A programme the customer wants to be told about (set in the TV Guide).
class Reminder {
  const Reminder({required this.channel, required this.title, required this.start, required this.end});

  final XItem channel;
  final String title;
  final DateTime start;
  final DateTime end;

  String get key => keyFor(channel, start);
  static String keyFor(XItem channel, DateTime start) => '${channel.id}|${start.millisecondsSinceEpoch ~/ 1000}';

  Map<String, dynamic> toJson() => {
        'ch': channel.toJson(),
        't': title,
        's': start.millisecondsSinceEpoch,
        'e': end.millisecondsSinceEpoch,
      };

  static Reminder? fromJson(dynamic j) {
    if (j is! Map) return null;
    final ch = XItem.fromJson(j['ch']);
    final s = int.tryParse('${j['s'] ?? ''}') ?? 0;
    final e = int.tryParse('${j['e'] ?? ''}') ?? 0;
    if (ch == null || s <= 0 || e <= s) return null;
    return Reminder(
      channel: ch,
      title: (j['t'] ?? '').toString(),
      start: DateTime.fromMillisecondsSinceEpoch(s),
      end: DateTime.fromMillisecondsSinceEpoch(e),
    );
  }
}

/// Programme reminders: while the app is open, a message appears when a chosen programme
/// starts, with "Watch now" to go straight to the channel.
class Reminders {
  Reminders._();

  static const _max = 60;

  /// The playlist that is open (set by the home screen): "Watch now" plays from it.
  static Source? api;

  /// Changes for the TV Guide.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static Timer? _timer;
  static final Set<String> _shown = {};
  static bool _showing = false;

  static String? _parsedFrom;
  static List<Reminder> _parsed = const [];

  static List<Reminder> get all {
    final raw = Store.remindersJson;
    if (raw != _parsedFrom) {
      final list = <Reminder>[];
      try {
        final data = jsonDecode(raw);
        if (data is List) {
          for (final j in data) {
            final r = Reminder.fromJson(j);
            if (r != null) list.add(r);
          }
        }
      } catch (_) {}
      list.sort((a, b) => a.start.compareTo(b.start));
      _parsedFrom = raw;
      _parsed = list;
    }
    final now = DateTime.now();
    return [for (final r in _parsed) if (r.end.isAfter(now)) r];
  }

  static void _save(List<Reminder> list) {
    Store.setRemindersJson(jsonEncode([for (final r in list.take(_max)) r.toJson()]));
    changes.value++;
  }

  static bool has(XItem channel, DateTime start) {
    final key = Reminder.keyFor(channel, start);
    return all.any((r) => r.key == key);
  }

  /// Sets or removes the reminder for a programme. True when it is set afterwards.
  static bool toggle(XItem channel, XEpg programme) {
    final key = Reminder.keyFor(channel, programme.start);
    final list = all;
    final had = list.any((r) => r.key == key);
    if (had) {
      list.removeWhere((r) => r.key == key);
    } else {
      list.add(Reminder(
        channel: channel,
        title: programme.title.isEmpty ? channel.name : programme.title,
        start: programme.start,
        end: programme.end,
      ));
    }
    _save(list);
    log('reminder ${had ? 'removed' : 'set'}');
    return !had;
  }

  static void remove(String key) {
    final list = all;
    if (!list.any((r) => r.key == key)) return;
    _save(list.where((r) => r.key != key).toList());
  }

  /// Starts looking at the clock (once, when the app starts).
  static void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 15), (_) => _check());
  }

  static Future<void> _check() async {
    if (_showing) return;
    final now = DateTime.now();
    for (final r in all) {
      if (_shown.contains(r.key)) continue;
      // Up to a minute early, and as long as the programme is on.
      if (r.start.difference(now) > const Duration(minutes: 1) || !r.end.isAfter(now)) continue;
      _shown.add(r.key);
      remove(r.key);
      // A Kids profile is not told about channels it may not watch.
      if (Store.kidsMode && !Store.allowed(r.channel)) continue;
      await _show(r);
      return;
    }
  }

  static Future<void> _show(Reminder r) async {
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null) return;
    _showing = true;
    log('reminder shown');
    final watch = await showDialog<bool>(context: context, builder: (_) => _ReminderDialog(reminder: r));
    _showing = false;
    if (watch == true) await _watch(r);
  }

  /// "Watch now": everything open closes (one connection per account) and the channel plays,
  /// with the other channels of its category for Up / Down.
  static Future<void> _watch(Reminder r) async {
    final source = api;
    final nav = navigatorKey.currentState;
    if (source == null || nav == null) return;
    // A channel in a locked category still needs the parental PIN.
    final here = nav.overlay?.context;
    if (Store.isLocked(XKind.live, r.channel.categoryId) && !Store.parentalUnlocked) {
      if (here == null || !await askParentalPin(here)) return;
    }
    nav.popUntil((route) => route.isFirst);
    // Let a closing player or preview hand back its connection first.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    var items = <XItem>[r.channel];
    var index = 0;
    try {
      final list = (await source
              .items(XKind.live, categoryId: r.channel.categoryId)
              .timeout(const Duration(seconds: 6)))
          .where((i) => i.categoryId == r.channel.categoryId || r.channel.categoryId.isEmpty)
          .where(Store.allowed)
          .toList();
      final i = list.indexWhere((x) => x.id == r.channel.id);
      if (i >= 0) {
        items = list;
        index = i;
      }
    } catch (e) {
      log('reminder: channel list ${e.runtimeType}');
    }
    Store.addRecent(r.channel);
    log('reminder: watching');
    await nav.push(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(api: source, entries: liveEntries(source, items), index: index, live: true),
    ));
  }
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({required this.reminder});
  final Reminder reminder;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  Timer? _close;

  @override
  void initState() {
    super.initState();
    // Nobody there: the message goes away by itself after a few minutes.
    _close = Timer(const Duration(minutes: 4), () {
      if (mounted) Navigator.of(context).maybePop(false);
    });
  }

  @override
  void dispose() {
    _close?.cancel();
    super.dispose();
  }

  String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final r = widget.reminder;
    final started = !r.start.isAfter(DateTime.now());
    return AlertDialog(
      backgroundColor: C.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(26, 22, 26, 6),
      title: Row(
        children: [
          const Icon(Icons.notifications_active_rounded, color: Color(0xFFFFC94A), size: 28),
          const SizedBox(width: 12),
          Text(started ? 'Starting now' : 'Starting in a minute',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 92,
                height: 92,
                color: C.card,
                padding: const EdgeInsets.all(8),
                child: NetImage(r.channel.icon, fit: BoxFit.contain, cacheWidth: 200),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.25)),
                  const SizedBox(height: 6),
                  Text('${r.channel.name}  ·  ${_clock(r.start)} – ${_clock(r.end)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, color: C.dim)),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Dismiss')),
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Watch now', style: TextStyle(color: C.accent)),
        ),
      ],
    );
  }
}
