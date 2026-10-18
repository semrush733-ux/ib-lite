"""Browser test of the Samsung app's Automatic video player (not part of the app).

Builds the Samsung variant, serves it next to the mock server (ci/mock_server.py) and opens it in
Chromium with the stand-in for AVPlay, with no player chosen in Settings (Automatic). Chromium's
<video> cannot play HLS or MPEG-TS, like a TV's standard player that cannot play a stream: the app
must go on to Samsung's AVPlay by itself, in the preview and full screen, and remember it. A film
the standard player can play stays on it (AVPlay let go, the page not see-through); one it cannot
play goes to AVPlay. Settings › VOD Player offers Automatic, Standard and AVPlay.

    python3 tvlite/test/engine_test.py            (from the repository root)
"""
import json, os, subprocess, sys, tempfile, time

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avplay_test as T  # noqa: E402
import features_test as FT  # noqa: E402

ROOT = T.ROOT
check = T.check


def state(page):
    return page.evaluate("""({ engine: Player.engine, state: Player.state(), url: (Player.urls()[0] || '').split('/').pop(),
        avp: document.documentElement.classList.contains('avp-on'), vidHidden: document.getElementById('vid').classList.contains('hide'),
        vidSrc: !!document.getElementById('vid').getAttribute('src'), avState: window.__av.state })""")


