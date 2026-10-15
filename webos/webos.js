// LG TV (webOS) glue for the Flutter web app.
// - Back on the remote goes one screen back; on the first screen the app asks "Exit?" itself and
//   then calls window.tizenExit() (same hook name as the Samsung build), which closes the app here.
// - Play / pause / stop and channel keys are passed on as the keys the app already knows.
// - Flight recorder: every start-up step (and every file the engine loads) is written to
//   localStorage at once, so it survives a crash. When the previous run died before the first
//   picture, the next start shows that log in a red box and waits for OK before trying again.
(function () {
  var KEY = 'b1g_bootlog';
  var steps = [];
  var boxShown = false;

  function save() {
    try { localStorage.setItem(KEY, JSON.stringify(steps)); } catch (e) {}
  }

  function box() {
    var d = document.getElementById('b1g-boot');
    if (!d && document.body) {
      d = document.createElement('div');
      d.id = 'b1g-boot';
      d.style.cssText = 'position:fixed;left:16px;top:16px;right:16px;z-index:99999;color:#fff;' +
        'font:17px/1.5 monospace;background:rgba(110,0,0,.93);padding:14px 18px;border-radius:10px;' +
        'white-space:pre-wrap;word-break:break-all;max-height:88%;overflow:hidden';
      document.body.appendChild(d);
    }
    return d;
  }

  var prev = null;
  try { prev = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) {}
  var crashedBefore = prev && prev.length && prev.join(' ').indexOf('app drawing') === -1;

  function render() {
    var d = box();
    if (!d) return;
    var t = '';
    if (crashedBefore) {
      t += 'LAST RUN (died at the bottom line):\n' + prev.join('\n') + '\n\n';
      t += boot.done ? 'THIS RUN:\n' : 'Press OK on the remote to try loading again.\n';
    }
    t += steps.join('\n');
    d.textContent = t;
  }

  function mark(t) {
    steps.push(t);
    save();
    if (boxShown) { try { render(); } catch (e) {} }
  }

  function showBox() {
    boxShown = true;
    try { render(); } catch (e) {}
  }

  // ---- errors always surface
  window.addEventListener('error', function (e) {
    var m = e.message || 'script error';
    if (e.filename) m += ' @' + String(e.filename).split('/').pop() + ':' + e.lineno;
    if (e.error && e.error.stack) m += '\n' + String(e.error.stack).split('\n').slice(0, 4).join('\n');
    mark('ERROR: ' + m);
    showBox();
  }, true);
  window.addEventListener('unhandledrejection', function (e) {
    var r = e.reason || {};
    mark('ERROR(promise): ' + (r.message || r));
    showBox();
  });

  // ---- breadcrumbs: every file the engine asks for (the last line = where it died)
  if (window.fetch) {
    var f0 = window.fetch;
    window.fetch = function (u, o) {
      try { mark('fetch ' + String((u && u.url) || u).split('?')[0].split('/').slice(-2).join('/')); } catch (e) {}
      return f0.apply(this, arguments);
    };
  }
  var xo = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (m, u) {
    try { mark('xhr ' + String(u).split('?')[0].split('/').slice(-2).join('/')); } catch (e) {}
    return xo.apply(this, arguments);
  };
  if (window.WebAssembly && WebAssembly.instantiateStreaming) {
    var wi = WebAssembly.instantiateStreaming;
    WebAssembly.instantiateStreaming = function () {
      mark('wasm instantiate (streaming)');
      return wi.apply(this, arguments);
    };
  }

  // Belt and braces: no code path may touch service workers (they crash LG's WebAppManager).
  try { delete Navigator.prototype.serviceWorker; } catch (e) {}
  try { delete window.caches; } catch (e) {}

  // The app paints at 2/3 scale (1280x720 on a 1080p window) and the TV scales it up:
  // LG's web engine paints in software and full 1080p stuttered. The window itself stays
  // 1920x1080 (a 720p appinfo resolution made the first frame crash on webOS 24).
  try {
    Object.defineProperty(window, 'devicePixelRatio', { get: function () { return 2 / 3; } });
  } catch (e) {}

  mark('start ' + new Date().toISOString().slice(11, 19) + ' ' + navigator.userAgent.slice(-45));

  // Every script the engine loader adds, and whether it finished.
  try {
    new MutationObserver(function (muts) {
      muts.forEach(function (m) {
        Array.prototype.forEach.call(m.addedNodes, function (n) {
          if (!n || n.tagName !== 'SCRIPT' || !n.src) return;
          var f = String(n.src).split('?')[0].split('/').pop();
          mark('script+ ' + f);
          n.addEventListener('load', function () { mark('script ok ' + f); });
          n.addEventListener('error', function () { mark('script FAILED ' + f); showBox(); });
        });
      });
    }).observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) {}

  // Heartbeat: the last t+N before silence = the second it died in.
  var hb = 0;
  var hbT = setInterval(function () {
    hb++;
    if (hb > 25) { clearInterval(hbT); return; }
    mark('t+' + hb + 's');
  }, 1000);
  window.addEventListener('flutter-first-frame', function () { clearInterval(hbT); });

  // ---- boot gate: after a crash the app waits for OK, so the log can be read
  var boot = function () {
    boot.done = true;
    mark('boot: loading the engine');
    if (window.__b1gBoot) window.__b1gBoot();
  };
  boot.done = false;

  document.addEventListener('DOMContentLoaded', function () {
    mark('page ready');
    if (crashedBefore) {
      showBox();
      // Wait for any remote key before loading the heavy part.
      var go = function (e) {
        if (boot.done) return;
        document.removeEventListener('keydown', go, true);
        boot();
      };
      document.addEventListener('keydown', go, true);
    } else {
      boot();
    }
  });

  window.addEventListener('flutter-first-frame', function () {
    mark('app drawing');
    try { localStorage.removeItem(KEY); } catch (e) {}
    var d = document.getElementById('b1g-boot');
    if (d && !crashedBefore) d.remove();
  });


  // ---- HLS tuned for TV zapping: small start buffer, short timeouts, capped memory.
  // media_kit's loader creates window.Hls and then "new Hls(config)": the constructor is
  // wrapped once so every player gets these settings.
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
  // Some LG remotes send the old names ('Left') or no name at all for the arrows; the app
  // only understands 'ArrowLeft' and friends, so those presses are sent again properly.
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
