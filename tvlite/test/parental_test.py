"""Browser test of the light TV app's category settings and problem reports (not part of the app).

Builds the Samsung variant, serves it next to the mock website (ci/mock_server.py) and opens it in
Chromium, signed in to the mock's Xtream account. Checks: Settings → Manage categories (a hidden
category is gone from the lists and from All), Parental control (locking asks for a new PIN first;
a locked category shows a padlock, does not open by itself, opens after the PIN, and its channels
stay out of All until then), and Report a problem (what it sends: the reason, the TV, the last
stream and the log, never a password or a stream address).

    python3 tvlite/test/parental_test.py          (from the repository root)
"""
import json, os, subprocess, sys, tempfile, time

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avplay_test as T  # noqa: E402
import features_test as FT  # noqa: E402
import profiles_test as PR  # noqa: E402

ROOT = T.ROOT
STRIP = "replace(/[\\uE000-\\uF8FF]|[\\uDB80-\\uDBFF][\\uDC00-\\uDFFF]/g, '').trim()"


def cat_rows(page, sel):
    return page.evaluate("[].slice.call(document.querySelectorAll('%s')).filter(function (r) { return r.style.display !== 'none'; })"
                         ".map(function (r) { return r.textContent.%s; })" % (sel, STRIP))


def open_settings_row(page, label):
    page.evaluate("""(l) => { var r = [].slice.call(document.querySelectorAll('.srow')).filter(function (x) {
        return x.querySelector('.lb').textContent === l; })[0]; F.set(r); r._ok(); }""", label)


def click_choice(page, name):
    page.evaluate("""(n) => { var r = [].slice.call(document.querySelectorAll('.kcrow')).filter(function (x) {
        return x.style.display !== 'none' && x.querySelector('.nm').textContent === n; })[0]; F.set(r); r._ok(); }""", name)


def browse_live(page):
    page.evaluate("Nav.push(new Screens.Browse(App.src, 'live'))")
    T.wait_for(page, "Nav.top().name === 'browse-live' && !document.querySelector('.content .pulse')", 6)
    time.sleep(0.8)


