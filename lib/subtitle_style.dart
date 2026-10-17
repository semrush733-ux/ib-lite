import 'package:flutter/material.dart';

import 'store.dart';

/// How subtitles look (Settings › Subtitles): size, colour, background and height on the
/// screen. The same look on both players (ExoPlayer and MPV).
class SubtitleLook {
  SubtitleLook._();

  static const sizeNames = ['Small', 'Medium', 'Large', 'Extra large'];
  static const colorNames = ['White', 'Yellow', 'Cyan', 'Green'];
  static const backgroundNames = ['Shadow', 'Dark box', 'Outline'];
  static const positionNames = ['Bottom', 'Higher'];

  // Letter height as a share of the picture's height. Medium is the size the app always had.
  static const _sizes = [0.042, 0.055, 0.068, 0.084];
  static const _colors = [Color(0xFFFFFFFF), Color(0xFFFFE14D), Color(0xFF5CE1FF), Color(0xFF7CFC6C)];

  /// Changes for the players and the preview in Settings.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static void changed() => changes.value++;

  /// Font size in logical pixels for a picture area [height] high.
  static double fontSize(double height) => (height * _sizes[Store.subSize]).clamp(12.0, 120.0).toDouble();

  /// Extra room under the subtitles ("Higher").
  static double lift(double height) => Store.subPosition == 1 ? height * 0.08 : 0;

  static TextStyle style(double height) {
    final size = fontSize(height);
    final color = _colors[Store.subColor];
    switch (Store.subBackground) {
      case 1:
        return TextStyle(
          color: color,
          fontSize: size,
          height: 1.3,
          fontWeight: FontWeight.w500,
          backgroundColor: const Color(0xB3000000),
        );
      case 2:
        final o = (size / 18).clamp(1.0, 3.0).toDouble();
        return TextStyle(
          color: color,
          fontSize: size,
          height: 1.25,
          fontWeight: FontWeight.w600,
          shadows: [
            for (final d in [Offset(-o, -o), Offset(o, -o), Offset(-o, o), Offset(o, o), Offset(0, o), Offset(0, -o), Offset(o, 0), Offset(-o, 0)])
              Shadow(offset: d, color: Colors.black),
          ],
        );
      default:
        return TextStyle(
          color: color,
          fontSize: size,
          height: 1.25,
          shadows: const [Shadow(blurRadius: 6, color: Colors.black), Shadow(blurRadius: 2, color: Colors.black)],
        );
    }
  }
}

/// A sample line over a dark picture, drawn with the chosen look (Settings and the player).
class SubtitlePreview extends StatelessWidget {
  const SubtitlePreview({super.key, this.height = 170});
  final double height;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SubtitleLook.changes,
      builder: (context, _, __) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: height,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF3B4A5E), Color(0xFF1C2330), Color(0xFF443226)],
            ),
          ),
          alignment: Alignment.bottomCenter,
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + SubtitleLook.lift(height)),
          // A little larger than on the real picture, so the sample is easy to read.
          child: Text(
            'This is how subtitles will look.',
            textAlign: TextAlign.center,
            style: SubtitleLook.style(height * 1.6),
          ),
        ),
      ),
    );
  }
}
