/* Extra film details from TMDB (themoviedb.org), as in the Android app: cast with photos, pictures
 * from the film and the trailer. Only to decorate the film page: playing never depends on it. On
 * only when the build has a TMDB key (the same optional key as the Android app). */
var Tmdb = {};

(function () {
  'use strict';

  var cache = {};
  Tmdb.enabled = function () { return !!(window.CONFIG && CONFIG.tmdbKey); };
  function base() { return CONFIG.tmdbBase || 'https://api.themoviedb.org/3'; }
  function image(size, path) { return path ? (CONFIG.tmdbImages || 'https://image.tmdb.org/t/p') + '/' + size + path : ''; }

  var BRACKET = /[\[\(\{][^\]\)\}]*[\]\)\}]/g, YEAR = /\b(19|20)\d\d\b/;
  var TAGS = /\b(4k|uhd|fhd|hd|sd|hevc|x265|x264|h265|h264|multi|dual audio|bluray|web-?dl|hdr)\b/gi;
  /** IPTV lists write titles like "EN | Big Film (2024) [4K]": TMDB needs "Big Film" and 2024. */
  Tmdb.cleanTitle = function (raw) {
    var text = String(raw || ''), year = '', m;
    var br = text.match(BRACKET) || [];
    for (var i = 0; i < br.length; i++) { m = YEAR.exec(br[i]); if (m) year = m[0]; }
    text = text.replace(BRACKET, ' ');
    // "EN | Title" or "4K-EN - Title": a short upper-case part in front of a separator goes.
    [' | ', '|', ' - ', ' : '].forEach(function (sep) {
      var at = text.indexOf(sep);
      if (at <= 0) return;
      var pre = U.str(text.substring(0, at)), rest = U.str(text.substring(at + sep.length));
      if (pre.length <= 6 && pre === pre.toUpperCase() && rest.length >= 2) text = rest;
    });
    // "Title - 2026" at the end: the year.
    m = /\s[-–]\s*((?:19|20)\d\d)\s*$/.exec(text);
    if (m) { if (!year) year = m[1]; text = text.substring(0, m.index); }
    text = text.replace(TAGS, ' ').replace(/[._]/g, ' ').replace(/\s+/g, ' ');
    text = U.str(text);
    return { title: text || U.str(raw), year: year };
  };

  function get(path, query) {
    var q = 'api_key=' + encodeURIComponent(CONFIG.tmdbKey);
    for (var k in query) if (query.hasOwnProperty(k) && query[k]) q += '&' + k + '=' + encodeURIComponent(query[k]);
    return Net.json(base() + path + '?' + q, { timeout: 12000 });
  }

  function parse(d) {
    var out = { plot: U.str(d.overview), year: '', genre: '', duration: '', rating: U.num(d.vote_average), backdrop: image('w1280', d.backdrop_path),
      trailer: '', cast: [], stills: [] };
    var date = U.str(d.release_date);
    if (date.length >= 4) out.year = date.substring(0, 4);
    if (d.genres && d.genres.length) out.genre = d.genres.map(function (g) { return U.str(g.name); }).filter(function (g) { return g; }).join(', ');
    var min = U.int(d.runtime);
    if (min > 0) out.duration = min >= 60 ? Math.floor(min / 60) + ' h ' + (min % 60) + ' min' : min + ' min';
    var cast = (d.credits && d.credits.cast) || [];
    for (var i = 0; i < cast.length && out.cast.length < 14; i++) {
      var n = U.str(cast[i].name);
      if (n) out.cast.push({ name: n, role: U.str(cast[i].character), photo: image('w185', cast[i].profile_path) });
    }
    var bd = (d.images && d.images.backdrops) || [];
    for (var j = 0; j < bd.length && out.stills.length < 10; j++) {
      if (bd[j].file_path) out.stills.push({ small: image('w300', bd[j].file_path), big: image('w1280', bd[j].file_path) });
    }
    var vids = ((d.videos && d.videos.results) || []).filter(function (v) { return v.site === 'YouTube' && v.key; });
    var tr = vids.filter(function (v) { return v.type === 'Trailer'; });
    if (tr.length || vids.length) out.trailer = (tr[0] || vids[0]).key;
    return out;
  }

  /** Details of a film: by its TMDB id when the server gives one, else by its title and year.
   *  Resolves null when TMDB is off, does not know the film or cannot be reached. */
  Tmdb.movie = function (title, tmdbId, year) {
    if (!Tmdb.enabled()) return Promise.resolve(null);
    var key = tmdbId ? 'id:' + tmdbId : 't:' + title + '|' + (year || '');
    if (cache.hasOwnProperty(key)) return Promise.resolve(cache[key]);
    var found = tmdbId ? Promise.resolve(String(tmdbId)) : (function () {
      var c = Tmdb.cleanTitle(title), y = year || c.year;
      function first(r) { return r && r.results && r.results.length ? String(r.results[0].id) : ''; }
      return get('/search/movie', { query: c.title, year: y }).then(function (r) {
        var id = first(r);
        if (id || !y) return id;
        return get('/search/movie', { query: c.title }).then(first);
      });
    })();
    return found.then(function (id) {
      if (!id) return null;
      return get('/movie/' + encodeURIComponent(id), { append_to_response: 'credits,videos,images', include_image_language: 'en,null' }).then(function (d) {
        return d ? parse(d) : null;
      });
    }).then(function (r) {
      cache[key] = r;
      App.log('tmdb: ' + (r ? r.cast.length + ' cast, ' + r.stills.length + ' pictures' + (r.trailer ? ', trailer' : '') : 'not found'));
      return r;
    }, function (e) {
      App.log('tmdb failed: ' + (e && e.message));
      return null; // not kept: tried again next time
    });
  };

  /** The trailer in the TV's YouTube app (LG); false when this TV cannot open it. */
  Tmdb.canOpenTrailer = function () { return !!window.PalmServiceBridge; };
  Tmdb.openTrailer = function (id) {
    App.log('trailer');
    return App.luna('luna://com.webos.applicationManager/launch', {
      id: 'youtube.leanback.v4', params: { contentTarget: 'https://www.youtube.com/tv?v=' + id, contentId: id }
    }, 4000).then(function (r) {
      if (!r || r.returnValue === false) {
        App.log('trailer: YouTube did not open (' + (r && (r.errorText || r.errorCode)) + ')');
        UI.toast('The YouTube app could not be opened on this TV.', 3000);
        return false;
      }
      return true;
    });
  };
})();
