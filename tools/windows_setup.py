#!/usr/bin/env python3
"""Turns the Windows project made by `flutter create --platforms=windows` into the app's own.

Run by .github/workflows/windows.yml after the project is created (not part of the app):

    python tools/windows_setup.py "IBO Lite Player" IBOLitePlayer

  * program name and window title; the program opens full screen like a TV app (no title bar, no
    taskbar; F11 switches to a maximised window and back, remembered), a window is never smaller
    than 960x540
  * the .exe file name and its version details (Properties > Details)
  * windows_extra/b1g_device.cpp: the app's "b1g/device" channel (machine id for the website,
    network and Wi-Fi details, full screen with F11, keep the screen on while a video plays)
  * the program icon from brand/icon.png

Every change must find its place in the template: when Flutter changes its Windows template,
the build stops here with a clear message instead of making a program that misses a part.
"""
import os
import re
import shutil
import sys

RUNNER = os.path.join('windows', 'runner')


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)


def patch(path, old, new, count=1):
    text = read(path)
    found = text.count(old)
    if found < 1:
        sys.exit('windows_setup: "%s" not found in %s (has the Flutter template changed?)' % (old.strip()[:60], path))
    write(path, text.replace(old, new, count))


def patch_re(path, pattern, repl):
    text = read(path)
    new, n = re.subn(pattern, repl, text, count=1)
    if n != 1:
        sys.exit('windows_setup: pattern %r not found in %s (has the Flutter template changed?)' % (pattern, path))
    write(path, new)


def wide_literal(text):
    """A C++ wide string literal for any text (non-ASCII letters as \\uXXXX)."""
    out = []
    for ch in text:
        if ch in '\\"':
            out.append('\\' + ch)
        elif 32 <= ord(ch) < 127:
            out.append(ch)
        else:
            out.append('\\u%04x' % ord(ch))
    return 'L"%s"' % ''.join(out)


def ascii_only(text):
    return re.sub(r'[^ -~]', '', text).replace('"', '').strip() or 'App'


def main():
    app_name = sys.argv[1] if len(sys.argv) > 1 else 'Lite Player'
    binary = re.sub(r'[^A-Za-z0-9]', '', sys.argv[2] if len(sys.argv) > 2 else app_name) or 'App'

    # 1. The channel code.
    for name in ('b1g_device.h', 'b1g_device.cpp'):
        shutil.copy(os.path.join('windows_extra', name), os.path.join(RUNNER, name))
    patch(os.path.join(RUNNER, 'CMakeLists.txt'), '"flutter_window.cpp"', '"flutter_window.cpp"\n  "b1g_device.cpp"')

    fw = os.path.join(RUNNER, 'flutter_window.cpp')
    patch(fw, '#include "flutter_window.h"', '#include "flutter_window.h"\n\n#include "b1g_device.h"')
    patch(fw, 'RegisterPlugins(flutter_controller_->engine());',
          'RegisterPlugins(flutter_controller_->engine());\n'
          '  b1g_device::Register(flutter_controller_->engine()->messenger(), GetHandle());')
    # Never smaller than 960x540 (at the screen's scale): the TV layout needs the room.
    patch(fw, '  switch (message) {',
          '  if (message == WM_GETMINMAXINFO) {\n'
          '    const UINT dpi = GetDpiForWindow(hwnd);\n'
          '    auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);\n'
          '    limits->ptMinTrackSize.x = MulDiv(960, static_cast<int>(dpi), 96);\n'
          '    limits->ptMinTrackSize.y = MulDiv(540, static_cast<int>(dpi), 96);\n'
          '    return 0;\n'
          '  }\n\n'
          '  switch (message) {')

    # 2. Opens full screen (like a TV app), or maximised when the viewer chose a window with F11
    #    last time; F11 / Alt+Enter switch between the two.
    patch(fw, 'this->Show();', 'if (!b1g_device::ShowFullScreen()) this->Show();')
    patch(os.path.join(RUNNER, 'win32_window.cpp'), 'ShowWindow(window_handle_, SW_SHOWNORMAL)',
          'ShowWindow(window_handle_, SW_SHOWMAXIMIZED)')

    # 3. Window title, .exe name, version details.
    patch_re(os.path.join(RUNNER, 'main.cpp'), r'window\.Create\(L"[^"]*"', 'window.Create(%s' % wide_literal(app_name))
    patch_re(os.path.join('windows', 'CMakeLists.txt'), r'set\(BINARY_NAME "[^"]*"\)', 'set(BINARY_NAME "%s")' % binary)
    rc = os.path.join(RUNNER, 'Runner.rc')
    plain = ascii_only(app_name)
    for key, value in (('CompanyName', plain), ('FileDescription', plain), ('InternalName', binary),
                       ('OriginalFilename', binary + '.exe'), ('ProductName', plain),
                       ('LegalCopyright', 'Copyright (C) ' + plain)):
        patch_re(rc, r'VALUE "%s", "[^"]*"' % key, 'VALUE "%s", "%s"' % (key, value))

    # 4. Icon: the brand symbol on the app's dark tile (rounded), 16 to 256 pixels.
    try:
        from PIL import Image, ImageDraw
        size = 256
        tile = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        mask = Image.new('L', (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * 0.2), fill=255)
        tile.paste(Image.new('RGBA', (size, size), (24, 12, 15, 255)), (0, 0), mask)
        symbol = Image.open(os.path.join('brand', 'icon.png')).convert('RGBA')
        box = symbol.getbbox()
        if box:
            symbol = symbol.crop(box)
        scale = 0.74 * size / max(symbol.size)
        symbol = symbol.resize((max(1, round(symbol.width * scale)), max(1, round(symbol.height * scale))), Image.LANCZOS)
        tile.paste(symbol, ((size - symbol.width) // 2, (size - symbol.height) // 2), symbol)
        tile.save(os.path.join(RUNNER, 'resources', 'app_icon.ico'),
                  sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
        print('icon done')
    except Exception as exc:  # noqa: BLE001 - the Flutter icon stays
        print('icon not made: %s' % exc)

    print('windows project ready: "%s" (%s.exe)' % (app_name, binary))


if __name__ == '__main__':
    main()
