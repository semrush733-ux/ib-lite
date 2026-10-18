"""Browser test of the light TV app's film page extras from TMDB (not part of the app).

Builds the app with a TMDB key pointed at the mock server (ci/mock_server.py stands in for TMDB:
/3/search/movie, /3/movie/555 with cast, pictures and a trailer) and checks, as in the Android app:
the cast row with photos and roles, the pictures row (a picture in focus is shown big behind the
page), the TMDB credit line, Down from the buttons into the rows (the page moves up), and on LG the
Trailer button opening the TV's YouTube app. Without a key: the server's cast names, no pictures.

    python3 tvlite/test/details_test.py           (from the repository root)
"""
import json, os, subprocess, sys, tempfile, time

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avplay_test as T  # noqa: E402
import features_test as FT  # noqa: E402

ROOT = T.ROOT
check = T.check

LUNA = """window.__luna = [];
window.PalmServiceBridge = function () {};
PalmServiceBridge.prototype.call = function (uri, params) {
  var self = this; window.__luna.push([uri, JSON.parse(params || '{}')]);
  setTimeout(function () { if (self.onservicecallback) self.onservicecallback(JSON.stringify({ returnValue: true })); }, 10);
};"""


def build(target, folder, tmdb):
    out = os.path.join(folder, 'out-' + target + ('-tmdb' if tmdb else ''))
    app = os.path.join(folder, 'app-' + target + ('-tmdb' if tmdb else ''))
    cmd = [sys.executable, os.path.join(ROOT, 'tools/build_tvlite.py'), '--target', target, '--out', out,
           '--name', 'IBO Lite Player', '--site', 'http://127.0.0.1:8787', '--id', 'com.liteplayer.tv',
           '--version', '2.0.999', '--build', '999', '--folder', app]
    if target == 'tizen':
        cmd += ['--tizen-app', 'LitePlayer', '--file', 'LitePlayer.wgt']
    if tmdb:
        cmd += ['--tmdb', 'test', '--tmdb-base', 'http://127.0.0.1:8787/3', '--tmdb-images', 'http://127.0.0.1:8787/t/p']
    subprocess.run(cmd, check=True, cwd=ROOT, stdout=subprocess.DEVNULL)
    return app


def open_film(b, port, init=''):
    page = b.new_page(viewport={'width': 1920, 'height': 1080})
    errors = []
    page.on('pageerror', lambda e: errors.append(str(e)))
    page.add_init_script("try { localStorage.setItem('lt_session', %s); } catch (e) {}\n%s" % (json.dumps(json.dumps(FT.SESSION)), init))
    page.goto('http://127.0.0.1:%d/index.html' % port)
    T.wait_for(page, "!document.getElementById('intro') && !!(window.Nav && Nav.top())", 15)
    page.evaluate("""App.src.categories('vod').then(function (c) { return App.src.items('vod', c[0].id); })
        .then(function (l) { Nav.push(new Screens.Movie(App.src, l[0])); })""")
    T.wait_for(page, "Nav.top().name === 'movie'", 6)
    return page, errors


def buttons(page):
    return [b for b in page.evaluate("[].slice.call(document.querySelectorAll('.dt .acts .btn')).map(function (b) { return b.textContent.replace(/[\\ue000-\\uf8ff]|[\\udb80-\\udbff][\\udc00-\\udfff]/g, ''); })")]


