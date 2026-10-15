import 'package:flutter/material.dart';

import 'downloads.dart';
import 'theme.dart';

/// The download progress under a film: a slim glowing bar, 0–100 %, and small, steady numbers
/// (speed · size · time left). Numbers use fixed-width digits so they never jiggle.
class DownloadProgress extends StatelessWidget {
  const DownloadProgress({super.key, required this.id, this.width = 460});

  final String id;
  final double width;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Downloads.i,
      builder: (context, _) {
        final d = Downloads.i.byId(id);
        if (d == null) return const SizedBox.shrink();
        return SizedBox(width: width, child: DownloadLine(d: d));
      },
    );
  }
}

class DownloadLine extends StatelessWidget {
  const DownloadLine({super.key, required this.d, this.compact = false});

  final DlItem d;
  final bool compact;

  static const _num = TextStyle(
    fontSize: 11.5,
    color: Color(0xFFB9BFCC),
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.2,
  );

  String get _status => switch (d.state) {
        DlState.running => 'Downloading',
        DlState.queued => 'In line',
        DlState.waiting => 'Paused while a video plays',
        DlState.paused => 'Paused',
        DlState.failed => d.error.isNotEmpty ? d.error : 'Stopped',
        DlState.done => 'Downloaded',
      };

  @override
  Widget build(BuildContext context) {
    final running = d.state == DlState.running;
    final done = d.done;
    final color = d.state == DlState.failed ? const Color(0xFFFF6B6B) : (done ? const Color(0xFF4CD07D) : C.accent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              done
                  ? Icons.check_circle_rounded
                  : (running ? Icons.downloading_rounded : (d.state == DlState.failed ? Icons.error_outline_rounded : Icons.pause_circle_outline_rounded)),
              size: 15,
              color: color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(_status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFE4E7EE))),
            ),
            Text('${d.percent}%',
                style: _num.copyWith(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
          ],
        ),
        const SizedBox(height: 7),
        _Bar(value: done ? 1 : d.fraction, active: running, color: color),
        if (!done) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Text(running && d.speed > 0 ? fmtSpeed(d.speed) : '—', style: _num.copyWith(color: running ? Colors.white : null)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  d.total > 0 ? '${fmtBytes(d.got)} / ${fmtBytes(d.total)}' : fmtBytes(d.got),
                  style: _num,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                ),
              ),
              Text(running ? fmtLeft(d.secondsLeft) : '', style: _num),
            ],
          ),
        ] else if (!compact) ...[
          const SizedBox(height: 6),
          Text('${fmtBytes(d.total)} · plays without internet', style: _num),
        ],
      ],
    );
  }
}

/// Slim rounded bar: dark track, red gradient fill with a soft glow, and a light sheen that
/// glides along while downloading. Moves smoothly between updates.
class _Bar extends StatefulWidget {
  const _Bar({required this.value, required this.active, required this.color});

  final double value;
  final bool active;
  final Color color;

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.active) _sheen.repeat();
  }

  @override
  void didUpdateWidget(covariant _Bar old) {
    super.didUpdateWidget(old);
    if (widget.active && !_sheen.isAnimating) _sheen.repeat();
    if (!widget.active && _sheen.isAnimating) _sheen.stop();
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: 6,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: widget.value),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          builder: (context, v, _) => CustomPaint(
            painter: _BarPainter(v, _sheen, widget.color, widget.active),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.v, this.sheen, this.color, this.active) : super(repaint: sheen);
  final double v;
  final Animation<double> sheen;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final track = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.drawRRect(track, Paint()..color = const Color(0x24FFFFFF));
    final w = size.width * v.clamp(0.0, 1.0);
    if (w <= 0) return;
    final fill = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), r);
    // Glow
    canvas.drawRRect(
      fill,
      Paint()
        ..color = color.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    // Fill
    canvas.drawRRect(
      fill,
      Paint()
        ..shader = LinearGradient(
          colors: [Color.lerp(color, Colors.black, 0.15)!, Color.lerp(color, Colors.white, 0.25)!],
        ).createShader(Rect.fromLTWH(0, 0, w, size.height)),
    );
    // Sheen gliding along the filled part
    if (active) {
      final x = -60 + (w + 120) * sheen.value;
      canvas.save();
      canvas.clipRRect(fill);
      canvas.drawRect(
        Rect.fromLTWH(x - 40, 0, 80, size.height),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0x00FFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
          ).createShader(Rect.fromLTWH(x - 40, 0, 80, size.height)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.v != v || old.color != color || old.active != active;
}
