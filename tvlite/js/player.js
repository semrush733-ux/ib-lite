/* The one video player of the app: the TV's own (hardware) player behind a single <video>.
 * The same element is the small preview and the full screen picture, so going full screen and
 * back never reloads the stream. Before a new address opens, the old one is let go (most IPTV
 * accounts allow one connection). A stream that does not start in time or fails tries the
 * channel's other format; a live channel that stops reconnects by itself. */
var Player = {};

(function () {
  'use strict';

  var v = U.$('vid');
  Player.v = v;
  var st = {
    token: 0, urls: [], ui: 0, live: false, start: 0, state: 'off', retries: 0,
    played: false, watch: null, stall: null, loadTimer: null, t0: 0, mode: 'off', seekTo: -1
  };
  var subs = [];
  Player.on = function (fn) { subs.push(fn); return fn; };
  Player.off = function (fn) { var i = subs.indexOf(fn); if (i >= 0) subs.splice(i, 1); };
  function emit(ev, data) {
    var l = subs.slice();
    for (var i = 0; i < l.length; i++) { try { l[i](ev, data); } catch (e) { App.log('ERROR player listener: ' + e.message); } }
  }
  function setState(s, info) {
    if (st.state === s && !info) return;
    st.state = s;
    emit('state', { state: s, info: info || '' });
  }
  Player.state = function () { return st.state; };
  Player.live = function () { return st.live; };
  Player.token = function () { return st.token; };
  Player.urls = function () { return st.urls.slice(); };
  Player.active = function () { return st.state !== 'off'; };

  /** What is playing, for the log (never the address: it holds the account's password). */
  function describe(url) {
    var p = String(url || '').split('?')[0].split('/');
    var kind = '';
    for (var i = 0; i < p.length; i++) if (p[i] === 'live' || p[i] === 'movie' || p[i] === 'series' || p[i] === 'timeshift') kind = p[i];
    return (kind || 'stream') + ' ' + (p[p.length - 1] || '');
  }
  function fmt(url) {
    var p = String(url || '').split('?')[0].toLowerCase();
    return U.endsWith(p, '.m3u8') ? 'm3u8' : U.endsWith(p, '.ts') ? 'ts' : '';
  }

  // ---------------------------------------------------------------- where the picture is
  /** mode 'full', 'preview' (rect {left, top, width, height} in page pixels) or 'off'. */
  Player.layout = function (mode, rect) {
    st.mode = mode;
    if (mode === 'off') {
      v.classList.add('hide');
      return;
    }
    var r = mode === 'full' ? { left: 0, top: 0, width: 1920, height: 1080 } : rect;
    v.style.left = Math.round(r.left) + 'px';
    v.style.top = Math.round(r.top) + 'px';
    v.style.width = Math.round(r.width) + 'px';
    v.style.height = Math.round(r.height) + 'px';
    v.classList.remove('hide');
  };
  Player.mode = function () { return st.mode; };

  // ---------------------------------------------------------------- open / stop
  function clearTimers() {
    clearTimeout(st.watch);
    clearTimeout(st.stall);
    clearTimeout(st.loadTimer);
    st.watch = st.stall = st.loadTimer = null;
  }
  function release() {
    try { v.pause(); } catch (e) {}
    try { v.removeAttribute('src'); v.load(); } catch (e2) {}
  }

  /** Plays the first address that works. opts: {live, start (seconds), key} */
  Player.open = function (urls, opts) {
    opts = opts || {};
    var t = ++st.token;
    clearTimers();
    var wasPlaying = st.state !== 'off';
    release();
    st.urls = (urls || []).slice();
    st.ui = 0;
    st.live = !!opts.live;
    st.start = opts.start || 0;
    st.retries = 0;
    st.played = false;
    st.seekTo = -1;
    setState('loading');
    if (!st.urls.length) { setState('error', 'no address'); return t; }
    // A moment for the TV's player to let go of the previous stream (one connection per account).
    st.loadTimer = setTimeout(function () { if (t === st.token) load(t); }, wasPlaying ? 120 : 10);
    return t;
  };

  function load(t) {
    var url = st.urls[st.ui];
    st.t0 = Date.now();
    App.log('open ' + describe(url) + (st.ui ? ' (other address)' : '') + (st.retries ? ' (reconnect ' + st.retries + ')' : ''));
    try {
      v.src = url;
      v.load();
    } catch (e) {}
    var p = null;
    try { p = v.play(); } catch (e2) {}
    if (p && p.then) p.then(null, function () {});
    arm(t, st.live ? 14000 : 30000);
  }

  function arm(t, ms) {
    clearTimeout(st.watch);
    st.watch = setTimeout(function () {
      if (t !== st.token) return;
      if (st.state === 'loading' || st.state === 'buffering') fail(t, 'nothing after ' + Math.round(ms / 1000) + ' s');
    }, ms);
  }

  function fail(t, why) {
    if (t !== st.token) return;
    App.log('stream problem: ' + why);
    clearTimers();
    if (!st.played && st.ui + 1 < st.urls.length) {
      st.ui++;
      release();
      st.loadTimer = setTimeout(function () { if (t === st.token) load(t); }, 150);
      return;
    }
    if (st.played && st.retries < 5) {
      reconnect(t);
      return;
    }
    release();
    setState('error', why);
  }

  function reconnect(t) {
    st.retries++;
    if (!st.live) st.start = Math.max(0, (v.currentTime || st.start) - 2);
    setState('buffering');
    release();
    st.loadTimer = setTimeout(function () { if (t === st.token) load(t); }, 700 + st.retries * 400);
  }

  Player.retry = function () {
    if (!st.urls.length) return;
    var urls = st.urls, live = st.live, start = st.live ? 0 : (v.currentTime || st.start);
    Player.open(urls, { live: live, start: start });
  };

  Player.stop = function () {
    st.token++;
    clearTimers();
    release();
    st.urls = [];
    setState('off');
  };

  // ---------------------------------------------------------------- video events
  function on(name, fn) { v.addEventListener(name, fn); }
  on('playing', function () {
    if (!st.urls.length) return;
    clearTimeout(st.watch);
    clearTimeout(st.stall);
    if (!st.played) {
      st.played = true;
      App.log('picture after ' + (Date.now() - st.t0) + ' ms (' + (fmt(st.urls[st.ui]) || 'file') + ')');
      if (st.live) Src.formatWorked(fmt(st.urls[st.ui]), st.ui > 0);
      emit('first');
    }
    st.retries = 0;
    setState('playing');
  });
  on('loadedmetadata', function () {
    if (!st.live && st.start > 1) {
      try { v.currentTime = st.start; } catch (e) {}
    }
    emit('meta');
  });
  on('waiting', function () {
    if (!st.urls.length || st.state === 'loading') return;
    if (st.state === 'paused') return;
    setState('buffering');
    var t = st.token;
    clearTimeout(st.stall);
    st.stall = setTimeout(function () {
      if (t === st.token && st.state === 'buffering') fail(t, 'stopped to buffer too long');
    }, st.live ? 12000 : 30000);
  });
  on('pause', function () {
    if (st.urls.length && st.played && !st.live && st.state === 'playing') setState('paused');
  });
  on('play', function () {
    if (st.state === 'paused') setState('playing');
  });
  on('error', function () {
    if (!st.urls.length || !v.getAttribute('src')) return;
    var e = v.error, code = e ? e.code : 0;
    fail(st.token, 'error ' + code + (e && e.message ? ' ' + e.message : ''));
  });
  on('ended', function () {
    if (!st.urls.length) return;
    if (st.live) { fail(st.token, 'stream ended'); return; }
    clearTimers();
    setState('ended');
  });
  on('timeupdate', function () {
    if (st.state === 'buffering' && !v.paused && v.readyState >= 3) {
      clearTimeout(st.stall);
      setState('playing');
    }
  });

  // ---------------------------------------------------------------- controls (films)
  Player.pos = function () { return v.currentTime || 0; };
  Player.dur = function () { var d = v.duration; return isFinite(d) && d > 0 ? d : 0; };
  Player.toggle = function () {
    if (st.live || !st.played) return;
    if (v.paused) {
      var p = v.play();
      if (p && p.then) p.then(null, function () {});
      setState('playing');
    } else {
      v.pause();
      setState('paused');
    }
  };
  Player.play = function () { if (v.paused) Player.toggle(); };
  Player.pause = function () { if (!v.paused && !st.live) Player.toggle(); };
  Player.seek = function (sec) {
    var d = Player.dur();
    if (!d) return;
    sec = Math.max(0, Math.min(d - 3, sec));
    try { v.currentTime = sec; } catch (e) {}
  };

  /** The stream's sound tracks, when the TV tells them. */
  Player.audioTracks = function () {
    var out = [], a = v.audioTracks;
    if (!a || !a.length) return out;
    for (var i = 0; i < a.length; i++) {
      out.push({ i: i, label: a[i].label || a[i].language || 'Track ' + (i + 1), lang: a[i].language || '', on: !!a[i].enabled });
    }
    return out;
  };
  Player.setAudio = function (i) {
    var a = v.audioTracks;
    if (!a) return;
    for (var k = 0; k < a.length; k++) a[k].enabled = k === i;
    App.log('sound track ' + (i + 1));
  };
  Player.size = function () { return v.videoWidth ? v.videoWidth + 'x' + v.videoHeight : ''; };
})();
