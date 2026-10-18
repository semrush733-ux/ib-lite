/* Profiles (as in the Android app): who watches on this TV. Every profile has its own favourites,
 * recently watched, resume points, Continue Watching and last channel. A Kids profile shows only the
 * categories for children; with a parental PIN, leaving it (and Settings there) needs the PIN.
 * Also: "Who's watching?" (at the start and from the home screen), the profile window (name, colour,
 * Kids), the parental PIN and the Kids categories screen. */
var Profiles = {};

(function () {
  'use strict';

  Profiles.MAX = 6;
  Profiles.COLORS = ['#E3262F', '#1E88FF', '#22C55E', '#F59E0B', '#D946EF', '#14B8A6', '#8B5CF6', '#F97316'];
  var MAIN = { id: 'main', n: 'Main', c: 0, k: 0 };

  function clean(p) { return { id: String(p.id), n: U.str(p.n) || 'Profile', c: Math.abs(U.int(p.c)) % Profiles.COLORS.length, k: p.k ? 1 : 0 }; }
  /** The profiles, the main one always first. */
  Profiles.all = function () {
    var list = [], seen = {};
    (Store.profileList() || []).forEach(function (p) {
      if (p && p.id && !seen[p.id]) { seen[p.id] = 1; list.push(clean(p)); }
    });
    var main = list.filter(function (p) { return p.id === 'main'; })[0] || MAIN;
    return [main].concat(list.filter(function (p) { return p.id !== 'main'; }));
  };
  Profiles.active = function () {
    var id = Store.profileId(), l = Profiles.all();
    return l.filter(function (p) { return p.id === id; })[0] || l[0];
  };
  Profiles.several = function () { return Profiles.all().length > 1; };
  /** "Who's watching?" when the app starts. */
  Profiles.askNow = function () { return Profiles.several() && Store.askProfile(); };
  function save(list) {
    Store.saveProfiles(list.map(function (p) { var o = { id: p.id, n: p.n, c: p.c }; if (p.k) o.k = 1; return o; }));
  }
  Profiles.use = function (p) {
    Store.useProfile(p.id, !!p.k);
    App.log('profile ' + p.id + (p.k ? ' (kids)' : ''));
  };
  Profiles.add = function (name, color, kids) {
    var p = { id: 'p' + Date.now().toString(36), n: name, c: color, k: kids ? 1 : 0 };
    save(Profiles.all().concat([p]));
    return p;
  };
  Profiles.update = function (p) {
    save(Profiles.all().map(function (x) { return x.id === p.id ? p : x; }));
    // The profile in use changed to or from Kids: the rule applies at once.
    if (p.id === Store.profileId()) Store.useProfile(p.id, !!p.k);
  };
  Profiles.remove = function (p) {
    if (p.id === 'main') return;
    save(Profiles.all().filter(function (x) { return x.id !== p.id; }));
    Store.forgetProfile(p.id);
    if (Store.profileId() === p.id) Profiles.use(Profiles.all()[0]);
  };
  Profiles.color = function (p) { return Profiles.COLORS[Math.abs(U.int(p.c)) % Profiles.COLORS.length]; };

  // A smiling child's face for Kids profiles (drawn, so it needs no icon font).
  var KID = '<svg viewBox="0 0 100 100" style="width:62%;height:62%;vertical-align:middle"><g fill="none" stroke="#fff" stroke-width="8" stroke-linecap="round">' +
    '<path d="M28 60 Q50 82 72 60"/><path d="M42 16 Q52 4 62 14"/></g><circle cx="34" cy="42" r="7" fill="#fff"/><circle cx="66" cy="42" r="7" fill="#fff"/></svg>';
  /** The round picture: the profile's colour with its first letter (a child's face for Kids). */
  Profiles.avatar = function (p, size) {
    var c = Profiles.color(p);
    return '<span class="avatar" style="width:' + size + 'px;height:' + size + 'px;line-height:' + size + 'px;font-size:' + Math.round(size * 0.46) + 'px;' +
      'background-color:' + c + '">' + (p.k ? KID : U.esc((U.str(p.n) || '?').charAt(0).toUpperCase())) + '</span>';
  };

  // ================================================================== parental PIN
  function pinField(placeholder, submit) {
    var field = UI.field({ icon: 'pin', placeholder: placeholder, submit: submit });
    field.input.type = 'password';
    field.input.setAttribute('inputmode', 'numeric');
    field.input.maxLength = 8;
    // The remote's number keys type straight in (no keyboard needed).
    field._key = function (k) {
      if (/^d\d$/.test(k)) { field.input.value = (field.input.value + k.charAt(1)).substring(0, 8); if (field._typed) field._typed(); return true; }
      return false;
    };
    return field;
  }
  /** Asks for the parental PIN, then ok(). Straight to ok() when no PIN is set or it was typed already. */
  App.askPin = function (title, ok) {
    var pin = Store.pin();
    if (!pin || Store.parentalUnlocked) { ok(); return; }
    var wrap = U.el('div'), err = U.el('div', 'pinerr', '');
    var field = pinField('Parental PIN', function (v) { check(v); });
    field._typed = function () { if (field.input.value.length >= pin.length) check(field.input.value); };
    wrap.appendChild(field);
    wrap.appendChild(err);
    var d = UI.dialog({
      title: title || 'Parental PIN', html: wrap, width: 900,
      buttons: [{ label: 'Cancel' }, { label: 'OK', pri: true, keep: true, ok: function () { check(field.value()); } }],
      focusEl: field
    });
    function check(v) {
      if (U.str(v) === pin) {
        Store.parentalUnlocked = true;
        d.close();
        ok();
        return;
      }
      err.textContent = 'Wrong PIN, please try again.';
      field.input.value = '';
      F.set(field);
    }
  };
  /** A new 4 to 8 digit PIN, typed twice. done(pin), or nothing when cancelled. */
  App.newPin = function (done) {
    function step(title, first) {
      var wrap = U.el('div'), err = U.el('div', 'pinerr', '');
      var field = pinField('4 to 8 digits', function (v) { next(v); });
      wrap.appendChild(field);
      wrap.appendChild(err);
      var d = UI.dialog({
        title: title, html: wrap, width: 900,
        buttons: [{ label: 'Cancel' }, { label: first == null ? 'Next' : 'Save', pri: true, keep: true, ok: function () { next(field.value()); } }],
        focusEl: field
      });
      setTimeout(function () { if (F.cur === field) field._ok(); }, 60);
      function next(v) {
        v = U.str(v);
        if (!/^\d{4,8}$/.test(v)) { err.textContent = 'The PIN has 4 to 8 digits.'; field.input.value = ''; return; }
        if (first != null && v !== first) { err.textContent = 'The two PINs are not the same. Please type it again.'; field.input.value = ''; return; }
        d.close();
        if (first == null) step('Type the PIN again', v); else done(v);
      }
    }
    step('Set a parental PIN', null);
  };
  /** Settings / Profiles: set, change or remove the PIN. then() after a change. */
  App.pinMenu = function (then) {
    if (!Store.pin()) {
      App.newPin(function (p) { Store.setPin(p); UI.toast('Parental PIN saved', 2500); if (then) then(); });
      return;
    }
    App.askPin('Parental PIN', function () {
      UI.dialog({
        title: 'Parental PIN', width: 1000,
        html: '<div class="dim">With the PIN, children cannot leave the Kids profile or open Settings there without you.</div>',
        buttons: [
          { label: 'Remove the PIN', icon: 'del', ok: function () { Store.setPin(''); UI.toast('Parental PIN removed', 2500); if (then) then(); } },
          { label: 'Change the PIN', icon: 'pin', pri: true, ok: function () {
            App.newPin(function (p) { Store.setPin(p); Store.parentalUnlocked = true; UI.toast('Parental PIN saved', 2500); if (then) then(); });
          } }
        ],
        focus: 1
      });
    });
  };
  /** Leaving a Kids profile (or changing things while in one) needs the parental PIN. */
  function parentOk(ok) {
    if (!Profiles.active().k) { ok(); return; }
    App.askPin('Parental PIN', ok);
  }

  // ================================================================== the profile window
  /** Name, colour and Kids for a new or existing profile. done({n, c, k} or {del: true}). */
  function editDialog(p, isNew, done) {
    var color = p.c, kids = !!p.k;
    var wrap = U.el('div', 'pfedit');
    var field = UI.field({ icon: 'person', placeholder: 'Name', value: p.n || '', submit: function () { F.set(dots.firstChild); } });
    field.input.maxLength = 20;
    wrap.appendChild(field);
    wrap.appendChild(U.el('div', 'pfh', 'COLOUR'));
    var dots = U.el('div', 'pfdots');
    Profiles.COLORS.forEach(function (c, i) {
      var b = U.el('span', 'pfdot f' + (i === color ? ' sel' : ''));
      b.style.backgroundColor = c;
      b._ok = function () {
        color = i;
        for (var k = 0; k < dots.childNodes.length; k++) dots.childNodes[k].classList.toggle('sel', k === i);
      };
      dots.appendChild(b);
    });
    wrap.appendChild(dots);
    var kidRow = U.el('div', 'opt f pfkids');
    function drawKids() {
      kidRow.innerHTML = U.icon(kids ? 'boxOn' : 'boxOff') + '<b>' + U.esc(App.t('Kids profile')) + '</b><span class="dim">  Only categories for children (Kids, Cartoons, Family…)</span>';
      kidRow.classList.toggle('sel', kids);
    }
    drawKids();
    kidRow._ok = function () { kids = !kids; drawKids(); };
    wrap.appendChild(kidRow);
    var buttons = [];
    if (!isNew && p.id !== 'main') buttons.push({ label: 'Delete', icon: 'del', ok: function () { done({ del: true }); } });
    buttons.push({ label: 'Cancel' });
    buttons.push({ label: isNew ? 'Add' : 'Save', pri: true, keep: true, ok: function () {
      var n = U.str(field.value());
      if (!n) { F.set(field); field._ok(); UI.toast('Please type a name', 2000); return; }
      d.close();
      done({ n: n, c: color, k: kids ? 1 : 0 });
    } });
    var d = UI.dialog({ title: isNew ? App.t('Add profile') : App.t('Change profile', 'Edit profile'), html: wrap, width: 1180, buttons: buttons, focusEl: field });
    if (isNew) setTimeout(function () { if (F.cur === field) field._ok(); }, 60);
  }

  /** After a Kids profile is made: a PIN keeps the children in it. */
  function offerPin(then) {
    if (Store.pin()) { then(); return; }
    UI.dialog({
      title: 'Set a parental PIN?', width: 1000,
      html: '<div>With a PIN, children cannot leave the Kids profile or open Settings without you.</div>',
      buttons: [{ label: 'Later', ok: then }, { label: 'Set PIN', icon: 'pin', pri: true, ok: function () {
        App.newPin(function (p) { Store.setPin(p); UI.toast('Parental PIN saved', 2500); then(); });
      } }],
      focus: 1, onClose: null
    });
  }

  // ================================================================== "Who's watching?"
  /** o: {src, atStart}: at the start, a choice opens the home screen; otherwise Back returns. */
  Screens.Profiles = function (o) {
    o = o || {};
    var self = this;
    this.name = 'profiles';
    var el = this.el = U.el('div', 'screen');
    el.innerHTML = '<div class="pf-bg"></div><div class="pf-top">' + UI.logo(52) + '</div>' +
      '<h1 class="pf-h">' + U.esc(App.t("Who's watching?")) + '</h1><div class="pf-row"></div><div class="pf-chips"></div>' +
      '<div class="pf-hint">Every profile has its own favourites, recently watched and Continue Watching. Hold OK on a profile to change or delete it.</div>';
    var row = el.querySelector('.pf-row'), chips = el.querySelector('.pf-chips');

    function home(changed) {
      if (o.atStart) { Nav.reset(new Screens.Home(o.src || App.src, null, true)); return; }
      if (changed) { Nav.reset(new Screens.Home(App.src, App.account)); return; }
      Nav.pop();
    }
    function pick(p) {
      var cur = Profiles.active();
      function go() { Profiles.use(p); home(p.id !== cur.id); }
      if (p.id !== cur.id && cur.k && !p.k) App.askPin('Parental PIN', go); else go();
    }
    function add() {
      parentOk(function () {
        if (Profiles.all().length >= Profiles.MAX) { UI.message('Profiles', 'A TV can have up to ' + Profiles.MAX + ' profiles.'); return; }
        editDialog({ n: '', c: Profiles.all().length % Profiles.COLORS.length, k: 0 }, true, function (r) {
          var p = Profiles.add(r.n, r.c, r.k);
          App.log('profile added' + (p.k ? ' (kids)' : ''));
          draw(p.id);
          if (p.k) offerPin(function () { draw(p.id); });
        });
      });
    }
    function edit(p) {
      parentOk(function () {
        editDialog(p, false, function (r) {
          if (r.del) {
            UI.confirm('Delete "' + p.n + '"?', 'Its favourites, recently watched and Continue Watching are deleted too.', 'Delete', 'Cancel', function () {
              Profiles.remove(p);
              App.log('profile deleted');
              UI.toast('"' + p.n + '" was deleted', 2500);
              draw();
            });
            return;
          }
          var was = !!p.k;
          var q = { id: p.id, n: r.n, c: r.c, k: r.k };
          Profiles.update(q);
          draw(p.id);
          if (q.k && !was) offerPin(function () { draw(p.id); });
        });
      });
    }
    function chip(icon, label, ok) {
      var c = U.el('span', 'btn f pfchip', U.icon(icon) + U.esc(label));
      c._ok = ok;
      chips.appendChild(c);
      return c;
    }
    function draw(focusId) {
      var list = Profiles.all(), cur = Profiles.active();
      var keep = focusId || (F.cur && row.contains(F.cur) ? F.cur._pid : cur.id);
      row.innerHTML = '';
      var focus = null;
      list.forEach(function (p) {
        var t = U.el('div', 'pft f' + (p.id === cur.id ? ' cur' : ''), Profiles.avatar(p, 200) + '<div class="pfn"></div><div class="pfs"></div>');
        t.querySelector('.pfn').textContent = p.n;
        t.querySelector('.pfs').textContent = p.k ? App.t('Kids') : (p.id === cur.id ? App.t('In use') : '');
        if (p.k) t.querySelector('.pfs').className = 'pfs kid';
        t._pid = p.id;
        t._ok = function () { pick(p); };
        t._long = function () { edit(p); };
        row.appendChild(t);
        if (p.id === keep) focus = t;
      });
      if (list.length < Profiles.MAX) {
        var a = U.el('div', 'pft f add', '<span class="avatar plus" style="width:200px;height:200px;line-height:196px">+</span><div class="pfn">Add profile</div><div class="pfs"></div>');
        a._pid = '+';
        a._ok = add;
        row.appendChild(a);
        if (keep === '+') focus = a;
      }
      chips.innerHTML = '';
      if (list.length > 1) {
        var ask = chip(Store.askProfile() ? 'boxOn' : 'boxOff', App.t('Ask when the app starts'), function () {
          parentOk(function () {
            Store.setAskProfile(!Store.askProfile());
            ask.innerHTML = U.icon(Store.askProfile() ? 'boxOn' : 'boxOff') + U.esc(App.t('Ask when the app starts'));
          });
        });
      }
      chip('kids', App.t('Kids categories'), function () { parentOk(function () { Nav.push(new Screens.KidsCats(o.src || App.src)); }); });
      chip('pin', Store.pin() ? 'Parental PIN: On' : 'Parental PIN: Off', function () { parentOk(function () { App.pinMenu(function () { draw(); }); }); });
      if (!o.atStart) chip('back', App.t('Back'), function () { home(false); });
      if (F.cur && !el.contains(F.cur) && UI.topDialog()) return;
      F.set(focus || row.firstChild);
    }
    this.onBack = function () { home(false); return true; };
    this.show = function (first) { if (first) draw(); else draw(F.cur && row.contains(F.cur) ? F.cur._pid : null); };
  };

  // ================================================================== choosing categories
  /** Category choices per kind (Live TV, Movies, Series), as in the Android app:
   *  'kids' = the categories children may see in a Kids profile (ticked by their names, changeable),
   *  'hide' = Settings → Manage categories (untick to hide everywhere),
   *  'lock' = Settings → Parental control (locked ones ask for the PIN before they open). */
  var CHOICE = {
    kids: {
      title: App.t('Kids categories'), icons: ['boxOn', 'boxOff'],
      note: 'A Kids profile shows only the ticked categories. Categories with Kids, Cartoons, Family, Disney… in their name are ticked by themselves; OK ticks or unticks any category by hand.',
      on: function (k, id) { return Store.kidsAllowed(k, id); },
      how: function (k, id, on) { return Store.kidsChoice(k, id) !== null ? 'chosen' : on ? 'by its name' : ''; },
      flip: function (k, id, on, done) { Store.setKidsChoice(k, id, !on); done(); },
      count: function (n, all) { return n + ' of ' + all + ' for children'; },
      extra: [{ name: 'By name only', icon: 'undo', run: function (k, done) {
        Store.resetKidsChoices(k); UI.toast('Back to the categories found by their names', 2200); done();
      } }]
    },
    hide: {
      title: 'Manage categories', icons: ['boxOn', 'boxOff'],
      note: 'Untick a category to hide it everywhere in the app; tick it again to bring it back. To move a category, hold OK on it in Live TV, Movies or Series.',
      on: function (k, id) { return !Store.isHiddenSetting(k, id); },
      how: function (k, id, on) { return on ? '' : 'hidden'; },
      flip: function (k, id, on, done) { Store.setHidden(k, id, on); done(); },
      count: function (n, all) { return n + ' of ' + all + ' shown'; },
      extra: [{ name: 'Original order', icon: 'undo', run: function (k, done) {
        Store.setCatOrder(k, []); UI.toast('Categories back in the playlist\'s own order', 2200); done();
      } }]
    },
    lock: {
      title: 'Parental control', icons: ['lock', 'unlock'],
      note: 'Locked categories ask for the parental PIN before they open, and their channels and titles are left out of All and Search until the PIN is typed.',
      on: function (k, id) { return Store.isLockMarked(k, id); },
      how: function (k, id, on) { return on ? (Store.pin() ? 'locked' : 'locked (no PIN set)') : ''; },
      flip: function (k, id, on, done) {
        function go() { Store.setLocked(k, id, !on); done(); }
        if (!Store.pin()) {
          UI.toast('Set a parental PIN first', 2200);
          App.newPin(function (pin) { Store.setPin(pin); Store.parentalUnlocked = true; go(); });
        } else App.askPin('Parental PIN', go);
      },
      count: function (n) { return (Store.pin() ? 'Parental control is ON' : 'No PIN set') + '  ·  ' + n + ' locked'; },
      extra: [{ name: 'Parental PIN', icon: 'pin', run: function (k, done) { App.pinMenu(done); } }]
    }
  };

  Screens.CatChoice = function (src, mode) {
    var self = this, M = CHOICE[mode] || CHOICE.kids;
    this.name = mode + '-categories';
    var el = this.el = U.el('div', 'screen');
    el.style.background = '#0E0A0B';
    el.innerHTML =
      '<div class="br-cats wide"><div class="br-head">' + UI.symbol(58) + '<span class="t">' + U.esc(M.title) + '</span></div>' +
      '<div class="vl cats"></div><div class="kc-note">' + U.esc(M.note) + '</div></div>' +
      '<div class="br-main wide"><div class="br-title"><span class="t"></span><span class="c"></span></div><div class="content"></div></div>';
    var content = el.querySelector('.content');
    var titleT = el.querySelector('.br-title .t'), titleC = el.querySelector('.br-title .c');
    var kinds = [{ id: 'live', name: App.t('Live TV'), icon: 'live' }, { id: 'vod', name: App.t('Movies'), icon: 'movie' }, { id: 'series', name: App.t('Series'), icon: 'series' }];
    var items = kinds.concat(M.extra);
    var kind = '', cats = [], list = null, req = 0;
    var catBox = el.querySelector('.cats');
    catBox.style.height = (items.length * 84) + 'px';
    var tabs = new UI.VList(catBox, {
      rowH: 84, rows: items.length, cls: 'crow', margin: 0,
      make: function (r) { r.innerHTML = ''; },
      render: function (r, t) { r.innerHTML = U.icon(t.icon) + U.esc(t.name); },
      ok: function (i) {
        if (kinds[i]) { load(kinds[i].id); if (list && cats.length) list.focus(0); return; }
        if (items[i] && kind) items[i].run(kind, redraw);
      },
      focus: function (i) { if (kinds[i]) load(kinds[i].id); }
    });
    function redraw() { if (list) list.refresh(); count(); }
    function count() {
      var n = 0;
      cats.forEach(function (c) { if (M.on(kind, c.id)) n++; });
      titleC.textContent = cats.length ? M.count(n, cats.length) : '';
    }
    function load(k) {
      if (k === kind) return;
      kind = k;
      var r = ++req;
      tabs.setSel(kinds.map(function (x) { return x.id; }).indexOf(k));
      titleT.textContent = kinds.filter(function (x) { return x.id === k; })[0].name;
      titleC.textContent = '';
      content.innerHTML = '';
      content.appendChild(UI.pulse('loading'));
      src.categories(k).then(function (l) {
        if (r !== req) return;
        Store.noteCategories(k, l);
        cats = Store.sortCats(k, l);
        content.innerHTML = '';
        if (!cats.length) { content.appendChild(U.el('div', 'empty', 'No categories.')); return; }
        var box = U.el('div', 'vl');
        box.style.cssText = 'position:absolute;left:0;top:0;width:1300px;height:' + (10 * 92) + 'px';
        content.appendChild(box);
        list = new UI.VList(box, {
          rowH: 92, rows: 10, cls: 'kcrow', margin: 2,
          make: function (row) { row.innerHTML = '<span class="ck"></span><span class="nm"></span><span class="how"></span>'; },
          render: function (row, c) {
            var on = M.on(k, c.id);
            row.childNodes[0].innerHTML = U.icon(on ? M.icons[0] : M.icons[1]);
            row.childNodes[0].className = 'ck' + (on ? ' on' : '');
            row.childNodes[1].textContent = c.name;
            row.childNodes[2].textContent = M.how(k, c.id, on);
          },
          ok: function (i) {
            var c = cats[i];
            if (c) M.flip(k, c.id, M.on(k, c.id), redraw);
          }
        });
        list.set(cats, 0);
        count();
      }, function (e) {
        if (r !== req) return;
        content.innerHTML = '';
        content.appendChild(U.el('div', 'empty', U.esc(Src.friendly(e))));
      });
    }
    this.show = function (first) {
      if (!first) { redraw(); return; }
      tabs.set(items, 0);
      tabs.focus(0);
      load('live');
    };
  };
  /** The Kids categories (Profiles). */
  Screens.KidsCats = function (src) { return new Screens.CatChoice(src, 'kids'); };
})();
