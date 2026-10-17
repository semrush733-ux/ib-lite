import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

import 'theme.dart' show log;

/// Something that takes voice commands: the open player.
abstract class VoiceTarget {
  /// [command]: play, pause, stop, next, previous, forward, rewind or seek ([positionMs]).
  void onVoiceCommand(String command, int positionMs);
}

/// Voice control (Android side: VoiceHelper.kt).
///
/// * Assistants: Alexa on Fire TV and the Google Assistant on Android TV send "pause", "play",
///   "rewind 30 seconds", "next"... to the player through Android's media session. The player
///   reports what it is playing ([state]) and gets the commands ([VoiceTarget]).
/// * Microphone: on phones and Android / Google TV boxes with Google's voice typing, [listen]
///   opens Android's speech screen and returns what was said. Fire TV has none ([canListen]).
class Voice {
  Voice._();

  static const _channel = MethodChannel('b1g/voice');
  static final List<VoiceTarget> _targets = [];
  static bool _canListen = false;

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// A microphone can be offered on this device.
  static bool get canListen => _canListen;

  static Future<void> init() async {
    if (!_android) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'command') return null;
      final a = call.arguments;
      final command = a is Map ? '${a['command']}' : '$a';
      final p = a is Map ? a['position'] : null;
      final position = p is int ? p : (int.tryParse('$p') ?? -1);
      final target = _targets.isEmpty ? null : _targets.last;
      log('voice command=$command position=$position player=${target != null}');
      target?.onVoiceCommand(command, position);
      return null;
    });
    try {
      _canListen = await _channel.invokeMethod<bool>('canListen') ?? false;
    } catch (_) {
      _canListen = false;
    }
    log('voice microphone=${_canListen ? 'yes' : 'no'}');
  }

  /// The player that is open gets the commands (the newest one when a recording plays over live TV).
  static void attach(VoiceTarget target) {
    _targets.remove(target);
    _targets.add(target);
  }

  static void detach(VoiceTarget target) {
    _targets.remove(target);
    if (_targets.isEmpty) idle();
  }

  /// What is playing now, so the assistant knows what it can do.
  static void state({
    required String title,
    required bool playing,
    bool buffering = false,
    int positionMs = 0,
    int durationMs = 0,
    double speed = 1,
    bool canPause = false,
    bool canSeek = false,
    bool canNext = false,
    bool canPrevious = false,
  }) {
    if (!_android) return;
    _channel.invokeMethod<void>('state', {
      'active': true,
      'title': title,
      'playing': playing,
      'buffering': buffering,
      'position': positionMs < 0 ? 0 : positionMs,
      'duration': durationMs < 0 ? 0 : durationMs,
      'speed': speed,
      'canPause': canPause,
      'canSeek': canSeek,
      'canNext': canNext,
      'canPrevious': canPrevious,
    }).catchError((Object _) {});
  }

  /// Nothing is playing (player closed, app in the background).
  static void idle() {
    if (!_android) return;
    _channel.invokeMethod<void>('state', {'active': false}).catchError((Object _) {});
  }

  /// Opens the speech screen; the words heard, best guess first (empty: nothing heard / cancelled).
  static Future<List<String>> listen({String prompt = ''}) async {
    if (!_android || !_canListen) return const [];
    try {
      final r = await _channel.invokeMethod<List<dynamic>>('listen', {'prompt': prompt});
      final words = [for (final w in r ?? const []) '$w'.trim()].where((w) => w.isNotEmpty).toList();
      log('voice heard ${words.length} guesses');
      return words;
    } catch (e) {
      log('voice listen failed: ${e.runtimeType}');
      return const [];
    }
  }
}

// --------------------------------------------------------------------------- what was said

/// One thing said to the player.
class VoiceCommand {
  const VoiceCommand(this.action, {this.seconds = 0, this.index = -1, this.heard = ''});

  /// play, pause, next, previous, last (channel watched before), startover, forward, back,
  /// channel ([index] in the list) or unknown.
  final String action;
  final int seconds;
  final int index;
  final String heard;
}

/// Lower case, letters (with their accents / vowel signs) and digits only, single spaces.
String voiceNorm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true), ' ')
    .replaceAll(RegExp(r' +'), ' ')
    .trim();

const _numbers = {
  'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7,
  'eight': 8, 'nine': 9, 'ten': 10, 'fifteen': 15, 'twenty': 20, 'thirty': 30, 'forty': 40,
  'forty five': 45, 'fifty': 50, 'sixty': 60, 'ninety': 90,
};

final _seekWords = RegExp(
    r'\b(forward|ahead|skip|aage|aagey|back|backward|backwards|rewind|peeche|pichhe|piche)\b'
    r'(?: by)?(?: (\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|fifteen|twenty|thirty|forty five|forty|fifty|sixty|ninety)\b)?'
    r'(?: (seconds?|secs?|minutes?|mins?|hours?)\b)?');

final _channelNumber = RegExp(r'^(?:channel|number|no|chanel)? ?(\d{1,4})$');

/// Words that are not part of a channel's name ("play Sky Sports" → "sky sports").
const _filler = {
  'play', 'open', 'watch', 'show', 'put', 'on', 'start', 'switch', 'to', 'go', 'please', 'the', 'channel',
  'lagao', 'lagaen', 'chalao', 'chalaen', 'kholo', 'dikhao', 'karo', 'par', 'pe', 'wala', 'wali', 'tv',
};

