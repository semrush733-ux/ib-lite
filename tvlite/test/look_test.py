"""Browser test of the light TV app's languages and wallpapers (not part of the app).

Builds the Samsung variant, serves it next to the mock server (ci/mock_server.py) and opens it in
Chromium. Checks: English by default, Settings › Language (Urdu: the app starts again with the
Android app's Urdu texts, and only that language's file loads), Automatic (a TV in German gets
German), and Settings › Main Wallpaper (the home picture changes at once, the choice stays).

    python3 tvlite/test/look_test.py              (from the repository root)
"""
import json, os, re, subprocess, sys, tempfile, time

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avplay_test as T  # noqa: E402
import features_test as FT  # noqa: E402

ROOT = T.ROOT
check = T.check


def plain(s):
    return re.sub('[-\U000f0000-\U000fffff]', '', s or '').strip()


def tiles(page):
    return [plain(x) for x in page.evaluate("[].slice.call(document.querySelectorAll('.tile .tt')).map(function (t) { return t.textContent; })")]


def table(lang):
    src = open(os.path.join(ROOT, 'tvlite/js/i18n.js'), encoding='utf-8').read()
    keys = json.loads(re.search(r'I18N.keys = (\[.*?\]);', src, re.S).group(1))
    row = json.loads(re.search(r'I18N.add\("%s", (\[.*\])\);' % lang, open(os.path.join(ROOT, 'tvlite/js/lang/%s.js' % lang), encoding='utf-8').read(), re.S).group(1))
    return dict(zip(keys, row))


def open_home(b, locale=None, init=''):
    ctx = b.new_context(viewport={'width': 1920, 'height': 1080}, locale=locale) if locale else b.new_context(viewport={'width': 1920, 'height': 1080})
    page = ctx.new_page()
    errors = []
    page.on('pageerror', lambda e: errors.append(str(e)))
    page.add_init_script("try { if (!localStorage.getItem('lt_session')) localStorage.setItem('lt_session', %s); } catch (e) {}\n%s"
                         % (json.dumps(json.dumps(FT.SESSION)), init))
    page.goto('http://127.0.0.1:%d/index.html' % FT.PORT)
    T.wait_for(page, "!document.getElementById('intro') && !!(window.Nav && Nav.top()) && Nav.top().name === 'home'", 15)
    return ctx, page, errors


def scripts(page):
    return page.evaluate("[].slice.call(document.querySelectorAll('script[src]')).map(function (s) { return s.getAttribute('src'); })")


