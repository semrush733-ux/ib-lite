import 'dart:async';

import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform, Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

import 'config.dart';
import 'store.dart' show Store;

/// A message from an engine: [error] true for real errors, false for chatter.
class EngineMessage {
  const EngineMessage(this.text, this.error);
  final String text;
  final bool error;
}

/// What the player screen needs from a playback engine. Two engines exist:
/// [MpvEngine] (libmpv through media_kit) and [ExoEngine] (Google ExoPlayer, Android only).
/// The screen's own controls work the same on both.
abstract class PlaybackEngine {
  String get name;

  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get buffering;
  Stream<bool> get completed;
  Stream<Tracks> get tracks;
  Stream<EngineMessage> get messages;

  Duration get durationNow;
  Tracks get tracksNow;
  int get width;
  int get height;
  bool get playing;
  bool get isBuffering;

  Future<void> open(String url, Duration start);
  /// Opens the address paused and fills the buffer (film page: "Watch" then starts at once).
  bool get canPreload => false;
  Future<void> preload(String url, Duration start) => open(url, start);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> setRate(double rate);
  Future<void> setAudioTrack(AudioTrack track);
  Future<void> setSubtitleTrack(SubtitleTrack track);
  Future<void> setVideoTrack(VideoTrack track);
  Future<List<String>> facts();
  Future<void> dispose();

  /// The picture. [subtitlePad] keeps subtitles above the control bar.
  Widget view({required BoxFit fit, required double subtitlePad});

  // ---- Picture Enhance ----
  /// Whether this engine can enhance the picture at all (MPV's direct mode cannot).
  bool get canEnhance => false;
  /// Level the next [open] starts with (0 off, 1 low, 2 high).
  int enhanceLevel = 0;
  /// Changes the level while playing. False when the engine needs a reopen for it.
  Future<bool> setEnhance(int level) async => false;
  /// Pictures skipped since the stream opened (to notice when the device is overloaded).
  Future<int> droppedFrames() async => 0;
  /// Pictures a second of the stream (0 when unknown).
  Future<double> fps() async => 0;

  /// The same engine can open the next address (keeps the last picture, skips start-up).
  bool get reusable => false;
  /// Lets go of the stream and the server connection, keeps the engine and its last picture.
  Future<void> stop() async {}
  /// The picture on screen now (to hold it during a reconnect), or null.
  Future<Uint8List?> snapshot() async => null;

  /// The stream's sound cannot be decoded by this engine on this device (the format's name).
  Stream<String> get soundUnsupported => const Stream.empty();
  /// The enhanced picture could not start: plays on without it.
  Stream<void> get enhanceFailed => const Stream.empty();
  /// The first picture is on the screen.
  Stream<void> get firstFrame => const Stream.empty();
}

// ------------------------------------------------------------------------------------- mpv

class MpvEngine extends PlaybackEngine {
  static bool get _weak {
    try {
      return Store.enhanceCap == 0; // measured as too weak for Picture Enhance
    } catch (_) {
      return false;
    }
  }

