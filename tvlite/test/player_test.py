"""Browser test of the light TV app's full-screen player options (not part of the app).

Builds the Samsung variant, serves it next to the mock website (ci/mock_server.py) and opens it in
Chromium. With the stand-in for AVPlay: "Last channel" (the bar button, PRE-CH and Fast-forward,
back and forth), the options panel (sound, picture, sleep timer; the arrows stay inside it, Left
closes it), Picture Fit / Stretch reaching AVPlay, and the sleep timer stopping the video and going
back to the home screen. With the standard player: Fit / Fill / Stretch on the <video> element
and the speed of a film.

    python3 tvlite/test/player_test.py            (from the repository root)
"""
import json, os, subprocess, sys, tempfile, time

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avplay_test as T  # noqa: E402
import features_test as FT  # noqa: E402

ROOT = T.ROOT


def playing_id(page):
    """The stream id now open (…/live/demo/demo/<id>.ts)."""
    return page.evaluate("(Player.urls()[0] || '').split('/').pop().split('.')[0]")


def open_live(page):
    page.evaluate("""App.src.items('live', '1').then(function (l) { window.__ch = l;
        Nav.push(new Screens.Player({ src: App.src, kind: 'live', items: l, index: 0, title: 'UK Entertainment',
          onClose: function () { Player.stop(); Player.layout('off'); } })); })""")
    T.wait_for(page, "Nav.top().name === 'player' && Player.state() === 'playing'", 8)


