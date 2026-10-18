"""Browser test of the light TV app's TV Guide, reminders and Start Over (not part of the app).

Builds the Samsung variant, serves it next to the mock server with a TV guide (test/mock_guide.py)
and opens it in Chromium with the stand-in for AVPlay. Xtream: the guide from Live TV (the preview
plays on in the guide's window), moving through channels and programmes, a reminder set and
removed, catch-up of a past programme, a channel picked to watch, the guide over the full-screen
player (GUIDE key, Back, picking a channel), Start Over (Rewind), and a reminder that comes due
("Watch now" plays the channel). M3U: the XMLTV guide (packed) in the guide box and the TV Guide.
The built-in demo: its guide. And the XMLTV reader on plain, packed and cut files.

    python3 tvlite/test/guide_test.py             (from the repository root)
"""
import gzip, json, os, re, subprocess, sys, tempfile, time, urllib.request

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avplay_test as T  # noqa: E402
import features_test as FT  # noqa: E402

ROOT = T.ROOT
check = T.check


def guide_state(page):
    return page.evaluate("""(function () {
        var g = document.querySelector('.screen.guide');
        if (!g) return null;
        var sel = g.querySelector('.gr .c.on'), side = g.querySelector('.gr .side.on');
        return {
          title: g.querySelector('.gd-info .t').textContent,
          badges: [].slice.call(g.querySelectorAll('.gd-info .bdg')).map(function (b) { return b.textContent; }),
          sel: sel ? sel.querySelector('b').textContent : null,
          bell: sel ? !!sel.querySelector('.ci.rem') : false,
          rec: sel ? !!sel.querySelector('.ci.rec') : false,
          row: side ? side.querySelector('.nm').textContent : null,
          rows: [].slice.call(g.querySelectorAll('.gr')).filter(function (r) { return r.style.display !== 'none'; }).length,
          cells: g.querySelectorAll('.gr .c[data-s]').length,
          day: g.querySelector('.gd-ruler .day').textContent
        };
    })()""")


def plain(s):
    """Text without the icon glyphs (private-use characters)."""
    return re.sub('[\ue000-\uf8ff\U000f0000-\U000fffff]', '', s or '')


def press(page, label):
    """OK on the live pane button with that label."""
    return page.evaluate("""(l) => { var b = [].slice.call(document.querySelectorAll('.pbtn')).filter(function (x) { return x.textContent.indexOf(l) >= 0; })[0];
        if (!b) return false; F.set(b); b._ok(); return true; }""", label)


def open_live(page):
    page.evaluate("Nav.push(new Screens.Browse(App.src, 'live'))")
    return T.wait_for(page, "document.querySelectorAll('.chrow').length > 0 && !!document.querySelector('.chrow .nm span').textContent", 8)


