import 'dart:async';

import 'package:flutter/material.dart';

import 'start.dart' show navigatorKey;
import 'theme.dart';

/// Sleep timer: after the chosen time the video stops and the app goes back to the home screen
/// (the TV can then go to sleep by itself). A minute before, a message asks whether to keep
/// watching. Set in the player (Audio and subtitles › Sleep timer); it is not kept across starts.
class SleepTimer {
  SleepTimer._();

  static const choices = [
    Duration.zero,
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 60),
    Duration(minutes: 90),
    Duration(minutes: 120),
  ];
  static const labels = ['Off', '15 min', '30 min', '1 h', '1 h 30', '2 h'];

  static Duration _chosen = Duration.zero;
  static Timer? _warnTimer;
  static Timer? _endTimer;

  /// When playback stops (null = timer off). The player shows it.
  static final ValueNotifier<DateTime?> ends = ValueNotifier(null);

  static int get chosenIndex {
    final i = choices.indexOf(_chosen);
    return i < 0 ? 0 : i;
  }

  static void set(Duration d) {
    _warnTimer?.cancel();
    _endTimer?.cancel();
    _chosen = d;
    if (d <= Duration.zero) {
      ends.value = null;
      log('sleep timer off');
      return;
    }
    ends.value = DateTime.now().add(d);
    log('sleep timer ${d.inMinutes} min');
    if (d > const Duration(seconds: 75)) _warnTimer = Timer(d - const Duration(seconds: 60), _warn);
    _endTimer = Timer(d, _expire);
  }

  /// "Stops at 23:45"
  static String get endsText {
    final t = ends.value;
    if (t == null) return '';
    return 'Stops at ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  static Future<void> _warn() async {
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null) return;
    final choice = await showDialog<int>(context: context, builder: (_) => const _SleepWarning());
    if (choice == 1) {
      set(const Duration(minutes: 30));
    } else if (choice == 2) {
      _expire();
    }
  }

  static void _expire() {
    _warnTimer?.cancel();
    _endTimer?.cancel();
    _chosen = Duration.zero;
    ends.value = null;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    log('sleep timer: playback stopped');
    // Closes the message, the player and a channel preview: back on the home screen.
    nav.popUntil((route) => route.isFirst);
    ScaffoldMessenger.maybeOf(nav.context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Sleep timer: playback stopped. Good night!', textAlign: TextAlign.center),
        behavior: SnackBarBehavior.floating,
        width: 460,
        duration: Duration(seconds: 6),
      ));
  }
}

class _SleepWarning extends StatefulWidget {
  const _SleepWarning();

  @override
  State<_SleepWarning> createState() => _SleepWarningState();
}

class _SleepWarningState extends State<_SleepWarning> {
  int _left = 60;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left = (_left - 1).clamp(0, 60));
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: C.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Row(
        children: [
          Icon(Icons.bedtime_rounded, color: Color(0xFF8FB4FF), size: 28),
          SizedBox(width: 12),
          Text('Sleep timer'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Text(
          'The video stops in $_left seconds.',
          style: const TextStyle(fontSize: 17, height: 1.4),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(2), child: const Text('Stop now')),
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(1),
          child: const Text('Keep watching (30 min more)', style: TextStyle(color: C.accent)),
        ),
      ],
    );
  }
}
