/* The one video player of the app: the TV's own (hardware) player.
 *
 * Two engines behind the same functions:
 *  - a single <video> element (the TV's media pipeline): LG, browsers, and Samsung by default;
 *  - Samsung (Tizen), when chosen in Settings: AVPlay (webapis.avplay), Samsung's hardware player.
 *    It plays MPEG-TS, HLS and MP4 directly on the TV's video chip, on its own picture layer under
 *    the app (for streams the standard player does not open).
 *
 * The same picture is the small preview and the full screen, so going full screen and back never
 * reloads the stream. Before a new address opens, the old one is let go (most IPTV accounts allow
 * one connection). A stream that does not start in time or fails tries the channel's other
 * format; a live channel that stops reconnects by itself. */
var Player = {};

(function () {
  'use strict';

  var v = U.$('vid');
  Player.v = v;
  var st = {
    token: 0, urls: [], ui: 0, live: false, loop: false, start: 0, state: 'off', retries: 0,
    played: false, watch: null, stall: null, loadTimer: null, t0: 0, mode: 'off', seekTo: -1,
    rect: { left: 0, top: 0, width: 1920, height: 1080 }
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
  Player.loops = function () { return st.loop; };
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

  // ================================================================ the engines
  // Samsung's AVPlay only when chosen in Settings (the TV's standard player is the default).
  Player.avplayAvailable = !!(window.webapis && webapis.avplay && typeof webapis.avplay.open === 'function');
  var av = Player.avplayAvailable && S.get('samsung_player', 'standard') === 'avplay' ? webapis.avplay : null;
  var avObj = null;
  Player.engine = av ? 'avplay' : 'video';

  // ---------------------------------------------------------------- <video> (LG, browsers)
  var VideoEngine = {
    load: function (t, url) {
      try {
        v.loop = st.loop;
        v.src = url;
        v.load();
      } catch (e) {}
      var p = null;
      try { p = v.play(); } catch (e2) {}
      if (p && p.then) p.then(null, function () {});
    },
    release: function () {
      try { v.pause(); } catch (e) {}
      try { v.removeAttribute('src'); v.load(); } catch (e2) {}
    },
    pos: function () { return v.currentTime || 0; },
    dur: function () { var d = v.duration; return isFinite(d) && d > 0 ? d : 0; },
    paused: function () { return v.paused; },
    pause: function () { v.pause(); },
    resume: function () { var p = v.play(); if (p && p.then) p.then(null, function () {}); },
    seek: function (sec) { try { v.currentTime = sec; } catch (e) {} },
    tracks: function () {
      var out = [], a = v.audioTracks;
      if (!a || !a.length) return out;
      for (var i = 0; i < a.length; i++) {
        out.push({ i: i, label: a[i].label || a[i].language || 'Track ' + (i + 1), lang: a[i].language || '', on: !!a[i].enabled });
      }
      return out;
    },
    setTrack: function (i) {
      var a = v.audioTracks;
      if (!a) return;
      for (var k = 0; k < a.length; k++) a[k].enabled = k === i;
    },
    size: function () { return { w: v.videoWidth || 0, h: v.videoHeight || 0 }; },
    mute: function (m) { v.muted = !!m; },
    show: function (on) {
      if (!on) { v.classList.add('hide'); return; }
      var r = st.rect;
      v.style.left = Math.round(r.left) + 'px';
      v.style.top = Math.round(r.top) + 'px';
      v.style.width = Math.round(r.width) + 'px';
      v.style.height = Math.round(r.height) + 'px';
      v.classList.remove('hide');
    }
  };

  // ---------------------------------------------------------------- AVPlay (Samsung)
  /** The JSON in AVPlay's track info, as an object (keys in lower case). */
  function extra(s) {
    var o = {};
    try {
      var j = typeof s === 'string' ? JSON.parse(s) : (s || {});
      for (var k in j) if (j.hasOwnProperty(k)) o[k.toLowerCase()] = j[k];
    } catch (e) {}
    return o;
  }
  function avState() { try { return av.getState(); } catch (e) { return 'NONE'; } }
  var avPos = 0;

  var AvEngine = {
    load: function (t, url) {
      avPos = 0;
      try { av.close(); } catch (e0) {}
      try {
        av.open(url);
      } catch (e) {
        fail(t, 'open ' + (e && (e.name || e.message) || e));
        return;
      }
      try {
        av.setListener({
          onbufferingstart: function () { if (t === st.token) onWaiting(); },
          onbufferingprogress: function () {},
          onbufferingcomplete: function () { if (t === st.token && st.played) onPlaying(); },
          oncurrentplaytime: function (ms) {
            if (t !== st.token) return;
            avPos = (ms || 0) / 1000;
            // The first moment of the picture: the stream really plays.
            if (!st.played || st.state === 'buffering' || st.state === 'loading') onPlaying();
          },
          onstreamcompleted: function () { if (t === st.token) onEnded(); },
          onerror: function (type) { if (t === st.token) fail(t, 'player ' + type); },
          onevent: function (type, data) {
            if (type === 'PLAYER_MSG_RESOLUTION_CHANGED' && t === st.token) emit('meta');
          },
          onsubtitlechange: function () {},
          ondrmevent: function () {}
        });
      } catch (e1) {}
      AvEngine.show(st.mode !== 'off');
      try { av.setDisplayMethod('PLAYER_DISPLAY_MODE_LETTER_BOX'); } catch (e2) {}
      // Live: give up a dead stream in good time, so the other format or a reconnect can follow.
      try { av.setTimeoutForBuffering(st.live ? 10 : 20); } catch (e3) {}
      try {
        av.prepareAsync(function () {
          if (t !== st.token) return;
          try { av.play(); } catch (e4) { fail(t, 'play ' + (e4 && e4.name || e4)); return; }
          if (!st.live && st.start > 1) AvEngine.seek(st.start);
          emit('meta');
        }, function (err) {
          if (t === st.token) fail(t, 'prepare ' + (err && (err.name || err.message) || err));
        });
      } catch (e5) {
        fail(t, 'prepare ' + (e5 && e5.name || e5));
      }
    },
    release: function () {
      avPos = 0;
      try { av.stop(); } catch (e) {}
      try { av.close(); } catch (e2) {}
    },
    pos: function () {
      try { var ms = av.getCurrentTime(); if (ms > 0) return ms / 1000; } catch (e) {}
      return avPos;
    },
    dur: function () {
      if (st.live) return 0;
      try { var ms = av.getDuration(); return ms > 0 ? ms / 1000 : 0; } catch (e) { return 0; }
    },
    paused: function () { return avState() === 'PAUSED'; },
    pause: function () { try { av.pause(); } catch (e) {} },
    resume: function () { try { av.play(); } catch (e) {} },
    seek: function (sec) {
      try { av.seekTo(Math.max(0, Math.floor(sec * 1000)), function () {}, function () {}); } catch (e) {}
    },
    tracks: function () {
      var out = [], info = [], cur = -1;
      try { info = av.getTotalTrackInfo() || []; } catch (e) {}
      try {
        var now = av.getCurrentStreamInfo() || [];
        for (var c = 0; c < now.length; c++) if (now[c].type === 'AUDIO') cur = now[c].index;
      } catch (e2) {}
      var n = 0;
      for (var i = 0; i < info.length; i++) {
        if (info[i].type !== 'AUDIO') continue;
        n++;
        var x = extra(info[i].extra_info), lang = String(x.language || x.lang || '');
        out.push({ i: info[i].index, label: lang ? lang.toUpperCase() + ' (' + n + ')' : 'Track ' + n, lang: lang, on: info[i].index === cur });
      }
      return out;
    },
    setTrack: function (i) { try { av.setSelectTrack('AUDIO', i); } catch (e) { App.log('sound track change refused: ' + (e && e.name || e)); } },
    size: function () {
      try {
        var now = av.getCurrentStreamInfo() || [];
        for (var c = 0; c < now.length; c++) {
          if (now[c].type !== 'VIDEO') continue;
          var x = extra(now[c].extra_info);
          return { w: parseInt(x.width, 10) || 0, h: parseInt(x.height, 10) || 0 };
        }
      } catch (e) {}
      return { w: 0, h: 0 };
    },
    // Changing channel: the old picture's sound stops at once (the next channel opens shortly).
    mute: function (m) { if (m && avState() === 'PLAYING') { try { av.pause(); } catch (e) {} } },
    show: function (on) {
      if (!avObj) return;
      var r = on ? st.rect : { left: 0, top: 0, width: 1, height: 1 };
      avObj.style.left = Math.round(r.left) + 'px';
      avObj.style.top = Math.round(r.top) + 'px';
      avObj.style.width = Math.round(r.width) + 'px';
      avObj.style.height = Math.round(r.height) + 'px';
      avObj.classList.toggle('hide', !on);
      // The picture is on the TV's own layer under the page: the page lets it through.
      document.documentElement.classList.toggle('avp-on', !!on);
      if (avState() === 'NONE') return;
      try { av.setDisplayRect(Math.round(r.left), Math.round(r.top), Math.max(1, Math.round(r.width)), Math.max(1, Math.round(r.height))); } catch (e) {}
    }
  };

  var E = VideoEngine;
  if (av) {
    try {
      avObj = document.createElement('object');
      avObj.type = 'application/avplayer';
      avObj.id = 'avp';
      avObj.className = 'hide';
      v.parentNode.insertBefore(avObj, v);
      v.classList.add('hide');
      E = AvEngine;
      App.log('player: Samsung AVPlay');
    } catch (e) {
      App.log('player: AVPlay not available (' + (e && e.message) + '), <video> used');
      av = null;
      Player.engine = 'video';
    }
  }

  // ---------------------------------------------------------------- where the picture is
  /** mode 'full', 'preview' (rect {left, top, width, height} in page pixels) or 'off'. */
  Player.layout = function (mode, rect) {
    st.mode = mode;
    if (mode === 'off') {
      E.show(false);
      return;
    }
    st.rect = mode === 'full' ? { left: 0, top: 0, width: 1920, height: 1080 } : rect;
    E.show(true);
  };
  Player.mode = function () { return st.mode; };

  // ---------------------------------------------------------------- open / stop
  function clearTimers() {
    clearTimeout(st.watch);
    clearTimeout(st.stall);
    clearTimeout(st.loadTimer);
    st.watch = st.stall = st.loadTimer = null;
  }
  function release() { E.release(); }

  /** Plays the first address that works. opts: {live, start (seconds), loop (start again at the end)} */
  Player.open = function (urls, opts) {
    opts = opts || {};
    var t = ++st.token;
    clearTimers();
    var wasPlaying = st.state !== 'off';
    release();
    st.urls = (urls || []).slice();
    st.ui = 0;
    st.live = !!opts.live;
    st.loop = !!opts.loop;
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
    E.load(t, url);
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
    if (!st.live) st.start = Math.max(0, (E.pos() || st.start) - 2);
    setState('buffering');
    release();
    st.loadTimer = setTimeout(function () { if (t === st.token) load(t); }, 700 + st.retries * 400);
  }

  Player.retry = function () {
    if (!st.urls.length) return;
    var urls = st.urls, live = st.live, start = st.live ? 0 : (E.pos() || st.start);
    Player.open(urls, { live: live, start: start, loop: st.loop });
  };

  Player.stop = function () {
    st.token++;
    clearTimers();
    release();
    st.urls = [];
    setState('off');
  };

  // ---------------------------------------------------------------- what the engines report
  function onPlaying() {
    if (!st.urls.length) return;
    clearTimeout(st.watch);
    clearTimeout(st.stall);
    if (!st.played) {
      st.played = true;
      App.log('picture after ' + (Date.now() - st.t0) + ' ms (' + (fmt(st.urls[st.ui]) || 'file') + ', ' + Player.engine + ')');
      if (st.live) Src.formatWorked(fmt(st.urls[st.ui]), st.ui > 0);
      emit('first');
    }
    st.retries = 0;
    if (st.state !== 'paused') setState('playing');
  }
  function onWaiting() {
    if (!st.urls.length || st.state === 'loading') return;
    if (st.state === 'paused') return;
    setState('buffering');
    var t = st.token;
    clearTimeout(st.stall);
    st.stall = setTimeout(function () {
      if (t === st.token && st.state === 'buffering') fail(t, 'stopped to buffer too long');
    }, st.live ? 12000 : 30000);
  }
  function onEnded() {
    if (!st.urls.length) return;
    if (st.loop) {
      // A video used as a channel (demo): starts again from the beginning.
      var t = st.token;
      release();
      st.loadTimer = setTimeout(function () { if (t === st.token) load(t); }, 100);
      return;
    }
    if (st.live) { fail(st.token, 'stream ended'); return; }
    clearTimers();
    setState('ended');
  }

  // <video> events (LG, browsers).
  function on(name, fn) { v.addEventListener(name, fn); }
  if (E === VideoEngine) {
    on('playing', onPlaying);
    on('loadedmetadata', function () {
      if (!st.live && st.start > 1) {
        try { v.currentTime = st.start; } catch (e) {}
      }
      emit('meta');
    });
    on('waiting', onWaiting);
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
      // <video loop> starts again by itself; only a real end gets here.
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
  }

  // ---------------------------------------------------------------- controls (films)
  Player.pos = function () { return E.pos(); };
  Player.dur = function () { return E.dur(); };
  Player.toggle = function () {
    if (st.live || !st.played) return;
    if (E.paused()) {
      E.resume();
      setState('playing');
    } else {
      E.pause();
      setState('paused');
    }
  };
  Player.play = function () { if (E.paused()) Player.toggle(); };
  Player.pause = function () { if (!E.paused() && !st.live) Player.toggle(); };
  Player.seek = function (sec) {
    var d = Player.dur();
    if (!d) return;
    sec = Math.max(0, Math.min(d - 3, sec));
    E.seek(sec);
  };

  /** The stream's sound tracks, when the TV tells them. */
  Player.audioTracks = function () { return E.tracks(); };
  Player.setAudio = function (i) {
    E.setTrack(i);
    App.log('sound track ' + i);
  };
  /** The picture size the stream delivers: {w, h} (0 while unknown). */
  Player.videoSize = function () { return E.size(); };
  Player.size = function () { var s = E.size(); return s.w ? s.w + 'x' + s.h : ''; };
  /** Sound off while changing channel (the old channel's sound stops). */
  Player.setMuted = function (m) { E.mute(m); };
})();
