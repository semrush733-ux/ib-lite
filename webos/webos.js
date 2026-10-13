// LG TV (webOS) glue for the Flutter web app.
// - Back on the remote goes one screen back; on the first screen the app asks "Exit?" itself and
//   then calls window.tizenExit() (same hook name as the Samsung build), which closes the app here.
// - Play / pause / stop and channel keys are passed on as the keys the app already knows.
(function () {
  window.tizenExit = function () {
    try { if (window.webOS && webOS.platformBack) { webOS.platformBack(); return; } } catch (e) {}
    try { window.close(); } catch (e) {}
  };
  function send(key, code, keyCode) {
    var t = document.activeElement || document.body;
    ['keydown', 'keyup'].forEach(function (type) {
      var ev = new KeyboardEvent(type, { key: key, code: code, bubbles: true, cancelable: true });
      try { Object.defineProperty(ev, 'keyCode', { get: function () { return keyCode; } }); } catch (e) {}
      t.dispatchEvent(ev);
    });
  }
  function stop(e) { e.preventDefault(); e.stopImmediatePropagation(); }
  document.addEventListener('keydown', function (e) {
    switch (e.keyCode) {
      case 461: stop(e); history.back(); break;                                  // Back
      case 415: case 19: case 413: send('MediaPlayPause', 'MediaPlayPause', 179); stop(e); break; // play / pause / stop
      case 427: send('PageUp', 'PageUp', 33); stop(e); break;                   // channel up
      case 428: send('PageDown', 'PageDown', 34); stop(e); break;               // channel down
    }
  }, true);
})();
