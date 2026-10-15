import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

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
    // Same decode sizes the lists use, so the picture usually comes straight from memory.
    // A missing or broken picture simply leaves the space empty (no grey box).
    Widget img(int cw, BoxFit fit) => url.startsWith('http')
        ? Image.network(
            url,
            fit: fit,
            cacheWidth: cw,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            frameBuilder: (_, child, frame, sync) => AnimatedOpacity(
              opacity: frame == null && !sync ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: child,
            ),
          )
        : const SizedBox.shrink();
    final pic = live
        ? SizedBox(width: h * 0.34, height: h * 0.2, child: img(240, BoxFit.contain))
        : ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(height: h * 0.4, child: AspectRatio(aspectRatio: 2 / 3, child: img(360, BoxFit.cover))),
          );
    // Picture above the middle, the name below it: the middle stays free for the soft pulse.
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.1,
          colors: [Color(0xFF241417), Color(0xFF0B0608)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment(0, live ? -0.42 : -0.5),
            child: pic,
          ),
          Align(
            alignment: Alignment(0, live ? 0.34 : 0.5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(subtitle,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.dim, fontSize: 14)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft, breathing glow — shown only when a start or a pause to buffer takes longer than
/// half a second (quick starts never show anything). No numbers, no bars.
class SoftPulse extends StatefulWidget {
  const SoftPulse({super.key, this.label, this.size});

  final String? label;

  /// Size of the glow (default: about 7 % of the screen height).
  final double? size;

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
        alignment: Alignment.center,
        child: AnimatedOpacity(
          opacity: _show ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                child: SizedBox(
                  width: widget.size ?? math.max(44, h * 0.07),
                  height: widget.size ?? math.max(44, h * 0.07),
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
