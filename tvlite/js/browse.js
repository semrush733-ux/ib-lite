/* Live TV, Movies, Series and Catch Up: categories on the left, the list or covers on the right.
 * Live: OK on a channel plays it in the preview, OK again goes full screen (same stream, no reload). */
(function () {
  'use strict';

  var ALL = '*all', FAV = '*fav', RECENT = '*recent', SEARCH = '*search';
  var TITLES = { live: 'Live TV', vod: 'Movies', series: 'Series' };
  var ALL_TITLES = { live: 'All Live Channels', vod: 'All Movies', series: 'All Series' };
  var COUNT = { live: ['channel', 'channels'], vod: ['movie', 'movies'], series: ['series', 'series'] };

  App.rect = function (e) {
    var r = e.getBoundingClientRect(), s = App.scale || 1;
    return { left: r.left / s, top: r.top / s, width: r.width / s, height: r.height / s };
  };

  Screens.Browse = function (src, kind, mode) {
    var self = this;
    var catchup = mode === 'catchup', live = kind === 'live';
    this.name = catchup ? 'catchup' : 'browse-' + kind;
    var el = this.el = U.el('div', 'screen');
    var wide = !live;
    var title = catchup ? 'Catch Up' : TITLES[kind];
    el.innerHTML =
      '<div class="br-cats' + (wide ? ' wide' : '') + '"><div class="br-head">' + UI.symbol(58) + '<span class="t">' + U.esc(title) + '</span></div>' +
      '<div class="vl cats"></div></div>' +
      '<div class="br-main' + (wide ? ' wide' : '') + '"><div class="br-title"><span class="t"></span><span class="c"></span></div><div class="content"></div></div>';
    if (!live) el.style.background = '#0E0A0B';
    var main = el.querySelector('.br-main');
    var content = el.querySelector('.content');
    var titleT = el.querySelector('.br-title .t'), titleC = el.querySelector('.br-title .c');

    // ---------------------------------------------------------------- categories
    var catBox = el.querySelector('.cats');
    catBox.style.height = (11 * 84) + 'px';
    var cats = [], selected = '', selectedName = '', req = 0, focusTimer = null, allCount = null, query = '';
    var catList = new UI.VList(catBox, {
      rowH: 84, rows: 11, cls: 'crow', margin: 2,
      make: function (r) { r.innerHTML = ''; },
      render: function (r, c) {
        var cnt = c.id === ALL && allCount != null ? '<span class="cnt">(' + allCount + ')</span>' : '';
        r.innerHTML = (c.icon ? U.icon(c.icon) : '') + U.esc(c.name) + cnt;
      },
      ok: function (i) { var c = cats[i]; if (c.id === SEARCH) search(); else select(c.id, c.name); },
      focus: function (i) {
        clearTimeout(focusTimer);
        var c = cats[i];
        if (!c || c.id === selected || c.id === ALL || c.id === SEARCH) return;
        focusTimer = setTimeout(function () { select(c.id, c.name); }, 500);
      }
    });

    function setTitle(name, n) {
      titleT.textContent = name;
      titleC.textContent = n == null ? '' : n + ' ' + COUNT[kind][n === 1 ? 0 : 1];
    }

    function loadCategories() {
      content.innerHTML = '';
      content.appendChild(UI.pulse('loading'));
      src.categories(kind).then(function (list) {
        cats = [];
        if (!catchup) cats.push({ id: SEARCH, name: 'Search', icon: 'search' });
        cats.push({ id: ALL, name: catchup ? 'All with Catch Up' : ALL_TITLES[kind], icon: 'apps' });
        if (!catchup) {
          cats.push({ id: FAV, name: 'Favourites', icon: 'star' });
          cats.push({ id: RECENT, name: 'Recent', icon: 'history' });
        }
        var firstReal = cats.length;
        list.forEach(function (c) { cats.push({ id: c.id, name: c.name }); });
        var start = list.length ? firstReal : (catchup ? 0 : 1);
        catList.set(cats, start);
        App.log('categories ' + kind + ': ' + list.length);
        select(cats[start].id, cats[start].name);
        catList.focus(start);
      }, function (e) {
        showError(Src.friendly(e), loadCategories, true);
      });
    }

    function showError(msg, retry, focus) {
      content.innerHTML = '<div class="empty">' + U.esc(msg) + '<br><br></div>';
      var b = U.el('span', 'btn f', U.icon('refresh') + 'Try again');
      b._ok = retry;
      content.querySelector('.empty').appendChild(b);
      if (focus) F.set(b);
    }

    // ---------------------------------------------------------------- items (channels / covers)
    var items = [], view = null;

    function select(id, name) {
      clearTimeout(focusTimer);
      if (id === selected && items.length && id !== FAV && id !== RECENT) return;
      var r = ++req;
      selected = id;
      selectedName = name;
      catList.setSel(cats.map(function (c) { return c.id; }).indexOf(id));
      setTitle(name, null);
      var ready = id === FAV ? Store.favs(kind).slice() : id === RECENT ? Store.recents(kind).slice() : null;
      if (ready) { show(ready); return; }
      busy();
      var p = id === ALL ? src.all(kind).then(function (l) { allCount = l.length; catList.refresh(); return l; }) : src.items(kind, id);
      p.then(function (list) {
        if (r !== req) return;
        if (catchup) list = list.filter(function (it) { return it.a === 1; });
        show(list);
      }, function (e) {
        if (r !== req) return;
        showError(Src.friendly(e), function () { selected = ''; select(id, name); });
      });
    }

    function busy() {
      items = [];
      buildView();
      view.list.set([]);
      var p = UI.pulse('loading');
      view.box.appendChild(p);
      view.busy = p;
    }

    function show(list) {
      items = list;
      buildView();
      if (view.busy) { view.busy.parentNode.removeChild(view.busy); view.busy = null; }
      var e = view.box.querySelector('.empty');
      if (e) e.parentNode.removeChild(e);
      var selIdx = -1;
      if (live && pvItem) for (var i = 0; i < list.length; i++) if (list[i].id === pvItem.id) { selIdx = i; break; }
      view.list.set(list, selIdx >= 0 ? selIdx : 0, selIdx);
      setTitle(selected === SEARCH ? 'Search: ' + query : selectedName, list.length);
      if (!list.length) {
        var text = selected === FAV ? 'No favourites yet.\nHold OK on a ' + (live ? 'channel' : 'title') + ' to add it here.' :
          selected === RECENT ? 'Nothing watched yet.\nWhat you open appears here.' :
          selected === SEARCH ? 'Nothing found.' : catchup ? 'No channel in this category keeps recordings.' : 'This category is empty.';
        view.box.appendChild(U.el('div', 'empty', U.esc(text).replace(/\n/g, '<br>')));
      }
      if (live && list.length) focusChannel(view.list.idx);
    }

    function buildView() {
      if (view) return;
      content.innerHTML = '';
      if (live) buildLive(); else buildGrid();
    }

    // ---------------------------------------------------------------- live: channel list + preview
    var pvItem = null, pv = null, epgBox = null, epgTimer = null, epgReq = 0, epgCache = {}, epgKeys = [], focusItem = null, clock = null, recList = null, recItems = [], recCh = null;

    function buildLive() {
      var box = U.el('div', 'vl chl');
      box.style.cssText = 'position:absolute;left:0;top:0;width:560px;height:' + (9 * 98) + 'px';
      content.appendChild(box);
      var list = new UI.VList(box, {
        rowH: 98, rows: 9, cls: 'chrow', margin: 1,
        make: function (r) {
          r.innerHTML = '<span class="no num"></span><img class="lg" alt=""><span class="nm"><span></span></span><span class="st"></span>';
          r._no = r.firstChild; r._lg = r.childNodes[1]; r._nm = r.childNodes[2].firstChild; r._st = r.childNodes[3];
        },
        render: function (r, it, i) {
          r._no.textContent = i + 1;
          UI.setImg(r._lg, it.i);
          r._nm.textContent = it.n;
          r._st.innerHTML = Store.isFav(it) ? U.icon('star') : (catchup ? U.icon('history') : '');
          r.style.height = '88px';
        },
        ok: function (i) { openChannel(i); },
        long: function (i) { toggleFav(items[i]); },
        focus: function (i) { focusChannel(i); }
      });
      view = { box: box, list: list };
      // Right side: buttons, the picture, the guide (Catch Up: the recordings).
      var pane = U.el('div', 'pane');
      pane.style.cssText = 'left:588px;right:0;top:0;bottom:28px;height:' + (1080 - 100 - 28) + 'px';
      content.appendChild(pane);
      if (catchup) { buildRecordings(pane); return; }
      var btns = U.el('div', 'pbtns');
      pane.appendChild(btns);
      var bw = Math.floor((848 - 32) / 3);
      function pbtn(icon, label, ok) {
        var b = U.el('span', 'pbtn f', U.icon(icon) + U.esc(label));
        b.style.width = bw + 'px';
        b._ok = ok;
        btns.appendChild(b);
        return b;
      }
      pbtn('full', 'Full screen', function () { var i = indexOf(focusItem || pvItem); if (i >= 0) fullScreen(i); });
      var favBtn = pbtn('starb', 'Favourite', function () { var it = focusItem || pvItem; if (it) toggleFav(it); });
      pbtn('search', 'Search', search);
      view.favBtn = favBtn;
      pv = U.el('div', 'pv');
      pv.style.cssText = 'width:848px;height:477px;top:96px';
      pv.innerHTML = '<div class="frame"></div><div class="idle"></div><div class="cap hide"><span class="live">LIVE</span><span class="nm"></span><span class="hint">OK = full screen</span></div><div class="err hide"></div>';
      pane.appendChild(pv);
      // Magic Remote: clicking the picture goes full screen.
      pv.addEventListener('click', function () {
        var i = indexOf(pvItem);
        if (i >= 0 && Player.active()) fullScreen(i);
      });
      epgBox = U.el('div', 'epg');
      epgBox.style.top = (96 + 477 + 24) + 'px';
      epgBox.innerHTML = '<div class="hd"></div><div class="bd"><div class="in"></div></div>';
      pane.appendChild(epgBox);
      idle(null);
      clock = setInterval(function () { if (focusItem) drawEpg(focusItem, epgCache[focusItem.id]); }, 30000);
    }

    function indexOf(it) {
      if (!it) return -1;
      for (var i = 0; i < items.length; i++) if (items[i].id === it.id) return i;
      return -1;
    }

    function idle(it) {
      if (!pv) return;
      var box = pv.querySelector('.idle');
      box.classList.remove('hide');
      box.innerHTML = (it && it.i ? '<img src="' + U.esc(it.i) + '" alt="">' : U.icon('live')) + '<div class="tx">Press OK to watch here</div>';
      var img = box.querySelector('img');
      if (img) img.onerror = function () { img.style.visibility = 'hidden'; };
    }

    function focusChannel(i) {
      var it = items[i];
      if (!it) return;
      if (catchup) return;
      if (focusItem && focusItem.id === it.id) return;
      focusItem = it;
      if (view && view.favBtn) view.favBtn.innerHTML = U.icon(Store.isFav(it) ? 'star' : 'starb') + 'Favourite';
      if (!pvItem) idle(it);
      var cached = epgCache[it.id];
      drawEpg(it, cached);
      clearTimeout(epgTimer);
      if (cached) return;
      var r = ++epgReq;
      epgTimer = setTimeout(function () {
        src.epg(it).then(function (l) { keepEpg(it.id, l); if (r === epgReq) drawEpg(it, l); }, function () {
          keepEpg(it.id, []);
          if (r === epgReq) drawEpg(it, []);
        });
      }, 350);
    }
    function keepEpg(id, l) {
      epgCache[id] = l;
      epgKeys.push(id);
      while (epgKeys.length > 40) delete epgCache[epgKeys.shift()];
    }
    function drawEpg(it, list) {
      if (!epgBox) return;
      var i = indexOf(it);
      epgBox.querySelector('.hd').innerHTML = (it.i ? '<img src="' + U.esc(it.i) + '" alt="">' : '') +
        (i >= 0 ? '<span class="n">' + (i + 1) + '</span>' : '') + '<span class="t">' + U.esc(it.n) + '</span><span class="clk num">' + U.hm(new Date()) + '</span>';
      var img = epgBox.querySelector('.hd img');
      if (img) img.onerror = function () { img.style.display = 'none'; };
      var inner = epgBox.querySelector('.in');
      inner.style.webkitTransform = inner.style.transform = '';
      epgBox._scroll = 0;
      if (!list) { inner.innerHTML = '<div class="msg">Loading the guide…</div>'; return; }
      var now = Date.now();
      var up = list.filter(function (e) { return e.end > now; }).slice(0, 10);
      if (!up.length) { inner.innerHTML = '<div class="msg">No programme information for this channel.</div>'; return; }
      var cur = up[0].start <= now ? up[0] : null;
      var html = '';
      if (cur) {
        var p = Math.max(0, Math.min(1, (now - cur.start) / Math.max(1, cur.end - cur.start)));
        html += '<div class="now">' + U.hm(new Date(cur.start)) + ' – ' + U.hm(new Date(cur.end)) + '   ' + U.esc(cur.title) + '</div>' +
          '<div class="prog"><i style="width:' + Math.round(p * 100) + '%"></i></div>' +
          (cur.desc ? '<div class="desc">' + U.esc(cur.desc.length > 260 ? cur.desc.substring(0, 259) + '…' : cur.desc) + '</div>' : '');
      }
      (cur ? up.slice(1) : up).forEach(function (e) {
        html += '<div class="nx"><span class="tm num">' + U.hm(new Date(e.start)) + ' – ' + U.hm(new Date(e.end)) + '</span>' + U.esc(e.title) + '</div>';
      });
      inner.innerHTML = html;
    }

    function previewRect() { return App.rect(pv); }

    function openChannel(i) {
      var it = items[i];
      if (!it) return;
      if (catchup) { loadRecordings(it); return; }
      if (pvItem && pvItem.id === it.id && Player.active() && Player.state() !== 'error') { fullScreen(i); return; }
      startPreview(i);
    }

    function startPreview(i) {
      var it = items[i];
      pvItem = it;
      view.list.setSel(i);
      pv.querySelector('.idle').classList.add('hide');
      var cap = pv.querySelector('.cap');
      cap.classList.add('hide');
      cap.querySelector('.nm').textContent = it.n;
      pv.querySelector('.err').classList.add('hide');
      pvPulse(true);
      Player.layout('preview', previewRect());
      Player.open(src.liveUrls(it), { live: true });
    }

    function pvPulse(on) {
      if (!pv) return;
      var p = pv.querySelector('.pulse');
      if (on && !p) pv.appendChild(UI.pulse('late'));
      if (!on && p) p.parentNode.removeChild(p);
    }

    function onPlayer(ev, d) {
      if (!pv || !pvItem || Nav.top() !== self) return;
      if (ev !== 'state') return;
      if (d.state === 'playing') {
        pvPulse(false);
        pv.querySelector('.cap').classList.remove('hide');
      } else if (d.state === 'buffering' || d.state === 'loading') {
        pvPulse(true);
      } else if (d.state === 'error') {
        pvPulse(false);
        Player.layout('off');
        var er = pv.querySelector('.err');
        er.textContent = 'This channel is not available right now.';
        er.classList.remove('hide');
        idle(pvItem);
        pv.querySelector('.idle .tx').textContent = '';
      }
    }
    Player.on(onPlayer);

    function stopPreview() {
      if (!pvItem) return;
      pvItem = null;
      Player.stop();
      Player.layout('off');
      pvPulse(false);
      if (pv) {
        pv.querySelector('.cap').classList.add('hide');
        idle(focusItem);
      }
      if (view) view.list.setSel(-1);
    }

    function fullScreen(i) {
      var it = items[i];
      if (!it) return;
      Store.addRecent(it);
      var playing = pvItem && pvItem.id === it.id && Player.active() && Player.state() !== 'error';
      if (!playing) pvItem = it;
      Nav.push(new Screens.Player({
        src: src, kind: 'live', items: items, index: i, adopt: playing, title: selectedName,
        onClose: function (idx) {
          // Back from full screen: that channel goes on in the preview.
          returnIdx = idx;
          if (Player.active() && items[idx]) {
            pvItem = items[idx];
            view.list.setSel(idx);
            pv.querySelector('.idle').classList.add('hide');
            pv.querySelector('.cap .nm').textContent = pvItem.n;
            pv.querySelector('.cap').classList.toggle('hide', Player.state() !== 'playing');
            pvPulse(Player.state() !== 'playing');
          } else {
            pvItem = null;
            view.list.setSel(-1);
          }
        }
      }));
    }

    // ---------------------------------------------------------------- catch up: recordings of a channel
    function buildRecordings(pane) {
      var head = U.el('div', 'br-title');
      head.innerHTML = '<span class="t">Recordings</span>';
      pane.appendChild(head);
      var box = U.el('div', 'vl recs');
      box.style.cssText = 'position:absolute;left:0;right:0;top:64px;height:' + (8 * 104) + 'px';
      pane.appendChild(box);
      recList = new UI.VList(box, {
        rowH: 104, rows: 8, cls: 'eprow', margin: 1,
        make: function (r) { r.innerHTML = '<span class="et"></span><span class="ex"></span>'; },
        render: function (r, e) {
          var d = new Date(e.start);
          r.firstChild.textContent = e.title || 'Programme';
          r.childNodes[1].innerHTML = U.esc(U.days[d.getDay()].substring(0, 3) + ' ' + d.getDate() + ' ' + U.months[d.getMonth()] + '  ' + U.hm(d) + ' – ' + U.hm(new Date(e.end))) + U.icon('play');
        },
        ok: function (i) { playRecording(i); }
      });
      var msg = U.el('div', 'empty', 'Choose a channel to see what it recorded.');
      msg.style.top = '30%';
      box.appendChild(msg);
      recList.msg = msg;
    }
    function loadRecordings(ch) {
      recCh = ch;
      view.list.setSel(indexOf(ch));
      recItems = [];
      recList.set([]);
      recList.msg.innerHTML = '<span class="spin"></span>';
      recList.msg.classList.remove('hide');
      src.recordings(ch).then(function (l) {
        if (recCh !== ch) return;
        recItems = l;
        recList.set(l, 0);
        if (l.length) { recList.msg.classList.add('hide'); recList.focus(0); }
        else recList.msg.textContent = 'No recordings for this channel.';
      }, function (e) {
        if (recCh !== ch) return;
        recList.msg.textContent = Src.friendly(e);
      });
    }
    function playRecording(i) {
      var e = recItems[i];
      if (!e || !recCh) return;
      var d = new Date(e.start);
      Nav.push(new Screens.Player({
        src: src, kind: 'rec', urls: src.recordingUrls(recCh, e), title: e.title || recCh.n,
        sub: recCh.n + '  ·  ' + U.days[d.getDay()] + ' ' + U.hm(d), poster: recCh.i
      }));
    }

    // ---------------------------------------------------------------- movies and series: covers
    function buildGrid() {
      var w = 212, h = 314, gap = 20, cols = 6, rows = 3;
      var box = U.el('div', 'vl grid');
      box.style.cssText = 'position:absolute;left:0;top:0;width:' + (cols * w + (cols - 1) * gap + 8) + 'px;height:' + (rows * h + (rows - 1) * gap + 4) + 'px';
      content.appendChild(box);
      var grid = new UI.VGrid(box, {
        w: w, h: h, gap: gap, cols: cols, rows: rows, fullRows: rows, cls: 'poster',
        make: function (t) {
          t.innerHTML = '<span class="ph">' + U.icon(kind === 'vod' ? 'movie' : 'series') + '</span><img alt=""><div class="cap cl2"></div><span class="fav"></span>';
          t._img = t.childNodes[1]; t._cap = t.childNodes[2]; t._fav = t.childNodes[3];
        },
        render: function (t, it) {
          UI.setImg(t._img, it.i);
          t._cap.textContent = it.n;
          t._fav.innerHTML = Store.isFav(it) ? U.icon('star') : '';
        },
        ok: function (i) { openTitle(i); },
        long: function (i) { toggleFav(items[i]); }
      });
      view = { box: box, list: grid };
    }

    function openTitle(i) {
      var it = items[i];
      if (!it) return;
      Store.addRecent(it);
      if (kind === 'series' && !it.u) Nav.push(new Screens.Series(src, it));
      else Nav.push(new Screens.Movie(src, it));
    }

    // ---------------------------------------------------------------- favourites and search
    function toggleFav(it) {
      if (!it) return;
      var added = Store.toggleFav(it);
      UI.toast(added ? 'Added to Favourites' : 'Removed from Favourites', 1400);
      if (selected === FAV) {
        var keep = view.list.idx;
        items = Store.favs(kind).slice();
        view.list.set(items, Math.min(keep, items.length - 1));
        setTitle(selectedName, items.length);
      } else if (view) view.list.refresh();
      if (view && view.favBtn && focusItem && focusItem.id === it.id) view.favBtn.innerHTML = U.icon(added ? 'star' : 'starb') + 'Favourite';
    }

    function search() {
      UI.ask('Search', query, 'Name', 'search', function (q) {
        if (!q) return;
        query = q;
        var r = ++req;
        selected = SEARCH;
        selectedName = 'Search: ' + q;
        catList.setSel(cats.map(function (c) { return c.id; }).indexOf(SEARCH));
        setTitle(selectedName, null);
        busy();
        src.all(kind).then(function (all) {
          if (r !== req) return;
          allCount = all.length;
          catList.refresh();
          var words = U.norm(q).split(' ').filter(function (w) { return w; });
          var found = [];
          for (var i = 0; i < all.length && found.length < 400; i++) {
            var n = U.norm(all[i].n), joined = n.replace(/ /g, ''), ok = words.length > 0;
            for (var k = 0; k < words.length && ok; k++) if (n.indexOf(words[k]) < 0 && joined.indexOf(words[k]) < 0) ok = false;
            if (ok) found.push(all[i]);
          }
          App.log('search ' + kind + ': ' + found.length);
          show(found);
          if (found.length) view.list.focus(0);
        }, function (e) {
          if (r !== req) return;
          showError(Src.friendly(e), search);
        });
      });
    }

    // ---------------------------------------------------------------- screen life
    var returnIdx = -1;
    this.show = function (first) {
      if (first) { loadCategories(); return; }
      if (live && pvItem && Player.active()) Player.layout('preview', previewRect());
      if (view) view.list.refresh();
      if (returnIdx >= 0 && view && items[returnIdx]) {
        view.list.focus(returnIdx);
        focusChannel(returnIdx);
      }
      returnIdx = -1;
      if (selected === RECENT || selected === FAV) {
        var cur = view ? view.list.idx : 0;
        items = selected === FAV ? Store.favs(kind).slice() : Store.recents(kind).slice();
        if (view) view.list.set(items, Math.min(cur, Math.max(0, items.length - 1)), live && pvItem ? indexOf(pvItem) : -1);
        setTitle(selectedName, items.length);
      }
    };
    this.hide = function (next) {
      // Another screen opens on top: the preview stops, unless full screen takes the stream over.
      if (next && next.name === 'player' && next.kind === 'live') return;
      stopPreview();
    };
    this.onKey = function (k) {
      if (k === 'back') stopPreview();
      return false;
    };
    this.destroy = function () {
      clearTimeout(focusTimer);
      clearTimeout(epgTimer);
      clearInterval(clock);
      Player.off(onPlayer);
      stopPreview();
    };
  };
})();
