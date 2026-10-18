#!/usr/bin/env python3
"""Builds the light TV app (folder tvlite/) into an installable package: a webOS package (.ipk) for
LG TVs, or with --target tizen a Samsung TV package (.wgt, not signed yet).

The app is plain HTML / CSS / JavaScript with the TV's own video player: no engine to load,
so it opens at once and stays smooth on every LG and Samsung TV.

Usage (from the repository root):
  python3 tools/build_tvlite.py --out out --name "IBO Lite Player" --site https://ibolite.pro \
      --id com.liteplayer.tv --version 2.0.1 [--build 1] [--file IBOLitePlayer.ipk]
  python3 tools/build_tvlite.py --target tizen --out out --name "IBO Lite Player" --site https://ibolite.pro \
      --id com.liteplayer.tv --tizen-app LitePlayer --version 2.0.1 --file LitePlayer.wgt
The brand symbol comes from brand/icon.png (the build workflow first takes it from the website).
"""
import argparse
import hashlib
import io
import json
import os
import shutil
import tarfile
import time
import zipfile
from xml.sax.saxutils import escape

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'tvlite')
BG = (20, 10, 13)


def symbol():
    img = Image.open(os.path.join(ROOT, 'brand', 'icon.png')).convert('RGBA')
    box = img.getbbox()
    if box:
        img = img.crop(box)
    return img