bool _hasPhrase(String s, List<String> phrases) {
  final padded = ' $s ';
  return phrases.any((p) => padded.contains(' $p '));
}

/// What the customer asked the player for. [channels]: names of the live channels in the list
/// (live TV only), so "Sky Sports Main Event" or "channel 25" can tune there.
VoiceCommand parseVoice(List<String> heard, {required bool live, List<String> channels = const []}) {
  for (final raw in heard) {
    final s = voiceNorm(raw);
    if (s.isEmpty) continue;
    // "Start over", "from the beginning", "shuru se".
    if (_hasPhrase(s, const ['start over', 'restart', 'from the beginning', 'from the start', 'beginning',
      'shuru se', 'shuru', 'शुरू से', 'शुरू', 'شروع سے', 'شروع'])) {
      return VoiceCommand('startover', heard: raw);
    }
    // The channel watched before ("last channel", "previous channel": TV remotes' PRE-CH).
    if (live && _hasPhrase(s, const ['last channel', 'previous channel', 'recall', 'go back', 'pichla channel',
      'pichhla channel', 'पिछला चैनल', 'پچھلا چینل'])) {
      return VoiceCommand('last', heard: raw);
    }
    // "Forward 30 seconds", "go back 2 minutes", "rewind 5 minutes" ("skip" alone means next).
    final m = _seekWords.firstMatch(s);
    if (m != null && !(m.group(1) == 'skip' && m.group(2) == null)) {
      final word = m.group(1)!;
      final amount = m.group(2);
      final unit = m.group(3) ?? '';
      final back = const ['back', 'backward', 'backwards', 'rewind', 'peeche', 'pichhe', 'piche'].contains(word);
      var n = amount == null ? 0 : (int.tryParse(amount) ?? _numbers[amount] ?? 0);
      if (n <= 0) n = back ? 10 : 30;
      final mult = unit.startsWith('h') ? 3600 : (unit.startsWith('m') ? 60 : 1);
      return VoiceCommand(back ? 'back' : 'forward', seconds: n * mult, heard: raw);
    }
    if (_hasPhrase(s, const ['next', 'next episode', 'next channel', 'skip', 'agla', 'agla channel', 'अगला', 'اگلا'])) {
      return VoiceCommand('next', heard: raw);
    }
    if (_hasPhrase(s, const ['previous', 'previous episode', 'pichla', 'pichhla', 'पिछला', 'پچھلا'])) {
      return VoiceCommand('previous', heard: raw);
    }
    if (_hasPhrase(s, const ['pause', 'stop', 'wait', 'hold on', 'ruko', 'roko', 'रुको', 'रोको', 'رکو', 'روکو'])) {
      return VoiceCommand('pause', heard: raw);
    }
    if (const ['play', 'chalao', 'chalu karo', 'चलाओ', 'چلاؤ'].contains(s) ||
        _hasPhrase(s, const ['resume', 'continue', 'unpause', 'play again'])) {
      return VoiceCommand('play', heard: raw);
    }
    if (live && channels.isNotEmpty) {
      final number = _channelNumber.firstMatch(s);
      if (number != null) {
        final n = int.parse(number.group(1)!);
        if (n >= 1 && n <= channels.length) return VoiceCommand('channel', index: n - 1, heard: raw);
      }
      final i = matchChannel(s, channels);
      if (i >= 0) return VoiceCommand('channel', index: i, heard: raw);
    }
  }
  return VoiceCommand('unknown', heard: heard.isEmpty ? '' : heard.first);
}

/// Words that are not part of a title in a voice search ("play Avengers movie" → "avengers").
const _queryFiller = {
  'play', 'watch', 'open', 'search', 'find', 'show', 'me', 'for', 'please', 'movie', 'movies', 'film',
  'films', 'series', 'season', 'episode', 'channel', 'live', 'lagao', 'chalao', 'dikhao', 'kholo',
};

/// What to search for in what was said (the whole text when only such words were said).
String voiceQuery(String said) {
  final words = voiceNorm(said).split(' ').where((w) => w.isNotEmpty).toList();
  final kept = words.where((w) => !_queryFiller.contains(w)).toList();
  return (kept.isEmpty ? words : kept).join(' ');
}

/// The channel whose name fits what was said best (-1: none). Every word said should be in the
/// name; a shorter name wins a tie ("Sky Sports 1" before "Sky Sports 1 HD Backup").
int matchChannel(String said, List<String> names) {
  final words = voiceNorm(said).split(' ').where((w) => w.isNotEmpty && !_filler.contains(w)).toList();
  if (words.isEmpty) return -1;
  var best = -1;
  var bestScore = 0.0;
  for (var i = 0; i < names.length; i++) {
    final name = ' ${voiceNorm(names[i])} ';
    final joined = name.replaceAll(' ', '');
    var hits = 0;
    for (final w in words) {
      if (name.contains(' $w ') || (w.length >= 3 && joined.contains(w))) hits++;
    }
    if (hits == 0) continue;
    final score = hits / words.length - name.length / 100000.0;
    if (score > bestScore) {
      bestScore = score;
      best = i;
    }
  }
  // All words found; with three words or more, two out of three is enough.
  if (bestScore >= 0.99) return best;
  if (words.length >= 3 && bestScore >= 0.66) return best;
  return -1;
}
