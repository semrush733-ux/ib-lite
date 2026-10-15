/* QR code encoder (byte mode, error correction M), drawn on a canvas.
 * Written for this app after the public QR specification (ISO/IEC 18004); plain ES5. */
var QR = (function () {
  'use strict';

  // Error correction level M (index 1 in the spec tables); format bits for M are 0.
  var ECC_PER_BLOCK = [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26,
    26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28];
  var NUM_BLOCKS = [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16,
    17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49];
  var FORMAT_BITS_M = 0;

  function rawModules(ver) {
    var r = (16 * ver + 128) * ver + 64;
    if (ver >= 2) {
      var n = Math.floor(ver / 7) + 2;
      r -= (25 * n - 10) * n - 55;
      if (ver >= 7) r -= 36;
    }
    return r;
  }

  function dataCodewords(ver) {
    return Math.floor(rawModules(ver) / 8) - ECC_PER_BLOCK[ver] * NUM_BLOCKS[ver];
  }

  // ---- Reed-Solomon over GF(256), polynomial 0x11D
  function mul(x, y) {
    var z = 0;
    for (var i = 7; i >= 0; i--) {
      z = (z << 1) ^ ((z >>> 7) * 0x11D);
      z ^= ((y >>> i) & 1) * x;
    }
    return z & 0xFF;
  }

  function divisor(degree) {
    var r = [];
    for (var i = 0; i < degree - 1; i++) r.push(0);
    r.push(1);
    var root = 1;
    for (i = 0; i < degree; i++) {
      for (var j = 0; j < r.length; j++) {
        r[j] = mul(r[j], root);
        if (j + 1 < r.length) r[j] ^= r[j + 1];
      }
      root = mul(root, 0x02);
    }
    return r;
  }

  function remainder(data, div) {
    var r = [];
    for (var i = 0; i < div.length; i++) r.push(0);
    for (var k = 0; k < data.length; k++) {
      var f = data[k] ^ r.shift();
      r.push(0);
      for (i = 0; i < div.length; i++) r[i] ^= mul(div[i], f);
    }
    return r;
  }

  function utf8(s) {
    var out = [];
    for (var i = 0; i < s.length; i++) {
      var c = s.charCodeAt(i);
      if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
        var d = s.charCodeAt(i + 1);
        if (d >= 0xDC00 && d <= 0xDFFF) {
          c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
          i++;
        }
      }
      if (c < 0x80) out.push(c);
      else if (c < 0x800) out.push(0xC0 | (c >> 6), 0x80 | (c & 63));
      else if (c < 0x10000) out.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
      else out.push(0xF0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    }
    return out;
  }

  function bit(x, i) { return ((x >>> i) & 1) !== 0; }

  /** Returns the QR matrix (array of rows of booleans) for text. */
  function encode(text) {
    var bytes = utf8(String(text));
    var ver, ccBits;
    for (ver = 1; ver <= 40; ver++) {
      ccBits = ver <= 9 ? 8 : 16;
      if (4 + ccBits + bytes.length * 8 <= dataCodewords(ver) * 8) break;
    }
    if (ver > 40) throw new Error('QR: text too long');

    // Bit stream: mode (byte), length, data, terminator, padding.
    var bits = [];
    function put(val, len) { for (var i = len - 1; i >= 0; i--) bits.push((val >>> i) & 1); }
    put(4, 4);
    put(bytes.length, ccBits);
    for (var i = 0; i < bytes.length; i++) put(bytes[i], 8);
    var capacity = dataCodewords(ver) * 8;
    put(0, Math.min(4, capacity - bits.length));
    put(0, (8 - bits.length % 8) % 8);
    for (var pad = 0xEC; bits.length < capacity; pad ^= 0xEC ^ 0x11) put(pad, 8);
    var data = [];
    for (i = 0; i < bits.length; i += 8) {
      var b = 0;
      for (var j = 0; j < 8; j++) b = (b << 1) | bits[i + j];
      data.push(b);
    }

    // Error correction blocks, interleaved.
    var numBlocks = NUM_BLOCKS[ver], eccLen = ECC_PER_BLOCK[ver];
    var raw = Math.floor(rawModules(ver) / 8);
    var numShort = numBlocks - raw % numBlocks;
    var shortLen = Math.floor(raw / numBlocks);
    var div = divisor(eccLen);
    var blocks = [];
    for (i = 0, j = 0; i < numBlocks; i++) {
      var dat = data.slice(j, j + shortLen - eccLen + (i < numShort ? 0 : 1));
      j += dat.length;
      var ecc = remainder(dat, div);
      if (i < numShort) dat.push(0);
      blocks.push(dat.concat(ecc));
    }
    var all = [];
    for (i = 0; i < blocks[0].length; i++) {
      for (j = 0; j < blocks.length; j++) {
        if (i !== shortLen - eccLen || j >= numShort) all.push(blocks[j][i]);
      }
    }

    // Matrix with the fixed patterns.
    var size = ver * 4 + 17;
    var m = [], fn = [];
    for (i = 0; i < size; i++) {
      m.push([]);
      fn.push([]);
      for (j = 0; j < size; j++) { m[i].push(false); fn[i].push(false); }
    }
    function set(x, y, dark) { m[y][x] = dark; fn[y][x] = true; }

    for (i = 0; i < size; i++) { set(6, i, i % 2 === 0); set(i, 6, i % 2 === 0); }
    function finder(x, y) {
      for (var dy = -4; dy <= 4; dy++) {
        for (var dx = -4; dx <= 4; dx++) {
          var d = Math.max(Math.abs(dx), Math.abs(dy)), xx = x + dx, yy = y + dy;
          if (xx >= 0 && xx < size && yy >= 0 && yy < size) set(xx, yy, d !== 2 && d !== 4);
        }
      }
    }
    finder(3, 3);
    finder(size - 4, 3);
    finder(3, size - 4);
    if (ver > 1) {
      var n = Math.floor(ver / 7) + 2;
      var step = Math.floor((ver * 8 + n * 3 + 5) / (n * 4 - 4)) * 2;
      var pos = [6];
      for (var p = size - 7; pos.length < n; p -= step) pos.splice(1, 0, p);
      for (i = 0; i < n; i++) {
        for (j = 0; j < n; j++) {
          if ((i === 0 && j === 0) || (i === 0 && j === n - 1) || (i === n - 1 && j === 0)) continue;
          for (var ay = -2; ay <= 2; ay++) {
            for (var ax = -2; ax <= 2; ax++) set(pos[i] + ax, pos[j] + ay, Math.max(Math.abs(ax), Math.abs(ay)) !== 1);
          }
        }
      }
    }
    function format(mask) {
      var d = (FORMAT_BITS_M << 3) | mask, r = d;
      for (var k = 0; k < 10; k++) r = (r << 1) ^ ((r >>> 9) * 0x537);
      var f = ((d << 10) | r) ^ 0x5412;
      for (k = 0; k <= 5; k++) set(8, k, bit(f, k));
      set(8, 7, bit(f, 6));
      set(8, 8, bit(f, 7));
      set(7, 8, bit(f, 8));
      for (k = 9; k < 15; k++) set(14 - k, 8, bit(f, k));
      for (k = 0; k < 8; k++) set(size - 1 - k, 8, bit(f, k));
      for (k = 8; k < 15; k++) set(8, size - 15 + k, bit(f, k));
      set(8, size - 8, true);
    }
    format(0);
    if (ver >= 7) {
      var r = ver;
      for (i = 0; i < 12; i++) r = (r << 1) ^ ((r >>> 11) * 0x1F25);
      var vb = (ver << 12) | r;
      for (i = 0; i < 18; i++) {
        var a = size - 11 + i % 3, c = Math.floor(i / 3);
        set(a, c, bit(vb, i));
        set(c, a, bit(vb, i));
      }
    }

    // Data, in the zig-zag order.
    var k = 0;
    for (var right = size - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (var vert = 0; vert < size; vert++) {
        for (j = 0; j < 2; j++) {
          var x = right - j;
          var up = ((right + 1) & 2) === 0;
          var y = up ? size - 1 - vert : vert;
          if (!fn[y][x] && k < all.length * 8) {
            m[y][x] = bit(all[k >>> 3], 7 - (k & 7));
            k++;
          }
        }
      }
    }

    function masked(mask) {
      var out = [];
      for (var y = 0; y < size; y++) {
        var row = [];
        for (var x = 0; x < size; x++) {
          var inv = false;
          if (!fn[y][x]) {
            switch (mask) {
              case 0: inv = (x + y) % 2 === 0; break;
              case 1: inv = y % 2 === 0; break;
              case 2: inv = x % 3 === 0; break;
              case 3: inv = (x + y) % 3 === 0; break;
              case 4: inv = (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0; break;
              case 5: inv = (x * y) % 2 + (x * y) % 3 === 0; break;
              case 6: inv = ((x * y) % 2 + (x * y) % 3) % 2 === 0; break;
              default: inv = ((x + y) % 2 + (x * y) % 3) % 2 === 0;
            }
          }
          row.push(m[y][x] !== inv);
        }
        out.push(row);
      }
      return out;
    }

    function penalty(g) {
      var score = 0, x, y, run, dark = 0;
      for (y = 0; y < size; y++) {
        run = 1;
        for (x = 1; x <= size; x++) {
          if (x < size && g[y][x] === g[y][x - 1]) run++;
          else { if (run >= 5) score += run - 2; run = 1; }
        }
      }
      for (x = 0; x < size; x++) {
        run = 1;
        for (y = 1; y <= size; y++) {
          if (y < size && g[y][x] === g[y - 1][x]) run++;
          else { if (run >= 5) score += run - 2; run = 1; }
        }
      }
      for (y = 0; y < size - 1; y++) {
        for (x = 0; x < size - 1; x++) {
          var v = g[y][x];
          if (v === g[y][x + 1] && v === g[y + 1][x] && v === g[y + 1][x + 1]) score += 3;
        }
      }
      // Finder-like runs 1:1:3:1:1 with light space on one side.
      var pat1 = [true, false, true, true, true, false, true, false, false, false, false];
      var pat2 = [false, false, false, false, true, false, true, true, true, false, true];
      function match(get, len) {
        var s = 0;
        for (var i = 0; i + 11 <= len; i++) {
          var a = true, b = true;
          for (var t = 0; t < 11; t++) {
            var val = get(i + t);
            if (val !== pat1[t]) a = false;
            if (val !== pat2[t]) b = false;
            if (!a && !b) break;
          }
          if (a) s += 40;
          if (b) s += 40;
        }
        return s;
      }
      for (y = 0; y < size; y++) score += match(function (i) { return g[y][i]; }, size);
      for (x = 0; x < size; x++) score += match(function (i) { return g[i][x]; }, size);
      for (y = 0; y < size; y++) for (x = 0; x < size; x++) if (g[y][x]) dark++;
      var total = size * size;
      score += Math.floor(Math.abs(dark * 20 - total * 10) / total) * 10;
      return score;
    }

    var best = null, bestScore = 0;
    for (var mask = 0; mask < 8; mask++) {
      format(mask);
      var g = masked(mask);
      var s = penalty(g);
      if (best === null || s < bestScore) { best = g; bestScore = s; }
    }
    return best;
  }

  /** Draws text as a QR code on a new canvas of about px pixels (sharp: whole pixels per module). */
  function canvas(text, px, dark, light) {
    var g = encode(text);
    var n = g.length, quiet = 2;
    var cell = Math.max(2, Math.floor(px / (n + quiet * 2)));
    var side = cell * (n + quiet * 2);
    var c = document.createElement('canvas');
    c.width = side;
    c.height = side;
    var ctx = c.getContext('2d');
    ctx.fillStyle = light || '#FFFFFF';
    ctx.fillRect(0, 0, side, side);
    ctx.fillStyle = dark || '#000000';
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (g[y][x]) ctx.fillRect((x + quiet) * cell, (y + quiet) * cell, cell, cell);
      }
    }
    return c;
  }

  return { encode: encode, canvas: canvas };
})();

if (typeof module !== 'undefined') module.exports = QR;