def main():
    tmp = tempfile.mkdtemp(prefix='tvlite-player-')
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
            open_live(page)
            check('live: plays the first channel', playing_id(page) == '1', playing_id(page))

            # ---------------- Last channel
            page.evaluate("App.key('last')")
            check('last channel: none yet (stays)', playing_id(page) == '1')
            page.evaluate("App.key('up')")
            T.wait_for(page, "(Player.urls()[0] || '').indexOf('/2.') > 0", 3)
            check('zap: the second channel', playing_id(page) == '2', playing_id(page))
            page.evaluate("App.key('last')")
            T.wait_for(page, "(Player.urls()[0] || '').indexOf('/1.') > 0", 3)
            check('PRE-CH: back to the channel before', playing_id(page) == '1', playing_id(page))
            page.evaluate("App.key('ff')")
            T.wait_for(page, "(Player.urls()[0] || '').indexOf('/2.') > 0", 3)
            check('Fast-forward: and back again', playing_id(page) == '2', playing_id(page))
            page.evaluate("App.key('ok')")  # the bar
            T.wait_for(page, "document.querySelector('.pscr .osd.show') !== null", 2)
            icons = page.evaluate("[].slice.call(document.querySelectorAll('.pscr .btns .rb')).length")
            labels = []
            for i in range(icons):
                labels.append(page.evaluate("(i) => { var b = document.querySelectorAll('.pscr .btns .rb')[i]; F.set(b); return document.querySelector('.pscr .lbl').textContent; }", i))
            check('bar: Last channel button with its name', any(l.startswith('Last channel (Test One FHD)') for l in labels), labels)
            check('bar: Picture button', any(l.startswith('Picture: Fit') for l in labels), labels)
            FT.back_to(page, 'player', 1)
            page.evaluate("App.key('back')")  # hides the bar
            T.wait_for(page, "document.querySelector('.pscr .osd.show') === null", 2)

            # ---------------- the options panel (Right on a live channel)
            page.evaluate("App.key('right')")
            check('options: opens on the right', T.wait_for(page, "!!document.querySelector('.optlist')", 2))
            heads = page.evaluate("[].slice.call(document.querySelectorAll('.optlist h3')).map(function (h) { return h.textContent; })")
            check('options: Sound, Picture, Sleep timer, Help', heads == ['Sound', 'Picture', 'Sleep timer', 'Help'], heads)
            check('options: Report a problem under Help', page.evaluate("[].slice.call(document.querySelectorAll('.optlist .opt')).some(function (o) { return /Report a problem/.test(o.textContent); })"))
            check('options: no speed for a live channel', 'Speed' not in heads)
            # Down from the sound tracks reaches the picture chips; Right moves along them
            page.evaluate("var o = [].slice.call(document.querySelectorAll('.optlist .opt')).filter(function (x) { return !/Report a problem/.test(x.textContent); }); F.set(o[o.length - 1]); App.key('down')")
            check('options: Down reaches the picture choices', page.evaluate("F.cur && F.cur.classList.contains('chip') && F.cur.textContent === 'Fit'"),
                  page.evaluate("F.cur && F.cur.textContent"))
            page.evaluate("App.key('right')")
            check('options: Right moves along (AVPlay: Fit, Stretch)', page.evaluate("F.cur.textContent") == 'Stretch', page.evaluate("F.cur.textContent"))
            page.evaluate("window.__av.calls = []; App.key('ok')")
            methods = [c[1] for c in page.evaluate('window.__av.calls') if c[0] == 'setDisplayMethod']
            check('Stretch: AVPlay fills the screen', 'PLAYER_DISPLAY_MODE_FULL_SCREEN' in methods, methods)
            check('Stretch: kept for next time', page.evaluate("JSON.parse(localStorage.getItem('lt_picture_fit'))") == 'stretch')
            check('options: still open after a choice', page.evaluate("!!document.querySelector('.optlist')"))
            # the sleep timer: 15 min
            page.evaluate("App.key('down')")
            check('options: Down reaches the sleep timer', page.evaluate("F.cur.textContent") in ('Off', '15 min'), page.evaluate("F.cur.textContent"))
            page.evaluate("F.set([].slice.call(document.querySelectorAll('.optlist .chip')).filter(function (c) { return c.textContent === '15 min'; })[0]); App.key('ok')")
            mins = page.evaluate("App.sleep.mins")
            note = page.evaluate("document.querySelectorAll('.optlist .pnote')[0].textContent")
            check('sleep timer: 15 min set, says when it stops', mins == 15 and note.startswith('Stops at'), [mins, note])
            page.evaluate("F.set(document.querySelector('.optlist .chip')); App.key('left')")
            check('options: Left at the edge closes it', page.evaluate("!document.querySelector('.optlist')"))
            # The time is up (a short time for the test): the video stops, back on the home screen.
            page.evaluate("App.sleep.set(0.02)")
            check('sleep timer: the video stops', T.wait_for(page, "!Player.active()", 4))
            check('sleep timer: back on the home screen', T.wait_for(page, "Nav.top().name === 'home'", 3), FT.top(page))
            check('sleep timer: off again', page.evaluate("App.sleep.mins") == 0)
            check('no script errors', not errors, '; '.join(errors[:3]))
            page.close()

            # ---------------- the standard player (<video>): Fill, and a film's speed
            page = b.new_page(viewport={'width': 1920, 'height': 1080})
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.add_init_script("try { localStorage.setItem('lt_session', %s); } catch (e) {}" % json.dumps(json.dumps(FT.SESSION)))
            page.goto('http://127.0.0.1:%d/index.html' % FT.PORT)
            T.wait_for(page, "!document.getElementById('intro') && !!(window.Nav && Nav.top())", 15)
            check('standard player: Fit, Fill and Stretch', page.evaluate("Player.fits().join(',')") == 'fit,fill,stretch')
            page.evaluate("Player.layout('full'); Player.setFit('fill')")
            check('Fill: the picture covers the screen', page.evaluate("document.getElementById('vid').style.objectFit") == 'cover')
            page.evaluate("Player.layout('preview', {left: 100, top: 100, width: 640, height: 360})")
            check('preview: always the whole picture', page.evaluate("document.getElementById('vid').style.objectFit") == 'contain')
            page.evaluate("Player.layout('full'); Player.open(['http://127.0.0.1:8787/movie/demo/demo/10.mp4'], {live: false})")
            check('film: speeds offered', page.evaluate("Player.speeds().join(',')") == '0.5,0.75,1,1.25,1.5,2')
            page.evaluate("Player.setSpeed(1.5)")
            check('film: 1.5x', page.evaluate("document.getElementById('vid').playbackRate") == 1.5)
            page.evaluate("Player.open(['http://127.0.0.1:8787/movie/demo/demo/12.mp4'], {live: false})")
            check('next film: normal speed again', page.evaluate("Player.speed()") == 1)
            page.evaluate("Player.stop(); Player.setFit('fit')")
            check('standard player: no script errors', not errors, '; '.join(errors[:3]))
            b.close()
    finally:
        mock.terminate()
        srv.shutdown()
    print('\n%d failed' % len(T.FAILS))
    sys.exit(1 if T.FAILS else 0)


if __name__ == '__main__':
    main()