  MpvEngine({required this.live, required this.direct}) {
    player = Player(
      configuration: PlayerConfiguration(
        title: kAppName,
        bufferSize: 48 * 1024 * 1024,
        logLevel: kVerbose ? MPVLogLevel.info : MPVLogLevel.error,
      ),
    );
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        vo: direct ? 'mediacodec_embed' : null,
        hwdec: direct ? 'mediacodec' : null,
      ),
    );
    _logSub = player.stream.log.listen((line) {
      final text = line.text.trim();
      if (text.isNotEmpty) _messages.add(EngineMessage('${line.prefix}: $text', line.level == 'error' || line.level == 'fatal'));
    });
    _errSub = player.stream.error.listen((message) {
      final text = message.trim();
      if (text.isNotEmpty) _messages.add(EngineMessage(text, true));
    });
  }

  final bool live;
  final bool direct;
  /// Seconds to refill after the buffer ran dry (smart buffer); null = the standard.
  String? pauseWait;
  late final Player player;
  late final VideoController controller;
  final _messages = StreamController<EngineMessage>.broadcast();
  StreamSubscription<dynamic>? _logSub;
  StreamSubscription<dynamic>? _errSub;

  @override
  String get name => 'mpv';
  @override
  Stream<Duration> get position => player.stream.position;
  @override
  Stream<Duration> get duration => player.stream.duration;
  @override
  Stream<bool> get buffering => player.stream.buffering;
  @override
  Stream<bool> get completed => player.stream.completed;
  @override
  Stream<Tracks> get tracks => player.stream.tracks;
  @override
  Stream<EngineMessage> get messages => _messages.stream;
  @override
  Duration get durationNow => player.state.duration;
  @override
  Tracks get tracksNow => player.state.tracks;
  @override
  int get width => player.state.width ?? 0;
  @override
  int get height => player.state.height ?? 0;
  @override
  bool get playing => player.state.playing;
  @override
  bool get isBuffering => player.state.buffering;

  /// Engine settings chosen for IPTV: reconnect inside the network layer, a
  /// few seconds of buffer, and only a short pause when the buffer runs dry.
  Future<void> _configure() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    // dynamic: setProperty only exists in the Android/desktop NativePlayer, so a
    // static call would break the web compile; the guard above never lets web get here.
    final dynamic mpv = platform;
    Future<void> set(String name, String value) async {
      try {
        await mpv.setProperty(name, value);
      } catch (_) {}
    }

    await Future.wait([
      set('user-agent', kUserAgent),
      set('network-timeout', '20'),
      set('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=4'),
      set('cache', 'yes'),
      set('cache-pause-initial', 'no'),
      set('cache-pause-wait', pauseWait ?? (live ? '1' : '2')),
      set('demuxer-readahead-secs', live ? '10' : '60'),
      // Weak boxes (1-2 GB) get smaller buffers so a long film cannot use up their memory.
      set('demuxer-max-bytes', live ? (_weak ? '32MiB' : '64MiB') : (_weak ? '64MiB' : '128MiB')),
      set('demuxer-max-back-bytes', live ? (_weak ? '8MiB' : '16MiB') : (_weak ? '16MiB' : '32MiB')),
      if (!live) set('demuxer-seekable-cache', 'yes'),
      set('vd-lavc-dr', 'yes'),
      if (live) set('demuxer-lavf-analyzeduration', '1'),
      if (!live) set('hr-seek', 'no'),
      set('audio-channels', 'stereo'),
      set('sub-auto', 'no'),
      set('hwdec-codecs', 'all'),
      set('vd-lavc-threads', '0'),
      set('vd-lavc-fast', 'yes'),
      set('vd-lavc-skiploopfilter', 'nonkey'),
      set('framedrop', 'decoder+vo'),
      set('scale', 'bilinear'),
      set('dscale', 'bilinear'),
      set('cscale', 'bilinear'),
      set('dither', 'no'),
      set('deband', 'no'),
      set('correct-downscaling', 'no'),
      set('linear-downscaling', 'no'),
      set('sigmoid-upscaling', 'no'),
      set('hdr-compute-peak', 'no'),
      set('interpolation', 'no'),
      if (direct) set('hwdec', 'mediacodec'),
    ]);
  }

  @override
  Future<void> open(String url, Duration start) async {
    await _configure();
    await player.open(
      // Browsers refuse a custom User-Agent, so the web build sends no headers.
      Media(url,
          httpHeaders: kIsWeb ? null : const {'User-Agent': kUserAgent},
          start: start > Duration.zero ? start : null),
      play: true,
    );
    if (enhanceLevel > 0) await setEnhance(enhanceLevel);
  }

  @override
  bool get canPreload => !kIsWeb;

  @override
  Future<void> preload(String url, Duration start) async {
    await _configure();
    await player.open(
      Media(url,
          httpHeaders: kIsWeb ? null : const {'User-Agent': kUserAgent},
          start: start > Duration.zero ? start : null),
      play: false,
    );
    if (enhanceLevel > 0) await setEnhance(enhanceLevel);
  }

  @override
  bool get canEnhance => !direct && !kIsWeb;

  dynamic get _native {
    final platform = player.platform;
    return platform is NativePlayer ? platform : null;
  }

  Future<void> _set(String name, String value) async {
    final dynamic mpv = _native;
    if (mpv == null) return;
    try {
      await mpv.setProperty(name, value);
    } catch (_) {}
  }

  Future<String> _get(String name) async {
    final dynamic mpv = _native;
    if (mpv == null) return '';
    try {
      return ((await mpv.getProperty(name)) as String).trim();
    } catch (_) {
      return '';
    }
  }

  static final Map<int, String> _shaderPaths = {};

  static Future<String> _shader(int level) async {
    final known = _shaderPaths[level];
    if (known != null) return known;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/lite_enhance_$level.glsl');
    await f.writeAsString(_casShader(level >= 2 ? 0.75 : 0.4));
    return _shaderPaths[level] = f.path;
  }

  @override
  Future<bool> setEnhance(int level) async {
    level = canEnhance ? level.clamp(0, 2) : 0;
    enhanceLevel = level;
    if (level == 0) {
      await Future.wait([
        _set('glsl-shaders', ''),
        _set('saturation', '0'),
        _set('contrast', '0'),
        _set('scale', 'bilinear'),
        _set('deinterlace', 'no'),
      ]);
      return true;
    }
    final path = await _shader(level);
    await Future.wait([
      _set('glsl-shaders', path),
      _set('saturation', level >= 2 ? '9' : '5'),
      _set('contrast', level >= 2 ? '5' : '3'),
      _set('scale', level >= 2 ? 'spline36' : 'bilinear'),
      // Interlaced channels (1080i sport): smooth lines instead of combing; progressive ones
      // are left alone ("auto"). Only on devices strong enough for Enhance.
      _set('deinterlace', 'auto'),
    ]);
    return true;
  }

  @override
  Future<Uint8List?> snapshot() async {
    if (kIsWeb || direct) return null; // the direct picture never passes through the app
    try {
      return await player.screenshot(format: 'image/jpeg').timeout(const Duration(milliseconds: 700));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> droppedFrames() async {
    final v = await Future.wait([_get('frame-drop-count'), _get('decoder-frame-drop-count')]);
    return (int.tryParse(v[0]) ?? 0) + (int.tryParse(v[1]) ?? 0);
  }

  @override
  Future<double> fps() async {
    final c = double.tryParse(await _get('container-fps')) ?? 0;
    if (c > 0) return c;
    return double.tryParse(await _get('estimated-vf-fps')) ?? 0;
  }

  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> seek(Duration to) => player.seek(to);
  @override
  Future<void> setRate(double rate) => player.setRate(rate);
  @override
  Future<void> setAudioTrack(AudioTrack track) => player.setAudioTrack(track);
  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) => player.setSubtitleTrack(track);
  @override
  Future<void> setVideoTrack(VideoTrack track) => player.setVideoTrack(track);

  @override
  Future<List<String>> facts() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return const [];
    final dynamic mpv = platform;
    Future<String> read(String name) async {
      try {
        return ((await mpv.getProperty(name)) as String).trim();
      } catch (_) {
        return '';
      }
    }

    final values = await Future.wait([
      read('video-format'),
      read('hwdec-current'),
      read('container-fps'),
      read('frame-drop-count'),
      read('decoder-frame-drop-count'),
      read('audio-codec-name'),
    ]);
    final fps = double.tryParse(values[2]) ?? 0;
    final hardware = values[1].isNotEmpty && values[1] != 'no';
    final dropped = (int.tryParse(values[3]) ?? 0) + (int.tryParse(values[4]) ?? 0);
    return <String>[
      'Engine: MPV${direct ? ' (direct picture)' : ''}',
      if (values[0].isNotEmpty)
        'Video: ${values[0].toUpperCase()}${fps > 0 ? ', ${fps.toStringAsFixed(fps == fps.roundToDouble() ? 0 : 2)} pictures a second' : ''}',
      hardware ? 'Decoded by the video chip (${values[1]})' : 'Decoded by the processor (slower)',
      if (values[5].isNotEmpty) 'Sound: ${values[5].toUpperCase()}',
      'Pictures skipped so far: $dropped',
      'Picture Enhance: ${canEnhance ? _levelName(enhanceLevel) : 'not in direct picture mode'}',
    ];
  }

  bool _disposed = false;

  /// TVs and browsers: the same <video> element plays the next channel too (tearing it down
  /// and building a new one on every zap gave a long black screen). Native MPV keeps its
  /// one-engine-per-stream behaviour, which is what proved reliable on Android boxes.
  @override
  bool get reusable => kIsWeb && !_disposed;

  @override
  Future<void> stop() async {
    if (!kIsWeb) return;
    try {
      await player.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _logSub?.cancel();
    await _errSub?.cancel();
    await _messages.close();
    await player.dispose();
  }

  @override
  Widget view({required BoxFit fit, required double subtitlePad}) {
    return Video(
      key: ObjectKey(controller),
      controller: controller,
      controls: NoVideoControls,
      fit: fit,
      fill: Colors.black,
      subtitleViewConfiguration: SubtitleViewConfiguration(
        padding: EdgeInsets.fromLTRB(24, 0, 24, subtitlePad),
      ),
    );
  }
}

