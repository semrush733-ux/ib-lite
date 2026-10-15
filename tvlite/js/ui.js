/* Shared pieces: the brand logo, soft pulse, dialogs, toasts, text fields and fast remote lists. */
var UI = {}, Brand = {};

(function () {
  'use strict';

  // ------------------------------------------------------------------ brand (website: Settings > App look)
  var saved = S.get('brand', null) || {};
  Brand.name = saved.name || '';
  Brand.logoName = saved.logoName || '';
  Brand.icon = saved.icon || '';
  Brand.iconData = saved.iconData || '';

  /** Name drawn in the logo: the website's "Name on the app logo", else the app's name. */
  Brand.title = function () { return Brand.logoName || Brand.name || CONFIG.appName || 'Lite Player'; };
  Brand.symbol = function () { return Brand.iconData || Brand.icon || 'img/symbol.png'; };

  function store() {
    S.set('brand', { name: Brand.name, logoName: Brand.logoName, icon: Brand.icon, iconData: Brand.iconData });
  }

  /** The symbol is kept on the TV as a picture, so the next start shows it at once (no pop-in). */
  function keepIcon(url) {
    var x = new XMLHttpRequest();
    try {
      x.open('GET', url, true);
      x.responseType = 'blob';
      x.timeout = 20000;
      x.onload = function () {
        if (x.status !== 200 || !x.response || x.response.size > 600000 || x.response.size < 100) return;
        var r = new FileReader();
        r.onload = function () {
          if (Brand.icon !== url) return;
          Brand.iconData = String(r.result || '');
          store();
          App.log('brand symbol kept on the TV (' + Math.round(x.response.size / 1024) + 'KB)');
        };
        r.readAsDataURL(x.response);
      };
      x.send();
    } catch (e) {}
  }

  Brand.apply = function (b) {
    if (!b || typeof b !== 'object') return;
    var name = U.str(b.name), logoName = U.str(b.logo_name), icon = U.str(b.icon);
    var changed = name !== Brand.name || logoName !== Brand.logoName || icon !== Brand.icon;
    if (icon !== Brand.icon) Brand.iconData = '';
    Brand.name = name;
    Brand.logoName = logoName;
    Brand.icon = icon;
    if (changed) {
      store();
      UI.refreshLogos();
    }
    if (Brand.icon && !Brand.iconData) keepIcon(Brand.icon);
  };

  // ------------------------------------------------------------------ logo
  /** Symbol and name (first word white, the rest red), drawn sharp at any size. */
  UI.logo = function (size) {
    var name = Brand.title(), i = name.indexOf(' ');
    var first = i > 0 ? name.substring(0, i) : name, rest = i > 0 ? name.substring(i) : '';
    var h = Math.round(size * 1.5);
    return '<span class="logo" data-size="' + size + '">' +
      '<img src="' + U.esc(Brand.symbol()) + '" style="width:' + h + 'px;height:' + h + 'px" alt="">' +
      '<span class="n" style="font-size:' + size + 'px;margin-left:' + Math.round(size * 0.32) + 'px">' +
      '<span class="w">' + U.esc(first) + '</span>' + (rest ? '<span class="r">' + U.esc(rest) + '</span>' : '') +
      '</span></span>';
  };
  /** Only the brand symbol (small headers). */
  UI.symbol = function (px) {
    return '<img class="sym" src="' + U.esc(Brand.symbol()) + '" style="width:' + px + 'px;height:' + px + 'px;vertical-align:middle" alt="">';
  };
  UI.refreshLogos = function () {
    var syms = document.querySelectorAll('img.sym');
    for (var k = 0; k < syms.length; k++) syms[k].src = Brand.symbol();
    var list = document.querySelectorAll('.logo[data-size]');
    for (var i = 0; i < list.length; i++) {
      var d = U.el('span', '', UI.logo(U.int(list[i].getAttribute('data-size'))));
      list[i].parentNode.replaceChild(d.firstChild, list[i]);
    }
  };

  // ------------------------------------------------------------------ soft pulse
  /** The breathing dot of the player. late = shown only when loading takes over half a second. */
  UI.pulse = function (cls) {
    return U.el('div', 'pulse' + (cls ? ' ' + cls : ''), '<i class="ring"></i><i class="glow"></i><i class="dot"></i>');
  };

  // ------------------------------------------------------------------ toasts
  var toastTimer = null;
  UI.toast = function (text, ms) {
    var box = U.$('toast');
    box.innerHTML = '<span class="toastmsg">' + U.esc(text) + '</span>';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { box.innerHTML = ''; }, ms || 2200);
  };

  // ------------------------------------------------------------------ dialogs
  var dialogs = [];
  UI.topDialog = function () { return dialogs.length ? dialogs[dialogs.length - 1].el : null; };

  /** o: {title, html, buttons: [{label, icon, pri, ok, keep}], onBack, width, focus (index)} */
  UI.dialog = function (o) {
    var d = { o: o, prev: F.cur };
    var el = U.el('div');
    el.innerHTML = '<div class="veil"></div>';
    var box = U.el('div', 'dialog');
    if (o.width) { box.style.width = o.width + 'px'; box.style.marginLeft = (-o.width / 2) + 'px'; }
    box.innerHTML = (o.title ? '<h2>' + U.esc(o.title) + '</h2>' : '') + '<div class="body"></div><div class="acts"></div>';
    var body = box.querySelector('.body');
    if (typeof o.html === 'string') body.innerHTML = o.html;
    else if (o.html) body.appendChild(o.html);
    var acts = box.querySelector('.acts');
    var btns = [];
    (o.buttons || []).forEach(function (b) {
      var e = U.el('span', 'btn f' + (b.pri ? ' pri' : ''), (b.icon ? U.icon(b.icon) : '') + U.esc(b.label));
      e._ok = function () {
        if (!b.keep) d.close();
        if (b.ok) b.ok(d);
      };
      acts.appendChild(e);
      btns.push(e);
    });
    if (!btns.length) acts.style.display = 'none';
    el.appendChild(box);
    d.el = el;
    d.box = box;
    d.body = body;
    d.close = function () {
      var i = dialogs.indexOf(d);
      if (i < 0) return;
      dialogs.splice(i, 1);
      if (el.parentNode) el.parentNode.removeChild(el);
      if (d.o.onClose) d.o.onClose();
      F.clear();
      if (d.prev && document.body.contains(d.prev) && F.visible(d.prev)) F.set(d.prev, 'back');
      else F.first();
    };
    dialogs.push(d);
    U.$('dlg').appendChild(el);
    var first = o.focus != null ? btns[o.focus] : null;
    if (o.focusEl) first = o.focusEl;
    if (first) F.set(first); else if (!F.first(el)) F.clear();
    return d;
  };
  UI.closeTop = function (byBack) {
    var d = dialogs[dialogs.length - 1];
    if (!d) return;
    if (byBack && d.o.onBack && d.o.onBack(d)) return;
    d.close();
  };
  UI.closeAll = function () { while (dialogs.length) dialogs[dialogs.length - 1].close(); };

  UI.message = function (title, text, done) {
    return UI.dialog({ title: title, html: U.esc(text).replace(/\n/g, '<br>'), buttons: [{ label: 'OK', pri: true, ok: done }] });
  };

  UI.confirm = function (title, text, yes, no, ok) {
    return UI.dialog({
      title: title, html: U.esc(text),
      buttons: [{ label: no || 'Cancel' }, { label: yes || 'OK', pri: true, ok: ok }], focus: 1
    });
  };

  /** A text field the remote opens with OK (then the TV's keyboard comes up). */
  UI.field = function (o) {
    var f = U.el('div', 'field f');
    f.innerHTML = (o.icon ? U.icon(o.icon) : '') + '<input type="text" spellcheck="false" autocomplete="off">';
    var input = f.querySelector('input');
    input.value = o.value || '';
    input.placeholder = o.placeholder || '';
    input.tabIndex = -1;
    input._submit = function () { if (o.submit) o.submit(input.value); };
    f._ok = function () {
      try { input.focus(); } catch (e) {}
      try { var n = input.value.length; input.setSelectionRange(n, n); } catch (e2) {}
    };
    f.value = function () { return input.value; };
    f.input = input;
    return f;
  };

  /** Asks for a line of text (search, activation code). */
  UI.ask = function (title, value, placeholder, icon, done) {
    var field = UI.field({
      value: value, placeholder: placeholder, icon: icon,
      submit: function (v) { d.close(); done(U.str(v)); }
    });
    var wrap = U.el('div');
    wrap.appendChild(field);
    var d = UI.dialog({
      title: title, html: wrap, width: 1000,
      buttons: [{ label: 'Cancel' }, { label: title, pri: true, ok: function () { done(U.str(field.value())); } }],
      focusEl: field
    });
    // Open the keyboard straight away.
    setTimeout(function () { if (F.cur === field) field._ok(); }, 60);
    return d;
  };

  // ------------------------------------------------------------------ QR
  /** QR code of about px page pixels, drawn at twice the size and shown at exactly half: sharp edges. */
  UI.qr = function (text, px) {
    try {
      var c = QR.canvas(text, px * 2, '#000', '#fff');
      c.style.width = (c.width / 2) + 'px';
      c.style.height = (c.height / 2) + 'px';
      return c;
    } catch (e) { return U.el('div', '', ''); }
  };

  // ------------------------------------------------------------------ fast list for the remote
  /**
   * Only the rows on screen exist; scrolling just writes new text into them, so even 20 000 channels
   * move instantly.  o: {rowH, rows, cls, make(row), render(row, item, i), ok(i), long(i), focus(i),
   * margin, upOut (Up at the top leaves the list)}
   */
  function VList(box, o) {
    var self = this;
    this.box = box;
    this.o = o;
    this.items = [];
    this.top = 0;
    this.idx = 0;
    this.sel = -1;
    this.pool = [];
    var inner = U.el('div', 'rows');
    box.appendChild(inner);
    this.inner = inner;
    for (var p = 0; p < o.rows; p++) {
      var r = U.el('div', o.cls + ' f');
      r.style.top = (p * o.rowH) + 'px';
      r._pos = p;
      o.make(r);
      bind(r);
      inner.appendChild(r);
      this.pool.push(r);
    }
    this.render();
    function bind(r) {
      r._key = function (k) { return self.key(k); };
      r._ok = function () { if (o.ok) o.ok(self.top + r._pos); };
      if (o.long) r._long = function () { o.long(self.top + r._pos); };
      r._focus = function () {
        self.idx = self.top + r._pos;
        if (o.focus) o.focus(self.idx);
      };
      r._enter = function () { self.focus(self.idx); };
    }
  }
  VList.prototype.margin = function () { return this.o.margin == null ? 1 : this.o.margin; };
  VList.prototype.set = function (items, idx, sel) {
    this.items = items || [];
    var n = this.items.length, rows = this.o.rows;
    this.idx = Math.max(0, Math.min(idx || 0, n - 1));
    this.sel = sel == null ? -1 : sel;
    // The row is shown without scrolling when it fits on the first page, else near the middle.
    this.top = this.idx <= rows - 1 - this.margin() ? 0 : Math.max(0, Math.min(this.idx - Math.floor(rows / 2), n - rows));
    var had = F.cur && this.has(F.cur);
    this.render();
    if (had) {
      if (n) F.set(this.pool[this.idx - this.top]);
      else F.clear();
    }
  };
  VList.prototype.has = function (el) { return el && el.parentNode === this.inner; };
  VList.prototype.render = function () {
    for (var p = 0; p < this.pool.length; p++) {
      var i = this.top + p, row = this.pool[p];
      if (i < this.items.length) {
        if (row.style.display) row.style.display = '';
        this.o.render(row, this.items[i], i);
        if (i === this.sel) row.classList.add('sel'); else row.classList.remove('sel');
      } else {
        row.style.display = 'none';
      }
    }
  };
  VList.prototype.setSel = function (i) {
    this.sel = i;
    for (var p = 0; p < this.pool.length; p++) {
      if (this.top + p === i) this.pool[p].classList.add('sel'); else this.pool[p].classList.remove('sel');
    }
  };
  VList.prototype.refresh = function () { this.render(); };
  VList.prototype.key = function (k) {
    var n = this.items.length;
    if (!n) return false;
    var step;
    if (k === 'down') step = 1;
    else if (k === 'up') step = -1;
    else if (k === 'chdown' || k === 'ff') step = this.o.rows;
    else if (k === 'chup' || k === 'rw') step = -this.o.rows;
    else return false;
    var to = this.idx + step;
    if (to < 0) {
      if (step === -1) return this.o.upOut ? false : true;
      to = 0;
    }
    if (to > n - 1) {
      if (step === 1) return true;
      to = n - 1;
    }
    this.focus(to);
    return true;
  };
  VList.prototype.focus = function (i) {
    var n = this.items.length, rows = this.o.rows, m = this.margin();
    if (!n) return;
    i = Math.max(0, Math.min(n - 1, i));
    var top = this.top;
    if (i < top + m) top = i - m;
    if (i > top + rows - 1 - m) top = i - rows + 1 + m;
    top = Math.max(0, Math.min(Math.max(0, n - rows), top));
    this.idx = i;
    if (top !== this.top) {
      this.top = top;
      this.render();
    }
    F.set(this.pool[i - top]);
  };
  UI.VList = VList;

  /** Poster grid: rows of covers, same idea (only what is on screen exists). */
  function VGrid(box, o) {
    var self = this;
    this.o = o;
    this.items = [];
    this.top = 0; // first visible row
    this.idx = 0;
    this.pool = [];
    var inner = U.el('div', 'rows');
    box.appendChild(inner);
    this.inner = inner;
    for (var r = 0; r < o.rows; r++) {
      for (var c = 0; c < o.cols; c++) {
        var t = U.el('div', o.cls + ' f');
        t.style.left = (c * (o.w + o.gap)) + 'px';
        t.style.top = (r * (o.h + o.gap)) + 'px';
        t.style.width = o.w + 'px';
        t.style.height = o.h + 'px';
        t._pos = r * o.cols + c;
        o.make(t);
        bind(t);
        inner.appendChild(t);
        this.pool.push(t);
      }
    }
    this.render();
    function bind(t) {
      t._key = function (k) { return self.key(k); };
      t._ok = function () { if (o.ok) o.ok(self.top * o.cols + t._pos); };
      if (o.long) t._long = function () { o.long(self.top * o.cols + t._pos); };
      t._focus = function () {
        self.idx = self.top * o.cols + t._pos;
        if (o.focus) o.focus(self.idx);
      };
      t._enter = function () { self.focus(self.idx); };
    }
  }
  VGrid.prototype.set = function (items, idx) {
    this.items = items || [];
    var n = this.items.length;
    this.idx = Math.max(0, Math.min(idx || 0, n - 1));
    this.top = Math.max(0, Math.floor(this.idx / this.o.cols) - 1);
    this.clampTop();
    var had = F.cur && F.cur.parentNode === this.inner;
    this.render();
    if (had) {
      if (n) F.set(this.pool[this.idx - this.top * this.o.cols]);
      else F.clear();
    }
  };
  VGrid.prototype.clampTop = function () {
    var totalRows = Math.ceil(this.items.length / this.o.cols);
    this.top = Math.max(0, Math.min(this.top, totalRows - this.o.fullRows));
  };
  VGrid.prototype.render = function () {
    var base = this.top * this.o.cols;
    for (var p = 0; p < this.pool.length; p++) {
      var i = base + p, t = this.pool[p];
      if (i < this.items.length) {
        if (t.style.display) t.style.display = '';
        this.o.render(t, this.items[i], i);
      } else {
        t.style.display = 'none';
      }
    }
  };
  VGrid.prototype.refresh = function () { this.render(); };
  VGrid.prototype.key = function (k) {
    var n = this.items.length, cols = this.o.cols;
    if (!n) return false;
    var to = this.idx, col = this.idx % cols;
    if (k === 'left') { if (col === 0) return false; to--; }
    else if (k === 'right') { if (col === cols - 1 || to + 1 >= n) return true; to++; }
    else if (k === 'up') { if (to - cols < 0) return this.o.upOut ? false : true; to -= cols; }
    else if (k === 'down') {
      if (to + cols >= n) {
        // Last row may be shorter: go to its last item.
        var lastRowStart = Math.floor((n - 1) / cols) * cols;
        if (to >= lastRowStart) return true;
        to = n - 1;
      } else to += cols;
    } else if (k === 'chdown') to = Math.min(n - 1, to + cols * this.o.fullRows);
    else if (k === 'chup') to = Math.max(0, to - cols * this.o.fullRows);
    else return false;
    this.focus(to);
    return true;
  };
  VGrid.prototype.focus = function (i) {
    var n = this.items.length, cols = this.o.cols;
    if (!n) return;
    i = Math.max(0, Math.min(n - 1, i));
    var row = Math.floor(i / cols), top = this.top, full = this.o.fullRows;
    if (row < top) top = row;
    if (row > top + full - 1) top = row - full + 1;
    var old = this.top;
    this.top = top;
    this.clampTop();
    this.idx = i;
    if (this.top !== old) this.render();
    F.set(this.pool[i - this.top * cols]);
  };
  UI.VGrid = VGrid;

  /** Puts a picture into an <img> of a recycled row (fades in when it arrives, empty when missing). */
  UI.setImg = function (img, url) {
    url = url || '';
    if (img._url === url) return;
    img._url = url;
    img.classList.remove('ok');
    if (!url || url.indexOf('http') !== 0) {
      img.removeAttribute('src');
      img.style.visibility = 'hidden';
      return;
    }
    img.style.visibility = '';
    img.onload = function () { if (img._url === url) img.classList.add('ok'); };
    img.onerror = function () { if (img._url === url) img.style.visibility = 'hidden'; };
    img.src = url;
  };
})();
