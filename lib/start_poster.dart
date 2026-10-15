import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart' show NetImage;

/// Instant start: the channel logo / film poster is on screen the moment playback is asked for,
/// so there is never a black screen. When the first picture of the video is ready it fades away
/// (about a quarter of a second) and the video is simply there.
class StartPoster extends StatelessWidget {
  const StartPoster({
    super.key,
    required this.visible,
    required this.url,
    required this.title,
    this.subtitle = '',
    this.live = true,
  });

  final bool visible;
  final String url;
  final String title;
  final String subtitle;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        // Appears at once, leaves softly (the cross-fade into the video).
        duration: visible ? Duration.zero : const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: RepaintBoundary(child: _content(context)),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final hasPic = url.startsWith('http');
    // Same decode sizes the lists use, so the picture usually comes straight from memory.
    final pic = live
        ? SizedBox(
            width: h * 0.34,
            height: h * 0.22,
            child: NetImage(url, fit: BoxFit.contain, cacheWidth: 240),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: h * 0.5,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: NetImage(url, fit: BoxFit.cover, cacheWidth: 360, fallback: Icons.movie_rounded),
              ),
            ),
          );
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.15),
          radius: 1.1,
          colors: [Color(0xFF241417), Color(0xFF0B0608)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasPic)
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 28, offset: Offset(0, 10))],
                ),
                child: pic,
              ),
            SizedBox(height: hasPic ? 22 : 0),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: C.dim, fontSize: 14)),
            ],
            // Room for the soft pulse under the title (it only shows on a slow start).
            SizedBox(height: h * 0.12),
          ],
        ),
      ),
    );
  }
}

/// A soft, breathing glow — shown only when a start or a pause to buffer takes longer than
/// half a second (quick starts never show anything). No numbers, no bars.
class SoftPulse extends StatefulWidget {
  const SoftPulse({super.key, this.label, this.belowPoster = false});

  final String? label;

  /// Sits under the poster's title instead of in the middle of the screen.
  final bool belowPoster;

  @override
  State<SoftPulse> createState() => _SoftPulseState();
}

class _SoftPulseState extends State<SoftPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  Timer? _delay;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _delay = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _show = true);
      _c.repeat();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return IgnorePointer(
      child: Align(
        alignment: widget.belowPoster ? Alignment(0, 0.62) : Alignment.center,
        child: AnimatedOpacity(
          opacity: _show ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                child: SizedBox(
                  width: math.max(44, h * 0.07),
                  height: math.max(44, h * 0.07),
                  child: _show ? CustomPaint(painter: _PulsePainter(_c)) : null,
                ),
              ),
              if (widget.label != null && widget.label!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(widget.label!,
                    style: const TextStyle(color: C.dim, fontSize: 14, shadows: [Shadow(color: Colors.black, blurRadius: 6)])),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Painted straight from the animation (no widget rebuilds): a glowing dot that breathes
/// and a ring that softly widens and fades.
class _PulsePainter extends CustomPainter {
  _PulsePainter(this.a) : super(repaint: a);
  final Animation<double> a;

  @override
  void paint(Canvas canvas, Size size) {
    final t = a.value;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final breathe = 0.5 - 0.5 * math.cos(t * 2 * math.pi); // 0..1..0
    // Ring
    final ringR = r * (0.45 + 0.55 * t);
    canvas.drawCircle(
      c,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.08
        ..color = C.accent.withValues(alpha: 0.55 * (1 - t)),
    );
    // Glow and dot
    canvas.drawCircle(
      c,
      r * (0.30 + 0.08 * breathe),
      Paint()
        ..color = C.accent.withValues(alpha: 0.18 + 0.17 * breathe)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(c, r * (0.17 + 0.04 * breathe), Paint()..color = Color.lerp(C.accent, Colors.white, 0.25 * breathe)!);
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) => false;
}
