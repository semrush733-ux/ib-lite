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
    // One opaque picture (photo + colour wash made in advance: tvlite/tools/make_tv_backgrounds.py).
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
    el.appendChild(App.privacyButton('cn-pp'));

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
    UI.dialog({ title: App.t('My device'), html: html, width: 1060, buttons: [{ label: 'Close', pri: true }] });
  };

  /** This TV: maker, model and system (Samsung: Tizen version; LG: webOS version). Never fails. */
  App.tvInfo = function () {
    if (window.webapis && webapis.productinfo) {
      var out = { manufacturer: 'Samsung', model: '', system: 'Tizen' };
      try { var pi = webapis.productinfo; out.model = pi.getRealModel ? pi.getRealModel() : pi.getModel(); } catch (e) {}
      try { out.system = 'Tizen ' + tizen.systeminfo.getCapability('http://tizen.org/feature/platform.version'); } catch (e1) {}
      return Promise.resolve(out);
    }
    if (!window.PalmSystem) return Promise.resolve({ manufacturer: '', model: '', system: navigator.userAgent.slice(-60) });
    return App.luna('luna://com.webos.service.tv.systemproperty/getSystemInfo', { keys: ['modelName', 'sdkVersion', 'firmwareVersion'] }, 1500).then(function (r) {
      return { manufacturer: 'LG', model: (r && r.modelName) || '', system: r && r.sdkVersion ? 'webOS ' + r.sdkVersion : 'webOS', firmware: (r && r.firmwareVersion) || '' };
    }, function () { return { manufacturer: 'LG', model: '', system: 'webOS' }; });
  };

  // ------------------------------------------------------------------ Report a problem (as in the Android app)
  /** What went wrong goes to the website with the app's recent log, this TV's model and the last
   *  channel or film (never a password or a stream address). The admin reads it in the Admin Panel
   *  app (More → Problem reports) or in WordPress (Lite Player → Problem reports). */
  var REASONS = ['A channel does not play', 'Picture freezes or buffers', 'No sound or wrong language', 'A film or series does not play',
    'TV Guide is wrong or missing', 'The app is slow or closes', 'Something else'];
  function reasonText(r) { return App.t(r); }
  var reportSent = 0;
  function hostOf(url) { var m = /^https?:\/\/([^\/?#]+)/i.exec(String(url || '')); return m ? m[1].replace(/^[^@]*@/, '') : ''; }
  App.reportProblem = function () {
    App.log('report dialog');
    var reason = -1;
    var wrap = U.el('div', 'rep');
    wrap.innerHTML = '<div class="dim">' + U.esc(App.t("What went wrong? The app sends its recent log, this TV's model and the last channel or film to the support team. No password is sent.")) + '</div><div class="chips"></div><div class="fl"></div><div class="pinerr"></div>';
    var chips = wrap.querySelector('.chips'), err = wrap.querySelector('.pinerr');
    REASONS.forEach(function (r, i) {
      var c = U.el('span', 'chip f', U.esc(reasonText(r))); // the English reason goes to the website
      c._ok = function () {
        reason = i;
        for (var k = 0; k < chips.childNodes.length; k++) chips.childNodes[k].classList.toggle('sel', k === i);
      };
      chips.appendChild(c);
    });
    var note = UI.field({ icon: 'edit', placeholder: 'A note for the support team (optional)', submit: function () {} });
    note.input.maxLength = 300;
    wrap.querySelector('.fl').appendChild(note);
    var sending = false;
    var d = UI.dialog({
      title: App.t('Report a problem'), html: wrap, width: 1300,
      buttons: [{ label: App.t('Cancel') }, { label: App.t('Send'), icon: 'check', pri: true, keep: true, ok: send }],
      focusEl: chips.firstChild
    });
    function send() {
      if (sending) return;
      if (Date.now() - reportSent < 60000) { err.textContent = App.t('A report was sent a moment ago. Please wait a minute.'); return; }
      var text = U.str(note.value());
      if (reason < 0 && !text) { err.textContent = App.t('Choose what went wrong (or write a note).'); return; }
      sending = true;
      err.textContent = '';
      var btn = d.box.querySelector('.btn.pri');
      btn.innerHTML = '<span class="spin"></span>';
      var s = Store.session() || {};
      App.tvInfo().then(function (tv) {
        App.log('report send reason="' + (reason >= 0 ? REASONS[reason] : '') + '" note=' + text.length);
        return Backend.sendReport({
          reason: reason >= 0 ? REASONS[reason] : '', note: text,
          app_version: (CONFIG.version || '?') + ' (' + (CONFIG.build || 0) + ')',
          platform: CONFIG.platform || 'lg-tv', device: tv, stream: Player.lastStream(),
          playlist: Store.playlistName() || App.title() || '', server: hostOf(s.mode === 'm3u' ? s.url : s.server),
          language: 'en', profile: Store.profileId() + (Store.kidsMode() ? ' (kids)' : ''), log: App.logText()
        });
      }).then(function (answer) {
        reportSent = Date.now();
        d.close();
        var n = U.int(answer && answer.report_id);
        UI.message(App.t('Report sent'), (n > 0 ? App.t('Thank you. Your report number is') + ' ' + n + '.' : App.t('Thank you.')) + '\n' + App.t('The support team can see what happened on this TV.'));
      }, function (e) {
        sending = false;
        btn.innerHTML = U.icon('check') + U.esc(App.t('Send'));
        App.log('report failed: ' + (e && e.message));
        err.textContent = (e && e.message) || App.t('Could not send the report. Check the internet and try again.');
      });
    }
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
    var buttons = [{ label: 'Close', pri: true }];
    if (!Store.kidsMode()) buttons.unshift({ label: 'Change playlist', icon: 'playlist', ok: App.choosePlaylist });
    UI.dialog({ title: App.title() || 'Account', html: html, width: 1060, buttons: buttons, focus: buttons.length - 1 });
  };

  /** Playlists added on the website for this TV. */
  App.choosePlaylist = function () {
    var d = UI.dialog({ title: App.t('Playlists'), html: '<div class="pls"><span class="spin"></span>  Loading…</div>', width: 1000, buttons: [{ label: 'Close' }] });
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
  /** "Start with the last channel" is tried once, on the home screen the app starts with. */
  var lastChannelTried = false;

  /** boot: the home screen the app starts with (main.js). */
  Screens.Home = function (src, account, boot) {
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
      '<div class="hm-bottom"><div class="infobox"></div><div class="plbox"></div><div class="wbox"></div></div>';
    // One opaque picture (photo + wash + vignette made in advance: tvlite/tools/make_tv_backgrounds.py).
    var bgEl = el.querySelector('.hm-bg');
    function drawWallpaper() { bgEl.style.backgroundImage = 'url(' + App.wallpaperUrl(App.wallpaper()) + ')'; }
    drawWallpaper(); // Settings › Main Wallpaper

    // A Kids profile: no playlist change and no Catch Up (it lists every channel), as in the Android app.
    var kids = Store.kidsMode(), profile = Profiles.active();
    el.classList.toggle('kids', kids);
    var pills = el.querySelector('.hm-pills');
    function pill(icon, label, ok) {
      var p = U.el('span', 'pill f', '<span class="pi">' + U.icon(icon) + '</span><span class="pl">' + U.esc(label) + '</span>');
      p._ok = ok;
      pills.appendChild(p);
      return p;
    }
    // The profile in use (its colour and letter): "Who's watching?".
    var profBtn = U.el('span', 'pill prof f', Profiles.avatar(profile, 84));
    profBtn._ok = function () { Nav.push(new Screens.Profiles({ src: src })); };
    pills.appendChild(profBtn);
    var plPill = kids ? null : pill('playlist', shortName(App.title(), 'Change Playlist'), App.choosePlaylist);
    var setPill = pill('settings', App.t('Settings'), function () {
      if (kids) App.askPin('Parental PIN', function () { Nav.push(new Screens.Settings()); });
      else Nav.push(new Screens.Settings());
    });

    var icons = el.querySelector('.hm-icons');
    function sq(icon, ok) {
      var s = U.el('span', 'sq f', U.icon(icon));
      s._ok = ok;
      icons.appendChild(s);
      return s;
    }
    var reloadBtn = sq('sync', reload);
    sq('speed', function () { App.speedTest(); }); // as in the Android app
    sq('tv', App.deviceDialog);
    sq('person', function () { App.accountDialog(acc, offline); });
    /** Long names (a playlist, "Settings" in some languages): the pills get tighter, then the
     *  playlist's name shorter, then the Settings label, so everything stays in view. */
    function fitPills() {
      var labels = [].slice.call(pills.querySelectorAll('.pl'));
      pills.classList.remove('tight');
      labels.forEach(function (l) { l.style.maxWidth = ''; });
      function over() { return pills.scrollWidth - pills.clientWidth; }
      if (over() <= 0) return;
      pills.classList.add('tight');
      var pl = plPill && plPill.querySelector('.pl');
      if (pl && over() > 0) pl.style.maxWidth = Math.max(110, pl.offsetWidth - over() - 2) + 'px';
      var st = setPill && setPill.querySelector('.pl');
      if (st && over() > 0) st.style.maxWidth = Math.max(110, st.offsetWidth - over() - 2) + 'px';
    }

    var tiles = el.querySelector('.hm-tiles');
    function tile(icon, title, ok) {
      var t = U.el('div', 'tile f', '<div class="bgc"></div><div class="hi"></div><div class="shine"></div>' +
        '<div class="ti">' + U.icon(icon) + '</div><div class="tt">' + U.esc(title) + '</div><div class="bar"></div>');
      t._ok = ok;
      tiles.appendChild(t);
      return t;
    }
    var liveTile = tile('live', App.t('Live TV'), function () { Nav.push(new Screens.Browse(src, 'live')); });
    tile('movie', App.t('Movies'), function () { Nav.push(new Screens.Browse(src, 'vod')); });
    tile('series', App.t('Series', 'TV Series'), function () { Nav.push(new Screens.Browse(src, 'series')); });
    if (!kids) tile('catchup', App.t('Catch Up'), function () {
      if (src.type !== 'xtream') {
        UI.message(App.t('Catch Up'), 'Catch Up works with Xtream Codes playlists, where the server keeps recordings of past programmes. ' +
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

    // Continue Watching (as in the Android app): half-watched films and episodes, newest first,
    // between the tiles and the streaming boxes. OK plays on where it stopped; holding OK offers
    // "Play from the start" and "Remove from the row".
    var cwBox = U.el('div', 'hm-cw');
    cwBox.innerHTML = '<div class="cwh">' + U.esc(App.t('Continue Watching')) + '</div><div class="cws"></div>';
    el.appendChild(cwBox);
    var cwStrip = cwBox.querySelector('.cws'), cwShown = null, cwScroll = 0, cwBusy = false;
    var CW_VIEW = 1766; // the row's visible width (screen less the margins)
    function cwNote(c) {
      if (c.next) return 'Next episode';
      if (c.dur > 0) {
        var left = Math.ceil((c.dur - c.pos) / 60);
        if (left > 0) return left >= 60 ? Math.floor(left / 60) + ' h ' + (left % 60) + ' min left' : left + ' min left';
      }
      var m = Math.floor(c.pos / 60);
      return m >= 60 ? 'At ' + Math.floor(m / 60) + ' h ' + (m % 60) + ' min' : 'At ' + m + ' min';
    }
    function cwScrollTo(card) {
      var x = card.offsetLeft, w = card.offsetWidth;
      if (x - cwScroll < 0) cwScroll = x;
      else if (x + w - cwScroll > CW_VIEW) cwScroll = x + w - CW_VIEW;
      cwStrip.style.webkitTransform = cwStrip.style.transform = cwScroll ? 'translateX(' + (-cwScroll) + 'px)' : '';
    }
    function drawContinue() {
      // A Kids profile: only what its categories allow (they may have changed since).
      var list = Store.continueList().filter(function (c) { return Store.allowed(c.item); });
      var sig = list.map(function (c) { return c.key + ':' + c.pos + ':' + (c.next || 0); }).join(',');
      if (sig === cwShown) return;
      cwShown = sig;
      var hadKey = F.cur && cwStrip.contains(F.cur) ? F.cur._cwKey : null, back = null;
      cwStrip.innerHTML = '';
      cwScroll = 0;
      cwStrip.style.webkitTransform = cwStrip.style.transform = '';
      el.classList.toggle('cw', list.length > 0);
      list.forEach(function (c) {
        var card = U.el('div', 'cwc f', '<span class="pp">' + U.icon(c.ep ? 'series' : 'movie') + '<img alt=""></span>' +
          '<span class="t"></span><span class="s"></span><span class="pb"><i></i></span><span class="nt">' + U.icon(c.next ? 'next' : 'play') + '<b></b></span>');
        UI.setImg(card.querySelector('img'), c.img);
        card.querySelector('.t').textContent = c.t;
        card.querySelector('.s').textContent = c.s;
        card.querySelector('.pb i').style.width = (c.dur > 0 && !c.next ? Math.max(2, Math.min(100, Math.round(c.pos * 100 / c.dur))) : 0) + '%';
        card.querySelector('.nt b').textContent = cwNote(c);
        card._cwKey = c.key;
        card._ok = function () { playContinue(c, false); };
        card._long = function () { continueMenu(c); };
        card._focus = function () { cwScrollTo(card); };
        cwStrip.appendChild(card);
        if (c.key === hadKey) back = card;
      });
      // The focus was in the row: it stays there (on the same card, else the newest one).
      if (hadKey !== null) F.set(back || cwStrip.firstChild || liveTile);
    }
    function continueMenu(c) {
      UI.dialog({
        title: c.t, html: '<div class="dim" style="font-size:30px;line-height:1.5">' + (c.s ? U.esc(c.s) + '<br>' : '') + U.esc(cwNote(c)) + '</div>',
        width: 1100,
        buttons: [
          { label: 'Remove from the row', icon: 'del', ok: function () { Store.removeContinue(c.key); drawContinue(); } },
          { label: 'Play from the start', icon: 'replay', ok: function () { playContinue(c, true); } },
          { label: 'Continue', icon: 'play', pri: true, ok: function () { playContinue(c, false); } }
        ],
        focus: 2
      });
    }
    /** Plays a card where it stopped (or from the start). An episode plays with the rest of its
     *  season after it, as from the series page. */
    function playContinue(c, fromStart) {
      if (cwBusy) return;
      if (fromStart) Store.setResume(c.key, 0);
      var start = fromStart || c.next ? 0 : c.pos;
      App.log('continue watching ' + (c.ep ? 'episode' : 'film') + ' start=' + start);
      if (!c.ep) {
        Nav.push(new Screens.Player({
          src: src, kind: 'vod', urls: src.vodUrls ? src.vodUrls(c.item) : [src.vodUrl(c.item)], title: c.t, sub: c.s,
          poster: c.img, resumeKey: c.key, start: start, item: c.item
        }));
        return;
      }
      cwBusy = true;
      UI.toast('Opening "' + c.t + '"…', 9000);
      var done = false;
      function go(eps, i) {
        if (done) return;
        done = true;
        cwBusy = false;
        U.$('toast').innerHTML = '';
        if (Nav.top() !== self || UI.topDialog()) return; // the customer went somewhere else meanwhile
        Nav.push(new Screens.Player({ src: src, kind: 'episode', episodes: eps, index: i, title: c.t, poster: c.img, start: start, series: c.item }));
      }
      var waited = setTimeout(function () { go([c.ep], 0); }, 8000);
      src.seriesInfo(c.item.id).then(function (d) {
        clearTimeout(waited);
        var eps = [c.ep], idx = 0;
        (d && d.order || []).forEach(function (s) {
          var season = d.seasons[s] || [];
          for (var i = 0; i < season.length; i++) if (season[i].id === c.ep.id) { eps = season; idx = i; }
        });
        go(eps, idx);
      }, function () {
        clearTimeout(waited);
        go([c.ep], 0);
      });
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
      drawPlaylistBox();
      if (plPill) plPill.querySelector('.pl').textContent = shortName(App.title(), 'Change Playlist');
      fitPills();
    }
    /** Whole calendar days from today to the day the playlist ends (negative: ended). */
    function daysLeft(end) {
      var now = new Date();
      return Math.round((Date.UTC(end.getFullYear(), end.getMonth(), end.getDate()) -
        Date.UTC(now.getFullYear(), now.getMonth(), now.getDate())) / 86400000);
    }
    /** The playlist box between the device box and the clock (as in the Android app): its name with
     *  a dot (green fine, amber ends within a week, red ended / no connection), when it ends, and
     *  the days left with the connections (screens at once) it allows. */
    function drawPlaylistBox() {
      var GREEN = '#2ECC71', AMBER = '#FFC94A', RED = '#FF6B6B';
      var dot = GREEN, lines = [], name = App.title() || '—';
      if (!acc) {
        dot = offline ? RED : '#8B93A3';
        lines.push(offline ? ['No connection to the server', RED] : ['Checking the playlist…', '']);
        lines.push([offline ? 'Press Reload to try again' : 'One moment please', '#8B93A3']);
      } else if (src.type === 'm3u' || src.type === 'demo') {
        // M3U links (and the demo) carry no end date: what the list holds instead.
        var holds = String(acc.note || '').replace(/^M3U playlist\s*·\s*/, '');
        lines.push([src.type === 'demo' ? 'Playlist Expiry: Unlimited' : 'Playlist Expiry: not given (M3U link)', '']);
        lines.push([holds || 'M3U playlist', '']);
      } else {
        var e = acc.expires, parts = [], color = '';
        if (acc.trial) parts.push('Trial');
        if (!e) {
          lines.push(['Playlist Expiry: Unlimited', '']);
          if (!acc.trial) parts.push('Active');
        } else {
          lines.push(['Playlist Expiry: ' + U.days[e.getDay()] + ' ' + e.getDate() + ', ' + U.months[e.getMonth()] + ' ' + e.getFullYear(), '']);
          var d = daysLeft(e);
          parts.push(d < 0 ? 'Ended' : d === 0 ? 'Ends today' : d === 1 ? '1 day left' : d + ' days left');
          if (d < 0) { color = RED; dot = RED; } else if (d <= 7) { color = AMBER; dot = AMBER; }
        }
        if (acc.maxConnections > 0) parts.push(acc.maxConnections === 1 ? '1 connection' : acc.maxConnections + ' connections');
        lines.push([parts.join('  ·  '), color]);
      }
      var html = '<div class="ln"><i class="dot" style="background:' + dot + '"></i>Playlist: ' + U.esc(name) + '</div>';
      lines.forEach(function (l) { html += '<div class="ln"' + (l[1] ? ' style="color:' + l[1] + '"' : '') + '>' + U.esc(l[0]) + '</div>'; });
      el.querySelector('.plbox').innerHTML = html;
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

    // ---------------------------------------------------------------- start with the last channel
    /** Settings → "Start with the last channel" (as in the Android app): the channel watched last
     *  plays by itself when the app starts, with the other channels of its category around it
     *  (Up / Down go on from there); Back leaves it on the home screen. The home screen shows for
     *  a moment first, and a key pressed meanwhile means the customer goes somewhere else. */
    var keyEarly = false;
    function noteKey() { if (!App.blocked) keyEarly = true; }
    function startLastChannel() {
      var it = Store.recents('live')[0];
      if (!it || !Store.allowed(it)) return;
      document.addEventListener('keydown', noteKey, true);
      function done() { document.removeEventListener('keydown', noteKey, true); }
      var cat = it.c || '';
      Promise.all([
        cat ? src.items('live', cat).then(null, function () { return null; }) : Promise.resolve(null),
        cat ? src.categories('live').then(null, function () { return []; }) : Promise.resolve([])
      ]).then(function (r) {
        var items = r[0], name = '', idx = -1, i;
        (r[1] || []).forEach(function (c) { if (c.id === cat) name = c.name; });
        if (items) for (i = 0; i < items.length; i++) if (items[i].id === it.id) { idx = i; break; }
        if (idx < 0) {
          // Its category came but the channel is not in it any more: nothing to start.
          if (items && items.length) { App.log('last channel: no longer on the server'); done(); return; }
          items = [it];
          idx = 0;
        }
        // The start screen, a message or another window may be up first: wait for the home screen.
        var calm = 0, waited = 0;
        (function wait() {
          if (keyEarly || Nav.top() !== self) { done(); return; }
          if (App.blocked || UI.topDialog()) calm = 0; else calm += 250;
          waited += 250;
          if (calm < 750) { if (waited < 12000) setTimeout(wait, 250); else done(); return; }
          done();
          App.log('start with the last channel');
          Nav.push(new Screens.Player({
            src: src, kind: 'live', items: items, index: idx, title: name,
            onClose: function () { Player.stop(); Player.layout('off'); }
          }));
        })();
      });
    }

    this.show = function (first) {
      drawInfo();
      drawClock();
      drawSvc();
      drawContinue();
      if (first && boot && !lastChannelTried) {
        lastChannelTried = true;
        if (S.get('start_last_channel', false)) startLastChannel();
      }
      if (first) {
        F.set(liveTile);
        // The pills are measured again once the app's fonts are in (they are a little wider).
        try { if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { fitPills(); }); } catch (e) {}
        if (!acc) refreshAccount();
        timers.push(setTimeout(follow, 6000));
        timers.push(setInterval(follow, 5 * 60000));
        timers.push(setInterval(function () { var s = Store.session(); if (s && s.auto && App.inDemo()) follow(); }, 15000));
        timers.push(setInterval(function () { drawClock(); Weather.refresh().then(drawClock); }, 20000));
        Weather.refresh().then(drawClock);
        App.on('licence', onLicence);
        App.on('reload', onReload);
        App.on('wallpaper', drawWallpaper);
      } else if (pendingFollow) {
        pendingFollow = false;
        follow();
      }
    };
    this.destroy = function () {
      timers.forEach(function (t) { clearTimeout(t); clearInterval(t); });
      App.off('licence', onLicence);
      App.off('reload', onReload);
      App.off('wallpaper', drawWallpaper);
    };
  };

  // ================================================================== settings
  /** A window of choices, one row each: [label, names, chosen index, pick(i)] (Live / VOD Player). */
  App.choiceDialog = function (title, rows, note, done) {
    var wrap = U.el('div', 'choices'), first = null;
    rows.forEach(function (r) {
      var row = U.el('div', 'subrow', '<span class="k">' + U.esc(r[0]) + '</span>');
      r[1].forEach(function (name, i) {
        var c = U.el('span', 'chip f' + (i === r[2] ? ' sel' : ''), U.esc(name));
        c._ok = function () {
          if (r[3](i) === false) return; // the choice asked first and keeps the old one for now
          [].forEach.call(row.querySelectorAll('.chip'), function (x, k) { x.classList.toggle('sel', k === i); });
        };
        c._enter = function (dir) { F.set(dir === 'up' || dir === 'down' ? (row.querySelector('.chip.sel') || c) : c); };
        row.appendChild(c);
        if (!first && i === r[2]) first = c;
      });
      wrap.appendChild(row);
    });
    if (note) wrap.appendChild(U.el('div', 'kc-note', U.esc(note)));
    return UI.dialog({ title: title, html: wrap, width: 1500, buttons: [{ label: 'Done', pri: true }], focusEl: first, onClose: done });
  };

  /** Settings as boxes, as in the Android app (one box per section). */
  Screens.Settings = function () {
    this.name = 'settings';
    var el = this.el = screenEl();
    el.innerHTML = '<div class="br-bg"></div><div class="st-head">' + UI.logo(46) + '<h1>' + U.esc(App.t('Settings')) + '</h1>' +
      '<div class="ver"></div></div><div class="st-grid"></div>';
    el.querySelector('.ver').innerHTML = U.esc(CONFIG.appName) + '  ·  Version ' + U.esc(CONFIG.version || '') +
      (Backend.statusLine() ? '  ·  ' + U.esc(Backend.statusLine()) : '') + '<span class="tvinfo"></span>';
    // The privacy policy at any time (Samsung's privacy guide): Up from the first row of boxes.
    el.querySelector('.st-head').appendChild(App.privacyButton('pp-head'));
    var grid = el.querySelector('.st-grid');
    function rgba(hex, a) {
      var n = parseInt(hex.substring(1), 16);
      return 'rgba(' + ((n >> 16) & 255) + ',' + ((n >> 8) & 255) + ',' + (n & 255) + ',' + a + ')';
    }
    function box(icon, color, title, value, ok) {
      var b = U.el('div', 'sbox f', '<span class="si">' + U.icon(icon) + '</span><span class="lb">' + U.esc(title) + '</span><span class="vl2"></span>');
      b.style.background = 'linear-gradient(135deg, ' + rgba(color, 0.2) + ', #1B1416 72%)';
      b.querySelector('.si').style.color = color;
      b._ok = function () { ok(b); };
      b._val = function (v) { b.querySelector('.vl2').textContent = v || ''; };
      b._val(value);
      grid.appendChild(b);
      return b;
    }
    function onOff(v) { return v ? 'On' : 'Off'; }
    var FORMATS = { auto: 'Automatic (TV player, HLS first)', m3u8: 'HLS (m3u8)', ts: 'MPEG-TS (ts)' };
    var FORMAT_SHORT = { auto: 'Automatic', m3u8: 'HLS', ts: 'MPEG-TS' };
    var PLAYERS = { auto: 'Automatic (recommended)', standard: 'Standard', avplay: 'Samsung AVPlay' };
    var PLAYER_ORDER = ['auto', 'standard', 'avplay'];
    var FIT_NAMES = { fit: 'Fit', fill: 'Fill', stretch: 'Stretch' };
    /** Samsung: Automatic (each stream on the player that plays it), the TV's standard player or
     *  AVPlay (the app starts again to switch). */
    function playerRow() {
      var cur = Math.max(0, PLAYER_ORDER.indexOf(Player.choice()));
      return ['Video player', PLAYER_ORDER.map(function (k) { return PLAYERS[k]; }), cur, function (i) {
        var next = PLAYER_ORDER[i];
        if (next === Player.choice()) return true;
        UI.confirm('Video player: ' + PLAYERS[next] + '?', 'The app starts again to switch the player.', 'Switch', 'Cancel', function () {
          S.set('samsung_player', next);
          App.log('video player: ' + next);
          Player.stop();
          location.reload();
        });
        return false;
      }];
    }
    function pictureRow() {
      var fits = Player.fits();
      return ['Picture', fits.map(function (f) { return FIT_NAMES[f]; }), Math.max(0, fits.indexOf(Player.fit())), function (i) { Player.setFit(fits[i]); }];
    }

    // Row 1: as in the Android app.
    box('wifi', '#1E88FF', 'Network', '', function () { App.networkDialog(); });
    var liveBox = box('live', '#FF3B4E', App.t('Live Player'), FORMAT_SHORT[Store.liveFormat()] || FORMAT_SHORT.auto, function () {
      var order = ['auto', 'm3u8', 'ts'];
      var rows = [
        ['Live stream format', order.map(function (f) { return FORMATS[f]; }), Math.max(0, order.indexOf(Store.liveFormat())), function (i) {
          Store.setLiveFormat(order[i]);
          liveBox._val(FORMAT_SHORT[order[i]]);
        }],
        [App.t('Start with the last channel'), ['Off', 'On'], S.get('start_last_channel', false) ? 1 : 0, function (i) {
          S.set('start_last_channel', !!i);
          UI.toast(i ? 'When the app starts, the channel you watched last plays by itself' : 'The app starts on the home screen', 3000);
        }],
        pictureRow()
      ];
      if (Player.avplayAvailable) rows.push(playerRow());
      App.choiceDialog(App.t('Live Player'), rows, 'Live channels and the channel preview. Start with the last channel: the channel you watched last plays when the app starts, ' +
        'with the others of its category (Up / Down go on from there); Back takes you to the home screen.');
    });
    var vodBox = box('movie', '#FF8A00', App.t('VOD Player'), Player.avplayAvailable ? PLAYERS[Player.choice()].replace(' (recommended)', '') : 'The TV\'s player', function () {
      var rows = [pictureRow()];
      if (Player.avplayAvailable) rows.unshift(playerRow());
      App.choiceDialog(App.t('VOD Player'), rows, 'Movies and series play in the TV\'s own hardware player. Films carry on where you stopped; ' +
        'sound tracks, subtitles and the speed are in the player (OK, then the Sound button).');
    });
    function subLook() { return App.subLook.sizes[App.subLook.size()] + ', ' + App.subLook.colors[App.subLook.color()].toLowerCase(); }
    var subBox = box('cc', '#FACC15', App.t('Subtitles'), subLook(), function () { App.subtitleSettings(function () { subBox._val(subLook()); }); });
    var pinBox = box('kids', '#22C55E', App.t('Parental Control'), onOff(!!Store.pin()), function () { Nav.push(new Screens.CatChoice(App.src, 'lock')); });
    var profBox = box('groups', '#38BDF8', App.t('Profiles'), Profiles.active().n, function () { Nav.push(new Screens.Profiles({ src: App.src })); });
    // Row 2
    function wallName() { return App.wallpaper() ? '#' + App.wallpaper() : App.t('Default'); }
    var wallBox = box('wallpaper', '#D946EF', App.t('Main Wallpaper'), wallName(), function () { App.wallpaperDialog(function () { wallBox._val(wallName()); }); });
    box('apps', '#6366F1', App.t('Manage Categories'), '', function () { Nav.push(new Screens.CatChoice(App.src, 'hide')); });
    function svcCount() { var n = Streaming.enabled().length; return n ? n + ' on' : 'Off'; }
    var svcBox = box('video', '#EF4444', 'Streaming Boxes', svcCount(), function () { Streaming.dialog(function () { svcBox._val(svcCount()); }); });
    box('clean', '#8B5CF6', App.t('Clear Cache'), '', function () {
      UI.dialog({
        title: App.t('Clear Cache'), width: 1200,
        html: U.esc('The cache: the channel and film lists and the TV guide kept by the app load fresh from the server. ' +
          'The watch history: recently watched and the places where films were stopped (of the profile in use). ' +
          'Your playlist, favourites, profiles and settings stay.'),
        buttons: [{ label: 'Cancel' }, {
          label: 'Clear watch history', icon: 'history', ok: function () {
            UI.confirm('Clear watch history?', 'Recently watched and the places where films were stopped are removed.', 'Clear', 'Cancel', function () {
              Store.clearHistory();
              UI.toast('Watch history cleared');
            });
          }
        }, { label: App.t('Clear cache now'), icon: 'clean', pri: true, ok: function () { App.clearCache(); } }], focus: 2
      });
    });
    function langName() {
      var c = App.uiLanguage();
      if (c === 'auto') return App.t('Automatic (TV language)');
      for (var i = 0; i < I18N.langs.length; i++) if (I18N.langs[i][0] === c) return I18N.langs[i][2];
      return '';
    }
    box('lang', '#06B6D4', App.t('Language'), langName(), function () { App.languageDialog(); });
    box('info', '#F5B400', App.t('Application Info'), 'Version ' + (CONFIG.version || ''), function () { App.appInfo(); });
    // Row 3: the TV app's own.
    var plBox = box('playlist', '#E3262F', App.t('Playlists'), shortName(App.title(), ''), function () { App.choosePlaylist(); });
    box('tv', '#94A3B8', App.t('My device'), Backend.deviceId || '', App.deviceDialog);
    box('account', '#F472B6', 'Account', '', function () { App.accountDialog(App.account, false); });
    box('speed', '#10B981', 'Speed test', '', function () { App.speedTest(); });
    box('error', '#F97316', App.t('Report a problem'), '', function () { App.reportProblem(); });
    box('refresh', '#64748B', 'Restart the app', '', function () { App.restart(); });

    this.show = function (first) {
      if (!first) {
        pinBox._val(onOff(!!Store.pin()));
        profBox._val(Profiles.active().n);
        plBox._val(shortName(App.title(), ''));
        return;
      }
      F.set(grid.firstChild);
      if (window.webapis && webapis.productinfo) { // Samsung TV: model and Tizen version
        try {
          var pi = webapis.productinfo, t0 = el.querySelector('.tvinfo');
          var model = pi.getRealModel ? pi.getRealModel() : pi.getModel();
          var tz = '';
          try { tz = tizen.systeminfo.getCapability('http://tizen.org/feature/platform.version'); } catch (e1) {}
          if (t0) t0.textContent = [model, tz ? 'Tizen ' + tz : ''].filter(function (s) { return s; }).map(function (s) { return '  ·  ' + s; }).join('');
        } catch (e) {}
        return;
      }
      App.luna('luna://com.webos.service.tv.systemproperty/getSystemInfo', { keys: ['modelName', 'sdkVersion', 'firmwareVersion'] }, 1500).then(function (r) {
        if (!r) return;
        var t = el.querySelector('.tvinfo');
        if (t) t.textContent = [r.modelName, r.sdkVersion ? 'webOS ' + r.sdkVersion : ''].filter(function (s) { return s; }).map(function (s) { return '  ·  ' + s; }).join('');
      });
    };
  };
})();
