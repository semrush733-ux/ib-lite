import 'dart:math' as math;

import 'package:flutter/gestures.dart' show GestureBinding;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

/// A small puppy that roams the edges of the screen: it runs along the bottom, sits down, wags
/// its tail and blinks; sometimes it climbs up the left or right side, walks upside down along
/// the top, or dashes diagonally across the middle into a top corner. When the viewer presses a
/// key or touches the screen it stops and sits until things are quiet again, and it stands
/// still whenever another screen is opened on top. Purely decorative: put it under
/// IgnorePointer/ExcludeFocus.
class RunningPuppy extends StatefulWidget {
  const RunningPuppy({super.key, this.size = 64, this.roam = true});

  /// Width of the puppy in logical pixels.
  final double size;

  /// false: only along the bottom (the old behaviour).
  final bool roam;

  @override
  State<RunningPuppy> createState() => _RunningPuppyState();
}

enum _Mode { run, sit }

enum _Edge { bottom, right, top, left, air }

/// One stretch of the walk: to [to] (centre of the puppy), on [edge].
class _Leg {
  const _Leg(this.to, this.edge, {this.speed = 1});
  final Offset to;
  final _Edge edge;
  final double speed;
}

class _RunningPuppyState extends State<RunningPuppy> with SingleTickerProviderStateMixin {
  final _rnd = math.Random();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  // Ticks the painter directly: no widget is rebuilt per frame.
  final _frame = ValueNotifier<int>(0);

  Size _area = Size.zero;
  Offset _pos = Offset.zero; // centre of the puppy
  bool _placed = false;
  _Edge _edge = _Edge.bottom;
  Offset _dir = const Offset(1, 0); // last direction of travel
  final List<_Leg> _legs = [];
  _Mode _mode = _Mode.sit;
  double _modeTime = 0; // seconds in the current mode
  double _sitFor = 1.5;
  double _clock = 0; // drives legs, tail, blinking
  DateTime _quietFrom = DateTime.fromMillisecondsSinceEpoch(0); // viewer busy until then

  double get _w => widget.size;
  double get _h => widget.size * 0.78;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  // The viewer is doing something: the puppy sits still and watches for a while.
  void _busy() => _quietFrom = DateTime.now().add(const Duration(seconds: 8));

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent) _busy();
    return false; // never takes the key
  }

  void _onPointer(PointerEvent e) {
    if (e is PointerDownEvent) _busy();
  }

  // ---- places on the screen (centre of the puppy)
  double get _bottomY => _area.height - _h / 2 - 8;
  double get _topY => _h / 2 + 8;
  double get _leftX => _h / 2 + 8;
  double get _rightX => _area.width - _h / 2 - 8;
  double get _minX => _w / 2 + 12;
  double get _maxX => _area.width - _w / 2 - 12;
  double get _minY => _w / 2 + 12;
  double get _maxY => _area.height - _w / 2 - 12;

  double _between(double a, double b) => a + (b - a) * (0.15 + _rnd.nextDouble() * 0.7);

  /// Plans the next walk from where the puppy is.
  void _plan() {
    final r = _rnd.nextDouble();
    final x = _pos.dx, y = _pos.dy;
    final goRight = x < _area.width / 2;
    if (!widget.roam) {
      _legs.add(_Leg(Offset(r < 0.6 ? (goRight ? _maxX : _minX) : _between(_minX, _maxX), _bottomY), _Edge.bottom));
      return;
    }
    switch (_edge) {
      case _Edge.bottom:
        if (r < 0.40) {
          _legs.add(_Leg(Offset(r < 0.22 ? (goRight ? _maxX : _minX) : _between(_minX, _maxX), _bottomY), _Edge.bottom));
        } else if (r < 0.62) {
          // Up the left side, sometimes on along the top.
          _legs.add(_Leg(Offset(_minX, _bottomY), _Edge.bottom));
          _legs.add(_Leg(Offset(_leftX, _rnd.nextBool() ? _minY : _between(_minY, _maxY)), _Edge.left));
        } else if (r < 0.84) {
          _legs.add(_Leg(Offset(_maxX, _bottomY), _Edge.bottom));
          _legs.add(_Leg(Offset(_rightX, _rnd.nextBool() ? _minY : _between(_minY, _maxY)), _Edge.right));
        } else {
          // A dash right across the middle into a top corner, then on along the top.
          final toLeft = !goRight;
          _legs.add(_Leg(Offset(toLeft ? _minX : _maxX, _topY), _Edge.air, speed: 1.6));
          _legs.add(_Leg(Offset(_between(_minX, _maxX), _topY), _Edge.top));
        }
      case _Edge.left:
        if (r < 0.5 && y <= _minY + 2) {
          _legs.add(_Leg(Offset(_between(_minX, _maxX), _topY), _Edge.top));
        } else if (r < 0.75) {
          _legs.add(_Leg(Offset(_leftX, _minY), _Edge.left));
          _legs.add(_Leg(Offset(_between(_minX, _maxX), _topY), _Edge.top));
        } else {
          _legs.add(_Leg(Offset(_leftX, _maxY), _Edge.left));
          _legs.add(_Leg(Offset(_between(_minX, _maxX), _bottomY), _Edge.bottom));
        }
      case _Edge.right:
        if (r < 0.5 && y <= _minY + 2) {
          _legs.add(_Leg(Offset(_between(_minX, _maxX), _topY), _Edge.top));
        } else if (r < 0.75) {
          _legs.add(_Leg(Offset(_rightX, _minY), _Edge.right));
          _legs.add(_Leg(Offset(_between(_minX, _maxX), _topY), _Edge.top));
        } else {
          _legs.add(_Leg(Offset(_rightX, _maxY), _Edge.right));
          _legs.add(_Leg(Offset(_between(_minX, _maxX), _bottomY), _Edge.bottom));
        }
      case _Edge.top:
        if (r < 0.35) {
          _legs.add(_Leg(Offset(_between(_minX, _maxX), _topY), _Edge.top));
        } else if (r < 0.67) {
          _legs.add(_Leg(Offset(_minX, _topY), _Edge.top));
          _legs.add(_Leg(Offset(_leftX, _maxY), _Edge.left));
          _legs.add(_Leg(Offset(_between(_minX, _maxX), _bottomY), _Edge.bottom));
        } else {
          _legs.add(_Leg(Offset(_maxX, _topY), _Edge.top));
          _legs.add(_Leg(Offset(_rightX, _maxY), _Edge.right));
          _legs.add(_Leg(Offset(_between(_minX, _maxX), _bottomY), _Edge.bottom));
        }
      case _Edge.air:
        _legs.add(_Leg(Offset(_between(_minX, _maxX), _bottomY), _Edge.bottom));
    }
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05).toDouble();
    _last = now;
    if (_area.isEmpty) return;
    if (!_placed) {
      _placed = true;
      _pos = Offset(_minX, _bottomY);
    }
    _clock += dt;
    _modeTime += dt;
    final busy = DateTime.now().isBefore(_quietFrom);
    if (_mode == _Mode.run) {
      if (busy && _edge == _Edge.bottom) {
        // The viewer is busy: stop right here and sit.
        _legs.clear();
        _mode = _Mode.sit;
        _modeTime = 0;
        _sitFor = 2;
      } else if (_legs.isEmpty) {
        _mode = _Mode.sit;
        _modeTime = 0;
      } else {
        final leg = _legs.first;
        if (leg.edge != _edge) _edge = leg.edge; // round the corner onto the next side
        final speed = _area.width * 0.16 * leg.speed; // pixels per second
        final d = leg.to - _pos;
        final dist = d.distance;
        final step = speed * dt;
        if (dist <= step || dist < 0.5) {
          _pos = leg.to;
          _legs.removeAt(0);
          if (_legs.isEmpty) {
            _mode = _Mode.sit;
            _modeTime = 0;
            // Long rests on the floor, short pauses on the walls and the ceiling.
            _sitFor = _edge == _Edge.bottom ? 2.5 + _rnd.nextDouble() * 3 : 0.8 + _rnd.nextDouble() * 1.2;
          }
        } else {
          _dir = d / dist;
          _pos += _dir * step;
        }
      }
    } else if (_modeTime > _sitFor && !busy) {
      if (_legs.isEmpty) _plan();
      _mode = _Mode.run;
      _modeTime = 0;
    }
    _frame.value++;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      if (size != _area) {
        final old = _area;
        _area = size;
        if (!old.isEmpty) {
          // Screen size changed: back to the floor.
          _legs.clear();
          _edge = _Edge.bottom;
          _pos = Offset(_pos.dx.clamp(_minX, _maxX).toDouble(), _bottomY);
        }
      }
      // Its own layer: redrawing the puppy never redraws the rest of the screen.
      return RepaintBoundary(
        child: CustomPaint(size: size, painter: _ScreenPainter(this, _frame)),
      );
    });
  }
}

