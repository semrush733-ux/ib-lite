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

  function switchAccount(identity) {
    if (S.get('identity', '') === identity) return;
    ['live', 'vod', 'series'].forEach(function (k) { S.del('fav_' + k); S.del('recent_' + k); });
    S.del('resume');
    favCache = {};
    recentCache = {};
    resumeCache = null;
    S.set('identity', identity);
  }
  Store.save = function (s, site) {
    if (s.mode !== 'demo') switchAccount(s.mode === 'm3u' ? 'm3u|' + s.url : 'xtream|' + s.server + '|' + s.user);
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
  /** Demo content: its favourites and history are kept apart from the playlist's. */
  function ns() { return sess && sess.mode === 'demo' ? 'demo_' : ''; }
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
  Store.clearHistory = function () {
    ['live', 'vod', 'series'].forEach(function (k) { S.del('recent_' + k); S.del('demo_recent_' + k); });
    recentCache = {};
    S.del('resume');
    S.del('demo_resume');
    resumeCache = null;
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
  /** Live stream format: 'auto' (TV's own HLS first, MPEG-TS as fallback), 'm3u8' or 'ts'. */
  Store.liveFormat = function () { return S.get('live_format', 'auto'); };
  Store.setLiveFormat = function (v) { S.set('live_format', v); };
})();
