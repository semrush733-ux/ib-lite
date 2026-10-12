import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A small puppy that runs along the bottom of the screen from one corner to the other,
/// turns round and runs back. Purely decorative: put it under IgnorePointer/ExcludeFocus.
class RunningPuppy extends StatefulWidget {
  const RunningPuppy({super.key, this.size = 64, this.lap = const Duration(seconds: 9)});

  /// Width of the puppy in logical pixels.
  final double size;

  /// Time for one run across the screen.
  final Duration lap;

  @override
  State<RunningPuppy> createState() => _RunningPuppyState();
}

class _RunningPuppyState extends State<RunningPuppy> with TickerProviderStateMixin {
  // Across and back: 0..1 left to right, 1..2 right to left.
  late final AnimationController _run =
      AnimationController(vsync: this, duration: widget.lap * 2)..repeat();
  // Leg swing, tail wag and the little bounce.
  late final AnimationController _step =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 360))..repeat();

  @override
  void dispose() {
    _run.dispose();
    _step.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.size;
    final h = w * 0.72;
    return LayoutBuilder(builder: (context, box) {
      return AnimatedBuilder(
        animation: Listenable.merge([_run, _step]),
        builder: (context, _) {
          final v = _run.value * 2;
          final right = v < 1; // running to the right
          final p = right ? v : 2 - v;
          // Slow start and stop at each corner.
          final eased = Curves.easeInOut.transform(p);
          final travel = box.maxWidth - w - 24;
          final x = 12 + travel * eased;
          final phase = _step.value * 2 * math.pi;
          final bounce = math.sin(phase * 2).abs() * 4;
          return Stack(
            children: [
              Positioned(
                left: x,
                bottom: 10 + bounce,
                width: w,
                height: h,
                child: Transform.flip(
                  flipX: !right,
                  child: CustomPaint(painter: _PuppyPainter(phase)),
                ),
              ),
              // Soft shadow under the puppy.
              Positioned(
                left: x + w * 0.15,
                bottom: 6,
                width: w * 0.7,
                height: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28 - bounce * 0.03),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          );
        },
      );
    });
  }
}

/// The puppy faces right; [phase] (radians) drives legs and tail.
class _PuppyPainter extends CustomPainter {
  _PuppyPainter(this.phase);
  final double phase;

  static const _fur = Color(0xFFE8B77A);
  static const _dark = Color(0xFF9A5F2E);
  static const _ink = Color(0xFF2A1A12);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final fur = Paint()..color = _fur;
    final dark = Paint()..color = _dark;
    final ink = Paint()..color = _ink;
    final legPaint = Paint()
      ..color = _fur
      ..strokeWidth = w * 0.085
      ..strokeCap = StrokeCap.round;
    final backLeg = Paint()
      ..color = const Color(0xFFD29F62)
      ..strokeWidth = w * 0.085
      ..strokeCap = StrokeCap.round;

    final swing = math.sin(phase) * 0.55;
    final hipY = h * 0.62;
    final legLen = h * 0.3;

    void leg(double x, double angle, Paint p) {
      final end = Offset(x + math.sin(angle) * legLen, hipY + math.cos(angle) * legLen);
      canvas.drawLine(Offset(x, hipY), end, p);
    }

    // Far legs first (darker), then the body, then the near legs.
    leg(w * 0.30, -swing, backLeg);
    leg(w * 0.66, swing, backLeg);

    // Tail, wagging.
    final wag = math.sin(phase * 2) * 0.5;
    final tail = Path()
      ..moveTo(w * 0.17, h * 0.46)
      ..quadraticBezierTo(w * 0.04, h * (0.30 - wag * 0.2), w * 0.06, h * (0.14 - wag * 0.12));
    canvas.drawPath(
        tail,
        Paint()
          ..color = _fur
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.07
          ..strokeCap = StrokeCap.round);

    // Body.
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.14, h * 0.36, w * 0.6, h * 0.32), Radius.circular(h * 0.16)), fur);
    // Patch on the back.
    canvas.drawOval(Rect.fromLTWH(w * 0.30, h * 0.36, w * 0.2, h * 0.13), dark);

    leg(w * 0.24, swing, legPaint);
    leg(w * 0.70, -swing, legPaint);

    // Head.
    final head = Offset(w * 0.78, h * 0.33);
    final r = h * 0.2;
    canvas.drawCircle(head, r, fur);
    // Snout.
    canvas.drawOval(Rect.fromCenter(center: head + Offset(r * 0.95, r * 0.35), width: r * 1.1, height: r * 0.8), fur);
    canvas.drawCircle(head + Offset(r * 1.45, r * 0.22), r * 0.2, ink); // nose
    // Ear, flopping with the run.
    canvas.save();
    canvas.translate(head.dx - r * 0.2, head.dy - r * 0.7);
    canvas.rotate(0.35 + math.sin(phase) * 0.18);
    canvas.drawOval(Rect.fromLTWH(-r * 0.35, 0, r * 0.7, r * 1.25), dark);
    canvas.restore();
    // Eye with a tiny shine.
    canvas.drawCircle(head + Offset(r * 0.42, -r * 0.12), r * 0.17, ink);
    canvas.drawCircle(head + Offset(r * 0.47, -r * 0.18), r * 0.06, Paint()..color = Colors.white);
    // Tongue.
    canvas.drawOval(
        Rect.fromCenter(center: head + Offset(r * 1.05, r * 0.82), width: r * 0.32, height: r * 0.42),
        Paint()..color = const Color(0xFFFF6F86));
  }

  @override
  bool shouldRepaint(_PuppyPainter old) => old.phase != phase;
}
