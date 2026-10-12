#!/usr/bin/env python3
"""Makes every launcher icon, TV banner, splash logo and in-app logo from
brand/icon.png (the logo SYMBOL only, transparent, ideally 1024 x 1024 or larger)
and brand/logo.png (wide logo for inside the app).

Rules, the same on every device:
  * only the symbol is used for icons and banners - never the app name or other text;
  * the symbol is trimmed to its visible pixels and centred, never stretched or cropped;
  * every picture the system can show on its own colour (Fire TV tiles, phone launchers that
    do not mask, TV banners) gets an opaque brand background, so no grey box appears behind it;
  * adaptive icons (Android 8+ phones, tablets, Google TV) use an opaque background layer and keep
    the symbol inside the 66 dp safe zone, so round, squircle and square masks never cut it;
  * every density up to xxxhdpi (4K TVs) is drawn from the large source, so it stays sharp.

Also writes store_assets/ (Amazon Appstore / Fire TV, Google Play, Samsung Tizen icons).
Run from the repository root (the build does this before compiling)."""
import os
import shutil
from PIL import Image, ImageDraw, ImageFilter

RES = 'android_overlay/app/src/main/res'
DENS = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def brand_value(key, default):
    try:
        for line in open('brand/brand.txt', encoding='utf-8'):
            if line.startswith(key + '='):
                v = line.split('=', 1)[1].strip()
                return v or default
    except OSError:
        pass
    return default


def hex_rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


BG = hex_rgb(brand_value('ICON_BG', '#140A0D'))       # dark brand background behind the symbol
GLOW = hex_rgb(brand_value('ICON_GLOW', '#E3262F'))   # soft light behind the symbol on banners

SYMBOL = Image.open('brand/icon.png').convert('RGBA')
LOGO = Image.open('brand/logo.png').convert('RGBA')
_bb = SYMBOL.getbbox()
if _bb:
    SYMBOL = SYMBOL.crop(_bb)  # only the visible symbol, so centring is exact
if max(SYMBOL.size) < 512:
    print('WARNING: brand/icon.png is small (%dx%d); use 1024 x 1024 or larger for sharp TV icons' % SYMBOL.size)


def fit(img, w, h, scale):
    """[img] scaled (keeping its shape) so its longer side fills [scale] of the box, centred."""
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    k = min(w * scale / img.width, h * scale / img.height)
    src = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
    out.alpha_composite(src, ((w - src.width) // 2, (h - src.height) // 2))
    return out


def background(w, h, glow=True, radius=0):
    """Opaque brand background with a soft glow in the middle (what the symbol sits on)."""
    bg = Image.new('RGBA', (w, h), BG + (255,))
    if glow:
        g = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(g)
        r = min(w, h) * 0.42
        d.ellipse([w / 2 - r, h / 2 - r, w / 2 + r, h / 2 + r], fill=GLOW + (60,))
        g = g.filter(ImageFilter.GaussianBlur(min(w, h) * 0.18))
        bg.alpha_composite(g)
    if radius:
        mask = Image.new('L', (w, h), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=255)
        out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        out.paste(bg, (0, 0), mask)
        return out
    return bg


def on_bg(w, h, scale, radius=0, circle=False):
    img = background(w, h, radius=radius)
    if circle:
        mask = Image.new('L', (w, h), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, w - 1, h - 1], fill=255)
        c = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        c.paste(img, (0, 0), mask)
        img = c
    img.alpha_composite(fit(SYMBOL, w, h, scale))
    return img


def mono(img):
    """White silhouette of the symbol (Android 13 themed icons)."""
    white = Image.new('RGBA', img.size, (255, 255, 255, 0))
    white.putalpha(img.getchannel('A'))
    return white


for name, k in DENS.items():
    d = '%s/mipmap-%s' % (RES, name)
    os.makedirs(d, exist_ok=True)
    s = round(48 * k)
    # Older launchers and Fire OS: an opaque tile, so no grey box shows around the symbol.
    on_bg(s, s, 0.70, radius=round(s * 0.2)).save(d + '/ic_launcher.png')
    on_bg(s, s, 0.62, circle=True).save(d + '/ic_launcher_round.png')
    # Adaptive icon (108 dp): the symbol stays inside the 66 dp safe zone of any mask shape.
    fg = round(108 * k)
    fit(SYMBOL, fg, fg, 0.50).save(d + '/ic_launcher_foreground.png')
    mono(fit(SYMBOL, fg, fg, 0.50)).save(d + '/ic_launcher_monochrome.png')
    background(fg, fg).convert('RGB').save(d + '/ic_launcher_background.png')

    dd = '%s/drawable-%s' % (RES, name)
    os.makedirs(dd, exist_ok=True)
    # Start screen: the symbol at its own size on the dark start colour.
    sp = round(120 * k)
    fit(SYMBOL, sp, sp, 1.0).save(dd + '/splash_logo.png')
    # TV banner (Android TV, Google TV, Fire TV): 320 x 180 dp, opaque, symbol only, centred.
    bw, bh = round(320 * k), round(180 * k)
    ban = background(bw, bh)
    ban.alpha_composite(fit(SYMBOL, bw, bh, 0.62))
    ban.convert('RGB').save(dd + '/tv_banner.png')

# Adaptive icon: background picture instead of a flat colour.
os.makedirs(RES + '/mipmap-anydpi-v26', exist_ok=True)
for icon in ('ic_launcher', 'ic_launcher_round'):
    with open('%s/mipmap-anydpi-v26/%s.xml' % (RES, icon), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
                '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
                '</adaptive-icon>\n')

os.makedirs('assets', exist_ok=True)
fit(SYMBOL, 1024, 1024, 1.0).save('assets/symbol.png')
shutil.copyfile('brand/logo.png', 'assets/logo.png')
print('brand pictures written')

# Pictures for app stores and other TV systems (uploaded with the build).
os.makedirs('store_assets', exist_ok=True)
on_bg(512, 512, 0.70).convert('RGB').save('store_assets/icon-512.png')               # Fire TV / Amazon Appstore, Google Play
on_bg(114, 114, 0.70).convert('RGB').save('store_assets/icon-114.png')               # Amazon Appstore small icon
b = background(1280, 720)
b.alpha_composite(fit(SYMBOL, 1280, 720, 0.62))
b.convert('RGB').save('store_assets/fire-tv-banner-1280x720.png')                    # Fire TV / Android TV banner
b = background(1920, 1080)
b.alpha_composite(fit(SYMBOL, 1920, 1080, 0.5))
b.convert('RGB').save('store_assets/tv-background-1920x1080.png')
fit(SYMBOL, 512, 512, 0.86).save('store_assets/tizen-icon-512.png')                   # Samsung Tizen (config.xml <icon>)
on_bg(512, 423, 0.66).convert('RGB').save('store_assets/tizen-icon-512x423.png')       # Samsung Seller Office TV icon
print('store pictures written')

# Browser version: favicon and home-screen icons.
for root, _, files in os.walk('web_brand'):
    for f in files:
        if not f.endswith('.png'):
            continue
        p = os.path.join(root, f)
        w, h = Image.open(p).size
        if 'maskable' in f:
            on_bg(w, h, 0.55).save(p)
        else:
            fit(SYMBOL, w, h, 0.96).save(p)
print('web icons written')
