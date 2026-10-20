### Windows test (keyboard like a remote, mock IPTV server)

15 checks, 0 failed

```
PASS  the program opens (sign-in screen)  [window found]
PASS  this computer registers with the website (machine id and MAC from Windows)  [backend register hwid=yes mac=no]
PASS  the program opens full screen (no title bar, taskbar behind it)  [(0, 0, 1920, 1080) screen 1920x1080 title bar=False top=app bottom=app]
PASS  F11 gives a maximised window with its title bar  [(-8, -8, 1928, 1048) maximised=True title bar=True]
PASS  sign in with the keyboard opens the home screen
PASS  Live TV shows categories and channels  [browse live items=4]
PASS  channel 1 plays full screen (.ts stream)  [ready index=0 format=ts video=1920x1080, position 10s]
PASS  video picture is decoded  [ready index=0 format=ts video=1920x1080]
PASS  the video covers the whole screen (also when a window was chosen)  [(0, 0, 1920, 1080) screen 1920x1080 title bar=False top=app bottom=app]
PASS  the log says how the video is decoded, and it plays on after that check  [processor format=h264 fps=25.000000 interlaced=yes, deinterlaced; position 10s -> 15s]
PASS  the 1080i channel is deinterlaced  [processor format=h264 fps=25.000000 interlaced=yes, deinterlaced]
PASS  Esc goes back (the program stays open)
PASS  after the video the window comes back  [(-8, -8, 1928, 1048) maximised=True title bar=True]
PASS  F11 makes it full screen again  [(0, 0, 1920, 1080) screen 1920x1080 title bar=False top=app bottom=app]
PASS  Esc on the home screen asks before closing
```
