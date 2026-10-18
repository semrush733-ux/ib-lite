"""Browser test of the light TV app's subtitles (not part of the app).

Builds the Samsung variant, serves it next to the mock server (ci/mock_server.py) and opens it in
Chromium. With the stand-in for AVPlay: the options panel lists the stream's subtitle tracks, a
track comes on (setSelectTrack TEXT, setSilentSubtitle), the text AVPlay sends is drawn by the app
and goes after its time, the language is remembered for the next film, Off. Settings › Subtitles:
size, colour, background and height, used by the player. With the standard player: a text track
of the <video> element, its cues drawn in the app's look.

    python3 tvlite/test/subtitles_test.py         (from the repository root)
"""
import json, os, subprocess, sys, tempfile, time

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avplay_test as T  # noqa: E402
import features_test as FT  # noqa: E402

ROOT = T.ROOT
check = T.check


def open_film(page):
    page.evaluate("""App.src.categories('vod').then(function (c) { return App.src.items('vod', c[0].id); })
        .then(function (l) { Nav.push(new Screens.Player({ src: App.src, kind: 'vod', urls: [App.src.vodUrl(l[0])], title: l[0].n, item: l[0], resumeKey: 'vod:' + l[0].id })); })""")
    return T.wait_for(page, "Nav.top().name === 'player' && Player.state() === 'playing'", 8)


def options(page):
    page.evaluate("App.key('ok')")
    T.wait_for(page, "document.querySelector('.pscr .osd.show') !== null", 2)
    page.evaluate("""(function () { var b = [].slice.call(document.querySelectorAll('.pscr .btns .rb')).filter(function (x) {
        F.set(x); return /subtitles/.test(document.querySelector('.pscr .lbl').textContent); })[0]; b._ok(); })()""")
    return T.wait_for(page, "!!document.querySelector('.optlist')", 2)


def opts(page):
    return page.evaluate("[].slice.call(document.querySelectorAll('.optlist .opt')).map(function (o) { return o.textContent.replace(/[\\ue000-\\uf8ff]|[\\udb80-\\udbff][\\udc00-\\udfff]/g, ''); })")


def sub_box(page):
    return page.evaluate("""(function () { var b = document.querySelector('.pscr .subs'), s = b.firstChild, cs = getComputedStyle(s);
        return { shown: !b.classList.contains('hide'), text: b.innerText, size: s.style.fontSize, color: cs.color, bg: cs.backgroundColor, bottom: b.style.bottom }; })()""")


