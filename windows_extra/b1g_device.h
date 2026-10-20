// Windows side of the app's "b1g/device" channel (the Android side is MainActivity.kt).
// Copied into windows/runner/ by tools/windows_setup.py when the Windows build creates its project.
#ifndef RUNNER_B1G_DEVICE_H_
#define RUNNER_B1G_DEVICE_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

namespace b1g_device {

// Answers the app's questions about this computer (ids for the website, network, Wi-Fi, memory)
// and does what it asks of the window (full screen, keep the screen on, open a web page).
void Register(flutter::BinaryMessenger* messenger, HWND window);

// Shows the window for the first time. Like a TV app it covers the whole screen (no title bar,
// no taskbar) unless the viewer switched to a window with F11 last time; then it returns false
// and the window opens maximised as before.
bool ShowFullScreen();

}  // namespace b1g_device

#endif  // RUNNER_B1G_DEVICE_H_
