/* Streaming boxes (Settings → Streaming boxes): Netflix, Prime Video, Disney+… on the home screen.
 * A box shows the playlist's own movies and series of that service, found two ways:
 *  1. the playlist's categories named after the service ("NETFLIX MOVIES", "AMAZON PRIME"…);
 *  2. the website's daily list of the service's titles (from TMDB, the film database), matched with
 *     the playlist's titles.
 * Only the service's name is shown, never the company's logo. */
var Streaming = {};

(function () {
  'use strict';

  Streaming.SERVICES = [
    { id: 'netflix', name: 'Netflix', words: ['netflix', 'nflx'] },
    { id: 'prime', name: 'Prime Video', words: ['amazon', 'prime'] },
    { id: 'disney', name: 'Disney+', words: ['disney'] },
    { id: 'hbo', name: 'HBO Max', words: ['hbo'] },
    { id: 'apple', name: 'Apple TV+', words: ['apple', 'appletv'] },
    { id: 'paramount', name: 'Paramount+', words: ['paramount'] },
    { id: 'hulu', name: 'Hulu', words: ['hulu'] },
    { id: 'peacock', name: 'Peacock', words: ['peacock'] }
  ];
  var found = {};
  Streaming.on = function (id) { return !!S.get('svc_' + id, false); };
  Streaming.set = function (id, on) { S.set('svc_' + id, !!on); found = {}; };
  Streaming.enabled = function () { return Streaming.SERVICES.filter(function (s) { return Streaming.on(s.id); }); };
  Streaming.clear = function () { found = {}; };

  // ---------------------------------------------------------------- names
  var FROM = 'àáâãäåèéêëìíîïòóôõöùúûüçñ', TO = 'aaaaaaeeeeiiiiooooouuuucn';
  /** Lower case, letters and digits only ("Spider-Man: No Way Home" → "spider man no way home"). */
  function norm(s) {
    s = String(s || '').toLowerCase().replace(/&/g, ' and ');
    var out = '', space = true;
    for (var i = 0; i < s.length; i++) {
      var c = s.charCodeAt(i);
      if (c > 127) { var k = FROM.indexOf(s.charAt(i)); if (k >= 0) c = TO.charCodeAt(k); }
      if ((c >= 48 && c <= 57) || (c >= 97 && c <= 122)) { out += String.fromCharCode(c); space = false; }
      else if (!space) { out += ' '; space = true; }
    }
    return out.replace(/ $/, '');
  }
  Streaming.norm = norm;

  var BRACKET = /[\[\(\{][^\]\)\}]*[\]\)\}]/g, YEAR = /\b(19|20)\d\d\b/,
    TAGS = /\b(4k|uhd|fhd|hd|sd|hevc|x265|x264|h265|h264|multi|dual audio|bluray|web-?dl|hdr)\b/gi,
    TRAIL = /^(.*\S)[\s\-:]+((?:19|20)\d\d)$/;
  /** IPTV names like "EN | Big Film (2024) [4K]": the title and the year. */
  function clean(raw) {
    var text = String(raw || '').replace(/^\s*\|[^|]{1,10}\|\s*/, ''), year = 0, m;
    var br = text.match(BRACKET) || [];
    for (var i = 0; i < br.length; i++) if ((m = YEAR.exec(br[i]))) year = +m[0];
    text = text.replace(BRACKET, ' ');
    ['|', ' - ', ' : '].forEach(function (sep) {
      var at = text.indexOf(sep);
      if (at <= 0) return;
      var pre = U.str(text.substring(0, at)), rest = U.str(text.substring(at + sep.length));
      if (pre.length <= 6 && pre === pre.toUpperCase() && rest.length >= 2) text = rest;
    });
    text = text.replace(TAGS, ' ').replace(/[._]/g, ' ').replace(/\s+/g, ' ').replace(/^ | $/g, '').replace(/\s+S\d{1,2}(\s*E\d{1,3})?$/i, '');
    return { title: text || U.str(raw), year: year };
  }
  Streaming.clean = clean;

  function catIsFor(name, s) {
    var n = ' ' + norm(name) + ' ';
    for (var i = 0; i < s.words.length; i++) if (n.indexOf(' ' + s.words[i] + ' ') >= 0) return true;
    return false;
  }
  Streaming.catIsFor = catIsFor;

  // ---------------------------------------------------------------- finding the titles
  var lists = null, listsAt = 0;
  /** The website's lists of every service's titles (refreshed there once a day; kept here 6 hours). */
  function siteLists() {
    if (lists && Date.now() - listsAt < 6 * 3600000) return Promise.resolve(lists);
    return Backend.streamingLists().then(function (l) {
      lists = l;
      listsAt = Date.now();
      S.set('svc_lists', l);
      return l;
    }, function (e) {
      App.log('streaming lists: ' + (e && e.message));
      if (!lists) lists = S.get('svc_lists', {}) || {};
      return lists;
    });
  }

  Streaming.find = function (src, s) {
    var key = [src.type, src.server || '', src.user || '', src.url || '', s.id].join('|');
    if (found[key]) return Promise.resolve(found[key]);
    var movies = [], series = [], seen = {}, matched = 0;
    function add(it) {
      var k = (it.k || '') + ':' + it.id;
      if (seen[k]) return false;
      seen[k] = 1;
      (it.k === 'series' ? series : movies).push(it);
      return true;
    }
    function fromList(kind, titles) {
      if (!titles || !titles.length) return Promise.resolve();
      return src.all(kind).then(function (all) {
        var byName = {};
        function put(k, it, y) { if (k) (byName[k] || (byName[k] = [])).push([it, y]); }
        for (var i = 0; i < all.length; i++) {
          var c = clean(all[i].n), m = TRAIL.exec(c.title);
          put(norm(c.title), all[i], c.year);
          if (m) put(norm(m[1]), all[i], c.year || +m[2]);
        }
        titles.forEach(function (t) {
          var hits = byName[norm(t[0])], y = +t[1] || 0;
          if (!hits) return;
          hits.forEach(function (h) {
            if (y && h[1] && Math.abs(h[1] - y) > 1) return; // same name, another film
            if (add(h[0])) matched++;
          });
        });
      }, function () {});
    }
    function fromCats(kind) {
      return src.categories(kind).then(function (cats) {
        var mine = cats.filter(function (c) { return catIsFor(c.name, s); });
        return mine.reduce(function (p, c) {
          return p.then(function () {
            return src.items(kind, c.id).then(function (items) { items.forEach(add); }, function () {});
          });
        }, Promise.resolve());
      }, function () {});
    }
    return siteLists().then(function (l) {
      var my = l && l[s.id];
      return fromList('vod', my && my.movie).then(function () { return fromList('series', my && my.tv); });
    }).then(function () { return fromCats('vod'); }).then(function () { return fromCats('series'); }).then(function () {
      App.log('streaming ' + s.id + ': movies=' + movies.length + ' series=' + series.length + ' matched=' + matched);
      return (found[key] = { movies: movies, series: series, matched: matched });
    });
  };

  // ---------------------------------------------------------------- Settings window
  Streaming.dialog = function (onChange) {
    var d = UI.dialog({ title: 'Streaming boxes', html: '<div class="dim" style="font-size:26px;margin-bottom:18px;white-space:normal">' +
      'Switch on a service and its box appears on the home screen, with its movies and series from your playlist.</div><div class="pls"></div>',
      width: 1000, buttons: [{ label: 'Close', pri: true }] });
    var box = d.body.querySelector('.pls');
    Streaming.SERVICES.forEach(function (s, i) {
      var b = U.el('div', 'opt f');
      function draw() { b.innerHTML = U.icon(Streaming.on(s.id) ? 'boxOn' : 'boxOff') + U.esc(s.name); b.classList.toggle('sel', Streaming.on(s.id)); }
      draw();
      b._ok = function () { Streaming.set(s.id, !Streaming.on(s.id)); draw(); if (onChange) onChange(); };
      box.appendChild(b);
      if (i === 0) F.set(b);
    });
  };

  // ---------------------------------------------------------------- the box's screen
  Screens.Streaming = function (src, s) {
    var self = this;
    this.name = 'streaming';
    var el = this.el = U.el('div', 'screen');
    el.style.background = '#0E0A0B';
    el.innerHTML =
      '<div class="br-cats wide"><div class="br-head">' + UI.symbol(58) + '<span class="t">' + U.esc(s.name) + '</span></div>' +
      '<div class="vl cats"></div></div>' +
      '<div class="br-main wide"><div class="br-title"><span class="t"></span><span class="c"></span></div><div class="content"></div></div>';
    var content = el.querySelector('.content');
    var titleT = el.querySelector('.br-title .t'), titleC = el.querySelector('.br-title .c');
    var res = null, kind = 'vod', grid = null, items = [];
    var tabs = [{ id: 'vod', name: App.t('Movies'), icon: 'movie' }, { id: 'series', name: App.t('Series'), icon: 'series' }];
    var catBox = el.querySelector('.cats');
    catBox.style.height = (2 * 84) + 'px';
    var tabList = new UI.VList(catBox, {
      rowH: 84, rows: 2, cls: 'crow', margin: 0,
      make: function (r) { r.innerHTML = ''; },
      render: function (r, t) {
        var n = res ? (t.id === 'vod' ? res.movies : res.series).filter(Store.allowed).length : null;
        r.innerHTML = U.icon(t.icon) + U.esc(t.name) + (n == null ? '' : '<span class="cnt">(' + n + ')</span>');
      },
      ok: function (i) { show(tabs[i].id); },
      focus: function (i) { show(tabs[i].id); }
    });

    function show(k) {
      if (!res || (k === kind && grid)) return;
      kind = k;
      tabList.setSel(k === 'vod' ? 0 : 1);
      items = (k === 'vod' ? res.movies : res.series).filter(Store.allowed);
      titleT.textContent = k === 'vod' ? App.t('Movies') : App.t('Series');
      titleC.textContent = items.length + (k === 'vod' ? (items.length === 1 ? ' movie' : ' movies') : ' series');
      content.innerHTML = '';
      grid = null;
      if (!items.length) {
        content.appendChild(U.el('div', 'empty', U.esc('No ' + (k === 'vod' ? 'movies' : 'series') + ' of ' + s.name + ' were found in your playlist.') +
          '<br><br><span style="font-size:26px">This box shows the playlist\'s own ' + U.esc(s.name) + ' categories, and the titles of ' + U.esc(s.name) +
          ' found in your playlist when the website has the film database (TMDB) set up.</span>'));
        return;
      }
      var w = 212, h = 314, gap = 20, cols = 6, rows = 3;
      var box = U.el('div', 'vl grid');
      box.style.cssText = 'position:absolute;left:0;top:0;width:' + (cols * w + (cols - 1) * gap + 8) + 'px;height:' + (rows * h + (rows - 1) * gap + 4) + 'px';
      content.appendChild(box);
      grid = new UI.VGrid(box, {
        w: w, h: h, gap: gap, cols: cols, rows: rows, fullRows: rows, cls: 'poster',
        make: function (t) {
          t.innerHTML = '<span class="ph">' + U.icon(k === 'vod' ? 'movie' : 'series') + '</span><img alt=""><div class="cap cl2"></div><span class="fav"></span>';
          t._img = t.childNodes[1]; t._cap = t.childNodes[2]; t._fav = t.childNodes[3];
        },
        render: function (t, it) {
          UI.setImg(t._img, it.i);
          t._cap.textContent = it.n;
          t._fav.innerHTML = Store.isFav(it) ? U.icon('star') : '';
        },
        ok: function (i) { open(items[i]); },
        long: function (i) {
          var it = items[i];
          if (!it) return;
          var added = Store.toggleFav(it);
          UI.toast(added ? 'Added to Favourites' : 'Removed from Favourites', 1400);
          grid.refresh();
        }
      });
      grid.set(items, 0);
    }

    function open(it) {
      if (!it) return;
      Store.addRecent(it);
      if (it.k === 'series' && !it.u) Nav.push(new Screens.Series(src, it));
      else Nav.push(new Screens.Movie(src, it));
    }

    function load() {
      content.innerHTML = '';
      content.appendChild(UI.pulse('loading'));
      titleT.textContent = 'Looking for ' + s.name + ' titles in your playlist…';
      Streaming.find(src, s).then(function (r) {
        if (Nav.top() !== self && !self.el.parentNode) return;
        res = r;
        tabList.refresh();
        kind = '';
        show(r.movies.length || !r.series.length ? 'vod' : 'series');
        tabList.focus(kind === 'vod' ? 0 : 1);
      }, function (e) {
        content.innerHTML = '<div class="empty">' + U.esc(Src.friendly(e)) + '</div>';
      });
    }

    this.show = function (first) {
      if (first) {
        tabList.set(tabs, 0);
        tabList.focus(0);
        load();
        return;
      }
      if (grid) grid.refresh();
    };
  };
})();
