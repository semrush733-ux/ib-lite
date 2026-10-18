/* The TV guide of an M3U playlist: an XMLTV file (plain or .gz) named on the website or inside the
 * playlist (url-tvg). It is downloaded, unpacked and read in the background (a Web Worker: this
 * same file), so the remote never waits; a TV without workers does the same on the page in small
 * steps. Only the playlist's own channels (tvg-id) and the programmes from 4 hours ago to 36 hours
 * ahead are kept, at most 120 per channel (as in the Android app).
 *
 * Page:   XMLTV.load(url, ids) -> Promise of {guide: {id: [[start, end, title, desc], ...]}, stats}
 * Worker: postMessage({url, ids, now}) -> {ok, guide, stats} or {ok: false, error}           */
(function (G) {
  'use strict';

  var IN_WORKER = typeof window === 'undefined' && typeof importScripts === 'function';
  var MAX_DOWNLOAD = 40 * 1024 * 1024; // what arrives (a .gz guide is far smaller than its text)
  var MAX_TEXT = 120 * 1024 * 1024; // what is read of the unpacked guide
  var PER_CHANNEL = 120;
  var CHUNK = 256 * 1024; // the page does this much per step

  // ================================================================== inflate (RFC 1951)
  // Resumable: run(budget) stops after about budget bytes of output and goes on when called again.
  var LBASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
  var LEXT = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
  var DBASE = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
    4097, 6145, 8193, 12289, 16385, 24577];
  var DEXT = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
  var ORDER = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
  var FAST = 10, FASTMASK = (1 << FAST) - 1;

  /** A Huffman code from code lengths: a quick table for codes up to 10 bits, the rest bit by bit. */
  function Huff(lengths, n) {
    var count = new Uint16Array(16), offs = new Uint16Array(16), next = new Uint16Array(16), i, len;
    for (i = 0; i < n; i++) count[lengths[i]]++;
    count[0] = 0;
    for (len = 1; len < 16; len++) offs[len] = offs[len - 1] + count[len - 1];
    var sym = new Uint16Array(n);
    for (i = 0; i < n; i++) if (lengths[i]) sym[offs[lengths[i]]++] = i;
    var code = 0;
    for (len = 1; len < 16; len++) { code = (code + count[len - 1]) << 1; next[len] = code; }
    var fast = new Uint16Array(1 << FAST);
    for (i = 0; i < n; i++) {
      len = lengths[i];
      if (!len) continue;
      var c = next[len]++;
      if (len > FAST) continue;
      var r = 0;
      for (var b = 0; b < len; b++) { r = (r << 1) | (c & 1); c >>= 1; }
      for (var j = r; j < (1 << FAST); j += 1 << len) fast[j] = (len << 9) | i;
    }
    this.count = count;
    this.sym = sym;
    this.fast = fast;
  }

  var FIXED_L = null, FIXED_D = null;
  function fixed() {
    if (FIXED_L) return;
    var l = new Uint8Array(288), i;
    for (i = 0; i < 144; i++) l[i] = 8;
    for (; i < 256; i++) l[i] = 9;
    for (; i < 280; i++) l[i] = 7;
    for (; i < 288; i++) l[i] = 8;
    FIXED_L = new Huff(l, 288);
    var d = new Uint8Array(30);
    for (i = 0; i < 30; i++) d[i] = 5;
    FIXED_D = new Huff(d, 30);
  }

  /** emit(Uint8Array) gets the output in pieces of up to 64 KB. */
  function Inflater(src, pos, emit) {
    this.s = src;
    this.p = pos;
    this.bb = 0;
    this.bc = 0;
    this.win = new Uint8Array(32768);
    this.wp = 0;
    this.out = new Uint8Array(65536);
    this.op = 0;
    this.emit = emit;
    this.last = false;
    this.mode = 0; // 0 next block, 1 stored, 2 compressed, 3 done
    this.left = 0;
    this.lt = null;
    this.dt = null;
    this.total = 0;
  }
  Inflater.prototype.fill = function () {
    var s = this.s;
    while (this.bc < 24 && this.p < s.length) { this.bb |= s[this.p++] << this.bc; this.bc += 8; }
  };
  Inflater.prototype.bits = function (n) {
    if (this.bc < n) {
      this.fill();
      if (this.bc < n) throw new Error('the guide file ends early');
    }
    var v = this.bb & ((1 << n) - 1);
    this.bb >>>= n;
    this.bc -= n;
    return v;
  };
  Inflater.prototype.decode = function (h) {
    if (this.bc < 15) this.fill();
    var e = h.fast[this.bb & FASTMASK];
    if (e) {
      var l = e >>> 9;
      if (l <= this.bc) { this.bb >>>= l; this.bc -= l; return e & 511; }
    }
    var code = 0, first = 0, index = 0;
    for (var len = 1; len < 16; len++) {
      code |= this.bits(1);
      var count = h.count[len];
      if (code - first < count) return h.sym[index + code - first];
      index += count;
      first += count;
      first <<= 1;
      code <<= 1;
    }
    throw new Error('the guide file is damaged');
  };
  Inflater.prototype.put = function (b) {
    this.win[this.wp] = b;
    this.wp = (this.wp + 1) & 32767;
    this.out[this.op++] = b;
    if (this.op === 65536) this.flush();
  };
  Inflater.prototype.flush = function () {
    if (!this.op) return;
    this.total += this.op;
    this.emit(this.out.subarray(0, this.op));
    this.out = new Uint8Array(65536);
    this.op = 0;
  };
  Inflater.prototype.header = function () {
    this.last = this.bits(1) === 1;
    var type = this.bits(2);
    if (type === 0) {
      var drop = this.bc & 7;
      this.bb >>>= drop;
      this.bc -= drop;
      var len = this.bits(16), nlen = this.bits(16);
      if ((len ^ 0xffff) !== nlen) throw new Error('the guide file is damaged');
      this.left = len;
      this.mode = 1;
    } else if (type === 1) {
      fixed();
      this.lt = FIXED_L;
      this.dt = FIXED_D;
      this.mode = 2;
    } else if (type === 2) {
      var nl = this.bits(5) + 257, nd = this.bits(5) + 1, nc = this.bits(4) + 4, i;
      var cl = new Uint8Array(19);
      for (i = 0; i < nc; i++) cl[ORDER[i]] = this.bits(3);
      var ch = new Huff(cl, 19), lens = new Uint8Array(nl + nd);
      i = 0;
      while (i < nl + nd) {
        var sy = this.decode(ch), rep = 0, val = 0;
        if (sy < 16) { lens[i++] = sy; continue; }
        if (sy === 16) {
          if (!i) throw new Error('the guide file is damaged');
          val = lens[i - 1];
          rep = 3 + this.bits(2);
        } else if (sy === 17) rep = 3 + this.bits(3);
        else rep = 11 + this.bits(7);
        if (i + rep > nl + nd) throw new Error('the guide file is damaged');
        while (rep--) lens[i++] = val;
      }
      this.lt = new Huff(lens.subarray(0, nl), nl);
      this.dt = new Huff(lens.subarray(nl), nd);
      this.mode = 2;
    } else throw new Error('the guide file is damaged');
  };
  /** Unpacks about budget more bytes; true at the end of the stream. */
  Inflater.prototype.run = function (budget) {
    var start = this.total + this.op;
    while (this.total + this.op - start < budget) {
      if (this.mode === 0) {
        if (this.last) { this.mode = 3; this.flush(); return true; }
        this.header();
      } else if (this.mode === 1) {
        while (this.left > 0 && this.total + this.op - start < budget) { this.put(this.bits(8)); this.left--; }
        if (!this.left) this.mode = 0;
      } else if (this.mode === 2) {
        var lt = this.lt, dt = this.dt;
        while (this.total + this.op - start < budget) {
          var sym = this.decode(lt);
          if (sym < 256) { this.put(sym); continue; }
          if (sym === 256) { this.mode = 0; break; }
          sym -= 257;
          if (sym >= 29) throw new Error('the guide file is damaged');
          var len = LBASE[sym] + (LEXT[sym] ? this.bits(LEXT[sym]) : 0);
          var ds = this.decode(dt);
          if (ds >= 30) throw new Error('the guide file is damaged');
          var dist = DBASE[ds] + (DEXT[ds] ? this.bits(DEXT[ds]) : 0);
          var win = this.win, from = (this.wp - dist) & 32767;
          for (var k = 0; k < len; k++) { this.put(win[from]); from = (from + 1) & 32767; }
        }
      } else return true;
    }
    this.flush();
    return this.mode === 3;
  };
  /** Byte position just after the stream (for the gzip trailer). */
  Inflater.prototype.end = function () { return this.p - (this.bc >> 3); };

  /** Where the deflate data starts: after a gzip header (1f 8b) or a zlib header; -1 for plain text. */
  function packedStart(b, at) {
    if (b.length - at > 18 && b[at] === 0x1f && b[at + 1] === 0x8b && b[at + 2] === 8) {
      var flg = b[at + 3], p = at + 10;
      if (flg & 4) p += 2 + (b[p] | (b[p + 1] << 8));
      if (flg & 8) { while (p < b.length && b[p]) p++; p++; }
      if (flg & 16) { while (p < b.length && b[p]) p++; p++; }
      if (flg & 2) p += 2;
      return p;
    }
    if (at === 0 && b.length > 2 && (b[0] & 15) === 8 && ((b[0] << 8) | b[1]) % 31 === 0 && !(b[1] & 32)) return 2;
    return -1;
  }

  // ================================================================== bytes to text (UTF-8, in pieces)
  function Utf8() {
    this.dec = null;
    try { this.dec = new TextDecoder('utf-8'); } catch (e) {}
    this.rest = null;
  }
  Utf8.prototype.text = function (bytes, last) {
    if (this.dec) {
      try { return this.dec.decode(bytes, { stream: !last }); } catch (e) { this.dec = null; }
    }
    // No TextDecoder: by hand (a character cut between two pieces waits for the next one).
    var b = bytes;
    if (this.rest) {
      var j = new Uint8Array(this.rest.length + bytes.length);
      j.set(this.rest);
      j.set(bytes, this.rest.length);
      b = j;
      this.rest = null;
    }
    var out = [], i = 0, n = b.length, s = '';
    while (i < n) {
      var c = b[i], need = c < 0x80 ? 0 : c >= 0xf0 ? 3 : c >= 0xe0 ? 2 : c >= 0xc0 ? 1 : -1;
      if (need < 0) { out.push(0xfffd); i++; continue; }
      if (i + need >= n && need) { if (!last) { this.rest = b.subarray(i); break; } out.push(0xfffd); break; }
      var cp = need === 0 ? c : need === 1 ? c & 31 : need === 2 ? c & 15 : c & 7;
      for (var k = 1; k <= need; k++) cp = (cp << 6) | (b[i + k] & 63);
      i += need + 1;
      if (cp > 0xffff) { cp -= 0x10000; out.push(0xd800 + (cp >> 10), 0xdc00 + (cp & 1023)); } else out.push(cp);
      if (out.length > 8000) { s += String.fromCharCode.apply(null, out); out = []; }
    }
    return s + String.fromCharCode.apply(null, out);
  };

  // ================================================================== XMLTV
  /** "20261010020000 +0500" -> milliseconds (UTC); 0 when it cannot be read. */
  function xmltvTime(s) {
    s = String(s || '').replace(/^\s+/, '');
    if (s.length < 12) return 0;
    var y = +s.substr(0, 4), mo = +s.substr(4, 2), d = +s.substr(6, 2), h = +s.substr(8, 2), mi = +s.substr(10, 2);
    var se = s.length >= 14 ? +s.substr(12, 2) || 0 : 0;
    if (!(y > 1970) || !(mo >= 1) || isNaN(d) || isNaN(h) || isNaN(mi)) return 0;
    var t = Date.UTC(y, mo - 1, d, h, mi, se);
    var off = /([+-])(\d\d):?(\d\d)/.exec(s.substring(14));
    if (off) t -= (off[1] === '-' ? -1 : 1) * (+off[2] * 60 + +off[3]) * 60000;
    return t;
  }
  var ENT = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
  function xmlText(s) {
    return String(s || '')
      .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
      .replace(/<[^>]*>/g, ' ')
      .replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, function (m, e) {
        if (e.charAt(0) === '#') {
          var n = e.charAt(1) === 'x' || e.charAt(1) === 'X' ? parseInt(e.substring(2), 16) : parseInt(e.substring(1), 10);
          return n > 0 && n < 0x10000 ? String.fromCharCode(n) : '';
        }
        var v = ENT[e.toLowerCase()];
        return v == null ? m : v;
      })
      .replace(/\s+/g, ' ')
      .replace(/^ | $/g, '');
  }

  var PROG = /<programme\b([^>]*)>([\s\S]*?)<\/programme>/g, ATTR = /([\w-]+)\s*=\s*"([^"]*)"/g;
  var TITLE = /<title\b[^>]*>([\s\S]*?)<\/title>/, DESC = /<desc\b[^>]*>([\s\S]*?)<\/desc>/;

  /** Reads text piece by piece; a programme cut between two pieces is read with the next one. */
  function Reader(ids, now) {
    var want = {}, i;
    for (i = 0; i < ids.length; i++) {
      var id = String(ids[i] || '');
      if (!id) continue;
      want[id] = id;
      if (!want[id.toLowerCase()]) want[id.toLowerCase()] = id;
    }
    this.want = want;
    this.from = now - 4 * 3600000;
    this.to = now + 36 * 3600000;
    this.carry = '';
    this.guide = {};
    this.seen = 0;
    this.kept = 0;
    this.channels = 0;
  }
  Reader.prototype.add = function (text) {
    var t = this.carry ? this.carry + text : text, m, end = 0;
    PROG.lastIndex = 0;
    while ((m = PROG.exec(t))) {
      end = PROG.lastIndex;
      this.seen++;
      this.programme(m[1], m[2]);
    }
    var rest = t.substring(end), open = rest.lastIndexOf('<programme');
    if (open >= 0) rest = rest.substring(open);
    else rest = rest.substring(Math.max(0, rest.length - 16));
    // A block that never ends (a damaged file) must not grow for ever.
    this.carry = rest.length > 2 * 1024 * 1024 ? '' : rest;
  };
  Reader.prototype.programme = function (attrs, body) {
    var start = '', stop = '', ch = '', a;
    ATTR.lastIndex = 0;
    while ((a = ATTR.exec(attrs))) {
      var k = a[1];
      if (k === 'start') start = a[2];
      else if (k === 'stop') stop = a[2];
      else if (k === 'channel') ch = a[2];
    }
    if (!ch) return;
    if (ch.indexOf('&') >= 0) ch = xmlText(ch);
    var id = this.want[ch] || this.want[ch.toLowerCase()];
    if (!id) return;
    var s = xmltvTime(start);
    if (!s || s > this.to) return;
    var e = xmltvTime(stop) || s + 3600000;
    if (e <= this.from || e <= s) return;
    var list = this.guide[id];
    if (!list) { list = this.guide[id] = []; this.channels++; }
    if (list.length >= PER_CHANNEL) return;
    var tm = TITLE.exec(body), title = tm ? xmlText(tm[1]) : '';
    if (!title) return;
    var dm = DESC.exec(body), desc = dm ? xmlText(dm[1]) : '';
    if (desc.length > 400) desc = desc.substring(0, 399) + '…';
    list.push([s, e, title, desc]);
    this.kept++;
  };
  Reader.prototype.finish = function () {
    var g = this.guide;
    for (var id in g) {
      if (!g.hasOwnProperty(id)) continue;
      var l = g[id].sort(function (a, b) { return a[0] - b[0]; }), clean = [];
      for (var i = 0; i < l.length; i++) if (!clean.length || l[i][0] > clean[clean.length - 1][0]) clean.push(l[i]);
      g[id] = clean;
    }
    return g;
  };

  // ================================================================== a whole guide file
  /** Unpacks (when packed) and reads the downloaded bytes. step(fn) runs fn later (the page) or at
   *  once (the worker); done(error, {guide, stats}). */
  function readGuide(bytes, ids, now, step, done) {
    var reader = new Reader(ids, now), utf = new Utf8(), textBytes = 0, t0 = Date.now();
    var packed = packedStart(bytes, 0) >= 0;
    function finish(err) {
      if (err && !reader.kept) { done(err); return; }
      reader.add(utf.text(new Uint8Array(0), true));
      done(null, {
        guide: reader.finish(),
        stats: { bytes: bytes.length, text: textBytes, packed: packed, programmes: reader.seen, kept: reader.kept, channels: reader.channels, ms: Date.now() - t0 }
      });
    }
    function eat(piece) {
      textBytes += piece.length;
      reader.add(utf.text(piece, false));
    }
    if (!packed) {
      var at = 0;
      (function plain() {
        try {
          var n = Math.min(bytes.length, at + CHUNK * 4, MAX_TEXT);
          if (at < n) eat(bytes.subarray(at, n));
          at = n;
          if (at >= bytes.length || at >= MAX_TEXT) { finish(null); return; }
        } catch (e) { finish(e); return; }
        step(plain);
      })();
      return;
    }
    var pos = packedStart(bytes, 0), inf = new Inflater(bytes, pos, eat);
    (function unpack() {
      try {
        if (inf.run(CHUNK)) {
          // Another gzip member may follow (some guides are several files put together).
          var next = inf.end() + 8, more = next < bytes.length ? packedStart(bytes, next) : -1;
          if (more < 0 || textBytes >= MAX_TEXT) { finish(null); return; }
          inf = new Inflater(bytes, more, eat);
        } else if (textBytes >= MAX_TEXT) { finish(null); return; }
      } catch (e) {
        // A cut or damaged file: what was unpacked before is still read.
        try { inf.flush(); } catch (e2) {}
        finish(e);
        return;
      }
      step(unpack);
    })();
  }

  // ================================================================== download
  /** The first 40 MB at most: read as it arrives where the TV can (fetch with a stream); when that
   *  is missing or refused, in one piece (XMLHttpRequest, which every TV has). */
  function download(url, done) {
    if (typeof fetch !== 'function' || typeof ReadableStream !== 'function') { downloadXhr(url, done); return; }
    var parts = [], got = 0;
    fetch(url, { credentials: 'omit' }).then(function (r) {
      if (!r.ok) { var bad = new Error('the guide address answered ' + r.status); bad.http = true; bad.final = true; throw bad; }
      if (!r.body || !r.body.getReader) return r.arrayBuffer().then(function (ab) { parts.push(new Uint8Array(ab)); got = ab.byteLength; });
      var rd = r.body.getReader();
      return (function pump() {
        return rd.read().then(function (x) {
          if (x.done) return null;
          parts.push(x.value);
          got += x.value.length;
          if (got >= MAX_DOWNLOAD) { try { rd.cancel(); } catch (e) {} return null; }
          return pump();
        });
      })();
    }).then(function () {
      if (!got) { done(fin(new Error('the guide file is empty'))); return; }
      var all = new Uint8Array(got), at = 0;
      for (var i = 0; i < parts.length; i++) { all.set(parts[i], at); at += parts[i].length; }
      parts = null;
      done(null, all);
    }, function (e) {
      if (e && e.http) { done(e); return; }
      parts = null;
      downloadXhr(url, done);
    });
  }
  function downloadXhr(url, done) {
    var x = new XMLHttpRequest();
    var over = false;
    try {
      x.open('GET', url, true);
      x.responseType = 'arraybuffer';
      x.timeout = 180000;
    } catch (e) { done(e); return; }
    x.onprogress = function (e) {
      // Bigger than a TV can hold: stop at once rather than after minutes of downloading.
      if ((e.lengthComputable && e.total > MAX_DOWNLOAD) || e.loaded > MAX_DOWNLOAD) { over = true; try { x.abort(); } catch (a) {} }
    };
    x.onload = function () {
      if (x.status !== 200 && x.status !== 0) { done(fin(new Error('the guide address answered ' + x.status))); return; }
      if (!x.response || !x.response.byteLength) { done(fin(new Error('the guide file is empty'))); return; }
      done(null, new Uint8Array(x.response));
    };
    x.onerror = function () { done(new Error('the guide could not be downloaded')); };
    x.ontimeout = function () { done(new Error('the guide took too long to download')); };
    x.onabort = function () { var a = new Error(over ? 'the guide file is too big for the TV' : 'stopped'); a.final = over; done(a); };
    try { x.send(); } catch (e2) { done(e2); }
  }

  function fin(e) { e.final = true; return e; }
  function job(url, ids, now, step, done) {
    download(url, function (err, bytes) {
      if (err) { done(err); return; }
      // A file that cannot be read is read the same way on the page: no second try there.
      readGuide(bytes, ids, now, step, function (e, r) { if (e) fin(e); done(e, r); });
    });
  }
  /** The worker's step: the next piece at once, in a loop (no growing call stack). */
  function trampoline() {
    var next = null, running = false;
    return function (fn) {
      next = fn;
      if (running) return;
      running = true;
      while (next) { var f = next; next = null; f(); }
      running = false;
    };
  }

  // ================================================================== worker / page
  if (IN_WORKER) {
    G.onmessage = function (e) {
      var d = e.data || {};
      job(d.url, d.ids || [], d.now || Date.now(), trampoline(), function (err, r) {
        // final: the server's answer or the file itself is the problem (the page would get the same).
        if (err) G.postMessage({ ok: false, error: String((err && err.message) || err), final: !!(err && err.final) });
        else G.postMessage({ ok: true, guide: r.guide, stats: r.stats });
      });
    };
    return;
  }

  function onPage(url, ids) {
    return new Promise(function (resolve, reject) {
      job(url, ids, Date.now(), function (fn) { setTimeout(fn, 0); }, function (err, r) { if (err) reject(err); else resolve(r); });
    });
  }
  function inWorker(url, ids) {
    return new Promise(function (resolve, reject) {
      var w;
      try { w = new Worker('js/xmltv.js'); } catch (e) { reject({ noWorker: true }); return; }
      var timer = setTimeout(function () { w.terminate(); reject(new Error('the guide took too long')); }, 300000);
      w.onmessage = function (e) {
        clearTimeout(timer);
        w.terminate();
        var d = e.data || {};
        if (d.ok) resolve({ guide: d.guide, stats: d.stats });
        else if (d.final) reject(new Error(d.error || 'no guide'));
        else reject({ noWorker: true, why: d.error }); // the page may reach what the worker could not
      };
      w.onerror = function (e) {
        clearTimeout(timer);
        w.terminate();
        if (e && e.preventDefault) e.preventDefault();
        reject({ noWorker: true });
      };
      w.postMessage({ url: url, ids: ids, now: Date.now() });
    });
  }

  G.XMLTV = {
    load: function (url, ids) {
      return inWorker(url, ids).then(null, function (e) {
        if (!e || !e.noWorker) throw e;
        if (G.App && App.log) App.log('guide: read on the page' + (e.why ? ' (the background worker: ' + e.why + ')' : ' (no background worker)'));
        return onPage(url, ids);
      });
    },
    // For the tests.
    read: function (bytes, ids, now) {
      return new Promise(function (resolve, reject) {
        readGuide(bytes, ids, now || Date.now(), trampoline(), function (err, r) { if (err) reject(err); else resolve(r); });
      });
    },
    time: xmltvTime,
    text: xmlText
  };
})(this);
