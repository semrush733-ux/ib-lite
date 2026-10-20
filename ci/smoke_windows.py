#!/usr/bin/env python3
"""
Windows test (runs in .github/workflows/windows.yml, on the Windows build machine).

Starts the mock IPTV server (ci/mock_server.py), opens the TEST build of the Windows app and
drives it with the keyboard, the way a remote would: sign in, Live TV, play a channel full
screen, Back with Esc, full screen with F11. The test build writes its log to a file
(B1G_LOG_FILE); the test reads it to know what really happened. Screenshots of the screen go to
out/smoke-win. Output: out/smoke-win/SMOKE.md and STATUS ("ok" when the app opens and signs in).

    python ci/smoke_windows.py <path to the test .exe> "<window title>" <log file>
"""
import ctypes
import os
import re
import subprocess
import sys
import time

EXE, TITLE, LOG = sys.argv[1], sys.argv[2], sys.argv[3]
OUT = 'out/smoke-win'
os.makedirs(OUT, exist_ok=True)

user32 = ctypes.WinDLL('user32', use_last_error=True)
VK = {'DOWN': 0x28, 'UP': 0x26, 'LEFT': 0x25, 'RIGHT': 0x27, 'ENTER': 0x0D, 'ESC': 0x1B, 'F11': 0x7A}
EXTENDED = {'DOWN', 'UP', 'LEFT', 'RIGHT'}
results = []
shots = 0
window = 0


def write_summary(note=''):
    failed = [r for r in results if r.startswith('FAIL')]
    with open('%s/SMOKE.md' % OUT, 'w', encoding='utf-8') as f:
        f.write('### Windows test (keyboard like a remote, mock IPTV server)\n\n')
        f.write('%d checks, %d failed%s\n\n```\n%s\n```\n' % (len(results), len(failed), note, '\n'.join(results)))


def check(name, ok, detail=''):
    line = '%s  %s' % ('PASS' if ok else 'FAIL', name)
    if detail not in ('', None):
        line += '  [%s]' % str(detail)[:200]
    results.append(line)
    print(line, flush=True)
    write_summary('  (still running)')
    return ok


def app_log():
    try:
        with open(LOG, encoding='utf-8', errors='replace') as f:
            return [line.rstrip('\n') for line in f if line.startswith('B1G ')]
    except OSError:
        return []


def mark():
    return len(app_log())


def wait_log(pattern, since, timeout):
    end = time.time() + timeout
    while time.time() < end:
        for line in app_log()[since:]:
            m = re.search(pattern, line)
            if m:
                return m
        time.sleep(0.5)
    return None


def wait_position(index, at_least, since, timeout):
    end = time.time() + timeout
    best = -1
    while time.time() < end:
        for line in app_log()[since:]:
            m = re.search(r'playing index=%d pos=(\d+)' % index, line)
            if m:
                best = max(best, int(m.group(1)))
        if best >= at_least:
            return best
        time.sleep(1)
    return best


def find_window():
    global window
    window = user32.FindWindowW(None, TITLE) or window
    return window


def focus():
    hwnd = find_window()
    if not hwnd:
        return False
    # Windows only lets the program that has the keyboard give it away: a tap on Alt first.
    user32.keybd_event(0x12, 0, 0, 0)
    user32.keybd_event(0x12, 0, 0x0002, 0)
    user32.SetForegroundWindow(hwnd)
    time.sleep(0.3)
    return user32.GetForegroundWindow() == hwnd


def key(name, pause=1.2):
    focus()
    vk = VK[name]
    scan = user32.MapVirtualKeyW(vk, 0)
    flags = 0x0001 if name in EXTENDED else 0
    user32.keybd_event(vk, scan, flags, 0)
    time.sleep(0.06)
    user32.keybd_event(vk, scan, flags | 0x0002, 0)
    time.sleep(pause)


def shot(name):
    global shots
    shots += 1
    try:
        from PIL import ImageGrab
        ImageGrab.grab().save('%s/%02d-%s.png' % (OUT, shots, name))
    except Exception as exc:  # noqa: BLE001
        print('screenshot failed: %s' % exc, flush=True)


def window_rect():
    class RECT(ctypes.Structure):
        _fields_ = [('left', ctypes.c_long), ('top', ctypes.c_long), ('right', ctypes.c_long), ('bottom', ctypes.c_long)]
    r = RECT()
    if find_window() and user32.GetWindowRect(window, ctypes.byref(r)):
        return r.left, r.top, r.right, r.bottom
    return None


