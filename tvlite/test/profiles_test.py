"""Browser test of the light TV app's profiles and Kids profile (not part of the app).

Builds the Samsung variant, serves it next to the mock website (ci/mock_server.py) and opens it in
Chromium (stand-in AVPlay, the mock's Xtream account). Checks: "Who's watching?" from the home
screen, adding a Kids profile with a parental PIN, the Kids home screen (no playlist change, no Catch
Up), only children's categories in Live TV (none by name in the mock, then one chosen by hand in
Kids categories), the PIN to leave the Kids profile and to open Settings there, every profile's own
favourites, "Who's watching?" when the app starts, and deleting a profile with its lists.

    python3 tvlite/test/profiles_test.py          (from the repository root)
"""
import json, os, subprocess, sys, tempfile, time

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avplay_test as T  # noqa: E402
import features_test as FT  # noqa: E402

ROOT = T.ROOT


def dialog_buttons(page):
    return page.evaluate("UI.topDialog() ? [].slice.call(UI.topDialog().querySelectorAll('.btn')).map(function (b) { return b.innerText.trim(); }) : null")


def press(page, label):
    """Presses the dialog button with this label."""
    return page.evaluate("""(label) => { var d = UI.topDialog(); if (!d) return false;
        var b = [].slice.call(d.querySelectorAll('.btn')).filter(function (x) {
          return x.textContent.replace(/[\uE000-\uF8FF]|[\uDB80-\uDBFF][\uDC00-\uDFFF]/g, '').trim() === label; })[0];
        if (!b) return false; F.set(b); b._ok(); return true; }""", label)


def type_in(page, text):
    """Types into the field of the dialog on top (as the TV's keyboard would)."""
    return page.evaluate("""(t) => { var d = UI.topDialog(); var i = d && d.querySelector('input'); if (!i) return false;
        i.value = t; if (i._submit) i._submit(); return true; }""", text)


def tiles(page):
    return page.evaluate("[].slice.call(document.querySelectorAll('.pft')).map(function (t) { return t.innerText.replace(/\\s+/g, ' ').trim(); })")


