import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../config.dart';
import '../engine.dart';
import '../remote_brand.dart';

/// The start animation, made in code (no video): a red glow and light streaks open the dark
/// screen, the brand symbol (brand/icon.png) turns in and lands with a light ring, a shine runs
/// over it and the app name appears letter by letter. The startup sound plays with it. Shown
/// once per app start, then [next]. Any key or tap skips it.
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.next});
  final Widget next;

  static bool _shown = false;

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> with SingleTickerProviderStateMixin {
  // TVs (Samsung / LG web build) draw without a GPU video path: the intro is shorter there.
  static const _length = Duration(milliseconds: kTizen ? 3200 : 4100);

  late final AnimationController _c = AnimationController(vsync: this, duration: _length);
  bool _done = IntroGate._shown;
  ExoEngine? _sound;
  final FocusNode _focus = FocusNode(debugLabel: 'intro');

  @override
  void initState() {
    super.initState();
    IntroGate._shown = true;
    if (_done) return;
    // A video or picture set on the website replaces the built-in animation.
    if (RemoteBrand.introSource != null) return;
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
    _start();
  }

  Future<void> _start() async {
    // The sound starts together with the picture; without sound (web, or a problem) the
    // animation simply runs silently.
    if (ExoEngine.available) {
      try {
        final e = await ExoEngine.create(live: false).timeout(const Duration(milliseconds: 900));
        if (!mounted || _done) {
          e.dispose();
          return;
        }
        _sound = e;
        unawaited(e.open('asset:///flutter_assets/assets/intro_sound.mp3', Duration.zero));
      } catch (_) {}
    }
    if (mounted && !_done) _c.forward();
  }

  void _finish() {
    if (_done) return;
    final e = _sound;
    _sound = null;
    e?.dispose();
    if (mounted) setState(() => _done = true);
  }

  @override
  void dispose() {
    _c.dispose();
    _sound?.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.next;
    final custom = RemoteBrand.introSource;
    if (custom != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent) _finish();
            return KeyEventResult.handled;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _finish,
            child: _CustomIntro(
              source: custom,
              video: RemoteBrand.introType == 'video',
              seconds: RemoteBrand.introSeconds,
              onDone: _finish,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B0506),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent) _finish();
          return KeyEventResult.handled;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _finish,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => _LiteIntro(t: _c.value * _length.inMilliseconds / 1000),
          ),
        ),
      ),
    );
  }
}

/// The intro made by the owner (website -> Settings -> App look): a video plays to its end
/// (at most 15 s), a picture stays [seconds]. Any problem simply continues into the app.
class _CustomIntro extends StatefulWidget {
  const _CustomIntro({required this.source, required this.video, required this.seconds, required this.onDone});
  final String source;
  final bool video;
  final int seconds;
  final VoidCallback onDone;

  @override
  State<_CustomIntro> createState() => _CustomIntroState();
}

class _CustomIntroState extends State<_CustomIntro> {
  Player? _player;
  VideoController? _controller;
  Timer? _limit;
  StreamSubscription<bool>? _end;
  StreamSubscription<String>? _error;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    if (widget.video) {
      final p = Player();
      _player = p;
      _controller = VideoController(p);
      _end = p.stream.completed.listen((done) {
        if (done) widget.onDone();
      });
      _error = p.stream.error.listen((_) => widget.onDone());
      unawaited(p.open(Media(widget.source)));
      _limit = Timer(const Duration(seconds: 15), widget.onDone);
    } else {
      _limit = Timer(Duration(seconds: widget.seconds), widget.onDone);
    }
    // Soft fade in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _limit?.cancel();
    _end?.cancel();
    _error?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    final c = _controller;
    if (c != null) {
      child = Video(controller: c, controls: NoVideoControls, fit: BoxFit.contain, fill: Colors.black);
    } else {
      final ImageProvider img =
          kIsWeb ? NetworkImage(widget.source) : FileImage(File(widget.source)) as ImageProvider;
      child = Image(
        image: img,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
          return const SizedBox();
        },
      );
    }
    return AnimatedOpacity(opacity: _visible ? 1 : 0, duration: const Duration(milliseconds: 450), child: child);
  }
}

// ----------------------------------------------------------------------------------- drawing

double _clamp(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);
double _seg(double t, double a, double b) => _clamp((t - a) / (b - a));
double _outCubic(double x) => 1 - math.pow(1 - x, 3).toDouble();
double _outBack(double x) {
  const c1 = 1.70158, c3 = c1 + 1;
  return 1 + c3 * math.pow(x - 1, 3) + c1 * math.pow(x - 1, 2);
}

const _red = Color(0xFFE3262F);

