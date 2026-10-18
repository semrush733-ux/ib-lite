/* Privacy, as the TV stores ask (Samsung's App Development Privacy Guide, LG's review): the privacy
 * policy can be read in the app at any time (first screen, Settings, Application info), and the
 * first time the app starts it asks before anything about this TV (MAC address, device ID) is sent
 * to the website. Nothing reaches the website until the user agrees (js/main.js waits for it). */
(function () {
  'use strict';

  /** Raise when the policy changes in a way users have to agree to again. */
  var CONSENT = 1;
  App.consented = function () { return U.int(S.get('privacy_ok', 0)) >= CONSENT; };
  App.privacyUrl = function () {
    if (CONFIG.privacyUrl) return CONFIG.privacyUrl;
    var site = Backend.site();
    return site ? site + '/privacy-policy-2/' : '';
  };
  function siteName() { return Backend.siteShort() || 'our website'; }
  function appName() { return CONFIG.appName || 'This app'; }

  /** The policy for this TV (the full one, which also covers the website, is on the website). */
  function policy() {
    var a = U.esc(appName()), s = U.esc(siteName());
    function h(t) { return '<h3>' + t + '</h3>'; }
    function li(items) { return '<ul>' + items.map(function (x) { return '<li>' + x + '</li>'; }).join('') + '</ul>'; }
    return '<p>What ' + a + ' collects on this TV and why. The full policy, which also covers the website, is at <b>' +
      U.esc(App.privacyUrl().replace(/^https?:\/\//, '')) + '</b>.</p>' +
      h('1. A media player only') +
      '<p>' + a + ' contains no channels, films or other content and sells none. You add your own playlists (M3U links or Xtream Codes logins) from providers you choose.</p>' +
      h('2. What the app sends to ' + s) + li([
        '<b>Device identifiers:</b> this TV\'s MAC address and its device ID (on Samsung TVs the DUID, on LG TVs the LG device ID), to link this TV to the playlists you add on the website and to run the free trial and the licence.',
        '<b>Technical information:</b> the app version, the type of TV, when the app was last online and the IP address of its requests (for security, to stop abuse and for the local weather on the home screen; the city is worked out from the IP address, the TV\'s location is not used).',
        '<b>Problem reports</b>, only when you send one: what went wrong, your note, the app version, the TV model, the name (never the address) of the last channel or film played and the app\'s recent technical log. No passwords.',
        '<b>Playlists you add on the website</b> (name, server address, login) are kept there to bring them to this TV; passwords are stored encrypted.'
      ]) +
      h('3. Kept on this TV only') +
      '<p>Favourites, watch history, Continue Watching, profiles, the parental PIN and settings stay on this TV. Uninstalling the app removes them.</p>' +
      h('4. Other services') +
      '<p>The app connects to the playlist servers you add, to ' + s + ' and to public services for the weather, the city from the IP address and film information (TMDB). These services receive the TV\'s IP address when the app contacts them.</p>' +
      h('5. What we do not do') +
      '<p>We do not sell or rent personal data, show third-party ads, use advertising IDs or record what you watch.</p>' +
      h('6. Keeping and deleting data') +
      '<p>Device data is kept while this TV uses the app. You can delete a playlist yourself on the website, and ask for all data of this TV to be deleted at any time: the contact address is in the full policy.</p>' +
      h('7. Security') +
      '<p>Connections to ' + s + ' use HTTPS, and changing this TV\'s playlists needs its private Device Key.</p>' +
      h('8. Children') +
      '<p>The app is not directed at children under 13. Kids profiles and a parental PIN are available.</p>';
  }

  /** A block of text the remote scrolls: Up / Down move it, at its ends the focus moves on. */
  function scroller(html) {
    var box = U.el('div', 'pp-text f', '<div class="pp-in">' + html + '</div>');
    box._key = function (k) {
      if (k !== 'up' && k !== 'down') return false;
      var max = box.scrollHeight - box.clientHeight, y = box.scrollTop;
      if (k === 'down' && y >= max - 1) return false;
      if (k === 'up' && y <= 0) return false;
      box.scrollTop = k === 'down' ? Math.min(max, y + 150) : Math.max(0, y - 150);
      return true;
    };
    box.addEventListener('wheel', function (e) { box.scrollTop += e.deltaY > 0 ? 120 : -120; e.preventDefault(); });
    return box;
  }

  /** Settings › Privacy Policy (also on the first screens and in Application info). */
  App.privacyDialog = function (done) {
    App.log('privacy policy');
    var wrap = U.el('div', 'pp-wrap');
    var text = scroller(policy());
    wrap.appendChild(text);
    var side = U.el('div', 'pp-side', '<div class="pp-qr"></div><div class="pp-cap">Read it on your phone</div><div class="pp-url"></div>');
    var url = App.privacyUrl();
    if (url) side.querySelector('.pp-qr').appendChild(UI.qr(url, 300));
    side.querySelector('.pp-url').textContent = url.replace(/^https?:\/\//, '');
    wrap.appendChild(side);
    return UI.dialog({ title: 'Privacy Policy', html: wrap, width: 1640, buttons: [{ label: 'Close', pri: true }], focusEl: text, onClose: done });
  };

  /** A small "Privacy Policy" button (first screens, Settings). */
  App.privacyButton = function (cls) {
    var b = U.el('span', 'btn f ' + (cls || ''), U.icon('shield') + 'Privacy Policy');
    b._ok = function () { App.privacyDialog(); };
    return b;
  };

  // ---------------------------------------------------------------- the first start
  /** "Before you start": shown once, before the app sends anything about this TV. onAgree runs
   *  when the user agrees; without the agreement the app cannot get playlists and closes. */
  Screens.Consent = function (onAgree) {
    this.name = 'consent';
    var el = this.el = U.el('div', 'screen');
    var s = U.esc(siteName());
    el.innerHTML = '<div class="cn-bg"></div><div class="cs-left">' + UI.logo(80) +
      '<h1>Before you start</h1>' +
      '<p>To bring the playlists you add on <b>' + s + '</b> to this TV and to run your free trial and licence, ' + U.esc(appName()) + ' sends ' + s + ':</p>' +
      '<ul><li>this TV\'s <b>MAC address</b> and <b>device ID</b></li><li>the <b>app version</b> and the <b>IP address</b> of its requests</li></ul>' +
      '<p>It goes over a secure connection and is kept while you use the app. It is never sold or used for advertising, and you can ask for it to be deleted at any time.</p>' +
      '<p class="cs-no">Without your consent the app cannot receive your playlists and closes.</p>' +
      '<div class="cs-acts"></div></div>' +
      '<div class="cs-right"><div class="pp-qr"></div><div class="pp-cap">The full Privacy Policy on your phone</div><div class="pp-url"></div></div>';
    el.querySelector('.cn-bg').style.backgroundImage = 'url(img/connect_full.webp)';
    var url = App.privacyUrl();
    if (url) el.querySelector('.cs-right .pp-qr').appendChild(UI.qr(url, 380));
    el.querySelector('.cs-right .pp-url').textContent = url.replace(/^https?:\/\//, '');
    var acts = el.querySelector('.cs-acts'), waiting = false;
    var agree = U.el('span', 'btn pri f', U.icon('check') + 'Agree and continue');
    agree._ok = function () {
      if (waiting) return;
      waiting = true;
      S.set('privacy_ok', CONSENT);
      App.log('privacy: agreed');
      agree.innerHTML = U.icon('hourglass') + 'Please wait…';
      onAgree();
    };
    acts.appendChild(agree);
    acts.appendChild(App.privacyButton());
    var exit = U.el('span', 'btn f', U.icon('power') + 'Exit');
    exit._ok = function () { App.log('privacy: not agreed, the app closes'); App.exit(); };
    acts.appendChild(exit);
    this.show = function () { if (!F.cur || !el.contains(F.cur)) F.set(agree); };
  };
})();
