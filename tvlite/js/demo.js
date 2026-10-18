/* Demo content built into the app: try the player (and film it) before any playlist is added.
 * Everything here may be shown freely: the Blender Foundation open movies (Creative Commons
 * Attribution) and public test streams that video companies provide for testing players.
 * Each title has more than one address: when one does not play, the next one is tried.
 * Only titles really in 3840x2160 are called 4K; the player bar shows the picture size it gets. */
(function () {
  'use strict';

  var MIT = 'https://mirrors.mit.edu/kodi/demo-files/BBB/';
  var GTV = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/';
  var UTOS = 'https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/';
  var MUX_BBB = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';

  // Big Buck Bunny in 3840x2160 (H.264); a TV or line that cannot keep up gets the Full HD copy.
  var BBB_4K = [MIT + 'bbb_sunflower_2160p_30fps_normal.mp4', MIT + 'bbb_sunflower_1080p_60fps_normal.mp4', MUX_BBB];
  var BBB_60 = [MIT + 'bbb_sunflower_1080p_60fps_normal.mp4', MIT + 'bbb_sunflower_1080p_30fps_normal.mp4', GTV + 'BigBuckBunny.mp4'];
  var BBB_HLS = [MUX_BBB, GTV + 'BigBuckBunny.mp4'];
  var SKATE_4K = ['http://sample.vodobox.net/skate_phantom_flex_4k/skate_phantom_flex_4k.m3u8'];
  var TOS = [UTOS + 'tears-of-steel.mp4/.m3u8', UTOS + 'tears-of-steel.ism/.m3u8', GTV + 'TearsOfSteel.mp4'];
  var SINTEL = ['https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8', GTV + 'Sintel.mp4'];
  var ED = [GTV + 'ElephantsDream.mp4'];
  var BLENDER_247 = ['https://ireplay.tv/test/blender.m3u8', 'https://ireplay.tv/test/hd_blender.m3u8'];
  var LIVE_TEST = ['https://cph-p2p-msl.akamaized.net/hls/live/2000341/test/master.m3u8'];
  var PATTERN = ['https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8'];

  var CREDIT = {
    bbb: '(c) Blender Foundation | www.bigbuckbunny.org. Creative Commons Attribution 3.0.',
    tos: '(c) Blender Foundation | mango.blender.org. Creative Commons Attribution 3.0.',
    sintel: '(c) Blender Foundation | www.sintel.org. Creative Commons Attribution 3.0.',
    ed: '(c) Blender Foundation | orange.blender.org. Creative Commons Attribution 2.5.'
  };

  // Channels. lp: a film that starts again at its end, so the channel never stops.
  function ch(id, n, logo, cat, urls, loop, prog) {
    return { k: 'live', id: id, n: n, i: 'img/demo/' + logo + '.png', c: cat, urls: urls, lp: loop ? 1 : 0, prog: prog };
  }
  var LIVE = [
    ch('dl1', '4K UHD · Big Buck Bunny', 'ch-4k', 'uhd', BBB_4K, true, ['Big Buck Bunny in Ultra HD', 'Picture quality demo']),
    ch('dl2', '4K UHD · Skate Slow Motion', 'ch-skate', 'uhd', SKATE_4K, true, ['Skateboarding in slow motion, 4K', 'Phantom Flex camera test']),
    ch('dl3', 'Blender Movies 24/7', 'ch-live', 'live', BLENDER_247, false, ['Blender open movies, non-stop', 'Animation channel']),
    ch('dl4', 'Live Test Channel', 'ch-test', 'live', LIVE_TEST, false, ['Live test signal', 'Live stream check']),
    ch('dl5', 'Full HD 60fps · Big Buck Bunny', 'ch-hd60', 'hd', BBB_60, true, ['Big Buck Bunny, Full HD 60 fps', 'Smooth motion demo']),
    ch('dl6', 'Tears of Steel', 'ch-movies', 'hd', TOS, true, ['Tears of Steel', 'Science fiction short film']),
    ch('dl7', 'Sintel', 'ch-movies', 'hd', SINTEL, true, ['Sintel', 'Fantasy short film']),
    ch('dl8', 'Elephants Dream', 'ch-hd', 'hd', ED, true, ['Elephants Dream', 'Science fiction short film']),
    ch('dl9', 'Big Buck Bunny · Adaptive', 'ch-hd', 'hd', BBB_HLS, true, ['Big Buck Bunny, adaptive stream', 'Quality follows the line speed']),
    ch('dl10', 'HLS Test Pattern', 'ch-pattern', 'hd', PATTERN, true, ['Test pattern, several qualities', 'Stream check'])
  ];

  function film(id, n, pic, cat, urls, info) {
    var it = { k: 'vod', id: id, n: n, i: 'img/demo/' + pic + '.jpg', c: cat, e: 'mp4', urls: urls };
    if (info.rating) it.r = String(info.rating);
    info.cover = it.i;
    info.backdrop = 'img/demo/' + pic + '-wide.jpg';
    it.info = info;
    return it;
  }
  var FILMS = [
    film('dm1', 'Big Buck Bunny (4K)', 'bbb', 'uhd', BBB_4K, {
      year: '2008', genre: 'Animation, Comedy', duration: '10 min', rating: 8, country: 'Netherlands', director: 'Sacha Goedegebure',
      plot: 'A giant, gentle rabbit gets his own back on three rodents who bully the forest animals. In Ultra HD, 3840 x 2160. ' + CREDIT.bbb
    }),
    film('dm2', 'Skate in Slow Motion (4K)', 'skate', 'uhd', SKATE_4K, {
      genre: 'Sport, Test footage',
      plot: 'Skateboard tricks filmed with a Phantom Flex high-speed camera: fine detail and smooth slow motion in 4K. A public test clip for video players.'
    }),
    film('dm3', 'Big Buck Bunny (Full HD 60fps)', 'bbbhd', 'hd', BBB_60, {
      year: '2008', genre: 'Animation, Comedy', duration: '10 min', rating: 8, country: 'Netherlands', director: 'Sacha Goedegebure',
      plot: 'The same film at 60 frames per second: very smooth motion. ' + CREDIT.bbb
    }),
    film('dm4', 'Tears of Steel', 'tos', 'hd', TOS, {
      year: '2012', genre: 'Science Fiction', duration: '12 min', rating: 7, country: 'Netherlands', director: 'Ian Hubert',
      plot: 'In a future Amsterdam, a group of scientists tries to save the world from destructive robots. Live action with visual effects. ' + CREDIT.tos
    }),
    film('dm5', 'Sintel', 'sintel', 'hd', SINTEL, {
      year: '2010', genre: 'Fantasy, Animation', duration: '15 min', rating: 7.6, country: 'Netherlands', director: 'Colin Levy',
      plot: 'A lonely young woman, Sintel, searches for the baby dragon she once rescued and raised. ' + CREDIT.sintel
    }),
    film('dm6', 'Elephants Dream', 'ed', 'hd', ED, {
      year: '2006', genre: 'Science Fiction, Animation', duration: '11 min', rating: 6.5, country: 'Netherlands', director: 'Bassam Kurdali',
      plot: 'Two men explore a strange, ever-changing machine world. The first open movie made with free software. ' + CREDIT.ed
    })
  ];

  function ep(id, season, num, title, urls, duration) {
    return { id: id, title: title, ext: 'mp4', season: season, num: num, duration: duration || '', urls: urls };
  }
  var SERIES = [
    {
      k: 'series', id: 'ds1', n: 'Open Movie Collection', i: 'img/demo/blender.jpg', c: 'all', r: '8',
      info: {
        plot: 'Four short films by the Blender Foundation, made with free software and shared with everyone (Creative Commons Attribution).',
        genre: 'Animation, Science Fiction', cover: 'img/demo/blender.jpg',
        seasons: {
          1: [ep('ds1e1', 1, 1, 'Elephants Dream (2006)', ED, '11 min'), ep('ds1e2', 1, 2, 'Big Buck Bunny (2008) · 4K', BBB_4K, '10 min'),
            ep('ds1e3', 1, 3, 'Sintel (2010)', SINTEL, '15 min'), ep('ds1e4', 1, 4, 'Tears of Steel (2012)', TOS, '12 min')]
        },
        order: [1]
      }
    },
    {
      k: 'series', id: 'ds2', n: '4K UHD Showcase', i: 'img/demo/uhd.jpg', c: 'all', r: '9',
      info: {
        plot: 'Clips to see what the player and the TV can do: Ultra HD detail in season 1, smooth 60 fps and adaptive streaming in season 2.',
        genre: 'Picture quality demo', cover: 'img/demo/uhd.jpg',
        seasons: {
          1: [ep('ds2e1', 1, 1, 'Big Buck Bunny · 4K', BBB_4K, '10 min'), ep('ds2e2', 1, 2, 'Skate in Slow Motion · 4K', SKATE_4K)],
          2: [ep('ds2e3', 2, 1, 'Big Buck Bunny · Full HD 60 fps', BBB_60, '10 min'), ep('ds2e4', 2, 2, 'Big Buck Bunny · Adaptive stream', BBB_HLS, '10 min')]
        },
        order: [1, 2]
      }
    }
  ];

  var DATA = {
    live: { cats: [{ id: 'uhd', name: '4K Ultra HD' }, { id: 'live', name: 'Live 24/7' }, { id: 'hd', name: 'Full HD' }], items: LIVE },
    vod: { cats: [{ id: 'uhd', name: '4K Ultra HD' }, { id: 'hd', name: 'Full HD' }], items: FILMS },
    series: { cats: [{ id: 'all', name: 'Demo Series' }], items: SERIES }
  };
  function find(kind, id) {
    var l = DATA[kind].items;
    for (var i = 0; i < l.length; i++) if (l[i].id === id) return l[i];
    return null;
  }

  function Demo() { this.type = 'demo'; }
  Src.Demo = Demo;
  Demo.prototype.label = function () { return 'Demo 4K'; };
  Demo.prototype.login = function () {
    return Promise.resolve({ status: 'Active', expires: null, note: 'Built-in demo content' });
  };
  Demo.prototype.categories = function (kind) { return Promise.resolve(DATA[kind].cats.slice()); };
  Demo.prototype.items = function (kind, cat) {
    return Promise.resolve(DATA[kind].items.filter(function (it) { return it.c === cat; }));
  };
  Demo.prototype.all = function (kind) { return Promise.resolve(DATA[kind].items.slice()); };
  Demo.prototype.hasAll = function () { return true; };
  Demo.prototype.vodInfo = function (it) {
    var f = find('vod', it.id);
    return Promise.resolve(f ? U.extend({}, f.info) : { cover: it.i });
  };
  Demo.prototype.seriesInfo = function (id) {
    var s = find('series', id);
    return Promise.resolve(s ? s.info : { plot: '', cover: '', genre: '', seasons: {}, order: [] });
  };
  /** A guide for the demo channels, so the guide box, the bar and the TV Guide look as they do with
   *  real channels: from 6 hours ago to a day ahead, the same programme lengths every time. */
  var LENGTHS = [[30, 60, 30, 90, 60], [60, 30, 30, 60, 90, 30], [90, 30, 60, 30], [30, 30, 60, 60, 120]];
  function demoGuide(c) {
    var n = 0, i;
    for (i = 0; i < LIVE.length; i++) if (LIVE[i] === c) n = i;
    var day = new Date(); day.setHours(0, 0, 0, 0);
    var now = Date.now(), from = now - 6 * 3600000, to = now + 26 * 3600000, out = [];
    var lens = LENGTHS[n % LENGTHS.length], t = day.getTime() - 24 * 3600000, k = 0;
    while (t < to) {
      var len = lens[(k + n) % lens.length] * 60000;
      if (t + len > from) {
        out.push({
          title: c.prog[k % c.prog.length], start: t, end: t + len, archive: false,
          desc: k % c.prog.length ? 'Built-in demo channel: ' + c.n + '.' : 'Demo channel built into the app to show the picture quality. Add your own playlist on the website to watch your channels.'
        });
      }
      t += len;
      k++;
    }
    return out;
  }
  Demo.prototype.guide = function (it) {
    var c = find('live', it && it.id);
    return Promise.resolve(c ? demoGuide(c) : []);
  };
  Demo.prototype.epg = function (it) {
    var now = Date.now();
    return this.guide(it).then(function (l) { return l.filter(function (e) { return e.end > now; }).slice(0, 6); });
  };
  Demo.prototype.recordings = function () { return Promise.resolve([]); };
  Demo.prototype.liveUrls = function (it) { var c = find('live', it.id); return c ? c.urls.slice() : []; };
  Demo.prototype.loops = function (it) { var c = find('live', it.id); return !!(c && c.lp); };
  Demo.prototype.vodUrls = function (it) { var f = find('vod', it.id); return f ? f.urls.slice() : []; };
  Demo.prototype.vodUrl = function (it) { return this.vodUrls(it)[0] || ''; };
  Demo.prototype.episodeUrls = function (e) { return (e.urls || []).slice(); };
  Demo.prototype.episodeUrl = function (e) { return (e.urls || [])[0] || ''; };

  // The demo is a "playlist" of its own: remembered like the others, so the app opens it again.
  var fromSession = Src.fromSession, toSession = Src.toSession;
  Src.fromSession = function (s) { return s && s.mode === 'demo' ? new Demo() : fromSession(s); };
  Src.toSession = function (src) { return src.type === 'demo' ? { mode: 'demo' } : toSession(src); };

  /** True while the demo is open (the built-in videos or the demo set on the website). */
  App.inDemo = function () { var s = Store.session(); return !!(s && (s.mode === 'demo' || s.demo)); };

  function openBuiltIn(auto) {
    var src = new Demo();
    Store.save({ mode: 'demo', auto: !!auto }, null);
    App.src = src;
    App.log('demo opened: built-in videos');
    return src.login().then(function (acc) { Nav.reset(new Screens.Home(src, acc)); });
  }

  /** The demo set on the website (asked again when the last answer is old), or null. */
  function websiteDemo() {
    if (Backend.demoAt && Date.now() - Backend.demoAt < 5 * 60000) return Promise.resolve(Backend.demo || null);
    if (!Backend.configured() || !Backend.registered()) return Promise.resolve(null);
    return Promise.race([
      Backend.playlists().then(function () { return Backend.demo || null; }, function () { return Backend.demo || null; }),
      new Promise(function (r) { setTimeout(function () { r(Backend.demo || null); }, 6000); })
    ]);
  }

  /** Opens the demo: the playlist set on the website when there is one, else the built-in videos.
   *  auto: opened from the start screen (no playlist yet), so the first playlist added on the
   *  website replaces it by itself. */
  var opening = false;
  App.openDemo = function (auto) {
    if (opening) return Promise.resolve();
    opening = true;
    function done() { opening = false; }
    UI.toast('Loading the demo…', 20000);
    return websiteDemo().then(function (p) {
      if (!p) { U.$('toast').innerHTML = ''; return openBuiltIn(auto); }
      return Src.open(p).then(function (r) {
        var s = Src.toSession(r.src);
        s.demo = 1;
        s.auto = !!auto;
        Store.save(s, p);
        S.del('demo_failed');
        App.src = r.src;
        U.$('toast').innerHTML = '';
        App.log('demo opened: website playlist');
        Nav.reset(new Screens.Home(r.src, r.account));
      }, function (e) {
        // Not hidden: the owner should know the demo link on the website does not open.
        App.log('demo set on the website did not open: ' + Src.friendly(e));
        S.set('demo_failed', Store.sig(p));
        U.$('toast').innerHTML = '';
        return openBuiltIn(auto).then(function () {
          UI.message('Demo', 'The demo playlist set on the website did not open (' + Src.friendly(e) + '). The test videos built into the app are shown instead.');
        });
      });
    }).then(done, function (e) { done(); throw e; });
  };
})();
