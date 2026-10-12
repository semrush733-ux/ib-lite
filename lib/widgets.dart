import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

bool _isSelectKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.select ||
    k == LogicalKeyboardKey.enter ||
    k == LogicalKeyboardKey.numpadEnter ||
    k == LogicalKeyboardKey.gameButtonA;

/// A card that can be reached with the remote (D-pad) and shows a clear
/// highlight while focused. OK opens it; holding OK (or the Menu button,
/// or a long press on a touch screen) calls [onLongPress].
class TvFocus extends StatefulWidget {
  const TvFocus({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.onFocus,
    this.autofocus = false,
    this.focusNode,
    this.radius = 10,
    this.color = C.card,
    this.selected = false,
    this.focusBorder = C.accent,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onFocus;
  final bool autofocus;
  final FocusNode? focusNode;
  final double radius;
  final Color color;
  final bool selected;
  final Color focusBorder;

  @override
  State<TvFocus> createState() => _TvFocusState();
}

class _TvFocusState extends State<TvFocus> {
  bool _focused = false;
  bool _down = false;
  bool _longFired = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.onLongPress == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.contextMenu) {
      if (event is KeyDownEvent) widget.onLongPress!();
      return KeyEventResult.handled;
    }
    if (!_isSelectKey(key)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _down = true;
      _longFired = false;
    } else if (event is KeyRepeatEvent) {
      if (_down && !_longFired) {
        _longFired = true;
        widget.onLongPress!();
      }
    } else if (event is KeyUpEvent) {
      final tap = _down && !_longFired;
      _down = false;
      _longFired = false;
      if (tap) widget.onTap();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.radius);
    final base = widget.color;
    // Focus is a soft red gradient with a glow; colours blend in instead of switching.
    final List<Color> colors = _focused
        ? [Color.alphaBlend(C.accent.withValues(alpha: 0.34), base), Color.alphaBlend(C.accent.withValues(alpha: 0.12), base)]
        : widget.selected
            ? [Color.alphaBlend(C.accent.withValues(alpha: 0.12), base), Color.alphaBlend(C.accent.withValues(alpha: 0.05), base)]
            : [base, base];
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          borderRadius: radius,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onFocusChange: (value) {
            if (_focused != value) setState(() => _focused = value);
            if (!value) {
              _down = false;
              _longFired = false;
            }
            if (value) widget.onFocus?.call();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
              borderRadius: radius,
              border: Border.all(
                color: _focused
                    ? widget.focusBorder
                    : (widget.selected ? C.accent.withValues(alpha: 0.45) : Colors.transparent),
                width: 2.5,
              ),
              boxShadow: _focused
                  ? [BoxShadow(color: widget.focusBorder.withValues(alpha: 0.32), blurRadius: 16, spreadRadius: 0.5)]
                  : const [BoxShadow(color: Colors.transparent, blurRadius: 16)],
            ),
            child: Stack(
              // The child keeps the full size given to the button (tiles fill their box).
              fit: StackFit.passthrough,
              children: [
                widget.child,
                if (_focused)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipRRect(borderRadius: radius, child: const Sheen()),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A faint band of light that slowly sweeps across the focused item.
class Sheen extends StatefulWidget {
  const Sheen({super.key});

  @override
  State<Sheen> createState() => _SheenState();
}

class _SheenState extends State<Sheen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final x = -2.0 + 4.0 * Curves.easeInOut.transform(_c.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(x - 1, -1),
              end: Alignment(x + 1, 1),
              colors: const [Color(0x00FFFFFF), Color(0x1AFFFFFF), Color(0x00FFFFFF)],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

/// Text field made for a TV remote (and fine with touch).
///
/// It is a normal focusable row until OK is pressed (or it is tapped): only then
/// the keyboard opens. So moving over the form with the remote never pops the
/// keyboard up, and OK on a field always brings the keyboard back.
/// While typing: Next / Done on the keyboard confirms, Up / Down or Back leaves the field.
class TvField extends StatefulWidget {
  const TvField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.focusNode,
    this.obscure = false,
    this.autofocus = false,
    this.action = TextInputAction.next,
    this.keyboardType,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;

  /// Focus of the row (not of the keyboard cursor).
  final FocusNode? focusNode;
  final bool obscure;

  /// Start typing straight away (used where the field is the only thing on screen).
  final bool autofocus;
  final TextInputAction action;
  final TextInputType? keyboardType;

  /// Called when the keyboard's Next / Done / Search key is pressed. The handler decides where
  /// the focus goes next; without a handler the focus returns to this row.
  final ValueChanged<String>? onSubmitted;

  @override
  State<TvField> createState() => TvFieldState();
}

class TvFieldState extends State<TvField> {
  final FocusNode _editNode = FocusNode(debugLabel: 'field-edit');
  FocusNode? _ownRowNode;
  bool _editing = false;
  bool _hadFocus = false;

  FocusNode get _rowNode => widget.focusNode ?? (_ownRowNode ??= FocusNode(debugLabel: 'field-row'));

  @override
  void initState() {
    super.initState();
    _editNode.addListener(_onEditFocus);
    widget.controller.addListener(_onText);
    if (widget.autofocus) {
      _editing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _editing) _editNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _editNode.removeListener(_onEditFocus);
    _editNode.dispose();
    _ownRowNode?.dispose();
    super.dispose();
  }

  void _onText() {
    if (mounted && !_editing) setState(() {});
  }

  void _onEditFocus() {
    if (_editNode.hasFocus) {
      _hadFocus = true;
    } else if (_editing && _hadFocus) {
      // Focus went somewhere else (another field was tapped, a dialog opened...).
      _leave(backToRow: false);
    }
  }

  /// Opens the keyboard on this field.
  void edit() {
    if (_editing) {
      _showKeyboard();
      return;
    }
    _hadFocus = false;
    if (mounted) setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _editNode.requestFocus();
    });
  }

  void _showKeyboard() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  void _leave({required bool backToRow}) {
    if (!_editing || !mounted) return;
    setState(() => _editing = false);
    if (backToRow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_editing) _rowNode.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _editing ? _editor() : _row();
  }

  Widget _row() {
    final text = widget.controller.text;
    final empty = text.isEmpty;
    final shown = empty ? 'Press OK to type' : (widget.obscure ? '•' * text.length : text);
    return TvFocus(
      focusNode: _rowNode,
      onTap: edit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(widget.icon, color: C.dim, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.label, style: const TextStyle(fontSize: 11.5, color: C.dim)),
                  const SizedBox(height: 1),
                  Text(
                    shown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, color: empty ? const Color(0xFF596070) : C.text),
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_rounded, color: Color(0xFF596070), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _editor() {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 2.5),
        );
    return PopScope(
      // Back first closes the keyboard (Android does that), then leaves the field, then the screen.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave(backToRow: true);
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _leave(backToRow: true),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _leave(backToRow: true),
          const SingleActivator(LogicalKeyboardKey.select): _showKeyboard,
        },
        child: TextField(
          controller: widget.controller,
          focusNode: _editNode,
          obscureText: widget.obscure,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: widget.keyboardType,
          textInputAction: widget.action,
          onSubmitted: (value) {
            final handler = widget.onSubmitted;
            _leave(backToRow: handler == null);
            handler?.call(value);
          },
          style: const TextStyle(fontSize: 16, color: C.text),
          cursorColor: C.accent,
          decoration: InputDecoration(
            labelText: widget.label,
            labelStyle: const TextStyle(color: C.dim),
            floatingLabelStyle: const TextStyle(color: C.accent),
            prefixIcon: Icon(widget.icon, color: C.accent, size: 20),
            filled: true,
            fillColor: C.card,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: border(C.accent),
            focusedBorder: border(C.accent),
          ),
        ),
      ),
    );
  }
}

/// Time and date, as on a TV home screen.
class Clock extends StatefulWidget {
  const Clock({super.key});

