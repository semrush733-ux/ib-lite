"""Browser test of the light TV app's home screen features (not part of the app).

Builds the Samsung variant, serves it next to the mock website (ci/mock_server.py) and opens it in
Chromium with the stand-in for Samsung's AVPlay (test/fake_tizen.js), signed in to the mock's Xtream
account. Checks: the playlist box, Continue Watching (a film and an episode stopped half way, the
card plays on where it stopped, "Next episode" after one watched to the end, removing a card), the
home layout with and without the row and the streaming boxes, and "Start with the last channel".

    python3 tvlite/test/features_test.py          (from the repository root)
"""
import json, os, subprocess, sys, tempfile, time

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avplay_test as T  # noqa: E402  (build, serve, wait_for, check)

ROOT = T.ROOT
PORT = 8093
SESSION = {'mode': 'xtream', 'server': 'http://127.0.0.1:8787', 'user': 'demo', 'pass': 'demo', 'pid': 0, 'pname': 'UK Sports', 'psig': ''}


def start(b, fake, extra=''):
    page = b.new_page(viewport={'width': 1920, 'height': 1080})
    errors = []
    page.on('pageerror', lambda e: errors.append(str(e)))
    init = ("try { localStorage.setItem('lt_privacy_ok', '1'); localStorage.setItem('lt_session', %s); localStorage.setItem('lt_samsung_player', JSON.stringify('avplay')); } catch (e) {}\n"
            % json.dumps(json.dumps(SESSION))) + extra + '\n' + fake
    page.add_init_script(init)
    page.goto('http://127.0.0.1:%d/index.html' % PORT)
    T.wait_for(page, "!document.getElementById('intro') && !!(window.Nav && Nav.top())", 15)
    return page, errors


def top(page):
    return page.evaluate('Nav.top() && Nav.top().name')


def back_to(page, name, tries=5):
    """Back until that screen is on top (the player's bar takes the first Back when it shows)."""
    for _ in range(tries):
        if top(page) == name:
            return True
        page.evaluate("App.key('back')")
        T.wait_for(page, "Nav.top().name === %s" % json.dumps(name), 0.8)
    return top(page) == name


def rects(page, sels):
    return page.evaluate("""(sels) => sels.map(function (s) {
        var e = document.querySelector(s); if (!e || e.offsetParent === null) return null;
        var r = e.getBoundingClientRect(); return [s, Math.round(r.top), Math.round(r.bottom)]; })""", sels)


def no_overlap(rows):
    rows = [r for r in rows if r]
    return all(rows[i][2] <= rows[i + 1][1] for i in range(len(rows) - 1))


