import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Samsung TV (Tizen): index.html defines window.tizenExit(), which closes the app.
void tizenExit() {
  try {
    if (globalContext.has('tizenExit')) globalContext.callMethod('tizenExit'.toJS);
  } catch (_) {}
}