def main():
    tmp = tempfile.mkdtemp(prefix='tvlite-parental-')
    mock = subprocess.Popen([sys.executable, os.path.join(ROOT, 'ci/mock_server.py'), '8787'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)
    time.sleep(1.5)
    app = T.build('tizen', tmp)
    srv = T.serve(app, FT.PORT)
    fake = open(os.path.join(HERE, 'fake_tizen.js')).read()
    check = T.check
    sent = []

    def report(route):
        sent.append(json.loads(route.request.post_data or '{}'))
        route.fulfill(status=200, content_type='application/json', body=json.dumps({'success': True, 'report_id': 42}))
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=['--disable-web-security'])
            ctx = b.new_context(viewport={'width': 1920, 'height': 1080})
            ctx.route('**/device/report', report)
            page = ctx.new_page()
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.add_init_script("try { localStorage.setItem('lt_session', %s); } catch (e) {}\n%s" % (json.dumps(json.dumps(FT.SESSION)), fake))
            page.goto('http://127.0.0.1:%d/index.html' % FT.PORT)
            T.wait_for(page, "!document.getElementById('intro') && !!(window.Nav && Nav.top())", 15)

            # ---------------- Manage categories: hide Sports
            page.evaluate("Nav.push(new Screens.Settings())")
            open_settings_row(page, 'Manage categories')
            check('Manage categories: opens', T.wait_for(page, "Nav.top().name === 'hide-categories' && document.querySelectorAll('.kcrow .nm').length > 1", 5), FT.top(page))
            click_choice(page, 'Sports')
            check('Manage categories: Sports hidden', page.evaluate("Store.isHiddenSetting('live', '2')") is True)
            check('Manage categories: says so', 'hidden' in ' '.join(cat_rows(page, '.kcrow')), cat_rows(page, '.kcrow'))
            FT.back_to(page, 'home')
            browse_live(page)
            cats = cat_rows(page, '.cats .crow')
            check('hidden: not in the categories', not any(c.startswith('Sports') for c in cats), cats)
            page.evaluate("[].slice.call(document.querySelectorAll('.cats .crow')).filter(function (r) { return /All Live/.test(r.textContent); })[0]._ok()")
            time.sleep(0.8)
            chans = cat_rows(page, '.chrow')
            check('hidden: its channels not in All', chans and not any('Sports One' in c for c in chans), chans)
            FT.back_to(page, 'home')
            page.evaluate("Store.setHidden('live', '2', false)")

            # ---------------- Parental control: lock UK Entertainment (a PIN is made first)
            page.evaluate("Nav.push(new Screens.Settings())")
            open_settings_row(page, 'Parental control')
            T.wait_for(page, "Nav.top().name === 'lock-categories' && document.querySelectorAll('.kcrow .nm').length > 1", 5)
            click_choice(page, 'UK Entertainment')
            check('lock: asks for a new PIN first', T.wait_for(page, "!!UI.topDialog() && /Set a parental PIN/.test(UI.topDialog().innerText)", 3))
            PR.type_in(page, '2468')
            T.wait_for(page, "!!UI.topDialog() && /again/i.test(UI.topDialog().innerText)", 3)
            PR.type_in(page, '2468')
            check('lock: PIN saved and the category locked', T.wait_for(page, "!UI.topDialog() && Store.isLocked('live', '1')", 3))
            check('lock: shows "locked"', any('UK Entertainment' in r and 'locked' in r for r in cat_rows(page, '.kcrow')), cat_rows(page, '.kcrow'))
            check('lock: the count says ON', 'Parental control is ON' in page.evaluate("document.querySelector('.br-title .c').textContent"))
            FT.back_to(page, 'home')
            page.evaluate("Store.parentalUnlocked = false")
            browse_live(page)
            check('locked: padlock on the category', page.evaluate("[].slice.call(document.querySelectorAll('.cats .crow')).some(function (r) { return /UK Entertainment/.test(r.textContent) && !!r.querySelector('.lk'); })"))
            title = page.evaluate("document.querySelector('.br-title .t').textContent")
            check('locked: the list does not start in it', title == 'Sports', title)
            page.evaluate("[].slice.call(document.querySelectorAll('.cats .crow')).filter(function (r) { return /All Live/.test(r.textContent); })[0]._ok()")
            time.sleep(0.8)
            chans = cat_rows(page, '.chrow')
            check('locked: its channels not in All', chans and not any('Test One' in c for c in chans), chans)
            page.evaluate("var r = [].slice.call(document.querySelectorAll('.cats .crow')).filter(function (x) { return /UK Entertainment/.test(x.textContent); })[0]; F.set(r); r._ok()")
            check('locked: OK asks for the PIN', T.wait_for(page, "!!UI.topDialog() && !!UI.topDialog().querySelector('input[type=password]')", 3))
            PR.type_in(page, '2468')
            T.wait_for(page, "/UK Entertainment/.test(document.querySelector('.br-title .t').textContent)", 4)
            time.sleep(0.6)
            chans = cat_rows(page, '.chrow')
            check('locked: opens after the PIN', any('Test One FHD' in c for c in chans), chans)
            check('unlocked: no padlock any more', not page.evaluate("!!document.querySelector('.cats .crow .lk')"))
            FT.back_to(page, 'home')

            # ---------------- Report a problem
            page.evaluate("Player.open(['http://127.0.0.1:8787/live/demo/demo/1.ts'], {live: true})")
            T.wait_for(page, "Player.state() === 'playing'", 6)
            page.evaluate("Player.stop()")
            page.evaluate("Nav.push(new Screens.Settings())")
            open_settings_row(page, 'Report a problem')
            check('report: the window', T.wait_for(page, "!!UI.topDialog() && UI.topDialog().querySelectorAll('.chip').length === 7", 3))
            PR.press(page, 'Send')
            check('report: asks what went wrong first', 'Choose what went wrong' in page.evaluate("UI.topDialog().querySelector('.pinerr').textContent"))
            page.evaluate("UI.topDialog().querySelectorAll('.chip')[1]._ok(); UI.topDialog().querySelector('input').value = 'Freezes at 9 pm'")
            PR.press(page, 'Send')
            check('report: sent, number shown', T.wait_for(page, "!!UI.topDialog() && /report number is 42/.test(UI.topDialog().innerText)", 6), page.evaluate("UI.topDialog() && UI.topDialog().innerText"))
            r = sent[0] if sent else {}
            check('report: reason and note', r.get('reason') == 'Picture freezes or buffers' and r.get('note') == 'Freezes at 9 pm', r.get('reason'))
            check('report: the TV and the app', r.get('platform') == 'samsung-tv' and r.get('device_id') and r.get('pairing_code') and '2.0.999' in r.get('app_version', ''), [r.get('platform'), r.get('app_version')])
            check('report: the last stream (no address)', r.get('stream', {}).get('what') == 'live 1.ts', r.get('stream'))
            check('report: the server is only its host', r.get('server') == '127.0.0.1:8787', r.get('server'))
            body = json.dumps(r)
            check('report: no password, no stream address', '/live/demo/demo/' not in body and '"pass"' not in body and 'password' not in body.lower().replace('no password is sent', ''))
            check('report: the log', 'report send' in r.get('log', ''), len(r.get('log', '')))
            PR.press(page, 'OK')
            open_settings_row(page, 'Report a problem')
            T.wait_for(page, "!!UI.topDialog()", 2)
            page.evaluate("UI.topDialog().querySelectorAll('.chip')[0]._ok()")
            PR.press(page, 'Send')
            check('report: not twice in a minute', 'wait a minute' in page.evaluate("UI.topDialog().querySelector('.pinerr').textContent") and len(sent) == 1)
            check('no script errors', not errors, '; '.join(errors[:3]))
            b.close()
    finally:
        mock.terminate()
        srv.shutdown()
    print('\n%d failed' % len(T.FAILS))
    sys.exit(1 if T.FAILS else 0)


if __name__ == '__main__':
    main()