def fit(img, w, h, scale):
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    k = min(w * scale / img.width, h * scale / img.height)
    s = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
    out.alpha_composite(s, ((w - s.width) // 2, (h - s.height) // 2))
    return out


def launcher_icon(sym, size):
    """Symbol centred on the solid dark brand colour (the LG launcher tile). LG's store rules: a square
    icon, one solid background colour (no gradient, no transparency) that matches the app tile colour."""
    big = size * 4
    bg = Image.new('RGBA', (big, big), BG + (255,))
    bg.alpha_composite(fit(sym, big, big, 0.72))
    return bg.resize((size, size), Image.LANCZOS).convert('RGB')


def tizen_icon(sym):
    """Samsung's app icon: 512 x 423, the symbol on the solid dark brand colour (RGB, no transparency)."""
    w, h = 512, 423
    bg = Image.new('RGBA', (w * 4, h * 4), BG + (255,))
    bg.alpha_composite(fit(sym, w * 4, h * 4, 0.62))
    return bg.resize((w, h), Image.LANCZOS).convert('RGB')


def tizen_pkg_id(seed):
    """A Samsung (Tizen) package id: 10 letters and digits, always the same for the same app id."""
    h = hashlib.md5(seed.encode('utf-8')).hexdigest()
    al = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    return ''.join(al[int(h[i:i + 2], 16) % 62] for i in range(0, 20, 2))


TIZEN_CONFIG = '''<?xml version="1.0" encoding="UTF-8"?>
<widget xmlns="http://www.w3.org/ns/widgets" xmlns:tizen="http://tizen.org/ns/widgets" id="{wid}" version="{version}" viewmodes="maximized">
    <tizen:application id="{pkg}.{app}" package="{pkg}" required_version="4.0"/>
    <content src="index.html"/>
    <feature name="http://tizen.org/feature/screen.size.normal.1080.1920"/>
    <icon src="icon.png"/>
    <name>{name}</name>
    <access origin="*" subdomains="true"/>
    <tizen:privilege name="http://tizen.org/privilege/internet"/>
    <tizen:privilege name="http://tizen.org/privilege/tv.inputdevice"/>
    <tizen:privilege name="http://developer.samsung.com/privilege/network.public"/>
    <tizen:privilege name="http://developer.samsung.com/privilege/productinfo"/>
    <tizen:profile name="tv-samsung"/>
    <tizen:setting screen-orientation="landscape" context-menu="disable" background-support="disable" encryption="disable" install-location="auto" hwkey-event="enable"/>
</widget>
'''


def tar_bytes(entries):
    """entries: list of (name, bytes or None for a folder). Owner root, as webOS expects."""
    buf = io.BytesIO()
    now = int(time.time())
    with tarfile.open(fileobj=buf, mode='w:gz', format=tarfile.GNU_FORMAT) as t:
        for name, data in entries:
            info = tarfile.TarInfo(name)
            info.uid = info.gid = 0
            info.uname = info.gname = 'root'
            info.mtime = now
            if data is None:
                info.type = tarfile.DIRTYPE
                info.mode = 0o755
                t.addfile(info)
            else:
                info.mode = 0o644
                info.size = len(data)
                t.addfile(info, io.BytesIO(data))
    return buf.getvalue()


def write_folder(folder, files):
    """The unpacked app (for browser tests)."""
    if not folder:
        return
    if os.path.isdir(folder):
        shutil.rmtree(folder)
    for rel, data in files.items():
        dest = os.path.join(folder, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, 'wb') as f:
            f.write(data)


def ar_member(name, data, mtime):
    head = '%-16s%-12d%-6d%-6d%-8s%-10d`\n' % (name, mtime, 0, 0, '100644', len(data))
    out = head.encode('ascii') + data
    if len(data) % 2:
        out += b'\n'
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', default='out')
    p.add_argument('--name', default='Lite Player')
    p.add_argument('--site', default='')
    p.add_argument('--api', default='')
    p.add_argument('--id', default='com.liteplayer.tv')
    p.add_argument('--version', default='2.0.0')
    p.add_argument('--build', type=int, default=0)
    p.add_argument('--vendor', default='')
    p.add_argument('--file', default='')
    p.add_argument('--folder', default='', help='also leave the unpacked app here (for browser tests)')
    p.add_argument('--resolution', default='1920x1080', choices=['1920x1080', '1280x720'],
                   help='graphics resolution in appinfo.json: 1920x1080 for UHD TVs, 1280x720 for Full HD TVs (LG Seller Lounge takes one package of each)')
    p.add_argument('--target', default='webos', choices=['webos', 'tizen'], help='webos: LG .ipk, tizen: Samsung .wgt')
    p.add_argument('--tizen-pkg', default='', help='Samsung package id (10 letters/digits); made from --id when empty')
    p.add_argument('--tizen-app', default='', help='Samsung application name part (letters/digits); made from --name when empty')
    p.add_argument('--tmdb', default='', help='TMDB API key (film details: cast photos, stills, trailer); none = those stay off')
    p.add_argument('--tmdb-base', default='', help='TMDB API address (tests)')
    p.add_argument('--tmdb-images', default='', help='TMDB pictures address (tests)')
    a = p.parse_args()
    tizen = a.target == 'tizen'

    site = a.site.rstrip('/')
    api = a.api or (site + '/wp-json/b1g/v1' if site else '')
    vendor = a.vendor or (site.split('://')[-1].split('/')[0] if site else a.name)
    app_id = ''.join(c for c in a.id.lower() if c.isalnum() or c in '.-') or 'com.liteplayer.tv'

    files = {}
    for base, _dirs, names in os.walk(SRC):
        for n in names:
            full = os.path.join(base, n)
            rel = os.path.relpath(full, SRC).replace(os.sep, '/')
            # test/: browser tests; tools/: helpers for the PC (install-samsung.bat), not part of the app.
            if rel in ('js/config.js',) or rel.startswith(('test/', 'tools/')) or n.startswith('.'):
                continue
            with open(full, 'rb') as f:
                files[rel] = f.read()

    config = {
        'appName': a.name, 'apiBase': api, 'platform': 'samsung-tv' if tizen else 'lg-tv', 'version': a.version,
        'build': a.build, 'appId': app_id,
    }
    if a.tmdb.strip():
        config['tmdbKey'] = a.tmdb.strip()
        if a.tmdb_base:
            config['tmdbBase'] = a.tmdb_base.rstrip('/')
        if a.tmdb_images:
            config['tmdbImages'] = a.tmdb_images.rstrip('/')
    files['js/config.js'] = ('/* Written by tools/build_tvlite.py */\nvar CONFIG = %s;\n' % json.dumps(config, indent=2)).encode('utf-8')
    files['index.html'] = files['index.html'].replace(b'<title>Lite Player</title>', ('<title>%s</title>' % a.name).encode('utf-8'))
    if tizen:
        # Samsung's own TV functions (TV id, MAC, screensaver), loaded by the TV before the app.
        tag = b'<script src="js/config.js"></script>'
        assert tag in files['index.html']
        files['index.html'] = files['index.html'].replace(tag, b'<script src="$WEBAPIS/webapis/webapis.js"></script>\n' + tag)

    sym = symbol()
    b = io.BytesIO()
    fit(sym, 512, 512, 1.0).save(b, 'PNG', optimize=True)
    files['img/symbol.png'] = b.getvalue()
    if tizen:
        b = io.BytesIO()
        tizen_icon(sym).save(b, 'PNG', optimize=True)
        files['icon.png'] = b.getvalue()
        pkg = a.tizen_pkg or tizen_pkg_id(a.id)
        appn = (''.join(c for c in (a.tizen_app or a.name) if c.isalnum()) or 'App')[:40]
        assert len(pkg) == 10 and pkg.isalnum(), 'Samsung package id must be 10 letters/digits'
        files['config.xml'] = TIZEN_CONFIG.format(wid=escape((site or 'http://localhost') + '/' + appn, {'"': '&quot;'}),
                                                  version=escape(a.version), pkg=pkg, app=appn, name=escape(a.name)).encode('utf-8')
        write_folder(a.folder, files)
        os.makedirs(a.out, exist_ok=True)
        path = os.path.join(a.out, a.file or appn + '.wgt')
        with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
            for rel in sorted(files):
                z.writestr(rel, files[rel])
        print('%s  %s.%s %s  (%d files, %.0f KB, not signed)' % (path, pkg, appn, a.version, len(files), os.path.getsize(path) / 1024))
        return
    for name, size in (('icon.png', 80), ('largeIcon.png', 130)):
        b = io.BytesIO()
        launcher_icon(sym, size).save(b, 'PNG', optimize=True)
        files[name] = b.getvalue()

    appinfo = {
        'id': app_id, 'version': a.version, 'vendor': vendor, 'type': 'web', 'main': 'index.html', 'title': a.name,
        'icon': 'icon.png', 'largeIcon': 'largeIcon.png', 'bgColor': '#0B0708',
        'resolution': a.resolution, 'disableBackHistoryAPI': True, 'handlesRelaunch': False,
    }
    files['appinfo.json'] = json.dumps(appinfo, indent=2).encode('utf-8')
    write_folder(a.folder, files)

    app_dir = 'usr/palm/applications/%s/' % app_id
    pkg_dir = 'usr/palm/packages/%s/' % app_id
    entries = [('usr/', None), ('usr/palm/', None), ('usr/palm/applications/', None), ('usr/palm/packages/', None),
               (app_dir, None), (pkg_dir, None)]
    dirs = set()
    for rel in sorted(files):
        parts = rel.split('/')[:-1]
        for i in range(1, len(parts) + 1):
            d = app_dir + '/'.join(parts[:i]) + '/'
            if d not in dirs:
                dirs.add(d)
                entries.append((d, None))
        entries.append((app_dir + rel, files[rel]))
    packageinfo = {'app': app_id, 'id': app_id, 'loc_name': a.name, 'package_format_version': 2, 'vendor': vendor, 'version': a.version}
    entries.append((pkg_dir + 'packageinfo.json', json.dumps(packageinfo, indent=2).encode('utf-8')))
    data_tgz = tar_bytes(entries)
    size = sum(len(d) for _n, d in entries if d)
    control = ('Package: %s\nVersion: %s\nSection: misc\nPriority: optional\nArchitecture: all\nInstalled-Size: %d\n'
               'Maintainer: N/A <nobody@example.com>\nDescription: This is a webOS application.\n'
               'webOS-Package-Format-Version: 2\nwebOS-Packager-Version: x.y.x\n') % (app_id, a.version, size)
    control_tgz = tar_bytes([('control', control.encode('utf-8'))])
    now = int(time.time())
    ipk = b'!<arch>\n' + ar_member('debian-binary', b'2.0\n', now) + ar_member('control.tar.gz', control_tgz, now) + \
        ar_member('data.tar.gz', data_tgz, now)
    os.makedirs(a.out, exist_ok=True)
    name = a.file or (''.join(c for c in a.name if c.isalnum()) or 'App') + '.ipk'
    path = os.path.join(a.out, name)
    with open(path, 'wb') as f:
        f.write(ipk)
    print('%s  %s %s  (%d files, %.0f KB)' % (path, app_id, a.version, len(files), len(ipk) / 1024))


if __name__ == '__main__':
    main()
