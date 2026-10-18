"""Browser test of the light TV app's Network, speed test, Clear cache and Application info (not part of the app).

Builds the Samsung variant, serves it next to the mock server (ci/mock_server.py) and opens it in
Chromium with a stand-in for Samsung's network functions. Checks: the speed test button on the home
screen (and a long playlist name never pushes Settings away), the speed test against a stand-in for
Cloudflare's speed servers (ping, download, upload, the verdict; a failure; closing it while it
runs), Settings › Network (Wi-Fi name, signal, addresses), Clear cache and Application info.

    python3 tvlite/test/system_test.py            (from the repository root)
"""
import json, os, subprocess, sys, tempfile, time

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avplay_test as T  # noqa: E402
import features_test as FT  # noqa: E402

ROOT = T.ROOT
check = T.check

NETWORK = """window.webapis = window.webapis || {};
window.webapis.network = { getActiveConnectionType: function () { return 1; }, getIp: function () { return '192.168.1.50'; },
  getGateway: function () { return '192.168.1.1'; }, getDns: function () { return '8.8.8.8'; }, getSubnetMask: function () { return '255.255.255.0'; },
  getMac: function () { return ''; }, getWiFiSsid: function () { return 'Home WiFi 5G'; }, getWiFiSignalStrengthLevel: function () { return 3; } };"""


def speed_routes(page, fail=False):
    big = b'\0' * (3 * 1024 * 1024)

    def handle(route):
        url = route.request.url
        if fail:
            return route.abort()
        if '/__down?bytes=0' in url:
            return route.fulfill(status=200, body=b'', headers={'Access-Control-Allow-Origin': '*'})
        if '/__down' in url:
            time.sleep(0.2)
            return route.fulfill(status=200, body=big, headers={'Access-Control-Allow-Origin': '*', 'Content-Type': 'application/octet-stream'})
        if '/__up' in url:
            time.sleep(0.1)
            return route.fulfill(status=200, body=b'ok', headers={'Access-Control-Allow-Origin': '*'})
        return route.continue_()
    page.unroute('https://speed.cloudflare.com/**')
    page.route('https://speed.cloudflare.com/**', handle)


def dialog_text(page):
    return page.evaluate("UI.topDialog() ? UI.topDialog().innerText : ''")


