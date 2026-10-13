#!/usr/bin/env python3
"""Before a build: takes the app icon (logo symbol) and the app name under the icon set in the
website's admin (Lite Player -> Settings -> App look) so the launcher uses them.
Writes brand/site_label.txt (the name, when set) and out/brand_sig.txt (what this build used,
so the hourly check knows when the website changed).
Usage: python3 tools/fetch_brand.py https://your-site.com   (does nothing when empty or unreachable)"""
import io
import json
import os
import re
import sys
import urllib.request

from PIL import Image

site = (sys.argv[1] if len(sys.argv) > 1 else '').rstrip('/')
if not site:
    sys.exit(0)
try:
    with urllib.request.urlopen(site + '/wp-json/b1g/v1/app/config', timeout=20) as r:
        cfg = json.load(r).get('config', {})
    brand = cfg.get('brand') or {}
    icon = (brand.get('icon') or '').strip()
    label = (brand.get('app_label') or '').strip()
    # Letters, digits, spaces and a few signs only (it goes into the Android manifest).
    label = re.sub(r'[^\w .()+-]', '', label.replace('&', 'and'), flags=re.UNICODE)
    label = re.sub(r'\s+', ' ', label).strip()[:30]
    os.makedirs('out', exist_ok=True)
    with open('out/brand_sig.txt', 'w') as f:
        f.write('%s|%s' % (label, icon))
    if label:
        with open('brand/site_label.txt', 'w') as f:
            f.write(label)
        print('app name under the icon from the website: %s' % label)
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
