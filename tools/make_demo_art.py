#!/usr/bin/env python3
"""Posters, backdrops and channel logos for the LG app's built-in demo content (tvlite/img/demo/).
Drawn here (no pictures from other sites), so they are always there and always sharp.
Run once from the repository root: python3 tools/make_demo_art.py"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = 'tvlite/img/demo'
F = '/usr/share/fonts/opentype/inter/Inter-%s.otf'


def font(weight, size):
    return ImageFont.truetype(F % weight, size)


def gradient(w, h, top, bottom, glow=None):
    img = Image.new('RGB', (w, h), bottom)
    d = ImageDraw.Draw(img)
    for y in range(h):
        k = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * k) for i in range(3)))
    if glow:
        g = Image.new('L', (w, h), 0)
        r = int(min(w, h) * 0.55)
        ImageDraw.Draw(g).ellipse([glow[0] * w - r, glow[1] * h - r, glow[0] * w + r, glow[1] * h + r], fill=150)
        g = g.filter(ImageFilter.GaussianBlur(min(w, h) * 0.18))
        img = Image.composite(Image.new('RGB', (w, h), glow[2]), img, g)
    return img


def wrap(d, text, f, width):
    words, lines, cur = text.split(), [], ''
    for wd in words:
        t = (cur + ' ' + wd).strip()
        if d.textlength(t, font=f) <= width:
            cur = t
        else:
            lines.append(cur)
            cur = wd
    if cur:
        lines.append(cur)
    return lines


def badge(d, x, y, text, fill=(227, 38, 47), size=30):
    f = font('ExtraBold', size)
    w = d.textlength(text, font=f)
    d.rounded_rectangle([x, y, x + w + size * 0.9, y + size * 1.55], radius=size * 0.35, fill=fill)
    d.text((x + size * 0.45, y + size * 0.77), text, font=f, fill='white', anchor='lm')


def poster(name, title, sub, tag, top, bottom, glow):
    w, h = 400, 600
    img = gradient(w, h, top, bottom, glow)
    d = ImageDraw.Draw(img)
    # Soft diagonal light.
    lay = Image.new('L', (w, h), 0)
    ImageDraw.Draw(lay).polygon([(0, 0), (w * 0.75, 0), (0, h * 0.55)], fill=40)
    img = Image.composite(Image.new('RGB', (w, h), (255, 255, 255)), img, lay.filter(ImageFilter.GaussianBlur(30)))
    d = ImageDraw.Draw(img)
    badge(d, 24, 24, tag)
    # The title sits in the middle: the app writes the name over the bottom of every cover.
    ft = font('ExtraBold', 52)
    lines = wrap(d, title, ft, w - 64)
    block = len(lines) * 60 + 44
    y = int(h * 0.45 - block / 2)
    shade = Image.new('L', (w, h), 0)
    ImageDraw.Draw(shade).rectangle([0, y - 34, w, y + block + 24], fill=110)
    img = Image.composite(Image.new('RGB', (w, h), (6, 4, 5)), img, shade.filter(ImageFilter.GaussianBlur(34)))
    d = ImageDraw.Draw(img)
    for i, line in enumerate(lines):
        d.text((w / 2, y + i * 60), line, font=ft, fill='white', anchor='ma')
    d.text((w / 2, y + len(lines) * 60 + 14), sub, font=font('SemiBold', 24), fill=(214, 218, 227), anchor='ma')
    img.save(os.path.join(OUT, name + '.jpg'), quality=88, optimize=True)
    # Wide picture for the details page.
    bw, bh = 1280, 720
    back = gradient(bw, bh, top, bottom, (0.72, 0.4, glow[2]))
    bd = ImageDraw.Draw(back)
    big = font('ExtraBold', 150)
    bd.text((bw - 60, bh - 90), tag, font=big, fill=tuple(min(255, c + 28) for c in bottom), anchor='rs')
    back = back.filter(ImageFilter.GaussianBlur(2))
    back.save(os.path.join(OUT, name + '-wide.jpg'), quality=82, optimize=True)


def logo(name, big, small, top, bottom):
    s = 256
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    m = Image.new('L', (s, s), 0)
    ImageDraw.Draw(m).rounded_rectangle([8, 8, s - 9, s - 9], radius=56, fill=255)
    img.paste(gradient(s, s, top, bottom).convert('RGBA'), (0, 0), m)
    d = ImageDraw.Draw(img)
    d.text((s / 2, s * 0.44), big, font=font('ExtraBold', 96 if len(big) <= 3 else 70), fill='white', anchor='mm')
    d.text((s / 2, s * 0.76), small, font=font('Bold', 30), fill=(255, 255, 255, 230), anchor='mm')
    img.save(os.path.join(OUT, name + '.png'), optimize=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    red, ink = (196, 30, 40), (14, 8, 10)
    poster('bbb', 'Big Buck Bunny', '2008 · Animation · Ultra HD', '4K UHD', (70, 140, 60), (10, 24, 12), (0.3, 0.35, (150, 200, 90)))
    poster('tos', 'Tears of Steel', '2012 · Sci-Fi', 'HD', (40, 70, 110), (6, 10, 18), (0.6, 0.3, (60, 120, 200)))
    poster('skate', 'Skate in Slow Motion', 'Phantom Flex camera · 4K', '4K UHD', (120, 70, 30), (16, 10, 6), (0.4, 0.35, (230, 140, 60)))
    poster('sintel', 'Sintel', '2010 · Fantasy', 'FULL HD', (120, 40, 30), (14, 6, 5), (0.5, 0.3, (220, 90, 50)))
    poster('ed', 'Elephants Dream', '2006 · Sci-Fi', 'FULL HD', (60, 60, 90), (8, 8, 14), (0.5, 0.3, (130, 120, 200)))
    poster('bbbhd', 'Big Buck Bunny', '2008 · Full HD · 60 fps', 'FULL HD', (80, 120, 50), (12, 20, 10), (0.4, 0.3, (170, 210, 100)))
    poster('blender', 'Open Movie Collection', 'Blender Foundation · 4 films', 'SERIES', (90, 30, 40), ink, (0.5, 0.35, red))
    poster('uhd', '4K UHD Showcase', 'Picture quality demo', 'SERIES', (30, 30, 36), ink, (0.5, 0.35, (227, 38, 47)))
    logo('ch-hd60', 'HD', '60 FPS', (227, 38, 47), (110, 12, 18))
    logo('ch-4k', '4K', 'UHD', (200, 40, 60), (90, 14, 30))
    logo('ch-skate', '4K', 'ACTION', (230, 130, 40), (120, 50, 10))
    logo('ch-movies', 'HD', 'MOVIES', (60, 110, 200), (20, 30, 90))
    logo('ch-live', 'LIVE', '24/7', (227, 38, 47), (40, 8, 12))
    logo('ch-test', 'TEST', 'LIVE', (90, 90, 100), (25, 25, 30))
    logo('ch-hd', 'HD', 'DEMO', (40, 150, 120), (10, 60, 50))
    logo('ch-pattern', 'HLS', 'TEST', (70, 90, 140), (16, 20, 40))
    print('demo pictures in', OUT, sorted(os.listdir(OUT)))


if __name__ == '__main__':
    main()
