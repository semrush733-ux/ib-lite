/* Details of a film (picture, rating, plot, Watch) and of a series (seasons and episodes). */
(function () {
  'use strict';

  function stars(r) {
    var out = '', v = r / 2;
    for (var i = 1; i <= 5; i++) out += U.icon(v >= i - 0.25 ? 'star' : (v >= i - 0.75 ? 'starh' : 'starb'));
    return out;
  }

  // ================================================================== film
  Screens.Movie = function (src, it) {
    var self = this;
    this.name = 'movie';
    var el = this.el = U.el('div', 'screen');
    el.style.background = '#0E0A0B';
    var info = {}, loading = true;
    var key = 'vod:' + it.id;
    el.innerHTML = '<div class="dt-bg"></div><div class="dt-wash"></div><div class="dt-wash2"></div>' +
      '<div class="dt"><h1 class="cl2"></h1><div class="meta"></div><div class="genre"></div><div class="plot"></div>' +
      '<div class="acts"></div><div class="more"></div></div>';
    el.querySelector('h1').textContent = it.n;

    function draw() {
      var bg = info.backdrop || info.cover || it.i;
      var bgEl = el.querySelector('.dt-bg');
      if (bg && bgEl._bg !== bg) {
        bgEl._bg = bg;
        var pre = new Image();
        pre.onload = function () { bgEl.style.backgroundImage = 'url("' + bg.replace(/"/g, '%22') + '")'; };
        pre.src = bg;
      }
      var rating = info.rating > 0 ? info.rating : U.num(it.r);
      var meta = '';
      if (rating > 0) meta += '<span class="stars">' + stars(rating) + '</span><span class="m">' + (Math.round(rating * 10) / 10) + '/10</span>';
      if (info.duration) meta += '<span class="m">' + U.esc(info.duration) + '</span>';
      if (info.year) meta += '<span class="m">' + U.esc(info.year) + '</span>';
      if (info.country) meta += '<span class="m">' + U.esc(info.country) + '</span>';
      el.querySelector('.meta').innerHTML = meta;
      el.querySelector('.genre').textContent = info.genre || '';
      var plot = el.querySelector('.plot');
      plot.textContent = info.plot || (loading ? 'Loading details…' : 'There is no description for this title.');
      plot.style.color = info.plot ? '' : '#8B93A3';
      var more = '';
      if (info.director) more += 'Director:  <b>' + U.esc(info.director) + '</b><br>';
      if (info.cast) more += 'Cast:  <b>' + U.esc(info.cast.length > 160 ? info.cast.substring(0, 159) + '…' : info.cast) + '</b>';
      el.querySelector('.more').innerHTML = more;
    }

    var acts = el.querySelector('.acts');
    function buttons() {
      var hadFocus = F.cur && acts.contains(F.cur);
      var focusIdx = 0;
      if (hadFocus) for (var k = 0; k < acts.childNodes.length; k++) if (acts.childNodes[k] === F.cur) focusIdx = k;
      acts.innerHTML = '';
      var resume = Store.resume(key);
      function btn(icon, label, pri, ok) {
        var b = U.el('span', 'btn f' + (pri ? ' pri' : ''), U.icon(icon) + U.esc(label));
        b._ok = ok;
        acts.appendChild(b);
        return b;
      }
      var first = btn('play', resume > 30 ? 'Resume from ' + U.time(resume) : 'Watch now', true, function () { watch(resume > 30 ? resume : 0); });
      if (resume > 30) btn('replay', 'From the start', false, function () { watch(0); });
      var fav = Store.isFav(it);
      btn(fav ? 'fav' : 'favb', fav ? 'In Favourites' : 'Favourite', false, function () {
        var added = Store.toggleFav(it);
        UI.toast(added ? 'Added to Favourites' : 'Removed from Favourites', 1400);
        buttons();
      });
      if (hadFocus) F.set(acts.childNodes[Math.min(focusIdx, acts.childNodes.length - 1)]);
      return first;
    }

    function watch(start) {
      Nav.push(new Screens.Player({
        src: src, kind: 'vod', urls: src.vodUrls ? src.vodUrls(it) : [src.vodUrl(it)], title: it.n, sub: [info.year, info.genre].filter(function (s) { return s; }).join('  ·  '),
        poster: info.cover || it.i, resumeKey: key, start: start
      }));
    }

    this.show = function (first) {
      draw();
      var b = buttons();
      if (first) {
        F.set(b);
        src.vodInfo(it).then(function (i) { info = i || {}; loading = false; draw(); }, function () { loading = false; draw(); });
      } else if (!F.cur || !el.contains(F.cur)) F.set(acts.firstChild);
    };
  };

  // ================================================================== series
  Screens.Series = function (src, it) {
    var self = this;
    this.name = 'series';
    var el = this.el = U.el('div', 'screen');
    el.style.background = '#0E0A0B';
    var info = null, season = null, eps = [];
    el.innerHTML = '<div class="sr-side"><div class="cov"></div><h2 class="cl2"></h2><div class="g"></div><div class="p"></div></div>' +
      '<div class="sr-main"><div class="seasons"><div class="in"></div></div><div class="vl eps"></div><div class="msg"></div></div>';
    el.querySelector('h2').textContent = it.n;
    var cov = el.querySelector('.cov');
    if (it.i) cov.style.backgroundImage = 'url("' + it.i.replace(/"/g, '%22') + '")';
    var sbox = el.querySelector('.seasons .in');
    var epBox = el.querySelector('.eps');
    epBox.style.cssText = 'position:absolute;left:0;right:0;top:110px;height:' + (8 * 108) + 'px';
    var msg = el.querySelector('.msg');
    msg.style.cssText = 'position:absolute;left:0;right:0;top:300px;text-align:center;color:#8B93A3;font-size:30px';
    var list = new UI.VList(epBox, {
      rowH: 108, rows: 8, cls: 'eprow', margin: 1, upOut: true,
      make: function (r) { r.innerHTML = '<span class="en num"></span><span class="et"></span><span class="ex"></span>'; },
      render: function (r, e) {
        r.childNodes[0].textContent = e.num;
        r.childNodes[1].textContent = e.title;
        var started = Store.resume('ep:' + e.id) > 30;
        r.childNodes[2].innerHTML = (started ? '<span class="c">Continue</span>' : '') + (e.duration ? U.esc(e.duration) : '') + U.icon('play');
      },
      ok: function (i) { play(i); }
    });

    function drawSeasons() {
      sbox.innerHTML = '';
      if (!info) return;
      info.order.forEach(function (s) {
        var b = U.el('span', 'sbtn f' + (s === season ? ' sel' : ''), s === 0 ? 'Specials' : 'Season ' + s);
        b._ok = function () { pick(s); list.focus(0); };
        b._focus = function () { if (s !== season) pick(s); scrollSeasons(b); };
        b._key = function (k) {
          if (k === 'down' && eps.length) { list.focus(0); return true; }
          return false;
        };
        sbox.appendChild(b);
      });
    }
    function scrollSeasons(b) {
      var x = b.offsetLeft + b.offsetWidth - 1300;
      x = Math.max(0, x);
      sbox.style.webkitTransform = sbox.style.transform = 'translateX(' + (-x) + 'px)';
    }
    function pick(s) {
      season = s;
      eps = (info && info.seasons[s]) || [];
      var kids = sbox.childNodes;
      for (var i = 0; i < kids.length; i++) kids[i].classList.toggle('sel', info.order[i] === s);
      list.set(eps, 0);
    }
    function play(i) {
      if (!eps[i]) return;
      Nav.push(new Screens.Player({
        src: src, kind: 'episode', episodes: eps, index: i, title: it.n, poster: (info && info.cover) || it.i
      }));
    }

    this.show = function (first) {
      if (!first) { list.refresh(); return; }
      msg.innerHTML = '<span class="spin"></span>';
      src.seriesInfo(it.id).then(function (d) {
        info = d;
        if (d.cover && !it.i) cov.style.backgroundImage = 'url("' + d.cover.replace(/"/g, '%22') + '")';
        el.querySelector('.g').textContent = d.genre || '';
        el.querySelector('.p').textContent = d.plot || '';
        if (!d.order.length) { msg.textContent = 'No episodes available yet.'; return; }
        msg.innerHTML = '';
        // Start on the season with the last episode watched, else the first.
        var start = d.order[0];
        d.order.forEach(function (s) { d.seasons[s].forEach(function (e) { if (Store.resume('ep:' + e.id) > 30) start = s; }); });
        season = start;
        drawSeasons();
        pick(start);
        list.focus(0);
      }, function (e) {
        msg.textContent = Src.friendly(e);
      });
    };
  };
})();
