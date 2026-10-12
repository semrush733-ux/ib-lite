#!/usr/bin/env python3
"""Before a build: takes the app icon (logo symbol) set in the website's admin
(Lite Player -> Settings -> App look) so the launcher icons use it.
Usage: python3 tools/fetch_brand.py https://your-site.com   (does nothing when empty or unreachable)"""
import io
import json
import sys
import urllib.request

from PIL import Image

site = (sys.argv[1] if len(sys.argv) > 1 else '').rstrip('/')
if not site:
    sys.exit(0)
try:
    with urllib.request.urlopen(site + '/wp-json/b1g/v1/app/config', timeout=20) as r:
        cfg = json.load(r).get('config', {})
    icon = ((cfg.get('brand') or {}).get('icon') or '').strip()
    if not icon:
        print('website has no app icon set: keeping brand/icon.png')
        sys.exit(0)
    with urllib.request.urlopen(icon, timeout=30) as r:
        data = r.read(20 * 1024 * 1024)
    img = Image.open(io.BytesIO(data)).convert('RGBA')
    if min(img.size) < 256:
        print('website app icon is too small (%dx%d): keeping brand/icon.png' % img.size)
        sys.exit(0)
    img.save('brand/icon.png')
    print('app icon taken from the website: %s (%dx%d)' % ((icon,) + img.size))
except Exception as e:  # never break the build because of the website
    print('could not read the app icon from the website (%s): keeping brand/icon.png' % e)
