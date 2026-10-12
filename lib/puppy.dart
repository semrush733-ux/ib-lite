import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

/// A small puppy that lives along the bottom of the screen: it runs to a spot, sits down,
/// wags its tail, tilts its head and blinks, then gets up and runs somewhere else
/// (corner to corner and stops in between). Purely decorative: put it under
/// IgnorePointer/ExcludeFocus.
class RunningPuppy extends StatefulWidget {
  const RunningPuppy({super.key, this.size = 64});

  /// Width of the puppy in logical pixels.
  final double size;

  @override
  State<RunningPuppy> createState() => _RunningPuppyState();
}

enum _Mode { run, sit }

class _RunningPuppyState extends State<RunningPuppy> with SingleTickerProviderStateMixin {
  final _rnd = math.Random();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  // Ticks the painter directly: no widget is rebuilt per frame.
  final _frame = ValueNotifier<int>(0);

  double _x = 0; // 0 = left corner, 1 = right corner
  double _target = 1;
  bool _right = true;
  _Mode _mode = _Mode.run;
  double _modeTime = 0; // seconds in the current mode
  double _sitFor = 3;
  double _clock = 0; // drives legs, tail, blinking

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05).toDouble();
    _last = now;
    _clock += dt;
    _modeTime += dt;
    if (_mode == _Mode.run) {
      const speed = 0.16; // screen widths per second
      final dir = _target > _x ? 1.0 : -1.0;
      _right = dir > 0;
      _x += dir * speed * dt;
      if ((dir > 0 && _x >= _target) || (dir < 0 && _x <= _target)) {
        _x = _target;
        _mode = _Mode.sit;
        _modeTime = 0;
        _sitFor = 2.5 + _rnd.nextDouble() * 3;
      }
    } else if (_modeTime > _sitFor) {
      // Next stop: often the far corner, sometimes a spot in between.
      final corner = _x < 0.5 ? 1.0 : 0.0;
      _target = _rnd.nextDouble() < 0.6 ? corner : 0.15 + _rnd.nextDouble() * 0.7;
      if ((_target - _x).abs() < 0.15) _target = corner;
      _mode = _Mode.run;
      _modeTime = 0;
    }
    _frame.value++;
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.size * 0.78;
    // Its own layer at the bottom of the screen: redrawing the puppy never redraws the rest.
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: h + 22,
        width: double.infinity,
        child: RepaintBoundary(
          child: CustomPaint(painter: _StripPainter(this, widget.size, _frame)),
        ),
      ),
    );
  }
}

/// Draws the shadow and the puppy at its place in the strip along the bottom.
class _StripPainter extends CustomPainter {
  _StripPainter(this.s, this.w, Listenable repaint) : super(repaint: repaint);
  final _RunningPuppyState s;
  final double w;

  @override
  void paint(Canvas canvas, Size size) {
    final h = w * 0.78;
    final running = s._mode == _Mode.run;
    final phase = s._clock * 2 * math.pi / 0.36;
    final bounce = running ? math.sin(phase * 2).abs() * 4 : 0.0;
    final sit = running ? 0.0 : (s._modeTime / 0.25).clamp(0.0, 1.0).toDouble();
    final left = 12 + (size.width - w - 24) * s._x.clamp(0.0, 1.0).toDouble();
    // Soft shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left + w * 0.15, size.height - 12, w * 0.7, 6), const Radius.circular(6)),
      Paint()..color = Colors.black.withValues(alpha: 0.28 - bounce * 0.03),
    );
    canvas.save();
    canvas.translate(left, size.height - 8 - bounce - h);
    if (!s._right) {
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }
    _PuppyPainter(phase: running ? phase : 0, sit: sit, time: s._clock, sitTime: running ? 0 : s._modeTime)
        .paint(canvas, Size(w, h));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripPainter old) => false;
}

/// The puppy faces right. [phase] drives the running legs, [sit] (0..1) folds it into a sitting
/// pose, [time] and [sitTime] drive the tail wag, head tilt and blinking.
class _PuppyPainter extends CustomPainter {
  _PuppyPainter({required this.phase, required this.sit, required this.time, required this.sitTime});
  final double phase;
  final double sit;
  final double time;
  final double sitTime;

  static const _fur = Color(0xFFE8B77A);
  static const _shade = Color(0xFFD29F62);
  static const _dark = Color(0xFF9A5F2E);
  static const _ink = Color(0xFF2A1A12);

  double _mix(double a, double b) => a + (b - a) * sit;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final fur = Paint()..color = _fur;
    final dark = Paint()..color = _dark;
    final ink = Paint()..color = _ink;
    Paint stroke(Color c, double width) => Paint()
      ..color = c
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final legW = w * 0.085;

    final swing = math.sin(phase) * 0.55 * (1 - sit);
    final ground = h * 0.95;

    // Body: level while running, tipped up (rear down) while sitting.
    final tilt = _mix(0, -0.55);
    final bodyCenter = Offset(_mix(w * 0.44, w * 0.46), _mix(h * 0.55, h * 0.62));

