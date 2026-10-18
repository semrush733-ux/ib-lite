"""Browser test of the light TV app's privacy screens (not part of the app).

Builds the Samsung variant, serves it next to the mock server (ci/mock_server.py) and opens it in
Chromium with stand-ins for Samsung's device functions. Checks, as Samsung's privacy guide asks:
the first start shows "Before you start" and sends nothing to the website and reads no MAC address
or device ID until the user agrees; the Privacy Policy can be read there (text that the remote
scrolls, a QR code to the full policy), on the first screen, in Settings and in Application info;
Agree goes on (the TV registers, the first screen), the question does not come again; Exit closes.

    python3 tvlite/test/privacy_test.py           (from the repository root)
"""
import json, os, subprocess, sys, tempfile, time

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avplay_test as T  # noqa: E402
import features_test as FT  # noqa: E402

ROOT = T.ROOT
check = T.check

DEVICE = """window.__ids = { duid: 0, mac: 0 }; window.__exit = 0;
window.webapis = window.webapis || {};
window.webapis.productinfo = { getDuid: function () { window.__ids.duid++; return 'TESTDUID123'; },
  getRealModel: function () { return 'UE55TEST'; }, getFirmware: function () { return 'T-TEST'; } };
window.webapis.network = { getMac: function () { window.__ids.mac++; return '00:1A:2B:3C:4D:5E'; } };
window.tizen = window.tizen || {};
window.tizen.application = { getCurrentApplication: function () { return { exit: function () { window.__exit++; } }; } };"""


def open_app(b, fake, init='', keep=None):
    page = (keep or b.new_context(viewport={'width': 1920, 'height': 1080})).new_page()
    errors, site = [], []
    page.on('pageerror', lambda e: errors.append(str(e)))
    page.on('request', lambda r: site.append(r.url) if ':8787/' in r.url else None)
    page.add_init_script(init + '\n' + DEVICE + '\n' + fake)
    page.goto('http://127.0.0.1:%d/index.html' % FT.PORT)
    T.wait_for(page, "!document.getElementById('intro') && !!(window.Nav && Nav.top())", 15)
    return page, errors, site


def top(page):
    return page.evaluate("Nav.top() && Nav.top().name")


def focus(page):
    return T.plain(page.evaluate("F.cur ? F.cur.textContent : ''")) if hasattr(T, 'plain') else \
        page.evaluate("F.cur ? F.cur.textContent.replace(/[\\ue000-\\uf8ff]|[\\udb80-\\udbff][\\udc00-\\udfff]/g, '') : ''")


def policy_open(page):
    return T.wait_for(page, "!!document.querySelector('.dialog .pp-text')", 3)


