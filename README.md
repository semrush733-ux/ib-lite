# B1G - IPTV player for Fire TV / Android TV

Flutter app, package `com.b1g.b1gtv`. It is a player only: it contains no channels and no server
address. The customer signs in with the details of their IPTV account (Xtream Codes API).

| | |
|---|---|
| Sign in | **Xtream Codes** (server address, username, password) or **M3U link** (any M3U / M3U8 playlist address) |
| Live TV | Categories, channel list, search, favourites, TV guide (now / next) |
| Movies / Series | Poster grid, seasons and episodes, resume where you stopped, next episode starts by itself |
| Player | ExoPlayer with hardware decoding, automatic reconnect, `.ts` with fallback to `.m3u8` |
| Remote | Everything works with the D-pad. Hold OK = favourite. In the player: Up / Down = channel, Left / Right = jump |

## Where the build is

Every push to the branch `b1g-tv` builds the app in the cloud (`.github/workflows/b1g-tv.yml`) and
replaces the file in this release:

`https://github.com/semrush733-ux/builder2343/releases/tag/b1g-latest` -> `B1G.apk`

The release notes hold the build report and the result of the emulator test. Screenshots of that
test are on the branch `ci-smoke-b1g`.

## Windows (EXE)

`.github/workflows/windows.yml` builds the same app for Windows 10 / 11 (64-bit) on every push
and publishes the release `windows-latest`:

- `IBOLitePlayer-Setup.exe` - installer for the current user (no administrator question), Start
  menu and desktop shortcut;
- `IBOLitePlayer-Windows.zip` - portable: unzip and start `IBOLitePlayer.exe`;
- `windows-update.json` - the app checks it; "Update now" downloads the new installer, runs it
  silently and the new version opens by itself (login, playlists and favourites stay).

Keyboard like the remote: arrows and Enter, Esc = Back, F11 or Alt+Enter = full screen; the
mouse works everywhere. The Windows part of the app's device channel is
`windows_extra/b1g_device.cpp` (machine id - only a hash is sent - and MAC for the website,
network and Wi-Fi details, keep the screen on, full screen); `tools/windows_setup.py` adds it to
the project Flutter creates. Not in the Windows app: the VPN and voice search (Android only).

Before publishing, the test build is opened on the Windows build machine and driven with the
keyboard against the mock IPTV server (`ci/smoke_windows.py`). Its result and screenshots are on
the branch `ci-win`. The program is not code-signed: SmartScreen may ask "Run anyway" once.

## Lock the app to one server

Put the server address into `config/server.txt` (one line, for example `http://example.com:8080`)
and push. The sign-in screen then only asks for username and password.

## Signing

Without signing secrets every build is signed with a new throw-away key: the APK installs, but a
newer build cannot be installed over an older one (uninstall first). Before the APK goes to
customers, add a keystore as repository secrets (`ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) and keep that keystore
safe - updates must always be signed with the same key.

## The B1G website (licence, default server, updates)

The app talks to the WordPress plugin "B1G App Platform" (`lib/backend.dart`, address in
`kApiBase`, override with `--dart-define=B1G_API_BASE=...`):

- device registration, trial / licence check and activation code, QR code to add a playlist;
- `GET app/config`: a default IPTV server (the sign-in screen then asks for username and
  password only; Xtream Codes and M3U link stay as tabs) and the newest app version
  ("Update available" with **Update now**, which downloads the APK and opens the installer).

What the website has to provide is written down in `docs/WEBSITE-CHANGES.md`.

## Project layout

```
lib/                    the app (Dart)
  xtream.dart           Xtream Codes API and the common Source interface
  m3u.dart              M3U playlist reader
  store.dart            saved login, favourites, resume positions
  backend.dart          the B1G website: licence, default server, app updates
  screens/              login, home, browse, series, player, device (QR / activation), update
android_overlay/        TV manifest, activity, icons and banner (copied over Flutter's Android template)
config/server.txt       optional fixed server address
ci/                     mock IPTV server and emulator test
test/                   unit tests
```

## Not in this version

A full-week TV guide grid, subtitles / audio-track menu, catch-up, parental PIN,
iPhone / Samsung / LG builds.

With an M3U link the playlist is downloaded on every app start. A playlist has no TV guide and no
series pages (every episode is its own entry). A link from an Xtream Codes panel
(`.../get.php?username=..&password=..`) is recognised and used through the panel's API instead,
which gives the TV guide and series pages back.