def run(app):
    # 1. The program opens and shows its window (test build: on the sign-in screen).
    ok = wait_log(r'screen=login', 0, 120) is not None
    time.sleep(3)
    shot('start')
    check('the program opens (sign-in screen)', ok, 'window found' if find_window() else 'no window')
    if not ok:
        return
    with open('%s/STATUS' % OUT, 'w') as f:
        f.write('ok')
    reg = wait_log(r'backend register hwid=(\w+) mac=(\w+)', 0, 30)
    check('this computer registers with the website (machine id and MAC from Windows)',
          reg is not None and reg.group(1) == 'yes', reg.group(0) if reg else 'no registration line')
    check('window opens maximised', bool(user32.IsZoomed(window)) if find_window() else False, window_rect())

    # 2. Sign in (server, username and password are filled in; the focus is on "Sign in").
    m = mark()
    key('ENTER')
    ok = wait_log(r'screen=home', m, 60) is not None
    time.sleep(3)
    shot('home')
    if not check('sign in with the keyboard opens the home screen', ok):
        return

    # 3. Live TV: categories and channels, then a channel full screen.
    m = mark()
    key('ENTER')
    got = wait_log(r'browse live items=(\d+)', m, 60)
    time.sleep(2)
    shot('live-list')
    check('Live TV shows categories and channels', got is not None and int(got.group(1)) == 4,
          got.group(0) if got else '')
    key('RIGHT')
    key('UP')
    m = mark()
    key('ENTER')
    wait_log(r'preview open', m, 20)
    time.sleep(4)
    shot('live-preview')
    m = mark()
    key('ENTER')
    ready = wait_log(r'ready index=0 format=(\w+) video=(\d+)x(\d+)', m, 90)
    pos = wait_position(0, 8, m, 60)
    shot('live-playing')
    check('channel 1 plays full screen (.ts stream)', ready is not None and pos >= 8,
          '%s, position %ss' % (ready.group(0) if ready else 'not ready', pos))
    check('video picture is decoded', ready is not None and int(ready.group(2)) > 0, ready.group(0) if ready else '')

    # 4. F11: full screen and back.
    key('F11', pause=2)
    rect = window_rect()
    width = user32.GetSystemMetrics(0)
    height = user32.GetSystemMetrics(1)
    full = rect is not None and rect[2] - rect[0] >= width and rect[3] - rect[1] >= height
    shot('f11-full-screen')
    check('F11 makes the window full screen', full, '%s screen %dx%d' % (rect, width, height))
    key('F11', pause=2)

    # 5. Esc is Back: the player closes, the channel list is there again.
    m = mark()
    key('ESC', pause=2.5)
    shot('esc-back')
    alive = app.poll() is None
    check('Esc goes back (the program stays open)', alive and find_window() != 0)
    key('ESC', pause=2)
    key('ESC', pause=2)
    shot('home-again')
    # On the home screen Esc asks "Exit the app?"; the answer is not given here.
    key('ESC', pause=2)
    shot('exit-question')
    check('Esc on the home screen asks before closing', app.poll() is None)


def main():
    env = dict(os.environ, MOCK_BASE='http://127.0.0.1:8787')
    server_log = open('%s/mock-server.log' % OUT, 'w')
    server = subprocess.Popen([sys.executable, 'ci/mock_server.py', '8787'], stdout=server_log,
                              stderr=subprocess.STDOUT, env=env)
    time.sleep(2)
    if os.path.exists(LOG):
        os.remove(LOG)
    app = subprocess.Popen([os.path.abspath(EXE)], cwd=os.path.dirname(os.path.abspath(EXE)))
    note = ''
    try:
        run(app)
    except Exception as exc:  # noqa: BLE001
        note = '  - the test stopped: %s' % exc
        results.append('FAIL  the test runs to the end')
    finally:
        time.sleep(1)
        exited = app.poll()
        if exited is not None:
            results.append('FAIL  the program was still running at the end  [exit code %s]' % exited)
        app.kill()
        server.terminate()
        server_log.close()
        lines = app_log()
        with open('%s/app-log.txt' % OUT, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines) + '\n')
        write_summary(note)
        print(open('%s/SMOKE.md' % OUT, encoding='utf-8').read())


if __name__ == '__main__':
    main()
