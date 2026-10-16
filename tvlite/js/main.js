/* Start: the brand screen while the app gets ready, then the right first screen.
 * Also: app in the background (the video lets go), messages from the provider, exit. */
(function () {
  'use strict';

  App.scale = (function () {
    var s = (window.innerWidth || 1920) / 1920;
    return Math.abs(s - 1) > 0.01 ? s : 1;
  })();

  App.log('start ' + (CONFIG.appName || '') + ' ' + (CONFIG.version || '') + ' | ' + navigator.userAgent.slice(-60));

  // No code path may touch service workers (registering one crashes LG's web app manager).
  try { if (navigator.serviceWorker) delete Navigator.prototype.serviceWorker; } catch (e) {}

  function firstScreen() {
    if (!Backend.allowed()) return Promise.resolve(new Screens.Activation());
    var s = Store.session();
    if (s) {
      var src = Src.fromSession(s);
      App.src = src;
      return Promise.resolve(new Screens.Home(src, null));
    }
    // A new TV: register first (the QR code needs the MAC Address and Device Key), at most a few seconds.
    return Promise.race([
      Backend.ensureRegistered(),
      new Promise(function (r) { setTimeout(r, 6000); })
    ]).then(function () { return new Screens.Connect(); });
  }

  /** The brand screen goes softly once the first screen is there (and was seen for a moment). */
  function closeIntro(t0) {
    var intro = U.$('intro');
    var wait = Math.max(0, 1400 - (Date.now() - t0));
    setTimeout(function () {
      App.blocked = false;
      intro.classList.add('out');
      setTimeout(function () { if (intro.parentNode) intro.parentNode.removeChild(intro); }, 400);
    }, wait);
  }

  App.restart = function () {
    UI.closeAll();
    Player.stop();
    Player.layout('off');
    firstScreen().then(function (s) { Nav.reset(s); });
  };

  // Back on the first screen. On an LG TV the TV itself takes over, as LG's store review asks:
  // webOS 5 and older go to the Home screen, webOS 6 and 22 show the TV's own "exit the app?"
  // question, webOS 23-25 go to the Home screen. On a Samsung TV our own question, as Samsung's
  // rule asks (the app closes only after the user picks Exit); in a browser the same question.
  App.askExit = function () {
    if (window.PalmSystem && PalmSystem.platformBack) {
      App.log('back on the first screen: handed to the TV');
      try {
        PalmSystem.platformBack();
        return;
      } catch (e) {
        App.log('platformBack failed: ' + e);
      }
    }
    UI.dialog({
      title: 'Exit ' + (CONFIG.appName || 'the app') + '?', html: 'Press Exit to close the app.',
      buttons: [{ label: 'Cancel' }, { label: 'Exit', pri: true, icon: 'power', ok: App.exit }], focus: 0
    });
  };
  App.exit = function () {
    Player.stop();
    App.log('exit');
    // Samsung TV: the app ends itself.
    if (window.tizen && tizen.application) {
      try {
        tizen.application.getCurrentApplication().exit();
        return;
      } catch (e0) {
        App.log('tizen exit failed: ' + e0);
      }
    }
    try { window.close(); } catch (e) {}
    // Still here (some TVs keep the page): hand back to the TV's home screen.
    setTimeout(function () {
      try { if (window.PalmSystem && PalmSystem.platformBack) PalmSystem.platformBack(); } catch (e2) {}
    }, 300);
  };

  // Licence changed on the website (trial ended, activated, suspended).
  App.on('licence', function () {
    var top = Nav.top();
    if (!top) return;
    if (!Backend.allowed() && top.name !== 'activation') {
      App.log('licence: ' + Backend.lic.status);
      UI.closeAll();
      Player.stop();
      Player.layout('off');
      Nav.reset(new Screens.Activation());
    } else if (Backend.allowed() && top.name === 'activation') {
      App.restart();
    }
  });

  // Messages from the provider (Admin Panel) and the "reload" command.
  function inbox() {
    Backend.pollInbox().then(function (msgs) {
      msgs.forEach(function (m) { UI.message(m.title || 'Message', m.body); });
    });
  }

  // The app goes to the background (Home key, another app): the stream lets go of the TV's player.
  var parked = null;
  function hidden() { return document.hidden || document.webkitHidden; }
  function onVisibility() {
    if (hidden()) {
      if (Player.active() && Player.state() !== 'error') {
        parked = { urls: Player.urls(), live: Player.live(), start: Player.pos(), loop: Player.loops() };
        App.log('app in the background: video paused');
        Player.stop();
      }
    } else if (parked) {
      var p = parked;
      parked = null;
      var top = Nav.top();
      if (top && (top.name === 'player' || top.name === 'browse-live')) {
        App.log('app back: video again');
        Player.open(p.urls, { live: p.live, start: p.live ? 0 : p.start, loop: p.loop });
      }
    }
  }
  document.addEventListener('visibilitychange', onVisibility);
  document.addEventListener('webkitvisibilitychange', onVisibility);

  // ---------------------------------------------------------------- Samsung TV (Tizen)
  if (window.tizen) {
    App.log('samsung keys: ' + Keys.registerTizen().length);
  }
  // No screensaver while a video plays (Samsung's guide), back on when it stops or pauses.
  if (window.webapis && webapis.appcommon && webapis.appcommon.setScreenSaver) {
    var saverOff = null;
    Player.on(function (ev, d) {
      if (ev !== 'state') return;
      var off = d.state === 'playing' || d.state === 'buffering' || d.state === 'loading';
      if (off === saverOff) return;
      saverOff = off;
      try {
        var SS = webapis.appcommon.AppCommonScreenSaverState;
        webapis.appcommon.setScreenSaver(off ? SS.SCREEN_SAVER_OFF : SS.SCREEN_SAVER_ON, function () {},
          function (e) { App.log('screensaver: ' + (e && e.message)); });
      } catch (e) {
        App.log('screensaver: ' + e);
      }
    });
  }

  // ---------------------------------------------------------------- go
  var t0 = Date.now();
  App.blocked = true;
  Backend.loadConfig();
  firstScreen().then(function (s) {
    Nav.reset(s);
    closeIntro(t0);
    if (Backend.registered()) Backend.refreshStatus();
  }, function (e) {
    App.log('ERROR start: ' + (e && e.message));
    Nav.reset(new Screens.Connect());
    closeIntro(t0);
  });
  setTimeout(inbox, 15000);
  setInterval(inbox, 3 * 60000);
})();