    // ---- far legs
    final hipFar = Offset(w * 0.30, _mix(h * 0.66, h * 0.86));
    final shoulderFar = Offset(_mix(w * 0.66, w * 0.62), _mix(h * 0.66, h * 0.58));
    final legLen = h * 0.3;
    Offset foot(Offset from, double angle) => Offset(from.dx + math.sin(angle) * legLen, from.dy + math.cos(angle) * legLen);
    // Rear leg folds forward along the ground when sitting.
    final rearFoldFar = Offset(_mix(foot(hipFar, -swing).dx, w * 0.44), _mix(foot(hipFar, -swing).dy, ground));
    canvas.drawLine(hipFar, rearFoldFar, stroke(_shade, legW));
    canvas.drawLine(shoulderFar, Offset(_mix(foot(shoulderFar, swing).dx, shoulderFar.dx + w * 0.02), ground),
        stroke(_shade, legW));

    // ---- tail: wags fast while sitting
    final wagSpeed = sit > 0.5 ? 14.0 : 7.0;
    final wag = math.sin(time * wagSpeed) * (sit > 0.5 ? 0.9 : 0.4);
    final tailBase = Offset(_mix(w * 0.17, w * 0.2), _mix(h * 0.46, h * 0.82));
    final tail = Path()
      ..moveTo(tailBase.dx, tailBase.dy)
      ..quadraticBezierTo(
        _mix(w * 0.04, w * 0.02 + wag * w * 0.04),
        _mix(h * (0.30 - wag * 0.2), h * 0.80),
        _mix(w * 0.06, w * 0.04 - wag * w * 0.06),
        _mix(h * (0.14 - wag * 0.12), h * (0.62 - wag * 0.12)),
      );
    canvas.drawPath(tail, stroke(_fur, w * 0.07));

    // ---- body
    canvas.save();
    canvas.translate(bodyCenter.dx, bodyCenter.dy);
    canvas.rotate(tilt);
    final bw = _mix(w * 0.6, w * 0.46), bh = h * 0.32;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: bw, height: bh), Radius.circular(bh / 2)), fur);
    canvas.drawOval(Rect.fromCenter(center: Offset(-bw * 0.08, -bh * 0.3), width: bw * 0.34, height: bh * 0.4), dark);
    canvas.restore();

    // ---- near legs
    final hip = Offset(w * 0.25, _mix(h * 0.66, h * 0.84));
    final shoulder = Offset(_mix(w * 0.70, w * 0.66), _mix(h * 0.66, h * 0.58));
    if (sit > 0.5) {
      // Sitting: a round haunch with the paw in front.
      canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.3, h * 0.8), width: w * 0.24, height: h * 0.24), Paint()..color = _fur);
      canvas.drawLine(Offset(w * 0.34, h * 0.9), Offset(w * 0.48, ground), stroke(_fur, legW));
    } else {
      canvas.drawLine(hip, foot(hip, swing), stroke(_fur, legW));
    }
    canvas.drawLine(shoulder, Offset(_mix(foot(shoulder, -swing).dx, shoulder.dx + w * 0.04), _mix(foot(shoulder, -swing).dy, ground)),
        stroke(_fur, legW));

    // ---- head: higher when sitting, tilts now and then
    final tiltHead = sit > 0.5 ? math.sin(sitTime * 1.6) * 0.22 : 0.0;
    final head = Offset(_mix(w * 0.78, w * 0.70), _mix(h * 0.33, h * 0.27));
    final r = h * 0.2;
    // Neck joins the head to the body in both poses.
    canvas.drawLine(Offset(_mix(w * 0.68, w * 0.60), _mix(h * 0.5, h * 0.5)), head, stroke(_fur, r * 1.1));
    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.rotate(tiltHead);
    canvas.drawCircle(Offset.zero, r, fur);
    canvas.drawOval(Rect.fromCenter(center: Offset(r * 0.95, r * 0.35), width: r * 1.1, height: r * 0.8), fur);
    canvas.drawCircle(Offset(r * 1.45, r * 0.22), r * 0.2, ink); // nose
    // Ear: flops while running, perks up a little while sitting.
    canvas.save();
    canvas.translate(-r * 0.2, -r * 0.7);
    canvas.rotate(_mix(0.35 + math.sin(phase) * 0.18, 0.15 + math.sin(time * 3) * 0.05));
    canvas.drawOval(Rect.fromLTWH(-r * 0.35, 0, r * 0.7, r * 1.25), dark);
    canvas.restore();
    // Eye, blinking every few seconds.
    final blink = (time % 3.4) < 0.14;
    if (blink) {
      canvas.drawLine(Offset(r * 0.28, -r * 0.12), Offset(r * 0.58, -r * 0.12), stroke(_ink, r * 0.08));
    } else {
      canvas.drawCircle(Offset(r * 0.42, -r * 0.12), r * 0.17, ink);
      canvas.drawCircle(Offset(r * 0.47, -r * 0.18), r * 0.06, Paint()..color = Colors.white);
    }
    // Tongue, panting.
    final pant = sit > 0.5 ? math.sin(time * 9).abs() * 0.12 : 0.0;
    canvas.drawOval(Rect.fromCenter(center: Offset(r * 1.05, r * (0.82 + pant)), width: r * 0.32, height: r * (0.42 + pant)),
        Paint()..color = const Color(0xFFFF6F86));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PuppyPainter old) => true;
}
