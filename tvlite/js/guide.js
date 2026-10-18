/* TV Guide (as in the Android app): channels down the side, their programmes along a time line and
 * the chosen programme's details on top, next to the picture that is playing.
 *   Up / Down: channel · Left / Right: earlier / later programme · CH+ / CH-: a page of channels
 *   OK: on now = watch the channel · past, with a recording = catch-up · coming up = a reminder
 *   Play: back to now · numbers: a channel number · Back: close
 * Reminders: while the app is open, a message comes when a chosen programme starts ("Watch now"). */
(function () {
  'use strict';

  var ROW_H = 90, ROWS = 7, SIDE_W = 430, PER_MIN = 14, LEFT = 56, GRID_W = 1920 - 2 * LEFT - SIDE_W - 12;
  var MIN = 60000, HALF = 30 * MIN, HOUR = 60 * MIN;
  var VISIBLE = Math.floor(GRID_W / PER_MIN) * MIN; // the time the grid shows (about 1 h 35)

  /** The local half hour at or before t. */
  function floor30(t) {
    var d = new Date(t);
    d.setMinutes(d.getMinutes() < 30 ? 0 : 30, 0, 0);
    return d.getTime();
  }
  function dayStart(t) { var d = new Date(t); d.setHours(0, 0, 0, 0); return d.getTime(); }
  /** "Today", "Yesterday", "Tomorrow" or "Mon 19 Oct". */
  function dayName(t) {
    var diff = Math.round((dayStart(t) - dayStart(Date.now())) / (24 * HOUR));
    if (diff === 0) return 'Today';
    if (diff === -1) return 'Yesterday';
    if (diff === 1) return 'Tomorrow';
    var d = new Date(t);
    return U.days[d.getDay()].substring(0, 3) + ' ' + d.getDate() + ' ' + U.months[d.getMonth()];
  }
  function hm(t) { return U.hm(new Date(t)); }
  App.guideDay = dayName;

  /** Catch-up needs the server's recordings (Xtream Codes). */
  function canCatchup(src) { return !!(src && typeof src.recordingUrls === 'function'); }
  function recorded(src, it, e) { return canCatchup(src) && !!(e.archive || (it && it.a)); }

  // ================================================================== reminders
  /** {ch: the channel, t: title, s: start, e: end (milliseconds)}; kept per playlist account. */
  var Reminders = App.reminders = {};
  function keyOf(ch, start) { return ch.id + '|' + Math.floor(start / 1000); }
  Reminders.all = function () {
    var now = Date.now();
    return (Store.reminders() || []).filter(function (r) { return r && r.ch && r.e > now; });
  };
  Reminders.has = function (ch, start) {
    var k = keyOf(ch, start), l = Reminders.all();
    for (var i = 0; i < l.length; i++) if (keyOf(l[i].ch, l[i].s) === k) return true;
    return false;
  };
  /** Sets or removes the reminder of a programme; true when it is set afterwards. */
  Reminders.toggle = function (ch, e) {
    var k = keyOf(ch, e.start), l = Reminders.all(), had = false;
    l = l.filter(function (r) { if (keyOf(r.ch, r.s) === k) { had = true; return false; } return true; });
    if (!had) l.push({ ch: ch, t: e.title || ch.n, s: e.start, e: e.end });
    l.sort(function (a, b) { return a.s - b.s; });
    Store.setReminders(l.slice(0, 60));
    App.log('reminder ' + (had ? 'removed' : 'set'));
    return !had;
  };
  Reminders.remove = function (r) {
    var k = keyOf(r.ch, r.s);
    Store.setReminders(Reminders.all().filter(function (x) { return keyOf(x.ch, x.s) !== k; }));
  };

  var shown = {}, showing = null, remTimer = null;
  /** Looks at the clock every 15 seconds (from the start of the app). */
  Reminders.start = function () {
    if (remTimer) return;
    remTimer = setInterval(Reminders.check, 15000);
  };
  Reminders.check = function () {
    if (showing || App.blocked || !App.src || !Nav.find('home') || UI.topDialog()) return;
    var now = Date.now(), list = Reminders.all();
    for (var i = 0; i < list.length; i++) {
      var r = list[i], k = keyOf(r.ch, r.s);
      if (shown[k]) continue;
      // Up to a minute early, and as long as the programme is on.
      if (r.s - now > MIN || r.e <= now) continue;
      shown[k] = 1;
      Reminders.remove(r);
      // A Kids profile is not told about channels it may not watch.
      if (!Store.allowed(r.ch)) continue;
      // Already on that channel: nothing to say.
      var t = Nav.top();
      if (t && t.name === 'player' && t.kind === 'live' && t.channel && t.channel() && t.channel().id === r.ch.id) continue;
      show(r);
      return;
    }
  };
  function show(r) {
    var started = r.s <= Date.now();
    var box = U.el('div', 'rmd');
    box.innerHTML = '<div class="lg"><img alt=""></div><div class="tx"><div class="t"></div><div class="s"></div></div>';
    UI.setImg(box.querySelector('img'), r.ch.i);
    box.querySelector('.t').textContent = r.t;
    box.querySelector('.s').textContent = r.ch.n + '  ·  ' + hm(r.s) + ' – ' + hm(r.e);
    App.log('reminder shown');
    var d = showing = UI.dialog({
      title: started ? 'Starting now' : 'Starting in a minute', html: box, width: 1100,
      buttons: [{ label: 'Dismiss' }, { label: 'Watch now', icon: 'play', pri: true, ok: function () { watch(r); } }],
      focus: 1, onClose: function () { showing = null; clearTimeout(gone); }
    });
    d.box.classList.add('rmdlg');
    d.box.querySelector('h2').innerHTML = U.icon('bell') + U.esc(started ? 'Starting now' : 'Starting in a minute');
    // Nobody there: the message goes away by itself after a few minutes.
    var gone = setTimeout(function () { d.close(); }, 4 * MIN);
  }
  /** "Watch now": back to the home screen, then the channel plays with the others of its category. */
  function watch(r) {
    var src = App.src, ch = r.ch;
    if (!src) return;
    function go() {
      UI.closeAll();
      Player.stop();
      Player.layout('off');
      while (Nav.stack.length > 1 && Nav.top().name !== 'home') Nav.pop();
      if (!Nav.top() || Nav.top().name !== 'home') return;
      var cat = ch.c || '', home = Nav.top();
      Promise.all([
        cat ? withTimeout(src.items('live', cat), 6000).then(null, function () { return null; }) : Promise.resolve(null),
        cat ? withTimeout(src.categories('live'), 6000).then(null, function () { return []; }) : Promise.resolve([])
      ]).then(function (res) {
        if (Nav.top() !== home) return;
        var items = (res[0] || []).filter(Store.allowed), idx = -1, name = '';
        (res[1] || []).forEach(function (c) { if (c.id === cat) name = c.name; });
        for (var i = 0; i < items.length; i++) if (items[i].id === ch.id) { idx = i; break; }
        if (idx < 0) { items = [ch]; idx = 0; }
        App.log('reminder: watching');
        Nav.push(new Screens.Player({
          src: src, kind: 'live', items: items, index: idx, title: name,
          onClose: function () { Player.stop(); Player.layout('off'); }
        }));
      });
    }
    // A channel in a locked category still needs the parental PIN.
    if (Store.isLocked('live', ch.c) && !Store.parentalUnlocked) App.askPin('Parental PIN', go);
    else go();
  }
  function withTimeout(p, ms) {
    return Promise.race([p, new Promise(function (res, rej) { setTimeout(function () { rej(new Error('timeout')); }, ms); })]);
  }

  // ================================================================== the guide of a channel
  /** Everything the playlist's guide has for one channel, oldest first (kept 15 minutes). */
  function guideOf(src, it) {
    var cache = src._guide || (src._guide = { m: {}, keys: [] }), hit = cache.m[it.id];
    if (hit && Date.now() - hit.at < 15 * MIN) return Promise.resolve(hit.list);
    var load = typeof src.guide === 'function' ? src.guide(it) : src.epg(it);
    return load.then(function (l) {
      l = l || [];
      cache.m[it.id] = { at: Date.now(), list: l };
      cache.keys.push(it.id);
      while (cache.keys.length > 300) delete cache.m[cache.keys.shift()];
      return l;
    });
  }
  App.guideOf = guideOf;

  // ================================================================== the screen
  /** o: {src, items (channels), index, title, onPick({channel: i} or {archive: {urls, title, sub, poster}})} */
  Screens.Guide = function (o) {
    var self = this;
    this.name = 'guide';
    this.noFocus = true; // the screen moves its own selection
    var src = o.src, items = o.items || [];
    var row = Math.max(0, Math.min(items.length - 1, o.index || 0)), top = 0;
    var cursor = Date.now(), viewStart = floor30(cursor) - HALF;
    var lists = {}, loading = {}, queue = [], running = 0, loadTimer = null, clock = null, digits = '', digitTimer = null;

    var el = this.el = U.el('div', 'screen guide');
    el.innerHTML =
      '<div class="gd-top"><div class="gd-card"></div><div class="gd-logo"><img alt=""></div>' +
      '<div class="gd-info"><div class="l1"><span class="n num"></span><span class="ch"></span><span class="clk num"></span></div>' +
      '<div class="t"></div><div class="l3"></div><div class="d"></div></div>' +
      '<div class="gd-pv"><div class="frame"></div><div class="idle"></div></div></div>' +
      '<div class="gd-ruler"><span class="day"></span><div class="tl"></div></div>' +
      '<div class="gd-grid"><div class="gd-rows"></div><div class="gd-now"></div></div>' +
      '<div class="gd-hint">' + U.icon('chevL') + U.icon('chevR') + ' programme   ·   CH+ / CH− page   ·   OK watch (past: catch-up, coming up: remind me)   ·   ' +
      U.icon('play') + ' back to now</div>';
    var logoImg = el.querySelector('.gd-logo img'), info = el.querySelector('.gd-info'), pv = el.querySelector('.gd-pv');
    var rowsBox = el.querySelector('.gd-rows'), nowLine = el.querySelector('.gd-now');
    var ruler = el.querySelector('.gd-ruler .tl'), dayEl = el.querySelector('.gd-ruler .day');
    var rowEls = [];
    for (var p = 0; p < ROWS; p++) {
      var r = U.el('div', 'gr');
      r.style.top = (p * ROW_H) + 'px';
      r.innerHTML = '<div class="side"><span class="no num"></span><img alt=""><span class="nm"><span></span></span></div><div class="cells"></div>';
      r._pos = p;
      rowsBox.appendChild(r);
      rowEls.push(r);
    }
    if (!items.length) rowsBox.innerHTML = '<div class="empty">No channels.</div>';

    // ---------------------------------------------------------------- loading (the rows around the selection)
    function scheduleLoad() {
      clearTimeout(loadTimer);
      loadTimer = setTimeout(function () {
        queue = [row];
        for (var i = Math.max(0, row - 4); i <= Math.min(items.length - 1, row + 9); i++) if (i !== row) queue.push(i);
        pump();
      }, 200);
    }
    function pump() {
      while (running < 3 && queue.length) {
        var i = queue.shift(), it = items[i];
        if (!it || lists[it.id] || loading[it.id]) continue;
        loading[it.id] = true;
        running++;
        (function (it) {
          guideOf(src, it).then(function (l) { lists[it.id] = l; }, function () { lists[it.id] = []; }).then(function () {
            delete loading[it.id];
            running--;
            if (dead) return;
            draw();
            pump();
          });
        })(it);
      }
    }
    var dead = false;

    // ---------------------------------------------------------------- selection
    function listOf(i) { var it = items[i]; return it ? lists[it.id] || null : null; }
    function at(i, t) {
      var l = listOf(i) || [];
      for (var k = 0; k < l.length; k++) if (l[k].start <= t && l[k].end > t) return l[k];
      return null;
    }
    function selected() { return at(row, cursor); }
    function keepCursorVisible() {
      if (cursor < viewStart + 5 * MIN || cursor > viewStart + VISIBLE - 20 * MIN) viewStart = floor30(cursor) - HALF;
    }
    function keepRowVisible() {
      if (row < top) top = row;
      if (row > top + ROWS - 1) top = row - ROWS + 1;
      top = Math.max(0, Math.min(Math.max(0, items.length - ROWS), top));
    }
    function moveRow(step, wrap) {
      var n = items.length;
      if (!n) return;
      row = wrap ? (row + step + n) % n : Math.max(0, Math.min(n - 1, row + step));
      keepRowVisible();
      draw();
      scheduleLoad();
    }
    /** Left / Right: the programme before / after; where the guide has nothing, half an hour. */
    function moveTime(step) {
      var l = listOf(row) || [], sel = selected(), target = null, k;
      if (sel) {
        var j = l.indexOf(sel) + step;
        if (j >= 0 && j < l.length) target = l[j];
      } else if (step > 0) {
        for (k = 0; k < l.length; k++) if (l[k].start > cursor) { target = l[k]; break; }
      } else {
        for (k = l.length - 1; k >= 0; k--) if (l[k].end <= cursor) { target = l[k]; break; }
      }
      if (target && Math.abs(target.start - cursor) < 12 * HOUR) cursor = target.start + Math.min(MIN, (target.end - target.start) / 2);
      else cursor += step * HALF;
      keepCursorVisible();
      draw();
    }
    function jumpNow() {
      cursor = Date.now();
      viewStart = floor30(cursor) - HALF;
      draw();
    }

    // ---------------------------------------------------------------- drawing
    function x(t) { return (t - viewStart) / MIN * PER_MIN; }
    function drawRuler() {
      var html = '', slots = Math.ceil(VISIBLE / HALF) + 1;
      for (var i = 0; i < slots; i++) {
        html += '<span class="num" style="left:' + Math.round(i * 30 * PER_MIN) + 'px">' + hm(viewStart + i * HALF) + '</span>';
      }
      var nx = x(Date.now());
      if (nx >= 0 && nx <= GRID_W) html += '<i class="mk" style="left:' + Math.round(nx - 11) + 'px"></i>';
      ruler.innerHTML = html;
      dayEl.textContent = dayName(cursor);
      nowLine.style.display = nx >= 0 && nx <= GRID_W ? '' : 'none';
      nowLine.style.left = Math.round(SIDE_W + 12 + nx - 1) + 'px';
      nowLine.style.height = (Math.min(ROWS, Math.max(0, items.length - top)) * ROW_H - 8) + 'px';
    }
    function cellHtml(i, e, picked, now) {
      var from = Math.max(e.start, viewStart), left = x(from), width = x(e.end) - left;
      var past = e.end <= now, onNow = e.start <= now && e.end > now, it = items[i];
      var cls = 'c' + (picked ? ' on' : '') + (onNow ? ' n' : past ? ' p' : '');
      var ic = '';
      if (past && recorded(src, it, e)) ic = '<span class="ci rec">' + U.icon('history') + '</span>';
      else if (!past && !onNow && Reminders.has(it, e.start)) ic = '<span class="ci rem">' + U.icon('bell') + '</span>';
      return '<div class="' + cls + '" data-s="' + e.start + '" style="left:' + Math.round(left) + 'px;width:' + Math.max(6, Math.round(width) - 6) + 'px">' +
        '<b>' + ic + U.esc(e.title || 'Programme') + '</b>' + (width > 230 ? '<i class="tm num">' + hm(e.start) + ' – ' + hm(e.end) + '</i>' : '') + '</div>';
    }
    function drawRows() {
      var now = Date.now(), viewEnd = viewStart + VISIBLE + HALF, sel = selected();
      for (var p = 0; p < ROWS; p++) {
        var r = rowEls[p], i = top + p, it = items[i];
        if (!it) { r.style.display = 'none'; continue; }
        r.style.display = '';
        r._i = i;
        var on = i === row, side = r.firstChild;
        side.className = 'side' + (on ? ' on' : '');
        side.childNodes[0].textContent = i + 1;
        UI.setImg(side.childNodes[1], it.i);
        side.childNodes[2].firstChild.textContent = it.n;
        var l = listOf(i), html = '';
        if (l) {
          for (var k = 0; k < l.length; k++) {
            var e = l[k];
            if (e.end <= viewStart || e.start >= viewEnd) continue;
            html += cellHtml(i, e, on && e === sel, now);
          }
        }
        if (!html) {
          html = '<div class="c none' + (on ? ' on' : '') + '" style="left:0;width:' + (GRID_W - 6) + 'px"><b>' +
            (l ? 'No programme information' : 'Loading…') + '</b></div>';
        }
        r.lastChild.innerHTML = html;
      }
    }
    function badge(text, cls) { return '<span class="bdg ' + cls + '">' + U.esc(text) + '</span>'; }
    function drawInfo() {
      var it = items[row];
      if (!it) return;
      var now = Date.now(), sel = selected(), l = listOf(row);
      UI.setImg(logoImg, it.i);
      info.querySelector('.n').textContent = row + 1;
      info.querySelector('.ch').textContent = it.n;
      info.querySelector('.clk').textContent = dayName(now) + '  ' + hm(now);
      var t = info.querySelector('.t'), l3 = info.querySelector('.l3'), d = info.querySelector('.d');
      if (!sel) {
        t.textContent = l ? 'No programme information' : 'Loading the guide…';
        t.className = 't dim';
        l3.innerHTML = l ? '<span class="dim">OK = watch this channel</span>' : '';
        d.textContent = '';
        return;
      }
      t.className = 't';
      t.textContent = sel.title || 'Programme';
      var live = sel.start <= now && sel.end > now, past = sel.end <= now;
      var html = '<span class="tm num">' + U.esc(dayName(sel.start)) + '  ' + hm(sel.start) + ' – ' + hm(sel.end) + '  ·  ' +
        Math.round((sel.end - sel.start) / MIN) + ' min</span>';
      if (live) {
        var f = Math.max(0, Math.min(1, (now - sel.start) / Math.max(1, sel.end - sel.start)));
        html += badge('LIVE NOW', 'live') + '<span class="prog"><i style="width:' + Math.round(f * 100) + '%"></i></span>';
      } else if (past) {
        html += recorded(src, it, sel) ? badge('CATCH UP', 'rec') + '<span class="dim">OK = watch from the recording</span>' : '';
      } else {
        html += badge('COMING UP', 'up');
        html += Reminders.has(it, sel.start) ? badge('REMINDER SET', 'rem') + '<span class="dim">OK = remove</span>' : '<span class="dim">OK = remind me</span>';
      }
      l3.innerHTML = html;
      d.textContent = sel.desc || '';
    }
    function drawPreview() {
      var idle = pv.querySelector('.idle');
      if (Player.active() && Player.state() !== 'error') {
        idle.classList.add('hide');
        Player.layout('preview', App.rect(pv));
        return;
      }
      var it = items[row];
      idle.classList.remove('hide');
      idle.innerHTML = it && it.i ? '<img alt="">' : U.icon('live');
      if (it && it.i) UI.setImg(idle.firstChild, it.i);
    }
    function draw() {
      if (dead) return;
      drawRuler();
      drawRows();
      drawInfo();
      if (!Player.active()) drawPreview();
    }

    // ---------------------------------------------------------------- OK
    function toast(t) { UI.toast(t, 2600); }
    function act() {
      var it = items[row];
      if (!it) return;
      var sel = selected(), now = Date.now();
      if (!sel || (sel.start <= now && sel.end > now)) { pick({ channel: row }); return; }
      if (sel.end <= now) {
        if (recorded(src, it, sel)) {
          var d = new Date(sel.start);
          pick({ archive: {
            urls: src.recordingUrls(it, sel), title: sel.title || it.n, poster: it.i,
            sub: it.n + '  ·  ' + U.days[d.getDay()].substring(0, 3) + ' ' + d.getDate() + ' ' + U.months[d.getMonth()] + '  ' + hm(sel.start)
          } });
          return;
        }
        toast('This programme has no recording on the server.');
        return;
      }
      var on = Reminders.toggle(it, sel);
      draw();
      toast(on ? 'Reminder set: a message appears when "' + (sel.title || it.n) + '" starts (' + dayName(sel.start) + ' ' + hm(sel.start) + ', while the app is open).' : 'Reminder removed.');
    }
    function pick(r) {
      App.log('guide: ' + (r.channel != null ? 'channel' : 'catch-up'));
      Nav.pop();
      if (o.onPick) o.onPick(r);
    }
    function digit(dg) {
      digits = (digits + dg).substring(0, 5);
      UI.toast(digits, 1300);
      clearTimeout(digitTimer);
      digitTimer = setTimeout(function () {
        var n = parseInt(digits, 10) - 1;
        digits = '';
        if (n >= 0 && n < items.length) { row = n; keepRowVisible(); draw(); scheduleLoad(); }
      }, 1200);
    }

    // ---------------------------------------------------------------- keys and the pointer
    this.onKey = function (k) {
      if (k.length === 2 && k.charAt(0) === 'd') { digit(k.charAt(1)); return true; }
      switch (k) {
        case 'up': moveRow(-1, true); return true;
        case 'down': moveRow(1, true); return true;
        case 'chup': case 'rw': moveRow(-ROWS); return true;
        case 'chdown': case 'ff': moveRow(ROWS); return true;
        case 'left': moveTime(-1); return true;
        case 'right': moveTime(1); return true;
        case 'ok': act(); return true;
        case 'play': case 'playpause': case 'pause': jumpNow(); return true;
        case 'guide': case 'info': Nav.pop(); return true;
      }
      return k !== 'back';
    };
    el.addEventListener('click', function (e) {
      var c = U.closest(e.target, 'c'), r = U.closest(e.target, 'gr');
      if (!r || r._i == null) return;
      if (c && c.getAttribute('data-s')) {
        var s = +c.getAttribute('data-s');
        var picked = r._i === row && selected() && selected().start === s;
        if (picked) { act(); return; }
        row = r._i;
        cursor = s + MIN;
        draw();
        scheduleLoad();
        return;
      }
      if (r._i === row) { act(); return; }
      row = r._i;
      draw();
      scheduleLoad();
    });
    function wheel(e) {
      if (Nav.top() !== self) return;
      var dy = e.deltaY || -e.wheelDelta || 0;
      if (dy) moveRow(dy > 0 ? 1 : -1);
    }
    el.addEventListener('wheel', wheel);
    el.addEventListener('mousewheel', wheel);

    // ---------------------------------------------------------------- life
    this.show = function () {
      keepRowVisible();
      if (Player.active()) Player.layout('preview', App.rect(pv));
      drawPreview();
      draw();
      scheduleLoad();
      if (!clock) clock = setInterval(function () { drawRuler(); drawRows(); drawInfo(); }, 30000);
    };
    this.destroy = function () {
      dead = true;
      clearTimeout(loadTimer);
      clearTimeout(digitTimer);
      clearInterval(clock);
      queue = [];
    };
  };

  /** Opens the guide for these channels (o as for Screens.Guide). */
  App.openGuide = function (o) {
    if (!o.items || !o.items.length) { UI.toast('No channels here.', 1500); return; }
    App.log('guide: ' + o.items.length + ' channels');
    Nav.push(new Screens.Guide(o));
  };
})();
