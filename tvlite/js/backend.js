/* The website (WordPress plugin): device registration, licence, playlists, messages and app look.
 * Also the on-TV storage of the playlist in use, favourites, recently watched and resume points. */
var Backend = {}, Store = {};

(function () {
  'use strict';

  // ------------------------------------------------------------------ tiny event bus
  var subs = {};
  App.on = function (name, fn) { (subs[name] = subs[name] || []).push(fn); };
  App.off = function (name, fn) {
    var l = subs[name] || [];
    var i = l.indexOf(fn);
    if (i >= 0) l.splice(i, 1);
  };
  App.emit = function (name, v) {
    var l = (subs[name] || []).slice();
    for (var i = 0; i < l.length; i++) { try { l[i](v); } catch (e) { App.log('ERROR ' + name + ': ' + e.message); } }
  };

  // ------------------------------------------------------------------ webOS system services
  var bridges = [];
  /** Asks the TV (webOS Luna service); null when not on a TV or no answer. */
  App.luna = function (uri, params, ms) {
    return new Promise(function (resolve) {
      var done = false;
      function fin(v) { if (!done) { done = true; resolve(v); } }
      setTimeout(function () { fin(null); }, ms || 2000);
      try {
        if (typeof PalmServiceBridge === 'undefined') { fin(null); return; }
        var b = new PalmServiceBridge();
        bridges.push(b);
        if (bridges.length > 20) bridges.shift();
        b.onservicecallback = function (msg) {
          try { fin(JSON.parse(msg)); } catch (e) { fin(null); }
        };
        b.call(uri, JSON.stringify(params || {}));
      } catch (e) { fin(null); }
    });
  };

  function isRealMac(mac) {
    var m = String(mac || '').toUpperCase().replace(/-/g, ':');
    if (!/^([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(m)) return '';
    if (m === '00:00:00:00:00:00' || m === '02:00:00:00:00:00' || m === 'FF:FF:FF:FF:FF:FF') return '';
    if (parseInt(m.substring(0, 2), 16) & 0x02) return '';
    return m;
  }

  /** The TV's own identifiers, so the website recognises it after the app is installed again. */
  Backend.ids = function () {
    // Samsung TV (Tizen): its unique id (DUID) and the MAC of its network connection.
    if (window.webapis && (webapis.productinfo || webapis.network)) {
      var t = {};
      try {
        var duid = webapis.productinfo && webapis.productinfo.getDuid();
        if (duid) t.hwid = 'sm-' + String(duid).substring(0, 60);
      } catch (e) {}
      try {
        var tmac = isRealMac(webapis.network && webapis.network.getMac());
        if (tmac) t.mac = tmac;
      } catch (e2) {}
      return Promise.resolve(t);
    }
    return Promise.all([
      App.luna('luna://com.webos.service.sm/deviceid/getIDs', { idType: ['LGUDID'] }, 2000),
      App.luna('luna://com.webos.service.connectionmanager/getinfo', {}, 2000)
    ]).then(function (r) {
      var out = {};
      try {
        var list = (r[0] && r[0].idList) || [];
        for (var i = 0; i < list.length; i++) if (list[i].idValue) { out.hwid = 'lg-' + String(list[i].idValue).substring(0, 60); break; }
      } catch (e) {}
      try {
        var wired = r[1] && r[1].wiredInfo && r[1].wiredInfo.macAddress;
        var wifi = r[1] && r[1].wifiInfo && r[1].wifiInfo.macAddress;
        var mac = isRealMac(wired) || isRealMac(wifi);
        if (mac) out.mac = mac;
      } catch (e2) {}
      return out;
    });
  };

  // ------------------------------------------------------------------ website address and device
  var DEFAULT_BASE = String(CONFIG.apiBase || '').replace(/\/+$/, '');
  function validBase(v) { return /^https:\/\/[^\/]+\/.*wp-json\//.test(v || ''); }
  Backend.base = DEFAULT_BASE;
  (function () {
    var moved = S.get('api_base', ''), from = S.get('api_base_from', '');
    if (validBase(moved) && from === DEFAULT_BASE) Backend.base = moved;
  })();
  Backend.configured = function () { return !!Backend.base; };
  Backend.site = function () {
    var i = Backend.base.indexOf('/wp-json/');
    return i > 0 ? Backend.base.substring(0, i) : Backend.base;
  };
  Backend.siteShort = function () { return Backend.site().replace(/^https?:\/\//, ''); };

  Backend.deviceId = S.get('device_id', '');
  Backend.pairing = S.get('pairing', '');
  if (!Backend.deviceId) {
    // The previous version of the app on this TV: same MAC Address, Device Key and licence.
    var oid = S.old('b1g_device_id'), opair = S.old('b1g_pairing');
    if (oid && opair) {
      Backend.deviceId = String(oid).replace(/^B1G-/, 'CLT-');
      Backend.pairing = String(opair);
      S.set('device_id', Backend.deviceId);
      S.set('pairing', Backend.pairing);
      App.log('device taken over from the previous app version');
    }
  }
  Backend.registered = function () { return !!(Backend.deviceId && Backend.pairing); };

  var lic = S.get('lic', null);
  if (!lic) {
    var os = S.old('b1g_lic_status');
    lic = { status: os || '', type: S.old('b1g_lic_type') || '', days: S.old('b1g_lic_days') || 0, checked: S.old('b1g_lic_checked') || 0 };
  }
  Backend.lic = lic;
  Backend.server = S.get('server', null) || { url: '', name: '' };

  Backend.allowed = function () { return lic.status !== 'expired' && lic.status !== 'suspended'; };
  Backend.expiry = function () {
    if (lic.type === 'lifetime' || lic.type === 'free') return null;
    if (lic.status !== 'trial' && lic.status !== 'active') return null;
    return new Date((lic.checked || Date.now()) + Math.max(0, lic.days) * 86400000);
  };
  Backend.statusLine = function () {
    switch (lic.status) {
      case 'trial': return lic.days > 0 ? 'Free trial · ' + lic.days + ' days left' : 'Free trial';
      case 'active':
        if (lic.type === 'lifetime') return 'Activated · Lifetime';
        if (lic.type === 'free') return 'Free';
        return lic.days > 0 ? 'Activated · ' + lic.days + ' days left' : 'Activated';
      case 'expired': return 'Trial ended';
      case 'suspended': return 'Device suspended';
    }
    return '';
  };
  // Colons may stay as they are in a link (a shorter QR code, the same as the Android app's).
  function qv(v) { return encodeURIComponent(v).replace(/%3A/gi, ':'); }
  Backend.uploadUrl = function () {
    return Backend.site() + '/upload-playlist/?device_id=' + qv(Backend.deviceId) + '&pairing_code=' + qv(Backend.pairing);
  };
  Backend.activationUrl = function () {
    return Backend.site() + '/activation/?device_id=' + qv(Backend.deviceId);
  };

  function failure(msg, status, code) {
    var e = new Error(msg);
    e.status = status || 0;
    e.code = code || '';
    return e;
  }
  function call(method, path, body) {
    if (!Backend.base) return Promise.reject(failure('The website address is not set in this build.'));
    return Net.req(method, Backend.base + path, body, { timeout: 15000 }).then(function (r) {
      var data = null;
      try { data = JSON.parse(r.text); } catch (e) { throw failure('Unexpected answer from the server.', r.status); }
      if (data && data.success === true) return data;
      var m = data && data.message ? String(data.message) : 'Request failed (' + r.status + ').';
      throw failure(m, r.status, data && data.code ? String(data.code) : '');
    });
  }
  function q(path) {
    return path + (path.indexOf('?') >= 0 ? '&' : '?') + 'device_id=' + encodeURIComponent(Backend.deviceId) +
      '&pairing_code=' + encodeURIComponent(Backend.pairing);
  }

  function storeStatus(d) {
    if (!d || typeof d !== 'object') return;
    var before = lic.status + '/' + lic.type + '/' + lic.days;
    lic.status = U.str(d.status);
    lic.type = U.str(d.licence_type);
    lic.days = U.int(d.days_left);
    lic.checked = Date.now();
    S.set('lic', lic);
    if (before !== lic.status + '/' + lic.type + '/' + lic.days) App.emit('licence');
  }

  var registering = null;
  Backend.ensureRegistered = function () {
    if (Backend.registered()) return Promise.resolve(true);
    if (registering) return registering;
    registering = Backend.ids().then(function (ids) {
      App.log('register (mac ' + (ids.mac ? 'yes' : 'no') + ', tv id ' + (ids.hwid ? 'yes' : 'no') + ')');
      var body = { platform: CONFIG.platform || 'lg-tv' };
      if (ids.mac) body.mac = ids.mac;
      if (ids.hwid) body.hwid = ids.hwid;
      return call('POST', '/device/register', body);
    }).then(function (data) {
      var d = data.device || {};
      Backend.deviceId = U.str(d.device_id);
      Backend.pairing = U.str(d.pairing_code);
      if (!Backend.registered()) return false;
      S.set('device_id', Backend.deviceId);
      S.set('pairing', Backend.pairing);
      storeStatus(d);
      App.emit('device');
      return true;
    }).then(function (ok) { registering = null; return ok; }, function (e) {
      registering = null;
      App.log('register failed: ' + e.message);
      return false;
    });
    return registering;
  };

  /** "Report a problem": the report goes to the website (Admin Panel → Problem reports). */
  Backend.sendReport = function (report) {
    return Backend.ensureRegistered().then(function (ok) {
      if (!ok) throw failure('This TV is not known to the website yet. Restart the app and try again.');
      return call('POST', '/device/report', U.extend({ device_id: Backend.deviceId, pairing_code: Backend.pairing }, report));
    });
  };

  /** App look, the default server, a moved website, "clear cache". Never fails. */
  Backend.loadConfig = function () {
    return call('GET', '/app/config?platform=' + encodeURIComponent(CONFIG.platform || 'lg-tv') +
      '&version_code=' + (CONFIG.build || 0) + '&device_id=' + encodeURIComponent(Backend.deviceId)).then(function (data) {
      var c = data.config || {};
      Backend.server = { url: U.str(c.server_url), name: U.str(c.server_name) };
      S.set('server', Backend.server);
      var moveTo = U.str(c.api_base);
      if (validBase(moveTo) && moveTo !== Backend.base) {
        App.log('website moved to a new address');
        Backend.base = moveTo;
        S.set('api_base', moveTo);
        S.set('api_base_from', DEFAULT_BASE);
      }
      Brand.apply(c.brand);
      App.emit('config');
    }, function (e) { App.log('config: ' + e.message); });
  };

  Backend.refreshStatus = function () {
    return Backend.ensureRegistered().then(function (ok) {
      if (!ok) return;
      return call('GET', q('/device/status')).then(function (data) { storeStatus(data.device); });
    }).then(null, function (e) { App.log('status: ' + e.message); });
  };

  /** Playlists added on the website for this TV. Rejects (status 403) when the licence is not active. */
  Backend.playlists = function () {
    return Backend.ensureRegistered().then(function (ok) {
      if (!ok) throw failure('No connection to the server.');
      return call('GET', q('/device/playlists'));
    }).then(function (data) {
      storeStatus(data.device);
      // The demo set on the website (App Settings), or null: the app's built-in demo videos.
      var d = data.demo;
      Backend.demo = d && U.str(d.url) ? {
        id: 0, name: U.str(d.name) || 'Demo', type: U.str(d.type) === 'xtream' ? 'xtream' : 'm3u',
        url: U.str(d.url), username: U.str(d.username), password: U.str(d.password), epg: U.str(d.epg_url)
      } : null;
      Backend.demoAt = Date.now();
      var out = [], raw = data.playlists || [];
      for (var i = 0; i < raw.length; i++) {
        var j = raw[i] || {};
        var url = U.str(j.url);
        if (!url) continue;
        out.push({
          id: U.int(j.id), name: U.str(j.name) || 'Playlist', type: U.str(j.type) === 'xtream' ? 'xtream' : 'm3u',
          url: url, username: U.str(j.username), password: U.str(j.password), epg: U.str(j.epg_url)
        });
      }
      return out;
    }, function (e) {
      if (e.status === 403) storeStatus({ status: lic.status === 'suspended' ? 'suspended' : 'expired', licence_type: lic.type, days_left: 0 });
      throw e;
    });
  };

  /** The website's daily lists of the streaming services' titles ({} when it has none). */
  Backend.streamingLists = function () {
    return call('GET', '/app/streaming').then(function (d) {
      return d && d.services && typeof d.services === 'object' ? d.services : {};
    }, function (e) {
      if (e.status === 404) return {};
      throw e;
    });
  };

  Backend.activate = function (code) {
    return Backend.ensureRegistered().then(function (ok) {
      if (!ok) return 'No connection to the activation server. Please check the internet and try again.';
      return call('POST', '/device/activate', { device_id: Backend.deviceId, code: U.str(code) }).then(function (data) {
        storeStatus(data.device);
        return null;
      }, function (e) { return e.message; });
    });
  };

  /** Messages from the provider's Admin Panel, and the "reload" command. */
  Backend.pollInbox = function () {
    if (!Backend.registered() || !Backend.base) return Promise.resolve([]);
    return call('GET', q('/device/inbox')).then(function (data) {
      storeStatus(data.device);
      var items = data.items || [], shown = [], ids = [];
      for (var i = 0; i < items.length; i++) {
        var it = items[i] || {}, id = U.int(it.id);
        if (id <= 0) continue;
        ids.push(id);
        if (it.kind === 'refresh') App.emit('reload');
        else if (it.kind === 'message') shown.push({ title: U.str(it.title), body: U.str(it.body) });
      }
      if (ids.length) call('POST', '/device/inbox/seen', { device_id: Backend.deviceId, pairing_code: Backend.pairing, ids: ids }).then(null, function () {});
      return shown;
    }, function () { return []; });
  };

  // ------------------------------------------------------------------ on-TV storage (Store)
  function fromOld(key, def) { var v = S.old(key); return v == null ? def : v; }

  var sess = S.get('session', null);
  if (!sess && fromOld('logged_in', false)) {
    // Playlist in use in the previous app version.
    if (fromOld('mode', '') === 'm3u' && fromOld('m3u_url', '')) {
      sess = { mode: 'm3u', url: fromOld('m3u_url', ''), epg: fromOld('m3u_epg_url', '') };
    } else if (fromOld('server', '') && fromOld('username', '') && fromOld('password', '')) {
      sess = { mode: 'xtream', server: fromOld('server', ''), user: fromOld('username', ''), pass: fromOld('password', '') };
    }
    if (sess) {
      sess.pid = U.int(fromOld('playlist_id', 0));
      sess.pname = fromOld('playlist_name', '') || '';
      sess.psig = fromOld('playlist_sig', '') || '';
      S.set('session', sess);
      S.set('identity', fromOld('identity', ''));
      ['live', 'vod', 'series'].forEach(function (k) {
        var f = S.old('fav_' + k), r = S.old('recent_' + k), list;
        if (f && f.length) {
          list = [];
          f.forEach(function (raw) { try { list.push(JSON.parse(raw)); } catch (e) {} });
          S.set('fav_' + k, list);
        }
        if (r && r.length) {
          list = [];
          r.forEach(function (raw) { try { list.push(JSON.parse(raw)); } catch (e) {} });
          S.set('recent_' + k, list);
        }
      });
      try { var res = JSON.parse(S.old('resume') || '{}'); if (res) S.set('resume', res); } catch (e) {}
      App.log('playlist taken over from the previous app version');
    }
  }

  Store.session = function () { return sess; };
  Store.playlistName = function () { return (sess && sess.pname) || ''; };

  /** Removes every stored value whose key (without "lt_") passes the test. */
  function forget(test) {
    try {
      var keys = [];
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (k && k.indexOf('lt_') === 0 && test(k.substring(3))) keys.push(k);
      }
      keys.forEach(function (k) { localStorage.removeItem(k); });
    } catch (e) {}
  }
  /** Favourites, recent, resume points and Continue Watching (of any profile), the category order
   *  and the categories for children: they belong to one playlist account. */
  function accountKey(k) {
    var base = k.replace(/^p_[^_]+_/, '');
    return /^(fav_|recent_|catorder_|kids_|hidden_|locked_)/.test(base) || base === 'resume' || base === 'continue' || base === 'reminders';
  }
  function switchAccount(identity) {
    if (S.get('identity', '') === identity) return;
    forget(function (k) { return k.indexOf('demo_') !== 0 && accountKey(k); });
    favCache = {};
    recentCache = {};
    resumeCache = null;
    cwCache = null;
    kidsCache = null;
    catCache = {};
    S.set('identity', identity);
  }
  Store.save = function (s, site) {
    if (s.mode !== 'demo' && !s.demo) switchAccount(s.mode === 'm3u' ? 'm3u|' + s.url : 'xtream|' + s.server + '|' + s.user);
    sess = U.extend({}, s);
    sess.pid = site ? site.id : 0;
    sess.pname = site ? site.name : '';
    sess.psig = site ? Store.sig(site) : '';
    S.set('session', sess);
  };
  Store.sig = function (p) { return p.url + '|' + p.username + '|' + p.password; };
  Store.logout = function () {
    sess = null;
    S.del('session');
  };

  var favCache = {}, recentCache = {}, resumeCache = null;
  /** Demo content: its lists are kept apart from the playlist's. */
  function acctNs() { return sess && (sess.mode === 'demo' || sess.demo) ? 'demo_' : ''; }
  /** Every profile has its own favourites, recently watched, resume points and Continue Watching;
   *  the main profile keeps the keys the app always used. */
  function ns() { var p = Store.profileId(); return acctNs() + (p === 'main' ? '' : 'p_' + p + '_'); }
  Store.favs = function (kind) {
    var k = ns() + 'fav_' + kind;
    if (!favCache[k]) favCache[k] = S.get(k, []) || [];
    return favCache[k];
  };
  Store.isFav = function (it) {
    var l = Store.favs(it.k);
    for (var i = 0; i < l.length; i++) if (l[i].id === it.id) return true;
    return false;
  };
  Store.toggleFav = function (it) {
    var l = Store.favs(it.k);
    for (var i = 0; i < l.length; i++) {
      if (l[i].id === it.id) { l.splice(i, 1); S.set(ns() + 'fav_' + it.k, l); return false; }
    }
    l.unshift(it);
    S.set(ns() + 'fav_' + it.k, l);
    return true;
  };
  Store.recents = function (kind) {
    var k = ns() + 'recent_' + kind;
    if (!recentCache[k]) recentCache[k] = S.get(k, []) || [];
    return recentCache[k];
  };
  Store.addRecent = function (it) {
    var l = Store.recents(it.k);
    for (var i = l.length - 1; i >= 0; i--) if (l[i].id === it.id) l.splice(i, 1);
    l.unshift(it);
    if (l.length > 30) l.length = 30;
    S.set(ns() + 'recent_' + it.k, l);
  };
  /** Settings → Clear watch history: of the profile in use. */
  Store.clearHistory = function () {
    var pre = ns(), other = pre.indexOf('demo_') === 0 ? pre.substring(5) : 'demo_' + pre;
    [pre, other].forEach(function (n) {
      ['live', 'vod', 'series'].forEach(function (k) { S.del(n + 'recent_' + k); });
      S.del(n + 'resume');
      S.del(n + 'continue');
    });
    recentCache = {};
    resumeCache = null;
    cwCache = null;
  };
  function resumes() {
    var k = ns() + 'resume';
    if (!resumeCache || resumeCache.k !== k) resumeCache = { k: k, m: S.get(k, {}) || {} };
    return resumeCache.m;
  }
  Store.resume = function (key) { return U.int(resumes()[key]); };
  Store.setResume = function (key, sec) {
    var m = resumes();
    delete m[key];
    if (sec > 0) m[key] = Math.floor(sec);
    var keys = Object.keys(m);
    while (keys.length > 300) delete m[keys.shift()];
    S.set(resumeCache.k, m);
  };

  // ------------------------------------------------------------------ Continue Watching
  /** Half-watched films and episodes for the row on the home screen, newest first, at most 20 (as in
   *  the Android app). A card: {key: 'vod:<id>' or 'ep:<id>' (the resume key), t: the film's or the
   *  series' name, s: 'S1 E3  ·  title' or the film's year and genre, img, pos and dur in seconds
   *  (dur 0: not known yet), at, item: the film or the series, ep: the episode, next: 1 for the
   *  episode after one watched to the end (not started yet)}. A series has one card: its latest. */
  var cwCache = null;
  function cwList() {
    var k = ns() + 'continue';
    if (!cwCache || cwCache.k !== k) cwCache = { k: k, l: S.get(k, []) || [] };
    return cwCache.l;
  }
  function cwSave() {
    if (cwCache.l.length > 20) cwCache.l.length = 20;
    S.set(cwCache.k, cwCache.l);
  }
  /** Takes out the card with this key, and with seriesId every card of that series. */
  function cwDrop(l, key, seriesId) {
    for (var i = l.length - 1; i >= 0; i--) {
      var c = l[i];
      if (c.key === key || (seriesId && c.ep && c.item && c.item.id === seriesId)) l.splice(i, 1);
    }
  }
  Store.epLabel = function (e) { return 'S' + e.season + ' E' + e.num + (e.title ? '  ·  ' + e.title : ''); };
  Store.continueList = function () { return cwList().slice(); };
  Store.removeContinue = function (key) {
    cwDrop(cwList(), key, null);
    cwSave();
  };
  /** The player tells where a film or an episode got to. w: {key, t, s, img, item, ep}. */
  Store.noteContinue = function (w, pos, dur) {
    if (!w || !w.key || !w.item) return;
    var l = cwList(), i;
    pos = Math.floor(pos || 0);
    dur = Math.floor(dur || 0);
    if (dur > 60 && pos > dur * 0.95) { Store.finishContinue(w, null); return; }
    if (pos < 30) {
      // Only a few seconds in: no new card, but a card that is there keeps the right place.
      for (i = 0; i < l.length; i++) {
        if (l[i].key !== w.key) continue;
        l[i].pos = pos;
        if (dur > 0) l[i].dur = dur;
        cwSave();
      }
      return;
    }
    cwDrop(l, w.key, w.ep ? w.item.id : null);
    var c = { key: w.key, t: w.t || w.item.n || '', s: w.s || '', img: w.img || w.item.i || '', pos: pos, dur: dur, at: Date.now(), item: w.item };
    if (w.ep) c.ep = w.ep;
    l.unshift(c);
    cwSave();
  };
  /** Watched to the end: its card goes, and the episode after it (next) gets a "Next episode" card. */
  Store.finishContinue = function (w, next) {
    if (!w || !w.key) return;
    var l = cwList();
    cwDrop(l, w.key, null);
    if (next && w.ep && w.item) {
      cwDrop(l, 'ep:' + next.id, w.item.id);
      l.unshift({ key: 'ep:' + next.id, t: w.t || w.item.n || '', s: Store.epLabel(next), img: w.img || w.item.i || '', pos: 0, dur: 0,
        at: Date.now(), item: w.item, ep: next, next: 1 });
    }
    cwSave();
  };
  /** The customer's own order of categories (hold OK on a category and move it), per kind. */
  /** TV Guide reminders (js/guide.js): for the playlist account, not per profile. */
  Store.reminders = function () { return S.get(acctNs() + 'reminders', []) || []; };
  Store.setReminders = function (l) { if (l && l.length) S.set(acctNs() + 'reminders', l); else S.del(acctNs() + 'reminders'); };
  Store.catOrder = function (kind) { return S.get(acctNs() + 'catorder_' + kind, []) || []; };
  Store.setCatOrder = function (kind, ids) { S.set(acctNs() + 'catorder_' + kind, ids); };
  /** Categories in that order: the moved ones where they were put, new ones after them. */
  Store.sortCats = function (kind, list) {
    var order = Store.catOrder(kind);
    if (!order.length) return list;
    var rank = {};
    order.forEach(function (id, i) { rank[id] = i; });
    var known = list.filter(function (c) { return rank.hasOwnProperty(c.id); });
    known.sort(function (a, b) { return rank[a.id] - rank[b.id]; });
    return known.concat(list.filter(function (c) { return !rank.hasOwnProperty(c.id); }));
  };

  // ------------------------------------------------------------------ profiles (as in the Android app)
  /** The profiles of this TV: [{id, n: name, c: colour number, k: 1 for Kids}]; "main" is always there. */
  Store.profileList = function () { return S.get('profiles', []) || []; };
  Store.saveProfiles = function (list) { S.set('profiles', list); };
  Store.profileId = function () { return S.get('profile_active', 'main') || 'main'; };
  /** A Kids profile is in use: only categories for children are shown. */
  var kidsNow = null; // read once: the lists ask for every channel
  Store.kidsMode = function () { if (kidsNow === null) kidsNow = !!S.get('profile_kids', false); return kidsNow; };
  Store.useProfile = function (id, kids) {
    S.set('profile_active', id || 'main');
    S.set('profile_kids', !!kids);
    kidsNow = !!kids;
    // Locked choices ask for the PIN again in the new profile.
    Store.parentalUnlocked = false;
  };
  /** Ask "Who's watching?" when the app starts (only with more than one profile). */
  Store.askProfile = function () { return S.get('profile_ask', true) !== false; };
  Store.setAskProfile = function (v) { S.set('profile_ask', !!v); };
  /** Forgets everything a deleted profile had saved. */
  Store.forgetProfile = function (id) {
    if (!id || id === 'main') return;
    forget(function (k) { return k.indexOf('p_' + id + '_') === 0 || k.indexOf('demo_p_' + id + '_') === 0; });
    favCache = {};
    recentCache = {};
    resumeCache = null;
    cwCache = null;
  };

  // ------------------------------------------------------------------ parental PIN
  /** The PIN that keeps children in the Kids profile (and out of Settings there); '' = none. */
  var pinNow = null;
  Store.pin = function () { if (pinNow === null) pinNow = S.get('parental_pin', '') || ''; return pinNow; };
  Store.setPin = function (p) {
    pinNow = p ? String(p) : '';
    if (p) S.set('parental_pin', pinNow); else S.del('parental_pin');
    Store.parentalUnlocked = false;
  };
  /** The PIN was typed since the app started (or the profile changed). */
  Store.parentalUnlocked = false;

  // ------------------------------------------------------------------ categories for the Kids profile
  // Found by their names (Kids, Cartoons, Family, Disney…) whenever the categories load; the parent
  // can switch any category on or off for children by hand (Profiles → Kids categories). Per account.
  var KIDS = /(^|[^a-z0-9])(kids?|child|children|childrens|cartoons?|toons?|junior|jr|family|families|disney|pixar|dreamworks|nick|nickelodeon|nickjr|cbeebies|cbbc|boomerang|baby|babies|kinder|kinderen|enfants?|infantil|infantiles|bambini|dzieci|cocuk|çocuk|animation|animated|animados?|animación|animacion|dibujos)($|[^a-z0-9])/i;
  var ADULT = /(adult|xxx|18\+|\+18|porn|sex|erot|for adults)/i;
  Store.looksForKids = function (name) { name = String(name || ''); return KIDS.test(name) && !ADULT.test(name); };
  var kidsCache = null;
  function kidsSets(kind) {
    var n = acctNs();
    if (!kidsCache || kidsCache.n !== n) kidsCache = { n: n };
    if (!kidsCache[kind]) {
      kidsCache[kind] = { auto: S.get(n + 'kids_auto_' + kind, []) || [], on: S.get(n + 'kids_on_' + kind, []) || [], off: S.get(n + 'kids_off_' + kind, []) || [] };
    }
    return kidsCache[kind];
  }
  function has(list, id) { return list.indexOf(id) >= 0; }
  /** Called whenever a category list arrives: the categories for children are noted by name. */
  Store.noteCategories = function (kind, cats) {
    var auto = cats.filter(function (c) { return Store.looksForKids(c.name); }).map(function (c) { return c.id; });
    var sets = kidsSets(kind);
    if (auto.join('\n') === sets.auto.join('\n')) return;
    sets.auto = auto;
    S.set(acctNs() + 'kids_auto_' + kind, auto);
  };
  /** May children see this category? The parent's choice first, else its name. */
  Store.kidsAllowed = function (kind, id) {
    var s = kidsSets(kind);
    if (has(s.off, id)) return false;
    if (has(s.on, id)) return true;
    return has(s.auto, id);
  };
  /** true / false: chosen by hand; null: follows its name. */
  Store.kidsChoice = function (kind, id) {
    var s = kidsSets(kind);
    return has(s.on, id) ? true : has(s.off, id) ? false : null;
  };
  Store.setKidsChoice = function (kind, id, v) {
    var s = kidsSets(kind), n = acctNs();
    s.on = s.on.filter(function (x) { return x !== id; });
    s.off = s.off.filter(function (x) { return x !== id; });
    if (v === true) s.on.push(id);
    if (v === false) s.off.push(id);
    S.set(n + 'kids_on_' + kind, s.on);
    S.set(n + 'kids_off_' + kind, s.off);
  };
  Store.resetKidsChoices = function (kind) {
    var n = acctNs();
    S.del(n + 'kids_on_' + kind);
    S.del(n + 'kids_off_' + kind);
    if (kidsCache) delete kidsCache[kind];
  };
  /** Left out of the app: in a Kids profile every category that is not for children. */
  // ------------------------------------------------------------------ hidden and locked categories
  // Settings → Manage categories (hidden everywhere) and Parental control (behind the PIN). Per account.
  var catCache = {};
  function catSet(name, kind) {
    var k = acctNs() + name + '_' + kind;
    if (!catCache[k]) {
      var l = S.get(k, []) || [], m = {};
      l.forEach(function (id) { m[id] = 1; });
      catCache[k] = { l: l, m: m };
    }
    return catCache[k];
  }
  function setCat(name, kind, id, on) {
    var k = acctNs() + name + '_' + kind;
    var l = catSet(name, kind).l.filter(function (x) { return x !== id; });
    if (on) l.push(id);
    if (l.length) S.set(k, l); else S.del(k);
    delete catCache[k];
  }
  Store.isHiddenSetting = function (kind, id) { return !!catSet('hidden', kind).m[id]; };
  Store.setHidden = function (kind, id, v) { setCat('hidden', kind, id, v); };
  Store.isLockMarked = function (kind, id) { return !!catSet('locked', kind).m[id]; };
  Store.setLocked = function (kind, id, v) { setCat('locked', kind, id, v); };
  /** Behind the PIN (only while a PIN is set). */
  Store.isLocked = function (kind, id) { return !!Store.pin() && Store.isLockMarked(kind, id); };
  /** Left out of the app: hidden in Manage categories, and in a Kids profile every category not for children. */
  Store.isHidden = function (kind, catId) { return Store.isHiddenSetting(kind, catId) || (Store.kidsMode() && !Store.kidsAllowed(kind, catId)); };
  /** May this channel / film / series be listed? (its category is not hidden) */
  Store.allowed = function (it) {
    if (!it) return true;
    if (Store.isHidden(it.k, it.c)) return false;
    return Store.parentalUnlocked || !Store.isLocked(it.k, it.c);
  };

  /** Movies / Series order: 'default' (as the server sends them), 'new', 'az', 'year', 'rating'. */
  Store.sortOrder = function (kind) { return S.get('sort_' + kind, 'default') || 'default'; };
  Store.setSortOrder = function (kind, v) { S.set('sort_' + kind, v); };

  /** Live stream format: 'auto' (TV's own HLS first, MPEG-TS as fallback), 'm3u8' or 'ts'. */
  Store.liveFormat = function () { return S.get('live_format', 'auto'); };
  Store.setLiveFormat = function (v) { S.set('live_format', v); };
})();