def main():
    tmp = tempfile.mkdtemp(prefix='tvlite-engine-')
    mock = subprocess.Popen([sys.executable, os.path.join(ROOT, 'ci/mock_server.py'), '8787'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)
    time.sleep(1.5)
    app = T.build('tizen', tmp)
    srv = T.serve(app, FT.PORT)
    fake = open(os.path.join(HERE, 'fake_tizen.js')).read()
    webm = os.path.join(tmp, 'clip.webm')
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc=size=320x180:rate=25', '-t', '20',
                    '-c:v', 'libvpx', '-b:v', '200k', webm], check=True)
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=['--disable-web-security'])
            ctx = b.new_context(viewport={'width': 1920, 'height': 1080})
            page = ctx.new_page()
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.add_init_script("try { if (!localStorage.getItem('lt_session')) localStorage.setItem('lt_session', %s); } catch (e) {}\n%s"
                                 % (json.dumps(json.dumps(FT.SESSION)), fake))
            # Film 10 is a file the standard player can play (WebM here); film 12 one it cannot.
            page.route('**/movie/demo/demo/10.mp4', lambda route: route.fulfill(path=webm, content_type='video/webm'))
            page.route('**/movie/demo/demo/12.mp4', lambda route: route.fulfill(status=200, body=b'not a video', content_type='video/mp4'))
            page.goto('http://127.0.0.1:%d/index.html' % FT.PORT)
            T.wait_for(page, "!document.getElementById('intro') && !!(window.Nav && Nav.top())", 15)
            check('Automatic by default', page.evaluate("Player.choice()") == 'auto')
            check('says so in the log', 'automatic' in page.evaluate("App.logText()"))

            # ---------------- Live TV: the preview, then full screen
            page.evaluate("Nav.push(new Screens.Browse(App.src, 'live'))")
            T.wait_for(page, "document.querySelectorAll('.chrow').length > 0 && !!document.querySelector('.chrow .nm span').textContent", 8)
            page.evaluate("document.querySelectorAll('.chrow')[0]._ok()")
            check('preview: plays', T.wait_for(page, "Player.state() === 'playing'", 12), state(page))
            s = state(page)
            check('preview: went on to AVPlay (MPEG-TS)', s['engine'] == 'avplay' and s['avp'] and s['vidHidden'] and not s['vidSrc'], s)
            log = page.evaluate("App.logText()")
            check('preview: the standard player was tried first (HLS)', 'open live 1.m3u8 on the standard player' in log, [l for l in log.split('\n') if 'open live' in l])
            rect = page.evaluate("(function () { var r = App.rect(document.querySelector('.pv')); return [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)]; })()")
            last = [c for c in page.evaluate('window.__av.calls') if c[0] == 'setDisplayRect'][-1][1:]
            check('preview: AVPlay in the preview box', last == rect, [last, rect])
            check('remembered: MPEG-TS on AVPlay', page.evaluate("JSON.parse(localStorage.getItem('lt_engine_by_type'))") == {'ts': 'avplay'},
                  page.evaluate("localStorage.getItem('lt_engine_by_type')"))
            page.evaluate("document.querySelectorAll('.chrow')[0]._ok()")
            check('full screen: the same stream', T.wait_for(page, "Nav.top().name === 'player' && Player.state() === 'playing'", 6) and state(page)['engine'] == 'avplay', state(page))
            last = [c for c in page.evaluate('window.__av.calls') if c[0] == 'setDisplayRect'][-1][1:]
            check('full screen: AVPlay full size', last == [0, 0, 1920, 1080], last)
            page.evaluate("window.__av.calls = []; App.key('up')")
            T.wait_for(page, "(Player.urls()[0] || '').indexOf('/2.') > 0 && Player.state() === 'playing'", 8)
            opens = [c[1].split('/').pop() for c in page.evaluate('window.__av.calls') if c[0] == 'open']
            check('next channel: straight to AVPlay for .ts', state(page)['engine'] == 'avplay', [state(page), opens])
            FT.back_to(page, 'home', 6)

            # ---------------- a film the standard player can play
            def film(n):
                page.evaluate("""(n) => App.src.categories('vod').then(function (c) { return App.src.items('vod', c[0].id); }).then(function (l) {
                    var it = l.filter(function (x) { return x.id === n; })[0];
                    Nav.push(new Screens.Player({ src: App.src, kind: 'vod', urls: [App.src.vodUrl(it)], title: it.n, item: it, resumeKey: 'vod:' + it.id })); })""", n)
                return T.wait_for(page, "Nav.top().name === 'player' && Player.state() === 'playing'", 14)
            page.evaluate("window.__av.live = false")
            check('film 10: plays', film('10'), state(page))
            s = state(page)
            check('film 10: on the standard player, AVPlay let go', s['engine'] == 'video' and not s['avp'] and not s['vidHidden'] and s['vidSrc'] and s['avState'] in ('NONE', 'IDLE'), s)
            check('film 10: Fill offered (the standard player has it)', page.evaluate("Player.fits().join(',')") == 'fit,fill,stretch')
            FT.back_to(page, 'home', 6)
            # ---------------- a film it cannot play: AVPlay
            check('film 12: plays', film('12'), [state(page), [l for l in page.evaluate("App.logText()").split('\n') if 'movie 12' in l or 'stream problem' in l][-4:]])
            s = state(page)
            check('film 12: went on to AVPlay', s['engine'] == 'avplay' and s['avp'] and s['vidHidden'], s)
            check('film 12: AVPlay pictures: Fit and Stretch', page.evaluate("Player.fits().join(',')") == 'fit,stretch')
            FT.back_to(page, 'home', 6)

            # ---------------- Settings › VOD Player
            page.evaluate("Nav.push(new Screens.Settings())")
            T.wait_for(page, "Nav.top().name === 'settings'", 2)
            val = page.evaluate("[].slice.call(document.querySelectorAll('.sbox')).filter(function (b) { return b.querySelector('.lb').textContent === 'VOD Player'; })[0].querySelector('.vl2').textContent")
            check('VOD Player box: Automatic', val == 'Automatic', val)
            page.evaluate("[].slice.call(document.querySelectorAll('.sbox')).filter(function (b) { return b.querySelector('.lb').textContent === 'VOD Player'; })[0]._ok()")
            T.wait_for(page, "!!document.querySelector('.choices')", 2)
            chips = page.evaluate("[].slice.call(document.querySelectorAll('.choices .subrow')).filter(function (r) { return /Video player/.test(r.innerText); })[0].innerText")
            check('Video player: Automatic, Standard, Samsung AVPlay', all(x in chips for x in ('Automatic (recommended)', 'Standard', 'Samsung AVPlay')), chips)
            check('Video player: Automatic chosen', page.evaluate("[].slice.call(document.querySelectorAll('.choices .chip.sel')).map(function (c) { return c.textContent; }).join('|')").startswith('Automatic'))
            check('no script errors', not errors, '; '.join(errors[:3]))
            b.close()
    finally:
        mock.terminate()
        srv.shutdown()
    print('\n%d failed' % len(T.FAILS))
    sys.exit(1 if T.FAILS else 0)


if __name__ == '__main__':
    main()