/// Draws the puppy where it is, turned to the side it walks on.
class _ScreenPainter extends CustomPainter {
  _ScreenPainter(this.s, Listenable repaint) : super(repaint: repaint);
  final _RunningPuppyState s;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = s._w, h = s._h;
    final running = s._mode == _Mode.run;
    final phase = s._clock * 2 * math.pi / 0.36;
    final bounce = running ? math.sin(phase * 2).abs() * 4 : 0.0;
    final sit = running ? 0.0 : (s._modeTime / 0.25).clamp(0.0, 1.0).toDouble();

    // Which way is "down" (the feet) and which way it faces.
    late Offset floor; // unit vector from the puppy to the surface under its feet
    switch (s._edge) {
      case _Edge.bottom:
        floor = const Offset(0, 1);
      case _Edge.top:
        floor = const Offset(0, -1);
      case _Edge.left:
        floor = const Offset(-1, 0);
      case _Edge.right:
        floor = const Offset(1, 0);
      case _Edge.air:
        floor = const Offset(0, 1);
    }
    var dir = s._dir;
    // Sitting / standing still: face along the surface, the way it last went.
    final along = Offset(-floor.dy, floor.dx);
    final dot = dir.dx * along.dx + dir.dy * along.dy;
    if (s._edge != _Edge.air || !running) dir = dot >= 0 ? along : -along;
    final angle = math.atan2(dir.dy, dir.dx);
    // Feet of the picture point to (-sin a, cos a) after turning; flip when that is the wrong side.
    final feet = Offset(-math.sin(angle), math.cos(angle));
    final flip = (feet.dx * floor.dx + feet.dy * floor.dy) < 0;

    // Soft shadow on the floor only.
    if (s._edge == _Edge.bottom) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(s._pos.dx, size.height - 9), width: w * 0.7, height: 6), const Radius.circular(6)),
        Paint()..color = Colors.black.withValues(alpha: 0.28 - bounce * 0.03),
      );
    }
    canvas.save();
    canvas.translate(s._pos.dx - floor.dx * bounce, s._pos.dy - floor.dy * bounce);
    canvas.rotate(angle);
    if (flip) canvas.scale(1, -1);
    canvas.translate(-w / 2, -h / 2);
    _PuppyPainter(phase: running ? phase : 0, sit: sit, time: s._clock, sitTime: running ? 0 : s._modeTime)
        .paint(canvas, Size(w, h));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScreenPainter old) => false;
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