// ------------------------------------------------------------------------------- ExoPlayer

class ExoEngine extends PlaybackEngine {
  ExoEngine._(this.live);

  static const _channel = MethodChannel('b1g/exo');
  static final Map<int, ExoEngine> _live = {};
  static bool _hooked = false;

  /// Only the Android app has it (not the web or the Samsung / LG versions).
  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final bool live;
  int _id = 0;
  /// The Flutter texture with the picture. It can change while a video plays: on a device whose
  /// video chip pads its pictures the picture moves to a SurfaceTexture (see VideoCrop.kt).
  final ValueNotifier<int> _texture = ValueNotifier(-1);
  bool _disposed = false;

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _tracks = StreamController<Tracks>.broadcast();
  final _messages = StreamController<EngineMessage>.broadcast();
  final _noSound = StreamController<String>.broadcast();
  final _enhanceFailed = StreamController<void>.broadcast();
  final _firstFrame = StreamController<void>.broadcast();
  int _lastDropped = 0;
  double _lastFps = 0;
  final ValueNotifier<String> _cues = ValueNotifier('');
  final ValueNotifier<Size> _size = ValueNotifier(Size.zero);

  Duration _dur = Duration.zero;
  Tracks _trackList = Tracks();
  bool _playing = false;
  bool _isBuffering = true;

