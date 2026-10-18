/* Where channels, movies and series come from: an Xtream Codes login or an M3U playlist link.
 * Items are kept small: {k: kind, id, n: name, i: picture, c: category, e: file type, r: rating,
 * num, u: address (M3U), g: guide id (M3U), a: 1 when the server keeps recordings}. */
var Src = {};

(function () {
  'use strict';

  var KINDS = ['live', 'vod', 'series'];
  var ACTIONS = {
    live: ['get_live_categories', 'get_live_streams'],
    vod: ['get_vod_categories', 'get_vod_streams'],
    series: ['get_series_categories', 'get_series']
  };

  function list(data) {
    if (!data) return [];
    if (Object.prototype.toString.call(data) === '[object Array]') return data;
    if (typeof data === 'object') {
      var out = [];
      for (var k in data) if (data[k] && typeof data[k] === 'object') out.push(data[k]);
      return out;
    }
    return [];
  }

  /** Year of a film or series: the server's year / release date, else the name ("Title (2021)",
   *  "Title [2021]", "Title - 2021"); 0 when none is found. */
  var ANY_YEAR = /(?:19|20)\d{2}/, YEAR_BRACKETS = /[(\[]\s*((?:19|20)\d{2})\s*[)\]]/, YEAR_DASH = /\s[-–|]\s*((?:19|20)\d{2})\s*$/;
  function plausible(y) { return y >= 1900 && y <= new Date().getFullYear() + 1; }
  function yearInName(name) {
    var m = YEAR_BRACKETS.exec(name) || YEAR_DASH.exec(name);
    var y = m ? parseInt(m[1], 10) : 0;
    return plausible(y) ? y : 0;
  }
  Src.yearInName = yearInName;
  function yearOf(m, name) {
    var keys = ['year', 'releaseDate', 'release_date', 'releasedate'];
    for (var i = 0; i < keys.length; i++) {
      var hit = ANY_YEAR.exec(U.str(m[keys[i]]));
      if (hit && plausible(parseInt(hit[0], 10))) return parseInt(hit[0], 10);
    }
    return yearInName(name);
  }

  function itemFrom(kind, m) {
    var id = U.str(kind === 'series' ? m.series_id : m.stream_id);
    if (!id) return null;
    var it = {
      k: kind, id: id, n: U.str(m.name) || 'No name',
      i: U.str(kind === 'series' ? m.cover : m.stream_icon), c: U.str(m.category_id), num: U.int(m.num)
    };
    if (kind === 'vod') it.e = U.str(m.container_extension);
    var r = U.str(m.rating);
    if (r && r !== '0') it.r = r;
    if (kind !== 'live') {
      // When the server added it ("Recently Added", the Newest sort) and its year (the Year sort).
      var ad = U.int(kind === 'series' ? m.last_modified : m.added);
      if (ad > 0) it.ad = ad;
      var y = yearOf(m, it.n);
      if (y) it.y = y;
    }
    if (kind === 'live' && U.int(m.tv_archive) === 1) it.a = 1;
    return it;
  }

  /** "host:port", "http://host:port/" or a full ".../get.php?username=..&password=.." link. */
  Src.parseServer = function (input) {
    var s = U.str(input);
    if (!s) return { server: '' };
    if (s.indexOf('://') < 0) s = 'http://' + s;
    var m = /^(https?):\/\/([^\/?#]+)([^?#]*)(\?[^#]*)?/i.exec(s);
    if (!m) return { server: '' };
    var path = m[3] || '', lower = path.toLowerCase();
    ['/get.php', '/player_api.php', '/xmltv.php', '/panel_api.php'].forEach(function (f) {
      if (lower.length >= f.length && lower.substring(lower.length - f.length) === f) path = path.substring(0, path.length - f.length);
    });
    path = path.replace(/\/+$/, '');
    var qs = {}, query = (m[4] || '').substring(1).split('&');
    for (var i = 0; i < query.length; i++) {
      var p = query[i].split('=');
      if (p[0]) { try { qs[decodeURIComponent(p[0])] = decodeURIComponent((p[1] || '').replace(/\+/g, ' ')); } catch (e) {} }
    }
    return { server: m[1].toLowerCase() + '://' + m[2] + path, username: qs.username, password: qs.password };
  };

  Src.friendly = function (e) {
    if (!e) return 'Something went wrong. Please try again.';
    if (e.auth) return e.message;
    if (e.kind === 'timeout') return 'The server did not answer in time. Please try again.';
    if (e.kind === 'network') return 'Cannot reach the server. Check the address and your internet connection.';
    if (e.kind === 'format') return 'This address did not answer like an IPTV server.';
    if (e.kind === 'http') return (e.status === 401 || e.status === 403) ? 'Wrong username or password.' : 'The server answered with an error (' + e.status + ').';
    return e.message || 'Something went wrong. Please try again.';
  };

  // Format that worked this session after the first choice failed (only changed by failures).
  var sessionFormat = '';
  Src.formatWorked = function (fmt, wasFallback) { if (wasFallback && (fmt === 'ts' || fmt === 'm3u8')) sessionFormat = fmt; };
  function order(formats) {
    var pref = Store.liveFormat();
    var first = pref === 'ts' ? 'ts' : pref === 'm3u8' ? 'm3u8' : (sessionFormat || 'm3u8');
    var out = [first, first === 'ts' ? 'm3u8' : 'ts'];
    if (formats && formats.length) {
      var ok = out.filter(function (f) { return formats.indexOf(f) >= 0; });
      if (ok.length) out = ok;
    }
    return out;
  }

  // ------------------------------------------------------------------ Xtream Codes
  function Xtream(server, user, pass) {
    this.type = 'xtream';
    this.server = String(server).replace(/\/+$/, '');
    this.user = user;
    this.pass = pass;
    this.formats = [];
    this.cache = {};
    this.catKeys = [];
    this.pending = {};
    this.auth = encodeURIComponent(user) + '/' + encodeURIComponent(pass);
  }
  Src.Xtream = Xtream;
  Xtream.prototype.label = function () { return this.user; };
  Xtream.prototype.api = function (extra, timeout) {
    return Net.json(this.server + '/player_api.php?username=' + encodeURIComponent(this.user) +
      '&password=' + encodeURIComponent(this.pass) + (extra || ''), { timeout: timeout || 30000 });
  };
  Xtream.prototype.login = function () {
    var self = this;
    return this.api('', 20000).then(function (data) {
      var u = data && data.user_info;
      if (!u || typeof u !== 'object') {
        var e = new Error('This address did not answer like an IPTV server.');
        e.kind = 'format';
        throw e;
      }
      if (U.int(u.auth) !== 1) { var a = new Error('Wrong username or password.'); a.auth = true; throw a; }
      var status = U.str(u.status);
      if (status && status.toLowerCase() !== 'active') {
        var b = new Error('This account is ' + status.toLowerCase() + '. Please contact your provider.');
        b.auth = true;
        throw b;
      }
      var f = u.allowed_output_formats;
      self.formats = Object.prototype.toString.call(f) === '[object Array]' ? f.map(String) : [];
      var exp = U.int(u.exp_date);
      return {
        status: status || 'Active', expires: exp > 0 ? new Date(exp * 1000) : null,
        maxConnections: U.int(u.max_connections), trial: U.int(u.is_trial) === 1, note: ''
      };
    }, function (e) {
      if (e.kind === 'http' && (e.status === 401 || e.status === 403)) { e.auth = true; e.message = 'Wrong username or password.'; }
      throw e;
    });
  };
  Xtream.prototype.keep = function (key, value) {
    if (key.indexOf('cat-') === 0) {
      this.catKeys.push(key);
      while (this.catKeys.length > 20) delete this.cache[this.catKeys.shift()];
    }
    if (key.indexOf('all-') === 0) {
      // One full list in memory at a time (they are big).
      for (var k in this.cache) if (k.indexOf('all-') === 0 && k !== key) delete this.cache[k];
    }
    this.cache[key] = value;
  };
  Xtream.prototype.categories = function (kind) {
    var self = this, key = 'cats-' + kind;
    if (this.cache[key]) return Promise.resolve(this.cache[key]);
    return this.api('&action=' + ACTIONS[kind][0]).then(function (data) {
      var out = [];
      list(data).forEach(function (m) {
        var id = U.str(m.category_id);
        if (id) out.push({ id: id, name: U.str(m.category_name) || 'Category ' + id });
      });
      self.keep(key, out);
      return out;
    });
  };
  function parseItems(kind, data) {
    var out = [];
    var l = list(data);
    for (var i = 0; i < l.length; i++) {
      var it = itemFrom(kind, l[i]);
      if (it) out.push(it);
    }
    return out;
  }
  Xtream.prototype.items = function (kind, cat) {
    var self = this;
    var all = this.cache['all-' + kind];
    if (all) return Promise.resolve(all.filter(function (it) { return it.c === cat; }));
    var key = 'cat-' + kind + '-' + cat;
    if (this.cache[key]) return Promise.resolve(this.cache[key]);
    return this.api('&action=' + ACTIONS[kind][1] + '&category_id=' + encodeURIComponent(cat), 60000).then(function (data) {
      var items = parseItems(kind, data);
      // Some servers ignore the category and send everything.
      var mine = items.filter(function (it) { return it.c === cat; });
      if (mine.length && mine.length < items.length) items = mine;
      self.keep(key, items);
      return items;
    });
  };
  Xtream.prototype.all = function (kind) {
    var self = this, key = 'all-' + kind;
    if (this.cache[key]) return Promise.resolve(this.cache[key]);
    if (this.pending[key]) return this.pending[key];
    var p = this.api('&action=' + ACTIONS[kind][1], 90000).then(function (data) {
      var items = parseItems(kind, data);
      self.keep(key, items);
      delete self.pending[key];
      return items;
    }, function (e) { delete self.pending[key]; throw e; });
    this.pending[key] = p;
    return p;
  };
  Xtream.prototype.hasAll = function (kind) { return !!this.cache['all-' + kind]; };

  function firstText(vals) {
    for (var i = 0; i < vals.length; i++) {
      var v = vals[i];
      if (Object.prototype.toString.call(v) === '[object Array]') { var inner = firstText(v); if (inner) return inner; }
      else { var s = U.str(v); if (s && s.toLowerCase() !== 'null') return s; }
    }
    return '';
  }
  function readableLength(info) {
    var s = U.int(info.duration_secs);
    if (s <= 0) {
      var p = U.str(info.duration).split(':');
      if (p.length === 3) s = U.int(p[0]) * 3600 + U.int(p[1]) * 60 + U.int(p[2]);
      else if (p.length === 1 && U.int(p[0]) > 0) s = U.int(p[0]) * 60;
    }
    if (s <= 0) return '';
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
    return h > 0 ? h + ' h ' + m + ' min' : m + ' min';
  }
  Xtream.prototype.vodInfo = function (it) {
    return this.api('&action=get_vod_info&vod_id=' + encodeURIComponent(it.id)).then(function (data) {
      var info = (data && data.info) || {};
      if (typeof info !== 'object' || Object.prototype.toString.call(info) === '[object Array]') info = {};
      var date = firstText([info.releasedate, info.release_date, info.releaseDate, info.year]);
      var y = /(19|20)\d\d/.exec(date);
      return {
        plot: firstText([info.plot, info.description]), cast: firstText([info.cast, info.actors]),
        director: firstText([info.director]), genre: firstText([info.genre]), year: y ? y[0] : '',
        rating: U.num(firstText([info.rating, info.rating_5based])), duration: readableLength(info),
        backdrop: firstText([info.backdrop_path, info.backdrop]), cover: firstText([info.movie_image, info.cover_big, info.cover]),
        country: firstText([info.country])
      };
    });
  };
  Xtream.prototype.seriesInfo = function (id) {
    return this.api('&action=get_series_info&series_id=' + encodeURIComponent(id)).then(function (data) {
      var out = { plot: '', cover: '', genre: '', backdrop: '', seasons: {}, order: [] };
      if (!data) return out;
      var info = data.info || {};
      out.plot = U.str(info.plot);
      out.cover = U.str(info.cover);
      out.genre = U.str(info.genre);
      out.backdrop = firstText([info.backdrop_path]);
      var eps = data.episodes, groups = [];
      if (Object.prototype.toString.call(eps) === '[object Array]') {
        eps.forEach(function (v) { if (Object.prototype.toString.call(v) === '[object Array]') groups.push(v); });
        if (!groups.length) groups.push(eps);
      } else if (eps && typeof eps === 'object') {
        for (var k in eps) if (Object.prototype.toString.call(eps[k]) === '[object Array]') groups.push(eps[k]);
      }
      groups.forEach(function (g) {
        g.forEach(function (e) {
          if (!e || !U.str(e.id)) return;
          var season = U.int(e.season), num = U.int(e.episode_num), inf = e.info || {};
          (out.seasons[season] = out.seasons[season] || []).push({
            id: U.str(e.id), title: U.str(e.title) || 'Episode ' + num, ext: U.str(e.container_extension) || 'mp4',
            season: season, num: num, duration: U.str(inf.duration), pic: U.str(inf.movie_image)
          });
        });
      });
      out.order = Object.keys(out.seasons).map(Number).sort(function (a, b) { return a - b; });
      out.order.forEach(function (s) { out.seasons[s].sort(function (a, b) { return a.num - b.num; }); });
      return out;
    });
  };
  function parseEpg(data, full) {
    var out = [];
    list(data && data.epg_listings).forEach(function (m) {
      var st = U.int(m.start_timestamp), en = U.int(m.stop_timestamp);
      if (st <= 0 || en <= st) return;
      out.push({ title: U.b64(m.title), desc: U.b64(m.description), start: st * 1000, end: en * 1000, archive: U.int(m.has_archive) === 1 });
    });
    out.sort(function (a, b) { return a.start - b.start; });
    if (full) {
      var clean = [];
      out.forEach(function (e) { if (!clean.length || e.start > clean[clean.length - 1].start) clean.push(e); });
      return clean;
    }
    return out;
  }
  Xtream.prototype.epg = function (it) {
    if (!it || it.k !== 'live') return Promise.resolve([]);
    return this.api('&action=get_short_epg&stream_id=' + encodeURIComponent(it.id) + '&limit=10', 12000).then(function (d) { return parseEpg(d); });
  };
  Xtream.prototype.recordings = function (it) {
    return this.api('&action=get_simple_data_table&stream_id=' + encodeURIComponent(it.id), 20000).then(function (d) {
      var now = Date.now();
      return parseEpg(d, true).filter(function (e) { return e.archive && e.start < now; }).reverse();
    });
  };
  Xtream.prototype.liveUrls = function (it) {
    var self = this;
    return order(this.formats).map(function (f) { return self.server + '/live/' + self.auth + '/' + it.id + '.' + f; });
  };
  Xtream.prototype.vodUrl = function (it) { return this.server + '/movie/' + this.auth + '/' + it.id + '.' + (it.e || 'mp4'); };
  Xtream.prototype.episodeUrl = function (ep) { return this.server + '/series/' + this.auth + '/' + ep.id + '.' + (ep.ext || 'mp4'); };
  Xtream.prototype.recordingUrls = function (it, e) {
    var d = new Date(e.start);
    var s = d.getFullYear() + '-' + U.two(d.getMonth() + 1) + '-' + U.two(d.getDate()) + ':' + U.two(d.getHours()) + '-' + U.two(d.getMinutes());
    var mins = Math.max(1, Math.min(1440, Math.round((e.end - e.start) / 60000)));
    return [
      this.server + '/timeshift/' + this.auth + '/' + mins + '/' + s + '/' + it.id + '.m3u8',
      this.server + '/streaming/timeshift.php?username=' + encodeURIComponent(this.user) + '&password=' +
        encodeURIComponent(this.pass) + '&stream=' + it.id + '&start=' + s + '&duration=' + mins,
      this.server + '/timeshift/' + this.auth + '/' + mins + '/' + s + '/' + it.id + '.ts'
    ];
  };

  // ------------------------------------------------------------------ M3U playlist link
  var VIDEO_FILES = ['.mp4', '.mkv', '.avi', '.mov', '.m4v', '.flv', '.wmv', '.mpg', '.mpeg', '.webm'];
  function kindOf(url) {
    var p = url.toLowerCase(), q = p.indexOf('?');
    if (q >= 0) p = p.substring(0, q);
    if (p.indexOf('/series/') >= 0) return 'series';
    if (p.indexOf('/movie/') >= 0 || p.indexOf('/movies/') >= 0 || p.indexOf('/vod/') >= 0) return 'vod';
    for (var i = 0; i < VIDEO_FILES.length; i++) if (U.endsWith(p, VIDEO_FILES[i])) return 'vod';
    return 'live';
  }

  function M3U(url, epg) {
    this.type = 'm3u';
    this.url = url;
    this.epgUrl = epg || '';
    this.data = null;
    this.loading = null;
  }
  Src.M3U = M3U;
  M3U.prototype.label = function () {
    var m = /^https?:\/\/([^\/:?#]+)/i.exec(this.url);
    return m ? m[1] : 'M3U playlist';
  };
  M3U.prototype.load = function () {
    var self = this;
    if (this.data) return Promise.resolve(this.data);
    if (this.loading) return this.loading;
    if (!/^https?:\/\//i.test(this.url)) {
      var bad = new Error('This playlist link is not valid. It must start with http:// or https://');
      bad.auth = true;
      return Promise.reject(bad);
    }
    this.loading = Net.req('GET', this.url, null, { timeout: 90000 }).then(function (r) {
      if (r.status === 401 || r.status === 403) { var a = new Error('The server refused this playlist link (' + r.status + ').'); a.auth = true; throw a; }
      if (r.status !== 200) { var h = new Error('The server answered with an error (' + r.status + ').'); throw h; }
      var d = parseM3u(r.text);
      if (!d.total) { var z = new Error('This link did not return a playlist with channels.'); z.auth = true; throw z; }
      self.data = d;
      self.loading = null;
      return d;
    }, function (e) { self.loading = null; throw e; });
    return this.loading;
  };
  function parseM3u(text) {
    var items = { live: [], vod: [], series: [] }, total = 0;
    var name = null, logo = '', group = '', tvg = '', epgUrl = '';
    var re = /([A-Za-z0-9_-]+)="([^"]*)"/g, pos = 0, len = text.length;
    while (pos < len && total < 400000) {
      var nl = text.indexOf('\n', pos);
      if (nl < 0) nl = len;
      var line = text.substring(pos, nl).replace(/^\s+|\s+$/g, '');
      pos = nl + 1;
      if (!line) continue;
      if (line.charAt(0) === '#') {
        if (line.indexOf('#EXTINF') === 0) {
          logo = ''; group = ''; tvg = '';
          var tvgName = '', m, end = 0;
          re.lastIndex = 0;
          while ((m = re.exec(line))) {
            var key = m[1].toLowerCase();
            if (key === 'tvg-logo') logo = m[2];
            else if (key === 'group-title') group = m[2];
            else if (key === 'tvg-name') tvgName = m[2];
            else if (key === 'tvg-id') tvg = m[2];
            end = re.lastIndex;
          }
          var comma = line.indexOf(',', end);
          name = comma >= 0 ? U.str(line.substring(comma + 1)) : '';
          if (!name) name = tvgName;
        } else if (line.indexOf('#EXTGRP:') === 0) {
          if (!group) group = U.str(line.substring(8));
        } else if (line.indexOf('#EXTM3U') === 0) {
          var t = /(?:url-tvg|x-tvg-url)="([^"]*)"/i.exec(line);
          if (t) epgUrl = t[1].split(',')[0];
        }
        continue;
      }
      if (!/^https?:\/\//i.test(line)) { name = null; continue; }
      var kind = kindOf(line), l = items[kind];
      var it = { k: kind, id: line, n: name || 'No name', i: logo, c: group || 'Other', num: l.length + 1, u: line };
      if (kind === 'live' && tvg) it.g = tvg;
      if (kind !== 'live') { var yr = yearInName(it.n); if (yr) it.y = yr; }
      l.push(it);
      total++;
      name = null; logo = ''; group = ''; tvg = '';
    }
    var cats = {};
    KINDS.forEach(function (k) {
      var seen = {}, out = [];
      items[k].forEach(function (it) { if (!seen[it.c]) { seen[it.c] = 1; out.push({ id: it.c, name: it.c }); } });
      cats[k] = out;
    });
    return { items: items, cats: cats, total: total, epgUrl: epgUrl };
  }
  Src.parseM3u = parseM3u;
  M3U.prototype.login = function () {
    return this.load().then(function (d) {
      var parts = [];
      function count(n, one, many) { return n + ' ' + (n === 1 ? one : many); }
      if (d.items.live.length) parts.push(count(d.items.live.length, 'channel', 'channels'));
      if (d.items.vod.length) parts.push(count(d.items.vod.length, 'movie', 'movies'));
      if (d.items.series.length) parts.push(count(d.items.series.length, 'episode', 'episodes'));
      return { status: 'Active', expires: null, note: 'M3U playlist · ' + parts.join(', ') };
    });
  };
  M3U.prototype.categories = function (kind) { return this.load().then(function (d) { return d.cats[kind] || []; }); };
  M3U.prototype.items = function (kind, cat) {
    return this.load().then(function (d) { return d.items[kind].filter(function (it) { return it.c === cat; }); });
  };
  M3U.prototype.all = function (kind) { return this.load().then(function (d) { return d.items[kind]; }); };
  M3U.prototype.hasAll = function () { return !!this.data; };
  M3U.prototype.vodInfo = function (it) { return Promise.resolve({ cover: it.i }); };
  M3U.prototype.seriesInfo = function () { return Promise.resolve({ plot: '', cover: '', genre: '', seasons: {}, order: [] }); };
  M3U.prototype.epg = function () { return Promise.resolve([]); };
  M3U.prototype.liveUrls = function (it) {
    var u = it.u, q = u.indexOf('?'), path = q >= 0 ? u.substring(0, q) : u, query = q >= 0 ? u.substring(q) : '';
    var alt = null;
    if (U.endsWith(path, '.ts')) alt = path.substring(0, path.length - 3) + '.m3u8' + query;
    else if (U.endsWith(path, '.m3u8') && path.indexOf('/live/') >= 0) alt = path.substring(0, path.length - 5) + '.ts' + query;
    if (!alt) return [u];
    // Xtream-style addresses exist in both formats: the TV's own HLS player first (Settings can change it).
    var first = order([])[0];
    var isTs = U.endsWith(path, '.ts');
    if ((first === 'm3u8' && isTs && path.indexOf('/live/') >= 0) || (first === 'ts' && !isTs)) return [alt, u];
    return [u, alt];
  };
  M3U.prototype.vodUrl = function (it) { return it.u; };

  /** Opens a playlist from the website; resolves {src, account}. */
  Src.open = function (p) {
    if (p.type === 'xtream') {
      var x = new Xtream(Src.parseServer(p.url).server, p.username, p.password);
      return x.login().then(function (acc) { return { src: x, account: acc }; }, function (e) {
        // Plain http failed: the server may be https only.
        if (e.auth || x.server.indexOf('http://') !== 0) throw e;
        var y = new Xtream(x.server.replace('http://', 'https://'), p.username, p.password);
        return y.login().then(function (acc) { return { src: y, account: acc }; }, function () { throw e; });
      });
    }
    // A link from an Xtream panel goes through the panel's API (guide, series, catch-up).
    var parsed = Src.parseServer(p.url);
    if (parsed.username && parsed.password && p.url.toLowerCase().indexOf('get.php') >= 0) {
      var xa = new Xtream(parsed.server, parsed.username, parsed.password);
      return xa.login().then(function (acc) { return { src: xa, account: acc }; }, function (e) {
        if (e.auth) throw e;
        var m = new M3U(p.url, p.epg);
        return m.login().then(function (acc) { return { src: m, account: acc }; });
      });
    }
    var m3 = new M3U(p.url, p.epg);
    return m3.login().then(function (acc) { return { src: m3, account: acc }; });
  };

  /** The source for the saved session (no network). */
  Src.fromSession = function (s) {
    if (!s) return null;
    if (s.mode === 'm3u') return new M3U(s.url, s.epg);
    return new Xtream(s.server, s.user, s.pass);
  };
  Src.toSession = function (src) {
    if (src.type === 'm3u') return { mode: 'm3u', url: src.url, epg: src.epgUrl };
    return { mode: 'xtream', server: src.server, user: src.user, pass: src.pass };
  };
})();
