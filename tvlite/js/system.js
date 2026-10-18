/* Settings › Network, the Internet speed test (also on the home screen), Clear cache and
 * Application info, as in the Android app. */
(function () {
  'use strict';

  // ================================================================== network
  /** What the TV is connected to: {type: wifi | ethernet | cellular | none | unknown, ssid,
   *  level (0..4), ip, gateway, dns, mask, mac, online}. Never fails. */
  App.netInfo = function () {
    var out = { type: 'unknown', ssid: '', level: -1, ip: '', gateway: '', dns: '', mask: '', mac: '', online: navigator.onLine !== false };
    // Samsung (Tizen): the TV's network functions (privilege network.public).
    var n = window.webapis && webapis.network;
    if (n && typeof n.getActiveConnectionType === 'function') {
      var t = -1;
      try { t = n.getActiveConnectionType(); } catch (e) {}
      out.type = t === 1 ? 'wifi' : t === 3 ? 'ethernet' : t === 2 ? 'cellular' : t === 0 ? 'none' : 'unknown';
      var get = function (fn) { try { return typeof n[fn] === 'function' ? String(n[fn]() || '') : ''; } catch (e) { return ''; } };
      out.ip = get('getIp');
      out.gateway = get('getGateway');
      out.dns = get('getDns');
      out.mask = get('getSubnetMask');
      out.mac = get('getMac');
      if (out.type === 'wifi') {
        out.ssid = get('getWiFiSsid');
        var lv = U.int(get('getWiFiSignalStrengthLevel'));
        out.level = Math.max(0, Math.min(4, lv > 4 ? Math.round(lv * 4 / 5) : lv));
      }
      if (out.type === 'none') out.online = false;
      return Promise.resolve(out);
    }
    // LG (webOS): the connection manager.
    if (window.PalmServiceBridge) {
      return App.luna('luna://com.palm.connectionmanager/getStatus', {}, 2500).then(function (r) {
        if (!r) return out;
        var w = r.wired || {}, f = r.wifi || {};
        var on = function (x) { return x && x.state === 'connected'; };
        var c = on(w) ? w : on(f) ? f : null;
        out.type = on(w) ? 'ethernet' : on(f) ? 'wifi' : 'none';
        if (c) {
          out.ip = c.ipAddress || '';
          out.gateway = c.gateway || '';
          out.dns = [c.dns1, c.dns2].filter(function (s) { return s; }).join(', ');
          out.mask = c.netmask || '';
        }
        if (on(f)) out.ssid = f.ssid || '';
        out.online = r.isInternetConnectionAvailable !== false && out.type !== 'none';
        return out;
      }, function () { return out; });
    }
    return Promise.resolve(out);
  };

  function bars(level) {
    var h = '';
    for (var i = 0; i < 4; i++) h += '<i class="b' + i + (i < level ? ' on' : '') + '"></i>';
    return '<span class="bars">' + h + '</span>';
  }

  /** Settings › Network: the connection, the addresses and the speed test. */
  App.networkDialog = function () {
    var box = U.el('div', 'netbox');
    box.innerHTML = '<div class="msg dim">Looking at the connection…</div>';
    var d = UI.dialog({
      title: 'Network', html: box, width: 1220,
      buttons: [{ label: 'Speed test', icon: 'speed', ok: function () { App.speedTest(); } }, { label: 'Close', pri: true }], focus: 0
    });
    App.netInfo().then(function (i) {
      if (UI.topDialog() !== d.el) return;
      var connected = i.type !== 'none' && i.online;
      var title = i.type === 'wifi' ? (i.ssid || 'Wi-Fi') : i.type === 'ethernet' ? 'Cable (Ethernet)' : i.type === 'cellular' ? 'Mobile data' :
        i.type === 'none' ? 'Not connected' : (i.online ? 'Connected' : 'Not connected');
      var icon = i.type === 'wifi' ? (i.level >= 0 ? bars(i.level) : U.icon('wifi')) : U.icon(i.type === 'ethernet' ? 'lan' : connected ? 'pub' : 'wifioff');
      var rows = [];
      if (i.type === 'wifi' && i.level >= 0) rows.push(['Signal', ['Very weak', 'Weak', 'Fair', 'Good', 'Excellent'][i.level]]);
      if (i.ip) rows.push(['IP address', i.ip]);
      if (i.gateway) rows.push(['Router (gateway)', i.gateway]);
      if (i.dns) rows.push(['DNS', i.dns]);
      if (i.mask) rows.push(['Subnet mask', i.mask]);
      if (Backend.deviceId) rows.push(['MAC Address (app)', Backend.deviceId]);
      box.innerHTML = '<div class="netcard ' + (connected ? 'ok' : 'off') + '"><span class="ni">' + icon + '</span><div class="nt">' +
        '<div class="st">' + (connected ? 'CONNECTED' : 'OFFLINE') + '</div><div class="nm">' + U.esc(title) + '</div></div></div>' +
        rows.map(function (r) { return '<div class="row2"><span class="k">' + U.esc(r[0]) + '</span><span class="v num">' + U.esc(r[1]) + '</span></div>'; }).join('') +
        '<div class="kc-note">To change the network or the Wi-Fi password: the TV\'s own Settings › ' +
        (window.PalmServiceBridge ? 'Network' : 'General › Network') + '.</div>';
    });
  };

  // ================================================================== speed test
  /** Against Cloudflare's public speed servers (the same as speed.cloudflare.com): ping, download for
   *  8 seconds in 3 streams, upload for 6 seconds. As in the Android app. */
  var SPEED = 'https://speed.cloudflare.com';
  var running = null;

  function xhr(method, url, body, opts) {
    var x = new XMLHttpRequest();
    x.open(method, url, true);
    x.timeout = opts.timeout || 15000;
    if (opts.binary) x.responseType = 'arraybuffer';
    var p = new Promise(function (resolve, reject) {
      x.onload = function () { if (x.status >= 200 && x.status < 400) resolve(x); else reject(new Error('answer ' + x.status)); };
      x.onerror = function () { reject(new Error('network')); };
      x.ontimeout = function () { reject(new Error('timeout')); };
      x.onabort = function () { reject(new Error('stopped')); };
    });
    if (opts.progress) x.onprogress = opts.progress;
    if (opts.upProgress && x.upload) x.upload.onprogress = opts.upProgress;
    x.send(body == null ? null : body);
    p.x = x;
    return p;
  }
  function test(job) {
    var all = [];
    job.track = function (p) { all.push(p.x); return p; };
    job.stop = function () { job.stopped = true; all.forEach(function (x) { try { x.abort(); } catch (e) {} }); };
    return job;
  }
  function ping(job) {
    var times = [], i = 0;
    return (function next() {
      if (job.stopped) return Promise.reject(new Error('stopped'));
      if (i >= 6) {
        times.sort(function (a, b) { return a - b; });
        return Promise.resolve(times.length ? times[Math.floor(times.length / 2)] : 0);
      }
      var t0 = Date.now(), first = i === 0;
      i++;
      return job.track(xhr('GET', SPEED + '/__down?bytes=0&r=' + Math.random(), null, { timeout: 5000 })).then(function () {
        if (!first) times.push(Date.now() - t0); // the first one also sets up the connection
        return next();
      });
    })();
  }
  function download(job, seconds, live) {
    var bytes = 0, t0 = Date.now(), end = t0 + seconds * 1000;
    function stream() {
      if (job.stopped || Date.now() >= end) return Promise.resolve();
      var got = 0;
      var p = job.track(xhr('GET', SPEED + '/__down?bytes=25000000&r=' + Math.random(), null, {
        binary: true, timeout: (seconds + 4) * 1000,
        progress: function (e) {
          bytes += e.loaded - got;
          got = e.loaded;
          if (Date.now() >= end) { try { p.x.abort(); } catch (a) {} }
        }
      }));
      return p.then(stream, function (e) { if (job.stopped || Date.now() < end - 500) throw e; });
    }
    var timer = setInterval(function () { var s = (Date.now() - t0) / 1000; if (s > 0.3) live(bytes * 8 / s / 1e6); }, 250);
    return Promise.all([stream(), stream(), stream()]).then(function () {
      clearInterval(timer);
      var s = (Math.min(Date.now(), end) - t0) / 1000;
      return s > 0 ? bytes * 8 / s / 1e6 : 0;
    }, function (e) { clearInterval(timer); throw e; });
  }
  function upload(job, seconds, live) {
    var block = new Uint8Array(2 * 1024 * 1024), bytes = 0, t0 = Date.now(), end = t0 + seconds * 1000;
    function next() {
      if (job.stopped || Date.now() >= end) return Promise.resolve();
      var sent = 0;
      var p = job.track(xhr('POST', SPEED + '/__up', block, {
        timeout: 20000,
        upProgress: function (e) {
          bytes += e.loaded - sent;
          sent = e.loaded;
          var s = (Date.now() - t0) / 1000;
          if (s > 0.3) live(bytes * 8 / s / 1e6);
          if (Date.now() >= end) { try { p.x.abort(); } catch (a) {} }
        }
      }));
      return p.then(function () { bytes += block.length - sent; return next(); }, function (e) { if (job.stopped || Date.now() < end - 500) throw e; });
    }
    return next().then(function () {
      var s = (Math.min(Date.now(), end) - t0) / 1000;
      return s > 0 ? bytes * 8 / s / 1e6 : 0;
    });
  }
  function verdict(mbps) {
    if (mbps >= 50) return 'Excellent: 4K streams play smoothly.';
    if (mbps >= 25) return 'Very good: Full HD and most 4K play smoothly.';
    if (mbps >= 10) return 'Good: HD channels play smoothly.';
    if (mbps >= 5) return 'Fair: SD and some HD channels.';
    return 'Slow: streams may buffer. Try a cable or move closer to the router.';
  }
  function mbit(v) { return v >= 100 ? String(Math.round(v)) : (Math.round(v * 10) / 10).toFixed(1); }

  var RING = 2 * Math.PI * 96;
  App.speedTest = function () {
    var box = U.el('div', 'spd');
    box.innerHTML =
      '<div class="gauge"><svg width="240" height="240" viewBox="0 0 240 240"><circle class="bg" cx="120" cy="120" r="96"></circle>' +
      '<circle class="fg" cx="120" cy="120" r="96" stroke-dasharray="' + RING.toFixed(1) + '" stroke-dashoffset="' + RING.toFixed(1) + '"></circle></svg>' +
      '<div class="val"><b class="num">0.0</b><span>Mbit/s</span><i></i></div></div>' +
      '<div class="stats"><div class="sb ping"><span>PING</span><b class="num">–</b><i>ms</i></div>' +
      '<div class="sb down"><span>DOWNLOAD</span><b class="num">–</b><i>Mbit/s</i></div>' +
      '<div class="sb up"><span>UPLOAD</span><b class="num">–</b><i>Mbit/s</i></div></div>' +
      '<div class="verdict dim"></div>';
    var fg = box.querySelector('.fg'), val = box.querySelector('.val b'), phase = box.querySelector('.val i'), say = box.querySelector('.verdict');
    var job = null, againBtn;
    function show(v) {
      val.textContent = mbit(v);
      var f = Math.max(0, Math.min(1, Math.log(1 + v) / Math.log(301)));
      fg.setAttribute('stroke-dashoffset', (RING * (1 - f)).toFixed(1));
    }
    function stat(cls, text) { box.querySelector('.sb.' + cls + ' b').textContent = text; }
    function run() {
      if (job) return;
      job = test({});
      var mine = job;
      stat('ping', '–'); stat('down', '–'); stat('up', '–');
      show(0);
      say.className = 'verdict dim';
      say.textContent = 'Testing… this takes about 15 seconds.';
      if (againBtn) againBtn.innerHTML = U.icon('refresh') + 'Testing…';
      phase.textContent = 'Ping';
      App.log('speed test');
      ping(mine).then(function (ms) {
        stat('ping', String(ms));
        phase.textContent = 'Download';
        return download(mine, 8, function (v) { if (!mine.stopped) show(v); });
      }).then(function (down) {
        stat('down', mbit(down));
        mine.down = down;
        phase.textContent = 'Upload';
        show(0);
        return upload(mine, 6, function (v) { if (!mine.stopped) show(v); });
      }).then(function (up) {
        stat('up', mbit(up));
        phase.textContent = 'Download';
        show(mine.down);
        say.className = 'verdict';
        say.textContent = verdict(mine.down);
        App.log('speed test: ' + mbit(mine.down) + ' down, ' + mbit(up) + ' up');
      }, function (e) {
        if (mine.stopped) return;
        App.log('speed test failed: ' + (e && e.message));
        say.className = 'verdict bad';
        say.textContent = 'The test could not reach the internet.';
      }).then(function () {
        if (job === mine) job = null;
        if (againBtn) againBtn.innerHTML = U.icon('refresh') + 'Test again';
      });
    }
    var d = UI.dialog({
      title: 'Internet speed test', html: box, width: 1060,
      buttons: [{ label: 'Test again', icon: 'refresh', keep: true, ok: run }, { label: 'Close', pri: true }], focus: 1,
      onClose: function () { if (job) { job.stop(); job = null; } running = null; }
    });
    d.box.querySelector('h2').innerHTML = U.icon('speed') + 'Internet speed test';
    againBtn = d.box.querySelectorAll('.acts .btn')[0];
    running = d;
    run();
    return d;
  };

  // ================================================================== clear cache
  /** As in the Android app: what was kept to be quick goes (the lists, the TV guide, the weather,
   *  the streaming lists); the playlist, favourites and settings stay. */
  App.clearCache = function () {
    UI.confirm('Clear cache?', 'The channel and film lists and the TV guide kept by the app load fresh from the server, and so do the weather and the streaming lists. ' +
      'Your playlist, favourites, profiles and settings stay. Use it when lists look old or the app feels slow.', 'Clear cache', 'Cancel', function () {
      var s = App.src;
      if (s) {
        if (s.cache) s.cache = {};
        if (s.catKeys) s.catKeys = [];
        if (s.pending) s.pending = {};
        s._guide = null;
        s.gmap = null;
        s.gconv = null;
        s.gfail = 0;
      }
      ['weather', 'where', 'svc_lists', 'demo_failed', 'log_prev'].forEach(function (k) { S.del(k); });
      App.log('cache cleared');
      UI.toast('Cache cleared: lists and the TV guide load fresh', 3200);
    });
  };

  // ================================================================== application info
  App.appInfo = function () {
    var rows = [
      ['Application', CONFIG.appName || ''],
      ['Version', (CONFIG.version || '—') + (CONFIG.build ? '  (build ' + CONFIG.build + ')' : '')],
      ['MAC Address', Backend.deviceId || '—'],
      ['Device Key', Backend.pairing || '—'],
      ['Licence', Backend.statusLine() || 'Unknown (no answer from the website yet)'],
      ['Expires', licEnd()],
      ['Playlist', App.title() || '—'],
      ['Video player', Player.engine === 'avplay' ? 'Samsung AVPlay' : 'The TV\'s standard player'],
      ['Profile', Profiles.active().n + (Store.kidsMode() ? ' (Kids)' : '')]
    ];
    var box = U.el('div', 'infobox2');
    function draw(tv) {
      var r = rows.slice();
      if (tv) r.push(['TV', [tv.manufacturer, tv.model].filter(function (s) { return s; }).join(' ') || '—'], ['System', tv.system || '—']);
      r.push(['Screen', Math.round(window.innerWidth) + ' × ' + Math.round(window.innerHeight)]);
      box.innerHTML = r.map(function (x) { return '<div class="row2"><span class="k">' + U.esc(x[0]) + '</span><span class="v">' + U.esc(x[1]) + '</span></div>'; }).join('');
    }
    draw(null);
    UI.dialog({ title: 'Application info', html: box, width: 1180, buttons: [{ label: 'Close', pri: true }] });
    App.tvInfo().then(draw);
  };
  function licEnd() {
    var l = Backend.lic || {};
    if (l.type === 'lifetime') return 'Lifetime (never ends)';
    if (l.status === 'expired') return 'Ended';
    if (l.status === 'suspended') return 'Suspended';
    var e = Backend.expiry();
    if (!e) return l.status ? 'Never' : '—';
    return e.getDate() + ' ' + U.months[e.getMonth()] + ' ' + e.getFullYear() + '  (' + Math.max(0, U.int(l.days)) + ' days left' + (l.status === 'trial' ? ', free trial' : '') + ')';
  }
})();