  /// Creates the native engine (and the picture surface for it).
  static Future<ExoEngine> create({required bool live, int startMs = 1500, int rebufMs = 3000}) async {
    if (!_hooked) {
      _hooked = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'event') return null;
        final m = call.arguments;
        if (m is! Map) return null;
        final id = (m['id'] as num?)?.toInt() ?? 0;
        _live[id]?._onEvent(m);
        return null;
      });
    }
    final e = ExoEngine._(live);
    final r = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'create', {'live': live, 'ua': kUserAgent, 'startMs': startMs, 'rebufMs': rebufMs});
    e._id = (r?['id'] as num?)?.toInt() ?? 0;
    e._texture.value = (r?['texture'] as num?)?.toInt() ?? -1;
    if (e._id == 0 || e._texture.value < 0) throw StateError('ExoPlayer could not start');
    if (r?['cropSafe'] == true) debugPrint('B1G exo picture: SurfaceTexture (this video chip pads its pictures)');
    _live[e._id] = e;
    return e;
  }

  void _onEvent(Map<dynamic, dynamic> m) {
    if (_disposed) return;
    switch (m['type']) {
      case 'state':
        final pos = Duration(milliseconds: (m['pos'] as num?)?.toInt() ?? 0);
        final dur = Duration(milliseconds: (m['dur'] as num?)?.toInt() ?? 0);
        final buf = m['buffering'] == true;
        _playing = m['playing'] == true;
        if (dur != _dur) {
          _dur = dur;
          _duration.add(dur);
        }
        if (buf != _isBuffering) {
          _isBuffering = buf;
          _buffering.add(buf);
        }
        if (_playing) _position.add(pos);
      case 'size':
        final w = (m['w'] as num?)?.toDouble() ?? 0;
        final h = (m['h'] as num?)?.toDouble() ?? 0;
        if (w > 0 && h > 0) _size.value = Size(w, h);
      case 'tracks':
        final list = m['list'];
        if (list is List) {
          final audio = <AudioTrack>[];
          final subs = <SubtitleTrack>[];
          final video = <VideoTrack>[];
          for (final t in list) {
            if (t is! Map) continue;
            final id = (t['id'] ?? '').toString();
            final lang = t['language']?.toString();
            final label = t['label']?.toString();
            switch (t['kind']) {
              case 'a':
                audio.add(AudioTrack(id, label, lang));
              case 's':
                subs.add(SubtitleTrack(id, label, lang));
              case 'v':
                video.add(VideoTrack(id, label, lang,
                    w: (t['w'] as num?)?.toInt(), h: (t['h'] as num?)?.toInt(), bitrate: (t['bitrate'] as num?)?.toInt()));
            }
          }
          _trackList = Tracks(audio: audio, subtitle: subs, video: video);
          _tracks.add(_trackList);
        }
      case 'cues':
        _cues.value = (m['text'] ?? '').toString();
      case 'ended':
        _completed.add(true);
      case 'noaudio':
        _noSound.add((m['mime'] ?? '').toString());
      case 'firstframe':
        _firstFrame.add(null);
      case 'texture':
        final textureId = (m['texture'] as num?)?.toInt() ?? -1;
        if (textureId >= 0) _texture.value = textureId;
      case 'log':
        debugPrint('B1G exo: ${m['text'] ?? ''}');
      case 'enhanceoff':
        enhanceLevel = 0;
        _enhanceFailed.add(null);
      case 'error':
        final text = (m['message'] ?? '').toString();
        // The enhanced picture could not be made on this device: the retry plays without it.
        if (enhanceLevel > 0 && text.contains('VIDEO_FRAME_PROCESS')) {
          enhanceLevel = 0;
          _enhanceFailed.add(null);
        }
        _messages.add(EngineMessage('exo: $text failed to open', true));
    }
  }

  Future<void> _call(String method, [Map<String, Object?> args = const {}]) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>(method, {'id': _id, ...args});
    } catch (_) {}
  }

  @override
  String get name => 'exo';
  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration> get duration => _duration.stream;
  @override
  Stream<bool> get buffering => _buffering.stream;
  @override
  Stream<bool> get completed => _completed.stream;
  @override
  Stream<Tracks> get tracks => _tracks.stream;
  @override
  Stream<EngineMessage> get messages => _messages.stream;
  @override
  Duration get durationNow => _dur;
  @override
  Tracks get tracksNow => _trackList;
  @override
  int get width => _size.value.width.toInt();
  @override
  int get height => _size.value.height.toInt();
  @override
  bool get playing => _playing;
  @override
  bool get isBuffering => _isBuffering;

  @override
  Future<void> open(String url, Duration start) {
    // A reused engine: forget what belonged to the previous stream.
    _lastFps = 0;
    _dur = Duration.zero;
    _trackList = Tracks();
    return _call('open', {'url': url, 'startMs': start.inMilliseconds, 'enhance': enhanceLevel});
  }

  @override
  bool get canPreload => true;

  @override
  Future<void> preload(String url, Duration start) {
    _lastFps = 0;
    _dur = Duration.zero;
    _trackList = Tracks();
    return _call('open', {'url': url, 'startMs': start.inMilliseconds, 'enhance': enhanceLevel, 'paused': true});
  }

  @override
  bool get reusable => !_disposed;
  @override
  Future<void> stop() => _call('stop');

  @override
  bool get canEnhance => true;
  @override
  Stream<String> get soundUnsupported => _noSound.stream;
  @override
  Stream<void> get enhanceFailed => _enhanceFailed.stream;
  @override
  Stream<void> get firstFrame => _firstFrame.stream;

  // ExoPlayer applies the effects when a stream opens: a change means reopening.
  @override
  Future<bool> setEnhance(int level) async => false;

  Future<void> _readStats() async {
    if (_disposed) return;
    try {
      final f = await _channel.invokeMethod<Map<dynamic, dynamic>>('facts', {'id': _id});
      _lastDropped = (f?['dropped'] as num?)?.toInt() ?? _lastDropped;
      final declared = (f?['fps'] as num?)?.toDouble() ?? 0;
      final measured = (f?['fpsEst'] as num?)?.toDouble() ?? 0;
      _lastFps = declared > 0 ? declared : (measured > 0 ? _roundFps(measured) : _lastFps);
    } catch (_) {}
  }

  @override
  Future<int> droppedFrames() async {
    await _readStats();
    return _lastDropped;
  }

  @override
  Future<double> fps() async {
    if (_lastFps <= 0) {
      await _readStats();
      if (_lastFps <= 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        await _readStats();
      }
    }
    return _lastFps;
  }
  @override
  Future<void> play() => _call('play');
  @override
  Future<void> pause() => _call('pause');
  @override
  Future<void> seek(Duration to) => _call('seek', {'ms': to.inMilliseconds});
  @override
  Future<void> setRate(double rate) => _call('rate', {'rate': rate});
  @override
  Future<void> setAudioTrack(AudioTrack track) => _call('track', {'kind': 'a', 'track': track.id});
  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) => _call('track', {'kind': 's', 'track': track.id});
  @override
  Future<void> setVideoTrack(VideoTrack track) => _call('track', {'kind': 'v', 'track': track.id});

  @override
  Future<List<String>> facts() async {
    if (_disposed) return const [];
    Map<dynamic, dynamic>? f;
    try {
      f = await _channel.invokeMethod<Map<dynamic, dynamic>>('facts', {'id': _id});
    } catch (_) {}
    if (f == null) return const ['Engine: ExoPlayer'];
    String mime(Object? v) {
      final s = (v ?? '').toString();
      final slash = s.indexOf('/');
      return (slash >= 0 ? s.substring(slash + 1) : s).toUpperCase();
    }

    final fps = (f['fps'] as num?)?.toDouble() ?? 0;
    final decoder = (f['decoder'] ?? '').toString();
    final software = decoder.startsWith('c2.android') || decoder.startsWith('OMX.google') || decoder.contains('ffmpeg');
    return [
      'Engine: ExoPlayer',
      if (mime(f['video']).isNotEmpty)
        'Video: ${mime(f['video'])}${fps > 0 ? ', ${fps.toStringAsFixed(fps == fps.roundToDouble() ? 0 : 2)} pictures a second' : ''}',
      if (decoder.isNotEmpty) software ? 'Decoded by the processor ($decoder)' : 'Decoded by the video chip ($decoder)',
      if (mime(f['audio']).isNotEmpty) 'Sound: ${mime(f['audio'])}',
      'Pictures skipped so far: ${(f['dropped'] as num?)?.toInt() ?? 0}',
      'Picture Enhance: ${_levelName(enhanceLevel)}',
      if ((f['surface'] ?? '').toString().isNotEmpty) 'Picture surface: ${f['surface']}',
    ];
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await _call('dispose');
    _disposed = true;
    _live.remove(_id);
    for (final c in [_position, _duration, _buffering, _completed, _tracks, _messages, _noSound, _enhanceFailed, _firstFrame]) {
      await c.close();
    }
  }

  @override
  Widget view({required BoxFit fit, required double subtitlePad}) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder<Size>(
            valueListenable: _size,
            builder: (context, size, _) {
              final s = size.isEmpty ? const Size(1920, 1080) : size;
              return ClipRect(
                child: FittedBox(
                  fit: fit,
                  child: SizedBox(
                    width: s.width,
                    height: s.height,
                    child: ValueListenableBuilder<int>(
                      valueListenable: _texture,
                      builder: (context, id, _) => Texture(textureId: id),
                    ),
                  ),
                ),
              );
            },
          ),
          ValueListenableBuilder<String>(
            valueListenable: _cues,
            builder: (context, text, _) => text.isEmpty
                ? const SizedBox.shrink()
                : Positioned(
                    left: 24,
                    right: 24,
                    bottom: subtitlePad,
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        height: 1.25,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black), Shadow(blurRadius: 2, color: Colors.black)],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}