  @override
  State<Clock> createState() => _ClockState();
}

class _ClockState extends State<Clock> {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${two(t.hour)}:${two(t.minute)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        Text('${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]} ${t.year}',
            style: const TextStyle(fontSize: 12.5, color: C.dim)),
      ],
    );
  }
}

/// Network picture with a quiet placeholder when it is missing or broken.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.contain, this.cacheWidth = 160, this.fallback = Icons.tv});

  final String url;
  final BoxFit fit;
  final int cacheWidth;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final placeholder = Center(child: Icon(fallback, color: C.dim.withValues(alpha: 0.5), size: 22));
    if (!url.startsWith('http')) return placeholder;
    return Image.network(
      url,
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, __, ___) => placeholder,
      frameBuilder: (_, child, frame, sync) => frame == null && !sync ? placeholder : child,
    );
  }
}

class Loading extends StatefulWidget {
  const Loading({super.key, this.label, this.expected = const Duration(milliseconds: 2500)});
  final String? label;

  /// Kept for callers; the dots do not show progress.
  final Duration expected;

  @override
  State<Loading> createState() => _LoadingState();
}

/// Three dots in a row that hop up and down one after another while something loads.
class _LoadingState extends State<Loading> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 76,
            height: 44,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [for (var i = 0; i < 3; i++) _dot(i)],
              ),
            ),
          ),
          if (widget.label != null) ...[
            const SizedBox(height: 10),
            Text(widget.label!,
                style: const TextStyle(color: C.dim, fontSize: 14, shadows: [Shadow(color: Colors.black, blurRadius: 6)])),
          ],
        ],
      ),
    );
  }

  Widget _dot(int i) {
    // Each dot starts a little later than the one before it.
    final t = (_c.value - i * 0.16) % 1.0;
    final up = t < 0.5 ? math.sin(t * 2 * math.pi) : 0.0;
    final lift = up < 0 ? 0.0 : up;
    return Transform.translate(
      offset: Offset(0, 8 - 16 * lift),
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: Color.lerp(const Color(0xFFFF8A90), C.accent, 1 - lift),
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 6)],
        ),
      ),
    );
  }
}

