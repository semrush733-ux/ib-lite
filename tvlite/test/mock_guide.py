#!/usr/bin/env python3
"""The mock IPTV server (ci/mock_server.py) with a TV guide, for the TV Guide test (not part of the app).

Adds to the Xtream mock: the whole guide of a channel (get_simple_data_table) from 6 hours ago to a
day ahead in half-hour and hour programmes, recordings for channel 1 (tv_archive, has_archive) and
the recording addresses (/timeshift/..., /streaming/timeshift.php). And for M3U playlists: an XMLTV
guide, plain (/epg.xml) and packed (/epg.xml.gz), and a playlist that names it (/guide.m3u).

    python3 tvlite/test/mock_guide.py 8787
"""
import base64
import datetime
import gzip
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, 'ci'))
import mock_server as M  # noqa: E402  (reads the port from sys.argv[1])

PORT = M.PORT
HOST = 'http://127.0.0.1:%d' % PORT
SLOT = 1800

# Channel 1 keeps recordings (catch-up); the others do not.
for row in M.LIVE:
    row['tv_archive'] = 1 if str(row['stream_id']) == '1' else 0


def b64(text):
    return base64.b64encode(text.encode('utf-8')).decode()


def slots(sid):
    """The same programmes every time: from 6 hours ago to a day ahead (half hours and hours)."""
    now = int(time.time())
    t = now - now % SLOT - 12 * SLOT
    out, k = [], 0
    while t < now + 48 * SLOT:
        length = SLOT * (2 if k % 3 == 1 else 1)
        out.append((t, t + length, 'Ch%s show %d' % (sid, k), 'What happens in show %d of channel %s.' % (k, sid)))
        t += length
        k += 1
    return out


def full_epg(sid):
    rows = []
    now = int(time.time())
    for i, (s, e, title, desc) in enumerate(slots(sid)):
        rows.append({'id': str(i), 'epg_id': str(i), 'title': b64(title), 'description': b64(desc),
                     'start': time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(s)),
                     'start_timestamp': str(s), 'stop_timestamp': str(e),
                     'now_playing': 1 if s <= now < e else 0, 'has_archive': 1 if sid == '1' and e <= now else 0})
    return {'epg_listings': rows}


def xmltv():
    """An XMLTV guide for the M3U playlist's channels (tvg-id one and two) and one it does not have."""
    def ts(t):
        return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime('%Y%m%d%H%M%S +0000')
    parts = ['<?xml version="1.0" encoding="UTF-8"?>', '<tv generator-info-name="mock">']
    for cid in ('one', 'two', 'elsewhere'):
        parts.append('<channel id="%s"><display-name>%s</display-name></channel>' % (cid, cid))
    for cid in ('one', 'two', 'elsewhere'):
        for s, e, title, desc in slots(cid):
            parts.append('<programme start="%s" stop="%s" channel="%s">\n  <title lang="en">XML %s &amp; more</title>\n'
                         '  <desc lang="en">%s</desc>\n</programme>' % (ts(s), ts(e), cid, title, desc))
    parts.append('</tv>')
    return '\n'.join(parts).encode('utf-8')


PLAYLIST = '#EXTM3U url-tvg="%s/epg.xml.gz"\n' % HOST + M.PLAYLIST.split('\n', 1)[1].replace(M.BASE, HOST)

api = M.Handler.api
get = M.Handler.do_GET


def api_with_guide(self, q):
    action, sid = q.get('action'), q.get('stream_id', '')
    if q.get('username') == 'demo' and q.get('password') == 'demo' and action in ('get_simple_data_table', 'get_short_epg'):
        if sid not in ('1', '2', '5'):
            return self.send_json({'epg_listings': []})
        rows = full_epg(sid)['epg_listings']
        if action == 'get_short_epg':  # now and what comes next, as a server gives it
            now = int(time.time())
            rows = [r for r in rows if int(r['stop_timestamp']) > now][:int(q.get('limit') or 4)]
        return self.send_json({'epg_listings': rows})
    return api(self, q)


def get_with_guide(self):
    path = self.path.split('?')[0]
    if path.startswith('/timeshift/') or path == '/streaming/timeshift.php':
        return self.send_file('movie.mp4', 'video/mp4')
    if path in ('/epg.xml', '/epg.xml.gz'):
        body = xmltv()
        if path.endswith('.gz'):
            body = gzip.compress(body)
        self.send_response(200)
        self.send_header('Content-Type', 'application/gzip' if path.endswith('.gz') else 'text/xml')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)
        return None
    if path == '/guide.m3u':
        return self.send_text(PLAYLIST, 'audio/x-mpegurl')
    return get(self)


M.Handler.api = api_with_guide
M.Handler.do_GET = get_with_guide

if __name__ == '__main__':
    print('mock IPTV server with a TV guide on port %d' % PORT, flush=True)
    M.ThreadingHTTPServer(('0.0.0.0', PORT), M.Handler).serve_forever()
