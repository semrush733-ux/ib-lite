// Samsung TV (Tizen) glue for the Flutter web app.
// - Back on the remote goes one screen back (like Android TV); on the first screen the app asks
//   "Exit?" itself and then calls window.tizenExit().
// - Exit on the remote closes the app.
// - Play / pause / stop keys are passed on as the keys the app already knows.
(function () {
  function tz() { return (typeof tizen !== 'undefined') ? tizen : null; }
  window.tizenExit = function () {
    try { tz().application.getCurrentApplication().exit(); } catch (e) {}
  };
  try {
    var keys = ['MediaPlayPause', 'MediaPlay', 'MediaPause', 'MediaStop', 'MediaFastForward', 'MediaRewind', 'ChannelUp', 'ChannelDown'];
    keys.forEach(function (k) { try { tz().tvinputdevice.registerKey(k); } catch (e) {} });
  } catch (e) {}
  function send(key, code, keyCode) {
    var t = document.activeElement || document.body;
    ['keydown', 'keyup'].forEach(function (type) {
      var ev = new KeyboardEvent(type, { key: key, code: code, bubbles: true, cancelable: true });
      try { Object.defineProperty(ev, 'keyCode', { get: function () { return keyCode; } }); } catch (e) {}
      t.dispatchEvent(ev);
    });
  }
  document.addEventListener('keydown', function (e) {
    switch (e.keyCode) {
      case 10009: // Back
        e.preventDefault();
        e.stopImmediatePropagation();
        history.back();
        break;
      case 10182: // Exit
        window.tizenExit();
        break;
      case 10252: send('MediaPlayPause', 'MediaPlayPause', 179); e.preventDefault(); e.stopImmediatePropagation(); break;
      case 415: send('MediaPlayPause', 'MediaPlayPause', 179); e.preventDefault(); e.stopImmediatePropagation(); break;
      case 19: send('MediaPlayPause', 'MediaPlayPause', 179); e.preventDefault(); e.stopImmediatePropagation(); break;
      case 427: send('PageUp', 'PageUp', 33); e.preventDefault(); e.stopImmediatePropagation(); break;   // channel up
      case 428: send('PageDown', 'PageDown', 34); e.preventDefault(); e.stopImmediatePropagation(); break; // channel down
    }
  }, true);
})();