/// Message with a "Try again" button, used when a list cannot be loaded.
class ErrorBox extends StatelessWidget {
  const ErrorBox({super.key, required this.message, required this.onRetry, this.autofocus = false});
  final String message;
  final VoidCallback onRetry;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: C.dim, size: 34),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: C.text, fontSize: 15)),
          ),
          const SizedBox(height: 16),
          TvFocus(
            autofocus: autofocus,
            onTap: onRetry,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              child: Text('Try again', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps the first screen of the app: Back asks "Exit?" before the app closes.
class ExitGuard extends StatelessWidget {
  const ExitGuard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await confirmExit(context)) await SystemNavigator.pop();
      },
      child: child,
    );
  }
}

Future<bool> confirmExit(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (ctx) => AlertDialog(
      backgroundColor: C.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Row(
        children: [
          Icon(Icons.power_settings_new_rounded, color: C.accent, size: 28),
          SizedBox(width: 12),
          Text('Exit the app?', style: TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
      content: const Text('Do you really want to close the app?', style: TextStyle(color: C.dim, fontSize: 16)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        _DialogButton(label: 'Stay', autofocus: true, onTap: () => Navigator.of(ctx).pop(false)),
        _DialogButton(label: 'Exit', danger: true, onTap: () => Navigator.of(ctx).pop(true)),
      ],
    ),
  );
  return ok == true;
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({required this.label, required this.onTap, this.autofocus = false, this.danger = false});
  final String label;
  final VoidCallback onTap;
  final bool autofocus;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      autofocus: autofocus,
      radius: 12,
      color: danger ? const Color(0xFF3A1216) : C.card,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
        child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
    );
  }
}