def main():
    tmp = tempfile.mkdtemp(prefix='tvlite-features-')
    mock = subprocess.Popen([sys.executable, os.path.join(ROOT, 'ci/mock_server.py'), '8787'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)
    time.sleep(1.5)
    app = T.build('tizen', tmp)
    srv = T.serve(app, PORT)
    fake = open(os.path.join(HERE, 'fake_tizen.js')).read()
    check = T.check
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=['--disable-web-security'])
            # ---------------- the start: the name is written letter by letter, the app loads after it
            pg = b.new_page(viewport={'width': 1920, 'height': 1080})
            pg.add_init_script("try { localStorage.setItem('lt_privacy_ok', '1'); localStorage.setItem('lt_session', %s); } catch (e) {}" % json.dumps(json.dumps(SESSION)))
            pg.goto('http://127.0.0.1:%d/index.html' % PORT, wait_until='domcontentloaded')
            T.wait_for(pg, "/go/.test(document.getElementById('intro').className)", 3)
            letters = pg.evaluate("document.querySelectorAll('#intro .ch').length")
            check('start: the name in letters', letters == len('IBO Lite Player'), letters)
            check('start: the app waits while the letters are written',
                  pg.evaluate("!/done/.test(document.getElementById('intro').className) ? typeof window.Nav === 'undefined' : true"))
            check('start: written, then the app loads', T.wait_for(pg, "/done/.test(document.getElementById('intro') ? document.getElementById('intro').className : 'done') && !!window.Nav", 6))
            check('start: the brand fades to the home screen', T.wait_for(pg, "!document.getElementById('intro') && Nav.top() && Nav.top().name === 'home'", 8))
            pg.close()

            page, errors = start(b, fake)
            check('home: opens', top(page) == 'home', top(page))
            check('home: playlist box filled', T.wait_for(page, "/Playlist Expiry:/.test(document.querySelector('.plbox').innerText)", 6),
                  page.evaluate("document.querySelector('.plbox').innerText"))
            check('home: no Continue Watching row yet', not page.evaluate("Nav.top().el.classList.contains('cw')"))

            # ---------------- a film stopped at 10 minutes
            page.evaluate("""App.src.categories('vod').then(function (c) { return App.src.items('vod', c[0].id); })
                .then(function (l) { window.__film = l[0]; Nav.push(new Screens.Movie(App.src, l[0])); })""")
            check('film page opens', T.wait_for(page, "Nav.top().name === 'movie'", 6))
            page.evaluate("window.__av.live = false; F.cur._ok()")
            check('film plays', T.wait_for(page, "Nav.top().name === 'player' && Player.state() === 'playing'", 8), page.evaluate('Player.state()'))
            page.evaluate('Player.seek(600)')
            time.sleep(0.6)
            back_to(page, 'movie')  # leaves the player (saves the place)
            check('back on home', back_to(page, 'home'), top(page))
            cards = page.evaluate("[].slice.call(document.querySelectorAll('.cwc')).map(function (c) { return c.innerText.replace(/\\s+/g, ' ').trim(); })")
            check('Continue Watching: one card for the film', len(cards) == 1 and 'Test Movie' in cards[0], cards)
            check('Continue Watching: time left', cards and '50 min left' in cards[0], cards)
            width = page.evaluate("document.querySelector('.cwc .pb i') && document.querySelector('.cwc .pb i').style.width")
            check('Continue Watching: progress bar', width in ('16%', '17%'), width)
            check('home: tiles shorter, rows do not overlap',
                  page.evaluate("Nav.top().el.classList.contains('cw')") and
                  no_overlap(rects(page, ['.hm-tiles', '.hm-cw', '.hm-bottom'])), rects(page, ['.hm-tiles', '.hm-cw', '.hm-bottom']))
            page.screenshot(path=os.path.join(tmp, 'home-continue.png'))
            print('screenshot:', os.path.join(tmp, 'home-continue.png'))

            # Down from the Live TV tile reaches the card; OK plays on at 10 minutes
            page.evaluate("F.set(document.querySelector('.tile')); App.key('down')")
            check('remote: Down from the tiles reaches the row', page.evaluate("F.cur && F.cur.classList.contains('cwc')"))
            page.evaluate("window.__av.calls = []; F.cur._ok()")
            check('card: the film plays again', T.wait_for(page, "Nav.top().name === 'player' && Player.state() === 'playing'", 8))
            seeks = [c for c in page.evaluate('window.__av.calls') if c[0] == 'seekTo']
            check('card: plays on where it stopped (10 min)', any(abs(s[1] - 600000) <= 5000 for s in seeks), seeks)
            back_to(page, 'home')

            # ---------------- an episode stopped at 15 minutes
            page.evaluate("""App.src.categories('series').then(function (c) { return App.src.items('series', c[0].id); })
                .then(function (l) { Nav.push(new Screens.Series(App.src, l[0])); })""")
            check('series page lists episodes', T.wait_for(page, "Nav.top().name === 'series' && document.querySelectorAll('.eprow').length > 0", 6))
            T.wait_for(page, "F.cur && F.cur.classList.contains('eprow')", 3)
            page.evaluate("window.__av.live = false; App.key('ok')")
            check('episode plays', T.wait_for(page, "Nav.top().name === 'player' && Player.state() === 'playing'", 8), page.evaluate('Player.state()'))
            page.evaluate('Player.seek(900)')
            time.sleep(0.6)
            back_to(page, 'series')
            back_to(page, 'home')
            cards = page.evaluate("[].slice.call(document.querySelectorAll('.cwc')).map(function (c) { return c.innerText.replace(/\\s+/g, ' ').trim(); })")
            check('Continue Watching: episode card first', len(cards) == 2 and 'Test Series' in cards[0] and 'S1 E1' in cards[0], cards)

            # The episode is watched to the end: its card becomes "Next episode" (S1 E2)
            page.evaluate("document.querySelector('.cwc')._ok()")
            check('episode card: plays', T.wait_for(page, "Nav.top().name === 'player' && Player.state() === 'playing'", 10), top(page))
            page.evaluate("window.__av.listener.onstreamcompleted()")
            time.sleep(1.2)
            back_to(page, 'home')
            cards = page.evaluate("[].slice.call(document.querySelectorAll('.cwc')).map(function (c) { return c.innerText.replace(/\\s+/g, ' ').trim(); })")
            check('Continue Watching: next episode card', cards and 'S1 E2' in cards[0] and 'Next episode' in cards[0], cards)

            # Holding OK: Remove from the row
            page.evaluate("F.set(document.querySelector('.cwc')); document.querySelector('.cwc')._long()")
            check('hold OK: three choices', T.wait_for(page, "!!UI.topDialog() && UI.topDialog().querySelectorAll('.btn').length === 3", 3))
            page.evaluate("UI.topDialog().querySelectorAll('.btn')[0]._ok()")
            n = page.evaluate("document.querySelectorAll('.cwc').length")
            check('remove: the card goes', n == 1, n)

            # With the streaming boxes too: everything still fits
            page.evaluate("Streaming.enabled = function () { return [{id: 'a', name: 'Netflix'}, {id: 'b', name: 'Disney+'}]; }; Nav.top().show(false)")
            rows = rects(page, ['.hm-tiles', '.hm-cw', '.hm-svc', '.hm-bottom'])
            check('home with both rows: no overlap', page.evaluate("Nav.top().el.classList.contains('svc')") and no_overlap(rows), rows)
            page.screenshot(path=os.path.join(tmp, 'home-both-rows.png'))
            print('screenshot:', os.path.join(tmp, 'home-both-rows.png'))
            check('no script errors', not errors, '; '.join(errors[:3]))
            page.close()

            # ---------------- Start with the last channel
            last = {'k': 'live', 'id': '4', 'n': 'Sports One', 'i': '', 'c': '2', 'num': 4}
            extra = ("try { localStorage.setItem('lt_start_last_channel', 'true'); localStorage.setItem('lt_recent_live', %s); } catch (e) {}"
                     % json.dumps(json.dumps([last])))
            page, errors = start(b, fake, extra)
            ok = T.wait_for(page, "Nav.top().name === 'player' && Nav.top().kind === 'live'", 8)
            check('last channel: plays by itself at the start', ok, top(page))
            opened = [c[1] for c in page.evaluate('window.__av.calls') if c[0] == 'open']
            check('last channel: the right channel', any('/4.' in u for u in opened), opened)
            check('last channel: Back goes to the home screen', back_to(page, 'home'), top(page))
            check('last channel: the picture stops', T.wait_for(page, "!Player.active()", 4))
            check('last channel: no script errors', not errors, '; '.join(errors[:3]))
            page.close()

            # A key pressed on the home screen first: no channel starts
            page, errors = start(b, fake, extra.replace("'true'", "'true'") + "\ndocument.addEventListener('DOMContentLoaded', function () {"
                                 " var t = setInterval(function () { if (window.Nav && Nav.top() && Nav.top().name === 'home' && App.blocked === false) { clearInterval(t);"
                                 " document.dispatchEvent(new KeyboardEvent('keydown', {keyCode: 39, key: 'ArrowRight', bubbles: true})); } }, 20); });")
            time.sleep(3)
            check('last channel: a key first keeps the home screen', top(page) == 'home', top(page))
            page.close()

            # Settings: the switch
            page, errors = start(b, fake)
            page.evaluate("Nav.push(new Screens.Settings())")
            # Settings › Live Player: the row "Start with the last channel", Off / On
            page.evaluate("[].slice.call(document.querySelectorAll('.sbox')).filter(function (b) { return b.querySelector('.lb').textContent === 'Live Player'; })[0]._ok()")
            T.wait_for(page, "!!document.querySelector('.choices')", 2)
            row = page.evaluate("""(function () { var r = [].slice.call(document.querySelectorAll('.choices .subrow')).filter(function (x) {
                return /Start with the last channel/.test(x.innerText); })[0]; if (!r) return null;
                var before = r.querySelector('.chip.sel').textContent; r.querySelectorAll('.chip')[1]._ok(); return [before, r.querySelector('.chip.sel').textContent,
                JSON.parse(localStorage.getItem('lt_start_last_channel'))]; })()""")
            check('settings: "Start with the last channel" switches On', row == ['Off', 'On', True], row)
            check('settings: no script errors', not errors, '; '.join(errors[:3]))
            b.close()
    finally:
        mock.terminate()
        srv.shutdown()
    print('\n%d failed' % len(T.FAILS))
    sys.exit(1 if T.FAILS else 0)


if __name__ == '__main__':
    main()