def main():
    tmp = tempfile.mkdtemp(prefix='tvlite-details-')
    mock = subprocess.Popen([sys.executable, os.path.join(ROOT, 'ci/mock_server.py'), '8787'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)
    time.sleep(1.5)
    srv = [T.serve(build('tizen', tmp, True), 8101), T.serve(build('tizen', tmp, False), 8102), T.serve(build('webos', tmp, True), 8103)]
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=['--disable-web-security'])
            # ---------------- Samsung with a TMDB key
            page, errors = open_film(b, 8101)
            check('first the server\'s cast names', T.wait_for(page, "document.querySelectorAll('.dt-row.cast .pc').length === 4", 6))
            check('then the cast row from TMDB', T.wait_for(page, "!!document.querySelector('.dt-credit') && document.querySelectorAll('.dt-row.cast .pc:not(.nm)').length === 4", 8),
                  page.evaluate("document.querySelectorAll('.dt-row.cast .pc').length"))
            first = page.evaluate("(function () { var c = document.querySelector('.dt-row.cast .pc'); return [c.querySelector('b').textContent, c.querySelector('.rl').textContent, !!c.querySelector('img')]; })()")
            check('cast: name, role and photo', first == ['Ali Khan', 'Shivam', True], first)
            check('a cast member without a photo: a figure', page.evaluate("!!document.querySelectorAll('.dt-row.cast .pc')[2].querySelector('.ph .ic')"))
            check('pictures row', page.evaluate("document.querySelectorAll('.dt-row.media .stl').length") == 3)
            check('the TMDB credit line', 'not endorsed or certified by TMDB' in page.evaluate("document.querySelector('.dt-credit') ? document.querySelector('.dt-credit').textContent : ''"))
            check('Samsung: no Trailer button (the TV app cannot open YouTube there)', 'Trailer' not in buttons(page), buttons(page))
            check('the cast is not repeated as text', 'Cast:' not in page.evaluate("document.querySelector('.dt .more').textContent"))
            page.evaluate("F.set(document.querySelector('.dt .acts .btn')); App.key('down')")
            check('Down from the buttons: the first cast member', page.evaluate("F.cur && F.cur.classList.contains('pc')") and page.evaluate("F.cur.querySelector('b').textContent") == 'Ali Khan')
            page.evaluate("App.key('right')")
            check('Right: the next one', page.evaluate("F.cur.querySelector('b').textContent") == 'Sara Ahmed')
            page.evaluate("App.key('down')")
            check('Down again: the pictures', page.evaluate("F.cur && F.cur.classList.contains('stl')"))
            time.sleep(0.3)
            moved = page.evaluate("document.querySelector('.dt-page').style.transform")
            bottom = page.evaluate("document.querySelector('.dt-row.media').getBoundingClientRect().bottom")
            check('the page moves up: the pictures are in view', bottom <= 1080, [moved, bottom])
            check('a picture in focus is shown behind the page', T.wait_for(page, "/w1280\\/s1.jpg/.test(document.querySelector('.dt-bg')._bg || '')", 3),
                  page.evaluate("document.querySelector('.dt-bg')._bg"))
            page.evaluate("App.key('right')")
            check('the next picture too', T.wait_for(page, "/w1280\\/s2.jpg/.test(document.querySelector('.dt-bg')._bg || '')", 3))
            time.sleep(0.5)
            page.screenshot(path=os.path.join(tmp, 'film-pictures.png'))
            page.evaluate("App.key('up'); App.key('up')")
            check('Up: back on the buttons, the page in place', page.evaluate("F.cur && F.cur.classList.contains('btn')") and
                  page.evaluate("document.querySelector('.dt-page').style.transform") in ('', 'none'), page.evaluate("document.querySelector('.dt-page').style.transform"))
            time.sleep(0.4)
            page.screenshot(path=os.path.join(tmp, 'film-tmdb.png'))
            check('Samsung TMDB: no script errors', not errors, '; '.join(errors[:3]))
            page.close()

            # ---------------- without a key: the server's cast names
            page, errors = open_film(b, 8102)
            check('no key: the server\'s cast names', T.wait_for(page, "document.querySelectorAll('.dt-row.cast .pc.nm').length === 4", 6),
                  page.evaluate("document.querySelectorAll('.dt-row.cast .pc').length"))
            check('no key: no pictures, no credit line', not page.evaluate("!!document.querySelector('.dt-row.media') || !!document.querySelector('.dt-credit')"))
            check('no key: no TMDB requests', 'tmdb' not in page.evaluate("App.logText()"))
            page.evaluate("F.set(document.querySelector('.dt .acts .btn')); App.key('down')")
            time.sleep(0.4)
            page.screenshot(path=os.path.join(tmp, 'film-names.png'))
            check('no key: no script errors', not errors, '; '.join(errors[:3]))
            page.close()

            # ---------------- LG: the trailer in the YouTube app
            page, errors = open_film(b, 8103, LUNA)
            check('LG: Trailer button', T.wait_for(page, "[].slice.call(document.querySelectorAll('.dt .acts .btn')).some(function (b) { return /Trailer/.test(b.textContent); })", 8), buttons(page))
            page.evaluate("[].slice.call(document.querySelectorAll('.dt .acts .btn')).filter(function (b) { return /Trailer/.test(b.textContent); })[0]._ok()")
            T.wait_for(page, "window.__luna.some(function (c) { return /applicationManager\\/launch/.test(c[0]); })", 3)
            call = [c for c in page.evaluate("window.__luna") if 'applicationManager/launch' in c[0]]
            check('LG: opens YouTube with the trailer', call and call[0][1].get('id') == 'youtube.leanback.v4' and 'TESTtrailer' in call[0][1]['params']['contentTarget'], call)
            check('LG: no script errors', not errors, '; '.join(errors[:3]))
            print('screenshots:', tmp)
            b.close()
    finally:
        mock.terminate()
        for s in srv:
            s.shutdown()
    print('\n%d failed' % len(T.FAILS))
    sys.exit(1 if T.FAILS else 0)


if __name__ == '__main__':
    main()