/// One frame of the intro at time [t] (seconds, 0 .. 4.1).
class _LiteIntro extends StatelessWidget {
  const _LiteIntro({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final out = kTizen ? _seg(t, 2.7, 3.2) : _seg(t, 3.55, 4.1); // final fade
    final enter = _seg(t, 0.35, 1.55);
    final e = _outBack(enter);
    final name = RemoteBrand.introName.isNotEmpty ? RemoteBrand.introName : kAppName;
    final letters = (name.length * _seg(t, 1.85, 2.9)).ceil();
    final underline = _outCubic(_seg(t, 2.55, 3.15));
    return LayoutBuilder(builder: (context, box) {
      final icon = box.maxHeight * 0.34;
      // TVs: a plain scale (the 3D turn re-rasterises the picture every frame and stutters).
      final m = Matrix4.identity()..setEntry(3, 2, kTizen ? 0.0 : 0.0014);
      if (!kTizen) m.rotateY((1 - e) * math.pi * 1.1);
      m.scaleByDouble(0.25 + 0.75 * e, 0.25 + 0.75 * e, 1, 1);
      return Opacity(
        opacity: 1 - out,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _GlowPainter(t)),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: _clamp(enter * 1.8),
                    child: Transform(
                      alignment: Alignment.center,
                      transform: m,
                      child: SizedBox(
                        width: icon,
                        height: icon,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            RemoteBrand.symbol != null
                                ? Image(
                                    image: RemoteBrand.symbol!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const _FallbackMark())
                                : Image.asset('assets/symbol.png',
                                    fit: BoxFit.contain, errorBuilder: (_, __, ___) => const _FallbackMark()),
                            // A light runs across the symbol once.
                            ClipRect(
                              child: CustomPaint(painter: _ShinePainter(_seg(t, 2.3, 3.0))),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: box.maxHeight * 0.05),
                  SizedBox(
                    height: box.maxHeight * 0.11,
                    child: Text(
                      name.substring(0, letters.clamp(0, name.length)),
                      style: TextStyle(
                        fontSize: box.maxHeight * 0.075,
                        fontWeight: FontWeight.w900,
                        letterSpacing: box.maxHeight * 0.006,
                        color: Colors.white,
                        // Blurred shadows are what TVs render slowest: none there.
                        shadows: kTizen ? null : const [Shadow(color: Color(0xAAE3262F), blurRadius: 24)],
                      ),
                    ),
                  ),
                  Container(
                    width: box.maxWidth * 0.22 * underline,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _red,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: kTizen ? null : const [BoxShadow(color: Color(0xCCE3262F), blurRadius: 14)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Background: a red glow that grows from the middle, light streaks crossing the screen and a
/// light ring when the symbol lands.
class _GlowPainter extends CustomPainter {
  _GlowPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.42);
    final glow = _outCubic(_seg(t, 0, 1.2));
    final pulse = 1 + 0.06 * math.sin(t * 5);
    canvas.drawCircle(
      c,
      size.height * 0.75 * glow * pulse,
      Paint()
        ..shader = RadialGradient(colors: [
          _red.withValues(alpha: 0.55 * glow),
          const Color(0x55801018),
          const Color(0x000B0506),
        ], stops: const [0, 0.45, 1])
            .createShader(Rect.fromCircle(center: c, radius: size.height * 0.75 * glow * pulse + 1)),
    );

    // Diagonal light streaks sweeping across (fewer on TVs).
    for (var i = 0; i < (kTizen ? 2 : 5); i++) {
      final p = _seg(t, 0.05 + i * 0.14, 1.05 + i * 0.14);
      if (p <= 0 || p >= 1) continue;
      final x = -size.width * 0.3 + p * size.width * 1.6;
      final y = size.height * (0.15 + i * 0.17);
      final len = size.width * (0.25 + 0.08 * i);
      final paint = Paint()
        ..strokeWidth = 2.0 + i
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(colors: [
          const Color(0x00FFFFFF),
          Color.lerp(Colors.white, _red, i / 5)!.withValues(alpha: 0.85 * math.sin(p * math.pi)),
          const Color(0x00FFFFFF),
        ]).createShader(Rect.fromLTWH(x - len, y - 40, len, 80));
      canvas.drawLine(Offset(x - len, y + len * 0.12), Offset(x, y - len * 0.12), paint);
    }

    // The ring when the symbol lands.
    final ring = _seg(t, 1.45, 2.2);
    if (ring > 0 && ring < 1) {
      canvas.drawCircle(
        c,
        size.height * (0.18 + 0.5 * _outCubic(ring)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 * (1 - ring) + 1
          ..color = Colors.white.withValues(alpha: 0.7 * (1 - ring)),
      );
      canvas.drawCircle(
        c,
        size.height * (0.14 + 0.38 * _outCubic(ring)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10 * (1 - ring) + 1
          ..color = _red.withValues(alpha: 0.6 * (1 - ring)),
      );
    }

    // Small sparks drifting up.
    final rnd = math.Random(7);
    final sp = _seg(t, 1.5, 4.1);
    if (sp > 0) {
      for (var i = 0; i < (kTizen ? 10 : 26); i++) {
        final sx = rnd.nextDouble() * size.width;
        final sy = size.height * (0.9 - rnd.nextDouble() * 0.3) - sp * size.height * (0.3 + rnd.nextDouble() * 0.5);
        final a = (math.sin(sp * math.pi) * (0.3 + rnd.nextDouble() * 0.6)).clamp(0.0, 1.0);
        canvas.drawCircle(Offset(sx, sy), 1.2 + rnd.nextDouble() * 2.2,
            Paint()..color = Color.lerp(Colors.white, _red, rnd.nextDouble())!.withValues(alpha: a));
      }
    }
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.t != t;
}

/// A bright diagonal band moving across the symbol.
class _ShinePainter extends CustomPainter {
  _ShinePainter(this.p);
  final double p;

  @override
  void paint(Canvas canvas, Size size) {
    if (p <= 0 || p >= 1) return;
    final x = -size.width * 0.6 + p * size.width * 2.2;
    final r = Rect.fromLTWH(x - size.width * 0.3, 0, size.width * 0.3, size.height);
    canvas.save();
    canvas.skew(-0.35, 0);
    canvas.drawRect(
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = const LinearGradient(
          colors: [Color(0x00FFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
        ).createShader(r),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShinePainter old) => old.p != p;
}

/// Shown only if the brand symbol picture is missing.
class _FallbackMark extends StatelessWidget {
  const _FallbackMark();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: const Color(0xFF18181C), borderRadius: BorderRadius.circular(40)),
        child: const Icon(Icons.play_arrow_rounded, color: _red, size: 120),
      );
}
