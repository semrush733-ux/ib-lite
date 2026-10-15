// Samsung TV (Tizen) glue for the Flutter web app.
// - Back on the remote goes one screen back (like Android TV); on the first screen the app asks
//   "Exit?" itself and then calls window.tizenExit().
// - Exit on the remote closes the app.
// - Play / pause / stop keys are passed on as the keys the app already knows.
(function () {
  function tz() { return (typeof tizen !== 'undefined') ? tizen : null; }

  // ---- HLS tuned for TV zapping: small start buffer, short timeouts, capped memory.
  var hlsTimer = setInterval(function () {
    var H = window.Hls;
    if (!H || H.__b1g) return;
    try {
      var W = function (cfg) {
        var merged = Object.assign({}, cfg || {}, {
          maxBufferLength: 12,
          maxMaxBufferLength: 30,
          backBufferLength: 10,
          manifestLoadingTimeOut: 8000,
          manifestLoadingMaxRetry: 2,
          levelLoadingTimeOut: 8000,
          fragLoadingTimeOut: 12000,
        });
        return new H(merged);
      };
      W.__b1g = true;
      Object.setPrototypeOf(W, H);
      W.prototype = H.prototype;
      window.Hls = W;
      clearInterval(hlsTimer);
    } catch (e) {
      clearInterval(hlsTimer);
    }
  }, 300);
  setTimeout(function () { clearInterval(hlsTimer); }, 60000);

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
  // Some TV remotes send the old names ('Left') or no name for the arrows; the app only
  // understands 'ArrowLeft' and friends, so those presses are sent again properly.
  var arrows = { Left: 'ArrowLeft', Right: 'ArrowRight', Up: 'ArrowUp', Down: 'ArrowDown' };
  var byCode = { 37: 'ArrowLeft', 38: 'ArrowUp', 39: 'ArrowRight', 40: 'ArrowDown' };
  document.addEventListener('keydown', function (e) {
    var fix = arrows[e.key] || (byCode[e.keyCode] && (!e.key || e.key.indexOf('Arrow') !== 0) ? byCode[e.keyCode] : null);
    if (fix) { e.preventDefault(); e.stopImmediatePropagation(); send(fix, fix, e.keyCode); }
  }, true);
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
