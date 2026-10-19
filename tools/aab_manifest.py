"""Prints the AndroidManifest.xml of an Android App Bundle as readable lines (not part of the app).

An .aab keeps its manifest as a protocol buffer (base/manifest/AndroidManifest.xml). This reads
that without bundletool or aapt2: one line per element with its attributes, indented by depth.
Used by the Google Play workflow to list the target SDK and the permissions in the release notes.

    unzip -q app.aab base/manifest/AndroidManifest.xml -d x
    python3 tools/aab_manifest.py x/base/manifest/AndroidManifest.xml
"""
import sys


def varint(b, i):
    r = s = 0
    while True:
        c = b[i]
        i += 1
        r |= (c & 0x7f) << s
        s += 7
        if c < 0x80:
            return r, i


def fields(b):
    i, out = 0, []
    while i < len(b):
        key, i = varint(b, i)
        f, t = key >> 3, key & 7
        if t == 0:
            v, i = varint(b, i)
            out.append((f, v))
        elif t == 2:
            n, i = varint(b, i)
            out.append((f, b[i:i + n]))
            i += n
        elif t == 5:
            out.append((f, b[i:i + 4]))
            i += 4
        elif t == 1:
            out.append((f, b[i:i + 8]))
            i += 8
        else:
            raise ValueError('unknown wire type %d' % t)
    return out


def text(x):
    try:
        return x.decode('utf-8')
    except (AttributeError, UnicodeDecodeError):
        return None


# aapt2 Resources.proto: XmlNode 1=element; XmlElement 3=name 4=attribute 5=child;
# XmlAttribute 2=name 3=value.
def element(b, depth):
    name, attrs, kids = None, [], []
    for f, v in fields(b):
        if f == 3:
            name = text(v)
        elif f == 4:
            a = {k: text(val) for k, val in fields(v) if k in (2, 3)}
            attrs.append('%s=%r' % (a.get(2), a.get(3)))
        elif f == 5:
            kids.append(v)
    print('  ' * depth + '<%s %s>' % (name, ' '.join(attrs)))
    for k in kids:
        for f, v in fields(k):
            if f == 1:
                element(v, depth + 1)


def main():
    data = open(sys.argv[1], 'rb').read()
    for f, v in fields(data):
        if f == 1:
            element(v, 0)


if __name__ == '__main__':
    main()