def main():
    tmp = tempfile.mkdtemp(prefix='tvlite-guide-')
    mock = subprocess.Popen([sys.executable, os.path.join(HERE, 'mock_guide.py'), '8787'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)
    time.sleep(1.5)
    app = T.build('tizen', tmp)
    srv = T.serve(app, FT.PORT)
    fake = open(os.path.join(HERE, 'fake_tizen.js')).read()
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=['--disable-web-security'])
            page, errors = FT.start(b, fake)
            check('home', FT.top(page) == 'home', FT.top(page))

            # ---------------- Live TV: the TV Guide button, the preview goes on in the guide's window
            check('live: channels', open_live(page))
            btns = plain(page.evaluate("[].slice.call(document.querySelectorAll('.pbtn')).map(function (b) { return b.textContent; }).join('|')"))
            check('live: a TV Guide button', btns == 'Full screen|TV Guide|Favourite', btns)
            page.evaluate("document.querySelectorAll('.chrow')[0]._ok()")
            check('live: the first channel plays in the preview', T.wait_for(page, "Player.state() === 'playing' && Player.mode() === 'preview'", 8))
            press(page, 'TV Guide')
            check('guide: opens', T.wait_for(page, "Nav.top().name === 'guide'", 3), FT.top(page))
            check('guide: the preview plays on in its window', page.evaluate("Player.active() && Player.mode() === 'preview'"))
            rect = page.evaluate("(function () { var r = App.rect(document.querySelector('.gd-pv')); return [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)]; })()")
            last = [c for c in page.evaluate('window.__av.calls') if c[0] == 'setDisplayRect'][-1][1:]
            check('guide: the picture is in the window', last == rect, [last, rect])
            check('guide: loads the programmes', T.wait_for(page, "document.querySelectorAll('.screen.guide .gr .c[data-s]').length > 4", 6))
            st = guide_state(page)
            check('guide: the four channels of the category', st['rows'] == 4, st)
            check('guide: starts on the channel in focus, on now', st['row'] == 'Test One FHD' and 'LIVE NOW' in st['badges'], st)
            check('guide: the day', st['day'] == 'Today', st['day'])
            page.screenshot(path=os.path.join(tmp, 'guide.png'))
            print('screenshot:', os.path.join(tmp, 'guide.png'))

            # ---------------- a programme coming up: a reminder
            now_title = st['title']
            page.evaluate("App.key('right')")
            st = guide_state(page)
            check('Right: the next programme (coming up)', st['title'] != now_title and 'COMING UP' in st['badges'], st)
            page.evaluate("App.key('ok')")
            st = guide_state(page)
            check('OK: reminder set', 'REMINDER SET' in st['badges'] and st['bell'] and page.evaluate("App.reminders.all().length") == 1, st)
            check('reminder: kept for the playlist account', page.evaluate("(JSON.parse(localStorage.getItem('lt_reminders')) || []).length") == 1)
            page.evaluate("App.key('ok')")
            st = guide_state(page)
            check('OK again: removed', 'REMINDER SET' not in st['badges'] and not st['bell'] and page.evaluate("App.reminders.all().length") == 0, st)

            # ---------------- a past programme with a recording: catch-up
            for _ in range(3):
                page.evaluate("App.key('left')")
            st = guide_state(page)
            check('Left: a past programme with a recording', 'CATCH UP' in st['badges'] and st['rec'], st)
            page.evaluate("window.__av.calls = []; window.__av.live = false; App.key('ok')")
            check('catch-up: plays the recording', T.wait_for(page, "Nav.top().name === 'player' && Nav.top().kind === 'rec' && Player.state() === 'playing'", 8), FT.top(page))
            check('catch-up: the timeshift address', '/timeshift/demo/demo/' in (page.evaluate("Player.urls()[0]") or ''), page.evaluate("Player.urls()[0]"))
            FT.back_to(page, 'browse-live')
            page.evaluate("window.__av.live = true")
            check('catch-up: Back to Live TV', FT.top(page) == 'browse-live', FT.top(page))

            # ---------------- a channel picked in the guide plays full screen
            press(page, 'TV Guide')
            T.wait_for(page, "Nav.top().name === 'guide'", 3)
            T.wait_for(page, "document.querySelectorAll('.screen.guide .gr .c[data-s]').length > 4", 6)
            page.evaluate("App.key('down')")
            st = guide_state(page)
            check('Down: the next channel', st['row'] == 'Test Two (HLS only)', st)
            T.wait_for(page, "!!document.querySelector('.screen.guide .gd-info .bdg')", 4)
            page.evaluate("App.key('ok')")
            check('OK on now: the channel full screen', T.wait_for(page, "Nav.top().name === 'player' && Nav.top().kind === 'live' && Player.state() === 'playing'", 8), FT.top(page))
            check('the channel is Test Two', T.wait_for(page, "(Player.urls()[0] || '').indexOf('/2.') > 0", 4), page.evaluate("Player.urls()[0]"))

            # ---------------- the guide over the full-screen player
            page.evaluate("App.key('guide')")
            check('GUIDE key: the guide over the player', T.wait_for(page, "Nav.top().name === 'guide'", 3) and page.evaluate("Player.mode() === 'preview'"))
            st = guide_state(page)
            check('guide: on the channel playing', st['row'] == 'Test Two (HLS only)', st)
            page.evaluate("App.key('back')")
            check('Back: full screen again', T.wait_for(page, "Nav.top().name === 'player' && Player.mode() === 'full'", 3) and page.evaluate("document.querySelector('.pscr .osd.show') !== null"))
            labels = page.evaluate("""[].slice.call(document.querySelectorAll('.pscr .btns .rb')).map(function (b) {
                F.set(b); return document.querySelector('.pscr .lbl').textContent; })""")
            check('bar: a TV Guide button', 'TV Guide' in labels, labels)
            check('bar: no Start Over without recordings', not any(l.startswith('Start Over') for l in labels), labels)
            page.evaluate("App.key('rw')")
            check('Rewind without recordings: says why', 'catch-up' in page.evaluate("document.getElementById('toast').textContent"), page.evaluate("document.getElementById('toast').textContent"))
            FT.back_to(page, 'player', 1)
            page.evaluate("App.key('back')")  # the bar goes
            page.evaluate("App.key('info')")
            T.wait_for(page, "Nav.top().name === 'guide'", 3)
            page.evaluate("App.key('up')")
            T.wait_for(page, "!!document.querySelector('.screen.guide .gd-info .bdg')", 4)
            page.evaluate("App.key('ok')")
            check('guide over the player: picking a channel tunes to it', T.wait_for(page, "Nav.top().name === 'player' && (Player.urls()[0] || '').indexOf('/1.') > 0", 6), page.evaluate("Player.urls()[0]"))

            # ---------------- Start Over (channel 1 keeps recordings)
            T.wait_for(page, "Player.state() === 'playing'", 6)
            page.evaluate("App.key('ok')")  # the bar
            T.wait_for(page, "document.querySelector('.pscr .osd.show') !== null", 2)
            labels = page.evaluate("""[].slice.call(document.querySelectorAll('.pscr .btns .rb')).map(function (b) {
                F.set(b); return document.querySelector('.pscr .lbl').textContent; })""")
            check('bar: Start Over on a channel with recordings', any(l.startswith('Start Over') for l in labels), labels)
            FT.back_to(page, 'player', 1)
            page.evaluate("App.key('back')")
            T.wait_for(page, "document.querySelector('.pscr .osd.show') === null", 2)
            T.wait_for(page, "true", 1)
            page.evaluate("window.__av.live = false; App.key('rw')")
            check('Rewind: Start Over plays the programme from its beginning', T.wait_for(page, "Nav.top().kind === 'rec' && Player.state() === 'playing'", 8), FT.top(page))
            want = page.evaluate("""(function () { var t = Date.now(), d = new Date(t - t % 1800000);
                return d.getFullYear() + '-' + U.two(d.getMonth() + 1) + '-' + U.two(d.getDate()) + ':' + U.two(d.getHours()) + '-' + U.two(d.getMinutes()); })()""")
            url = page.evaluate("Player.urls()[0]") or ''
            check('Start Over: from the start of the programme on now', '/timeshift/demo/demo/' in url and want in url, [url, want])
            sub = page.evaluate("Nav.top().el.querySelector('.top .sub').textContent")
            check('Start Over: says so on the bar', 'Start Over' in sub, sub)
            page.evaluate("window.__av.live = true")
            for _ in range(3):  # the recording's bar takes the first Back
                if page.evaluate("Nav.top().kind === 'live'"):
                    break
                page.evaluate("App.key('back')")
                T.wait_for(page, "Nav.top().kind === 'live'", 0.8)
            check('Back: live TV again', T.wait_for(page, "Nav.top().kind === 'live' && Player.state() === 'playing' && (Player.urls()[0] || '').indexOf('/live/') > 0", 8),
                  [FT.top(page), page.evaluate("Player.urls()[0]")])

            # ---------------- a reminder comes due: "Watch now"
            FT.back_to(page, 'home', 6)
            check('back on home', FT.top(page) == 'home', FT.top(page))
            page.evaluate("""App.src.items('live', '1').then(function (l) { window.__two = l[1];
                App.reminders.toggle(l[1], { start: Date.now() + 30000, end: Date.now() + 1800000, title: 'The Big Match' }); })""")
            T.wait_for(page, "App.reminders.all().length === 1", 3)
            page.evaluate("App.reminders.check()")
            check('reminder: the message', T.wait_for(page, "!!document.querySelector('.rmdlg')", 3))
            text = page.evaluate("document.querySelector('.rmdlg').innerText")
            check('reminder: what and where', 'Starting in a minute' in text and 'The Big Match' in text and 'Test Two' in text, text)
            check('reminder: Watch now in focus', page.evaluate("F.cur && F.cur.textContent.indexOf('Watch now') >= 0"))
            check('reminder: done with', page.evaluate("App.reminders.all().length") == 0)
            page.screenshot(path=os.path.join(tmp, 'reminder.png'))
            page.evaluate("F.cur._ok()")
            check('Watch now: the channel plays', T.wait_for(page, "Nav.top().name === 'player' && (Player.urls()[0] || '').indexOf('/2.') > 0", 8), page.evaluate("Player.urls()[0]"))
            check('Watch now: with its category (Up / Down)', page.evaluate("Nav.top().channel().n") == 'Test Two (HLS only)')
            FT.back_to(page, 'home', 4)
            check('Xtream: no script errors', not errors, '; '.join(errors[:3]))
            page.close()

            # ---------------- M3U with an XMLTV guide (packed)
            page = b.new_page(viewport={'width': 1920, 'height': 1080})
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            sess = {'mode': 'm3u', 'url': 'http://127.0.0.1:8787/guide.m3u', 'epg': '', 'pid': 0, 'pname': 'M3U', 'psig': ''}
            page.add_init_script("try { localStorage.setItem('lt_session', %s); localStorage.setItem('lt_samsung_player', JSON.stringify('avplay')); } catch (e) {}\n%s"
                                 % (json.dumps(json.dumps(sess)), fake))
            page.goto('http://127.0.0.1:%d/index.html' % FT.PORT)
            T.wait_for(page, "!document.getElementById('intro') && !!(window.Nav && Nav.top())", 15)
            check('M3U: home', FT.top(page) == 'home', FT.top(page))
            check('M3U: Live TV', open_live(page))
            page.evaluate("F.set(document.querySelectorAll('.chrow')[0])")
            check('M3U: the guide box shows the XMLTV guide', T.wait_for(page, "/XML Chone show/.test(document.querySelector('.epg .now') ? document.querySelector('.epg .now').textContent : '')", 10),
                  page.evaluate("document.querySelector('.epg').innerText"))
            check('M3U: names decoded', '&' in page.evaluate("document.querySelector('.epg .now').textContent") and '&amp;' not in page.evaluate("document.querySelector('.epg .now').textContent"))
            press(page, 'TV Guide')
            T.wait_for(page, "Nav.top().name === 'guide'", 3)
            check('M3U guide: programmes', T.wait_for(page, "document.querySelectorAll('.screen.guide .gr .c[data-s]').length > 3", 6))
            st = guide_state(page)
            check('M3U guide: on now', 'LIVE NOW' in st['badges'] and st['title'].startswith('XML Chone show'), st)
            for _ in range(2):
                page.evaluate("App.key('left')")
            st = guide_state(page)
            check('M3U guide: past programmes have no catch-up', 'CATCH UP' not in st['badges'] and not st['rec'], st)
            page.evaluate("App.key('ok')")
            check('M3U guide: says there is no recording', 'no recording' in page.evaluate("document.getElementById('toast').textContent"))
            check('M3U guide: still open', FT.top(page) == 'guide')
            log = page.evaluate("App.logText ? App.logText() : ''")
            check('M3U: read in the background worker', 'no background worker' not in log and 'XMLTV not read' not in log, [l for l in log.split('\n') if 'guide' in l][-3:])

            # ---------------- the XMLTV reader on its own: plain, packed, cut
            xml = urllib.request.urlopen('http://127.0.0.1:8787/epg.xml').read()
            gz = gzip.compress(xml)
            res = page.evaluate("""(a) => Promise.all(a.map(function (x) { return XMLTV.read(new Uint8Array(x), ['one', 'TWO']).then(function (r) {
                return [Object.keys(r.guide).sort().join(','), (r.guide.one || []).length, r.stats.packed]; }, function (e) { return ['error', e.message]; }); }))""",
                                [list(xml), list(gz), list(gz[:len(gz) * 2 // 3])])
            check('XMLTV: plain', res[0][0] == 'TWO,one' and res[0][1] > 30 and not res[0][2], res[0])
            check('XMLTV: packed, the same', res[1][:2] == res[0][:2] and res[1][2], res[1])
            check('XMLTV: a cut file gives what arrived', res[2][0] != 'error' and 0 < res[2][1] <= res[0][1], res[2])
            check('M3U: no script errors', not errors, '; '.join(errors[:3]))
            page.close()

            # ---------------- the built-in demo
            page = b.new_page(viewport={'width': 1920, 'height': 1080})
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.add_init_script("try { localStorage.setItem('lt_session', JSON.stringify({mode: 'demo'})); } catch (e) {}")
            page.goto('http://127.0.0.1:%d/index.html' % FT.PORT)
            T.wait_for(page, "!document.getElementById('intro') && !!(window.Nav && Nav.top())", 15)
            open_live(page)
            press(page, 'TV Guide')
            T.wait_for(page, "Nav.top().name === 'guide'", 3)
            check('demo guide: programmes', T.wait_for(page, "document.querySelectorAll('.screen.guide .gr .c[data-s]').length > 3", 4))
            st = guide_state(page)
            check('demo guide: on now', 'LIVE NOW' in st['badges'], st)
            page.evaluate("App.key('play')")
            check('demo: no script errors', not errors, '; '.join(errors[:3]))
            b.close()
    finally:
        mock.terminate()
        srv.shutdown()
    print('\n%d failed' % len(T.FAILS))
    sys.exit(1 if T.FAILS else 0)


if __name__ == '__main__':
    main()
