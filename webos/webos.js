// LG TV (webOS) glue for the Flutter web app.
// - Back on the remote goes one screen back; on the first screen the app asks "Exit?" itself and
//   then calls window.tizenExit() (same hook name as the Samsung build), which closes the app here.
// - Play / pause / stop and channel keys are passed on as the keys the app already knows.
// - Arrows sent with old names ('Left') are resent as 'ArrowLeft' etc.
// - Silent flight recorder: start-up steps, every request with its HTTP status / error, and any
//   script error go to localStorage (survives a crash). Nothing is ever shown to viewers.
//   Developers: press the RED button 5 times quickly to show / hide the log on screen.
(function () {
  var KEY = 'b1g_bootlog';
  var PREV = 'b1g_bootlog_prev';
  var MAX = 160;
  var steps = [];
  var t0 = Date.now();

  // The previous run's log is kept (when it never reached the first picture it is the crash log).
  try {
    var last = localStorage.getItem(KEY);
    if (last) localStorage.setItem(PREV, last);
  } catch (e) {}

  function save() {
    try { localStorage.setItem(KEY, JSON.stringify(steps)); } catch (e) {}
  }

  function mark(t) {
    steps.push('+' + ((Date.now() - t0) / 1000).toFixed(1) + 's ' + t);
    if (steps.length > MAX) steps.splice(0, steps.length - MAX);
    save();
    if (panel) render();
  }

  // ---- developer panel (hidden; RED x5 toggles it). Never takes focus or input.
  var panel = null;
  function render() {
    var prev = '';
    try {
      var p = JSON.parse(localStorage.getItem(PREV) || 'null');
      if (p && p.length) prev = 'PREVIOUS RUN:\n' + p.slice(-25).join('\n') + '\n\n';
    } catch (e) {}
    panel.textContent = prev + 'THIS RUN:\n' + steps.slice(-45).join('\n');
  }
  function togglePanel() {
    if (panel) { panel.remove(); panel = null; return; }
    panel = document.createElement('div');
    panel.style.cssText = 'position:fixed;left:12px;top:12px;width:46%;max-height:94%;overflow:hidden;' +
      'z-index:99999;pointer-events:none;color:#fff;font:13px/1.35 monospace;' +
      'background:rgba(0,0,0,.82);padding:10px 12px;border-radius:8px;white-space:pre-wrap;word-break:break-all';
    panel.setAttribute('aria-hidden', 'true');
    document.body.appendChild(panel);
    render();
  }
  var reds = [];
  document.addEventListener('keydown', function (e) {
    if (e.keyCode !== 403) return; // RED colour key
    var now = Date.now();
    reds = reds.filter(function (t) { return now - t < 2500; });
    reds.push(now);
    if (reds.length >= 5) { reds = []; togglePanel(); }
  }, true);

  // ---- errors are recorded (not shown)
  window.addEventListener('error', function (e) {
    var m = e.message || 'script error';
    if (e.filename) m += ' @' + String(e.filename).split('/').pop() + ':' + e.lineno;
    if (e.error && e.error.stack) m += ' | ' + String(e.error.stack).split('\n').slice(0, 3).join(' | ');
    if (e.target && e.target !== window && (e.target.src || e.target.href)) {
      m = 'resource failed: ' + (e.target.src || e.target.href);
    }
    mark('ERROR ' + m);
  }, true);
  window.addEventListener('unhandledrejection', function (e) {
    var r = e.reason || {};
    mark('ERROR(promise) ' + (r.message || r) + (r.stack ? ' | ' + String(r.stack).split('\n').slice(0, 2).join(' | ') : ''));
  });

  // ---- every request with its result (status and time, or the error)
  function short(u) {
    try {
      var s = String((u && u.url) || u).split('?')[0];
      return s.split('/').slice(-2).join('/');
    } catch (e) { return '?'; }
  }
  if (window.fetch) {
    var f0 = window.fetch;
    window.fetch = function (u) {
      var name = short(u);
      var started = Date.now();
      var p = f0.apply(this, arguments);
      try {
        p.then(function (r) {
          mark('fetch ' + name + ' -> ' + r.status + ' (' + (Date.now() - started) + 'ms)');
        }, function (err) {
          mark('fetch ' + name + ' -> FAILED ' + ((err && err.message) || err) + ' (' + (Date.now() - started) + 'ms)');
        });
      } catch (e) {}
      return p;
    };
  }
  var xo = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (m, u) {
    var name = short(u);
    var x = this;
    var started = Date.now();
    try {
      x.addEventListener('loadend', function () {
        mark('xhr ' + name + ' -> ' + (x.status || 'FAILED') + ' (' + (Date.now() - started) + 'ms)');
      });
    } catch (e) {}
    return xo.apply(this, arguments);
  };

  // No code path may touch service workers (registering one crashes LG's WebAppManager).
  try { delete Navigator.prototype.serviceWorker; } catch (e) {}
  try { delete window.caches; } catch (e) {}

  // The app paints at 2/3 scale (1280x720 on the 1080p window) and the TV scales it up:
  // LG's web engine paints in software and full 1080p stuttered. The window stays 1920x1080
  // (a 720p appinfo resolution made the first frame crash).
  try {
    Object.defineProperty(window, 'devicePixelRatio', { get: function () { return 2 / 3; } });
  } catch (e) {}

  mark('start ' + navigator.userAgent.slice(-45));

  // ---- start the engine at once (index.html leaves the start to this file)
  document.addEventListener('DOMContentLoaded', function () {
    mark('page ready, loading the engine');
    if (window.__b1gBoot) window.__b1gBoot();
  });
  window.addEventListener('flutter-first-frame', function () { mark('app drawing'); });

  // ---- HLS tuned for TV zapping: small start buffer, short timeouts, capped memory.
  // media_kit creates window.Hls and then "new Hls(config)": the constructor is wrapped once
  // so every player gets these settings.
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
      Object.setPrototypeOf(W, H);   // statics: isSupported, Events, ...
      W.prototype = H.prototype;
      window.Hls = W;
      mark('hls tuned');
      clearInterval(hlsTimer);
    } catch (e) {
      clearInterval(hlsTimer);
    }
  }, 300);
  setTimeout(function () { clearInterval(hlsTimer); }, 60000);

  // ---- remote keys / exit
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
  var arrows = { Left: 'ArrowLeft', Right: 'ArrowRight', Up: 'ArrowUp', Down: 'ArrowDown' };
  var byCode = { 37: 'ArrowLeft', 38: 'ArrowUp', 39: 'ArrowRight', 40: 'ArrowDown' };
  document.addEventListener('keydown', function (e) {
    var fix = arrows[e.key] || (byCode[e.keyCode] && (!e.key || e.key.indexOf('Arrow') !== 0) ? byCode[e.keyCode] : null);
    if (fix) { stop(e); send(fix, fix, e.keyCode); }
  }, true);
  document.addEventListener('keydown', function (e) {
    switch (e.keyCode) {
      case 461: stop(e); history.back(); break;                                  // Back
      case 415: case 19: case 413: send('MediaPlayPause', 'MediaPlayPause', 179); stop(e); break; // play / pause / stop
      case 427: send('PageUp', 'PageUp', 33); stop(e); break;                   // channel up
      case 428: send('PageDown', 'PageDown', 34); stop(e); break;               // channel down
    }
  }, true);
})();
