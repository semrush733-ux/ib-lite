"""Browser test of the light TV app's player engines (not part of the app).

Builds the Samsung variant, serves it next to the mock website (ci/mock_server.py), opens it in
Chromium with a stand-in for Samsung's AVPlay (test/fake_tizen.js) and checks that the player uses
AVPlay correctly: open/prepare/play, first picture, preview and full-screen rectangles, pause and
seek for films, sound tracks, the other address after a failure, the reconnect of a live channel
that ends, and stop. Then the LG variant (plain <video>) starts without errors.

    python3 tvlite/test/avplay_test.py            (from the repository root)
"""
import functools, http.server, json, os, socketserver, subprocess, sys, tempfile, threading, time

from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
FAILS = []


def check(name, ok, detail=''):
    print(('PASS  ' if ok else 'FAIL  ') + name + (('  [%s]' % detail) if detail not in ('', None) else ''), flush=True)
    if not ok:
        FAILS.append(name)


def build(target, folder):
    out = os.path.join(folder, 'out')
    app = os.path.join(folder, 'app-' + target)
    cmd = [sys.executable, os.path.join(ROOT, 'tools/build_tvlite.py'), '--target', target, '--out', out,
           '--name', 'IBO Lite Player', '--site', 'http://127.0.0.1:8787', '--id', 'com.liteplayer.tv',
           '--version', '2.0.999', '--build', '999', '--folder', app]
    if target == 'tizen':
        cmd += ['--tizen-app', 'LitePlayer', '--file', 'LitePlayer.wgt']
    subprocess.run(cmd, check=True, cwd=ROOT, stdout=subprocess.DEVNULL)
    return app


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