def main():
    tmp = tempfile.mkdtemp(prefix='tvlite-subs-')
    mock = subprocess.Popen([sys.executable, os.path.join(ROOT, 'ci/mock_server.py'), '8787'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)
    time.sleep(1.5)
    app = T.build('tizen', tmp)
    srv = T.serve(app, FT.PORT)
    fake = open(os.path.join(HERE, 'fake_tizen.js')).read()
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=['--disable-web-security'])
            page, errors = FT.start(b, fake)
            page.evaluate("window.__av.live = false")
            check('film plays (AVPlay)', open_film(page))
            check('options open', options(page))
            o = opts(page)
            check('options: subtitles Off and the two tracks', 'Off' in o and any(x.startswith('ENG') for x in o) and any(x.startswith('ARA') for x in o), o)
            heads = page.evaluate("[].slice.call(document.querySelectorAll('.optlist h3')).map(function (h) { return h.textContent; })")
            check('options: subtitle size', 'Subtitle size' in heads, heads)
            # the subtitle tracks come after "Off" (the sound tracks are above)
            page.evaluate("""window.__av.calls = []; (function () { var o = [].slice.call(document.querySelectorAll('.optlist .opt')), i;
                for (i = 0; i < o.length; i++) if (/Off$/.test(o[i].textContent)) break;
                o[i + 1]._ok(); })()""")
            calls = [c for c in page.evaluate('window.__av.calls') if c[0] in ('setSelectTrack', 'setSilentSubtitle')]
            check('ENG: AVPlay shows the text track', ['setSelectTrack', 'TEXT', 3] in calls and ['setSilentSubtitle', False] in calls, calls)
            check('ENG: remembered', page.evaluate("JSON.parse(localStorage.getItem('lt_sub_lang'))") == 'eng')
            page.evaluate("window.__av.listener.onsubtitlechange(1200, 'Hello <i>there</i>\\nSecond line', 0, '')")
            sb = sub_box(page)
            check('the app draws the subtitle', sb['shown'] and sb['text'] == 'Hello there\nSecond line', sb)
            check('Medium white with a shadow at the bottom', sb['size'] == '59px' and sb['color'] == 'rgb(255, 255, 255)' and sb['bottom'] == '48px', sb)
            check('it goes after its time', T.wait_for(page, "document.querySelector('.pscr .subs').classList.contains('hide')", 3))
            page.evaluate("App.key('ok')")  # the bar: the subtitle moves above it
            T.wait_for(page, "document.querySelector('.pscr .osd.show') !== null", 2)
            page.evaluate("window.__av.listener.onsubtitlechange(3000, 'Over the bar', 0, '')")
            check('above the bar while it shows', sub_box(page)['bottom'] == '298px', sub_box(page))
            FT.back_to(page, 'home', 4)

            # ---------------- the next film: the language comes on by itself
            page.evaluate("window.__av.calls = []")
            open_film(page)
            T.wait_for(page, "window.__av.calls.some(function (c) { return c[0] === 'setSelectTrack' && c[1] === 'TEXT'; })", 3)
            calls = [c for c in page.evaluate('window.__av.calls') if c[0] == 'setSelectTrack']
            check('next film: English subtitles again', ['setSelectTrack', 'TEXT', 3] in calls, calls)
            options(page)
            check('options: ENG is the one on', page.evaluate("[].slice.call(document.querySelectorAll('.optlist .opt.sel')).map(function (o) { return o.textContent; }).join('|')").find('ENG') >= 0)
            page.evaluate("window.__av.calls = []; [].slice.call(document.querySelectorAll('.optlist .opt')).filter(function (x) { return /Off$/.test(x.textContent); })[0]._ok()")
            check('Off: silent again', ['setSilentSubtitle', True] in page.evaluate('window.__av.calls'), page.evaluate('window.__av.calls'))
            check('Off: not remembered', page.evaluate("JSON.parse(localStorage.getItem('lt_sub_lang'))") == '')
            FT.back_to(page, 'home', 4)

            # ---------------- Settings › Subtitles
            page.evaluate("Nav.push(new Screens.Settings())")
            T.wait_for(page, "Nav.top().name === 'settings'", 2)
            page.evaluate("[].slice.call(document.querySelectorAll('.sbox')).filter(function (r) { return r.querySelector('.lb').textContent === 'Subtitles'; })[0]._ok()")
            check('Settings: the subtitle look', T.wait_for(page, "!!document.querySelector('.subset')", 2))
            check('Settings: Medium in focus', page.evaluate("F.cur && F.cur.textContent") == 'Medium')
            page.evaluate("App.key('right')")
            page.evaluate("App.key('ok')")  # Large
            page.evaluate("App.key('down')")
            check('Down: the colour row on its choice', page.evaluate("F.cur.textContent") == 'White', page.evaluate("F.cur.textContent"))
            page.evaluate("App.key('right'); App.key('ok')")  # Yellow
            page.evaluate("App.key('down'); App.key('right'); App.key('ok')")  # Dark box
            page.evaluate("App.key('down'); App.key('right'); App.key('ok')")  # Higher
            vals = page.evaluate("['sub_size', 'sub_color', 'sub_bg', 'sub_pos'].map(function (k) { return JSON.parse(localStorage.getItem('lt_' + k)); })")
            check('Settings: Large, Yellow, Dark box, Higher', vals == [2, 1, 1, 1], vals)
            sample = page.evaluate("document.querySelector('.subset .subs span').style.fontSize")
            check('Settings: the sample follows', sample == str(round(73 * 0.62)) + 'px', sample)
            page.screenshot(path=os.path.join(tmp, 'subtitle-settings.png'))
            page.evaluate("UI.closeAll()")
            row = page.evaluate("[].slice.call(document.querySelectorAll('.sbox')).filter(function (r) { return r.querySelector('.lb').textContent === 'Subtitles'; })[0].textContent")
            check('Settings: the row says Large, yellow', 'Large, yellow' in row, row)
            FT.back_to(page, 'home', 3)
            page.evaluate("window.__av.calls = []")
            open_film(page)
            page.evaluate("App.key('back')")  # the bar goes (the subtitle sits lower then)
            T.wait_for(page, "document.querySelector('.pscr .osd.show') === null", 2)
            page.evaluate("Player.setSub(3); window.__av.listener.onsubtitlechange(5000, 'Big yellow', 0, '')")
            sb = sub_box(page)
            check('player: the chosen look', sb['size'] == '73px' and sb['color'] == 'rgb(255, 225, 77)' and sb['bg'] == 'rgba(0, 0, 0, 0.72)' and sb['bottom'] == '134px', sb)
            page.screenshot(path=os.path.join(tmp, 'subtitle-player.png'))
            print('screenshots:', tmp)
            check('AVPlay: no script errors', not errors, '; '.join(errors[:3]))
            page.close()

            # ---------------- the standard player: a text track of <video>
            page = b.new_page(viewport={'width': 1920, 'height': 1080})
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.add_init_script("try { localStorage.setItem('lt_privacy_ok', '1'); localStorage.setItem('lt_session', %s); } catch (e) {}" % json.dumps(json.dumps(FT.SESSION)))
            # Chromium here plays WebM, not the H.264 films of a real server: a small WebM stands in.
            webm = os.path.join(tmp, 'clip.webm')
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc=size=320x180:rate=25', '-t', '20',
                            '-c:v', 'libvpx', '-b:v', '200k', webm], check=True)
            page.route('**/movie/demo/demo/*', lambda route: route.fulfill(path=webm, content_type='video/webm'))
            page.goto('http://127.0.0.1:%d/index.html' % FT.PORT)
            T.wait_for(page, "!document.getElementById('intro') && !!(window.Nav && Nav.top())", 15)
            check('standard: film plays', open_film(page), page.evaluate("Player.state()"))
            page.evaluate("""(function () { var v = document.getElementById('vid'), tr = document.createElement('track');
                tr.kind = 'subtitles'; tr.srclang = 'en'; tr.label = 'English';
                tr.src = URL.createObjectURL(new Blob(['WEBVTT\\n\\n00:00.000 --> 09:00.000\\nFrom the <b>track</b>\\n'], { type: 'text/vtt' }));
                v.appendChild(tr); })()""")
            check('standard: the track is listed', T.wait_for(page, "Player.subTracks().length === 1 && Player.subTracks()[0].label === 'English'", 3),
                  page.evaluate("JSON.stringify(Player.subTracks())"))
            page.evaluate("Player.setSub(Player.subTracks()[0].i)")
            check('standard: its cue drawn by the app', T.wait_for(page, "document.querySelector('.pscr .subs').innerText === 'From the track'", 5), sub_box(page))
            check('standard: the track itself is not drawn by the TV', page.evaluate("document.getElementById('vid').textTracks[0].mode") == 'hidden')
            page.evaluate("Player.setSub(-1)")
            check('standard: Off', page.evaluate("document.getElementById('vid').textTracks[0].mode") == 'disabled' and sub_box(page)['shown'] is False)
            check('standard: no script errors', not errors, '; '.join(errors[:3]))
            b.close()
    finally:
        mock.terminate()
        srv.shutdown()
    print('\n%d failed' % len(T.FAILS))
    sys.exit(1 if T.FAILS else 0)


if __name__ == '__main__':
    main()