def main():
    tmp = tempfile.mkdtemp(prefix='tvlite-profiles-')
    mock = subprocess.Popen([sys.executable, os.path.join(ROOT, 'ci/mock_server.py'), '8787'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)
    time.sleep(1.5)
    app = T.build('tizen', tmp)
    srv = T.serve(app, FT.PORT)
    fake = open(os.path.join(HERE, 'fake_tizen.js')).read()
    check = T.check
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=['--disable-web-security'])
            page, errors = FT.start(b, fake)
            check('home: profile button', page.evaluate("!!document.querySelector('.pill.prof .avatar')"))
            # a favourite of the main profile
            page.evaluate("Store.toggleFav({k: 'live', id: '1', n: 'Test One FHD', i: '', c: '1'})")

            # ---------------- Who's watching? from the home screen
            page.evaluate("document.querySelector('.pill.prof')._ok()")
            check("profiles: Who's watching? opens", T.wait_for(page, "Nav.top().name === 'profiles'", 4), FT.top(page))
            check('profiles: Main and Add profile', tiles(page) == ['M Main In use', '+ Add profile'], tiles(page))

            # add a Kids profile
            page.evaluate("[].slice.call(document.querySelectorAll('.pft')).filter(function (t) { return t._pid === '+'; })[0]._ok()")
            check('add: the profile window', T.wait_for(page, "!!UI.topDialog() && !!UI.topDialog().querySelector('.pfdots')", 3), dialog_buttons(page))
            page.evaluate("UI.topDialog().querySelector('input').value = 'Ali'; UI.topDialog().querySelector('.pfkids')._ok();"
                          "UI.topDialog().querySelectorAll('.pfdot')[2]._ok()")
            press(page, 'Add')
            check('add: offers a parental PIN for Kids', T.wait_for(page, "!!UI.topDialog() && /parental PIN/i.test(UI.topDialog().innerText)", 3), dialog_buttons(page))
            press(page, 'Set PIN')
            T.wait_for(page, "!!UI.topDialog() && !!UI.topDialog().querySelector('input')", 3)
            type_in(page, '12')
            check('PIN: too short is refused', T.wait_for(page, "/4 to 8 digits/.test(UI.topDialog().querySelector('.pinerr').textContent)", 2))
            type_in(page, '1234')
            T.wait_for(page, "!!UI.topDialog() && /again/i.test(UI.topDialog().innerText)", 3)
            type_in(page, '1234')
            check('PIN: saved', T.wait_for(page, "!UI.topDialog() && JSON.parse(localStorage.getItem('lt_parental_pin')) === '1234'", 3))
            check('profiles: Ali (Kids) added', tiles(page)[:2] == ['M Main In use', 'Ali Kids'], tiles(page))
            saved = page.evaluate("JSON.parse(localStorage.getItem('lt_profiles'))")
            ali = [x for x in saved if x['n'] == 'Ali']
            check('profiles: saved with colour and Kids', len(ali) == 1 and ali[0]['c'] == 2 and ali[0].get('k') == 1, saved)

            # ---------------- the Kids profile
            page.evaluate("[].slice.call(document.querySelectorAll('.pft')).filter(function (t) { return /Ali/.test(t.innerText); })[0]._ok()")
            check('Kids: home screen', T.wait_for(page, "Nav.top().name === 'home' && Nav.top().el.classList.contains('kids')", 4), FT.top(page))
            names = page.evaluate("[].slice.call(document.querySelectorAll('.tile .tt')).map(function (t) { return t.textContent; })")
            check('Kids: no Catch Up tile', names == ['Live TV', 'Movies', 'TV Series'], names)
            check('Kids: no playlist pill', page.evaluate("[].slice.call(document.querySelectorAll('.pill .pl')).map(function (p) { return p.textContent; }).join(',')") == 'Settings')
            check("Kids: the main profile's favourites are not here", page.evaluate("Store.favs('live').length") == 0)
            page.evaluate("Nav.push(new Screens.Browse(App.src, 'live'))")
            T.wait_for(page, "Nav.top().name === 'browse-live' && document.querySelectorAll('.crow').length > 0 && !document.querySelector('.content .pulse')", 6)
            time.sleep(0.8)
            cats = page.evaluate("[].slice.call(document.querySelectorAll('.cats .crow')).filter(function (r) { return r.style.display !== 'none'; }).map(function (r) { return r.innerText.trim(); })")
            check('Kids: no category for children by name in the mock', not any(c in ('UK Entertainment', 'Sports') for c in cats), cats)
            empty = page.evaluate("(document.querySelector('.empty') || {}).innerText || ''")
            check('Kids: says how to choose categories', 'Kids categories' in empty, empty)
            FT.back_to(page, 'home')

            # Settings in the Kids profile asks for the PIN
            page.evaluate("[].slice.call(document.querySelectorAll('.pill')).filter(function (p) { return /Settings/.test(p.innerText); })[0]._ok()")
            check('Kids: Settings asks for the PIN', T.wait_for(page, "!!UI.topDialog() && !!UI.topDialog().querySelector('input[type=password]')", 3))
            type_in(page, '9999')
            check('PIN: wrong one refused', T.wait_for(page, "/Wrong PIN/.test(UI.topDialog().querySelector('.pinerr').textContent)", 2))
            type_in(page, '1234')
            check('PIN: right one opens Settings', T.wait_for(page, "Nav.top().name === 'settings'", 3), FT.top(page))
            rows = page.evaluate("[].slice.call(document.querySelectorAll('.srow .lb')).map(function (r) { return r.textContent; })")
            check('Settings: Profiles and Parental control rows', 'Profiles' in rows and 'Parental control' in rows, rows)
            # the last row can be reached: the list moves
            page.evaluate("var r = document.querySelectorAll('.srow'); F.set(r[r.length - 1])")
            time.sleep(0.5)
            bottom = page.evaluate("document.querySelectorAll('.srow')[document.querySelectorAll('.srow').length - 1].getBoundingClientRect().bottom")
            check('Settings: the last row comes into view', bottom <= 1080, bottom)
            FT.back_to(page, 'home')

            # a parent ticks "Sports" in Kids categories
            page.evaluate("Nav.push(new Screens.KidsCats(App.src))")
            check('Kids categories: lists the categories', T.wait_for(page, "document.querySelectorAll('.kcrow').length > 0 && [].slice.call(document.querySelectorAll('.kcrow')).some(function (r) { return /Sports/.test(r.innerText); })", 5))
            page.evaluate("[].slice.call(document.querySelectorAll('.kcrow')).filter(function (r) { return /Sports/.test(r.innerText); })[0]._ok()")
            check('Kids categories: ticked by hand', page.evaluate("Store.kidsChoice('live', '2')") is True)
            FT.back_to(page, 'home')
            page.evaluate("Nav.push(new Screens.Browse(App.src, 'live'))")
            T.wait_for(page, "Nav.top().name === 'browse-live' && document.querySelectorAll('.chrow').length > 0", 6)
            time.sleep(0.8)
            cats = page.evaluate("[].slice.call(document.querySelectorAll('.cats .crow')).filter(function (r) { return r.style.display !== 'none'; }).map(function (r) { return r.innerText.trim(); })")
            check('Kids: now only Sports', any('Sports' in c for c in cats) and not any('UK Entertainment' in c for c in cats), cats)
            chans = page.evaluate("[].slice.call(document.querySelectorAll('.chrow')).filter(function (r) { return r.style.display !== 'none'; }).map(function (r) { return r.innerText.trim(); })")
            check('Kids: only its channels', any('Sports One' in c for c in chans) and not any('Test One' in c for c in chans), chans)
            FT.back_to(page, 'home')

            # leaving the Kids profile needs the PIN
            page.evaluate("Store.parentalUnlocked = false; document.querySelector('.pill.prof')._ok()")
            T.wait_for(page, "Nav.top().name === 'profiles'", 3)
            page.evaluate("[].slice.call(document.querySelectorAll('.pft')).filter(function (t) { return /Main/.test(t.innerText); })[0]._ok()")
            check('leaving Kids: asks for the PIN', T.wait_for(page, "!!UI.topDialog() && !!UI.topDialog().querySelector('input[type=password]')", 3))
            type_in(page, '1234')
            check('leaving Kids: back to Main', T.wait_for(page, "Nav.top().name === 'home' && !Nav.top().el.classList.contains('kids')", 4), FT.top(page))
            check("Main: its favourites are back", page.evaluate("Store.favs('live').length") == 1)
            check('no script errors', not errors, '; '.join(errors[:3]))
            page.close()

            # ---------------- Who's watching? when the app starts (2 profiles, ask on)
            page, errors = FT.start(b, fake, "try { localStorage.setItem('lt_profiles', %s); localStorage.setItem('lt_parental_pin', '\"1234\"'); } catch (e) {}"
                                    % json.dumps(json.dumps([{'id': 'pk', 'n': 'Ali', 'c': 2, 'k': 1}])))
            check("start: Who's watching? first", FT.top(page) == 'profiles', FT.top(page))
            page.evaluate("App.key('back')")
            check('start: Back goes on with the profile used last', T.wait_for(page, "Nav.top().name === 'home'", 4), FT.top(page))
            # delete the Kids profile (its lists go too)
            page.evaluate("localStorage.setItem('lt_p_pk_fav_live', '[]'); document.querySelector('.pill.prof')._ok()")
            T.wait_for(page, "Nav.top().name === 'profiles'", 3)
            page.evaluate("[].slice.call(document.querySelectorAll('.pft')).filter(function (t) { return /Ali/.test(t.innerText); })[0]._long()")
            T.wait_for(page, "!!UI.topDialog() && !!UI.topDialog().querySelector('.pfdots')", 3)
            press(page, 'Delete')
            T.wait_for(page, "!!UI.topDialog() && /Delete \"Ali\"/.test(UI.topDialog().innerText)", 3)
            press(page, 'Delete')
            check('delete: the profile goes', T.wait_for(page, "document.querySelectorAll('.pft').length === 2", 3), tiles(page))
            check('delete: its lists go too', page.evaluate("localStorage.getItem('lt_p_pk_fav_live')") is None)
            check('start test: no script errors', not errors, '; '.join(errors[:3]))
            b.close()
    finally:
        mock.terminate()
        srv.shutdown()
    print('\n%d failed' % len(T.FAILS))
    sys.exit(1 if T.FAILS else 0)


if __name__ == '__main__':
    main()
