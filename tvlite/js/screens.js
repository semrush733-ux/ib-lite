/* Screens: playlist connect (QR), activation, home, settings, and their small windows. */
var Screens = {};

(function () {
  'use strict';

  function screenEl(cls) { return U.el('div', 'screen' + (cls ? ' ' + cls : '')); }
  function shortName(n, fallback) {
    n = U.str(n);
    if (!n) return fallback;
    return n.length > 22 ? n.substring(0, 21) + '…' : n;
  }
  App.title = function () { return Store.playlistName() || (App.src ? App.src.label() : ''); };

  // ================================================================== opening a playlist
  /** Opens a website playlist and shows the home screen (or reports the problem). */
  App.openPlaylist = function (p, quiet) {
    if (!quiet) UI.toast('Loading "' + p.name + '"…', 20000);
    return Src.open(p).then(function (r) {
      Store.save(Src.toSession(r.src), p);
      App.src = r.src;
      U.$('toast').innerHTML = '';
      Nav.reset(new Screens.Home(r.src, r.account));
      return true;
    }, function (e) {
      U.$('toast').innerHTML = '';
      throw e;
    });
  };

  // ================================================================== connect (QR)
  Screens.Connect = function (message) {
    var self = this;
    this.name = 'connect';
    var el = this.el = screenEl();
    var tried = false, opening = false, lists = [], timer = null, error = message || '';
    el.innerHTML =
      '<div class="cn-bg"></div>' +
      '<div class="cn-left">' + UI.logo(80) +
      '<h1>Add your playlist</h1><div class="sub">Your playlist is added on our website — no typing with the remote.</div>' +
      '<div class="steps"></div><div class="demo"></div><div class="err"></div><div class="plchoice"></div></div>' +
      '<div class="cn-right"><div class="qrbox"></div>' +
      '<div class="idrow"><span class="k">MAC Address:</span><span class="v mac">—</span></div>' +
      '<div class="idrow"><span class="k">Device Key:</span><span class="v key">—</span></div>' +
      '<div class="waitline"><span class="wl"></span><span class="wt">Waiting for your playlist…</span></div></div>';
    // One opaque picture (photo + colour wash made in advance: tools/make_tv_backgrounds.py).
    el.querySelector('.cn-bg').style.backgroundImage = 'url(img/connect_full.webp)';
    el.querySelector('.wl').appendChild(UI.pulse());
    var site = Backend.siteShort();
    el.querySelector('.steps').innerHTML =
      step(1, 'Scan the QR code with your phone, or open', site ? site + '/upload-playlist' : 'the website') +
      step(2, 'Your MAC Address and Device Key are filled in for you', '') +
      step(3, 'Add an M3U link or your Xtream Codes login', '') +
      step(4, 'The playlist appears on this TV by itself', '');
    function step(n, text, strong) {
      return '<div class="step"><span class="n">' + n + '</span>' + U.esc(text) + (strong ? '  <b>' + U.esc(strong) + '</b>' : '') + '</div>';
    }
    // No playlist yet: the built-in demo content plays at once (to try the player, or to film it).
    var demoBtn = U.el('span', 'btn f', U.icon('play') + 'Watch the 4K demo');
    demoBtn._ok = function () { if (!opening) App.openDemo(true); };
    el.querySelector('.demo').appendChild(demoBtn);
    el.querySelector('.demo').appendChild(U.el('span', 'dnote', 'No playlist yet? Try the player with built-in 4K channels, movies and series.'));

    var shownId = '';
    function drawIds() {
      el.querySelector('.mac').textContent = Backend.deviceId || '—';
      el.querySelector('.key').textContent = Backend.pairing || '—';
      var box = el.querySelector('.qrbox');
      var id = Backend.deviceId + '|' + Backend.pairing;
      if (id === shownId) return;
      shownId = id;
      box.innerHTML = '';
      if (!Backend.configured()) box.innerHTML = '<div class="wait">The website address is not set in this build yet.</div>';
      else if (!Backend.registered()) box.innerHTML = '<div class="wait">Connecting…</div>';
      else box.appendChild(UI.qr(Backend.uploadUrl(), 528));
    }
    function drawError() {
      el.querySelector('.err').innerHTML = error ? '<div class="errbox">' + U.esc(error) + '</div>' : '';
    }
    var choicesShown = false;
    function drawChoices() {
      var box = el.querySelector('.plchoice');
      var show = lists.length > 1 || (lists.length === 1 && tried && !opening);
      var had = F.cur && box.contains(F.cur), hadIdx = 0;
      if (had) for (var k = 1; k < box.childNodes.length; k++) if (box.childNodes[k] === F.cur) hadIdx = k - 1;
      if (!show) { box.innerHTML = ''; if (had) F.set(demoBtn); return; }
      // The first time the choices appear they take the focus; later the focus stays where it is.
      var first = !choicesShown;
      choicesShown = true;
      box.innerHTML = '<h3>Choose a playlist</h3>';
      lists.forEach(function (p, i) {
        var b = U.el('span', 'btn f', U.icon('playlist') + U.esc(p.name));
        b._ok = function () { open(p); };
        box.appendChild(b);
        if (had ? i === Math.min(hadIdx, lists.length - 1) : (i === 0 && (first || !F.cur))) F.set(b);
      });
    }
    function wait(text) { el.querySelector('.wt').textContent = text; }

    function open(p) {
      if (opening) return;
      opening = true;
      error = '';
      drawError();
      wait('Loading your playlist…');
      App.openPlaylist(p, true).then(function () {
        opening = false;
      }, function (e) {
        opening = false;
        error = '"' + p.name + '": ' + Src.friendly(e);
        drawError();
        wait('Waiting for your playlist…');
        drawChoices();
      });
    }
    function check() {
      if (opening || !Backend.configured()) return;
      Backend.ensureRegistered().then(function (ok) {
        drawIds();
        if (!ok) return null;
        return Backend.playlists();
      }).then(function (l) {
        if (!l || Nav.top() !== self) return;
        lists = l;
        drawChoices();
        if (l.length === 1 && !tried) {
          tried = true;
          open(l[0]);
        }
      }, function (e) {
        if (e && e.status === 403) App.emit('licence');
      });
    }
    this.show = function (first) {
      drawIds();
      drawError();
      if (!F.cur || !el.contains(F.cur)) F.set(demoBtn);
      if (first) {
        check();
        timer = setInterval(check, 5000);
      }
    };
    this.destroy = function () { clearInterval(timer); App.off('device', drawIds); };
    App.on('device', drawIds);
  };

  // ================================================================== activation (trial ended)
  Screens.Activation = function () {
    var self = this;
    this.name = 'activation';
    var el = this.el = screenEl();
    var suspended = Backend.lic.status === 'suspended';
    var busy = false, timer = null;
    el.innerHTML =
      '<div class="ac-left"><div class="in">' + UI.logo(70) +
      '<h2>' + (suspended ? 'This device is suspended.' : 'Your free trial has ended.') + '</h2>' +
      '<div class="s">' + (suspended ? 'Please contact support to restore access.' : 'Activate once and keep watching — no monthly fees.') + '</div>' +
      '<div class="devcard"><span class="q"></span><span class="ids"><div class="k">MAC ADDRESS</div><div class="v">' + U.esc(Backend.deviceId || '—') + '</div>' +
      '<div class="k">SCAN TO ACTIVATE</div><div class="v" style="font-size:28px;font-weight:600;color:#D5DAE3">' + U.esc(Backend.siteShort() + '/activation') + '</div></span></div>' +
      '</div></div>' +
      '<div class="ac-right"><div class="in"><h3>Activate this device</h3>' +
      '<div class="s">Get your code at  ' + U.esc(Backend.siteShort() + '/activation') + '</div><div class="er"></div><div class="fl"></div></div></div>';
    if (Backend.registered()) el.querySelector('.q').appendChild(UI.qr(Backend.activationUrl(), 272));
    var field = UI.field({ icon: 'key', placeholder: 'Activation code', submit: function () { activate(); } });
    el.querySelector('.fl').appendChild(field);
    var btn = U.el('div', 'btn pri f', 'Activate');
    btn._ok = activate;
    el.querySelector('.fl').appendChild(btn);

    function activate() {
      if (busy) return;
      var code = U.str(field.value());
      var er = el.querySelector('.er');
      if (!code) { er.innerHTML = '<div class="errbox">Please enter your activation code.</div>'; return; }
      busy = true;
      btn.innerHTML = '<span class="spin"></span>';
      F.set(btn);
      Backend.activate(code).then(function (err) {
        busy = false;
        btn.textContent = 'Activate';
        if (!err && Backend.allowed()) { App.restart(); return; }
        er.innerHTML = '<div class="errbox">' + U.esc(err || 'Activation did not complete. Please try again.') + '</div>';
      });
    }
    this.show = function (first) {
      if (!first) return;
      F.set(field);
      setTimeout(function () { Backend.refreshStatus().then(function () { if (Backend.allowed() && Nav.top() === self) App.restart(); }); }, 1000);
      timer = setInterval(function () {
        if (busy) return;
        Backend.refreshStatus().then(function () { if (Backend.allowed() && Nav.top() === self) App.restart(); });
      }, 20000);
    };
    this.destroy = function () { clearInterval(timer); };
  };

  // ================================================================== small windows
  App.deviceDialog = function () {
    var html = U.el('div');
    html.innerHTML = '<div style="white-space:nowrap"><span class="q" style="display:inline-block;vertical-align:middle;background:#fff;border-radius:16px;padding:12px"></span>' +
      '<span style="display:inline-block;vertical-align:middle;margin-left:40px">' +
      '<div class="dim" style="font-size:22px;letter-spacing:3px;font-weight:700">MAC ADDRESS</div><div style="font-size:40px;font-weight:800;margin:4px 0 20px">' + U.esc(Backend.deviceId || '—') + '</div>' +
      '<div class="dim" style="font-size:22px;letter-spacing:3px;font-weight:700">DEVICE KEY</div><div style="font-size:40px;font-weight:800;margin:4px 0 20px">' + U.esc(Backend.pairing || '—') + '</div>' +
      '<div class="dim" style="font-size:26px">' + U.esc(Backend.statusLine() || '') + '</div></span></div>' +
      '<div class="dim" style="font-size:26px;margin-top:24px">Scan the code to add or change playlists on ' + U.esc(Backend.siteShort()) + '</div>';
    if (Backend.registered()) {
      var c = UI.qr(Backend.uploadUrl(), 260);
      c.style.display = 'block';
      html.querySelector('.q').appendChild(c);
    }
    UI.dialog({ title: 'My device', html: html, width: 1060, buttons: [{ label: 'Close', pri: true }] });
  };

  function fmtDate(d) { return d.getDate() + ' ' + U.months[d.getMonth()] + ' ' + d.getFullYear(); }
  App.accountDialog = function (account, offline) {
    var src = App.src;
    var a = account;
    function row(k, v) { return '<div class="row2"><span class="k">' + U.esc(k) + '</span><span class="v">' + U.esc(v) + '</span></div>'; }
    var html = row('Playlist', src && src.type === 'xtream' ? 'Xtream Codes' : src && src.type === 'demo' ? 'Demo content (built into the app)' : 'M3U') +
      row('Status', !a ? (offline ? 'No connection' : 'Checking…') : (a.trial ? 'Trial' : 'Active')) +
      row('Expires', !a ? '—' : (a.expires ? fmtDate(a.expires) : 'Never')) +
      (a && a.note ? row('Note', a.note) : '') +
      (a && a.maxConnections ? row('Connections', String(a.maxConnections)) : '') +
      row('App', Backend.statusLine() || '—');
    UI.dialog({
      title: App.title() || 'Account', html: html, width: 1060,
      buttons: [{ label: 'Change playlist', icon: 'playlist', ok: App.choosePlaylist }, { label: 'Close', pri: true }], focus: 1
    });
  };

  /** Playlists added on the website for this TV. */
  App.choosePlaylist = function () {
    var d = UI.dialog({ title: 'Playlists', html: '<div class="pls"><span class="spin"></span>  Loading…</div>', width: 1000, buttons: [{ label: 'Close' }] });
    var demo = App.inDemo();
    function demoChoice(box, focus) {
      var label = Backend.demo ? U.esc(Backend.demo.name) + '  <span class="dim">(demo)</span>' : 'Demo 4K content  <span class="dim">(built into the app)</span>';
      var b = U.el('div', 'opt f' + (demo ? ' sel' : ''), U.icon(demo ? 'radioOn' : 'radioOff') + label);
      b._ok = function () {
        d.close();
        if (!demo) App.openDemo(false);
      };
      box.appendChild(b);
      if (focus || demo) F.set(b);
    }
    Backend.playlists().then(function (lists) {
      var box = d.body.querySelector('.pls');
      if (!box) return;
      box.innerHTML = '';
      if (!lists.length) {
        box.innerHTML = '<div class="dim" style="margin-bottom:14px">No playlists yet. Add one on ' + U.esc(Backend.siteShort()) + '/upload-playlist</div>';
        demoChoice(box, true);
        return;
      }
      var cur = Store.session() && !demo ? Store.session().pid : 0;
      lists.forEach(function (p, i) {
        var b = U.el('div', 'opt f' + (p.id === cur ? ' sel' : ''), U.icon(p.id === cur ? 'radioOn' : 'radioOff') + U.esc(p.name));
        b._ok = function () {
          d.close();
          if (p.id === cur && App.src) return; // already open
          App.openPlaylist(p).then(null, function (e) { UI.message('Playlist', '"' + p.name + '": ' + Src.friendly(e)); });
        };
        box.appendChild(b);
        if (i === 0 || p.id === cur) F.set(b);
      });
      demoChoice(box, false);
    }, function (e) {
      var box = d.body.querySelector('.pls');
      if (!box) return;
      box.innerHTML = '<div class="errbox" style="margin:0 0 14px">' + U.esc(e.message || 'No connection.') + '</div>';
      demoChoice(box, true);
    });
  };

  // ================================================================== weather (place, time, temperature)
  var Weather = { city: '', country: '', temp: null, day: true, at: 0 };
  (function () {
    var w = S.get('weather', null);
    if (w) U.extend(Weather, w);
  })();
  Weather.refresh = function () {
    if (Date.now() - Weather.at < 30 * 60000) return Promise.resolve();
    Weather.at = Date.now();
    var where = S.get('where', null);
    var p = where && Date.now() - where.at < 12 * 3600000 ? Promise.resolve(where) :
      Net.json('https://ipwho.is/?fields=success,city,country,latitude,longitude', { timeout: 8000, quiet: true }).then(function (d) {
        if (!d || d.success === false) throw new Error('no place');
        var r = { city: d.city || '', country: d.country || '', lat: d.latitude, lon: d.longitude, at: Date.now() };
        S.set('where', r);
        return r;
      });
    return p.then(function (r) {
      Weather.city = r.city;
      Weather.country = r.country;
      return Net.json('https://api.open-meteo.com/v1/forecast?latitude=' + r.lat + '&longitude=' + r.lon + '&current=temperature_2m,is_day', { timeout: 8000, quiet: true });
    }).then(function (d) {
      var c = d && d.current;
      if (c) {
        Weather.temp = U.num(c.temperature_2m);
        Weather.day = U.int(c.is_day) === 1;
      }
      S.set('weather', { city: Weather.city, country: Weather.country, temp: Weather.temp, day: Weather.day, at: Weather.at });
    }).then(null, function () {});
  };

  // ================================================================== home
  Screens.Home = function (src, account) {
    var self = this;
    this.name = 'home';
    App.src = src;
    var el = this.el = screenEl();
    var acc = account || null, offline = false, timers = [], refreshing = false, pendingFollow = false;
    App.account = acc;
    el.innerHTML =
      '<div class="hm-bg"></div>' +
      '<div class="hm-top">' + UI.logo(60) + '<div class="hm-pills"></div><div class="hm-icons"></div></div>' +
      '<div class="hm-tiles"></div>' +
      '<div class="hm-bottom"><div class="infobox"></div><div class="expiry"></div><div class="wbox"></div></div>';
    // One opaque picture (photo + wash + vignette made in advance: tools/make_tv_backgrounds.py).
    el.querySelector('.hm-bg').style.backgroundImage = 'url(img/home_full.webp)';

    var pills = el.querySelector('.hm-pills');
    function pill(icon, label, ok) {
      var p = U.el('span', 'pill f', '<span class="pi">' + U.icon(icon) + '</span><span class="pl">' + U.esc(label) + '</span>');
      p._ok = ok;
      pills.appendChild(p);
      return p;
    }
    var plPill = pill('playlist', shortName(App.title(), 'Change Playlist'), App.choosePlaylist);
    pill('settings', 'Settings', function () { Nav.push(new Screens.Settings()); });

    var icons = el.querySelector('.hm-icons');
    function sq(icon, ok) {
      var s = U.el('span', 'sq f', U.icon(icon));
      s._ok = ok;
      icons.appendChild(s);
      return s;
    }
    var reloadBtn = sq('sync', reload);
    sq('tv', App.deviceDialog);
    sq('person', function () { App.accountDialog(acc, offline); });

    var tiles = el.querySelector('.hm-tiles');
    function tile(icon, title, ok) {
      var t = U.el('div', 'tile f', '<div class="bgc"></div><div class="hi"></div><div class="shine"></div>' +
        '<div class="ti">' + U.icon(icon) + '</div><div class="tt">' + U.esc(title) + '</div><div class="bar"></div>');
      t._ok = ok;
      tiles.appendChild(t);
      return t;
    }
    var liveTile = tile('live', 'Live TV', function () { Nav.push(new Screens.Browse(src, 'live')); });
    tile('movie', 'Movies', function () { Nav.push(new Screens.Browse(src, 'vod')); });
    tile('series', 'TV Series', function () { Nav.push(new Screens.Browse(src, 'series')); });
    tile('catchup', 'Catch Up', function () {
      if (src.type !== 'xtream') {
        UI.message('Catch Up', 'Catch Up works with Xtream Codes playlists, where the server keeps recordings of past programmes. ' +
          (src.type === 'demo' ? 'The demo content has no recordings.' : 'An M3U playlist link does not carry recordings.'));
        return;
      }
      Nav.push(new Screens.Browse(src, 'live', 'catchup'));
    });

    // Streaming boxes (Settings → Streaming boxes) between the tiles and the information.
    var svcRow = U.el('div', 'hm-svc');
    el.appendChild(svcRow);
    var svcShown = '';
    function drawSvc() {
      var list = Streaming.enabled();
      var sig = list.map(function (s) { return s.id; }).join(',');
      if (sig === svcShown) return;
      svcShown = sig;
      var had = F.cur && svcRow.contains(F.cur);
      svcRow.innerHTML = '';
      el.classList.toggle('svc', list.length > 0);
      var n = list.length, w = n ? Math.floor((1766 - (n - 1) * 24) / n) : 0;
      svcRow.classList.toggle('compact', n > 5);
      list.forEach(function (s) {
        var b = U.el('div', 'svcbox f', U.icon('video') + '<span class="nm">' + U.esc(s.name) + '</span><span class="sb">Movies &amp; Series</span>');
        b.style.width = Math.min(330, w) + 'px';
        b._ok = function () { Nav.push(new Screens.Streaming(src, s)); };
        svcRow.appendChild(b);
      });
      if (had) F.set(liveTile);
    }

    function appExpiry() {
      if (Backend.lic.type === 'lifetime') return 'Lifetime';
      var e = Backend.expiry();
      if (!e) return Backend.statusLine() || '—';
      return e.getFullYear() + '-' + U.two(e.getMonth() + 1) + '-' + U.two(e.getDate()) + (Backend.lic.status === 'trial' ? '  (free trial)' : '');
    }
    function drawInfo() {
      el.querySelector('.infobox').innerHTML =
        'MAC Address: ' + U.esc(Backend.deviceId || '—') + '<br>Device Key: ' + U.esc(Backend.pairing || '—') +
        '<br>Application Expiry: ' + U.esc(appExpiry());
      var ex = el.querySelector('.expiry');
      var text;
      if (!acc) text = offline ? 'Playlist: no connection' : 'Playlist: checking…';
      else if (acc.note) text = acc.note;
      else if (!acc.expires) text = 'Playlist Expiry: Unlimited';
      else {
        var e = acc.expires;
        text = 'Playlist Expiry: ' + U.days[e.getDay()] + ' ' + e.getDate() + ', ' + U.months[e.getMonth()] + ' ' + e.getFullYear();
      }
      ex.textContent = text;
      ex.style.color = offline && !acc ? '#FF6B6B' : '';
      plPill.querySelector('.pl').textContent = shortName(App.title(), 'Change Playlist');
    }
    function drawClock() {
      var now = new Date();
      var place = [Weather.city, Weather.country].filter(function (s) { return s; }).join(', ');
      var date = U.days[now.getDay()].substring(0, 3) + ', ' + now.getDate() + '.' + U.months[now.getMonth()] + ' ' + now.getFullYear();
      el.querySelector('.wbox').innerHTML =
        '<div class="pl">' + (place ? U.icon('loc') + U.esc(place) : U.esc(date)) + '</div>' +
        '<span class="sun" style="color:' + (Weather.day ? '#FFC94A' : '#8FB4FF') + '">' + U.icon(Weather.day ? 'sun' : 'moon') + '</span>' +
        (place ? '<div>' + U.esc(date) + '</div>' : '') +
        '<div class="big num">' + U.hm(now) + '</div>' +
        (Weather.temp != null ? '<div class="tmp num">' + Weather.temp.toFixed(1) + '°</div>' : '');
    }

    function refreshAccount() {
      return src.login().then(function (a) {
        acc = a;
        App.account = a;
        offline = false;
        drawInfo();
      }, function (e) {
        if (e && e.auth) {
          Store.logout();
          Nav.reset(new Screens.Connect(e.message));
          return;
        }
        offline = true;
        drawInfo();
      });
    }

    /** The playlist on the website may have changed (new server, new login) or been removed. */
    function follow() {
      var s = Store.session();
      if (s && (s.mode === 'demo' || s.demo)) return followDemo(s);
      if (!s || !s.pid || !Backend.configured()) return Promise.resolve();
      return Backend.playlists().then(function (lists) {
        var p = null;
        for (var i = 0; i < lists.length; i++) if (lists[i].id === s.pid) p = lists[i];
        if (Nav.top() !== self || Player.active()) { pendingFollow = !p || Store.sig(p) !== s.psig; return; }
        if (!p) {
          if (!lists.length) {
            App.log('playlist removed on the website: none left');
            Store.logout();
            Nav.reset(new Screens.Connect('This playlist was removed. Scan the QR code or add a playlist on the website.'));
            return;
          }
          App.log('playlist removed on the website: opening another');
          App.openPlaylist(lists[0], true).then(null, function () {});
          return;
        }
        if (!s.psig) { s.psig = Store.sig(p); S.set('session', s); return; }
        if (Store.sig(p) === s.psig) return;
        App.log('playlist changed on the website: reopening');
        App.openPlaylist(p, true).then(null, function () {});
      }, function () {});
    }

    /** While the demo is open: a demo opened from the start screen gives way to the first playlist
     *  added on the website; a demo changed on the website (set, new link, removed) opens again. */
    function followDemo(s) {
      if (!Backend.configured()) return Promise.resolve();
      return Backend.playlists().then(function (lists) {
        var away = Nav.top() !== self || Player.active();
        if (s.auto && lists.length) {
          if (away) { pendingFollow = true; return; }
          App.log('playlist added on the website: leaving the demo');
          App.openPlaylist(lists[0]).then(null, function (e) {
            s.auto = false; // asked once; the Playlists window still has it
            S.set('session', s);
            UI.message('Playlist', '"' + lists[0].name + '": ' + Src.friendly(e));
          });
          return;
        }
        var want = Backend.demo ? Store.sig(Backend.demo) : 'builtin';
        var have = s.mode === 'demo' ? 'builtin' : s.psig;
        if (want === have || want === S.get('demo_failed', '')) return;
        if (away) { pendingFollow = true; return; }
        App.log('demo changed on the website: opening it again');
        App.openDemo(!!s.auto);
      }, function () {});
    }

    function reload() {
      if (refreshing) return;
      refreshing = true;
      reloadBtn.innerHTML = U.icon('hourglass');
      Promise.all([follow(), refreshAccount(), Backend.refreshStatus(), Backend.loadConfig()]).then(function () {
        refreshing = false;
        reloadBtn.innerHTML = U.icon('sync');
        drawInfo();
      });
    }
    function onLicence() { if (Nav.top() === self) drawInfo(); }
    function onReload() { App.log('reload asked by the admin panel'); reload(); }

    this.show = function (first) {
      drawInfo();
      drawClock();
      drawSvc();
      if (first) {
        F.set(liveTile);
        if (!acc) refreshAccount();
        timers.push(setTimeout(follow, 6000));
        timers.push(setInterval(follow, 5 * 60000));
        timers.push(setInterval(function () { var s = Store.session(); if (s && s.auto && App.inDemo()) follow(); }, 15000));
        timers.push(setInterval(function () { drawClock(); Weather.refresh().then(drawClock); }, 20000));
        Weather.refresh().then(drawClock);
        App.on('licence', onLicence);
        App.on('reload', onReload);
      } else if (pendingFollow) {
        pendingFollow = false;
        follow();
      }
    };
    this.destroy = function () {
      timers.forEach(function (t) { clearTimeout(t); clearInterval(t); });
      App.off('licence', onLicence);
      App.off('reload', onReload);
    };
  };

  // ================================================================== settings
  Screens.Settings = function () {
    this.name = 'settings';
    var el = this.el = screenEl();
    el.innerHTML = '<div class="br-bg"></div><div class="st-side">' + UI.logo(46) + '<h1>Settings</h1><div class="ver"></div></div><div class="st-main"></div>';
    el.querySelector('.ver').innerHTML = U.esc(CONFIG.appName) + '<br>Version ' + U.esc(CONFIG.version || '') +
      '<br>' + U.esc(Backend.statusLine() || '') + '<br><span class="tvinfo"></span>';
    var main = el.querySelector('.st-main');
    var FORMATS = { auto: 'Automatic (TV player, HLS first)', m3u8: 'HLS (m3u8)', ts: 'MPEG-TS (ts)' };
    function row(icon, label, value, ok) {
      var r = U.el('div', 'srow f', U.icon(icon) + '<span class="lb">' + U.esc(label) + '</span><span class="vl2">' + (value || '') + '</span>');
      r._ok = function () { ok(r); };
      main.appendChild(r);
      return r;
    }
    row('playlist', 'Playlists', U.esc(shortName(App.title(), '')) + U.icon('chevR'), function () { App.choosePlaylist(); });
    row('live', 'Live stream format', U.esc(FORMATS[Store.liveFormat()] || FORMATS.auto), function (r) {
      var order = ['auto', 'm3u8', 'ts'];
      var next = order[(order.indexOf(Store.liveFormat()) + 1) % order.length];
      Store.setLiveFormat(next);
      r.querySelector('.vl2').textContent = FORMATS[next];
      UI.toast('Live channels: ' + FORMATS[next]);
    });
    // Samsung: the TV's standard player, or Samsung's AVPlay (for streams the standard one does not open).
    if (Player.avplayAvailable) {
      var PLAYERS = { standard: 'Standard (recommended)', avplay: 'Samsung AVPlay' };
      row('play', 'Video player', U.esc(PLAYERS[S.get('samsung_player', 'standard')] || PLAYERS.standard), function () {
        var next = S.get('samsung_player', 'standard') === 'avplay' ? 'standard' : 'avplay';
        UI.confirm('Video player: ' + PLAYERS[next] + '?', 'The app starts again to switch the player.', 'Switch', 'Cancel', function () {
          S.set('samsung_player', next);
          App.log('video player: ' + next);
          Player.stop();
          location.reload();
        });
      });
    }
    row('tv', 'My device', U.esc(Backend.deviceId || '') + U.icon('chevR'), App.deviceDialog);
    row('person', 'Account', U.icon('chevR'), function () { App.accountDialog(App.account, false); });
    function svcCount() { var n = Streaming.enabled().length; return (n ? n + ' on' : 'Off') + U.icon('chevR'); }
    var svcRow = row('video', 'Streaming boxes', svcCount(), function () {
      Streaming.dialog(function () { svcRow.querySelector('.vl2').innerHTML = svcCount(); });
    });
    row('history', 'Clear watch history', '', function () {
      UI.confirm('Clear watch history?', 'Recently watched and the places where films were stopped are removed.', 'Clear', 'Cancel', function () {
        Store.clearHistory();
        UI.toast('Watch history cleared');
      });
    });
    row('refresh', 'Restart the app', '', function () { App.restart(); });
    this.show = function (first) {
      if (!first) return;
      if (window.webapis && webapis.productinfo) { // Samsung TV: model and Tizen version
        try {
          var pi = webapis.productinfo, t0 = el.querySelector('.tvinfo');
          var model = pi.getRealModel ? pi.getRealModel() : pi.getModel();
          var tz = '';
          try { tz = tizen.systeminfo.getCapability('http://tizen.org/feature/platform.version'); } catch (e1) {}
          if (t0) t0.textContent = [model, tz ? 'Tizen ' + tz : ''].filter(function (s) { return s; }).join(' · ');
        } catch (e) {}
        return;
      }
      App.luna('luna://com.webos.service.tv.systemproperty/getSystemInfo', { keys: ['modelName', 'sdkVersion', 'firmwareVersion'] }, 1500).then(function (r) {
        if (!r) return;
        var t = el.querySelector('.tvinfo');
        if (t) t.textContent = [r.modelName, r.sdkVersion ? 'webOS ' + r.sdkVersion : ''].filter(function (s) { return s; }).join(' · ');
      });
    };
  };
})();