def main():
    tmp = tempfile.mkdtemp(prefix='tvlite-system-')
    mock = subprocess.Popen([sys.executable, os.path.join(ROOT, 'ci/mock_server.py'), '8787'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)
    time.sleep(1.5)
    app = T.build('tizen', tmp)
    srv = T.serve(app, FT.PORT)
    fake = open(os.path.join(HERE, 'fake_tizen.js')).read()
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=['--disable-web-security'])
            # A playlist with a long name: the Settings pill still fits.
            FT.SESSION['pname'] = 'My Very Long Playlist Name From The Provider'
            page, errors = FT.start(b, fake, NETWORK)
            check('home', FT.top(page) == 'home', FT.top(page))
            sq = page.evaluate("document.querySelectorAll('.hm-icons .sq').length")
            check('home: four buttons on the right (reload, speed test, device, account)', sq == 4, sq)
            fit = page.evaluate("""(function () { var p = document.querySelector('.hm-pills').getBoundingClientRect();
                var s = [].slice.call(document.querySelectorAll('.hm-pills .pill')).pop().getBoundingClientRect();
                return [Math.round(s.right), Math.round(p.right)]; })()""")
            check('home: a long playlist name leaves Settings in view', fit[0] <= fit[1], fit)
            page.screenshot(path=os.path.join(tmp, 'home-long-name.png'))

            # ---------------- the speed test
            speed_routes(page)
            page.evaluate("document.querySelectorAll('.hm-icons .sq')[1]._ok()")
            check('speed test: opens', T.wait_for(page, "!!document.querySelector('.spd')", 2))
            check('speed test: Close in focus', page.evaluate("F.cur && F.cur.textContent") == 'Close', page.evaluate("F.cur && F.cur.textContent"))
            check('speed test: ping', T.wait_for(page, "/^\\d+$/.test(document.querySelector('.spd .sb.ping b').textContent)", 6), dialog_text(page))
            check('speed test: download', T.wait_for(page, "/\\d/.test(document.querySelector('.spd .sb.down b').textContent)", 14), dialog_text(page))
            check('speed test: upload and the verdict', T.wait_for(page, "/\\d/.test(document.querySelector('.spd .sb.up b').textContent) && /Excellent|good|Good|Fair|Slow/.test(document.querySelector('.spd .verdict').textContent)", 12),
                  dialog_text(page))
            check('speed test: Test again', page.evaluate("/Test again/.test(document.querySelectorAll('.dialog .acts .btn')[0].textContent)"))
            page.screenshot(path=os.path.join(tmp, 'speed-test.png'))
            print('screenshots:', tmp)
            # a failure
            speed_routes(page, fail=True)
            page.evaluate("document.querySelectorAll('.dialog .acts .btn')[0]._ok()")
            check('speed test: no internet', T.wait_for(page, "/could not reach/.test(document.querySelector('.spd .verdict').textContent)", 8), dialog_text(page))
            # closing while it runs
            speed_routes(page)
            page.evaluate("document.querySelectorAll('.dialog .acts .btn')[0]._ok()")
            time.sleep(1.2)
            page.evaluate("UI.closeTop()")
            time.sleep(1.5)
            check('speed test: closed while running, no dialog left', not page.evaluate("!!UI.topDialog()"))

            # ---------------- Settings
            page.evaluate("Nav.push(new Screens.Settings())")
            T.wait_for(page, "Nav.top().name === 'settings'", 2)
            rows = page.evaluate("[].slice.call(document.querySelectorAll('.sbox .lb')).map(function (r) { return r.textContent; })")
            for want in ('Network', 'Live Player', 'VOD Player', 'Subtitles', 'Parental Control', 'Profiles', 'Main Wallpaper', 'Manage Categories',
                         'Streaming Boxes', 'Clear Cache', 'Language', 'Application Info', 'Playlists', 'My device', 'Account', 'Speed test',
                         'Report a problem', 'Restart the app'):
                check('Settings box: ' + want, want in rows, rows)
            check('Settings: 18 boxes, three rows of six', len(rows) == 18 and page.evaluate(
                "(function () { var b = document.querySelectorAll('.sbox'); return b[5].offsetTop === b[0].offsetTop && b[6].offsetTop > b[0].offsetTop && b[12].offsetTop > b[6].offsetTop; })()"), rows)
            check('Settings: the first box in focus', page.evaluate("F.cur && F.cur.querySelector('.lb').textContent") == 'Network')
            page.evaluate("App.key('right')")
            check('Settings: Right moves along the boxes', page.evaluate("F.cur.querySelector('.lb').textContent") == 'Live Player')
            page.evaluate("App.key('down')")
            check('Settings: Down to the next row', page.evaluate("F.cur.querySelector('.lb').textContent") == 'Manage Categories', page.evaluate("F.cur.querySelector('.lb').textContent"))
            page.screenshot(path=os.path.join(tmp, 'settings.png'))

            def press_row(label):
                page.evaluate("(l) => [].slice.call(document.querySelectorAll('.sbox')).filter(function (r) { return r.querySelector('.lb').textContent === l; })[0]._ok()", label)

            press_row('Network')
            check('Network: the connection', T.wait_for(page, "/CONNECTED/.test(UI.topDialog() ? UI.topDialog().innerText : '')", 3), dialog_text(page))
            text = dialog_text(page)
            check('Network: Wi-Fi name, signal and addresses', 'Home WiFi 5G' in text and 'Good' in text and '192.168.1.50' in text and '192.168.1.1' in text and '8.8.8.8' in text, text)
            check('Network: four signal bars, three lit', page.evaluate("document.querySelectorAll('.bars i.on').length") == 3)
            page.screenshot(path=os.path.join(tmp, 'network.png'))
            page.evaluate("UI.closeAll()")

            # Clear cache
            page.evaluate("App.src.categories('live')")
            T.wait_for(page, "Object.keys(App.src.cache).length > 0", 3)
            page.evaluate("localStorage.setItem('lt_weather', '{}')")
            press_row('Clear Cache')
            check('Clear Cache: the cache or the watch history', 'Clear watch history' in dialog_text(page) and 'Clear cache now' in dialog_text(page), dialog_text(page))
            page.evaluate("[].slice.call(document.querySelectorAll('.dialog .acts .btn')).pop()._ok()")
            check('Clear cache: asks first', 'Clear cache?' in dialog_text(page), dialog_text(page))
            page.evaluate("[].slice.call(document.querySelectorAll('.dialog .acts .btn')).pop()._ok()")
            check('Clear cache: the lists go', page.evaluate("Object.keys(App.src.cache).length") == 0)
            check('Clear cache: the weather goes', page.evaluate("localStorage.getItem('lt_weather')") is None)
            check('Clear cache: the playlist stays', page.evaluate("!!localStorage.getItem('lt_session')"))
            check('Clear cache: says so', 'Cache cleared' in page.evaluate("document.getElementById('toast').textContent"))

            # Application info
            press_row('Application Info')
            T.wait_for(page, "!!document.querySelector('.infobox2')", 2)
            text = dialog_text(page)
            check('Application info: name, version, device, licence', 'IBO Lite Player' in text and '2.0.999' in text and 'build 999' in text and 'MAC Address' in text and 'Licence' in text, text)
            check('Application info: the TV', T.wait_for(page, "/Samsung/.test(UI.topDialog().innerText)", 3) or 'TV' in dialog_text(page), dialog_text(page))
            page.evaluate("UI.closeAll()")
            check('no script errors', not errors, '; '.join(errors[:3]))
            b.close()
    finally:
        mock.terminate()
        srv.shutdown()
    print('\n%d failed' % len(T.FAILS))
    sys.exit(1 if T.FAILS else 0)


if __name__ == '__main__':
    main()