/// mpv user shader: contrast-adaptive sharpen (the idea of AMD's CAS) on the decoded picture.
String _casShader(double sharp) => """//!HOOK MAIN
//!BIND HOOKED
//!DESC Lite Picture Enhance
vec4 hook() {
  vec4 e4 = HOOKED_tex(HOOKED_pos);
  vec3 e = e4.rgb;
  vec3 b = HOOKED_texOff(vec2(0.0, -1.0)).rgb;
  vec3 d = HOOKED_texOff(vec2(-1.0, 0.0)).rgb;
  vec3 f = HOOKED_texOff(vec2(1.0, 0.0)).rgb;
  vec3 h = HOOKED_texOff(vec2(0.0, 1.0)).rgb;
  vec3 mn = min(min(min(d, e), min(f, b)), h);
  vec3 mx = max(max(max(d, e), max(f, b)), h);
  vec3 amp = sqrt(clamp(min(mn, 1.0 - mx) / max(mx, 0.0001), 0.0, 1.0));
  vec3 w = -amp / mix(8.0, 5.0, ${sharp.toStringAsFixed(2)});
  vec3 c = (b * w + d * w + f * w + h * w + e) / (1.0 + 4.0 * w);
  return vec4(clamp(c, 0.0, 1.0), e4.a);
}
""";

String _levelName(int level) => level >= 2 ? 'High' : (level == 1 ? 'Low' : 'Off');

/// A measured rate snapped to the usual video rates (23.976, 24, 25, 29.97, 30, 50, 59.94, 60).
double _roundFps(double v) {
  const rates = [23.976, 24.0, 25.0, 29.97, 30.0, 50.0, 59.94, 60.0];
  var best = 0.0;
  var diff = 1e9;
  for (final r in rates) {
    final d = (v - r).abs();
    if (d < diff) {
      diff = d;
      best = r;
    }
  }
  return diff <= best * 0.04 ? best : 0;
}
