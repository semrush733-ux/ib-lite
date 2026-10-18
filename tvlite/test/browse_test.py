"""Browser test of the light TV app's Movies / Series lists (not part of the app).

Builds the Samsung variant, serves it next to the mock website (ci/mock_server.py) and opens it in
Chromium, signed in to the mock's Xtream account. The films the mock sends get dates, years and
ratings on the way (so the mock itself stays as the Android tests know it). Checks: "Recently
Added" (newest first, titles without a date left out), Sort (A–Z, newest added, year, rating; kept
for next time; not for Recent / Recently Added), Up from the first row of covers reaching Sort, and
the year found in a title's name.

    python3 tvlite/test/browse_test.py            (from the repository root)
"""
import json, os, subprocess, sys, tempfile, time

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avplay_test as T  # noqa: E402
import features_test as FT  # noqa: E402

ROOT = T.ROOT
FILMS = [
    {'num': 1, 'name': 'Bravo (2019)', 'stream_id': 101, 'stream_icon': '', 'rating': '6.1', 'category_id': '11', 'container_extension': 'mp4', 'added': '1700000000'},
    {'num': 2, 'name': 'alpha', 'stream_id': 102, 'stream_icon': '', 'rating': '8.4', 'category_id': '11', 'container_extension': 'mp4', 'added': '1760000000', 'year': '2024'},
    {'num': 3, 'name': '"Charlie" - 2021', 'stream_id': 103, 'stream_icon': '', 'rating': '', 'category_id': '11', 'container_extension': 'mp4'},
    {'num': 4, 'name': 'Delta', 'stream_id': 104, 'stream_icon': '', 'rating': '7.0', 'category_id': '11', 'container_extension': 'mp4', 'added': '1730000000', 'releaseDate': '2016-05-01'},
]


def names(page):
    return page.evaluate("[].slice.call(document.querySelectorAll('.poster')).filter(function (t) { return t.style.display !== 'none' && t._cap; })"
                         ".map(function (t) { return t._cap.textContent; })")


def main():
    tmp = tempfile.mkdtemp(prefix='tvlite-browse-')
    mock = subprocess.Popen([sys.executable, os.path.join(ROOT, 'ci/mock_server.py'), '8787'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)
    time.sleep(1.5)
    app = T.build('tizen', tmp)
    srv = T.serve(app, FT.PORT)
    fake = open(os.path.join(HERE, 'fake_tizen.js')).read()
    check = T.check

    def films(route):
        if 'get_vod_streams' in route.request.url:
            route.fulfill(status=200, content_type='application/json', body=json.dumps(FILMS))
        else:
            route.continue_()
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=['--disable-web-security'])
            ctx = b.new_context(viewport={'width': 1920, 'height': 1080})
            ctx.route('**/player_api.php*', films)
            page = ctx.new_page()
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.add_init_script("try { localStorage.setItem('lt_privacy_ok', '1'); localStorage.setItem('lt_session', %s); } catch (e) {}\n%s" % (json.dumps(json.dumps(FT.SESSION)), fake))
            page.goto('http://127.0.0.1:%d/index.html' % FT.PORT)
            T.wait_for(page, "!document.getElementById('intro') && !!(window.Nav && Nav.top())", 15)
            years = page.evaluate("App.src.all('vod').then(function (l) { var o = {}; l.forEach(function (it) { o[it.n] = it.y || 0; }); return o; })")
            check('year: from the server, the release date or the name', years == {'Bravo (2019)': 2019, 'alpha': 2024, '"Charlie" - 2021': 2021, 'Delta': 2016}, years)

            page.evaluate("Nav.push(new Screens.Browse(App.src, 'vod'))")
            T.wait_for(page, "Nav.top().name === 'browse-vod' && document.querySelectorAll('.poster').length > 0", 6)
            time.sleep(0.6)
            cats = page.evaluate("[].slice.call(document.querySelectorAll('.cats .crow')).filter(function (r) { return r.style.display !== 'none'; }).map(function (r) { return r.textContent.replace(/[\\uE000-\\uF8FF]|[\\uDB80-\\uDBFF][\\uDC00-\\uDFFF]/g, '').replace(/\\(\\d+\\)$/, '').trim(); })")
            check('categories: Recently Added after Recent', 'Recently Added' in cats and cats.index('Recently Added') == cats.index('Recent') + 1, cats)
            check('default order: as the server sends them', names(page) == ['Bravo (2019)', 'alpha', '"Charlie" - 2021', 'Delta'], names(page))
            check('Sort button shown', page.evaluate("!document.querySelector('.srt').classList.contains('hide')"))

            # Up from the first row of covers reaches Sort; Down goes back
            page.evaluate("F.set(document.querySelector('.poster')); App.key('up')")
            check('remote: Up from the covers reaches Sort', page.evaluate("F.cur && F.cur.classList.contains('srt')"))
            page.evaluate("App.key('ok')")
            T.wait_for(page, "!!UI.topDialog()", 2)
            opts = page.evaluate("[].slice.call(UI.topDialog().querySelectorAll('.opt')).map(function (o) { return o.textContent.replace(/[\\uE000-\\uF8FF]|[\\uDB80-\\uDBFF][\\uDC00-\\uDFFF]/g, '').trim(); })")
            check('Sort: five orders', opts == ['Default order', 'Newest added', 'A–Z', 'Year (newest first)', 'Rating (best first)'], opts)

            def pick(label):
                page.evaluate("""(l) => { var o = [].slice.call(UI.topDialog().querySelectorAll('.opt')).filter(function (x) { return x.textContent.indexOf(l) >= 0; })[0]; F.set(o); o._ok(); }""", label)
                time.sleep(0.3)
            pick('A–Z')
            check('A–Z (quotes and case do not count)', names(page) == ['alpha', 'Bravo (2019)', '"Charlie" - 2021', 'Delta'], names(page))
            check('Sort button names the order', 'A–Z' in page.evaluate("document.querySelector('.srt').textContent"))
            for label, want in (('Newest added', ['alpha', 'Delta', 'Bravo (2019)', '"Charlie" - 2021']),
                                ('Year', ['alpha', '"Charlie" - 2021', 'Bravo (2019)', 'Delta']),
                                ('Rating', ['alpha', 'Delta', 'Bravo (2019)', '"Charlie" - 2021'])):
                page.evaluate("document.querySelector('.srt')._ok()")
                T.wait_for(page, "!!UI.topDialog()", 2)
                pick(label)
                check('Sort: ' + label, names(page) == want, names(page))
            check('Sort: kept for next time', page.evaluate("JSON.parse(localStorage.getItem('lt_sort_vod'))") == 'rating')

            # Recently Added: newest first, without the undated one, and no Sort there
            page.evaluate("""(function () { var r = [].slice.call(document.querySelectorAll('.cats .crow')).filter(function (x) { return /Recently Added/.test(x.innerText); })[0];
                F.set(r); r._ok(); })()""")
            T.wait_for(page, "/Recently Added/.test(document.querySelector('.br-title .t').textContent)", 4)
            time.sleep(0.6)
            check('Recently Added: newest first, undated left out', names(page) == ['alpha', 'Delta', 'Bravo (2019)'], names(page))
            check('Recently Added: no Sort button', page.evaluate("document.querySelector('.srt').classList.contains('hide')"))
            check('no script errors', not errors, '; '.join(errors[:3]))
            b.close()
    finally:
        mock.terminate()
        srv.shutdown()
    print('\n%d failed' % len(T.FAILS))
    sys.exit(1 if T.FAILS else 0)


if __name__ == '__main__':
    main()