def main():
    tmp = tempfile.mkdtemp(prefix='tvlite-look-')
    mock = subprocess.Popen([sys.executable, os.path.join(ROOT, 'ci/mock_server.py'), '8787'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)
    time.sleep(1.5)
    app = T.build('tizen', tmp)
    srv = T.serve(app, FT.PORT)
    ur, de = table('ur'), table('de')
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=['--disable-web-security'])
            ctx, page, errors = open_home(b, 'en-US')
            check('English by default', tiles(page) == ['Live TV', 'Movies', 'TV Series', 'Catch Up'], tiles(page))
            check('English: no language file loads', not any('js/lang/' in s for s in scripts(page)), scripts(page))

            # ---------------- Settings › Language: Urdu
            page.evaluate("Nav.push(new Screens.Settings())")
            T.wait_for(page, "Nav.top().name === 'settings'", 2)
            page.evaluate("[].slice.call(document.querySelectorAll('.sbox')).filter(function (r) { return r.querySelector('.lb').textContent === 'Language'; })[0]._ok()")
            check('Language: the choices', T.wait_for(page, "document.querySelectorAll('.lg2').length === 26", 2), page.evaluate("document.querySelectorAll('.lg2').length"))
            check('Language: Automatic is the one in use', plain(page.evaluate("F.cur.textContent")).startswith('Automatic'), page.evaluate("F.cur.textContent"))
            page.screenshot(path=os.path.join(tmp, 'languages.png'))
            with page.expect_navigation():
                page.evaluate("[].slice.call(document.querySelectorAll('.lg2')).filter(function (b) { return /Urdu/.test(b.textContent); })[0]._ok()")
            T.wait_for(page, "!document.getElementById('intro') && !!(window.Nav && Nav.top()) && Nav.top().name === 'home'", 15)
            want = [ur['Live TV'], ur['Movies'], ur['Series'], ur['Catch Up']]
            check('Urdu: the home tiles', tiles(page) == want, [tiles(page), want])
            check('Urdu: Settings', plain(page.evaluate("document.querySelectorAll('.hm-pills .pill')[2].textContent")) == ur['Settings'],
                  page.evaluate("document.querySelectorAll('.hm-pills .pill')[2].textContent"))
            check('Urdu: only its own file loads', [s for s in scripts(page) if 'js/lang/' in s] == ['js/lang/ur.js'], scripts(page))
            page.evaluate("Nav.push(new Screens.Browse(App.src, 'live'))")
            T.wait_for(page, "document.querySelectorAll('.pbtn').length === 3", 6)
            btns = [plain(x) for x in page.evaluate("[].slice.call(document.querySelectorAll('.pbtn')).map(function (b) { return b.textContent; })")]
            check('Urdu: Live TV buttons', btns == [ur['Full screen'], ur['TV Guide'], ur['Favourite']], btns)
            page.screenshot(path=os.path.join(tmp, 'urdu-live.png'))
            FT.back_to(page, 'home')
            page.screenshot(path=os.path.join(tmp, 'urdu-home.png'))
            check('Urdu: no script errors', not errors, '; '.join(errors[:3]))
            ctx.close()

            # ---------------- Automatic: a TV in German
            ctx, page, errors = open_home(b, 'de-DE')
            want = [de['Live TV'], de['Movies'], de['Series'], de['Catch Up']]
            check('Automatic: German on a German TV', tiles(page) == want, [tiles(page), want])
            fit = page.evaluate("""(function () { var p = document.querySelector('.hm-pills'), s = document.querySelectorAll('.hm-pills .pill')[2];
                var l = s.querySelector('.pl'); return [p.scrollWidth <= p.clientWidth, l.scrollWidth <= l.clientWidth + 1, l.textContent]; })()""")
            check('German: "Einstellungen" fits next to the playlist', fit[0] and fit[1], fit)
            check('German: no script errors', not errors, '; '.join(errors[:3]))

            # ---------------- Settings › Main Wallpaper
            check('wallpaper: the standard one', 'img/home_full.webp' in page.evaluate("document.querySelector('.hm-bg').style.backgroundImage"))
            page.evaluate("Nav.push(new Screens.Settings())")
            T.wait_for(page, "Nav.top().name === 'settings'", 2)
            page.evaluate("(l) => [].slice.call(document.querySelectorAll('.sbox')).filter(function (r) { return r.querySelector('.lb').textContent === l; })[0]._ok()", de['Main Wallpaper'])
            check('wallpaper: 21 choices', T.wait_for(page, "document.querySelectorAll('.wp').length === 21", 2))
            check('wallpaper: the thumbnails load', T.wait_for(page, "[].slice.call(document.querySelectorAll('.wp img')).every(function (i) { return i.complete && i.naturalWidth === 384; })", 4))
            page.screenshot(path=os.path.join(tmp, 'wallpapers.png'))
            page.evaluate("document.querySelectorAll('.wp')[7]._ok()")
            check('wallpaper: picked', page.evaluate("JSON.parse(localStorage.getItem('lt_wallpaper'))") == 7)
            check('wallpaper: the home picture changes', 'img/wall/wp07.webp' in page.evaluate("Nav.find('home').el.querySelector('.hm-bg').style.backgroundImage"))
            page.evaluate("UI.closeAll()")
            FT.back_to(page, 'home')
            T.wait_for(page, "true", 0.6)
            page.screenshot(path=os.path.join(tmp, 'home-wallpaper7.png'))
            ok = page.evaluate("""new Promise(function (r) { var i = new Image(); i.onload = function () { r(i.naturalWidth); }; i.onerror = function () { r(0); }; i.src = 'img/wall/wp07.webp'; })""")
            check('wallpaper: the picture is in the app', ok == 1280, ok)
            check('wallpaper: no script errors', not errors, '; '.join(errors[:3]))
            print('screenshots:', tmp)
            ctx.close()
            b.close()
    finally:
        mock.terminate()
        srv.shutdown()
    print('\n%d failed' % len(T.FAILS))
    sys.exit(1 if T.FAILS else 0)


if __name__ == '__main__':
    main()
