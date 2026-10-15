// LG TV (webOS) glue for the Flutter web app.
// - Back on the remote goes one screen back; on the first screen the app asks "Exit?" itself and
//   then calls window.tizenExit() (same hook name as the Samsung build), which closes the app here.
// - Play / pause / stop and channel keys are passed on as the keys the app already knows.
(function () {
  // ---- Start-up watch: shows on screen how far the app got, and any error, so a TV
  // that closes the app at once can tell us why (remove once LG TVs run fine).
  function box() {
    var d = document.getElementById('b1g-boot');
    if (!d && document.body) {
      d = document.createElement('div');
      d.id = 'b1g-boot';
      d.style.cssText = 'position:fixed;left:16px;top:16px;right:16px;z-index:99999;color:#fff;' +
        'font:16px/1.45 monospace;background:rgba(120,0,0,.92);padding:14px 18px;border-radius:10px;' +
        'white-space:pre-wrap;word-break:break-all;display:none;max-height:85%;overflow:hidden';
      document.body.appendChild(d);
    }
    return d;
  }
  var steps = [];
  function mark(t, show) {
    steps.push(t);
    try {
      var d = box();
      if (d && (show || d.style.display === 'block')) {
        d.style.display = 'block';
        d.textContent = 'Lite Player start log\n' + steps.join('\n');
      }
    } catch (e) {}
  }
  window.addEventListener('error', function (e) {
    var m = e.message || 'script error';
    if (e.filename) m += '\n  at ' + e.filename.split('/').pop() + ':' + e.lineno;
    if (e.error && e.error.stack) m += '\n' + String(e.error.stack).split('\n').slice(0, 4).join('\n');
    mark('ERROR: ' + m, true);
  }, true);
  window.addEventListener('unhandledrejection', function (e) {
    var r = e.reason || {};
    mark('ERROR (promise): ' + (r.message || r) + (r.stack ? '\n' + String(r.stack).split('\n').slice(0, 4).join('\n') : ''), true);
  });
  mark('webos.js loaded  ua=' + navigator.userAgent.slice(-60));
  document.addEventListener('DOMContentLoaded', function () { mark('page loaded'); });
  window.addEventListener('flutter-first-frame', function () {
    mark('app drawing');
    var d = document.getElementById('b1g-boot');
    // All fine: never show the log.
    if (d && d.textContent.indexOf('ERROR') === -1) d.remove();
  });
  var waited = 0;
  var t = setInterval(function () {
    waited += 2;
    if (window._flutter) mark('engine script present (' + waited + 's)');
    if (waited >= 8) {
      clearInterval(t);
      // Still no picture after 8 s: show the log so the reason can be read / photographed.
      var d = box();
      if (d) { d.style.display = 'block'; d.textContent = 'Lite Player start log\n' + steps.join('\n'); }
    }
  }, 2000);

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