def serve(folder, port):
    handler = functools.partial(Quiet, directory=folder)
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.ThreadingTCPServer(('127.0.0.1', port), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def wait_for(page, js, timeout=8.0):
    end = time.time() + timeout
    while time.time() < end:
        try:
            if page.evaluate(js):
                return True
        except Exception:
            pass
        time.sleep(0.1)
    return False


def calls(page, name=None):
    c = page.evaluate('window.__av.calls')
    return [x for x in c if name is None or x[0] == name]


def main():
    tmp = tempfile.mkdtemp(prefix='tvlite-test-')
    mock = subprocess.Popen([sys.executable, os.path.join(ROOT, 'ci/mock_server.py'), '8787'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)
    time.sleep(1.5)
    tizen_app = build('tizen', tmp)
    webos_app = build('webos', tmp)
    s1, s2 = serve(tizen_app, 8091), serve(webos_app, 8092)
    fake = open(os.path.join(HERE, 'fake_tizen.js')).read()
    try:
        with sync_playwright() as p:
            b = p.chromium.launch()
            # ---------------- Samsung: AVPlay
            page = b.new_page(viewport={'width': 1920, 'height': 1080})
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.add_init_script(fake)
            page.goto('http://127.0.0.1:8091/index.html')
            check('app starts (first screen shown)', wait_for(page, '!!(window.Nav && Nav.top())', 12))
            check('Samsung uses AVPlay', page.evaluate('Player.engine') == 'avplay')
            check('the <video> element stays hidden', page.evaluate("document.getElementById('vid').classList.contains('hide')"))
            check('an AVPlay picture element exists', page.evaluate("!!document.querySelector('object#avp[type=\"application/avplayer\"]')"))

            # live channel, full screen
            page.evaluate("Player.layout('full'); Player.open(['http://127.0.0.1:8787/live/demo/demo/1.ts'], {live: true})")
            check('live: plays', wait_for(page, "Player.state() === 'playing'", 6), page.evaluate('Player.state()'))
            names = [c[0] for c in calls(page)]
            check('live: open → prepareAsync → play', all(n in names for n in ('open', 'prepareAsync', 'play')), ','.join(names[:12]))
            rects = calls(page, 'setDisplayRect')
            check('live: full-screen rectangle 0,0,1920,1080', any(r[1:] == [0, 0, 1920, 1080] for r in rects), rects[-1:] if rects else 'none')
            check('page lets the picture through', page.evaluate("document.documentElement.classList.contains('avp-on')"))
            check('picture size from the stream', page.evaluate('Player.size()') == '1920x1080', page.evaluate('Player.size()'))
            tr = page.evaluate('Player.audioTracks()')
            check('two sound tracks, first on', len(tr) == 2 and tr[0]['on'] and tr[1]['i'] == 2, json.dumps(tr))
            page.evaluate('Player.setAudio(2)')
            check('sound track change goes to AVPlay', any(c[1:] == ['AUDIO', 2] for c in calls(page, 'setSelectTrack')))

            # preview box
            page.evaluate("Player.layout('preview', {left: 1100, top: 160, width: 720, height: 405})")
            rects = calls(page, 'setDisplayRect')
            check('preview rectangle', rects and rects[-1][1:] == [1100, 160, 720, 405], rects[-1:] if rects else 'none')
            page.evaluate("Player.layout('off')")
            check('picture off: page background back', not page.evaluate("document.documentElement.classList.contains('avp-on')"))

            # live channel that ends: reconnects
            page.evaluate("Player.layout('full')")
            page.evaluate('window.__av.calls = []; window.__av.listener.onstreamcompleted()')
            check('live end: reconnects', wait_for(page, "window.__av.calls.some(function (c) { return c[0] === 'open'; })", 4))
            check('live end: plays again', wait_for(page, "Player.state() === 'playing'", 6), page.evaluate('Player.state()'))

            # first address fails: the other format
            page.evaluate("window.__av.calls = []; window.__av.failNext = 'PLAYER_ERROR_CONNECTION_FAILED';"
                          "Player.open(['http://127.0.0.1:8787/live/demo/demo/2.ts', 'http://127.0.0.1:8787/live/demo/demo/2.m3u8'], {live: true})")
            check('failure: the other address plays', wait_for(page, "Player.state() === 'playing'", 8), page.evaluate('Player.state()'))
            opened = [c[1] for c in calls(page, 'open')]
            check('failure: second address opened', len(opened) >= 2 and opened[-1].endswith('.m3u8'), opened)

            # film: resume position, pause, seek
            page.evaluate("window.__av.live = false; window.__av.calls = []; Player.open(['http://127.0.0.1:8787/movie/demo/demo/9.mp4'], {live: false, start: 120})")
            check('film: plays', wait_for(page, "Player.state() === 'playing'", 6))
            seeks = calls(page, 'seekTo')
            check('film: starts where it was left (120 s)', any(s[1] == 120000 for s in seeks), seeks)
            check('film: duration from AVPlay', page.evaluate('Player.dur()') == 3600)
            page.evaluate('Player.toggle()')
            check('film: pause', page.evaluate("Player.state() === 'paused' && window.__av.state === 'PAUSED'"))
            page.evaluate('Player.toggle()')
            check('film: play again', page.evaluate("Player.state() === 'playing' && window.__av.state === 'PLAYING'"))
            page.evaluate('Player.seek(600)')
            check('film: seek 10 min', any(s[1] == 600000 for s in calls(page, 'seekTo')))

            # stop
            page.evaluate("window.__av.calls = []; Player.stop()")
            names = [c[0] for c in calls(page)]
            check('stop: AVPlay stopped and closed', 'stop' in names and 'close' in names, names)
            check('Samsung: no script errors', not errors, '; '.join(errors[:3]))

            # ---------------- LG: <video>
            page2 = b.new_page(viewport={'width': 1920, 'height': 1080})
            errors2 = []
            page2.on('pageerror', lambda e: errors2.append(str(e)))
            page2.goto('http://127.0.0.1:8092/index.html')
            check('LG: app starts', wait_for(page2, '!!(window.Nav && Nav.top())', 12))
            check('LG uses <video>', page2.evaluate('Player.engine') == 'video')
            page2.evaluate("Player.layout('full'); Player.open(['http://127.0.0.1:8787/live/demo/demo/1.m3u8'], {live: true})")
            time.sleep(1.5)
            check('LG: video element shown', not page2.evaluate("document.getElementById('vid').classList.contains('hide')"))
            page2.evaluate('Player.stop()')
            check('LG: no script errors', not errors2, '; '.join(errors2[:3]))
            b.close()
    finally:
        mock.terminate()
        s1.shutdown()
        s2.shutdown()
    print('\n%d failed' % len(FAILS))
    sys.exit(1 if FAILS else 0)


if __name__ == '__main__':
    main()
