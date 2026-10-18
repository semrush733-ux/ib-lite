"""Pre-composes the light TV app's full-screen backgrounds into one opaque picture each.

The Home and Connect screens used a picture plus one or two see-through colour layers (wash,
vignette) on top. Low-cost TVs (Samsung Crystal UHD, older LG) blend every full-screen layer on
every frame, which made the start animation and the fade into the app stutter. Here Chromium
draws exactly the CSS the app used, once, and the result is saved as a single WebP the TV can just
show:

    tvlite/img/home_full.webp     .hm-bg picture + .hm-wash + .hm-vig
    tvlite/img/connect_full.webp  .cn-bg picture + .cn-wash

Run from the repository root after changing assets/home_bg.webp or the colours below:
    python3 tvlite/tools/make_tv_backgrounds.py
"""
import base64, io, os

from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, 'assets/home_bg.webp')
OUT = os.path.join(ROOT, 'tvlite/img')

HOME_LAYERS = [
    'linear-gradient(to bottom, rgba(44,11,15,0.92) 0%, rgba(54,16,22,0.82) 50%, rgba(20,6,8,0.94) 100%)',
    'radial-gradient(ellipse 1400px 1000px at 60% 35%, rgba(0,0,0,0), rgba(0,0,0,0.6))',
]
CONNECT_LAYERS = [
    'linear-gradient(135deg, rgba(64,10,16,0.95), rgba(26,6,8,0.9))',
]

PAGE = '''<!DOCTYPE html><html><head><style>
html, body { margin: 0; width: 1920px; height: 1080px; background: #0B0708; overflow: hidden; }
div { position: absolute; left: 0; top: 0; width: 1920px; height: 1080px; }
.pic { background: url(%s) center / cover no-repeat; }
</style></head><body><div class="pic"></div>%s</body></html>'''


def render(page, layers, name):
    src = 'data:image/webp;base64,' + base64.b64encode(open(SRC, 'rb').read()).decode()
    html = PAGE % (src, ''.join('<div style="background: %s"></div>' % l for l in layers))
    page.set_content(html)
    page.wait_for_timeout(300)
    png = page.screenshot(clip={'x': 0, 'y': 0, 'width': 1920, 'height': 1080})
    im = Image.open(io.BytesIO(png)).convert('RGB')
    path = os.path.join(OUT, name)
    im.save(path, 'WEBP', quality=82, method=6)
    print('%s  %dx%d  %.0f KB' % (path, im.size[0], im.size[1], os.path.getsize(path) / 1024))


def main():
    with sync_playwright() as p:
        b = p.chromium.launch()
        page = b.new_page(viewport={'width': 1920, 'height': 1080})
        render(page, HOME_LAYERS, 'home_full.webp')
        render(page, CONNECT_LAYERS, 'connect_full.webp')
        b.close()


if __name__ == '__main__':
    main()
