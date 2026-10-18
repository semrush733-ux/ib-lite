/* Full screen playback: live channels (zapping with Up / Down, channel list on Left, sound on Right)
 * and films / episodes / recordings (Left / Right jump, OK pauses). The bar appears on OK and
 * hides by itself. A channel logo or film cover is on screen at once and fades into the picture. */
(function () {
  'use strict';

  /** o: {src, kind: live|vod|episode|rec, items, index, adopt, urls, title, sub, poster, resumeKey,
   *      start, episodes, onClose(index), item (the film), series (of the episodes)} */
  Screens.Player = function (o) {
    var self = this;
    this.name = 'player';
    this.kind = o.kind;
    this.noFocus = true; // the bar's buttons take the remote only while the bar is on screen
    var live = o.kind === 'live', src = o.src;
    var items = o.items || [], index = o.index || 0, target = null, zapTimer = null;
    var episodes = o.episodes || null, ep = o.index || 0;
    var osdTimer = null, osdOn = false, epg = [], epgTimer = null, tick = null, saveTimer = null;
    var seekTarget = null, seekTimer = null, seekStreak = 0, lastSeek = 0, digits = '', digitTimer = null;
    var panel = null, dead = false;

    var el = this.el = U.el('div', 'screen pscr');
    el.innerHTML =
      '<div class="poster2"><div class="pic"></div><div class="tl"><div class="t1"></div><div class="st"></div></div></div>' +
      '<div class="dead hide">' + U.icon('error') + '<div class="t1"></div><div class="t2"></div></div>' +
      '<div class="osd">' +
      '<div class="top"><div class="tt"></div><div class="sub"></div><div class="right"><span class="qb hide"></span><span class="plname">' + U.icon('playlist') + '<span></span></span><span class="clk num"></span></div></div>' +
      '<div class="bot"><div class="lg"><img alt=""></div><div class="info"><div class="now"></div><div class="next"></div>' +
      '<div class="tl2 hide"><span class="pos num"></span><span class="bar"><i></i><b></b></span><span class="tot num"></span></div>' +
      '<div class="ctrls"><div class="lbl"></div><div class="btns"></div></div></div></div></div>' +
      '<div class="seekhint hide num"></div><div class="zapnum hide num"></div>';
    var poster = el.querySelector('.poster2'), osd = el.querySelector('.osd'), deadBox = el.querySelector('.dead');
    // Magic Remote: a click on the picture shows the bar (or tries again after a failure).
    el.addEventListener('click', function (e) {
      if (U.closest(e.target, 'f') || panel) return;
      if (dead) { setDead(false); pulse(true); Player.retry(); return; }
      showOsd(true);
    });
    var btnBox = el.querySelector('.btns'), lbl = el.querySelector('.lbl'), tl = el.querySelector('.tl2');
    el.querySelector('.plname span').textContent = App.title() || '';
    if (!App.title()) el.querySelector('.plname').classList.add('hide');

    function cur() { return live ? items[target != null ? target : index] : null; }
    function epNow() { return episodes ? episodes[ep] : null; }
    function resumeKey() { return episodes ? 'ep:' + epNow().id : (o.resumeKey || ''); }
    function titleText() {
      if (live) { var it = cur(); return it ? ((target != null ? target : index) + 1) + '.  ' + it.n : ''; }
      if (episodes) { var e = epNow(); return o.title + '  ·  S' + e.season + ' E' + e.num; }
      return o.title || '';
    }
    function subText() {
      if (episodes) return epNow().title;
      return o.sub || '';
    }
    function pic() {
      if (live) { var it = cur(); return it ? it.i : ''; }
      if (episodes && epNow().pic) return epNow().pic;
      return o.poster || '';
    }

    // ---------------------------------------------------------------- start picture (logo / cover)
    var posterHideTimer = null;
    function showPoster() {
      clearTimeout(posterHideTimer);
      var p = pic();
      var box = poster.querySelector('.pic');
      box.className = 'pic' + (live ? '' : ' vod');
      box.innerHTML = p ? '<img alt="">' : '';
      if (p) {
        var img = box.firstChild;
        img.style.opacity = '0';
        img.onload = function () { img.style.opacity = '1'; };
        img.onerror = function () { img.style.display = 'none'; };
        img.src = p;
      }
      poster.querySelector('.tl').className = 'tl' + (live ? '' : ' vod');
      poster.querySelector('.t1').textContent = titleText();
      poster.querySelector('.st').textContent = live ? '' : subText();
      poster.classList.remove('hide');
      poster.classList.remove('go');
    }
    function hidePoster() {
      if (poster.classList.contains('hide') || poster.classList.contains('go')) return;
      poster.classList.add('go');
      posterHideTimer = setTimeout(function () { poster.classList.add('hide'); }, 300);
    }
    function pulse(on) {
      var p = el.querySelector('.pulse.pp');
      if (on && !p) el.appendChild(UI.pulse('late pp'));
      if (!on && p) p.parentNode.removeChild(p);
    }
    function setDead(on, text) {
      dead = on;
      deadBox.classList.toggle('hide', !on);
      if (on) {
        deadBox.querySelector('.t1').textContent = text || (live ? 'This channel is not available right now.' : 'This video could not be played.');
        deadBox.querySelector('.t2').textContent = live ? 'OK = try again  ·  Up / Down = another channel' : 'OK = try again  ·  Back = leave';
      }
    }

    // ---------------------------------------------------------------- the bar (OSD)
    function drawTop() {
      el.querySelector('.top .tt').textContent = titleText();
      var sub = subText();
      el.querySelector('.top .sub').textContent = sub;
      el.querySelector('.top .sub').classList.toggle('hide', !sub);
      el.querySelector('.clk').textContent = U.hm(new Date());
      var lg = el.querySelector('.bot .lg');
      lg.className = 'lg' + (live ? '' : ' vod');
      UI.setImg(lg.querySelector('img'), pic());
      lg.querySelector('img').classList.add('ok');
      drawQuality();
    }
    /** The picture size the stream really delivers (4K shows as 4K only when it is). */
    function drawQuality() {
      var vs = Player.videoSize(), w = vs.w || 0, h = vs.h || 0, q = el.querySelector('.qb');
      var label = !w || !h || Player.state() === 'error' ? '' : w >= 3200 || h >= 2000 ? '4K UHD' : w >= 1800 || h >= 1000 ? 'FULL HD' : w >= 1200 || h >= 700 ? 'HD' : 'SD';
      q.classList.toggle('hide', !label);
      if (label) q.innerHTML = '<b>' + label + '</b>' + w + ' × ' + h;
    }
    function drawGuide() {
      var now = el.querySelector('.bot .now'), next = el.querySelector('.bot .next');
      if (!live) { now.classList.add('hide'); next.classList.add('hide'); return; }
      now.classList.remove('hide');
      var t = Date.now(), c = null, n = null;
      if (target == null) {
        for (var i = 0; i < epg.length; i++) {
          if (epg[i].start <= t && epg[i].end > t) c = epg[i];
          else if (epg[i].start > t && !n) n = epg[i];
        }
      }
      if (c) {
        var p = Math.max(0, Math.min(1, (t - c.start) / Math.max(1, c.end - c.start)));
        now.className = 'now';
        now.innerHTML = '<span class="num">' + U.hm(new Date(c.start)) + ' – ' + U.hm(new Date(c.end)) + '</span>   ' + U.esc(c.title) +
          '<div class="prog" style="width:1200px"><i style="width:' + Math.round(p * 100) + '%"></i></div>';
      } else {
        now.className = 'now none';
        now.textContent = target != null ? '' : 'No TV guide for this channel';
      }
      next.classList.toggle('hide', !n);
      if (n) next.innerHTML = 'Next  <span class="num">' + U.hm(new Date(n.start)) + '</span>   ' + U.esc(n.title);
    }
    function drawTime() {
      if (live) { tl.classList.add('hide'); return; }
      var d = Player.dur(), p = seekTarget != null ? seekTarget : Player.pos();
      tl.classList.toggle('hide', !d);
      if (!d) return;
      var f = Math.max(0, Math.min(1, p / d));
      tl.querySelector('.pos').textContent = U.time(p);
      tl.querySelector('.tot').textContent = U.time(d);
      tl.querySelector('.bar i').style.width = (f * 100) + '%';
      tl.querySelector('.bar b').style.left = (f * 100) + '%';
    }
    var buttons = [], mainBtn = null;
    function button(icon, label, ok, opts) {
      opts = opts || {};
      var b = U.el('span', 'rb f' + (opts.big ? ' big' : '') + (opts.gap ? ' gap' : '') + (opts.act ? ' act' : ''), U.icon(icon));
      b._ok = function () { touch(); ok(b); };
      b._focus = function () {
        if (!osdOn) showOsd(false); // pointed at with the Magic Remote while the bar was away
        lbl.textContent = typeof label === 'function' ? label() : label;
        touch();
      };
      b._key = function (k) {
        if (k === 'left' || k === 'right') {
          var i = buttons.indexOf(b) + (k === 'right' ? 1 : -1);
          if (i >= 0 && i < buttons.length) F.set(buttons[i]);
          touch();
          return true;
        }
        if (k === 'up' && !live && !tl.classList.contains('hide')) { F.set(tl); touch(); return true; }
        return false;
      };
      btnBox.appendChild(b);
      buttons.push(b);
      return b;
    }
    function drawButtons() {
      btnBox.innerHTML = '';
      buttons = [];
      var many = live ? items.length > 1 : (episodes && episodes.length > 1);
      if (live) {
        if (many) mainBtn = button('list', 'Channel list', openList, { big: true });
        if (many) button('prev', 'Previous channel', function () { zap(-1); });
        if (many) button('next', 'Next channel', function () { zap(1); });
        var b = button('audio', 'Sound', openOptions, { gap: true });
        if (!many) mainBtn = b;
        var fav = cur() && Store.isFav(cur());
        button(fav ? 'star' : 'starb', function () { return cur() && Store.isFav(cur()) ? 'Remove from Favourites' : 'Add to Favourites'; }, function (bt) {
          var it = cur();
          if (!it) return;
          var added = Store.toggleFav(it);
          bt.innerHTML = U.icon(added ? 'star' : 'starb');
          bt.classList.toggle('act', added);
          lbl.textContent = added ? 'Added to Favourites' : 'Removed from Favourites';
        }, { act: fav });
      } else {
        if (many) button('prev', 'Previous episode', function () { step(-1); });
        button('rw', 'Back 10 seconds', function () { seekBy(-1); });
        mainBtn = button(Player.state() === 'paused' ? 'play' : 'pause', function () { return Player.state() === 'paused' ? 'Play' : 'Pause'; }, function (bt) {
          Player.toggle();
          setTimeout(function () { bt.innerHTML = U.icon(Player.state() === 'paused' ? 'play' : 'pause'); lbl.textContent = Player.state() === 'paused' ? 'Play' : 'Pause'; }, 50);
        }, { big: true });
        button('ff', 'Forward 10 seconds', function () { seekBy(1); });
        if (many) button('next', 'Next episode', function () { step(1); });
        button('audio', 'Sound', openOptions, { gap: true });
      }
      button('back', 'Back', function () { leave(); });
    }
    tl.classList.add('f');
    tl._focus = function () { lbl.textContent = 'Left / Right to jump back or forward, Down for the buttons'; touch(); };
    tl._key = function (k) {
      touch();
      if (k === 'left' || k === 'right') { seekBy(k === 'right' ? 1 : -1); return true; }
      if (k === 'down') { if (mainBtn) F.set(mainBtn); return true; }
      if (k === 'up') return true;
      return false;
    };
    tl._ok = function () { Player.toggle(); touch(); };

    function showOsd(focus) {
      drawTop();
      drawGuide();
      drawTime();
      osd.classList.add('show');
      osdOn = true;
      if (focus && !panel) {
        if (!buttons.length) drawButtons();
        if (!F.cur || !el.contains(F.cur)) F.set(mainBtn || buttons[0]);
      }
      touch();
    }
    function hideOsd() {
      osd.classList.remove('show');
      osdOn = false;
      clearTimeout(osdTimer);
      if (F.cur && osd.contains(F.cur)) F.clear();
    }
    function touch() {
      clearTimeout(osdTimer);
      if (!osdOn) return;
      osdTimer = setTimeout(function () {
        if (panel || (!live && Player.state() === 'paused' && F.cur && osd.contains(F.cur))) { touch(); return; }
        hideOsd();
      }, live ? 5000 : 4500);
    }
    function onFocusedBar() { return osdOn && F.cur && osd.contains(F.cur); }

    // ---------------------------------------------------------------- live: zapping
    function loadEpg() {
      clearTimeout(epgTimer);
      epg = [];
      var it = items[index];
      if (!live || !it) return;
      epgTimer = setTimeout(function () {
        src.epg(it).then(function (l) { if (items[index] === it) { epg = l; if (osdOn) drawGuide(); } }, function () {});
      }, 600);
    }
    function tune(i, quietPoster) {
      index = i;
      target = null;
      var it = items[i];
      Store.addRecent(it);
      setDead(false);
      if (!quietPoster) showPoster();
      Player.setMuted(false);
      pulse(true);
      Player.open(src.liveUrls(it), { live: true, loop: !!(src.loops && src.loops(it)) });
      loadEpg();
      if (osdOn) { drawTop(); drawGuide(); }
      if (buttons.length) drawButtons();
    }
    function zap(step) {
      if (items.length < 2) return;
      var from = target != null ? target : index;
      target = (from + step + items.length) % items.length;
      Player.setMuted(true);
      showPoster();
      setDead(false);
      showOsd(false);
      clearTimeout(zapTimer);
      zapTimer = setTimeout(function () { var t = target; if (t != null) tune(t, true); }, 400);
    }
    function digit(dgt) {
      if (!live) return;
      digits = (digits + dgt).substring(0, 5);
      var z = el.querySelector('.zapnum');
      z.textContent = digits;
      z.classList.remove('hide');
      clearTimeout(digitTimer);
      digitTimer = setTimeout(function () {
        z.classList.add('hide');
        var n = parseInt(digits, 10) - 1;
        digits = '';
        if (n >= 0 && n < items.length && n !== index) { target = n; showPoster(); showOsd(false); tune(n, true); }
      }, 1400);
    }

    // ---------------------------------------------------------------- films: jumping and episodes
    function seekBy(dir) {
      var d = Player.dur();
      if (!d) return;
      var now = Date.now();
      seekStreak = now - lastSeek < 900 ? seekStreak + 1 : 0;
      lastSeek = now;
      var stepS = seekStreak < 3 ? 10 : seekStreak < 8 ? 30 : 60;
      var base = seekTarget != null ? seekTarget : Player.pos();
      seekTarget = Math.max(0, Math.min(d - 3, base + dir * stepS));
      var h = el.querySelector('.seekhint');
      var diff = Math.round(seekTarget - Player.pos());
      h.textContent = (diff >= 0 ? '+' : '−') + U.time(Math.abs(diff)) + '   ' + U.time(seekTarget);
      h.classList.remove('hide');
      if (!osdOn) showOsd(false);
      drawTime();
      touch();
      clearTimeout(seekTimer);
      seekTimer = setTimeout(function () {
        h.classList.add('hide');
        if (seekTarget != null) Player.seek(seekTarget);
        seekTarget = null;
      }, 700);
    }
    /** What the Continue Watching row on the home screen shows for this film or episode. */
    function cwWhat() {
      if (episodes) {
        var e = epNow();
        return o.series ? { key: 'ep:' + e.id, t: o.title, s: Store.epLabel(e), img: o.poster, item: o.series, ep: e } : null;
      }
      return o.kind === 'vod' && o.item && o.resumeKey ? { key: o.resumeKey, t: o.title, s: o.sub, img: o.poster, item: o.item } : null;
    }
    function saveResume() {
      var key = resumeKey();
      if (!key || o.kind === 'rec') return;
      var p = Player.pos(), d = Player.dur();
      if (!d || p < 5) return;
      Store.setResume(key, p > 30 && p < d - 60 ? p : 0);
      Store.noteContinue(cwWhat(), p, d);
    }
    function openVod(start) {
      setDead(false);
      showPoster();
      pulse(true);
      var urls = o.urls;
      if (episodes) urls = src.episodeUrls ? src.episodeUrls(epNow()) : [src.episodeUrl(epNow())];
      var s = start != null ? start : Store.resume(resumeKey());
      Player.open(urls, { live: false, start: s > 30 ? s : 0 });
      if (osdOn) drawTop();
    }
    /** finished: the episode was watched to the end (its place is not kept). */
    function step(d, finished) {
      if (!episodes) return;
      var to = ep + d;
      if (to < 0 || to >= episodes.length) return;
      if (!finished) saveResume();
      ep = to;
      openVod();
      drawButtons();
    }

    // ---------------------------------------------------------------- side panels
    function closePanel() {
      if (!panel) return;
      panel.parentNode.removeChild(panel);
      panel = null;
      F.clear();
      if (osdOn) F.set(mainBtn || buttons[0]);
    }
    function openList() {
      if (!live || items.length < 2) return;
      hideOsd();
      panel = U.el('div', 'chlist');
      panel.innerHTML = '<h3>' + U.esc(o.title || 'Channels') + '</h3>';
      var box = U.el('div', 'vl');
      box.style.cssText = 'position:absolute;left:30px;right:30px;top:100px;height:' + (9 * 98) + 'px';
      panel.appendChild(box);
      el.appendChild(panel);
      var list = new UI.VList(box, {
        rowH: 98, rows: 9, cls: 'chrow', margin: 2,
        make: function (r) {
          r.innerHTML = '<span class="no num"></span><img class="lg" alt=""><span class="nm"><span></span></span><span class="st"></span>';
          r.style.height = '88px';
        },
        render: function (r, it, i) {
          r.childNodes[0].textContent = i + 1;
          UI.setImg(r.childNodes[1], it.i);
          r.childNodes[2].firstChild.textContent = it.n;
          r.childNodes[3].innerHTML = Store.isFav(it) ? U.icon('star') : '';
        },
        ok: function (i) {
          closePanel();
          if (i !== index) { target = i; tune(i); } else showOsd(false);
        }
      });
      list.set(items, index, index);
      list.focus(index);
    }
    function openOptions() {
      var tracks = Player.audioTracks();
      hideOsd();
      panel = U.el('div', 'optlist');
      panel.innerHTML = '<h3>Sound</h3>';
      if (tracks.length < 2) {
        var only = U.el('div', 'opt f sel', U.icon('radioOn') + (tracks.length ? U.esc(tracks[0].label) : 'Standard sound'));
        only._ok = closePanel;
        panel.appendChild(only);
      } else {
        tracks.forEach(function (t) {
          var r = U.el('div', 'opt f' + (t.on ? ' sel' : ''), U.icon(t.on ? 'radioOn' : 'radioOff') + U.esc(t.label + (t.lang && t.label !== t.lang ? '  (' + t.lang + ')' : '')));
          r._ok = function () { Player.setAudio(t.i); closePanel(); UI.toast('Sound: ' + t.label, 1500); };
          panel.appendChild(r);
        });
      }
      var size = Player.size();
      if (size) panel.appendChild(U.el('div', 'dim', '<div style="font-size:24px;margin:14px 10px 4px">Picture ' + U.esc(size) + '</div>'));
      el.appendChild(panel);
      var first = panel.querySelector('.opt.sel') || panel.querySelector('.opt');
      F.set(first);
    }

    // ---------------------------------------------------------------- player events
    function onPlayer(ev, d) {
      if (Nav.top() !== self) return;
      if ((ev === 'first' || ev === 'meta') && osdOn) drawQuality();
      if (ev === 'first') { hidePoster(); pulse(false); return; }
      if (ev !== 'state') return;
      if (d.state === 'playing') { pulse(false); hidePoster(); setDead(false); }
      else if (d.state === 'loading' || d.state === 'buffering') pulse(true);
      else if (d.state === 'paused') { pulse(false); showOsd(true); }
      else if (d.state === 'error') {
        pulse(false);
        showPoster();
        setDead(true);
      } else if (d.state === 'ended') {
        var more = episodes && ep + 1 < episodes.length;
        Store.setResume(resumeKey(), 0);
        Store.finishContinue(cwWhat(), more ? episodes[ep + 1] : null);
        if (more) step(1, true); else leave(true);
      }
      if (buttons.length && !live && mainBtn) mainBtn.innerHTML = U.icon(Player.state() === 'paused' ? 'play' : 'pause');
    }
    Player.on(onPlayer);

    function leave(ended) {
      if (!ended) saveResume();
      Nav.pop();
    }

    // ---------------------------------------------------------------- keys
    this.onKey = function (k) {
      if (panel) {
        if (k === 'back') { closePanel(); return true; }
        if (k === 'left' && panel.className === 'chlist') { closePanel(); return true; }
        if (k === 'right' && panel.className === 'chlist') return true;
        if ((k === 'left' || k === 'right') && panel.className === 'optlist') { closePanel(); return true; }
        return false;
      }
      if (k.length === 2 && k.charAt(0) === 'd') { digit(k.charAt(1)); return true; }
      if (live) {
        if (k === 'up' || k === 'chup') { zap(1); return true; }
        if (k === 'down' || k === 'chdown') { zap(-1); return true; }
        if (k === 'info') { showOsd(true); return true; }
      } else {
        if (k === 'rw') { seekBy(-1); return true; }
        if (k === 'ff') { seekBy(1); return true; }
        if (k === 'playpause' || k === 'play' || k === 'pause') {
          if (k === 'playpause' || (k === 'play' && Player.state() === 'paused') || (k === 'pause' && Player.state() !== 'paused')) Player.toggle();
          showOsd(false);
          return true;
        }
        if (k === 'stop') { leave(); return true; }
      }
      if (k === 'back') {
        if (onFocusedBar() || osdOn) { hideOsd(); return true; }
        leave();
        return true;
      }
      if (onFocusedBar()) return false; // the buttons move and press themselves
      if (k === 'ok') {
        if (dead) { setDead(false); pulse(true); Player.retry(); return true; }
        showOsd(true);
        return true;
      }
      if (live) {
        if (osdOn && (k === 'left' || k === 'right')) { showOsd(true); return true; }
        if (k === 'left') { openList(); return true; }
        if (k === 'right') { openOptions(); return true; }
        return true;
      }
      if (k === 'left' || k === 'right') { seekBy(k === 'right' ? 1 : -1); return true; }
      if (k === 'up' || k === 'down') { showOsd(true); return true; }
      return true;
    };

    // ---------------------------------------------------------------- life
    this.show = function (first) {
      if (!first) return;
      Player.layout('full');
      drawButtons();
      if (live) {
        if (o.adopt && Player.active() && Player.state() !== 'error') {
          poster.classList.add('hide');
          if (Player.state() !== 'playing') { showPoster(); pulse(true); }
          loadEpg();
          Store.addRecent(items[index]);
        } else {
          tune(index);
        }
        showOsd(false);
      } else {
        openVod(o.start);
        showOsd(false);
        saveTimer = setInterval(saveResume, 10000);
      }
      tick = setInterval(function () {
        if (!osdOn) return;
        el.querySelector('.clk').textContent = U.hm(new Date());
        drawQuality();
        if (live) drawGuide(); else drawTime();
      }, live ? 15000 : 500);
    };
    this.destroy = function () {
      clearTimeout(zapTimer); clearTimeout(osdTimer); clearTimeout(epgTimer); clearTimeout(seekTimer);
      clearTimeout(digitTimer); clearTimeout(posterHideTimer);
      clearInterval(tick); clearInterval(saveTimer);
      Player.off(onPlayer);
      Player.setMuted(false);
      if (live) {
        if (target != null) { target = null; }
        if (Player.state() === 'error') Player.stop();
        if (o.onClose) o.onClose(index);
        if (!Player.active()) Player.layout('off');
      } else {
        Player.stop();
        Player.layout('off');
      }
    };
  };
})();