def main():
    tmp = tempfile.mkdtemp(prefix='tvlite-privacy-')
    mock = subprocess.Popen([sys.executable, os.path.join(ROOT, 'ci/mock_server.py'), '8787'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)
    time.sleep(1.5)
    app = T.build('tizen', tmp)
    srv = T.serve(app, FT.PORT)
    fake = open(os.path.join(HERE, 'fake_tizen.js')).read()
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=['--disable-web-security'])
            ctx = b.new_context(viewport={'width': 1920, 'height': 1080})
            # ---------------- the first start
            page, errors, site = open_app(b, fake, keep=ctx)
            check('first start: "Before you start"', top(page) == 'consent', top(page))
            time.sleep(1.5)
            check('first start: nothing sent to the website yet', not site, site[:3])
            ids = page.evaluate("window.__ids")
            check('first start: no MAC address or device ID read yet', ids == {'duid': 0, 'mac': 0}, ids)
            text = page.evaluate("document.querySelector('.cs-left').innerText")
            check('says what is sent and why', all(x in text for x in ('MAC address', 'device ID', 'IP address', 'playlists', 'deleted')), text)
            check('says what happens without consent', 'cannot receive your playlists' in text, text)
            check('Agree in focus', 'Agree and continue' in focus(page), focus(page))
            btns = page.evaluate("[].slice.call(document.querySelectorAll('.cs-acts .btn')).map(function (b) { return b.textContent; })")
            check('buttons: Agree, Privacy Policy, Exit', len(btns) == 3 and 'Privacy Policy' in btns[1] and 'Exit' in btns[2], btns)
            check('a QR code to the full policy', page.evaluate("!!document.querySelector('.cs-right canvas')") and
                  'ibolite' in page.evaluate("document.querySelector('.cs-right .pp-url').textContent") or
                  '127.0.0.1' in page.evaluate("document.querySelector('.cs-right .pp-url').textContent"),
                  page.evaluate("document.querySelector('.cs-right .pp-url').textContent"))
            page.screenshot(path=os.path.join(tmp, 'consent.png'))

            # the policy from there
            page.evaluate("App.key('right')")
            check('Right: Privacy Policy', 'Privacy Policy' in focus(page), focus(page))
            page.evaluate("App.key('ok')")
            check('Privacy Policy opens', policy_open(page))
            body = page.evaluate("document.querySelector('.pp-text').innerText")
            check('policy: identifiers, reports, TMDB, deleting, children',
                  all(x in body for x in ('MAC address', 'DUID', 'Problem reports', 'TMDB', 'deleted', 'children')), body[:200])
            check('policy: the text is in focus', page.evaluate("F.cur && F.cur.classList.contains('pp-text')"))
            y0 = page.evaluate("document.querySelector('.pp-text').scrollTop")
            page.evaluate("App.key('down')")
            y1 = page.evaluate("document.querySelector('.pp-text').scrollTop")
            check('policy: Down scrolls the text', y1 > y0, [y0, y1])
            for _ in range(30):
                page.evaluate("App.key('down')")
            check('policy: at the end Down goes to Close', 'Close' in focus(page), focus(page))
            check('policy: a QR code to the full policy', page.evaluate("!!document.querySelector('.pp-side canvas')"))
            page.screenshot(path=os.path.join(tmp, 'policy.png'))
            page.evaluate("App.key('ok')")
            check('Close: back on "Before you start"', not page.evaluate("!!UI.topDialog()") and 'Privacy Policy' in focus(page), focus(page))
            check('still nothing sent', not site, site[:3])

            # agree
            page.evaluate("App.key('left'); App.key('ok')")
            check('Agree: the first screen', T.wait_for(page, "Nav.top().name === 'connect'", 10), top(page))
            check('Agree: the TV registers now', any('/device/register' in u for u in site), [u.split('?')[0] for u in site][:5])
            check('Agree: MAC address and device ID read now', page.evaluate("window.__ids.duid > 0 && window.__ids.mac > 0"), page.evaluate("window.__ids"))
            check('Agree: kept', page.evaluate("JSON.parse(localStorage.getItem('lt_privacy_ok'))") == 1)
            check('first screen: a Privacy Policy button', page.evaluate("!!document.querySelector('.cn-pp')"))
            page.evaluate("document.querySelector('.cn-pp')._ok()")
            check('first screen: the policy opens', policy_open(page))
            page.screenshot(path=os.path.join(tmp, 'connect.png'))
            page.evaluate("UI.closeAll()")
            check('no script errors', not errors, '; '.join(errors[:3]))
            page.close()

            # ---------------- the next start: no question
            page, errors, site = open_app(b, fake, keep=ctx)
            check('next start: no question again', top(page) == 'connect', top(page))
            # Settings and Application info
            page.evaluate("Nav.push(new Screens.Settings())")
            T.wait_for(page, "Nav.top().name === 'settings'", 2)
            page.evaluate("App.key('up')")
            check('Settings: Up from the boxes to Privacy Policy', 'Privacy Policy' in focus(page), focus(page))
            page.evaluate("App.key('ok')")
            check('Settings: the policy opens', policy_open(page))
            page.screenshot(path=os.path.join(tmp, 'settings-policy.png'))
            page.evaluate("UI.closeAll()")
            page.evaluate("[].slice.call(document.querySelectorAll('.sbox')).filter(function (b) { return b.querySelector('.lb').textContent === 'Application Info'; })[0]._ok()")
            T.wait_for(page, "!!document.querySelector('.infobox2')", 2)
            info = page.evaluate("[].slice.call(document.querySelectorAll('.dialog .acts .btn')).map(function (b) { return b.textContent; })")
            check('Application info: Privacy Policy and Close', any('Privacy Policy' in x for x in info) and 'Close' in focus(page), [info, focus(page)])
            page.evaluate("[].slice.call(document.querySelectorAll('.dialog .acts .btn'))[0]._ok()")
            check('Application info: the policy opens', policy_open(page))
            page.evaluate("UI.closeAll()")
            check('next start: no script errors', not errors, '; '.join(errors[:3]))
            page.close()
            ctx.close()

            # ---------------- not agreeing: the app closes
            page, errors, site = open_app(b, fake)
            check('fresh TV: the question', top(page) == 'consent', top(page))
            page.evaluate("[].slice.call(document.querySelectorAll('.cs-acts .btn')).pop()._ok()")
            check('Exit: the app closes', page.evaluate("window.__exit") == 1, page.evaluate("window.__exit"))
            check('Exit: nothing sent, nothing read', not site and page.evaluate("window.__ids") == {'duid': 0, 'mac': 0}, [site[:2], page.evaluate("window.__ids")])
            check('Exit: not kept as agreed', page.evaluate("localStorage.getItem('lt_privacy_ok')") is None)
            # Back on the question: the exit question (first screen)
            page.evaluate("App.key('back')")
            check('Back: "Exit IBO Lite Player?"', T.wait_for(page, "/Exit/.test(UI.topDialog() ? UI.topDialog().innerText : '')", 2))
            check('fresh TV: no script errors', not errors, '; '.join(errors[:3]))
            print('screenshots:', tmp)
            b.close()
    finally:
        mock.terminate()
        srv.shutdown()
    print('\n%d failed' % len(T.FAILS))
    sys.exit(1 if T.FAILS else 0)


if __name__ == '__main__':
    main()
