/* Core: small helpers, storage, web requests, the silent log, remote keys, focus and screens.
 * Plain ES5 so it also runs on older LG TVs. */
var U = {}, S = {}, Net = {}, Keys = {}, F = {}, Nav = {}, App = {};

(function () {
  'use strict';

  // ------------------------------------------------------------------ helpers
  U.$ = function (id) { return document.getElementById(id); };
  U.el = function (tag, cls, html) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (html != null) e.innerHTML = html;
    return e;
  };
  var ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  U.esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return ESC[c]; }); };
  U.str = function (v) { return v == null ? '' : String(v).replace(/^\s+|\s+$/g, ''); };
  U.int = function (v) { var n = parseInt(v, 10); return isNaN(n) ? 0 : n; };
  U.num = function (v) { var n = parseFloat(v); return isNaN(n) ? 0 : n; };
  U.two = function (n) { return n < 10 ? '0' + n : '' + n; };
  U.hm = function (d) { return U.two(d.getHours()) + ':' + U.two(d.getMinutes()); };
  U.months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  U.days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  U.time = function (sec) {
    sec = Math.max(0, Math.floor(sec || 0));
    var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    return (h > 0 ? h + ':' + U.two(m) : m) + ':' + U.two(s);
  };
  U.startsWith = function (s, p) { return String(s).substring(0, p.length) === p; };
  U.endsWith = function (s, p) { s = String(s); return s.length >= p.length && s.substring(s.length - p.length) === p; };
  U.extend = function (a, b) { for (var k in b) if (Object.prototype.hasOwnProperty.call(b, k)) a[k] = b[k]; return a; };
  U.closest = function (e, cls) {
    while (e && e.nodeType === 1) {
      if (e.classList && e.classList.contains(cls)) return e;
      e = e.parentNode;
    }
    return null;
  };
  /** base64 (as Xtream sends guide titles) to text; anything else comes back unchanged. */
  U.b64 = function (s) {
    s = U.str(s);
    if (!s) return '';
    try {
      var bin = atob(s.replace(/\s/g, ''));
      try { return decodeURIComponent(escape(bin)); } catch (e) { return bin; }
    } catch (e2) { return s; }
  };
  /** Letters and digits only, lower case (so "Spider-Man" is found with "spider man"). */
  U.norm = function (s) {
    var from = 'àáâãäåèéêëìíîïòóôõöùúûüçñ', to = 'aaaaaaeeeeiiiiooooouuuucn';
    s = String(s || '').toLowerCase();
    var out = '';
    for (var i = 0; i < s.length; i++) {
      var ch = s.charAt(i), k = from.indexOf(ch);
      if (k >= 0) ch = to.charAt(k);
      out += /[a-z0-9؀-ۿऀ-ॿЀ-ӿ]/.test(ch) ? ch : ' ';
    }
    return out.replace(/ +/g, ' ').replace(/^ | $/g, '');
  };

  var ICONS = {
    live: 'f860', movie: 'f1f3', series: 'f1f4', catchup: 'f00fc', replay: 'f00fc', settings: 'f0164', search: 'f013d', apps: 'f56d',
    star: 'f01d4', starb: 'f01cf', starh: 'f01d0', history: 'f7ef', lock: 'f889', back: 'f572', play: 'f00a0',
    pause: 'f0056', full: 'f7a6', guide: 'f5ff', fav: 'f738', favb: 'f737', next: 'f0192', prev: 'f0193',
    ff: 'f734', rw: 'f735', audio: 'f593', cc: 'f64a', info: 'f816', check: 'f636', close: 'f647', refresh: 'f00e9',
    wifioff: 'f02bd', error: 'f712', loc: 'f884', sun: 'f02ae', moon: 'e42f', lang: 'f83f', logout: 'f88b',
    del: 'f696', key: 'f0343', vpn: 'f029c', update: 'f020c', list: 'f85e', playlist: 'f00a9', sync: 'f0207',
    speed: 'f01b5', tv: 'f025d', person: 'f0071', account: 'f522', hourglass: 'f800', video: 'f027a',
    aspect: 'f581', hq: 'f7e9', undo: 'f0261', keyboard: 'f833', radioOn: 'f00d7', radioOff: 'f00d8',
    power: 'f00b8', shield: 'f016b', dns: 'f6c1', link: 'f85a', pub: 'f00c6', smart: 'f0198', memory: 'f8b3',
    wifi: 'f02bf', image: 'f80d', more: 'f8dc', chevR: 'e15f', chevL: 'e15e', down: 'e246', clean: 'f643'
  };
  U.icon = function (name) { return '<i class="ic">&#x' + (ICONS[name] || 'f816') + ';</i>'; };

  // ------------------------------------------------------------------ storage
  S.get = function (k, def) {
    try {
      var v = localStorage.getItem('lt_' + k);
      return v == null ? def : JSON.parse(v);
    } catch (e) { return def; }
  };
  S.set = function (k, v) {
    try { localStorage.setItem('lt_' + k, JSON.stringify(v)); } catch (e) { App.log('storage full (' + k + ')'); }
  };
  S.del = function (k) { try { localStorage.removeItem('lt_' + k); } catch (e) {} };
  /** A value the previous (Flutter) version of the app kept, so the TV keeps its ID and playlist. */
  S.old = function (k) {
    try {
      var v = localStorage.getItem('flutter.' + k);
      return v == null ? null : JSON.parse(v);
    } catch (e) { return null; }
  };

  // ------------------------------------------------------------------ silent log (RED x5 shows it)
  var LOG = [], t0 = Date.now(), logDirty = false, logPanel = null;
  try {
    var last = localStorage.getItem('lt_log');
    if (last) localStorage.setItem('lt_log_prev', last);
  } catch (e) {}
  App.log = function (msg) {
    var line = '+' + ((Date.now() - t0) / 1000).toFixed(1) + 's ' + msg;
    LOG.push(line);
    if (LOG.length > 220) LOG.splice(0, LOG.length - 220);
    logDirty = true;
    if (window.console && console.log) console.log('[app] ' + line);
    if (logPanel) renderLog();
  };
  setInterval(function () {
    if (!logDirty) return;
    logDirty = false;
    try { localStorage.setItem('lt_log', JSON.stringify(LOG)); } catch (e) {}
  }, 2000);
  function renderLog() {
    var prev = '';
    try {
      var p = JSON.parse(localStorage.getItem('lt_log_prev') || 'null');
      if (p && p.length) prev = 'PREVIOUS RUN:\n' + p.slice(-18).join('\n') + '\n\n';
    } catch (e) {}
    logPanel.textContent = prev + 'THIS RUN:\n' + LOG.slice(-40).join('\n');
  }
  App.toggleLog = function () {
    if (logPanel) { logPanel.parentNode.removeChild(logPanel); logPanel = null; return; }
    logPanel = U.el('div');
    logPanel.id = 'log';
    U.$('stage').appendChild(logPanel);
    renderLog();
  };
  window.addEventListener('error', function (e) {
    var m = e.message || 'script error';
    if (e.filename) m += ' @' + String(e.filename).split('/').pop() + ':' + e.lineno;
    App.log('ERROR ' + m);
  });

  // ------------------------------------------------------------------ requests
  /** What a request is about, for the log (never the address itself: it holds passwords). */
  function what(url) {
    var u = String(url).split('?'), path = u[0].split('/');
    var name = path[path.length - 1] || path[path.length - 2] || '?';
    var m = /[?&]action=([a-z_]+)/.exec(url);
    if (m) name += ':' + m[1];
    if (url.indexOf('/wp-json/') > 0) name = 'site' + u[0].substring(u[0].indexOf('/v1/') + 3);
    return name;
  }
  function failure(kind, status, text) {
    var e = new Error(kind === 'timeout' ? 'The server did not answer in time.' :
      kind === 'network' ? 'No connection to the server.' : 'The server answered with an error (' + status + ').');
    e.kind = kind;
    e.status = status || 0;
    e.text = text || '';
    return e;
  }
  /** GET / POST; resolves with {status, text} for any answer, rejects on no answer. */
  Net.req = function (method, url, body, opts) {
    opts = opts || {};
    return new Promise(function (resolve, reject) {
      var x = new XMLHttpRequest(), started = Date.now(), name = what(url);
      try { x.open(method, url, true); } catch (e) { reject(failure('network', 0)); return; }
      x.timeout = opts.timeout || 15000;
      if (body != null) x.setRequestHeader('Content-Type', 'application/json');
      if (opts.cancel) opts.cancel.x = x;
      x.onload = function () {
        if (!opts.quiet) App.log(method + ' ' + name + ' -> ' + x.status + ' (' + (Date.now() - started) + 'ms, ' + Math.round((x.responseText || '').length / 1024) + 'KB)');
        resolve({ status: x.status, text: x.responseText || '' });
      };
      x.onerror = function () { App.log(method + ' ' + name + ' -> FAILED (' + (Date.now() - started) + 'ms)'); reject(failure('network', 0)); };
      x.ontimeout = function () { App.log(method + ' ' + name + ' -> TIMEOUT'); reject(failure('timeout', 0)); };
      x.onabort = function () { reject(failure('abort', 0)); };
      try { x.send(body != null ? JSON.stringify(body) : null); } catch (e) { reject(failure('network', 0)); }
    });
  };
  /** JSON from a GET; rejects on HTTP errors and on an answer that is not JSON. */
  Net.json = function (url, opts) {
    return Net.req('GET', url, null, opts).then(function (r) {
      if (r.status < 200 || r.status >= 300) throw failure('http', r.status, r.text);
      var t = r.text.replace(/^\s+/, '');
      if (!t) return null;
      try { return JSON.parse(t); } catch (e) { throw failure('format', r.status, ''); }
    });
  };

  // ------------------------------------------------------------------ remote keys
  var CODES = {
    37: 'left', 38: 'up', 39: 'right', 40: 'down', 13: 'ok', 461: 'back', 27: 'back', 10009: 'back', 8: 'back',
    415: 'play', 19: 'pause', 413: 'stop', 417: 'ff', 412: 'rw', 179: 'playpause', 10252: 'playpause',
    33: 'chup', 34: 'chdown', 427: 'chup', 428: 'chdown', 403: 'red', 404: 'green', 405: 'yellow', 406: 'blue',
    457: 'info', 1056: 'info'
  };
  Keys.name = function (e) {
    var c = e.keyCode || e.which;
    if (c >= 48 && c <= 57) return 'd' + (c - 48);
    if (c >= 96 && c <= 105) return 'd' + (c - 96);
    if (CODES[c]) return CODES[c];
    switch (e.key) {
      case 'ArrowLeft': case 'Left': return 'left';
      case 'ArrowRight': case 'Right': return 'right';
      case 'ArrowUp': case 'Up': return 'up';
      case 'ArrowDown': case 'Down': return 'down';
      case 'Enter': return 'ok';
      case 'MediaPlayPause': return 'playpause';
    }
    return '';
  };

  // ------------------------------------------------------------------ focus
  F.cur = null;
  F.set = function (el, how) {
    if (!el) return;
    var old = F.cur;
    if (old && old !== el) {
      old.classList.remove('on');
      if (old._blur) old._blur();
    }
    F.cur = el;
    el.classList.add('on');
    if (el._focus) el._focus(how);
  };
  F.clear = function () {
    if (F.cur) {
      F.cur.classList.remove('on');
      if (F.cur._blur) F.cur._blur();
    }
    F.cur = null;
  };
  F.visible = function (e) { return e.offsetParent !== null && !e.classList.contains('nf'); };
  F.root = function () {
    var d = UI.topDialog && UI.topDialog();
    if (d) return d;
    var t = Nav.top();
    return t ? t.el : null;
  };
  F.first = function (root) {
    root = root || F.root();
    if (!root) return false;
    var list = root.querySelectorAll('.f');
    for (var i = 0; i < list.length; i++) {
      if (F.visible(list[i])) { F.set(list[i]); return true; }
    }
    return false;
  };
  /** Moves to the nearest element in that direction on the screen. */
  F.move = function (dir, from) {
    from = from || F.cur;
    var root = F.root();
    if (!root) return false;
    if (!from || !root.contains(from) || !F.visible(from)) return F.first(root);
    var list = root.querySelectorAll('.f');
    var c = from.getBoundingClientRect();
    var ccx = (c.left + c.right) / 2, ccy = (c.top + c.bottom) / 2;
    var best = null, bs = 1e9;
    for (var i = 0; i < list.length; i++) {
      var e = list[i];
      if (e === from || !F.visible(e)) continue;
      var r = e.getBoundingClientRect();
      if (!r.width && !r.height) continue;
      var rcx = (r.left + r.right) / 2, rcy = (r.top + r.bottom) / 2, p, s, off;
      if (dir === 'right') {
        if (rcx <= ccx + 1 || r.right <= c.right) continue;
        p = Math.max(0, r.left - c.right); s = Math.max(0, r.top - c.bottom, c.top - r.bottom); off = Math.abs(rcy - ccy);
      } else if (dir === 'left') {
        if (rcx >= ccx - 1 || r.left >= c.left) continue;
        p = Math.max(0, c.left - r.right); s = Math.max(0, r.top - c.bottom, c.top - r.bottom); off = Math.abs(rcy - ccy);
      } else if (dir === 'down') {
        if (rcy <= ccy + 1 || r.bottom <= c.bottom) continue;
        p = Math.max(0, r.top - c.bottom); s = Math.max(0, r.left - c.right, c.left - r.right); off = Math.abs(rcx - ccx);
      } else {
        if (rcy >= ccy - 1 || r.top >= c.top) continue;
        p = Math.max(0, c.top - r.bottom); s = Math.max(0, r.left - c.right, c.left - r.right); off = Math.abs(rcx - ccx);
      }
      var score = p + s * 4 + off * 0.15;
      if (score < bs) { bs = score; best = e; }
    }
    if (!best) return false;
    if (best._enter) best._enter(dir, from); else F.set(best);
    return true;
  };

  // ------------------------------------------------------------------ screens
  Nav.stack = [];
  Nav.top = function () { return Nav.stack.length ? Nav.stack[Nav.stack.length - 1] : null; };
  Nav.push = function (s) {
    var t = Nav.top();
    if (t) {
      t.lastFocus = F.cur;
      t.el.classList.add('hide');
      if (t.hide) t.hide(s);
    }
    Nav.stack.push(s);
    U.$('screens').appendChild(s.el);
    F.clear();
    if (s.show) s.show(true);
    if (!s.noFocus && (!F.cur || !s.el.contains(F.cur))) F.first(s.el);
    App.log('screen ' + (s.name || '?'));
  };
  function drop(s) {
    if (s.destroy) { try { s.destroy(); } catch (e) { App.log('ERROR destroy ' + e.message); } }
    if (s.el.parentNode) s.el.parentNode.removeChild(s.el);
  }
  Nav.pop = function () {
    var s = Nav.stack.pop();
    if (!s) return;
    drop(s);
    var t = Nav.top();
    if (!t) return;
    t.el.classList.remove('hide');
    F.clear();
    if (t.show) t.show(false);
    if (!F.cur) {
      if (t.lastFocus && t.el.contains(t.lastFocus) && F.visible(t.lastFocus)) F.set(t.lastFocus, 'back');
      else F.first(t.el);
    }
    App.log('screen ' + (t.name || '?') + ' (back)');
  };
  /** Everything closes and this screen is the only one. */
  Nav.reset = function (s) {
    while (Nav.stack.length) drop(Nav.stack.pop());
    F.clear();
    Nav.push(s);
  };
  Nav.replace = function (s) {
    var old = Nav.stack.pop();
    if (old) drop(old);
    var t = Nav.top();
    if (t) t.el.classList.add('hide');
    Nav.stack.push(s);
    U.$('screens').appendChild(s.el);
    F.clear();
    if (s.show) s.show(true);
    if (!F.cur || !s.el.contains(F.cur)) F.first(s.el);
    App.log('screen ' + (s.name || '?'));
  };
  Nav.back = function () {
    var t = Nav.top();
    if (t && t.onBack && t.onBack()) return;
    if (Nav.stack.length > 1) Nav.pop();
    else App.askExit();
  };
  Nav.find = function (name) {
    for (var i = Nav.stack.length - 1; i >= 0; i--) if (Nav.stack[i].name === name) return Nav.stack[i];
    return null;
  };

  // ------------------------------------------------------------------ key handling
  var okTimer = null, okLongDone = false, okEl = null, reds = [];
  App.blocked = false; // the start screen is up: keys wait

  function editing() {
    var a = document.activeElement;
    return a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA') ? a : null;
  }

  App.key = function (k, e) {
    if (k === 'red') {
      var now = Date.now();
      reds = reds.filter(function (t) { return now - t < 2500; });
      reds.push(now);
      if (reds.length >= 5) { reds = []; App.toggleLog(); }
    }
    if (App.blocked) return;
    var d = UI.topDialog && UI.topDialog();
    var cur = F.cur;
    if (cur && cur._key && (d ? d.contains(cur) : true) && cur._key(k, e)) return;
    if (d) {
      if (k === 'back') { UI.closeTop(true); return; }
    } else {
      var t = Nav.top();
      if (t && t.onKey && t.onKey(k, e)) return;
    }
    switch (k) {
      case 'left': case 'right': case 'up': case 'down':
        F.move(k);
        break;
      case 'ok':
        if (cur && cur._ok) cur._ok();
        break;
      case 'back':
        Nav.back();
        break;
    }
  };

  document.addEventListener('keydown', function (e) {
    var k = Keys.name(e);
    var input = editing();
    if (input) {
      // Typing (the TV's on-screen keyboard or a real one): only Enter, Back, Up and Down are ours.
      if (k === 'ok') { e.preventDefault(); input.blur(); if (input._submit) input._submit(); return; }
      if (k === 'back' && e.keyCode !== 8) { e.preventDefault(); input.blur(); return; }
      if (k === 'up' || k === 'down') { e.preventDefault(); input.blur(); App.key(k, e); }
      return;
    }
    if (!k) return;
    e.preventDefault();
    if (k === 'ok') {
      var cur = F.cur;
      if (cur && cur._long && !App.blocked) {
        if (e.repeat) return;
        okEl = cur;
        okLongDone = false;
        clearTimeout(okTimer);
        okTimer = setTimeout(function () {
          okLongDone = true;
          if (okEl === F.cur && okEl._long) okEl._long();
        }, 650);
        return;
      }
      if (e.repeat) return;
    }
    App.key(k, e);
  }, true);

  document.addEventListener('keyup', function (e) {
    if (editing()) return;
    if (Keys.name(e) !== 'ok' || !okEl) return;
    clearTimeout(okTimer);
    var el = okEl;
    okEl = null;
    if (!okLongDone && el === F.cur) App.key('ok', e);
  }, true);

  // The Magic Remote's pointer: pointing focuses, clicking presses, the wheel scrolls lists.
  function inRoot(t) {
    var root = F.root();
    return root && root.contains(t) && F.visible(t);
  }
  // Only a pointer that really moves takes the focus (the page changing under a resting pointer
  // must not pull the focus away from the remote's arrows).
  var moved = 0, mx = -1, my = -1;
  document.addEventListener('mousemove', function (e) {
    if (e.clientX === mx && e.clientY === my) return;
    mx = e.clientX;
    my = e.clientY;
    moved = Date.now();
  });
  document.addEventListener('mouseover', function (e) {
    if (App.blocked || Date.now() - moved > 400) return;
    var t = U.closest(e.target, 'f');
    if (t && t !== F.cur && inRoot(t)) F.set(t, 'mouse');
  });
  document.addEventListener('click', function (e) {
    if (App.blocked) return;
    var t = U.closest(e.target, 'f');
    if (!t || !inRoot(t)) return;
    if (t !== F.cur) F.set(t, 'mouse');
    if (t._ok) t._ok();
  });
  function wheel(e) {
    if (App.blocked || !F.cur || !F.cur._key) return;
    var dy = e.deltaY || -e.wheelDelta || 0;
    if (dy) F.cur._key(dy > 0 ? 'down' : 'up', e);
  }
  document.addEventListener('wheel', wheel);
  document.addEventListener('mousewheel', wheel);
})();
