"""Builds tvlite/fonts/icons2.woff: extra icons for the light TV app (not part of the app).

fonts/icons.woff holds the icons the Android app uses (Flutter's Material Icons, rounded). The
icons added later come from Google's "Material Icons Round" font, which looks the same, and live
in this second, small font. The page lists both fonts ('Icons', 'Icons2'), so the browser takes
each icon from the font that has it. Every icon gets its own private code from U+F5000 on.

    python3 tvlite/tools/make_icons2.py <path to MaterialIconsRound-Regular.otf>

(the font is in github.com/google/material-design-icons, folder font/). Prints the lines for
the ICONS table in js/core.js.
"""
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = 0xF5000

# name in the app -> glyph name in Material Icons Round. Keep the order: the codes follow it.
ICONS = [
    ('bell', 'notifications_active'), ('bellOn', 'notifications'), ('bellOff', 'notifications_off'),
    ('bellAdd', 'notification_add'), ('subs', 'subtitles'), ('subsOff', 'subtitles_off'),
    ('textSize', 'format_size'), ('textColor', 'format_color_text'), ('textFields', 'text_fields'),
    ('opacity', 'opacity'), ('netCheck', 'network_check'), ('router', 'router'), ('lan', 'lan'),
    ('signal', 'signal_wifi_4_bar'), ('tower', 'cell_tower'), ('download', 'download'), ('upload', 'upload'),
    ('storage', 'storage'), ('sd', 'sd_storage'), ('sweep', 'delete_sweep'), ('devinfo', 'perm_device_information'),
    ('devices', 'devices'), ('cached', 'cached'), ('wallpaper', 'wallpaper'), ('palette', 'palette'),
    ('landscape', 'landscape'), ('dark', 'dark_mode'), ('style', 'style'), ('sparkle', 'auto_awesome'),
    ('timer', 'timer'), ('timerOff', 'timer_off'), ('bedtime', 'bedtime'), ('clock', 'schedule'),
    ('event', 'event'), ('eventOk', 'event_available'), ('today', 'today'), ('month', 'calendar_month'),
    ('upcoming', 'upcoming'), ('later', 'watch_later'), ('restart', 'restart_alt'), ('timeline', 'view_timeline'),
    ('grid', 'grid_view'), ('tune', 'tune'), ('theaters', 'theaters'), ('group', 'group'), ('groups', 'groups'),
    ('hd', 'hd'), ('face', 'face'), ('actors', 'recent_actors'), ('movies', 'local_movies'),
    ('ondemand', 'ondemand_video'), ('movieFilter', 'movie_filter'), ('ctv', 'connected_tv'), ('livetv', 'live_tv'),
    ('okCircle', 'check_circle'), ('doneAll', 'done_all'), ('block', 'block'), ('toggleOn', 'toggle_on'),
    ('toggleOff', 'toggle_off'), ('sensors', 'sensors'),
]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = TTFont(sys.argv[1])
    by_name = {}
    for code, glyph in src.getBestCmap().items():
        by_name.setdefault(glyph, code)
    missing = [g for _, g in ICONS if g not in by_name]
    if missing:
        sys.exit('not in the font: ' + ', '.join(missing))

    # Keep only these glyphs (their own codes first), then give them the app's codes.
    opts = subset.Options()
    opts.layout_features = []
    opts.name_IDs = [0, 1, 2, 3, 4, 5, 6]
    opts.notdef_outline = True
    opts.flavor = 'woff'
    sub = subset.Subsetter(options=opts)
    sub.populate(unicodes=[0x20] + [by_name[g] for _, g in ICONS])
    sub.subset(src)
    # As in icons.woff: the space in the format 4 tables, everything in a format 12 table
    # (the codes are above U+FFFF).
    space = src.getBestCmap()[0x20]
    mapping = {0x20: space}
    for i, (_, g) in enumerate(ICONS):
        mapping[BASE + i] = g
    from fontTools.ttLib.tables._c_m_a_p import cmap_format_12
    big = cmap_format_12(12)
    big.platformID, big.platEncID, big.language = 3, 10, 0
    big.cmap = mapping
    tables = [t for t in src['cmap'].tables if t.format == 4]
    for t in tables:
        t.cmap = {0x20: space}
    src['cmap'].tables = tables + [big]
    src['name'].setName('Icons2', 1, 3, 1, 0x409)
    src['name'].setName('Icons2', 4, 3, 1, 0x409)
    src.flavor = 'woff'
    out = os.path.join(ROOT, 'fonts', 'icons2.woff')
    src.save(out)
    print('%s: %d icons, %d bytes' % (out, len(ICONS), os.path.getsize(out)))
    line = []
    for i, (name, _) in enumerate(ICONS):
        line.append("%s: '%x'" % (name, BASE + i))
    print(', '.join(line))


if __name__ == '__main__':
    main()
